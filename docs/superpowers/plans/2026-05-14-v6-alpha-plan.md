# C-Paper v6.0-alpha Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Do one step at a time. Do not skip ahead. Verify each step before moving on.**

**Goal:** Build the collaborative server (Go + SQLite + chi) and integrate it with the desktop client (Python + JS), enabling user accounts, paper sharing, learning groups, and paper reviews.

**Architecture:**
- **Server (Go):** REST API using chi router, SQLite via mattn/go-sqlite3, bcrypt passwords, JWT auth, SSE for group progress, rate limiting middleware
- **Desktop integration (Python):** `collab_client.py` HTTP client, `api.py` bridge methods exposing server calls to JS
- **Desktop integration (JS/CSS/HTML):** Login modal, share dialog, group panel, review section in the existing three-column UI

**Tech Stack:** Go 1.22+, chi v5, mattn/go-sqlite3, golang-jwt/jwt/v5, bcrypt, chi/cors. Python 3.11+, requests. Vanilla JS, CSS3. SQLite 3. Docker for deployment.

---

## Key Design Decisions

1. **Zero-framework Go:** Only chi router. No ORM. Raw SQL with parameterized queries.
2. **Password auth before OAuth:** Implement email+password register/login first. OAuth stubs for Apple/Lark to be filled later.
3. **SSE not WebSocket:** Groups use SSE for real-time progress updates. Simpler, HTTP-native, no upgrade overhead.
4. **Client-side token storage:** JWT stored in Python config file (`~/.cie_cache/collab_config.json`), not localStorage, so it persists across sessions.
5. **RLM (Rate Limit Middleware):** Token-bucket per IP, 60 req/min general, 5 req/min for auth endpoints.
6. **Share codes are short random strings:** 8-char alphanumeric, no meaning, collision-checked before insert.
7. **One review per user per paper tuple:** (subject, year, season, paper_type) enforced by UNIQUE constraint.
8. **SSE broker pattern:** Each group gets a goroutine with a channel fan-out. In-memory, no Redis needed for free-tier scale.

---

## File Structure

| File | Responsibility | Operation |
|---|---|---|
| `server/go.mod` | Go module definition | **Create** |
| `server/go.sum` | Dependency hashes | Auto-generated |
| `server/cmd/main.go` | Entry point: config, wire routes, start | **Create** |
| `server/db/db.go` | SQLite connection, migrations, helpers | **Create** |
| `server/db/migrations.go` | Schema up/down migrations | **Create** |
| `server/auth/handler.go` | Register, login, refresh, me endpoints | **Create** |
| `server/auth/jwt.go` | JWT sign/verify, middleware helper | **Create** |
| `server/auth/model.go` | User model, request/response types | **Create** |
| `server/auth/store.go` | User CRUD against SQLite | **Create** |
| `server/middleware/auth.go` | JWT extraction, user context injection | **Create** |
| `server/middleware/ratelimit.go` | Token-bucket per-IP rate limiter | **Create** |
| `server/middleware/cors.go` | CORS wrapper around chi/cors | **Create** |
| `server/share/handler.go` | Share CRUD HTTP handlers | **Create** |
| `server/share/model.go` | Share model, request/response types | **Create** |
| `server/share/store.go` | Share CRUD against SQLite | **Create** |
| `server/group/handler.go` | Group CRUD + SSE HTTP handlers | **Create** |
| `server/group/model.go` | Group/member/paper/download models | **Create** |
| `server/group/store.go` | Group CRUD against SQLite | **Create** |
| `server/group/sse.go` | SSE broker: subscribe, broadcast, unsubscribe | **Create** |
| `server/review/handler.go` | Review CRUD HTTP handlers | **Create** |
| `server/review/model.go` | Review model, request/response types | **Create** |
| `server/review/store.go` | Review CRUD against SQLite | **Create** |
| `server/Dockerfile` | Multi-stage Docker build | **Create** |
| `server/fly.toml` | Fly.io deployment config | **Create** |
| `server/auth/handler_test.go` | Auth integration tests | **Create** |
| `server/share/handler_test.go` | Share integration tests | **Create** |
| `server/group/handler_test.go` | Group integration tests | **Create** |
| `server/review/handler_test.go` | Review integration tests | **Create** |
| `src/backend/collab_client.py` | Python HTTP client for server API | **Create** |
| `src/backend/api.py` | Add collab methods to JS bridge | **Modify** |
| `src/backend/const.py` | Add SERVER_BASE_URL constant | **Modify** |
| `src/ui_v2.html` | Login modal, share dialog, group panel, review section | **Modify** |
| `src/ui_v2.js` | Login/share/group/review JS logic | **Modify** |
| `src/ui_v2.css` | New UI component styles | **Modify** |
| `tests/test_collab_client.py` | Python client unit tests | **Create** |


---

## Task 1: Project Scaffold (Go module + directory structure)

**Files:**
- Create: `server/go.mod`
- Create: `server/.gitignore`

- [ ] **Step 1: Create server directory structure**

```bash
mkdir -p server/cmd server/db server/auth server/share server/group server/review server/middleware
```

Expected output: (none, directories created)

- [ ] **Step 2: Initialize Go module**

```bash
cd server && go mod init github.com/Ja-son-WU/C-Paper/server && go mod tidy
```

Expected output: `go: creating new go.mod: module github.com/Ja-son-WU/C-Paper/server`

- [ ] **Step 3: Add chi router dependency**

```bash
cd server && go get github.com/go-chi/chi/v5 && go mod tidy
```

Expected output: `go: added github.com/go-chi/chi/v5 v5.x.x`

- [ ] **Step 4: Add SQLite dependency**

```bash
cd server && go get github.com/mattn/go-sqlite3 && go mod tidy
```

Expected output: `go: added github.com/mattn/go-sqlite3 v1.14.x`

- [ ] **Step 5: Add JWT dependency**

```bash
cd server && go get github.com/golang-jwt/jwt/v5 && go mod tidy
```

Expected output: `go: added github.com/golang-jwt/jwt/v5 v5.x.x`

- [ ] **Step 6: Add bcrypt dependency**

```bash
cd server && go get golang.org/x/crypto/bcrypt && go mod tidy
```

Expected output: `go: added golang.org/x/crypto v0.x.x`

- [ ] **Step 7: Add CORS dependency**

```bash
cd server && go get github.com/go-chi/cors && go mod tidy
```

Expected output: `go: added github.com/go-chi/cors v1.x.x`

- [ ] **Step 8: Create server/.gitignore**

```bash
cat > server/.gitignore << 'EOF'
# Binaries
server
*.exe
*.test
*.out

# Database
*.db
*.db-journal
*.db-wal
*.db-shm

# Environment
.env
EOF
```

Expected output: (none)

- [ ] **Step 9: Commit**

```bash
git add server/go.mod server/go.sum server/.gitignore
git commit -m "chore: scaffold Go module and dependencies for collaborative server"
```

---

## Task 2: Database Layer (SQLite connection + schema migrations)

**Files:**
- Create: `server/db/db.go`
- Create: `server/db/migrations.go`

### Step 1 (TDD): Write a test for database connection and migrations

Create `server/db/db_test.go`:

```go
package db

import (
	"database/sql"
	"os"
	"testing"
)

func TestOpenAndMigrate(t *testing.T) {
	path := "/tmp/test_cpaper_v6.db"
	os.Remove(path)
	defer os.Remove(path)

	db, err := Open(path)
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer db.Close()

	if err := Migrate(db); err != nil {
		t.Fatalf("Migrate() error = %v", err)
	}

	// Verify tables exist
	tables := []string{"users", "shares", "groups", "group_members", "group_papers", "group_downloads", "reviews", "review_reactions"}
	for _, table := range tables {
		var name string
		err := db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&name)
		if err != nil {
			t.Errorf("table %s not found: %v", table, err)
		}
		if name != table {
			t.Errorf("expected table name %s, got %s", table, name)
		}
	}

	// Verify users table columns
	rows, err := db.Query("PRAGMA table_info(users)")
	if err != nil {
		t.Fatalf("PRAGMA table_info(users) error = %v", err)
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, typ string
		var notNull int
		var dflt sql.NullString
		var pk int
		if err := rows.Scan(&cid, &name, &typ, &notNull, &dflt, &pk); err != nil {
			t.Fatalf("scan error = %v", err)
		}
		cols[name] = true
	}
	required := []string{"id", "email", "password_hash", "nickname", "avatar_url", "oauth_provider", "oauth_id", "created_at", "updated_at"}
	for _, c := range required {
		if !cols[c] {
			t.Errorf("users table missing column %s", c)
		}
	}
}
```

### Step 2: Run the test, expect failure

```bash
cd server && go test ./db/ -v -run TestOpenAndMigrate 2>&1
```

Expected: compilation error or test failure because `Open` and `Migrate` do not exist yet.

### Step 3: Implement `server/db/db.go`

```go
package db

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	_ "github.com/mattn/go-sqlite3"
)

// Open opens (or creates) the SQLite database at the given path.
// It ensures the parent directory exists and enables WAL mode for concurrency.
func Open(path string) (*sql.DB, error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("mkdir %s: %w", dir, err)
	}

	db, err := sql.Open("sqlite3", path+"?_journal_mode=WAL&_foreign_keys=on&_busy_timeout=5000")
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}

	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}

	db.SetMaxOpenConns(1) // SQLite is single-writer
	return db, nil
}
```

- [ ] **Step 4: Run the test, expect "Migrate undefined" error**

```bash
cd server && go test ./db/ -v -run TestOpenAndMigrate 2>&1
```

Expected: compile error — `undefined: Migrate`

- [ ] **Step 5: Implement `server/db/migrations.go`**

