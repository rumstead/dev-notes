# Mock Interview: Distributed Task Processor

> Simulate this as a timed exercise. Set a timer for 45 minutes total.
> Read the prompt, spend 3-5 min clarifying, then code.

---

## PART 1: Build (25-30 min)

### Problem Statement (what the interviewer says)

> "We have a system that processes tasks from an in-memory queue. Tasks can fail
> transiently (e.g., downstream service is temporarily unavailable) or permanently
> (e.g., bad input). We need you to build a task processor in Go that:
>
> 1. Accepts tasks into a queue
> 2. Processes them concurrently with a configurable number of workers
> 3. Retries transient failures with exponential backoff
> 4. Moves permanently failed tasks to a dead-letter queue
> 5. Shuts down gracefully when signaled"

---

### Step 1: Clarify (say these out loud)

Good questions to ask:

- "How do we distinguish transient vs permanent errors? Should I define an error interface, or is there a status code?"
- "Is there a max retry count? What's a reasonable default — 3?"
- "Should backoff have a cap? I'll cap at ~30 seconds to avoid unbounded waits."
- "For graceful shutdown — should in-flight tasks complete, or should we abandon them?"
  - **Best answer**: "In-flight should complete, but new tasks should stop being accepted."
- "Is ordering important? I'll assume no for a worker pool."
- "Should I handle duplicate tasks / idempotency, or is that out of scope?"

### Step 2: Outline (sketch on screen or say aloud)

```
Types:
  - Task{ID, Payload, Retries, MaxRetries}
  - Result — success or dead-lettered
  - TransientError / PermanentError

Components:
  - TaskQueue (buffered channel)
  - DeadLetterQueue (buffered channel or slice)
  - WorkerPool — N goroutines reading from TaskQueue
  - Processor — the business logic (injected/mockable)
  - Coordinator — ties it together, handles shutdown

Flow:
  Submit -> TaskQueue -> Worker picks up -> Process
    -> success: done
    -> transient error + retries left: backoff, re-enqueue
    -> transient error + no retries: dead-letter
    -> permanent error: dead-letter immediately
```

### Step 3: Code

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"sync"
	"time"
)

// --- Error types ---

type TransientError struct {
	Err error
}

func (e *TransientError) Error() string { return fmt.Sprintf("transient: %v", e.Err) }
func (e *TransientError) Unwrap() error { return e.Err }

type PermanentError struct {
	Err error
}

func (e *PermanentError) Error() string { return fmt.Sprintf("permanent: %v", e.Err) }
func (e *PermanentError) Unwrap() error { return e.Err }

// --- Task ---

type Task struct {
	ID         string
	Payload    string
	Attempts   int
	MaxRetries int
}

// --- Processor interface (makes it testable) ---

type Processor interface {
	Process(ctx context.Context, task Task) error
}

// --- TaskProcessor (the coordinator) ---

type TaskProcessor struct {
	queue      chan Task
	dlq        chan Task
	processor  Processor
	workers    int
	wg         sync.WaitGroup
}

func NewTaskProcessor(processor Processor, workers, queueSize int) *TaskProcessor {
	return &TaskProcessor{
		queue:     make(chan Task, queueSize),
		dlq:       make(chan Task, queueSize),
		processor: processor,
		workers:   workers,
	}
}

func (tp *TaskProcessor) Submit(task Task) bool {
	select {
	case tp.queue <- task:
		return true
	default:
		return false // queue full — apply backpressure
	}
}

func (tp *TaskProcessor) Start(ctx context.Context) {
	for i := 0; i < tp.workers; i++ {
		tp.wg.Add(1)
		go tp.worker(ctx, i)
	}
}

func (tp *TaskProcessor) worker(ctx context.Context, id int) {
	defer tp.wg.Done()

	for {
		select {
		case task, ok := <-tp.queue:
			if !ok {
				return // queue closed, shutdown
			}
			tp.handleTask(ctx, task)
		case <-ctx.Done():
			// Drain remaining tasks in queue before exiting
			for {
				select {
				case task, ok := <-tp.queue:
					if !ok {
						return
					}
					tp.handleTask(context.Background(), task)
				default:
					return
				}
			}
		}
	}
}

