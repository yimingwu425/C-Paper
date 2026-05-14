package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"golang.org/x/time/rate"
)

func TestIPRateLimiter_GetLimiter(t *testing.T) {
	rl := NewIPRateLimiter(rate.Every(time.Second), 5)

	l1 := rl.GetLimiter("192.168.1.1")
	l2 := rl.GetLimiter("192.168.1.2")
	if l1 == l2 {
		t.Error("different IPs should have different limiters")
	}

	l1Again := rl.GetLimiter("192.168.1.1")
	if l1 != l1Again {
		t.Error("same IP should return same limiter")
	}
}

func TestIPRateLimiter_Cleanup(t *testing.T) {
	rl := NewIPRateLimiter(rate.Every(time.Second), 5)
	rl.GetLimiter("1.1.1.1")
	rl.GetLimiter("2.2.2.2")

	// Simulate cleanup with very short max age
	rl.cleanup(0) // maxAge=0 means remove all

	count := 0
	rl.limiters.Range(func(key, value any) bool {
		count++
		return true
	})
	if count != 0 {
		t.Errorf("expected 0 entries after cleanup, got %d", count)
	}
}

func TestRateLimitMiddleware(t *testing.T) {
	// 1 token per 1000 seconds, burst 1 = effectively block after first request
	rl := NewIPRateLimiter(rate.Every(1000*time.Second), 1)

	handler := rateLimitMiddleware(rl, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))

	// First request should pass
	req := httptest.NewRequest("GET", "/", nil)
	req.RemoteAddr = "10.0.0.1:1234"
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Errorf("first request: expected 200, got %d", rec.Code)
	}

	// Second request should be rate limited
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != 429 {
		t.Errorf("second request: expected 429, got %d", rec.Code)
	}
}

func TestRateLimitMiddleware_DifferentIPs(t *testing.T) {
	rl := NewIPRateLimiter(rate.Every(1000*time.Second), 1)

	handler := rateLimitMiddleware(rl, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))

	makeReq := func(ip string) *http.Request {
		req := httptest.NewRequest("GET", "/", nil)
		req.RemoteAddr = ip + ":1234"
		return req
	}

	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, makeReq("10.0.0.1"))
	if rec1.Code != 200 {
		t.Errorf("IP1 first request: expected 200, got %d", rec1.Code)
	}

	// Request from IP 2 should also pass (different limiter)
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, makeReq("10.0.0.2"))
	if rec2.Code != 200 {
		t.Errorf("IP2 first request: expected 200, got %d", rec2.Code)
	}

	// Second request from IP 1 should be rate limited
	rec3 := httptest.NewRecorder()
	handler.ServeHTTP(rec3, makeReq("10.0.0.1"))
	if rec3.Code != 429 {
		t.Errorf("IP1 second request: expected 429, got %d", rec3.Code)
	}
}

func TestRateLimitMiddleware_ResponseFormat(t *testing.T) {
	rl := NewIPRateLimiter(rate.Every(1000*time.Second), 1)

	handler := rateLimitMiddleware(rl, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))

	makeReq := func() *http.Request {
		req := httptest.NewRequest("GET", "/", nil)
		req.RemoteAddr = "10.0.0.1:1234"
		return req
	}

	// Consume the token
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, makeReq())

	// Second request should get rate limited with JSON response
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, makeReq())

	if rec.Code != 429 {
		t.Errorf("expected 429, got %d", rec.Code)
	}
	if rec.Header().Get("Content-Type") != "application/json" {
		t.Errorf("expected Content-Type application/json, got %s", rec.Header().Get("Content-Type"))
	}
	if rec.Body.Len() == 0 {
		t.Error("expected non-empty body for rate limit response")
	}
}

func TestExtractIP_XForwardedFor(t *testing.T) {
	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("X-Forwarded-For", "203.0.113.50, 70.41.3.18")

	ip := extractIP(req)
	if ip != "203.0.113.50" {
		t.Errorf("expected 203.0.113.50, got %s", ip)
	}
}

func TestExtractIP_XRealIP(t *testing.T) {
	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("X-Real-IP", "203.0.113.50")

	ip := extractIP(req)
	if ip != "203.0.113.50" {
		t.Errorf("expected 203.0.113.50, got %s", ip)
	}
}

func TestExtractIP_RemoteAddr(t *testing.T) {
	req := httptest.NewRequest("GET", "/", nil)
	req.RemoteAddr = "192.168.1.1:54321"

	ip := extractIP(req)
	if ip != "192.168.1.1" {
		t.Errorf("expected 192.168.1.1, got %s", ip)
	}
}

func TestExtractIP_XForwardedForPriority(t *testing.T) {
	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("X-Forwarded-For", "203.0.113.50")
	req.Header.Set("X-Real-IP", "70.41.3.18")
	req.RemoteAddr = "192.168.1.1:54321"

	ip := extractIP(req)
	if ip != "203.0.113.50" {
		t.Errorf("X-Forwarded-For should take priority, expected 203.0.113.50, got %s", ip)
	}
}