```go
package db

import (
	"database/sql"
	"fmt"
	"log"
)

// Migrate applies all schema migrations. Idempotent — safe to call on every startup.
func Migrate(db *sql.DB) error {
	migrations := []struct {
		name string
		sql  string
	}{
		{
			name: "001_users",
			sql: `CREATE TABLE IF NOT EXISTS users (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				email TEXT NOT NULL UNIQUE,
				password_hash TEXT NOT NULL DEFAULT '',
				nickname TEXT NOT NULL DEFAULT '',
				avatar_url TEXT NOT NULL DEFAULT '',
				oauth_provider TEXT NOT NULL DEFAULT '',
				oauth_id TEXT NOT NULL DEFAULT '',
				created_at TEXT NOT NULL DEFAULT (datetime('now')),
				updated_at TEXT NOT NULL DEFAULT (datetime('now'))
			)`,
		},
		{
			name: "002_shares",
			sql: `CREATE TABLE IF NOT EXISTS shares (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				user_id INTEGER NOT NULL,
				code TEXT NOT NULL UNIQUE,
				subject TEXT NOT NULL,
				year INTEGER NOT NULL,
				season TEXT NOT NULL,
				paper_type TEXT NOT NULL DEFAULT '',
				expires_at TEXT NOT NULL,
				view_count INTEGER NOT NULL DEFAULT 0,
				created_at TEXT NOT NULL DEFAULT (datetime('now')),
				FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
			)`,
		},
		{
			name: "002b_shares_index",
			sql:  `CREATE INDEX IF NOT EXISTS idx_shares_code ON shares(code)`,
		},
		{
			name: "003_groups",
			sql: `CREATE TABLE IF NOT EXISTS groups_table (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				name TEXT NOT NULL,
				description TEXT NOT NULL DEFAULT '',
				invite_code TEXT NOT NULL UNIQUE,
				owner_id INTEGER NOT NULL,
				created_at TEXT NOT NULL DEFAULT (datetime('now')),
				FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
			)`,
		},
		{
			name: "004_group_members",
			sql: `CREATE TABLE IF NOT EXISTS group_members (
				group_id INTEGER NOT NULL,
				user_id INTEGER NOT NULL,
				role TEXT NOT NULL DEFAULT 'member',
				joined_at TEXT NOT NULL DEFAULT (datetime('now')),
				PRIMARY KEY (group_id, user_id),
				FOREIGN KEY (group_id) REFERENCES groups_table(id) ON DELETE CASCADE,
				FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
			)`,
		},
		{
			name: "005_group_papers",
			sql: `CREATE TABLE IF NOT EXISTS group_papers (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				group_id INTEGER NOT NULL,
				added_by INTEGER NOT NULL,
				subject TEXT NOT NULL,
				year INTEGER NOT NULL,
				season TEXT NOT NULL,
				paper_type TEXT NOT NULL DEFAULT '',
				filename TEXT NOT NULL,
				download_url TEXT NOT NULL DEFAULT '',
				created_at TEXT NOT NULL DEFAULT (datetime('now')),
				FOREIGN KEY (group_id) REFERENCES groups_table(id) ON DELETE CASCADE,
				FOREIGN KEY (added_by) REFERENCES users(id)
			)`,
		},
		{
			name: "006_group_downloads",
			sql: `CREATE TABLE IF NOT EXISTS group_downloads (
				group_paper_id INTEGER NOT NULL,
				user_id INTEGER NOT NULL,
				status TEXT NOT NULL DEFAULT 'pending',
				updated_at TEXT NOT NULL DEFAULT (datetime('now')),
				PRIMARY KEY (group_paper_id, user_id),
				FOREIGN KEY (group_paper_id) REFERENCES group_papers(id) ON DELETE CASCADE,
				FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
			)`,
		},
		{
			name: "007_reviews",
			sql: `CREATE TABLE IF NOT EXISTS reviews (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				user_id INTEGER NOT NULL,
				subject TEXT NOT NULL,
				year INTEGER NOT NULL,
				season TEXT NOT NULL,
				paper_type TEXT NOT NULL DEFAULT '',
				filename TEXT NOT NULL DEFAULT '',
				rating INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 5),
				difficulty INTEGER NOT NULL CHECK(difficulty >= 1 AND difficulty <= 5),
				tags TEXT NOT NULL DEFAULT '[]',
				comment TEXT NOT NULL DEFAULT '',
				created_at TEXT NOT NULL DEFAULT (datetime('now')),
				FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
				UNIQUE(user_id, subject, year, season, paper_type)
			)`,
		},
		{
			name: "008_review_reactions",
			sql: `CREATE TABLE IF NOT EXISTS review_reactions (
				review_id INTEGER NOT NULL,
				user_id INTEGER NOT NULL,
				reaction TEXT NOT NULL,
				PRIMARY KEY (review_id, user_id, reaction),
				FOREIGN KEY (review_id) REFERENCES reviews(id) ON DELETE CASCADE,
				FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
			)`,
		},
	}

	for _, m := range migrations {
		if _, err := db.Exec(m.sql); err != nil {
			return fmt.Errorf("migration %s: %w", m.name, err)
		}
	}
	log.Printf("Database migrated: %d migrations applied", len(migrations))
	return nil
}
```

- [ ] **Step 6: Run the test, expect pass**

```bash
cd server && go test ./db/ -v -run TestOpenAndMigrate 2>&1
```

Expected output: `PASS`, `ok  github.com/Ja-son-WU/C-Paper/server/db  ...`

- [ ] **Step 7: Commit**

```bash
git add server/db/
git commit -m "feat(db): add SQLite connection helper and schema migrations"
```

---

## Task 3: Auth Package (register, login, JWT)

**Files:**
- Create: `server/auth/model.go`
- Create: `server/auth/jwt.go`
- Create: `server/auth/store.go`
- Create: `server/auth/handler.go`
- Create: `server/auth/handler_test.go`


### Step 1 (TDD): Write auth handler test

Create `server/auth/handler_test.go`:

```go
package auth

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Ja-son-WU/C-Paper/server/db"
)

func setupAuthTest(t *testing.T) (*Handler, func()) {
	t.Helper()
	database, err := db.Open("/tmp/test_cpaper_auth.db")
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	if err := db.Migrate(database); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	// Clear users table
	database.Exec("DELETE FROM users")
	store := NewStore(database)
	jwtSecret := []byte("test-secret-key-for-testing-only")
	handler := NewHandler(store, jwtSecret)
	cleanup := func() {
		database.Exec("DELETE FROM users")
		database.Close()
	}
	return handler, cleanup
}

func TestRegisterAndLogin(t *testing.T) {
	h, cleanup := setupAuthTest(t)
	defer cleanup()

	// Step A: Register
	regBody := map[string]string{
		"email":    "test@example.com",
		"password": "securepass123",
		"nickname": "Tester",
	}
	regJSON, _ := json.Marshal(regBody)
	regReq := httptest.NewRequest("POST", "/api/auth/register", bytes.NewReader(regJSON))
	regReq.Header.Set("Content-Type", "application/json")
	regRec := httptest.NewRecorder()
	h.Register(regRec, regReq)

	if regRec.Code != http.StatusCreated {
		t.Fatalf("register status = %d, want 201, body: %s", regRec.Code, regRec.Body.String())
	}

	var regResp map[string]interface{}
	json.Unmarshal(regRec.Body.Bytes(), &regResp)
	if regResp["token"] == nil || regResp["token"] == "" {
		t.Fatal("register response missing token")
	}
	if regResp["user"] == nil {
		t.Fatal("register response missing user")
	}

	// Step B: Duplicate registration should fail
	regReq2 := httptest.NewRequest("POST", "/api/auth/register", bytes.NewReader(regJSON))
	regReq2.Header.Set("Content-Type", "application/json")
	regRec2 := httptest.NewRecorder()
	h.Register(regRec2, regReq2)
	if regRec2.Code != http.StatusConflict {
		t.Fatalf("duplicate register status = %d, want 409", regRec2.Code)
	}

	// Step C: Login with correct password
	loginBody := map[string]string{
		"email":    "test@example.com",
		"password": "securepass123",
	}
	loginJSON, _ := json.Marshal(loginBody)
	loginReq := httptest.NewRequest("POST", "/api/auth/login", bytes.NewReader(loginJSON))
	loginReq.Header.Set("Content-Type", "application/json")
	loginRec := httptest.NewRecorder()
	h.Login(loginRec, loginReq)

	if loginRec.Code != http.StatusOK {
		t.Fatalf("login status = %d, want 200, body: %s", loginRec.Code, loginRec.Body.String())
	}

	var loginResp map[string]interface{}
	json.Unmarshal(loginRec.Body.Bytes(), &loginResp)
	if loginResp["token"] == nil {
		t.Fatal("login response missing token")
	}

	// Step D: Login with wrong password should fail
	badBody := map[string]string{
		"email":    "test@example.com",
		"password": "wrongpassword",
	}
	badJSON, _ := json.Marshal(badBody)
	badReq := httptest.NewRequest("POST", "/api/auth/login", bytes.NewReader(badJSON))
	badReq.Header.Set("Content-Type", "application/json")
	badRec := httptest.NewRecorder()
	h.Login(badRec, badReq)
	if badRec.Code != http.StatusUnauthorized {
		t.Fatalf("bad login status = %d, want 401", badRec.Code)
	}
}

func TestRegisterValidation(t *testing.T) {
	h, cleanup := setupAuthTest(t)
	defer cleanup()

	tests := []struct {
		name       string
		body       map[string]string
		wantStatus int
	}{
		{"empty email", map[string]string{"email": "", "password": "pass123"}, http.StatusBadRequest},
		{"invalid email", map[string]string{"email": "notanemail", "password": "pass123"}, http.StatusBadRequest},
		{"short password", map[string]string{"email": "a@b.com", "password": "12"}, http.StatusBadRequest},
		{"missing password", map[string]string{"email": "a@b.com", "password": ""}, http.StatusBadRequest},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bodyJSON, _ := json.Marshal(tt.body)
			req := httptest.NewRequest("POST", "/api/auth/register", bytes.NewReader(bodyJSON))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			h.Register(rec, req)
			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d, body: %s", rec.Code, tt.wantStatus, rec.Body.String())
			}
		})
	}
}

func TestMeEndpoint(t *testing.T) {
	h, cleanup := setupAuthTest(t)
	defer cleanup()

	// Register first
	regBody := map[string]string{"email": "me@example.com", "password": "pass123456", "nickname": "MeUser"}
	regJSON, _ := json.Marshal(regBody)
	regReq := httptest.NewRequest("POST", "/api/auth/register", bytes.NewReader(regJSON))
	regReq.Header.Set("Content-Type", "application/json")
	regRec := httptest.NewRecorder()
	h.Register(regRec, regReq)

	var regResp map[string]interface{}
	json.Unmarshal(regRec.Body.Bytes(), &regResp)
	token := regResp["token"].(string)

	// Call /api/me with token
	meReq := httptest.NewRequest("GET", "/api/me", nil)
	meReq.Header.Set("Authorization", "Bearer "+token)
	meRec := httptest.NewRecorder()
	h.Me(meRec, meReq)

	if meRec.Code != http.StatusOK {
		t.Fatalf("me status = %d, want 200, body: %s", meRec.Code, meRec.Body.String())
	}
	var meResp map[string]interface{}
	json.Unmarshal(meRec.Body.Bytes(), &meResp)
	user, ok := meResp["user"].(map[string]interface{})
	if !ok {
		t.Fatal("me response missing user object")
	}
	if user["email"] != "me@example.com" {
		t.Errorf("email = %v, want me@example.com", user["email"])
	}

	// Call /api/me without token
	badReq := httptest.NewRequest("GET", "/api/me", nil)
	badRec := httptest.NewRecorder()
	h.Me(badRec, badReq)
	if badRec.Code != http.StatusUnauthorized {
		t.Errorf("unauthorized me status = %d, want 401", badRec.Code)
	}
}
```

