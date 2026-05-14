package models

import (
	"database/sql"
	"testing"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

func setupShareDB(t *testing.T) *sql.DB {
	t.Helper()
	db := setupTestDB(t) // reuse user DB setup
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS shares (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		code TEXT NOT NULL UNIQUE,
		subject TEXT NOT NULL,
		year INTEGER NOT NULL,
		season TEXT NOT NULL,
		paper_type TEXT NOT NULL DEFAULT '',
		expires_at TEXT NOT NULL,
		view_count INTEGER NOT NULL DEFAULT 0,
		created_at TEXT NOT NULL DEFAULT (datetime('now'))
	)`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_shares_code ON shares(code)`); err != nil {
		t.Fatal(err)
	}
	return db
}

func TestShareStore_Create(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	share, err := shares.Create(user.ID, "abc1234", "9709", 2023, "Jun", "qp", expires)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	if share.Code != "abc1234" {
		t.Errorf("expected code abc1234, got %s", share.Code)
	}
	if share.Subject != "9709" {
		t.Errorf("expected subject 9709, got %s", share.Subject)
	}
	if share.Year != 2023 {
		t.Errorf("expected year 2023, got %d", share.Year)
	}
	if share.Season != "Jun" {
		t.Errorf("expected season Jun, got %s", share.Season)
	}
	if share.PaperType != "qp" {
		t.Errorf("expected paper_type qp, got %s", share.PaperType)
	}
	if share.UserID != user.ID {
		t.Errorf("expected user_id %d, got %d", user.ID, share.UserID)
	}
}

func TestShareStore_CreateDuplicate(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	shares.Create(user.ID, "abc1234", "9709", 2023, "Jun", "qp", expires)

	_, err := shares.Create(user.ID, "abc1234", "9709", 2023, "Nov", "ms", expires)
	if err == nil {
		t.Error("expected error for duplicate share code")
	}
}

func TestShareStore_GetByCode(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	shares.Create(user.ID, "abc1234", "9709", 2023, "Jun", "qp", expires)

	share, err := shares.GetByCode("abc1234")
	if err != nil {
		t.Fatalf("GetByCode failed: %v", err)
	}
	if share.Subject != "9709" {
		t.Errorf("expected subject 9709, got %s", share.Subject)
	}
	// GetByCode increments view_count, so after Create (view_count=0) + first GetByCode = 1
	if share.ViewCount != 1 {
		t.Errorf("expected view_count 1, got %d", share.ViewCount)
	}
}

func TestShareStore_GetByCodeIncrementViews(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	shares.Create(user.ID, "abc1234", "9709", 2023, "Jun", "qp", expires)

	shares.GetByCode("abc1234")
	shares.GetByCode("abc1234")
	share, _ := shares.GetByCode("abc1234")
	if share.ViewCount != 3 {
		t.Errorf("expected view_count 3, got %d", share.ViewCount)
	}
}

func TestShareStore_GetByCodeNotFound(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	shares := NewShareStore(db)

	_, err := shares.GetByCode("nonexistent")
	if err == nil {
		t.Error("expected error for non-existent share code")
	}
}

func TestShareStore_Delete(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	shares.Create(user.ID, "abc1234", "9709", 2023, "Jun", "qp", expires)

	err := shares.Delete("abc1234", user.ID)
	if err != nil {
		t.Fatalf("Delete failed: %v", err)
	}
	_, err = shares.GetByCode("abc1234")
	if err == nil {
		t.Error("expected error after delete")
	}
}

func TestShareStore_DeleteWrongUser(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	shares.Create(user.ID, "abc1234", "9709", 2023, "Jun", "qp", expires)

	// Delete with wrong user ID should not remove the share
	err := shares.Delete("abc1234", 9999)
	if err != nil {
		t.Fatalf("Delete with wrong user should not error, got: %v", err)
	}
	// Share should still exist
	_, err = shares.GetByCode("abc1234")
	if err != nil {
		t.Error("share should still exist after delete with wrong user")
	}
}

func TestShareStore_ListByUser(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	users := NewUserStore(db)
	shares := NewShareStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	expires := time.Now().AddDate(0, 0, 7).Format(time.RFC3339)
	shares.Create(user.ID, "code1", "9709", 2023, "Jun", "qp", expires)
	shares.Create(user.ID, "code2", "9709", 2023, "Nov", "ms", expires)

	list, err := shares.ListByUser(user.ID)
	if err != nil {
		t.Fatalf("ListByUser failed: %v", err)
	}
	if len(list) != 2 {
		t.Errorf("expected 2 shares, got %d", len(list))
	}
}

func TestShareStore_ListByUserEmpty(t *testing.T) {
	db := setupShareDB(t)
	defer db.Close()
	shares := NewShareStore(db)

	list, err := shares.ListByUser(9999)
	if err != nil {
		t.Fatalf("ListByUser failed: %v", err)
	}
	if len(list) != 0 {
		t.Errorf("expected 0 shares, got %d", len(list))
	}
}