func (tp *TaskProcessor) handleTask(ctx context.Context, task Task) {
	task.Attempts++
	err := tp.processor.Process(ctx, task)

	if err == nil {
		fmt.Printf("[task=%s] completed on attempt %d\n", task.ID, task.Attempts)
		return
	}

	var permErr *PermanentError
	if errors.As(err, &permErr) {
		fmt.Printf("[task=%s] permanent failure: %v -> DLQ\n", task.ID, err)
		tp.sendToDLQ(task)
		return
	}

	var transErr *TransientError
	if errors.As(err, &transErr) {
		if task.Attempts > task.MaxRetries {
			fmt.Printf("[task=%s] max retries exceeded -> DLQ\n", task.ID)
			tp.sendToDLQ(task)
			return
		}

		// Exponential backoff with jitter
		backoff := time.Duration(1<<uint(task.Attempts-1)) * 100 * time.Millisecond
		jitter := time.Duration(rand.Int63n(int64(backoff / 2)))
		wait := backoff + jitter

		// Cap backoff
		if wait > 30*time.Second {
			wait = 30 * time.Second
		}

		fmt.Printf("[task=%s] transient failure (attempt %d/%d), retrying in %v\n",
			task.ID, task.Attempts, task.MaxRetries, wait)

		select {
		case <-time.After(wait):
			// Re-enqueue for retry
			select {
			case tp.queue <- task:
			default:
				fmt.Printf("[task=%s] queue full during retry -> DLQ\n", task.ID)
				tp.sendToDLQ(task)
			}
		case <-ctx.Done():
			// Shutting down during backoff — re-enqueue without waiting
			select {
			case tp.queue <- task:
			default:
				tp.sendToDLQ(task)
			}
		}
		return
	}

	// Unknown error type — treat as permanent
	fmt.Printf("[task=%s] unknown error type: %v -> DLQ\n", task.ID, err)
	tp.sendToDLQ(task)
}

func (tp *TaskProcessor) sendToDLQ(task Task) {
	select {
	case tp.dlq <- task:
	default:
		fmt.Printf("[task=%s] WARNING: DLQ full, task dropped\n", task.ID)
	}
}

// Shutdown stops accepting new tasks, waits for in-flight to complete
func (tp *TaskProcessor) Shutdown() {
	close(tp.queue)
	tp.wg.Wait()
	close(tp.dlq)
}

func (tp *TaskProcessor) DeadLetters() <-chan Task {
	return tp.dlq
}
```

### Step 4: Walk Through (say this to interviewer)

**Happy path**: "Submit a task, worker picks it up, Process succeeds, done."

**Transient failure path**: "Process returns TransientError. We increment attempts, calculate backoff with jitter so multiple retrying tasks don't stampede, re-enqueue. If attempts exceed MaxRetries, it goes to the DLQ."

**Permanent failure path**: "Process returns PermanentError. Immediately goes to DLQ, no retry."

**Shutdown path**: "Context is cancelled. Workers see ctx.Done(), drain any remaining tasks from the queue (using background context so they can complete), then exit. WaitGroup ensures Shutdown blocks until all workers finish."

**Backpressure**: "Submit uses a non-blocking send. If the queue is full, it returns false — the caller decides what to do (reject, drop, buffer externally)."

### Step 5: What I'd Add in Production

- **Metrics**: tasks_processed_total, tasks_failed_total (by error type), task_duration_seconds histogram, dlq_size gauge, queue_depth gauge
- **Structured logging**: replace fmt.Printf with slog, include task ID as a field
- **Persistent queue**: replace in-memory channel with Redis/Kafka/SQS for durability
- **DLQ consumer**: separate process to inspect/replay dead-lettered tasks
- **Tests**: mock Processor that returns errors on specific attempts, verify retry count, verify DLQ routing
- **Health check**: expose readiness based on queue depth / worker liveness

---

## PART 2: Troubleshoot (15-20 min)

### Problem Statement

> "A colleague wrote this service that aggregates pricing data from multiple
> upstream APIs. It's been running in production but we're seeing:
> - Goroutine count growing unboundedly over time
> - Occasional panics
> - Some requests returning stale data
>
> Find and fix the bugs."

### The Buggy Code

```go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