### Step 2: Run the test, expect compilation failure

```bash
cd server && go test ./auth/ -v -run TestRegisterAndLogin 2>&1
```

Expected: `undefined: NewStore`, `undefined: NewHandler`, etc.

### Step 3: Implement `server/auth/model.go`

```go
package auth

import "time"

// User represents a registered user.
type User struct {
	ID            int64     `json:"id"`
	Email         string    `json:"email"`
	PasswordHash  string    `json:"-"`
	Nickname      string    `json:"nickname"`
	AvatarURL     string    `json:"avatar_url"`
	OAuthProvider string    `json:"oauth_provider,omitempty"`
	OAuthID       string    `json:"oauth_id,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// RegisterRequest is the JSON body for POST /api/auth/register.
type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Nickname string `json:"nickname,omitempty"`
}

// LoginRequest is the JSON body for POST /api/auth/login.
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// AuthResponse is the JSON body returned on successful auth.
type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

// ErrorResponse is a generic JSON error body.
type ErrorResponse struct {
	Error string `json:"error"`
}
```

### Step 4: Implement `server/auth/jwt.go`

```go
package auth

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// TokenClaims represents the JWT payload.
type TokenClaims struct {
	UserID int64  `json:"user_id"`
	Email  string `json:"email"`
	jwt.RegisteredClaims
}

// GenerateToken creates a signed JWT string valid for 7 days.
func GenerateToken(userID int64, email string, secret []byte) (string, error) {
	claims := TokenClaims{
		UserID: userID,
		Email:  email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(7 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "c-paper",
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secret)
}

// VerifyToken parses and validates a JWT string, returning the claims.
func VerifyToken(tokenStr string, secret []byte) (*TokenClaims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &TokenClaims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return secret, nil
	})
	if err != nil {
		return nil, fmt.Errorf("parse token: %w", err)
	}
	claims, ok := token.Claims.(*TokenClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return claims, nil
}
```

### Step 5: Implement `server/auth/store.go`

```go
package auth

import (
	"database/sql"
	"fmt"
	"strings"
)

// Store provides database access for user operations.
type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

// CreateUser inserts a new user and returns the created user with ID.
func (s *Store) CreateUser(email, passwordHash, nickname string) (*User, error) {
	result, err := s.db.Exec(
		"INSERT INTO users (email, password_hash, nickname) VALUES (?, ?, ?)",
		email, passwordHash, nickname,
	)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return nil, fmt.Errorf("email already registered")
		}
		return nil, fmt.Errorf("insert user: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}
	return s.GetUserByID(id)
}

// GetUserByEmail returns a user by email, or nil if not found.
func (s *Store) GetUserByEmail(email string) (*User, error) {
	user := &User{}
	var createdAt, updatedAt string
	err := s.db.QueryRow(
		"SELECT id, email, password_hash, nickname, avatar_url, oauth_provider, oauth_id, created_at, updated_at FROM users WHERE email = ?",
		email,
	).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.Nickname,
		&user.AvatarURL, &user.OAuthProvider, &user.OAuthID, &createdAt, &updatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user by email: %w", err)
	}
	user.CreatedAt, _ = parseTime(createdAt)
	user.UpdatedAt, _ = parseTime(updatedAt)
	return user, nil
}

// GetUserByID returns a user by ID, or nil if not found.
func (s *Store) GetUserByID(id int64) (*User, error) {
	user := &User{}
	var createdAt, updatedAt string
	err := s.db.QueryRow(
		"SELECT id, email, password_hash, nickname, avatar_url, oauth_provider, oauth_id, created_at, updated_at FROM users WHERE id = ?",
		id,
	).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.Nickname,
		&user.AvatarURL, &user.OAuthProvider, &user.OAuthID, &createdAt, &updatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user by id: %w", err)
	}
	user.CreatedAt, _ = parseTime(createdAt)
	user.UpdatedAt, _ = parseTime(updatedAt)
	return user, nil
}

func parseTime(s string) (t interface{}, err error) {
	// return as-is string for now; callers can parse if needed
	return s, nil
}
```

Wait — let me retain proper time parsing. Change `parseTime` to a real implementation:

```go
import "time"

func parseTime(s string) (time.Time, error) {
	return time.Parse("2006-01-02 15:04:05", s)
}
```

Note: In the actual implementation, include `"time"` in the imports and remove the placeholder parseTime above.

### Step 6: Implement `server/auth/handler.go`

```go
package auth

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

// Handler contains HTTP handlers for auth endpoints.
type Handler struct {
	store     *Store
	jwtSecret []byte
}

func NewHandler(store *Store, jwtSecret []byte) *Handler {
	return &Handler{store: store, jwtSecret: jwtSecret}
}

var emailRE = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

// Register handles POST /api/auth/register.
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))

	if !emailRE.MatchString(req.Email) {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid email format"})
		return
	}
	if len(req.Password) < 6 {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "password must be at least 6 characters"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to hash password"})
		return
	}

	nickname := req.Nickname
	if nickname == "" {
		nickname = strings.Split(req.Email, "@")[0]
	}

	user, err := h.store.CreateUser(req.Email, string(hash), nickname)
	if err != nil {
		if strings.Contains(err.Error(), "already registered") {
			writeJSON(w, http.StatusConflict, ErrorResponse{Error: "email already registered"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to create user"})
		return
	}

	token, err := GenerateToken(user.ID, user.Email, h.jwtSecret)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to generate token"})
		return
	}

	writeJSON(w, http.StatusCreated, AuthResponse{Token: token, User: *user})
}

// Login handles POST /api/auth/login.
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))

	user, err := h.store.GetUserByEmail(req.Email)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "internal error"})
		return
	}
	if user == nil {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "invalid email or password"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "invalid email or password"})
		return
	}

	token, err := GenerateToken(user.ID, user.Email, h.jwtSecret)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to generate token"})
		return
	}

	writeJSON(w, http.StatusOK, AuthResponse{Token: token, User: *user})
}

// Me handles GET /api/me. It expects the user ID to be set in the request context
// by the auth middleware.
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(UserIDKey).(int64)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "unauthorized"})
		return
	}
	user, err := h.store.GetUserByID(userID)
	if err != nil || user == nil {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "user not found"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"user": user})
}

// UserIDKey is the context key for the authenticated user ID.
type contextKey string

var UserIDKey contextKey = "user_id"

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
```

### Step 7: Run the test, expect pass

```bash
cd server && go test ./auth/ -v 2>&1
```

Expected output: all tests `PASS`

### Step 8: Commit

```bash
git add server/auth/
git commit -m "feat(auth): register, login, JWT token generation and verification"
```

---

## Task 4: Middleware (JWT auth, rate limit, CORS)

**Files:**
- Create: `server/middleware/auth.go`
- Create: `server/middleware/ratelimit.go`
- Create: `server/middleware/cors.go`


### Step 1 (TDD): Write middleware tests

Create `server/middleware/middleware_test.go`:

```go
package middleware

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/Ja-son-WU/C-Paper/server/auth"
)

func TestJWTAuthMiddleware(t *testing.T) {
	secret := []byte("test-secret")
	token, err := auth.GenerateToken(42, "user@test.com", secret)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	// Test with valid token
	handler := JWTAuth(secret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID, ok := r.Context().Value(auth.UserIDKey).(int64)
		if !ok {
			t.Error("user_id not in context")
			return
		}
		if userID != 42 {
			t.Errorf("user_id = %d, want 42", userID)
		}
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", rec.Code)
	}

	// Test without token
	req2 := httptest.NewRequest("GET", "/test", nil)
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusUnauthorized {
		t.Errorf("no-token status = %d, want 401", rec2.Code)
	}

	// Test with invalid token
	req3 := httptest.NewRequest("GET", "/test", nil)
	req3.Header.Set("Authorization", "Bearer invalid.token.here")
	rec3 := httptest.NewRecorder()
	handler.ServeHTTP(rec3, req3)
	if rec3.Code != http.StatusUnauthorized {
		t.Errorf("bad-token status = %d, want 401", rec3.Code)
	}
}

