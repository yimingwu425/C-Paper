package middleware

import (
	"encoding/json"
	"net"
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// ipEntry holds a limiter with its last access time.
type ipEntry struct {
	limiter    *rate.Limiter
	lastAccess time.Time
}

// IPRateLimiter manages per-IP rate limiters using a token bucket algorithm.
type IPRateLimiter struct {
	limiters sync.Map
	rate     rate.Limit
	burst    int
}

// NewIPRateLimiter creates a new per-IP rate limiter.
// r is the rate of tokens per second, burst is the maximum burst size.
func NewIPRateLimiter(r rate.Limit, burst int) *IPRateLimiter {
	return &IPRateLimiter{
		rate:  r,
		burst: burst,
	}
}

// GetLimiter returns the rate limiter for the given IP, creating one if needed.
func (rl *IPRateLimiter) GetLimiter(ip string) *rate.Limiter {
	if entry, exists := rl.limiters.Load(ip); exists {
		e := entry.(*ipEntry)
		e.lastAccess = time.Now()
		return e.limiter
	}

	newLimiter := rate.NewLimiter(rl.rate, rl.burst)
	entry := &ipEntry{limiter: newLimiter, lastAccess: time.Now()}
	actual, _ := rl.limiters.LoadOrStore(ip, entry)
	return actual.(*ipEntry).limiter
}

// cleanup removes entries not accessed for the given duration.
func (rl *IPRateLimiter) cleanup(maxAge time.Duration) {
	now := time.Now()
	rl.limiters.Range(func(key, value any) bool {
		entry := value.(*ipEntry)
		if now.Sub(entry.lastAccess) > maxAge {
			rl.limiters.Delete(key)
		}
		return true
	})
}

// StartCleanup launches a background goroutine that periodically evicts stale entries.
func (rl *IPRateLimiter) StartCleanup(interval, maxAge time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for range ticker.C {
			rl.cleanup(maxAge)
		}
	}()
}

// RateLimitGeneral creates a middleware that limits requests to 60 per minute per IP.
func RateLimitGeneral(next http.Handler) http.Handler {
	limiter := NewIPRateLimiter(rate.Every(1*time.Second), 60)
	limiter.StartCleanup(10*time.Minute, 5*time.Minute)
	return rateLimitMiddleware(limiter, next)
}

// RateLimitAuth creates a middleware that limits auth requests to 5 per minute per IP.
func RateLimitAuth(next http.Handler) http.Handler {
	limiter := NewIPRateLimiter(rate.Every(12*time.Second), 5)
	limiter.StartCleanup(10*time.Minute, 5*time.Minute)
	return rateLimitMiddleware(limiter, next)
}

func rateLimitMiddleware(rl *IPRateLimiter, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := extractIP(r)
		limiter := rl.GetLimiter(ip)

		if !limiter.Allow() {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"ok":    false,
				"error": "Rate limit exceeded. Please try again later.",
			})
			return
		}

		next.ServeHTTP(w, r)
	})
}

// extractIP gets the client IP from the request, preferring X-Forwarded-For.
func extractIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// Take the first IP in the chain
		for i, c := range xff {
			if c == ',' {
				return xff[:i]
			}
		}
		return xff
	}

	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return xri
	}

	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return ip
}
