package models

import (
	"database/sql"
	"time"
)

type Group struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	InviteCode  string `json:"invite_code"`
	OwnerID     int64  `json:"owner_id"`
	CreatedAt   string `json:"created_at"`
}

type GroupMember struct {
	GroupID   int64  `json:"group_id"`
	UserID    int64  `json:"user_id"`
	Role      string `json:"role"`
	JoinedAt  string `json:"joined_at"`
	Nickname  string `json:"nickname,omitempty"`
	AvatarURL string `json:"avatar_url,omitempty"`
}

type GroupPaper struct {
	ID          int64  `json:"id"`
	GroupID     int64  `json:"group_id"`
	AddedBy     int64  `json:"added_by"`
	Subject     string `json:"subject"`
	Year        int    `json:"year"`
	Season      string `json:"season"`
	PaperType   string `json:"paper_type"`
	Filename    string `json:"filename"`
	DownloadURL string `json:"download_url"`
	CreatedAt   string `json:"created_at"`
}

type GroupDownload struct {
	GroupPaperID int64  `json:"group_paper_id"`
	UserID       int64  `json:"user_id"`
	Status       string `json:"status"`
	UpdatedAt    string `json:"updated_at"`
}

type GroupStore struct {
	db *sql.DB
}

func NewGroupStore(db *sql.DB) *GroupStore {
	return &GroupStore{db: db}
}

