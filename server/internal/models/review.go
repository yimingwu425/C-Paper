package models

import (
	"database/sql"
	"encoding/json"
	"time"
)

type Review struct {
	ID           int64    `json:"id"`
	UserID       int64    `json:"user_id"`
	Subject      string   `json:"subject"`
	Year         int      `json:"year"`
	Season       string   `json:"season"`
	PaperType    string   `json:"paper_type"`
	Filename     string   `json:"filename"`
	Rating       int      `json:"rating"`
	Difficulty   int      `json:"difficulty"`
	Tags         []string `json:"tags"`
	Comment      string   `json:"comment"`
	CreatedAt    string   `json:"created_at"`
	UserNickname string   `json:"user_nickname,omitempty"`
}

type ReviewStats struct {
	Subject       string  `json:"subject"`
	TotalReviews  int     `json:"total_reviews"`
	AvgRating     float64 `json:"avg_rating"`
	AvgDifficulty float64 `json:"avg_difficulty"`
}

type ReviewStore struct {
	db *sql.DB
}

func NewReviewStore(db *sql.DB) *ReviewStore {
	return &ReviewStore{db: db}
}

func (s *ReviewStore) Create(userID int64, subject string, year int, season, paperType, filename string, rating, difficulty int, tags []string, comment string) (*Review, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	tagsJSON, _ := json.Marshal(tags)
	res, err := s.db.Exec(
		`INSERT INTO reviews (user_id, subject, year, season, paper_type, filename, rating, difficulty, tags, comment, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		userID, subject, year, season, paperType, filename, rating, difficulty, string(tagsJSON), comment, now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return &Review{ID: id, UserID: userID, Subject: subject, Year: year, Season: season, PaperType: paperType, Filename: filename, Rating: rating, Difficulty: difficulty, Tags: tags, Comment: comment, CreatedAt: now}, nil
}

func (s *ReviewStore) Delete(reviewID, userID int64) error {
	_, err := s.db.Exec(`DELETE FROM reviews WHERE id = ? AND user_id = ?`, reviewID, userID)
	return err
}

func (s *ReviewStore) List(subject string, year int, season string) ([]Review, error) {
	query := `SELECT r.id, r.user_id, r.subject, r.year, r.season, r.paper_type, r.filename, r.rating, r.difficulty, r.tags, r.comment, r.created_at, u.nickname
		      FROM reviews r JOIN users u ON r.user_id = u.id WHERE 1=1`
	var args []interface{}
	if subject != "" {
		query += ` AND r.subject = ?`
		args = append(args, subject)
	}
	if year > 0 {
		query += ` AND r.year = ?`
		args = append(args, year)
	}
	if season != "" {
		query += ` AND r.season = ?`
		args = append(args, season)
	}
	query += ` ORDER BY r.created_at DESC`

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var reviews []Review
	for rows.Next() {
		var rev Review
		var tagsStr string
		if err := rows.Scan(&rev.ID, &rev.UserID, &rev.Subject, &rev.Year, &rev.Season, &rev.PaperType, &rev.Filename, &rev.Rating, &rev.Difficulty, &tagsStr, &rev.Comment, &rev.CreatedAt, &rev.UserNickname); err != nil {
			return nil, err
		}
		json.Unmarshal([]byte(tagsStr), &rev.Tags)
		reviews = append(reviews, rev)
	}
	return reviews, rows.Err()
}

func (s *ReviewStore) Stats(subject string) (*ReviewStats, error) {
	stats := &ReviewStats{Subject: subject}
	err := s.db.QueryRow(
		`SELECT COUNT(*), COALESCE(AVG(rating), 0), COALESCE(AVG(difficulty), 0) FROM reviews WHERE subject = ?`, subject,
	).Scan(&stats.TotalReviews, &stats.AvgRating, &stats.AvgDifficulty)
	return stats, err
}
