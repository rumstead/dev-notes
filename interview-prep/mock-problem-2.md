# Mock Interview 2: Health-Checked Load Balancer

> Timer: 45 minutes. Different skills from Mock 1 — HTTP, state machines, concurrent reads/writes.

---

## PART 1: Build (25-30 min)

### Problem Statement

> "Build an HTTP reverse proxy that distributes requests across a set of backends.
> The proxy should:
>
> 1. Health check backends periodically (e.g., every 10 seconds)
> 2. Only route to healthy backends
> 3. Use round-robin selection among healthy backends
> 4. Return 503 if no healthy backends are available
> 5. Support adding/removing backends at runtime via an admin API"

---

### Step 1: Clarify (say these out loud)

- "For health checks — should I hit a specific path like `/healthz`, or just TCP connect?"
    - Good default: HTTP GET to `/healthz`, 200 = healthy
- "How many consecutive failures before marking unhealthy? And how many successes to recover?"
    - Good default: 3 failures → unhealthy, 1 success → healthy
- "Should the proxy stream the response or buffer it?"
    - Use `httputil.ReverseProxy` — it streams by default
- "What timeout for health checks vs proxied requests?"
    - Health check: 2s, Proxy: 30s
- "Round-robin — strict ordering or approximate is fine?"
    - Approximate (atomic counter mod N) is fine for an interview

### Step 2: Outline

```
Types:
  - Backend{URL, Healthy, FailCount, mu}
  - LoadBalancer{backends, mu, current(atomic), healthInterval}

Components:
  - Health checker — goroutine per backend, periodic HTTP GET
  - Router — round-robin over healthy backends
  - Admin API — POST/DELETE /backends
  - Proxy handler — forward request to selected backend

State transitions:
  healthy ---(3 consecutive failures)---> unhealthy
  unhealthy ---(1 success)---> healthy
```

### Step 3: Code