func TestRateLimitMiddleware(t *testing.T) {
	limiter := NewRateLimiter(3, time.Second) // 3 requests per second
	handler := RateLimit(limiter)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	// First 3 requests should pass
	for i := 0; i < 3; i++ {
		req := httptest.NewRequest("GET", "/test", nil)
		req.RemoteAddr = "192.168.1.1:12345"
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("request %d: status = %d, want 200", i+1, rec.Code)
		}
	}

	// 4th request should be rate limited
	req := httptest.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "192.168.1.1:12345"
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Errorf("rate-limited status = %d, want 429", rec.Code)
	}

	// Different IP should not be limited
	req2 := httptest.NewRequest("GET", "/test", nil)
	req2.RemoteAddr = "10.0.0.2:54321"
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Errorf("different-IP status = %d, want 200", rec2.Code)
	}
}

func TestRateLimitCleanup(t *testing.T) {
	limiter := NewRateLimiter(1, 50*time.Millisecond)
	handler := RateLimit(limiter)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	// Use up the token
	req := httptest.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "10.0.0.1:12345"
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("first request status = %d", rec.Code)
	}

	limiter.mu.RLock()
	bucketCount := len(limiter.buckets)
	limiter.mu.RUnlock()
	if bucketCount != 1 {
		t.Errorf("expected 1 bucket, got %d", bucketCount)
	}

	// Wait for cleanup
	time.Sleep(100 * time.Millisecond)
	limiter.cleanup()

	limiter.mu.RLock()
	bucketCount = len(limiter.buckets)
	limiter.mu.RUnlock()
	if bucketCount != 0 {
		t.Errorf("after cleanup: expected 0 buckets, got %d", bucketCount)
	}
}
```

### Step 2: Run the test, expect failure

```bash
cd server && go test ./middleware/ -v 2>&1
```

Expected: compilation error, `JWTAuth`, `NewRateLimiter`, `RateLimit` undefined.

### Step 3: Implement `server/middleware/auth.go`

```go
package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/Ja-son-WU/C-Paper/server/auth"
)

// JWTAuth returns middleware that extracts and verifies JWT tokens
// from the Authorization header, injecting the user ID into the request context.
func JWTAuth(secret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if header == "" || !strings.HasPrefix(header, "Bearer ") {
				http.Error(w, `{"error":"missing authorization header"}`, http.StatusUnauthorized)
				return
			}
			tokenStr := strings.TrimPrefix(header, "Bearer ")
			claims, err := auth.VerifyToken(tokenStr, secret)
			if err != nil {
				http.Error(w, `{"error":"invalid or expired token"}`, http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), auth.UserIDKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
```

### Step 4: Implement `server/middleware/ratelimit.go`

```go
package middleware

import (
	"net/http"
	"sync"
	"time"
)

// RateLimiter implements a per-IP token bucket rate limiter.
type RateLimiter struct {
	rate      int
	window    time.Duration
	mu        sync.RWMutex
	buckets   map[string]*tokenBucket
	cleanupAt time.Time
}

type tokenBucket struct {
	tokens   int
	lastFill time.Time
}

// NewRateLimiter creates a rate limiter with the given rate per window.
func NewRateLimiter(rate int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		rate:      rate,
		window:    window,
		buckets:   make(map[string]*tokenBucket),
		cleanupAt: time.Now().Add(5 * time.Minute),
	}
}

func (rl *RateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	bucket, exists := rl.buckets[ip]
	now := time.Now()

	if !exists {
		rl.buckets[ip] = &tokenBucket{tokens: rl.rate - 1, lastFill: now}
		return true
	}

	// Refill tokens based on elapsed time
	elapsed := now.Sub(bucket.lastFill)
	refill := int(float64(elapsed) / float64(rl.window) * float64(rl.rate))
	if refill > 0 {
		bucket.tokens += refill
		if bucket.tokens > rl.rate {
			bucket.tokens = rl.rate
		}
		bucket.lastFill = now
	}

	if bucket.tokens > 0 {
		bucket.tokens--
		return true
	}
	return false
}

func (rl *RateLimiter) cleanup() {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	now := time.Now()
	if now.Before(rl.cleanupAt) {
		return
	}
	for ip, bucket := range rl.buckets {
		if now.Sub(bucket.lastFill) > 5*time.Minute {
			delete(rl.buckets, ip)
		}
	}
	rl.cleanupAt = now.Add(5 * time.Minute)
}

// RateLimit returns middleware that rate-limits requests per IP.
func RateLimit(limiter *RateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := extractIP(r.RemoteAddr)
			if !limiter.allow(ip) {
				w.Header().Set("Retry-After", "60")
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				w.Write([]byte(`{"error":"rate limit exceeded"}`))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func extractIP(addr string) string {
	// addr is "ip:port". Strip the port.
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[:i]
		}
	}
	return addr
}
```

### Step 5: Implement `server/middleware/cors.go`

```go
package middleware

import (
	"net/http"

	"github.com/go-chi/cors"
)

// CORS returns a CORS middleware handler configured for the C-Paper client.
// This is a thin wrapper around chi/cors.
func CORS(allowedOrigins []string) func(http.Handler) http.Handler {
	return cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Requested-With"},
		ExposedHeaders:   []string{"Link", "X-Total-Count"},
		AllowCredentials: true,
		MaxAge:           300,
	})
}
```

### Step 6: Run the test, expect pass

```bash
cd server && go test ./middleware/ -v 2>&1
```

Expected output: all tests `PASS`

### Step 7: Commit

```bash
git add server/middleware/
git commit -m "feat(middleware): JWT auth, rate limiting, and CORS middleware"
```

---

## Task 5: Share Package (create, get, delete, list)

**Files:**
- Create: `server/share/model.go`
- Create: `server/share/store.go`
- Create: `server/share/handler.go`
- Create: `server/share/handler_test.go`


### Step 1 (TDD): Write share handler test

Create `server/share/handler_test.go`:

```go
package share

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Ja-son-WU/C-Paper/server/auth"
	"github.com/Ja-son-WU/C-Paper/server/db"
	"github.com/go-chi/chi/v5"
)

func setupShareTest(t *testing.T) (*Handler, *sql.DB, func()) {
	t.Helper()
	database, err := db.Open("/tmp/test_cpaper_share.db")
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	if err := db.Migrate(database); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	database.Exec("DELETE FROM shares")
	database.Exec("DELETE FROM users")

	store := NewStore(database)
	handler := NewHandler(store)

	// Create a test user directly
	database.Exec("INSERT INTO users (id, email, password_hash, nickname) VALUES (1, 'test@test.com', 'hash', 'Test')")

	cleanup := func() {
		database.Exec("DELETE FROM shares")
		database.Exec("DELETE FROM users")
		database.Close()
	}
	return handler, database, cleanup
}

func authRequest(method, path, token string, body interface{}) *http.Request {
	var r *http.Request
	if body != nil {
		b, _ := json.Marshal(body)
		r = httptest.NewRequest(method, path, bytes.NewReader(b))
	} else {
		r = httptest.NewRequest(method, path, nil)
	}
	r.Header.Set("Content-Type", "application/json")
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	// Inject user_id into context for testing (mimics auth middleware)
	ctx := context.WithValue(r.Context(), auth.UserIDKey, int64(1))
	return r.WithContext(ctx)
}

func TestCreateShare(t *testing.T) {
	h, _, cleanup := setupShareTest(t)
	defer cleanup()

	body := CreateShareRequest{
		Subject:   "9709",
		Year:      2023,
		Season:    "Summer",
		PaperType: "12",
		ExpiresIn: 7,
	}

	req := authRequest("POST", "/api/share", "", body)
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("create status = %d, want 201, body: %s", rec.Code, rec.Body.String())
	}

	var resp ShareResponse
	json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Code == "" {
		t.Fatal("share code is empty")
	}
	if len(resp.Code) != 8 {
		t.Errorf("share code length = %d, want 8", len(resp.Code))
	}
	if resp.Subject != "9709" {
		t.Errorf("subject = %s, want 9709", resp.Subject)
	}
}

func TestGetShare(t *testing.T) {
	h, _, cleanup := setupShareTest(t)
	defer cleanup()

	// Create a share first
	body := CreateShareRequest{
		Subject:   "9709",
		Year:      2023,
		Season:    "Summer",
		PaperType: "12",
		ExpiresIn: 7,
	}
	req := authRequest("POST", "/api/share", "", body)
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	var created ShareResponse
	json.Unmarshal(rec.Body.Bytes(), &created)

	// Get the share (no auth required per spec)
	getReq := httptest.NewRequest("GET", "/api/share/"+created.Code, nil)
	getRec := httptest.NewRecorder()

	// Use chi context to set URL param
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("code", created.Code)
	getReq = getReq.WithContext(context.WithValue(getReq.Context(), chi.RouteCtxKey, rctx))

	h.Get(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("get status = %d, want 200, body: %s", getRec.Code, getRec.Body.String())
	}

	var fetched ShareResponse
	json.Unmarshal(getRec.Body.Bytes(), &fetched)
	if fetched.Code != created.Code {
		t.Errorf("code = %s, want %s", fetched.Code, created.Code)
	}

	// Get non-existent share
	rctx2 := chi.NewRouteContext()
	rctx2.URLParams.Add("code", "DEADBEEF")
	badReq := httptest.NewRequest("GET", "/api/share/DEADBEEF", nil)
	badReq = badReq.WithContext(context.WithValue(badReq.Context(), chi.RouteCtxKey, rctx2))
	badRec := httptest.NewRecorder()
	h.Get(badRec, badReq)
	if badRec.Code != http.StatusNotFound {
		t.Errorf("non-existent share status = %d, want 404", badRec.Code)
	}
}

