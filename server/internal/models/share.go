package models

import (
	"database/sql"
	"time"
)

type Share struct {
	ID        int64  `json:"id"`
	UserID    int64  `json:"user_id"`
	Code      string `json:"code"`
	Subject   string `json:"subject"`
	Year      int    `json:"year"`
	Season    string `json:"season"`
	PaperType string `json:"paper_type"`
	ExpiresAt string `json:"expires_at"`
	ViewCount int    `json:"view_count"`
	CreatedAt string `json:"created_at"`
}

type ShareStore struct {
	db *sql.DB
}

func NewShareStore(db *sql.DB) *ShareStore {
	return &ShareStore{db: db}
}

func (s *ShareStore) Create(userID int64, code, subject string, year int, season, paperType, expiresAt string) (*Share, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	res, err := s.db.Exec(
		`INSERT INTO shares (user_id, code, subject, year, season, paper_type, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		userID, code, subject, year, season, paperType, expiresAt, now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return &Share{ID: id, UserID: userID, Code: code, Subject: subject, Year: year, Season: season, PaperType: paperType, ExpiresAt: expiresAt, CreatedAt: now}, nil
}

func (s *ShareStore) GetByCode(code string) (*Share, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	_, err = tx.Exec(`UPDATE shares SET view_count = view_count + 1 WHERE code = ?`, code)
	if err != nil {
		return nil, err
	}

	sh := &Share{}
	err = tx.QueryRow(
		`SELECT id, user_id, code, subject, year, season, paper_type, expires_at, view_count, created_at FROM shares WHERE code = ?`, code,
	).Scan(&sh.ID, &sh.UserID, &sh.Code, &sh.Subject, &sh.Year, &sh.Season, &sh.PaperType, &sh.ExpiresAt, &sh.ViewCount, &sh.CreatedAt)
	if err != nil {
		return nil, err
	}

	return sh, tx.Commit()
}

func (s *ShareStore) Delete(code string, userID int64) error {
	_, err := s.db.Exec(`DELETE FROM shares WHERE code = ? AND user_id = ?`, code, userID)
	return err
}

func (s *ShareStore) ListByUser(userID int64) ([]Share, error) {
	rows, err := s.db.Query(
		`SELECT id, user_id, code, subject, year, season, paper_type, expires_at, view_count, created_at FROM shares WHERE user_id = ? ORDER BY created_at DESC`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var shares []Share
	for rows.Next() {
		var sh Share
		if err := rows.Scan(&sh.ID, &sh.UserID, &sh.Code, &sh.Subject, &sh.Year, &sh.Season, &sh.PaperType, &sh.ExpiresAt, &sh.ViewCount, &sh.CreatedAt); err != nil {
			return nil, err
		}
		shares = append(shares, sh)
	}
	return shares, rows.Err()
}
