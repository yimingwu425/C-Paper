package main

import (
	"log"
	"net/http"

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

	log.Printf("C-Paper server listening on %s", cfg.Port)
	if err := http.ListenAndServe(cfg.Port, handler); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
