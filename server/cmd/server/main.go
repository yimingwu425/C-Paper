package main

import (
	"context"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/ja-son-wu/c-paper-server/internal/config"
	"github.com/ja-son-wu/c-paper-server/internal/database"
	"github.com/ja-son-wu/c-paper-server/internal/router"
)

func main() {
	cfg := config.Load()

	db := database.Open(cfg.DBPath)
	defer db.Close()

	database.Migrate(db)

	handler := router.Setup(db, cfg)

	srv := &http.Server{
		Addr:    cfg.Port,
		Handler: handler,
	}

	// Start server in goroutine
	go func() {
		log.Printf("C-Paper server listening on %s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	<-ctx.Done()

	log.Println("Shutting down server...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}
	log.Println("Server stopped")
}