type PriceCache struct {
	prices map[string]float64
	mu     sync.Mutex
}

var cache = &PriceCache{
	prices: make(map[string]float64),
}

var upstreams = []string{
	"http://pricing-a:8080/price",
	"http://pricing-b:8080/price",
	"http://pricing-c:8080/price",
}

func fetchPrice(url string, product string) (float64, error) {
	resp, err := http.Get(fmt.Sprintf("%s?product=%s", url, product))
	if err != nil {
		return 0, err
	}
	var result struct{ Price float64 }
	json.NewDecoder(resp.Body).Decode(&result)
	return result.Price, nil
}

func getBestPrice(product string) float64 {
	// Check cache first
	cache.mu.Lock()
	if price, ok := cache.prices[product]; ok {
		cache.mu.Unlock()
		return price
	}
	cache.mu.Unlock()

	results := make(chan float64)

	for _, url := range upstreams {
		go func() {
			price, err := fetchPrice(url, product)
			if err == nil {
				results <- price
			}
		}()
	}

	best := <-results

	for i := 1; i < len(upstreams); i++ {
		price := <-results
		if price < best {
			best = price
		}
	}

	cache.mu.Lock()
	cache.prices[product] = best
	cache.mu.Unlock()

	return best
}

func refreshCache() {
	for {
		time.Sleep(5 * time.Minute)
		cache.mu.Lock()
		cache.prices = make(map[string]float64)
		cache.mu.Unlock()
	}
}

func handler(w http.ResponseWriter, r *http.Request) {
	product := r.URL.Query().Get("product")
	price := getBestPrice(product)
	fmt.Fprintf(w, `{"product": "%s", "price": %.2f}`, product, price)
}

