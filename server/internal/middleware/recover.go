package middleware

import (
	"log"
	"net/http"
	"runtime/debug"
)

// Recover returns middleware that catches panics and returns 500 instead of crashing.
func Recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("PANIC recovered: %v | method=%s path=%s\n%s", rec, r.Method, r.URL.Path, debug.Stack())
				http.Error(w, `{"ok":false,"error":"internal server error"}`, http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
