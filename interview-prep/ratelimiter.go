package main

import (
	"context"
	"fmt"
	"time"
)

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

func main() {
	// Allow 5 requests per second
	rl := NewRateLimiter(5, time.Second)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	for i := 0; i < 12; i++ {
		if err := rl.Wait(ctx); err != nil {
			fmt.Printf("request %d: rate limit exceeded or context done: %v\n", i+1, err)
			return
		}
		fmt.Printf("request %d: allowed at %s\n", i+1, time.Now().Format(time.RFC3339Nano))
	}
}