func main() {
	go refreshCache()
	http.HandleFunc("/best-price", handler)
	http.ListenAndServe(":8080", nil)
}
```

---

### Bugs to Find (try to find them yourself first, then check below)

<details>
<summary>Bug 1: Goroutine leak (the big one)</summary>

**Location**: `getBestPrice` — the goroutines launched for each upstream.

**Problem**: If any upstream returns an error, that goroutine doesn't send to `results`. But the main function expects exactly `len(upstreams)` values from `results`. If even one upstream fails, the main goroutine blocks forever on `<-results`.

Worse: if 2 out of 3 succeed and then getBestPrice returns, the 3rd goroutine (still running) will try to send on `results` — but nobody is receiving. That goroutine hangs forever. **This is the goroutine leak.**

**Fix**: Use a buffered channel `results := make(chan float64, len(upstreams))`, collect with a timeout, and handle partial results.

</details>

<details>
<summary>Bug 2: Loop variable capture</summary>

**Location**: `go func() { fetchPrice(url, product) }` — `url` is captured by reference.

**Problem**: All goroutines will use the **last value** of `url` from the loop. All three requests go to the same upstream.

**Fix**: `go func(u string) { ... }(url)` — pass as parameter.

**Note**: This was fixed in Go 1.22+ with the loop variable change, so mention you know about the change but would still be explicit for clarity.

</details>

<details>
<summary>Bug 3: resp.Body never closed</summary>

**Location**: `fetchPrice` — `resp.Body` is never closed.

**Problem**: Each request leaks a TCP connection. Over time, file descriptors are exhausted and new connections fail.

**Fix**: `defer resp.Body.Close()` after the nil check on `err`.

</details>

<details>
<summary>Bug 4: No request timeout</summary>

**Location**: `fetchPrice` — uses `http.Get` which has no timeout.

**Problem**: If an upstream hangs, the goroutine blocks indefinitely. Combined with Bug 1, this means goroutines accumulate.

**Fix**: Use `http.Client{Timeout: 5 * time.Second}` or pass a context with deadline.

</details>

<details>
<summary>Bug 5: Stale data / cache race</summary>

**Location**: `getBestPrice` cache check + `refreshCache`.

**Problem**: The cache check at the top uses `Mutex` (exclusive lock) for a read operation — performance issue but not a bug. The real issue: `refreshCache` clears the entire cache atomically, but between the cache check and the cache write in `getBestPrice`, `refreshCache` could clear the cache, and then the stale price gets written right back.

Also: cache has no TTL per entry. The blunt 5-minute full wipe means brief windows of stale data followed by thundering herd as every request cache-misses simultaneously.

**Fix**: Use `sync.RWMutex` (RLock for reads), add per-entry TTL, or use a proper cache library.

</details>

<details>
<summary>Bug 6: Panic potential</summary>

**Location**: `fetchPrice` — `json.NewDecoder(resp.Body).Decode(&result)` — error is ignored.

**Problem**: If the response is not valid JSON (e.g., an error page, empty body), `result.Price` is `0`. This silently returns `0` as a valid price, which could propagate as the "best" price.

Also: if `resp` is nil (shouldn't happen if err is nil, but defensive coding), this panics.

**Fix**: Check the decode error. Validate that the price is > 0 or within expected bounds.

</details>

<details>
<summary>Bug 7: No input validation</summary>

**Location**: `handler` — `product` could be empty string.

**Problem**: Empty product queries hit all upstreams unnecessarily. Also, the product string is interpolated directly into the URL without escaping — potential injection.

**Fix**: Validate `product` is non-empty, use `url.QueryEscape(product)`.

</details>

---

### The Fixed Version (reference)

```go
func fetchPrice(ctx context.Context, client *http.Client, upstream string, product string) (float64, error) {
	reqURL := fmt.Sprintf("%s?product=%s", upstream, url.QueryEscape(product))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return 0, fmt.Errorf("creating request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("fetching price from %s: %w", upstream, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("unexpected status %d from %s", resp.StatusCode, upstream)
	}

	var result struct{ Price float64 }
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, fmt.Errorf("decoding response from %s: %w", upstream, err)
	}

	if result.Price <= 0 {
		return 0, fmt.Errorf("invalid price %.2f from %s", result.Price, upstream)
	}

	return result.Price, nil
}

func getBestPrice(ctx context.Context, product string) (float64, error) {
	// Check cache (RLock for concurrent reads)
	cache.mu.RLock()
	if price, ok := cache.prices[product]; ok {
		cache.mu.RUnlock()
		return price, nil
	}
	cache.mu.RUnlock()

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	client := &http.Client{Timeout: 5 * time.Second}
	results := make(chan float64, len(upstreams)) // buffered!

	var wg sync.WaitGroup
	for _, u := range upstreams {
		wg.Add(1)
		go func(upstream string) {
			defer wg.Done()
			price, err := fetchPrice(ctx, client, upstream, product)
			if err != nil {
				fmt.Printf("error fetching from %s: %v\n", upstream, err)
				return
			}
			results <- price
		}(u) // pass url as parameter
	}

	// Close results when all fetches complete (prevents leak)
	go func() {
		wg.Wait()
		close(results)
	}()

	var best float64
	found := false
	for price := range results {
		if !found || price < best {
			best = price
			found = true
		}
	}

	if !found {
		return 0, fmt.Errorf("no prices available for %s", product)
	}

	cache.mu.Lock()
	cache.prices[product] = best
	cache.mu.Unlock()

	return best, nil
}
```

---

## How to Practice

1. **Set a 45-min timer** and do Part 1 from scratch in a blank Go file
2. **Print Part 2's buggy code**, read it on paper, and write down every bug before checking answers
3. **Repeat Part 1 with variations**: change it to an HTTP service, add metrics, add a CLI
4. **Practice narrating** — record yourself explaining your decisions for 5 minutes

The #1 differentiator: **talk through failure modes without being prompted**.
