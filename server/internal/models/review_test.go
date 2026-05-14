package models

import (
	"database/sql"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func setupReviewDB(t *testing.T) *sql.DB {
	t.Helper()
	db := setupTestDB(t)
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS reviews (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		subject TEXT NOT NULL,
		year INTEGER NOT NULL,
		season TEXT NOT NULL,
		paper_type TEXT NOT NULL DEFAULT '',
		filename TEXT NOT NULL DEFAULT '',
		rating INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 5),
		difficulty INTEGER NOT NULL CHECK(difficulty >= 1 AND difficulty <= 5),
		tags TEXT NOT NULL DEFAULT '[]',
		comment TEXT NOT NULL DEFAULT '',
		created_at TEXT NOT NULL DEFAULT (datetime('now'))
	)`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique ON reviews(user_id, subject, year, season, paper_type)`); err != nil {
		t.Fatal(err)
	}
	return db
}

func TestReviewStore_Create(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	review, err := reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "file.pdf", 4, 3, []string{"hard"}, "good paper")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	if review.Rating != 4 {
		t.Errorf("expected rating 4, got %d", review.Rating)
	}
	if review.Difficulty != 3 {
		t.Errorf("expected difficulty 3, got %d", review.Difficulty)
	}
	if review.Subject != "9709" {
		t.Errorf("expected subject 9709, got %s", review.Subject)
	}
	if review.Year != 2023 {
		t.Errorf("expected year 2023, got %d", review.Year)
	}
	if review.Season != "Jun" {
		t.Errorf("expected season Jun, got %s", review.Season)
	}
	if review.PaperType != "qp" {
		t.Errorf("expected paper_type qp, got %s", review.PaperType)
	}
	if review.Filename != "file.pdf" {
		t.Errorf("expected filename file.pdf, got %s", review.Filename)
	}
	if review.Comment != "good paper" {
		t.Errorf("expected comment 'good paper', got %s", review.Comment)
	}
	if len(review.Tags) != 1 || review.Tags[0] != "hard" {
		t.Errorf("expected tags [hard], got %v", review.Tags)
	}
	if review.ID == 0 {
		t.Error("expected non-zero ID")
	}
}

func TestReviewStore_CreateNilTags(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	review, err := reviews.Create(user.ID, "9702", 2023, "Jun", "qp", "file.pdf", 3, 2, nil, "")
	if err != nil {
		t.Fatalf("Create with nil tags failed: %v", err)
	}
	// Create stores the original nil slice; json.Marshal(nil) produces "null" in the DB
	// When read back via List, Unmarshal("null") yields nil
	if review.Tags != nil {
		t.Errorf("expected nil tags from Create, got %v", review.Tags)
	}

	// Verify round-trip: List should return nil tags deserialized from "null"
	list, err := reviews.List("9702", 0, "")
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("expected 1 review, got %d", len(list))
	}
	// Unmarshal("null") gives nil, not empty slice
	if list[0].Tags != nil {
		t.Errorf("expected nil tags after round-trip, got %v", list[0].Tags)
	}
}

func TestReviewStore_CreateDuplicate(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "file.pdf", 4, 3, nil, "")
	_, err := reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "file.pdf", 5, 2, nil, "again")
	if err == nil {
		t.Error("expected error for duplicate review")
	}
}

func TestReviewStore_List(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user1, _ := users.Create("user1@test.com", "hash", "u1")
	user2, _ := users.Create("user2@test.com", "hash", "u2")
	reviews.Create(user1.ID, "9709", 2023, "Jun", "qp", "f.pdf", 4, 3, nil, "good")
	reviews.Create(user2.ID, "9709", 2023, "Jun", "qp", "f.pdf", 5, 2, nil, "great")

	list, err := reviews.List("9709", 2023, "Jun")
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(list) != 2 {
		t.Errorf("expected 2 reviews, got %d", len(list))
	}
}

func TestReviewStore_ListSubjectOnly(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "f.pdf", 4, 3, nil, "")
	reviews.Create(user.ID, "9709", 2023, "Nov", "ms", "f.pdf", 3, 2, nil, "")
	reviews.Create(user.ID, "9702", 2023, "Jun", "qp", "f.pdf", 5, 4, nil, "")

	// List by subject only
	list, err := reviews.List("9709", 0, "")
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(list) != 2 {
		t.Errorf("expected 2 reviews for subject 9709, got %d", len(list))
	}
}

func TestReviewStore_ListAll(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "f.pdf", 4, 3, nil, "")
	reviews.Create(user.ID, "9702", 2023, "Jun", "qp", "f.pdf", 5, 4, nil, "")

	// List all (no filters)
	list, err := reviews.List("", 0, "")
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(list) != 2 {
		t.Errorf("expected 2 reviews, got %d", len(list))
	}
}

func TestReviewStore_ListEmpty(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	reviews := NewReviewStore(db)

	list, err := reviews.List("", 0, "")
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(list) != 0 {
		t.Errorf("expected 0 reviews, got %d", len(list))
	}
}

func TestReviewStore_Stats(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user1, _ := users.Create("u1@test.com", "hash", "u1")
	user2, _ := users.Create("u2@test.com", "hash", "u2")
	reviews.Create(user1.ID, "9709", 2023, "Jun", "qp", "f.pdf", 4, 3, nil, "")
	reviews.Create(user2.ID, "9709", 2023, "Jun", "qp", "f.pdf", 5, 2, nil, "")

	stats, err := reviews.Stats("9709")
	if err != nil {
		t.Fatalf("Stats failed: %v", err)
	}
	if stats.TotalReviews != 2 {
		t.Errorf("expected 2 reviews, got %d", stats.TotalReviews)
	}
	if stats.AvgRating != 4.5 {
		t.Errorf("expected avg rating 4.5, got %f", stats.AvgRating)
	}
	if stats.AvgDifficulty != 2.5 {
		t.Errorf("expected avg difficulty 2.5, got %f", stats.AvgDifficulty)
	}
	if stats.Subject != "9709" {
		t.Errorf("expected subject 9709, got %s", stats.Subject)
	}
}

func TestReviewStore_StatsEmpty(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	reviews := NewReviewStore(db)

	stats, err := reviews.Stats("nonexistent")
	if err != nil {
		t.Fatalf("Stats failed: %v", err)
	}
	if stats.TotalReviews != 0 {
		t.Errorf("expected 0 reviews, got %d", stats.TotalReviews)
	}
}

func TestReviewStore_Delete(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	review, _ := reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "f.pdf", 4, 3, nil, "")

	err := reviews.Delete(review.ID, user.ID)
	if err != nil {
		t.Fatalf("Delete failed: %v", err)
	}

	// Use empty filters to list all reviews
	list, _ := reviews.List("", 0, "")
	if len(list) != 0 {
		t.Errorf("expected 0 reviews after delete, got %d", len(list))
	}
}

func TestReviewStore_DeleteWrongUser(t *testing.T) {
	db := setupReviewDB(t)
	defer db.Close()
	users := NewUserStore(db)
	reviews := NewReviewStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	review, _ := reviews.Create(user.ID, "9709", 2023, "Jun", "qp", "f.pdf", 4, 3, nil, "")

	// Delete with wrong user ID should not remove the review
	err := reviews.Delete(review.ID, 9999)
	if err != nil {
		t.Fatalf("Delete with wrong user should not error, got: %v", err)
	}

	list, _ := reviews.List("", 0, "")
	if len(list) != 1 {
		t.Errorf("expected 1 review (delete with wrong user should be no-op), got %d", len(list))
	}
}
