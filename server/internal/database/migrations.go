package database

import (
	"database/sql"
	"log"
)

// Migrate creates all tables and indexes if they do not already exist.
func Migrate(db *sql.DB) {
	tables := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			email TEXT NOT NULL UNIQUE,
			password_hash TEXT NOT NULL,
			nickname TEXT DEFAULT '',
			avatar_url TEXT DEFAULT '',
			created_at TEXT DEFAULT (datetime('now')),
			updated_at TEXT DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS shares (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			code TEXT NOT NULL UNIQUE,
			subject TEXT NOT NULL,
			year INTEGER NOT NULL,
			season TEXT NOT NULL,
			paper_type TEXT DEFAULT '',
			expires_at TEXT NOT NULL,
			view_count INTEGER DEFAULT 0,
			created_at TEXT DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS groups (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			description TEXT DEFAULT '',
			invite_code TEXT NOT NULL UNIQUE,
			owner_id INTEGER NOT NULL REFERENCES users(id),
			created_at TEXT DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS group_members (
			group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			role TEXT DEFAULT 'member',
			joined_at TEXT DEFAULT (datetime('now')),
			PRIMARY KEY (group_id, user_id)
		)`,
		`CREATE TABLE IF NOT EXISTS group_papers (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			added_by INTEGER NOT NULL REFERENCES users(id),
			subject TEXT NOT NULL,
			year INTEGER NOT NULL,
			season TEXT NOT NULL,
			paper_type TEXT DEFAULT '',
			filename TEXT NOT NULL,
			download_url TEXT DEFAULT '',
			created_at TEXT DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS group_downloads (
			group_paper_id INTEGER NOT NULL REFERENCES group_papers(id) ON DELETE CASCADE,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			status TEXT DEFAULT 'pending',
			updated_at TEXT DEFAULT (datetime('now')),
			PRIMARY KEY (group_paper_id, user_id)
		)`,
		`CREATE TABLE IF NOT EXISTS reviews (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			subject TEXT NOT NULL,
			year INTEGER NOT NULL,
			season TEXT NOT NULL,
			paper_type TEXT DEFAULT '',
			filename TEXT DEFAULT '',
			rating INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 5),
			difficulty INTEGER NOT NULL CHECK(difficulty >= 1 AND difficulty <= 5),
			tags TEXT DEFAULT '[]',
			comment TEXT DEFAULT '',
			created_at TEXT DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS review_reactions (
			review_id INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			reaction TEXT NOT NULL,
			PRIMARY KEY (review_id, user_id)
		)`,
	}

	for _, ddl := range tables {
		if _, err := db.Exec(ddl); err != nil {
			log.Fatalf("Failed to create table: %v\nSQL: %s", err, ddl)
		}
	}

	indexes := []string{
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_shares_code ON shares(code)`,
		`CREATE INDEX IF NOT EXISTS idx_shares_user_id ON shares(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_shares_expires_at ON shares(expires_at)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_invite_code ON groups(invite_code)`,
		`CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id)`,
		`CREATE INDEX IF NOT EXISTS idx_group_papers_group ON group_papers(group_id)`,
		`CREATE INDEX IF NOT EXISTS idx_group_downloads_user ON group_downloads(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_reviews_subject_year ON reviews(subject, year, season)`,
		`CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique ON reviews(user_id, subject, year, season, paper_type)`,
		`CREATE INDEX IF NOT EXISTS idx_review_reactions_review ON review_reactions(review_id)`,
	}

	for _, ddl := range indexes {
		if _, err := db.Exec(ddl); err != nil {
			log.Fatalf("Failed to create index: %v\nSQL: %s", err, ddl)
		}
	}

	log.Println("Database migration completed successfully")
}
