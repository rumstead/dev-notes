# Distributed Systems Coding Interview Prep

> **Format**: CoderPad, pair-programming style. Write, evaluate, and troubleshoot production-grade distributed systems code.

---

## What They're Assessing

1. **Can you write clean, correct concurrent code under pressure?**
2. **Do you handle failure modes (timeouts, retries, partial failures)?**
3. **Can you read existing code and spot bugs / race conditions / design flaws?**
4. **Do you think about production concerns (observability, graceful shutdown, resource cleanup)?**

---

## Phase 1: Writing Code — Patterns You Must Nail

### 1. Worker Pool with Graceful Shutdown

This is the #1 most common distributed systems coding question. You already have notes on this — make sure you can write it **from scratch in under 5 minutes**.

```go
func workerPool(ctx context.Context, jobs <-chan Job, numWorkers int) <-chan Result {
    results := make(chan Result, numWorkers)
    var wg sync.WaitGroup

    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            for {
                select {
                case job, ok := <-jobs:
                    if !ok {
                        return // channel closed, drain complete
                    }
                    results <- process(ctx, job)
                case <-ctx.Done():
                    return // context cancelled, shutdown
                }
            }
        }(i)
    }

    go func() {
        wg.Wait()
        close(results)
    }()

    return results
}
```

**Key talking points**:
- Why buffered vs unbuffered channels matter here
- What happens if you don't check `ok` on the channel receive
- Why `defer wg.Done()` and not `wg.Done()` at the end
- The goroutine that waits and closes results — why it must be separate

### 2. Retry with Exponential Backoff + Jitter

```go
func retryWithBackoff(ctx context.Context, maxRetries int, fn func() error) error {
    var err error
    for attempt := 0; attempt <= maxRetries; attempt++ {
        err = fn()
        if err == nil {
            return nil
        }

        if attempt == maxRetries {
            break
        }

        // Exponential backoff: 100ms, 200ms, 400ms, 800ms...
        backoff := time.Duration(1<<uint(attempt)) * 100 * time.Millisecond

        // Add jitter (0-50% of backoff)
        jitter := time.Duration(rand.Int63n(int64(backoff / 2)))
        wait := backoff + jitter

        select {
        case <-time.After(wait):
            // continue to next attempt
        case <-ctx.Done():
            return fmt.Errorf("context cancelled during retry: %w", ctx.Err())
        }
    }
    return fmt.Errorf("max retries (%d) exceeded: %w", maxRetries, err)
}
```

**Key talking points**:
- Why jitter matters (thundering herd)
- Why you check ctx.Done() during the wait (not just before the call)
  - When to use `time.After` vs `time.NewTimer` (timer leak in long-running loops)
- Consider: should some errors be non-retryable? (classify errors)

### 3. Rate Limiter (Token Bucket)

```go
type RateLimiter struct {
    tokens   chan struct{}
    interval time.Duration
}

func NewRateLimiter(rate int, interval time.Duration) *RateLimiter {
    rl := &RateLimiter{
        tokens:   make(chan struct{}, rate),
        interval: interval,
    }
    // Pre-fill tokens
    for i := 0; i < rate; i++ {
        rl.tokens <- struct{}{}
    }
    // Refill tokens
    go func() {
        ticker := time.NewTicker(interval / time.Duration(rate))
        defer ticker.Stop()
        for range ticker.C {
            select {
            case rl.tokens <- struct{}{}:
            default: // bucket full, discard
            }
        }
    }()
    return rl
}

func (rl *RateLimiter) Wait(ctx context.Context) error {
    select {
    case <-rl.tokens:
        return nil
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

### 4. Fan-Out / Fan-In

```go
func fanOutFanIn(ctx context.Context, urls []string) []Result {
    var wg sync.WaitGroup
    results := make(chan Result, len(urls))

    for _, url := range urls {
        wg.Add(1)
        go func(u string) {
            defer wg.Done()
            res, err := fetchWithTimeout(ctx, u, 5*time.Second)
            results <- Result{URL: u, Data: res, Err: err}
        }(url)
    }

    go func() {
        wg.Wait()
        close(results)
    }()

    var out []Result
    for r := range results {
        out = append(out, r)
    }
    return out
}
```

### 5. Circuit Breaker (simplified)

```go
type CircuitBreaker struct {
    mu            sync.Mutex
    failures      int
    threshold     int
    state         string // "closed", "open", "half-open"
    lastFailure   time.Time
    resetTimeout  time.Duration
}