func TestListShares(t *testing.T) {
	h, _, cleanup := setupShareTest(t)
	defer cleanup()

	// Create two shares
	for i := 0; i < 2; i++ {
		body := CreateShareRequest{
			Subject:   "9709",
			Year:      2023 + i,
			Season:    "Summer",
			PaperType: "12",
			ExpiresIn: 7,
		}
		req := authRequest("POST", "/api/share", "", body)
		rec := httptest.NewRecorder()
		h.Create(rec, req)
	}

	// List
	listReq := authRequest("GET", "/api/shares", "", nil)
	listRec := httptest.NewRecorder()
	h.List(listRec, listReq)

	if listRec.Code != http.StatusOK {
		t.Fatalf("list status = %d, want 200", listRec.Code)
	}

	var shares []ShareResponse
	json.Unmarshal(listRec.Body.Bytes(), &shares)
	if len(shares) != 2 {
		t.Errorf("share count = %d, want 2", len(shares))
	}
}

func TestDeleteShare(t *testing.T) {
	h, _, cleanup := setupShareTest(t)
	defer cleanup()

	body := CreateShareRequest{
		Subject:   "9709", Year: 2023, Season: "Summer",
		PaperType: "12", ExpiresIn: 7,
	}
	req := authRequest("POST", "/api/share", "", body)
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	var created ShareResponse
	json.Unmarshal(rec.Body.Bytes(), &created)

	// Delete
	delReq := authRequest("DELETE", "/api/share/"+created.Code, "", nil)
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("code", created.Code)
	delReq = delReq.WithContext(context.WithValue(delReq.Context(), chi.RouteCtxKey, rctx))
	delRec := httptest.NewRecorder()
	h.Delete(delRec, delReq)

	if delRec.Code != http.StatusOK {
		t.Fatalf("delete status = %d, want 200", delRec.Code)
	}

	// Verify gone
	rctx2 := chi.NewRouteContext()
	rctx2.URLParams.Add("code", created.Code)
	getReq2 := httptest.NewRequest("GET", "/api/share/"+created.Code, nil)
	getReq2 = getReq2.WithContext(context.WithValue(getReq2.Context(), chi.RouteCtxKey, rctx2))
	getRec2 := httptest.NewRecorder()
	h.Get(getRec2, getReq2)
	if getRec2.Code != http.StatusNotFound {
		t.Errorf("after-delete get status = %d, want 404", getRec2.Code)
	}
}

func TestShareExpiration(t *testing.T) {
	h, db, cleanup := setupShareTest(t)
	defer cleanup()

	body := CreateShareRequest{
		Subject:   "9709", Year: 2023, Season: "Summer",
		PaperType: "12", ExpiresIn: 0, // 0 means use default 7 days
	}
	req := authRequest("POST", "/api/share", "", body)
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	var created ShareResponse
	json.Unmarshal(rec.Body.Bytes(), &created)

	// Manually expire the share
	db.Exec("UPDATE shares SET expires_at = datetime('now', '-1 day') WHERE code = ?", created.Code)

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("code", created.Code)
	getReq := httptest.NewRequest("GET", "/api/share/"+created.Code, nil)
	getReq = getReq.WithContext(context.WithValue(getReq.Context(), chi.RouteCtxKey, rctx))
	getRec := httptest.NewRecorder()
	h.Get(getRec, getReq)

	if getRec.Code != http.StatusNotFound {
		t.Errorf("expired share status = %d, want 404", getRec.Code)
	}
}
```

### Step 2: Run the test, expect failure

```bash
cd server && go test ./share/ -v 2>&1
```

Expected: compilation error, types and functions not defined.

### Step 3: Implement `server/share/model.go`

```go
package share

import "time"

