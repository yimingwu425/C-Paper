package middleware

import (
	"encoding/json"
	"net"
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

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
	limiter, exists := rl.limiters.Load(ip)
	if exists {
		return limiter.(*rate.Limiter)
	}

	newLimiter := rate.NewLimiter(rl.rate, rl.burst)
	actual, _ := rl.limiters.LoadOrStore(ip, newLimiter)
	return actual.(*rate.Limiter)
}

// RateLimitGeneral creates a middleware that limits requests to 60 per minute per IP.
func RateLimitGeneral(next http.Handler) http.Handler {
	limiter := NewIPRateLimiter(rate.Every(1*time.Second), 60)
	return rateLimitMiddleware(limiter, next)
}

// RateLimitAuth creates a middleware that limits auth requests to 5 per minute per IP.
func RateLimitAuth(next http.Handler) http.Handler {
	limiter := NewIPRateLimiter(rate.Every(12*time.Second), 5)
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