func (cb *CircuitBreaker) Execute(fn func() error) error {
    cb.mu.Lock()
    if cb.state == "open" {
        if time.Since(cb.lastFailure) > cb.resetTimeout {
            cb.state = "half-open"
        } else {
            cb.mu.Unlock()
            return fmt.Errorf("circuit breaker is open")
        }
    }
    cb.mu.Unlock()

    err := fn()

    cb.mu.Lock()
    defer cb.mu.Unlock()

    if err != nil {
        cb.failures++
        cb.lastFailure = time.Now()
        if cb.failures >= cb.threshold {
            cb.state = "open"
        }
        return err
    }

    cb.failures = 0
    cb.state = "closed"
    return nil
}
```

---

## Phase 2: Troubleshooting — Common Bugs to Spot

### Bug 1: Goroutine Leak (missing context check)

```go
// BUGGY
func fetchAll(urls []string) []string {
    results := make(chan string)
    for _, url := range urls {
        go func(u string) {
            resp, _ := http.Get(u) // no timeout, no context
            body, _ := io.ReadAll(resp.Body)
            results <- string(body) // blocks forever if nobody reads
        }(u)
    }
    // If caller only reads some results, remaining goroutines leak
    var out []string
    for i := 0; i < len(urls); i++ {
        out = append(out, <-results)
    }
    return out
}
```

**Issues to call out**:
- No context / no timeout on HTTP calls
- Error handling swallowed
- If any `http.Get` fails with nil resp, you get a nil pointer dereference
- `resp.Body` is never closed — resource leak
- If this function is abandoned early, goroutines hang on `results <-`

### Bug 2: Race Condition on Shared State

```go
// BUGGY — data race
type Counter struct {
    count int
}

func (c *Counter) Increment() { c.count++ }
func (c *Counter) Get() int   { return c.count }

// Fix: use sync.Mutex or atomic.Int64
```

### Bug 3: Channel Deadlock

```go
// BUGGY — deadlock
func main() {
    ch := make(chan int) // unbuffered
    ch <- 42             // blocks forever, no receiver yet
    fmt.Println(<-ch)
}
```

### Bug 4: Improper Select Priority

```go
// BUGGY — ctx.Done() may never be selected under load
for {
    select {
    case job := <-jobs:
        process(job)
    case <-ctx.Done():
        return
    }
}
// If jobs channel is always ready, Go's select is random,
// so ctx.Done() WILL eventually fire, but consider:
// explicitly checking ctx.Err() inside the job case for faster response
```

### Bug 5: Close of Closed Channel (panic)

```go
// BUGGY — multiple goroutines closing same channel
var once sync.Once
// Fix: use sync.Once to close, or have only one goroutine own closing
once.Do(func() { close(ch) })
```

---

## Phase 3: Production Concerns — What to Mention Proactively

These separate good from great candidates:

1. **Observability**: "I'd add metrics here — request count, latency histogram, error rate"
2. **Graceful shutdown**: "On SIGTERM, stop accepting new work, drain in-flight, then exit"
3. **Health checks**: "Liveness vs readiness — if the worker pool is saturated, fail readiness"
4. **Resource limits**: "Bound the channel/queue size to apply backpressure"
5. **Error classification**: "Distinguish transient vs permanent errors for retry logic"
6. **Idempotency**: "If this operation retries, is it safe to run twice?"
7. **Timeouts everywhere**: "Every external call needs a timeout. No unbounded waits."
8. **Structured logging**: "Log with correlation IDs, not just messages"

---

## Phase 4: Likely Problem Scenarios

Based on the job description (distributed systems, production-grade), expect one of these:

### Scenario A: Build a Task Queue / Job Processor
- Produce jobs, consume with worker pool
- Handle failures, retries, dead-letter
- Graceful shutdown on signal
- **You already know this pattern** — see your worker pool notes

### Scenario B: Build an HTTP Proxy / Load Balancer
- Forward requests to backends
- Health check backends
- Circuit break unhealthy ones
- Handle timeouts, connection pooling

### Scenario C: Implement a Cache with TTL + Eviction
```go
type Cache struct {
    mu      sync.RWMutex
    items   map[string]cacheItem
    ttl     time.Duration
}

