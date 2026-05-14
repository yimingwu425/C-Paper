package database

import (
	"database/sql"
	"log"

	_ "github.com/mattn/go-sqlite3"
)

// Open creates a new SQLite connection with WAL mode, foreign keys, and busy timeout.
func Open(dbPath string) *sql.DB {
	dsn := "file:" + dbPath + "?_journal_mode=WAL&_foreign_keys=ON&_busy_timeout=5000"
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}

	// WAL mode allows concurrent reads. Use a small pool for read throughput.
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(5)

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}

	return db
}