// Share represents a paper share record.
type Share struct {
	ID        int64     `json:"id"`
	UserID    int64     `json:"user_id"`
	Code      string    `json:"code"`
	Subject   string    `json:"subject"`
	Year      int       `json:"year"`
	Season    string    `json:"season"`
	PaperType string    `json:"paper_type"`
	ExpiresAt time.Time `json:"expires_at"`
	ViewCount int       `json:"view_count"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateShareRequest is the JSON body for POST /api/share.
type CreateShareRequest struct {
	Subject   string `json:"subject"`
	Year      int    `json:"year"`
	Season    string `json:"season"`
	PaperType string `json:"paper_type"`
	ExpiresIn int    `json:"expires_in"` // days: 1, 7, 30, 0=default 7
}

// ShareResponse is the JSON response for a share.
type ShareResponse struct {
	Code      string `json:"code"`
	Subject   string `json:"subject"`
	Year      int    `json:"year"`
	Season    string `json:"season"`
	PaperType string `json:"paper_type"`
	ExpiresAt string `json:"expires_at"`
	ViewCount int    `json:"view_count"`
	CreatedAt string `json:"created_at"`
}
```

### Step 4: Implement `server/share/store.go`

```go
package share

import (
	"crypto/rand"
	"database/sql"
	"fmt"
	"math/big"
	"strings"
	"time"
)

const codeCharset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
const codeLen = 8

// Store provides database access for share operations.
type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

// GenerateCode creates a unique 8-character share code.
func GenerateCode() (string, error) {
	code := make([]byte, codeLen)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(codeCharset))))
		if err != nil {
			return "", fmt.Errorf("rand: %w", err)
		}
		code[i] = codeCharset[n.Int64()]
	}
	return string(code), nil
}

// Create inserts a new share with a unique code.
func (s *Store) Create(userID int64, req CreateShareRequest) (*ShareResponse, error) {
	// Generate unique code with retry
	var code string
	var err error
	for i := 0; i < 5; i++ {
		code, err = GenerateCode()
		if err != nil {
			return nil, err
		}
		exists, err := s.codeExists(code)
		if err != nil {
			return nil, err
		}
		if !exists {
			break
		}
	}
	if code == "" {
		return nil, fmt.Errorf("failed to generate unique code")
	}

	expiresIn := req.ExpiresIn
	if expiresIn <= 0 {
		expiresIn = 7
	}
	if expiresIn > 365 {
		expiresIn = 365
	}
	expiresAt := time.Now().Add(time.Duration(expiresIn) * 24 * time.Hour)

	_, err = s.db.Exec(
		`INSERT INTO shares (user_id, code, subject, year, season, paper_type, expires_at)
		 VALUES (?, ?, ?, ?, ?, ?, datetime(?))`,
		userID, code, req.Subject, req.Year, req.Season, req.PaperType,
		expiresAt.Format("2006-01-02 15:04:05"),
	)
	if err != nil {
		return nil, fmt.Errorf("insert share: %w", err)
	}

	return &ShareResponse{
		Code:      code,
		Subject:   req.Subject,
		Year:      req.Year,
		Season:    req.Season,
		PaperType: req.PaperType,
		ExpiresAt: expiresAt.Format(time.RFC3339),
		ViewCount: 0,
		CreatedAt: time.Now().Format(time.RFC3339),
	}, nil
}

func (s *Store) codeExists(code string) (bool, error) {
	var count int
	err := s.db.QueryRow("SELECT COUNT(*) FROM shares WHERE code = ?", code).Scan(&count)
	return count > 0, err
}

// GetByCode retrieves a share by its code, or nil if not found or expired.
func (s *Store) GetByCode(code string) (*ShareResponse, error) {
	var share Share
	var expiresAt, createdAt string
	err := s.db.QueryRow(
		`SELECT id, user_id, code, subject, year, season, paper_type, expires_at, view_count, created_at
		 FROM shares WHERE code = ?`, code,
	).Scan(&share.ID, &share.UserID, &share.Code, &share.Subject, &share.Year,
		&share.Season, &share.PaperType, &expiresAt, &share.ViewCount, &createdAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get share: %w", err)
	}

	// Check expiration
	exp, err := time.Parse("2006-01-02 15:04:05", expiresAt)
	if err == nil && time.Now().After(exp) {
		return nil, nil // expired
	}

	// Increment view count
	s.db.Exec("UPDATE shares SET view_count = view_count + 1 WHERE code = ?", code)

	return &ShareResponse{
		Code:      share.Code,
		Subject:   share.Subject,
		Year:      share.Year,
		Season:    share.Season,
		PaperType: share.PaperType,
		ExpiresAt: expiresAt,
		ViewCount: share.ViewCount + 1,
		CreatedAt: createdAt,
	}, nil
}

// ListByUser returns all shares for a user.
func (s *Store) ListByUser(userID int64) ([]ShareResponse, error) {
	rows, err := s.db.Query(
		`SELECT code, subject, year, season, paper_type, expires_at, view_count, created_at
		 FROM shares WHERE user_id = ? ORDER BY created_at DESC`, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list shares: %w", err)
	}
	defer rows.Close()

	var shares []ShareResponse
	for rows.Next() {
		var resp ShareResponse
		var expiresAt, createdAt string
		if err := rows.Scan(&resp.Code, &resp.Subject, &resp.Year, &resp.Season,
			&resp.PaperType, &expiresAt, &resp.ViewCount, &createdAt); err != nil {
			return nil, fmt.Errorf("scan share: %w", err)
		}
		resp.ExpiresAt = expiresAt
		resp.CreatedAt = createdAt
		shares = append(shares, resp)
	}
	if shares == nil {
		shares = []ShareResponse{}
	}
	return shares, nil
}

// DeleteByCode removes a share by its code, only if owned by userID.
func (s *Store) DeleteByCode(code string, userID int64) (bool, error) {
	result, err := s.db.Exec(
		"DELETE FROM shares WHERE code = ? AND user_id = ?", code, userID,
	)
	if err != nil {
		return false, fmt.Errorf("delete share: %w", err)
	}
	n, _ := result.RowsAffected()
	return n > 0, nil
}
```

Note: Remove unused `"strings"` from the import in store.go — it was added in error.

### Step 5: Implement `server/share/handler.go`

```go
package share

import (
	"encoding/json"
	"net/http"

	"github.com/Ja-son-WU/C-Paper/server/auth"
	"github.com/go-chi/chi/v5"
)

// Handler contains HTTP handlers for share endpoints.
type Handler struct {
	store *Store
}

func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// Create handles POST /api/share.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(auth.UserIDKey).(int64)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "unauthorized"})
		return
	}

	var req CreateShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}

	if req.Subject == "" || req.Year < 1900 || req.Season == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "subject, year, season are required"})
		return
	}

	resp, err := h.store.Create(userID, req)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, resp)
}

// Get handles GET /api/share/{code}. No auth required.
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")
	if code == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "code is required"})
		return
	}

	resp, err := h.store.GetByCode(code)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	if resp == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "share not found or expired"})
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// Delete handles DELETE /api/share/{code}.
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(auth.UserIDKey).(int64)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "unauthorized"})
		return
	}

	code := chi.URLParam(r, "code")
	deleted, err := h.store.DeleteByCode(code, userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	if !deleted {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "share not found"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// List handles GET /api/shares.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(auth.UserIDKey).(int64)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, ErrorResponse{Error: "unauthorized"})
		return
	}

	shares, err := h.store.ListByUser(userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, shares)
}

// ErrorResponse is a generic JSON error.
type ErrorResponse struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
```

### Step 6: Run the test, expect pass

```bash
cd server && go test ./share/ -v 2>&1
```

Expected output: all tests `PASS`

### Step 7: Commit

```bash
git add server/share/
git commit -m "feat(share): CRUD handlers for paper sharing with short codes and expiration"
```

---

## Task 6: Group Package (create, join, leave, papers, SSE progress)

**Files:**
- Create: `server/group/model.go`
- Create: `server/group/store.go`
- Create: `server/group/sse.go`
- Create: `server/group/handler.go`
- Create: `server/group/handler_test.go`


### Step 1 (TDD): Write group handler test

Create `server/group/handler_test.go`:

```go
package group

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Ja-son-WU/C-Paper/server/auth"
	"github.com/Ja-son-WU/C-Paper/server/db"
	"github.com/go-chi/chi/v5"
)

func setupGroupTest(t *testing.T) (*Handler, *sql.DB, *SSEBroker, func()) {
	t.Helper()
	database, err := db.Open("/tmp/test_cpaper_group.db")
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	if err := db.Migrate(database); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	// Clean all group-related tables
	database.Exec("DELETE FROM group_downloads")
	database.Exec("DELETE FROM group_papers")
	database.Exec("DELETE FROM group_members")
	database.Exec("DELETE FROM groups_table")
	database.Exec("DELETE FROM shares")
	database.Exec("DELETE FROM users")

	// Create test users
	database.Exec("INSERT INTO users (id, email, password_hash, nickname) VALUES (1, 'alice@test.com', 'h', 'Alice')")
	database.Exec("INSERT INTO users (id, email, password_hash, nickname) VALUES (2, 'bob@test.com', 'h', 'Bob')")

	broker := NewSSEBroker()
	store := NewStore(database)
	handler := NewHandler(store, broker)

	cleanup := func() {
		database.Exec("DELETE FROM group_downloads")
		database.Exec("DELETE FROM group_papers")
		database.Exec("DELETE FROM group_members")
		database.Exec("DELETE FROM groups_table")
		database.Exec("DELETE FROM users")
		database.Close()
	}
	return handler, database, broker, cleanup
}

func authCtx(userID int64) context.Context {
	return context.WithValue(context.Background(), auth.UserIDKey, userID)
}

func ctxWithChiParam(ctx context.Context, key, value string) context.Context {
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add(key, value)
	return context.WithValue(ctx, chi.RouteCtxKey, rctx)
}

func TestCreateAndGetGroup(t *testing.T) {
	h, _, _, cleanup := setupGroupTest(t)
	defer cleanup()

	// Create group
	body := CreateGroupRequest{
		Name:        "Math Study Group",
		Description: "For 9709 prep",
	}
	bodyJSON, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/api/groups", bytes.NewReader(bodyJSON))
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(authCtx(1))
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("create status = %d, want 201, body: %s", rec.Code, rec.Body.String())
	}

	var group GroupResponse
	json.Unmarshal(rec.Body.Bytes(), &group)
	if group.ID == 0 {
		t.Fatal("group ID is 0")
	}
	if group.InviteCode == "" {
		t.Fatal("invite code is empty")
	}
	if group.MemberCount != 1 {
		t.Errorf("member count = %d, want 1", group.MemberCount)
	}

	// Get group details
	ctx := ctxWithChiParam(authCtx(1), "id", "1")
	getReq := httptest.NewRequest("GET", "/api/groups/1", nil)
	getReq = getReq.WithContext(ctx)
	getRec := httptest.NewRecorder()
	h.Get(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("get status = %d, want 200, body: %s", getRec.Code, getRec.Body.String())
	}
	var fetched GroupResponse
	json.Unmarshal(getRec.Body.Bytes(), &fetched)
	if fetched.Name != "Math Study Group" {
		t.Errorf("name = %s, want Math Study Group", fetched.Name)
	}
}

func TestJoinAndLeaveGroup(t *testing.T) {
	h, _, _, cleanup := setupGroupTest(t)
	defer cleanup()

	// Alice creates group
	body := CreateGroupRequest{Name: "Study", Description: "test"}
	bodyJSON, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/api/groups", bytes.NewReader(bodyJSON))
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(authCtx(1))
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	var group GroupResponse
	json.Unmarshal(rec.Body.Bytes(), &group)

	// Bob joins with invite code
	joinBody := JoinGroupRequest{InviteCode: group.InviteCode}
	joinJSON, _ := json.Marshal(joinBody)
	joinReq := httptest.NewRequest("POST", "/api/groups/1/join", bytes.NewReader(joinJSON))
	joinReq.Header.Set("Content-Type", "application/json")
	joinReq = joinReq.WithContext(ctxWithChiParam(authCtx(2), "id", "1"))
	joinRec := httptest.NewRecorder()
	h.Join(joinRec, joinReq)

	if joinRec.Code != http.StatusOK {
		t.Fatalf("join status = %d, want 200, body: %s", joinRec.Code, joinRec.Body.String())
	}

	// Verify member count
	ctx := ctxWithChiParam(authCtx(1), "id", "1")
	getReq := httptest.NewRequest("GET", "/api/groups/1", nil)
	getReq = getReq.WithContext(ctx)
	getRec := httptest.NewRecorder()
	h.Get(getRec, getReq)

	var updated GroupResponse
	json.Unmarshal(getRec.Body.Bytes(), &updated)
	if updated.MemberCount != 2 {
		t.Errorf("member count = %d, want 2", updated.MemberCount)
	}

	// Bob leaves
	leaveReq := httptest.NewRequest("POST", "/api/groups/1/leave", nil)
	leaveReq = leaveReq.WithContext(ctxWithChiParam(authCtx(2), "id", "1"))
	leaveRec := httptest.NewRecorder()
	h.Leave(leaveRec, leaveReq)

	if leaveRec.Code != http.StatusOK {
		t.Fatalf("leave status = %d, want 200", leaveRec.Code)
	}

	// Verify member count back to 1
	getReq2 := httptest.NewRequest("GET", "/api/groups/1", nil)
	getReq2 = getReq2.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	getRec2 := httptest.NewRecorder()
	h.Get(getRec2, getReq2)

	var afterLeave GroupResponse
	json.Unmarshal(getRec2.Body.Bytes(), &afterLeave)
	if afterLeave.MemberCount != 1 {
		t.Errorf("member count after leave = %d, want 1", afterLeave.MemberCount)
	}
}

func TestGroupPapers(t *testing.T) {
	h, _, _, cleanup := setupGroupTest(t)
	defer cleanup()

	// Create group
	body := CreateGroupRequest{Name: "Study", Description: "test"}
	bodyJSON, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/api/groups", bytes.NewReader(bodyJSON))
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(authCtx(1))
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	// Add paper
	paperBody := AddPaperRequest{
		Subject:     "9709",
		Year:        2023,
		Season:      "Summer",
		PaperType:   "12",
		Filename:    "9709_s23_qp_12.pdf",
		DownloadURL: "https://example.com/paper.pdf",
	}
	paperJSON, _ := json.Marshal(paperBody)
	paperReq := httptest.NewRequest("POST", "/api/groups/1/papers", bytes.NewReader(paperJSON))
	paperReq.Header.Set("Content-Type", "application/json")
	paperReq = paperReq.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	paperRec := httptest.NewRecorder()
	h.AddPaper(paperRec, paperReq)

	if paperRec.Code != http.StatusCreated {
		t.Fatalf("add paper status = %d, want 201, body: %s", paperRec.Code, paperRec.Body.String())
	}

	// List papers
	listReq := httptest.NewRequest("GET", "/api/groups/1/papers", nil)
	listReq = listReq.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	listRec := httptest.NewRecorder()
	h.ListPapers(listRec, listReq)

	var papers []PaperResponse
	json.Unmarshal(listRec.Body.Bytes(), &papers)
	if len(papers) != 1 {
		t.Fatalf("paper count = %d, want 1", len(papers))
	}
	if papers[0].Filename != "9709_s23_qp_12.pdf" {
		t.Errorf("filename = %s, want 9709_s23_qp_12.pdf", papers[0].Filename)
	}
}

func TestSSEProgress(t *testing.T) {
	h, _, broker, cleanup := setupGroupTest(t)
	defer cleanup()

	// Create group with Alice
	body := CreateGroupRequest{Name: "Study", Description: "test"}
	bodyJSON, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/api/groups", bytes.NewReader(bodyJSON))
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(authCtx(1))
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	// Add paper
	paperBody := AddPaperRequest{
		Subject: "9709", Year: 2023, Season: "Summer",
		PaperType: "12", Filename: "paper.pdf",
	}
	paperJSON, _ := json.Marshal(paperBody)
	paperReq := httptest.NewRequest("POST", "/api/groups/1/papers", bytes.NewReader(paperJSON))
	paperReq.Header.Set("Content-Type", "application/json")
	paperReq = paperReq.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	paperRec := httptest.NewRecorder()
	h.AddPaper(paperRec, paperReq)

	var paper PaperResponse
	json.Unmarshal(paperRec.Body.Bytes(), &paper)

	// Subscribe to SSE
	evtReq := httptest.NewRequest("GET", "/api/groups/1/events", nil)
	evtReq = evtReq.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	evtRec := httptest.NewRecorder()

	// We can't use httptest.Recorder for SSE streaming since it buffers.
	// Instead, test the broker directly.
	ch := broker.Subscribe(1)
	defer broker.Unsubscribe(1, ch)

	// Update progress
	progressBody := ProgressRequest{
		PaperID: paper.ID,
		Status:  "downloaded",
	}
	progressJSON, _ := json.Marshal(progressBody)
	progReq := httptest.NewRequest("POST", "/api/groups/1/progress", bytes.NewReader(progressJSON))
	progReq.Header.Set("Content-Type", "application/json")
	progReq = progReq.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	progRec := httptest.NewRecorder()
	h.UpdateProgress(progRec, progReq)

	if progRec.Code != http.StatusOK {
		t.Fatalf("progress update status = %d, want 200", progRec.Code)
	}

	// Check SSE event received
	select {
	case event := <-ch:
		if event.Type != "progress_update" {
			t.Errorf("event type = %s, want progress_update", event.Type)
		}
	default:
		t.Error("expected SSE event but received none")
	}

	// Verify download status
	progGetReq := httptest.NewRequest("GET", "/api/groups/1/progress", nil)
	progGetReq = progGetReq.WithContext(ctxWithChiParam(authCtx(1), "id", "1"))
	progGetRec := httptest.NewRecorder()
	h.GetProgress(progGetRec, progGetReq)

	var members []MemberProgress
	json.Unmarshal(progGetRec.Body.Bytes(), &members)
	if len(members) == 0 {
		t.Fatal("progress list is empty")
	}
	found := false
	for _, m := range members {
		if m.UserID == 1 {
			found = true
			if m.Downloaded != 1 {
				t.Errorf("downloaded count = %d, want 1", m.Downloaded)
			}
		}
	}
	if !found {
		t.Error("user 1 not in progress list")
	}
}
```

### Step 2: Run the test, expect failure

```bash
cd server && go test ./group/ -v 2>&1
```

Expected: compilation error.

### Step 3: Implement `server/group/model.go`

```go
package group

import "time"

// Group represents a learning group.
type Group struct {
	ID          int64     `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	InviteCode  string    `json:"invite_code"`
	OwnerID     int64     `json:"owner_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// GroupMember represents a user's membership in a group.
type GroupMember struct {
	GroupID  int64     `json:"group_id"`
	UserID   int64     `json:"user_id"`
	Role     string    `json:"role"`
	JoinedAt time.Time `json:"joined_at"`
}

// GroupPaper represents a paper shared within a group.
type GroupPaper struct {
	ID          int64     `json:"id"`
	GroupID     int64     `json:"group_id"`
	AddedBy     int64     `json:"added_by"`
	Subject     string    `json:"subject"`
	Year        int       `json:"year"`
	Season      string    `json:"season"`
	PaperType   string    `json:"paper_type"`
	Filename    string    `json:"filename"`
	DownloadURL string    `json:"download_url"`
	CreatedAt   time.Time `json:"created_at"`
}

// --- Request types ---

type CreateGroupRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type JoinGroupRequest struct {
	InviteCode string `json:"invite_code"`
}

type AddPaperRequest struct {
	Subject     string `json:"subject"`
	Year        int    `json:"year"`
	Season      string `json:"season"`
	PaperType   string `json:"paper_type"`
	Filename    string `json:"filename"`
	DownloadURL string `json:"download_url"`
}

type ProgressRequest struct {
	PaperID int64  `json:"paper_id"`
	Status  string `json:"status"`
}

// --- Response types ---

type GroupResponse struct {
	ID          int64            `json:"id"`
	Name        string           `json:"name"`
	Description string           `json:"description"`
	InviteCode  string           `json:"invite_code"`
	OwnerID     int64            `json:"owner_id"`
	MemberCount int              `json:"member_count"`
	Members     []MemberInfo     `json:"members,omitempty"`
	Papers      []PaperResponse  `json:"papers,omitempty"`
	CreatedAt   string           `json:"created_at"`
}

type MemberInfo struct {
	UserID   int64  `json:"user_id"`
	Nickname string `json:"nickname"`
	Role     string `json:"role"`
	JoinedAt string `json:"joined_at"`
}

type PaperResponse struct {
	ID          int64  `json:"id"`
	GroupID     int64  `json:"group_id"`
	AddedBy     int64  `json:"added_by"`
	AddedByName string `json:"added_by_name"`
	Subject     string `json:"subject"`
	Year        int    `json:"year"`
	Season      string `json:"season"`
	PaperType   string `json:"paper_type"`
	Filename    string `json:"filename"`
	DownloadURL string `json:"download_url"`
	CreatedAt   string `json:"created_at"`
}

type MemberProgress struct {
	UserID     int64  `json:"user_id"`
	Nickname   string `json:"nickname"`
	Total      int    `json:"total"`
	Downloaded int    `json:"downloaded"`
	Pending    int    `json:"pending"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}
