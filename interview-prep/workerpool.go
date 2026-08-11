package main

import (
	"context"
	"sync"
)

type Result struct{}
type Job struct{}

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

func process(ctx context.Context, job Job) Result {
	return Result{}
}