```go
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"sync"
	"sync/atomic"
	"time"
)

// --- Backend ---

type Backend struct {
	URL           *url.URL
	Alive         bool
	FailCount     int
	FailThreshold int
	mu            sync.RWMutex
	proxy         *httputil.ReverseProxy
}

func NewBackend(rawURL string, failThreshold int) (*Backend, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	b := &Backend{
		URL:           u,
		Alive:         true, // optimistic — assume healthy until proven otherwise
		FailThreshold: failThreshold,
	}
	b.proxy = httputil.NewSingleHostReverseProxy(u)

	// Custom error handler — mark backend unhealthy on proxy failure
	b.proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("proxy error to %s: %v", u.Host, err)
		b.SetAlive(false)
		http.Error(w, "bad gateway", http.StatusBadGateway)
	}
	return b, nil
}

func (b *Backend) IsAlive() bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.Alive
}

func (b *Backend) SetAlive(alive bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if alive {
		b.FailCount = 0
		if !b.Alive {
			log.Printf("backend %s is now healthy", b.URL.Host)
		}
		b.Alive = true
	} else {
		b.FailCount++
		if b.FailCount >= b.FailThreshold {
			if b.Alive {
				log.Printf("backend %s is now unhealthy (failures: %d)", b.URL.Host, b.FailCount)
			}
			b.Alive = false
		}
	}
}

func (b *Backend) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	b.proxy.ServeHTTP(w, r)
}

// --- Load Balancer ---

type LoadBalancer struct {
	backends []*Backend
	mu       sync.RWMutex
	current  atomic.Uint64
}

func NewLoadBalancer() *LoadBalancer {
	return &LoadBalancer{}
}

func (lb *LoadBalancer) AddBackend(b *Backend) {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	lb.backends = append(lb.backends, b)
}

func (lb *LoadBalancer) RemoveBackend(host string) bool {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	for i, b := range lb.backends {
		if b.URL.Host == host {
			lb.backends = append(lb.backends[:i], lb.backends[i+1:]...)
			return true
		}
	}
	return false
}

// NextHealthy returns the next healthy backend using round-robin.
func (lb *LoadBalancer) NextHealthy() *Backend {
	lb.mu.RLock()
	defer lb.mu.RUnlock()

	n := len(lb.backends)
	if n == 0 {
		return nil
	}

	// Try all backends starting from current position
	start := int(lb.current.Add(1))
	for i := 0; i < n; i++ {
		idx := (start + i) % n
		if lb.backends[idx].IsAlive() {
			return lb.backends[idx]
		}
	}
	return nil // no healthy backends
}

// ServeHTTP is the main proxy handler
func (lb *LoadBalancer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	backend := lb.NextHealthy()
	if backend == nil {
		http.Error(w, "no healthy backends", http.StatusServiceUnavailable)
		return
	}
	backend.ServeHTTP(w, r)
}

// --- Health Checker ---

func (lb *LoadBalancer) HealthCheck(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	client := &http.Client{Timeout: 2 * time.Second}

	for {
		select {
		case <-ticker.C:
			lb.mu.RLock()
			backends := make([]*Backend, len(lb.backends))
			copy(backends, lb.backends) // snapshot to avoid holding lock during HTTP calls
			lb.mu.RUnlock()

			var wg sync.WaitGroup
			for _, b := range backends {
				wg.Add(1)
				go func(backend *Backend) {
					defer wg.Done()
					checkURL := fmt.Sprintf("%s/healthz", backend.URL.String())
					req, err := http.NewRequestWithContext(ctx, http.MethodGet, checkURL, nil)
					if err != nil {
						backend.SetAlive(false)
						return
					}
					resp, err := client.Do(req)
					if err != nil {
						backend.SetAlive(false)
						return
					}
					defer resp.Body.Close()
					backend.SetAlive(resp.StatusCode == http.StatusOK)
				}(b)
			}
			wg.Wait()

		case <-ctx.Done():
			return
		}
	}
}

// --- Admin API ---

func (lb *LoadBalancer) AdminHandler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /backends", func(w http.ResponseWriter, r *http.Request) {
		var req struct{ URL string }
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		b, err := NewBackend(req.URL, 3)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		lb.AddBackend(b)
		w.WriteHeader(http.StatusCreated)
	})

	mux.HandleFunc("DELETE /backends", func(w http.ResponseWriter, r *http.Request) {
		host := r.URL.Query().Get("host")
		if !lb.RemoveBackend(host) {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})

	mux.HandleFunc("GET /backends", func(w http.ResponseWriter, r *http.Request) {
		lb.mu.RLock()
		defer lb.mu.RUnlock()

		type status struct {
			URL   string `json:"url"`
			Alive bool   `json:"alive"`
		}
		var out []status
		for _, b := range lb.backends {
			out = append(out, status{URL: b.URL.String(), Alive: b.IsAlive()})
		}
		json.NewEncoder(w).Encode(out)
	})

	return mux
}

// --- Main ---

func main() {
	lb := NewLoadBalancer()

	// Add initial backends
	for _, rawURL := range []string{
		"http://backend-1:8080",
		"http://backend-2:8080",
		"http://backend-3:8080",
	} {
		b, err := NewBackend(rawURL, 3)
		if err != nil {
			log.Fatal(err)
		}
		lb.AddBackend(b)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go lb.HealthCheck(ctx, 10*time.Second)

	// Proxy on :8080, admin on :9090
	go func() {
		log.Println("admin API on :9090")
		log.Fatal(http.ListenAndServe(":9090", lb.AdminHandler()))
	}()

	log.Println("proxy on :8080")
	log.Fatal(http.ListenAndServe(":8080", lb))
}
```

### Step 4: Talking Points

- **Why `RWMutex`?** Reads (every proxied request) vastly outnumber writes (add/remove backend). `RLock` allows
  concurrent request routing.
- **Why snapshot the backends slice before health checking?** Holding `RLock` during HTTP calls would block
  `AddBackend`/`RemoveBackend` for seconds.