```

### Step 4: Implement `server/group/store.go`

```go
package group

import (
	"crypto/rand"
	"database/sql"
	"fmt"
	"math/big"
)

const inviteCodeCharset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const inviteCodeLen = 6

// Store provides database access for group operations.
type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func generateInviteCode() (string, error) {
	code := make([]byte, inviteCodeLen)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(inviteCodeCharset))))
		if err != nil {
			return "", err
		}
		code[i] = inviteCodeCharset[n.Int64()]
	}
	return string(code), nil
}

func (s *Store) Create(ownerID int64, req CreateGroupRequest) (*GroupResponse, error) {
	code, err := generateInviteCode()
	if err != nil {
		return nil, fmt.Errorf("generate code: %w", err)
	}

	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	result, err := tx.Exec(
		"INSERT INTO groups_table (name, description, invite_code, owner_id) VALUES (?, ?, ?, ?)",
		req.Name, req.Description, code, ownerID,
	)
	if err != nil {
		return nil, fmt.Errorf("insert group: %w", err)
	}
	groupID, _ := result.LastInsertId()

	// Auto-add owner as member
	_, err = tx.Exec(
		"INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, 'owner')",
		groupID, ownerID,
	)
	if err != nil {
		return nil, fmt.Errorf("insert owner: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	return &GroupResponse{
		ID:          groupID,
		Name:        req.Name,
		Description: req.Description,
		InviteCode:  code,
		OwnerID:     ownerID,
		MemberCount: 1,
		CreatedAt:   "now",
	}, nil
}

func (s *Store) GetByID(groupID, userID int64) (*GroupResponse, error) {
	var g GroupResponse
	var createdAt string
	err := s.db.QueryRow(
		"SELECT id, name, description, invite_code, owner_id, created_at FROM groups_table WHERE id = ?",
		groupID,
	).Scan(&g.ID, &g.Name, &g.Description, &g.InviteCode, &g.OwnerID, &createdAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get group: %w", err)
	}
	g.CreatedAt = createdAt

	// Count members
	s.db.QueryRow("SELECT COUNT(*) FROM group_members WHERE group_id = ?", groupID).Scan(&g.MemberCount)

	// Get members
	rows, err := s.db.Query(
		`SELECT gm.user_id, u.nickname, gm.role, gm.joined_at
		 FROM group_members gm JOIN users u ON gm.user_id = u.id
		 WHERE gm.group_id = ?`, groupID,
	)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var m MemberInfo
			rows.Scan(&m.UserID, &m.Nickname, &m.Role, &m.JoinedAt)
			g.Members = append(g.Members, m)
		}
	}

	// Get papers
	paperRows, err := s.db.Query(
		`SELECT gp.id, gp.group_id, gp.added_by, u.nickname, gp.subject, gp.year,
		        gp.season, gp.paper_type, gp.filename, gp.download_url, gp.created_at
		 FROM group_papers gp JOIN users u ON gp.added_by = u.id
		 WHERE gp.group_id = ? ORDER BY gp.created_at DESC`, groupID,
	)
	if err == nil {
		defer paperRows.Close()
		for paperRows.Next() {
			var p PaperResponse
			paperRows.Scan(&p.ID, &p.GroupID, &p.AddedBy, &p.AddedByName,
				&p.Subject, &p.Year, &p.Season, &p.PaperType, &p.Filename,
				&p.DownloadURL, &p.CreatedAt)
			g.Papers = append(g.Papers, p)
		}
	}

	if g.Members == nil {
		g.Members = []MemberInfo{}
	}
	if g.Papers == nil {
		g.Papers = []PaperResponse{}
	}

	return &g, nil
}

func (s *Store) Join(groupID, userID int64, inviteCode string) error {
	// Verify invite code
	var actualCode string
	err := s.db.QueryRow("SELECT invite_code FROM groups_table WHERE id = ?", groupID).Scan(&actualCode)
	if err == sql.ErrNoRows {
		return fmt.Errorf("group not found")
	}
	if err != nil {
		return fmt.Errorf("get group: %w", err)
	}
	if actualCode != inviteCode {
		return fmt.Errorf("invalid invite code")
	}

	// Check not already member
	var count int
	s.db.QueryRow("SELECT COUNT(*) FROM group_members WHERE group_id = ? AND user_id = ?", groupID, userID).Scan(&count)
	if count > 0 {
		return fmt.Errorf("already a member")
	}

	_, err = s.db.Exec(
		"INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, 'member')",
		groupID, userID,
	)
	if err != nil {
		return fmt.Errorf("join group: %w", err)
	}
	return nil
}

