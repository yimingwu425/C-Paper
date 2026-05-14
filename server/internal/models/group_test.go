package models

import (
	"database/sql"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func setupGroupDB(t *testing.T) *sql.DB {
	t.Helper()
	db := setupTestDB(t)
	for _, ddl := range []string{
		`CREATE TABLE IF NOT EXISTS groups (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			invite_code TEXT NOT NULL UNIQUE,
			owner_id INTEGER NOT NULL REFERENCES users(id),
			created_at TEXT NOT NULL DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS group_members (
			group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			role TEXT NOT NULL DEFAULT 'member',
			joined_at TEXT NOT NULL DEFAULT (datetime('now')),
			PRIMARY KEY (group_id, user_id)
		)`,
		`CREATE TABLE IF NOT EXISTS group_papers (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			added_by INTEGER NOT NULL REFERENCES users(id),
			subject TEXT NOT NULL,
			year INTEGER NOT NULL,
			season TEXT NOT NULL,
			paper_type TEXT NOT NULL DEFAULT '',
			filename TEXT NOT NULL,
			download_url TEXT NOT NULL DEFAULT '',
			created_at TEXT NOT NULL DEFAULT (datetime('now'))
		)`,
		`CREATE TABLE IF NOT EXISTS group_downloads (
			group_paper_id INTEGER NOT NULL REFERENCES group_papers(id) ON DELETE CASCADE,
			user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			status TEXT NOT NULL DEFAULT 'pending',
			updated_at TEXT NOT NULL DEFAULT (datetime('now')),
			PRIMARY KEY (group_paper_id, user_id)
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_invite_code ON groups(invite_code)`,
	} {
		if _, err := db.Exec(ddl); err != nil {
			t.Fatal(err)
		}
	}
	return db
}

func TestGroupStore_Create(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	group, err := groups.Create("Test Group", "A test group", "invite123", user.ID)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	if group.Name != "Test Group" {
		t.Errorf("expected name Test Group, got %s", group.Name)
	}
	if group.Description != "A test group" {
		t.Errorf("expected description 'A test group', got %s", group.Description)
	}
	if group.InviteCode != "invite123" {
		t.Errorf("expected invite_code invite123, got %s", group.InviteCode)
	}
	if group.OwnerID != user.ID {
		t.Errorf("expected owner_id %d, got %d", user.ID, group.OwnerID)
	}

	members, _ := groups.ListMembers(group.ID)
	if len(members) != 1 {
		t.Errorf("expected 1 member (owner), got %d", len(members))
	}
	if members[0].Role != "owner" {
		t.Errorf("expected role owner, got %s", members[0].Role)
	}
}

func TestGroupStore_CreateDuplicateInviteCode(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	groups.Create("Group 1", "", "invite123", user.ID)
	_, err := groups.Create("Group 2", "", "invite123", user.ID)
	if err == nil {
		t.Error("expected error for duplicate invite code")
	}
}

func TestGroupStore_GetByID(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	created, _ := groups.Create("Test Group", "", "inv1", user.ID)

	found, err := groups.GetByID(created.ID)
	if err != nil {
		t.Fatalf("GetByID failed: %v", err)
	}
	if found.Name != "Test Group" {
		t.Errorf("expected name Test Group, got %s", found.Name)
	}
}

func TestGroupStore_GetByInviteCode(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@example.com", "hash", "tester")
	groups.Create("Test Group", "", "inv1", user.ID)

	found, err := groups.GetByInviteCode("inv1")
	if err != nil {
		t.Fatalf("GetByInviteCode failed: %v", err)
	}
	if found.Name != "Test Group" {
		t.Errorf("expected name Test Group, got %s", found.Name)
	}
}

func TestGroupStore_Join(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	owner, _ := users.Create("owner@test.com", "hash", "owner")
	member, _ := users.Create("member@test.com", "hash", "member")
	group, _ := groups.Create("Test Group", "", "invite123", owner.ID)

	err := groups.Join("invite123", member.ID)
	if err != nil {
		t.Fatalf("Join failed: %v", err)
	}

	members, _ := groups.ListMembers(group.ID)
	if len(members) != 2 {
		t.Errorf("expected 2 members, got %d", len(members))
	}

	// Verify member has 'member' role
	for _, m := range members {
		if m.UserID == member.ID && m.Role != "member" {
			t.Errorf("expected role member, got %s", m.Role)
		}
	}
}

func TestGroupStore_JoinInvalidCode(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	err := groups.Join("nonexistent", user.ID)
	if err == nil {
		t.Error("expected error for invalid invite code")
	}
}

func TestGroupStore_JoinDuplicate(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	owner, _ := users.Create("owner@test.com", "hash", "owner")
	member, _ := users.Create("member@test.com", "hash", "member")
	groups.Create("Test Group", "", "inv1", owner.ID)

	groups.Join("inv1", member.ID)
	// Join again should not error (INSERT OR IGNORE)
	err := groups.Join("inv1", member.ID)
	if err != nil {
		t.Fatalf("duplicate join should not error, got: %v", err)
	}
}

func TestGroupStore_IsMember(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	owner, _ := users.Create("owner@test.com", "hash", "owner")
	group, _ := groups.Create("Test Group", "", "inv1", owner.ID)

	isMember, _ := groups.IsMember(group.ID, owner.ID)
	if !isMember {
		t.Error("owner should be a member")
	}

	isMember, _ = groups.IsMember(group.ID, 9999)
	if isMember {
		t.Error("non-member should not be a member")
	}
}

func TestGroupStore_Leave(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	owner, _ := users.Create("owner@test.com", "hash", "owner")
	member, _ := users.Create("member@test.com", "hash", "member")
	group, _ := groups.Create("Test Group", "", "inv1", owner.ID)
	groups.Join("inv1", member.ID)

	err := groups.Leave(group.ID, member.ID)
	if err != nil {
		t.Fatalf("Leave failed: %v", err)
	}

	members, _ := groups.ListMembers(group.ID)
	if len(members) != 1 {
		t.Errorf("expected 1 member after leave, got %d", len(members))
	}
}

func TestGroupStore_OwnerCannotLeave(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	owner, _ := users.Create("owner@test.com", "hash", "owner")
	group, _ := groups.Create("Test Group", "", "inv1", owner.ID)

	// Owner should not be able to leave (DELETE has AND role != 'owner')
	err := groups.Leave(group.ID, owner.ID)
	if err != nil {
		t.Fatalf("Leave should not error for owner, got: %v", err)
	}

	// Owner should still be a member
	isMember, _ := groups.IsMember(group.ID, owner.ID)
	if !isMember {
		t.Error("owner should still be a member after attempting to leave")
	}
}

func TestGroupStore_ListByUser(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	groups.Create("Group 1", "", "inv1", user.ID)
	groups.Create("Group 2", "", "inv2", user.ID)

	list, err := groups.ListByUser(user.ID)
	if err != nil {
		t.Fatalf("ListByUser failed: %v", err)
	}
	if len(list) != 2 {
		t.Errorf("expected 2 groups, got %d", len(list))
	}
}

func TestGroupStore_ListByUserEmpty(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	groups := NewGroupStore(db)

	list, err := groups.ListByUser(9999)
	if err != nil {
		t.Fatalf("ListByUser failed: %v", err)
	}
	if len(list) != 0 {
		t.Errorf("expected 0 groups, got %d", len(list))
	}
}

func TestGroupStore_AddPaper(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	group, _ := groups.Create("Test Group", "", "inv1", user.ID)

	paper, err := groups.AddPaper(group.ID, user.ID, "9709", 2023, "Jun", "qp", "paper.pdf", "https://example.com/paper.pdf")
	if err != nil {
		t.Fatalf("AddPaper failed: %v", err)
	}
	if paper.Subject != "9709" {
		t.Errorf("expected subject 9709, got %s", paper.Subject)
	}
	if paper.Filename != "paper.pdf" {
		t.Errorf("expected filename paper.pdf, got %s", paper.Filename)
	}
}

func TestGroupStore_ListPapers(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	group, _ := groups.Create("Test Group", "", "inv1", user.ID)

	groups.AddPaper(group.ID, user.ID, "9709", 2023, "Jun", "qp", "p1.pdf", "")
	groups.AddPaper(group.ID, user.ID, "9709", 2023, "Nov", "ms", "p2.pdf", "")

	papers, err := groups.ListPapers(group.ID)
	if err != nil {
		t.Fatalf("ListPapers failed: %v", err)
	}
	if len(papers) != 2 {
		t.Errorf("expected 2 papers, got %d", len(papers))
	}
}

func TestGroupStore_RemovePaper(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	group, _ := groups.Create("Test Group", "", "inv1", user.ID)

	paper, _ := groups.AddPaper(group.ID, user.ID, "9709", 2023, "Jun", "qp", "p1.pdf", "")

	err := groups.RemovePaper(paper.ID, user.ID)
	if err != nil {
		t.Fatalf("RemovePaper failed: %v", err)
	}

	papers, _ := groups.ListPapers(group.ID)
	if len(papers) != 0 {
		t.Errorf("expected 0 papers after remove, got %d", len(papers))
	}
}

func TestGroupStore_UpdateProgress(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	group, _ := groups.Create("Test Group", "", "inv1", user.ID)
	paper, _ := groups.AddPaper(group.ID, user.ID, "9709", 2023, "Jun", "qp", "p1.pdf", "")

	err := groups.UpdateProgress(paper.ID, user.ID, "done")
	if err != nil {
		t.Fatalf("UpdateProgress failed: %v", err)
	}

	progress, _ := groups.GetProgress(group.ID)
	if len(progress) != 1 {
		t.Fatalf("expected 1 progress entry, got %d", len(progress))
	}
	if progress[0].Status != "done" {
		t.Errorf("expected status done, got %s", progress[0].Status)
	}
}

func TestGroupStore_UpdateProgressUpsert(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	group, _ := groups.Create("Test Group", "", "inv1", user.ID)
	paper, _ := groups.AddPaper(group.ID, user.ID, "9709", 2023, "Jun", "qp", "p1.pdf", "")

	groups.UpdateProgress(paper.ID, user.ID, "pending")
	groups.UpdateProgress(paper.ID, user.ID, "done")

	progress, _ := groups.GetProgress(group.ID)
	if len(progress) != 1 {
		t.Fatalf("expected 1 progress entry after upsert, got %d", len(progress))
	}
	if progress[0].Status != "done" {
		t.Errorf("expected status done after upsert, got %s", progress[0].Status)
	}
}

func TestGroupStore_GetProgressEmpty(t *testing.T) {
	db := setupGroupDB(t)
	defer db.Close()
	users := NewUserStore(db)
	groups := NewGroupStore(db)

	user, _ := users.Create("test@test.com", "hash", "t")
	group, _ := groups.Create("Test Group", "", "inv1", user.ID)

	progress, err := groups.GetProgress(group.ID)
	if err != nil {
		t.Fatalf("GetProgress failed: %v", err)
	}
	if len(progress) != 0 {
		t.Errorf("expected 0 progress entries, got %d", len(progress))
	}
}