- **Why `atomic.Uint64` for round-robin?** Avoids taking a lock on every request just to increment a counter.
- **Why `ErrorHandler` on the proxy?** Default behavior writes a generic error. Custom handler lets us mark the backend
  unhealthy on proxy failure (fast path, don't wait for next health check).
- **Why optimistic start (Alive=true)?** New backends serve traffic immediately. The health check will correct within
  one interval if they're actually down.

### Step 5: Production Additions

- **Weighted round-robin** — backends with different capacities
- **Connection draining** — when removing a backend, finish in-flight requests before dropping
- **Request hedging** — if backend is slow, send duplicate to another and use first response
- **Metrics** — requests per backend, latency histogram, health check failures, 503 rate
- **Circuit breaker** — if a backend fails N proxied requests, stop sending immediately (don't wait for health check)
- **Sticky sessions** — hash client IP or header to consistent backend

---

## PART 2: Troubleshoot (15-20 min)

### Problem Statement

> "This service discovery client maintains a local cache of service endpoints.
> It watches a remote registry for changes and updates the cache. In production
> we're seeing:
> - Stale endpoints being returned long after services are deregistered
> - Occasional concurrent map write panics
> - Memory usage growing over time
>
> Find and fix the bugs."

### The Buggy Code

```go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Endpoint struct {
	Host string
	Port int
}

type ServiceCache struct {
	services map[string][]Endpoint
	ttls     map[string]time.Time
}

func NewServiceCache() *ServiceCache {
	return &ServiceCache{
		services: make(map[string][]Endpoint),
		ttls:     make(map[string]time.Time),
	}
}

func (sc *ServiceCache) Get(name string) []Endpoint {
	return sc.services[name]
}

func (sc *ServiceCache) Set(name string, endpoints []Endpoint, ttl time.Duration) {
	sc.services[name] = endpoints
	sc.ttls[name] = time.Now().Add(ttl)
}

func (sc *ServiceCache) Watch(registryURL string) {
	for {
		resp, err := http.Get(registryURL + "/services")
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}

		var updates map[string][]Endpoint
		json.NewDecoder(resp.Body).Decode(&updates)

		for name, endpoints := range updates {
			sc.Set(name, endpoints, 30*time.Second)
		}

		time.Sleep(10 * time.Second)
	}
}

func (sc *ServiceCache) evictExpired() {
	for {
		time.Sleep(5 * time.Second)
		now := time.Now()
		for name, expiry := range sc.ttls {
			if now.After(expiry) {
				delete(sc.services, name)
				delete(sc.ttls, name)
			}
		}
	}
}

func (sc *ServiceCache) Handler(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("service")
	endpoints := sc.Get(name)
	if len(endpoints) == 0 {
		http.Error(w, "service not found", http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(endpoints)
}

func main() {
	cache := NewServiceCache()

	go cache.Watch("http://registry:8080")
	go cache.evictExpired()

	http.HandleFunc("/lookup", cache.Handler)
	http.ListenAndServe(":8080", nil)
}
```

---

### Bugs — find them yourself first, then expand

<details>
<summary>Bug 1: Concurrent map read/write panic (critical)</summary>

**Problem**: Three goroutines access `sc.services` and `sc.ttls` concurrently with no synchronization:

- `Watch()` writes via `Set()`
- `evictExpired()` reads and deletes
- HTTP handler reads via `Get()`

Go maps are **not safe for concurrent use**. This will panic with `concurrent map read and map write` or
`concurrent map writes`.

**Fix**: Add `sync.RWMutex`. `RLock` for `Get`, `Lock` for `Set` and `evictExpired`.

</details>

<details>
<summary>Bug 2: Stale endpoints — eviction doesn't work properly</summary>

**Problem**: `Watch()` refreshes every 10 seconds with a 30-second TTL. But it only processes services that the *
*registry returns**. If a service is **deregistered** (removed from registry), it simply stops appearing in the
response. `Watch` never removes it — it just stops refreshing its TTL. The entry sits in cache until `evictExpired` runs
after the TTL.

But here's the real issue: `evictExpired` deletes from `sc.services` and `sc.ttls`, yet `Watch` could immediately re-add
a stale entry if there's a race. And if the registry is slow or errors out, the `Watch` sleeps 5s and retries — during
which the old TTL could expire, the entry gets evicted, but then `Watch` succeeds and re-adds it from a stale response.

**Fix**: When `Watch` receives an update, treat it as the **full set** of services. Delete any cached service that's NOT
in the update response. This is a **reconciliation** pattern (same concept as Kubernetes controllers).

</details>

<details>
<summary>Bug 3: resp.Body never closed — memory leak</summary>

**Problem**: `Watch()` calls `http.Get` in a loop but never closes `resp.Body`. Each response body holds an open TCP
connection and buffered data. Over time, this exhausts connections and grows memory.

**Fix**: `defer resp.Body.Close()` — but since this is in a loop, use an inline function or explicit close before the
next iteration.

```go
resp, err := http.Get(...)
if err != nil { ... }
func () {
defer resp.Body.Close()
// decode here
}()
```

Or simply: `resp.Body.Close()` after decoding.

</details>

<details>
<summary>Bug 4: Decode error silently ignored</summary>

**Problem**: `json.NewDecoder(resp.Body).Decode(&updates)` — if decode fails, `updates` is nil. The `for range` over nil
map does nothing — so a bad response silently skips the update cycle. No logging, no error tracking.

**Fix**: Check the error. Log it. Consider whether to keep the old cache or clear it.

</details>

<details>
<summary>Bug 5: No context / no timeout on HTTP calls</summary>

**Problem**: `http.Get` has no timeout. If the registry hangs, `Watch` blocks indefinitely — no health checks, no TTL
refreshes, stale data served until eviction.

**Fix**: Use `http.Client{Timeout: 10 * time.Second}` and pass a context for cancellation on shutdown.

</details>

<details>
<summary>Bug 6: Deleting from map while iterating</summary>

**Problem**: In `evictExpired`:

```go
for name, expiry := range sc.ttls {
if now.After(expiry) {
delete(sc.services, name)
delete(sc.ttls, name) // deleting from map being iterated
}
}
```

In Go, deleting from a map during `range` is actually **safe** — this is explicitly allowed by the spec. So this is a
trick question / NOT a bug. But it's worth mentioning you know this, as many candidates incorrectly flag it.

</details>

<details>
<summary>Bug 7: No graceful shutdown</summary>

**Problem**: `Watch` and `evictExpired` run forever with no way to stop them. No context, no done channel. If the main
HTTP server shuts down, these goroutines keep running and making requests to the registry.

**Fix**: Pass `context.Context` to both, check `ctx.Done()` in the loop.

</details>

---

### The Fixed Version (reference)

```go
type ServiceCache struct {
services map[string][]Endpoint
ttls     map[string]time.Time
mu       sync.RWMutex
}

func (sc *ServiceCache) Get(name string) []Endpoint {
sc.mu.RLock()
defer sc.mu.RUnlock()
eps := sc.services[name]
// Return a copy to avoid races on the slice
out := make([]Endpoint, len(eps))
copy(out, eps)
return out
}

func (sc *ServiceCache) Watch(ctx context.Context, registryURL string) {
client := &http.Client{Timeout: 10 * time.Second}
ticker := time.NewTicker(10 * time.Second)
defer ticker.Stop()

fetch := func () {
req, err := http.NewRequestWithContext(ctx, http.MethodGet, registryURL+"/services", nil)
if err != nil {
log.Printf("watch: request error: %v", err)
return
}
resp, err := client.Do(req)
if err != nil {
log.Printf("watch: fetch error: %v", err)
return
}
defer resp.Body.Close()

var updates map[string][]Endpoint
if err := json.NewDecoder(resp.Body).Decode(&updates); err != nil {
log.Printf("watch: decode error: %v", err)
return
}

sc.mu.Lock()
defer sc.mu.Unlock()

// Reconcile: add/update what's in the response
for name, endpoints := range updates {
sc.services[name] = endpoints
sc.ttls[name] = time.Now().Add(30 * time.Second)
}

// Remove anything NOT in the response (deregistered)
for name := range sc.services {
if _, exists := updates[name]; !exists {
delete(sc.services, name)
delete(sc.ttls, name)
}
}
}

fetch() // initial fetch
for {
select {
case <-ticker.C:
fetch()
case <-ctx.Done():
return
}
}
}
```

---

## How This Tests Different Skills Than Mock 1

| Skill           | Mock 1 (Task Processor) | Mock 2 (Load Balancer)     |
|-----------------|-------------------------|----------------------------|
| Channels        | Primary mechanism       | Not used                   |
| Mutexes (RW)    | Not used                | Primary mechanism          |
| HTTP server     | Not involved            | Core of the solution       |
| HTTP client     | Not involved            | Health checks + proxy      |
| State machine   | Simple (retry count)    | Backend health transitions |
| Data structures | Queue (channel)         | Map + round-robin index    |
| Concurrency bug | Goroutine leak          | Map race + stale data      |
