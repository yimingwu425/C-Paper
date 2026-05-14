package middleware

import (
	"github.com/go-chi/cors"
)

// CORSOptions returns cors.Options configured with the given allowed origins.
func CORSOptions(allowedOrigins []string) cors.Options {
	return cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type"},
		AllowCredentials: true,
		MaxAge:           300,
	}
}
