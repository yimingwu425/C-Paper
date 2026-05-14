package models

import (
	"database/sql"
	"time"
)

type User struct {
	ID           int64  `json:"id"`
	Email        string `json:"email"`
	PasswordHash string `json:"-"`
	Nickname     string `json:"nickname"`
	AvatarURL    string `json:"avatar_url"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
}

type UserStore struct {
	db *sql.DB
}

func NewUserStore(db *sql.DB) *UserStore {
	return &UserStore{db: db}
}

func (s *UserStore) Create(email, passwordHash, nickname string) (*User, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	res, err := s.db.Exec(
		`INSERT INTO users (email, password_hash, nickname, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`,
		email, passwordHash, nickname, now, now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return &User{ID: id, Email: email, Nickname: nickname, CreatedAt: now, UpdatedAt: now}, nil
}

func (s *UserStore) GetByID(id int64) (*User, error) {
	u := &User{}
	err := s.db.QueryRow(
		`SELECT id, email, password_hash, nickname, avatar_url, created_at, updated_at FROM users WHERE id = ?`, id,
	).Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Nickname, &u.AvatarURL, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (s *UserStore) GetByEmail(email string) (*User, error) {
	u := &User{}
	err := s.db.QueryRow(
		`SELECT id, email, password_hash, nickname, avatar_url, created_at, updated_at FROM users WHERE email = ?`, email,
	).Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Nickname, &u.AvatarURL, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (s *UserStore) Update(id int64, nickname, avatarURL string) error {
	_, err := s.db.Exec(
		`UPDATE users SET nickname = ?, avatar_url = ?, updated_at = ? WHERE id = ?`,
		nickname, avatarURL, time.Now().UTC().Format(time.RFC3339), id,
	)
	return err
}
