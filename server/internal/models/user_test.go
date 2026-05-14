package models

import (
	"database/sql"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func setupTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	// Run migrations
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		email TEXT NOT NULL UNIQUE,
		password_hash TEXT NOT NULL,
		nickname TEXT NOT NULL DEFAULT '',
		avatar_url TEXT NOT NULL DEFAULT '',
		created_at TEXT NOT NULL DEFAULT (datetime('now')),
		updated_at TEXT NOT NULL DEFAULT (datetime('now'))
	)`); err != nil {
		t.Fatal(err)
	}
	return db
}

func TestUserStore_Create(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	user, err := store.Create("test@example.com", "hash123", "tester")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	if user.ID == 0 {
		t.Error("expected non-zero ID")
	}
	if user.Email != "test@example.com" {
		t.Errorf("expected email test@example.com, got %s", user.Email)
	}
	if user.Nickname != "tester" {
		t.Errorf("expected nickname tester, got %s", user.Nickname)
	}
	if user.CreatedAt == "" {
		t.Error("expected non-empty CreatedAt")
	}
	if user.UpdatedAt == "" {
		t.Error("expected non-empty UpdatedAt")
	}
}

func TestUserStore_CreateDuplicate(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	store.Create("test@example.com", "hash", "t1")
	_, err := store.Create("test@example.com", "hash", "t2")
	if err == nil {
		t.Error("expected error for duplicate email")
	}
}

func TestUserStore_GetByEmail(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	store.Create("test@example.com", "hash", "tester")
	user, err := store.GetByEmail("test@example.com")
	if err != nil {
		t.Fatalf("GetByEmail failed: %v", err)
	}
	if user.Nickname != "tester" {
		t.Errorf("expected nickname tester, got %s", user.Nickname)
	}
	if user.PasswordHash != "hash" {
		t.Errorf("expected password_hash hash, got %s", user.PasswordHash)
	}
}

func TestUserStore_GetByEmailNotFound(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	_, err := store.GetByEmail("nonexistent@example.com")
	if err == nil {
		t.Error("expected error for non-existent email")
	}
}

func TestUserStore_GetByID(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	created, _ := store.Create("test@example.com", "hash", "tester")
	found, err := store.GetByID(created.ID)
	if err != nil {
		t.Fatalf("GetByID failed: %v", err)
	}
	if found.Email != "test@example.com" {
		t.Errorf("email mismatch: expected test@example.com, got %s", found.Email)
	}
	if found.Nickname != "tester" {
		t.Errorf("nickname mismatch: expected tester, got %s", found.Nickname)
	}
}

func TestUserStore_GetByIDNotFound(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	_, err := store.GetByID(9999)
	if err == nil {
		t.Error("expected error for non-existent ID")
	}
}

func TestUserStore_Update(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	user, _ := store.Create("test@example.com", "hash", "old")
	err := store.Update(user.ID, "new", "https://avatar.url")
	if err != nil {
		t.Fatalf("Update failed: %v", err)
	}
	updated, _ := store.GetByID(user.ID)
	if updated.Nickname != "new" {
		t.Errorf("expected nickname new, got %s", updated.Nickname)
	}
	if updated.AvatarURL != "https://avatar.url" {
		t.Errorf("expected avatar_url https://avatar.url, got %s", updated.AvatarURL)
	}
}

func TestUserStore_UpdateNonExistent(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()
	store := NewUserStore(db)

	// Update on non-existent user should not return error (0 rows affected is not an error)
	err := store.Update(9999, "new", "url")
	if err != nil {
		t.Fatalf("Update on non-existent user should not error, got: %v", err)
	}
}
