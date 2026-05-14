package config

import (
	"log"
	"os"
	"strings"
	"time"
)

// Config holds all server configuration values.
type Config struct {
	Port           string
	DBPath         string
	JWTSecret      string
	JWTExpiry      time.Duration
	RefreshExpiry  time.Duration
	BcryptCost     int
	RateLimit      float64
	AuthRateLimit  float64
	AllowedOrigins []string
}

// Load reads configuration from environment variables with sensible defaults.
func Load() *Config {
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable is required")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = ":8080"
	} else if !strings.HasPrefix(port, ":") {
		port = ":" + port
	}

	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "./data.db"
	}

	origins := os.Getenv("CORS_ORIGINS")
	var allowedOrigins []string
	if origins == "" || origins == "*" {
		allowedOrigins = []string{"*"}
	} else {
		for _, o := range strings.Split(origins, ",") {
			o = strings.TrimSpace(o)
			if o != "" {
				allowedOrigins = append(allowedOrigins, o)
			}
		}
	}

	return &Config{
		Port:           port,
		DBPath:         dbPath,
		JWTSecret:      jwtSecret,
		JWTExpiry:      7 * 24 * time.Hour,  // 7 days
		RefreshExpiry:  30 * 24 * time.Hour, // 30 days
		BcryptCost:     12,
		RateLimit:      60, // per minute
		AuthRateLimit:  5,  // per minute
		AllowedOrigins: allowedOrigins,
	}
}
