## Channel Creation & Types

### Basic Channel Creation
```go
// Unbuffered (synchronous)
ch := make(chan int)
// Buffered (asynchronous)
ch := make(chan int, 10)        // Buffer size 10

```
### Channel Operations
```go
// Send (blocks if unbuffered and no receiver)
ch <- value

// Receive
value := <-ch               // Blocks until value available
value, ok := <-ch          // ok=false if channel closed

// Check if closed (receive only)
select {
case value, ok := <-ch:
    if !ok {
        // Channel is closed
    }
}

func workerPool(jobs <-chan Job, results chan<- Result, numWorkers int) {
    var wg sync.WaitGroup

    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for job := range jobs {
                results <- processJob(job)
            }
        }()
    }

    go func() {
        wg.Wait()
        close(results)
    }()
}
```
## Context Creation & Usage

### Context Creation
```go
// Background context (never cancelled)
ctx := context.Background()

// TODO context (placeholder)
ctx := context.TODO()

// With timeout
ctx, cancel := context.WithTimeout(parent, 5*time.Second)
defer cancel() // Always call cancel to avoid leaks

// With deadline
deadline := time.Now().Add(10 * time.Second)
ctx, cancel := context.WithDeadline(parent, deadline)
defer cancel()

// With cancellation
ctx, cancel := context.WithCancel(parent)
defer cancel()

// With value
ctx := context.WithValue(parent, "key", "value")
```

### Context Usage Patterns
```go
func doWork(ctx context.Context) error {
    select {
    case <-time.After(5 * time.Second): // Simulate long work
        return nil
    case <-ctx.Done():
        return ctx.Err() // context.DeadlineExceeded
    }
}
func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()

    err := doWork(ctx)
    if err != nil {
        fmt.Println("Timed out:", err)
    } else {
        fmt.Println("Completed")
    }
}
```

## Common Patterns Combined

### Graceful Shutdown
```go
func server(ctx context.Context) {
    jobs := make(chan Job, 100)
    results := make(chan Result, 100)

    // Start workers
    var wg sync.WaitGroup
    for i := 0; i < 5; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for {
                select {
                case job := <-jobs:
                    results <- processJob(job)
                case <-ctx.Done():
                    return
                }
            }
        }()
    }

    // Graceful shutdown
    <-ctx.Done()
    close(jobs)
    wg.Wait()
    close(results)
}
```