func (s *GroupStore) Create(name, description, inviteCode string, ownerID int64) (*Group, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	now := time.Now().UTC().Format(time.RFC3339)
	res, err := tx.Exec(
		`INSERT INTO groups (name, description, invite_code, owner_id, created_at) VALUES (?, ?, ?, ?, ?)`,
		name, description, inviteCode, ownerID, now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()

	_, err = tx.Exec(
		`INSERT INTO group_members (group_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)`,
		id, ownerID, now,
	)
	if err != nil {
		return nil, err
	}

	return &Group{ID: id, Name: name, Description: description, InviteCode: inviteCode, OwnerID: ownerID, CreatedAt: now}, tx.Commit()
}

func (s *GroupStore) GetByID(id int64) (*Group, error) {
	g := &Group{}
	err := s.db.QueryRow(
		`SELECT id, name, description, invite_code, owner_id, created_at FROM groups WHERE id = ?`, id,
	).Scan(&g.ID, &g.Name, &g.Description, &g.InviteCode, &g.OwnerID, &g.CreatedAt)
	return g, err
}

func (s *GroupStore) ListByUser(userID int64) ([]Group, error) {
	rows, err := s.db.Query(
		`SELECT g.id, g.name, g.description, g.invite_code, g.owner_id, g.created_at
		 FROM groups g JOIN group_members gm ON g.id = gm.group_id
		 WHERE gm.user_id = ? ORDER BY g.created_at DESC`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var groups []Group
	for rows.Next() {
		var g Group
		if err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.InviteCode, &g.OwnerID, &g.CreatedAt); err != nil {
			return nil, err
		}
		groups = append(groups, g)
	}
	return groups, rows.Err()
}

func (s *GroupStore) Join(inviteCode string, userID int64) error {
	g, err := s.GetByInviteCode(inviteCode)
	if err != nil {
		return err
	}
	now := time.Now().UTC().Format(time.RFC3339)
	_, err = s.db.Exec(
		`INSERT OR IGNORE INTO group_members (group_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)`,
		g.ID, userID, now,
	)
	return err
}

func (s *GroupStore) GetByInviteCode(code string) (*Group, error) {
	g := &Group{}
	err := s.db.QueryRow(
		`SELECT id, name, description, invite_code, owner_id, created_at FROM groups WHERE invite_code = ?`, code,
	).Scan(&g.ID, &g.Name, &g.Description, &g.InviteCode, &g.OwnerID, &g.CreatedAt)
	return g, err
}

func (s *GroupStore) Leave(groupID, userID int64) error {
	_, err := s.db.Exec(`DELETE FROM group_members WHERE group_id = ? AND user_id = ? AND role != 'owner'`, groupID, userID)
	return err
}

func (s *GroupStore) IsMember(groupID, userID int64) (bool, error) {
	var count int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM group_members WHERE group_id = ? AND user_id = ?`, groupID, userID).Scan(&count)
	return count > 0, err
}

func (s *GroupStore) ListMembers(groupID int64) ([]GroupMember, error) {
	rows, err := s.db.Query(
		`SELECT gm.group_id, gm.user_id, gm.role, gm.joined_at, u.nickname, u.avatar_url
		 FROM group_members gm JOIN users u ON gm.user_id = u.id
		 WHERE gm.group_id = ? ORDER BY gm.joined_at`, groupID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []GroupMember
	for rows.Next() {
		var m GroupMember
		if err := rows.Scan(&m.GroupID, &m.UserID, &m.Role, &m.JoinedAt, &m.Nickname, &m.AvatarURL); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	return members, rows.Err()
}

func (s *GroupStore) AddPaper(groupID, addedBy int64, subject string, year int, season, paperType, filename, downloadURL string) (*GroupPaper, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	res, err := s.db.Exec(
		`INSERT INTO group_papers (group_id, added_by, subject, year, season, paper_type, filename, download_url, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		groupID, addedBy, subject, year, season, paperType, filename, downloadURL, now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return &GroupPaper{ID: id, GroupID: groupID, AddedBy: addedBy, Subject: subject, Year: year, Season: season, PaperType: paperType, Filename: filename, DownloadURL: downloadURL, CreatedAt: now}, nil
}

func (s *GroupStore) RemovePaper(paperID, userID int64) error {
	_, err := s.db.Exec(
		`DELETE FROM group_papers WHERE id = ? AND (added_by = ? OR group_id IN (SELECT id FROM groups WHERE owner_id = ?))`,
		paperID, userID, userID,
	)
	return err
}

func (s *GroupStore) ListPapers(groupID int64) ([]GroupPaper, error) {
	rows, err := s.db.Query(
		`SELECT id, group_id, added_by, subject, year, season, paper_type, filename, download_url, created_at FROM group_papers WHERE group_id = ? ORDER BY created_at DESC`, groupID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var papers []GroupPaper
	for rows.Next() {
		var p GroupPaper
		if err := rows.Scan(&p.ID, &p.GroupID, &p.AddedBy, &p.Subject, &p.Year, &p.Season, &p.PaperType, &p.Filename, &p.DownloadURL, &p.CreatedAt); err != nil {
			return nil, err
		}
		papers = append(papers, p)
	}
	return papers, rows.Err()
}

func (s *GroupStore) UpdateProgress(groupPaperID, userID int64, status string) error {
	now := time.Now().UTC().Format(time.RFC3339)
	_, err := s.db.Exec(
		`INSERT INTO group_downloads (group_paper_id, user_id, status, updated_at) VALUES (?, ?, ?, ?)
		 ON CONFLICT(group_paper_id, user_id) DO UPDATE SET status = ?, updated_at = ?`,
		groupPaperID, userID, status, now, status, now,
	)
	return err
}

func (s *GroupStore) GetProgress(groupID int64) ([]GroupDownload, error) {
	rows, err := s.db.Query(
		`SELECT gd.group_paper_id, gd.user_id, gd.status, gd.updated_at
		 FROM group_downloads gd JOIN group_papers gp ON gd.group_paper_id = gp.id
		 WHERE gp.group_id = ?`, groupID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var downloads []GroupDownload
	for rows.Next() {
		var d GroupDownload
		if err := rows.Scan(&d.GroupPaperID, &d.UserID, &d.Status, &d.UpdatedAt); err != nil {
			return nil, err
		}
		downloads = append(downloads, d)
	}
	return downloads, rows.Err()
}