type cacheItem struct {
    value     interface{}
    expiresAt time.Time
}

func (c *Cache) Get(key string) (interface{}, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    item, ok := c.items[key]
    if !ok || time.Now().After(item.expiresAt) {
        return nil, false
    }
    return item.value, true
}

func (c *Cache) Set(key string, value interface{}) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = cacheItem{value: value, expiresAt: time.Now().Add(c.ttl)}
}
```
- Discuss: lazy vs active eviction, LRU, memory bounds

### Scenario D: Debug a Flaky Distributed Service
- Given code with subtle bugs (race conditions, goroutine leaks, missing error handling)
- Find and fix them
- Explain what would happen in production

### Scenario E: Implement Leader Election / Distributed Lock
- Using a backing store (etcd, Redis)
- Handle lease renewal, fencing tokens
- What happens on network partition?

---

## Quick Reference: Go Concurrency Primitives

| Primitive | When to Use |
|---|---|
| `sync.Mutex` | Protect shared state, short critical sections |
| `sync.RWMutex` | Many readers, few writers |
| `sync.WaitGroup` | Wait for N goroutines to complete |
| `sync.Once` | One-time initialization (or one-time close) |
| `sync.Map` | Highly concurrent map with append-only or stable keys |
| `atomic.*` | Simple counters, flags |
| `chan` | Communication between goroutines |
| `context.Context` | Cancellation, timeouts, request-scoped values |
| `errgroup.Group` | WaitGroup + first error propagation + context cancel |
| `semaphore.Weighted` | Limit concurrent access to a resource |

---

## Interview Execution Checklist

Before coding:
- [ ] **Clarify requirements** — "Should this handle partial failures?" "What's the expected throughput?"
- [ ] **State assumptions** — "I'll assume Go, single-process for now"
- [ ] **Outline approach** — "I'll start with the data structures, then the main loop, then error handling"

While coding:
- [ ] **Narrate your thinking** — "I'm using a buffered channel here because..."
- [ ] **Handle errors explicitly** — never swallow `err`
- [ ] **Use context for cancellation** — every long operation
- [ ] **Close resources** — channels, HTTP bodies, files
- [ ] **Name things well** — even in an interview

After coding:
- [ ] **Walk through a happy path**
- [ ] **Walk through a failure path** — "What if this call times out?"
- [ ] **Mention what you'd add in production** — metrics, logging, tests
- [ ] **Discuss testing strategy** — "I'd test this with a mock that returns errors to verify retry behavior"

---

## Common Mistakes to Avoid

- **Don't jump into code immediately** — spend 2-3 min understanding the problem
- **Don't ignore error returns** — this is the #1 red flag in Go interviews
- **Don't forget `defer cancel()`** after creating a context
- **Don't use `time.After` in a hot loop** — it leaks timers, use `time.NewTimer` + `Reset()`
- **Don't close channels from the receiver side** — only the sender should close
- **Don't mix sync primitives and channels unnecessarily** — pick one model
- **Don't forget to handle the "zero value" case** — what if the map is nil? the slice is empty?