func (s *Store) Leave(groupID, userID int64) error {
	var ownerID int64
	s.db.QueryRow("SELECT owner_id FROM groups_table WHERE id = ?", groupID).Scan(&ownerID)
	if ownerID == userID {
		return fmt.Errorf("owner cannot leave group; delete the group instead")
	}

	_, err := s.db.Exec(
		"DELETE FROM group_members WHERE group_id = ? AND user_id = ?", groupID, userID,
	)
	if err != nil {
		return fmt.Errorf("leave group: %w", err)
	}
	return nil
}

func (s *Store) AddPaper(groupID, userID int64, req AddPaperRequest) (*PaperResponse, error) {
	result, err := s.db.Exec(
		`INSERT INTO group_papers (group_id, added_by, subject, year, season, paper_type, filename, download_url)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		groupID, userID, req.Subject, req.Year, req.Season, req.PaperType, req.Filename, req.DownloadURL,
	)
	if err != nil {
		return nil, fmt.Errorf("add paper: %w", err)
	}
	id, _ := result.LastInsertId()

	// Auto-create download tracking records for all members
	s.db.Exec(
		`INSERT INTO group_downloads (group_paper_id, user_id, status)
		 SELECT ?, gm.user_id, 'pending' FROM group_members gm WHERE gm.group_id = ?`,
		id, groupID,
	)

	return &PaperResponse{
		ID:        id,
		GroupID:   groupID,
		AddedBy:   userID,
		Subject:   req.Subject,
		Year:      req.Year,
		Season:    req.Season,
		PaperType: req.PaperType,
		Filename:  req.Filename,
		DownloadURL: req.DownloadURL,
	}, nil
}

func (s *Store) UpdateProgress(groupPaperID, userID int64, status string) error {
	_, err := s.db.Exec(
		`INSERT INTO group_downloads (group_paper_id, user_id, status, updated_at)
		 VALUES (?, ?, ?, datetime('now'))
		 ON CONFLICT(group_paper_id, user_id)
		 DO UPDATE SET status = ?, updated_at = datetime('now')`,
		groupPaperID, userID, status, status,
	)
	return err
}

func (s *Store) GetProgress(groupID int64) ([]MemberProgress, error) {
	rows, err := s.db.Query(
		`SELECT u.id, u.nickname,
		        COUNT(gd.group_paper_id) as total,
		        SUM(CASE WHEN gd.status = 'downloaded' THEN 1 ELSE 0 END) as downloaded
		 FROM group_members gm
		 JOIN users u ON gm.user_id = u.id
		 LEFT JOIN group_papers gp ON gp.group_id = gm.group_id
		 LEFT JOIN group_downloads gd ON gd.group_paper_id = gp.id AND gd.user_id = gm.user_id
		 WHERE gm.group_id = ?
		 GROUP BY u.id, u.nickname`, groupID,
	)
	if err != nil {
		return nil, fmt.Errorf("get progress: %w", err)
	}
	defer rows.Close()

	var progress []MemberProgress
	for rows.Next() {
		var p MemberProgress
		rows.Scan(&p.UserID, &p.Nickname, &p.Total, &p.Downloaded)
		p.Pending = p.Total - p.Downloaded
		progress = append(progress, p)
	}
	if progress == nil {
		progress = []MemberProgress{}
	}
	return progress, nil
}

func (s *Store) ListByUser(userID int64) ([]GroupResponse, error) {
	rows, err := s.db.Query(
		`SELECT g.id, g.name, g.description, g.invite_code, g.owner_id, g.created_at,
		        (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) as member_count
		 FROM groups_table g
		 JOIN group_members gm ON g.id = gm.group_id
		 WHERE gm.user_id = ?
		 ORDER BY g.created_at DESC`, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list groups: %w", err)
	}
	defer rows.Close()

	var groups []GroupResponse
	for rows.Next() {
		var g GroupResponse
		var createdAt string
		rows.Scan(&g.ID, &g.Name, &g.Description, &g.InviteCode, &g.OwnerID, &createdAt, &g.MemberCount)
		g.CreatedAt = createdAt
		groups = append(groups, g)
	}
	if groups == nil {
		groups = []GroupResponse{}
	}
	return groups, nil
}
```

### Step 5: Implement `server/group/sse.go`

```go
package group

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"
)

// SSEEvent represents a server-sent event.
type SSEEvent struct {
	Type string
	Data string
}

// SSEBroker manages SSE subscriptions per group.
type SSEBroker struct {
	mu      sync.RWMutex
	clients map[int64]map[chan SSEEvent]struct{} // groupID -> set of channels
}

func NewSSEBroker() *SSEBroker {
	return &SSEBroker{
		clients: make(map[int64]map[chan SSEEvent]struct{}),
	}
}

// Subscribe adds a new subscriber channel for a group.
func (b *SSEBroker) Subscribe(groupID int64) chan SSEEvent {
	b.mu.Lock()
	defer b.mu.Unlock()

	ch := make(chan SSEEvent, 32)
	if b.clients[groupID] == nil {
		b.clients[groupID] = make(map[chan SSEEvent]struct{})
	}
	b.clients[groupID][ch] = struct{}{}
	return ch
}

// Unsubscribe removes a subscriber channel.
func (b *SSEBroker) Unsubscribe(groupID int64, ch chan SSEEvent) {
	b.mu.Lock()
	defer b.mu.Unlock()

	if clients, ok := b.clients[groupID]; ok {
		delete(clients, ch)
		close(ch)
		if len(clients) == 0 {
			delete(b.clients, groupID)
		}
	}
}

// Broadcast sends an event to all subscribers of a group.
func (b *SSEBroker) Broadcast(groupID int64, event SSEEvent) {
	b.mu.RLock()
	defer b.mu.RUnlock()

	clients, ok := b.clients[groupID]
	if !ok {
		return
	}
	for ch := range clients {
		select {
		case ch <- event:
		default:
			// Channel full, drop event
			log.Printf("SSE: dropping event for group %d (channel full)", groupID)
		}
	}
}

// MarshalEvent serializes an SSE event to the wire format.
func MarshalEvent(event SSEEvent) string {
	data, _ := json.Marshal(event.Data)
	return fmt.Sprintf("event: %s\ndata: %s\n\n", event.Type, string(data))
}
```

### Step 6: Implement `server/group/handler.go`

```go
package group

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"

	"github.com/Ja-son-WU/C-Paper/server/auth"
	"github.com/go-chi/chi/v5"
)

// Handler contains HTTP handlers for group endpoints.
type Handler struct {
	store  *Store
	broker *SSEBroker
}

func NewHandler(store *Store, broker *SSEBroker) *Handler {
	return &Handler{store: store, broker: broker}
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	var req CreateGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}
	if req.Name == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "name is required"})
		return
	}
	resp, err := h.store.Create(userID, req)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, resp)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	resp, err := h.store.GetByID(groupID, userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	if resp == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "group not found"})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groups, err := h.store.ListByUser(userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, groups)
}

func (h *Handler) Join(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	var req JoinGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}
	if err := h.store.Join(groupID, userID, req.InviteCode); err != nil {
		errMsg := err.Error()
		code := http.StatusBadRequest
		if errMsg == "already a member" {
			code = http.StatusConflict
		}
		writeJSON(w, code, ErrorResponse{Error: errMsg})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "joined"})
}

func (h *Handler) Leave(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	if err := h.store.Leave(groupID, userID); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "left"})
}

func (h *Handler) AddPaper(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	var req AddPaperRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}
	if req.Subject == "" || req.Filename == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "subject and filename required"})
		return
	}
	resp, err := h.store.AddPaper(groupID, userID, req)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	// Broadcast to SSE subscribers
	h.broker.Broadcast(groupID, SSEEvent{
		Type: "paper_added",
		Data: fmt.Sprintf(`{"paper_id":%d,"filename":"%s","user_id":%d}`, resp.ID, resp.Filename, userID),
	})
	writeJSON(w, http.StatusCreated, resp)
}

func (h *Handler) ListPapers(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	resp, err := h.store.GetByID(groupID, userID)
	if err != nil || resp == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "group not found"})
		return
	}
	writeJSON(w, http.StatusOK, resp.Papers)
}

func (h *Handler) UpdateProgress(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(auth.UserIDKey).(int64)
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	var req ProgressRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON"})
		return
	}
	if err := h.store.UpdateProgress(req.PaperID, userID, req.Status); err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	// Broadcast progress update to all subscribers
	h.broker.Broadcast(groupID, SSEEvent{
		Type: "progress_update",
		Data: fmt.Sprintf(`{"user_id":%d,"paper_id":%d,"status":"%s"}`, userID, req.PaperID, req.Status),
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) GetProgress(w http.ResponseWriter, r *http.Request) {
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}
	progress, err := h.store.GetProgress(groupID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, progress)
}

func (h *Handler) Events(w http.ResponseWriter, r *http.Request) {
	groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid group ID"})
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "streaming not supported"})
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	ch := h.broker.Subscribe(groupID)
	defer h.broker.Unsubscribe(groupID, ch)

	// Send initial keepalive
	fmt.Fprintf(w, ":ok\n\n")
	flusher.Flush()

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-ch:
			if !ok {
				return
			}
			fmt.Fprint(w, MarshalEvent(event))
			flusher.Flush()
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func init() { log.SetFlags(0) } // suppress log prefixes for cleaner SSE stuff
```

### Step 7: Add chi dependency (if not already)

```bash
cd server && go get github.com/go-chi/chi/v5 && go mod tidy
```

### Step 8: Run the test, expect pass

```bash
cd server && go test ./group/ -v 2>&1
```

Expected output: all tests `PASS`

### Step 9: Commit

```bash
git add server/group/
git commit -m "feat(group): CRUD, join/leave, paper sharing, SSE progress broadcasting"
```

---

## Task 7: Review Package (submit, list, stats, delete)

**Files:**
- Create: `server/review/model.go`
- Create: `server/review/store.go`
- Create: `server/review/handler.go`
- Create: `server/review/handler_test.go`

