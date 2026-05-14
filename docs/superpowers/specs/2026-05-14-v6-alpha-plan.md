# C-Paper v6.0-alpha 实现计划

> 阶段：v6.0-alpha
> 范围：协作服务端 (Go + SQLite) + 桌面端集成（分享、小组、评价）
> 日期：2026-05-14
> 状态：计划中

---

## 一、概述

v6.0-alpha 是 v6.0 的首个交付阶段，目标是将协作服务端上线并将分享、学习小组、试卷评价三大功能集成到现有桌面端（pywebview）中。

### 1.1 交付物

1. **Go 协作服务端** — 完整的后端服务，包含用户系统、分享、小组、评价四大模块
2. **桌面端 Python 客户端** — `collab_client.py`，封装所有服务端 API 调用
3. **桌面端 UI 集成** — 在现有 `ui_v2.html/js/css` 中新增协作功能面板

### 1.2 不包含

- iOS 移动端（v6.0-rc 阶段）
- AI 分析 / OCR / 智能去重（v6.0-beta 阶段）
- OAuth 登录（Apple / 飞书）— 作为后续迭代，alpha 仅支持邮箱+密码注册登录

---

## 二、技术架构详细设计

### 2.1 Go 服务端目录结构

```
server/
├── cmd/
│   └── server/
│       └── main.go              # 入口：启动 HTTP 服务、初始化 DB
├── internal/
│   ├── config/
│   │   └── config.go            # 配置加载（环境变量、端口、JWT secret 等）
│   ├── database/
│   │   ├── db.go                # SQLite 连接池初始化、WAL 模式设置
│   │   └── migrations.go        # 自动迁移：建表、加索引
│   ├── middleware/
│   │   ├── auth.go              # JWT 认证中间件（解析 Authorization header）
│   │   ├── ratelimit.go         # 速率限制中间件（每 IP 令牌桶）
│   │   ├── cors.go              # CORS 中间件
│   │   └── logger.go            # 请求日志中间件
│   ├── models/
│   │   ├── user.go              # User 结构体 + 数据库操作
│   │   ├── share.go             # Share 结构体 + 数据库操作
│   │   ├── group.go             # Group, GroupMember, GroupPaper, GroupDownload 结构体 + 操作
│   │   └── review.go            # Review, ReviewReaction 结构体 + 操作
│   ├── handlers/
│   │   ├── auth.go              # 注册、登录、刷新 token、获取/更新用户信息
│   │   ├── share.go             # 创建/获取/删除分享
│   │   ├── group.go             # 小组 CRUD、成员管理、共享试卷、进度更新
│   │   ├── review.go            # 评价 CRUD、统计
│   │   └── sse.go               # SSE 事件推送（小组进度实时通知）
│   └── router/
│       └── router.go            # 路由注册（chi 路由器）
├── migrations/
│   └── 001_init.sql             # 初始 Schema（备份用，实际由 migrations.go 自动执行）
├── go.mod
├── go.sum
└── Dockerfile                   # 容器化部署（Fly.io / Railway）
```

### 2.2 API 路由设计

使用 `go-chi/chi` 路由库，路由树如下：

```
/api
├── /auth
│   ├── POST   /register          # 邮箱+密码注册
│   ├── POST   /login             # 邮箱+密码登录，返回 JWT
│   └── POST   /refresh           # 刷新 JWT（需携带 refresh token）
├── /me
│   ├── GET    /                  # 获取当前用户信息（需认证）
│   └── PUT    /                  # 更新用户信息（需认证）
├── /share
│   ├── POST   /                  # 创建分享（需认证）
│   ├── GET    /:code             # 获取分享内容（无需认证）
│   ├── DELETE /:code             # 删除分享（需认证，仅创建者）
│   └── GET    /list              # 我的分享列表（需认证）
├── /groups
│   ├── POST   /                  # 创建小组（需认证）
│   ├── GET    /                  # 我的小组列表（需认证）
│   ├── GET    /:id               # 小组详情（需认证，仅成员）
│   ├── POST   /:id/join          # 加入小组（需认证，凭邀请码）
│   ├── POST   /:id/leave         # 退出小组（需认证）
│   ├── POST   /:id/papers        # 添加共享试卷（需认证，仅成员）
│   ├── DELETE /:id/papers/:pid   # 移除共享试卷（需认证，仅添加者或 owner）
│   ├── GET    /:id/progress      # 成员下载进度（需认证，仅成员）
│   ├── POST   /:id/progress      # 更新我的下载进度（需认证，仅成员）
│   └── GET    /:id/events        # SSE 实时事件流（需认证，仅成员）
├── /reviews
│   ├── POST   /                  # 提交评价（需认证）
│   ├── GET    /                  # 获取评价列表（无需认证，可按 subject/year 筛选）
│   ├── GET    /stats             # 评分统计（无需认证）
│   └── DELETE /:id               # 删除评价（需认证，仅作者）
└── /health
    └── GET    /                  # 健康检查（无需认证）
```

### 2.3 中间件栈

请求处理链（从外到内）：

```
HTTP Request
  → Logger（记录请求方法、路径、耗时）
  → CORS（允许客户端 origin）
  → RateLimit（每 IP 60/min，登录/注册 5/min）
  → [可选] Auth（JWT 验证，注入 user_id 到 context）
  → Handler
```

### 2.4 认证流程

```
注册流程：
  POST /api/auth/register {email, password, nickname}
  → 校验邮箱格式、密码长度 >= 8
  → bcrypt hash password (cost=12)
  → INSERT INTO users
  → 签发 JWT access_token (7天) + refresh_token (30天)
  → 返回 {access_token, refresh_token, user}

登录流程：
  POST /api/auth/login {email, password}
  → 查找用户 by email
  → bcrypt.CompareHashAndPassword
  → 签发 JWT
  → 返回 {access_token, refresh_token, user}

请求认证：
  Authorization: Bearer <access_token>
  → 解析 JWT，提取 user_id
  → 注入 context：ctx = context.WithValue(ctx, "user_id", userID)
```

---

## 三、数据库 Schema（SQLite）

### 3.1 表定义

```sql
-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    email       TEXT    NOT NULL UNIQUE,
    password_hash TEXT  NOT NULL,
    nickname    TEXT    NOT NULL DEFAULT '',
    avatar_url  TEXT    NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 分享表
CREATE TABLE IF NOT EXISTS shares (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code        TEXT    NOT NULL UNIQUE,         -- 6~8 位短码
    subject     TEXT    NOT NULL,                -- 科目代码，如 "9709"
    year        INTEGER NOT NULL,                -- 年份，如 2023
    season      TEXT    NOT NULL,                -- Mar/Jun/Nov
    paper_type  TEXT    NOT NULL DEFAULT '',      -- qp/ms/ci 等
    expires_at  TEXT    NOT NULL,                 -- 过期时间 ISO8601
    view_count  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 学习小组表
CREATE TABLE IF NOT EXISTS groups (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL,
    description  TEXT    NOT NULL DEFAULT '',
    invite_code  TEXT    NOT NULL UNIQUE,         -- 8 位邀请码
    owner_id     INTEGER NOT NULL REFERENCES users(id),
    created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 小组成员表
CREATE TABLE IF NOT EXISTS group_members (
    group_id  INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      TEXT    NOT NULL DEFAULT 'member',  -- owner/admin/member
    joined_at TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (group_id, user_id)
);

-- 小组共享试卷表
CREATE TABLE IF NOT EXISTS group_papers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id    INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    added_by    INTEGER NOT NULL REFERENCES users(id),
    subject     TEXT    NOT NULL,
    year        INTEGER NOT NULL,
    season      TEXT    NOT NULL,
    paper_type  TEXT    NOT NULL DEFAULT '',
    filename    TEXT    NOT NULL,
    download_url TEXT   NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 小组下载进度表
CREATE TABLE IF NOT EXISTS group_downloads (
    group_paper_id INTEGER NOT NULL REFERENCES group_papers(id) ON DELETE CASCADE,
    user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status         TEXT    NOT NULL DEFAULT 'pending',  -- pending/downloaded
    updated_at     TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (group_paper_id, user_id)
);

-- 试卷评价表
CREATE TABLE IF NOT EXISTS reviews (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject     TEXT    NOT NULL,
    year        INTEGER NOT NULL,
    season      TEXT    NOT NULL,
    paper_type  TEXT    NOT NULL DEFAULT '',
    filename    TEXT    NOT NULL DEFAULT '',
    rating      INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 5),
    difficulty  INTEGER NOT NULL CHECK(difficulty >= 1 AND difficulty <= 5),
    tags        TEXT    NOT NULL DEFAULT '[]',     -- JSON 数组
    comment     TEXT    NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 评价互动表
CREATE TABLE IF NOT EXISTS review_reactions (
    review_id  INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction   TEXT    NOT NULL,                   -- helpful/useful/etc
    PRIMARY KEY (review_id, user_id)
);
```

### 3.2 索引策略

```sql
-- 用户：邮箱唯一索引（UNIQUE 约束自动创建）
-- 分享：短码唯一索引 + 用户查询索引 + 过期清理索引
CREATE UNIQUE INDEX idx_shares_code ON shares(code);
CREATE INDEX idx_shares_user_id ON shares(user_id);
CREATE INDEX idx_shares_expires_at ON shares(expires_at);

-- 小组：邀请码唯一索引 + 成员查询复合索引
CREATE UNIQUE INDEX idx_groups_invite_code ON groups(invite_code);
CREATE INDEX idx_group_members_user ON group_members(user_id);
CREATE INDEX idx_group_members_group ON group_members(group_id);

-- 小组试卷：按小组查询索引
CREATE INDEX idx_group_papers_group ON group_papers(group_id);

-- 小组下载进度：复合主键已覆盖，额外加用户查询索引
CREATE INDEX idx_group_downloads_user ON group_downloads(user_id);

-- 评价：按科目+年份查询索引 + 用户查询索引 + 唯一约束（一人一卷一评）
CREATE INDEX idx_reviews_subject_year ON reviews(subject, year, season);
CREATE INDEX idx_reviews_user ON reviews(user_id);
CREATE UNIQUE INDEX idx_reviews_unique ON reviews(user_id, subject, year, season, paper_type);

-- 评价互动：复合主键已覆盖
CREATE INDEX idx_review_reactions_review ON review_reactions(review_id);
```

### 3.3 SQLite 配置要点

```go
// 连接字符串启用 WAL 模式和外键约束
db, err := sql.Open("sqlite3", "file:data.db?_journal_mode=WAL&_foreign_keys=ON&_busy_timeout=5000")

// 连接池设置（SQLite 单写多读特性）
db.SetMaxOpenConns(1)       // 单写连接
db.SetMaxIdleConns(1)
```

---

## 四、实现任务拆分

### 任务 1：Go 服务端基础设施

**文件路径：**
- `server/go.mod`
- `server/cmd/server/main.go`
- `server/internal/config/config.go`
- `server/internal/database/db.go`
- `server/internal/database/migrations.go`

**关键代码结构：**

```go
// server/go.mod
module github.com/ja-son-wu/c-paper-server

go 1.22

require (
    github.com/go-chi/chi/v5 v5.1.0
    github.com/go-chi/cors v1.2.1
    github.com/golang-jwt/jwt/v5 v5.2.1
    github.com/mattn/go-sqlite3 v1.14.24
    golang.org/x/crypto v0.31.0
)

// server/internal/config/config.go
type Config struct {
    Port        string // 默认 ":8080"
    DBPath      string // 默认 "./data.db"
    JWTSecret   string // 从环境变量读取
    JWTExpiry   time.Duration // 7 * 24 * time.Hour
    RefreshExpiry time.Duration // 30 * 24 * time.Hour
    BcryptCost  int    // 12
    RateLimit   int    // 60/min
    AuthRateLimit int  // 5/min
    AllowedOrigins []string
}

// server/cmd/server/main.go
func main() {
    cfg := config.Load()
    db := database.Open(cfg.DBPath)
    database.Migrate(db)
    r := router.Setup(db, cfg)
    log.Printf("C-Paper server listening on %s", cfg.Port)
    http.ListenAndServe(cfg.Port, r)
}
```

**预计工作量：** 1.5 天

---

### 任务 2：中间件实现

**文件路径：**
- `server/internal/middleware/auth.go`
- `server/internal/middleware/ratelimit.go`
- `server/internal/middleware/cors.go`
- `server/internal/middleware/logger.go`

**关键代码结构：**

```go
// auth.go — JWT 认证中间件
func AuthMiddleware(jwtSecret string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            tokenStr := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
            token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
                return []byte(jwtSecret), nil
            })
            if err != nil || !token.Valid {
                http.Error(w, `{"error":"unauthorized"}`, 401)
                return
            }
            claims := token.Claims.(jwt.MapClaims)
            userID := int64(claims["user_id"].(float64))
            ctx := context.WithValue(r.Context(), "user_id", userID)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

// ratelimit.go — 基于 sync.Map 的 IP 令牌桶
type IPRateLimiter struct {
    mu       sync.Mutex
    limiters map[string]*rate.Limiter
    rate     rate.Limit
    burst    int
}
```

**预计工作量：** 1 天

---

### 任务 3：用户系统（模型 + Handler）

**文件路径：**
- `server/internal/models/user.go`
- `server/internal/handlers/auth.go`
- `server/internal/handlers/user.go`

**关键代码结构：**

```go
// models/user.go
type User struct {
    ID           int64  `json:"id"`
    Email        string `json:"email"`
    PasswordHash string `json:"-"`
    Nickname     string `json:"nickname"`
    AvatarURL    string `json:"avatar_url"`
    CreatedAt    string `json:"created_at"`
    UpdatedAt    string `json:"updated_at"`
}

func CreateUser(db *sql.DB, email, passwordHash, nickname string) (*User, error)
func GetUserByEmail(db *sql.DB, email string) (*User, error)
func GetUserByID(db *sql.DB, id int64) (*User, error)
func UpdateUser(db *sql.DB, id int64, nickname, avatarURL string) error

// handlers/auth.go
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) GetMe(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) UpdateMe(w http.ResponseWriter, r *http.Request)
```

**预计工作量：** 1.5 天

---

### 任务 4：分享链接模块

**文件路径：**
- `server/internal/models/share.go`
- `server/internal/handlers/share.go`

**关键代码结构：**

```go
// models/share.go
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

func GenerateCode() string  // 生成 6~8 位短码 (大小写字母+数字)
func CreateShare(db *sql.DB, userID int64, subject string, year int, season, paperType, expiry string) (*Share, error)
func GetShareByCode(db *sql.DB, code string) (*Share, error)
func DeleteShare(db *sql.DB, code string, userID int64) error
func ListSharesByUser(db *sql.DB, userID int64) ([]Share, error)
func IncrementViewCount(db *sql.DB, code string) error
```

**预计工作量：** 1 天

---

### 任务 5：学习小组模块

**文件路径：**
- `server/internal/models/group.go`
- `server/internal/handlers/group.go`
- `server/internal/handlers/sse.go`

**关键代码结构：**

```go
// models/group.go
type Group struct {
    ID          int64  `json:"id"`
    Name        string `json:"name"`
    Description string `json:"description"`
    InviteCode  string `json:"invite_code"`
    OwnerID     int64  `json:"owner_id"`
    CreatedAt   string `json:"created_at"`
}

type GroupMember struct {
    GroupID  int64  `json:"group_id"`
    UserID   int64  `json:"user_id"`
    Role     string `json:"role"`     // owner/admin/member
    JoinedAt string `json:"joined_at"`
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
    Status       string `json:"status"`   // pending/downloaded
    UpdatedAt    string `json:"updated_at"`
}

func CreateGroup(db *sql.DB, name, desc string, ownerID int64) (*Group, error)
func JoinGroup(db *sql.DB, inviteCode string, userID int64) error
func LeaveGroup(db *sql.DB, groupID, userID int64) error
func ListGroupsByUser(db *sql.DB, userID int64) ([]Group, error)
func GetGroupDetail(db *sql.DB, groupID int64) (*Group, []GroupMember, []GroupPaper, error)
func AddGroupPaper(db *sql.DB, groupID, userID int64, paper GroupPaper) error
func RemoveGroupPaper(db *sql.DB, groupID, paperID, userID int64) error
func UpdateProgress(db *sql.DB, groupPaperID, userID int64, status string) error
func GetProgress(db *sql.DB, groupID int64) ([]GroupDownload, error)

// handlers/sse.go — SSE 事件推送
type SSEHub struct {
    mu      sync.RWMutex
    clients map[int64]map[chan SSEEvent]bool  // groupID -> set of channels
}

func (h *SSEHub) Subscribe(groupID int64) chan SSEEvent
func (h *SSEHub) Unsubscribe(groupID int64, ch chan SSEEvent)
func (h *SSEHub) Broadcast(groupID int64, event SSEEvent)
```

**预计工作量：** 2 天

---

### 任务 6：试卷评价模块

**文件路径：**
- `server/internal/models/review.go`
- `server/internal/handlers/review.go`

**关键代码结构：**

```go
// models/review.go
type Review struct {
    ID         int64    `json:"id"`
    UserID     int64    `json:"user_id"`
    Subject    string   `json:"subject"`
    Year       int      `json:"year"`
    Season     string   `json:"season"`
    PaperType  string   `json:"paper_type"`
    Filename   string   `json:"filename"`
    Rating     int      `json:"rating"`      // 1-5
    Difficulty int      `json:"difficulty"`  // 1-5
    Tags       []string `json:"tags"`
    Comment    string   `json:"comment"`
    CreatedAt  string   `json:"created_at"`
}

func CreateReview(db *sql.DB, userID int64, r Review) (*Review, error)
func ListReviews(db *sql.DB, subject string, year int, season string) ([]Review, error)
func GetReviewStats(db *sql.DB, subject string) (map[string]interface{}, error)
func DeleteReview(db *sql.DB, reviewID, userID int64) error
```

**预计工作量：** 1 天

---

### 任务 7：路由注册 + 服务端集成测试

**文件路径：**
- `server/internal/router/router.go`
- `server/cmd/server/main.go`（完善）
- `server/internal/handlers/auth_test.go`
- `server/internal/handlers/share_test.go`
- `server/internal/handlers/group_test.go`
- `server/internal/handlers/review_test.go`

**关键代码结构：**

```go
// router/router.go
func Setup(db *sql.DB, cfg *config.Config) http.Handler {
    r := chi.NewRouter()
    r.Use(middleware.Logger)
    r.Use(cors.Handler(cors.Options{
        AllowedOrigins: cfg.AllowedOrigins,
        AllowedMethods: []string{"GET", "POST", "PUT", "DELETE"},
        AllowedHeaders: []string{"Authorization", "Content-Type"},
    }))
    r.Use(middleware.RateLimit(cfg.RateLimit))

    r.Route("/api", func(r chi.Router) {
        r.Get("/health", handlers.HealthCheck)

        r.Post("/auth/register", authHandler.Register)
        r.Post("/auth/login", authHandler.Login)
        r.Post("/auth/refresh", authHandler.Refresh)

        r.Group(func(r chi.Router) {
            r.Use(middleware.Auth(cfg.JWTSecret))
            r.Get("/me", authHandler.GetMe)
            r.Put("/me", authHandler.UpdateMe)
            // ... 分享、小组、评价路由
        })

        // 无需认证的公开路由
        r.Get("/share/{code}", shareHandler.GetByCode)
        r.Get("/reviews", reviewHandler.List)
        r.Get("/reviews/stats", reviewHandler.Stats)
    })
    return r
}
```

**预计工作量：** 1.5 天

---

### 任务 8：桌面端 Python 协作客户端

**文件路径：**
- `src/backend/collab_client.py`（新增）

**关键代码结构：**

```python
"""collab_client.py — 协作服务端 HTTP 客户端"""
import requests
from .cache import read_json, write_json

class CollabClient:
    def __init__(self, base_url: str = ""):
        self._base_url = base_url  # 服务端地址，如 "https://cpaper-api.fly.dev"
        self._token = ""           # JWT access_token
        self._refresh_token = ""   # JWT refresh_token
        self._token_path = os.path.join(CACHE_DIR, "collab_token.json")
        self._session = requests.Session()
        self._load_tokens()

    # ── 认证 ──
    def register(self, email: str, password: str, nickname: str) -> dict
    def login(self, email: str, password: str) -> dict
    def logout(self) -> None
    def is_logged_in(self) -> bool
    def get_me(self) -> dict
    def update_me(self, nickname: str = "", avatar_url: str = "") -> dict

    # ── 分享 ──
    def create_share(self, subject: str, year: int, season: str,
                     paper_type: str = "", expiry: str = "7d") -> dict
    def get_share(self, code: str) -> dict
    def delete_share(self, code: str) -> dict
    def list_my_shares(self) -> dict

    # ── 小组 ──
    def create_group(self, name: str, description: str = "") -> dict
    def join_group(self, invite_code: str) -> dict
    def leave_group(self, group_id: int) -> dict
    def list_groups(self) -> dict
    def get_group(self, group_id: int) -> dict
    def add_group_paper(self, group_id: int, subject: str, year: int,
                        season: str, paper_type: str, filename: str,
                        download_url: str = "") -> dict
    def remove_group_paper(self, group_id: int, paper_id: int) -> dict
    def update_progress(self, group_id: int, paper_id: int, status: str) -> dict
    def get_progress(self, group_id: int) -> dict

    # ── 评价 ──
    def create_review(self, subject: str, year: int, season: str,
                      rating: int, difficulty: int, comment: str = "",
                      tags: list = None, paper_type: str = "",
                      filename: str = "") -> dict
    def list_reviews(self, subject: str = "", year: int = 0,
                     season: str = "") -> dict
    def get_review_stats(self, subject: str) -> dict
    def delete_review(self, review_id: int) -> dict

    # ── SSE ──
    def subscribe_group_events(self, group_id: int, callback) -> threading.Thread

    # ── 内部方法 ──
    def _request(self, method: str, path: str, **kwargs) -> dict
    def _refresh_if_needed(self) -> None
    def _load_tokens(self) -> None
    def _save_tokens(self) -> None
```

**预计工作量：** 1.5 天

---

### 任务 9：桌面端 API 桥接层扩展

**文件路径：**
- `src/backend/api.py`（修改：新增协作相关方法）
- `src/backend/const.py`（修改：新增服务端 URL 常量）

**关键代码结构（新增到 API 类中）：**

```python
# api.py 中新增方法

# ── 协作：认证 ──
def collab_register(self, email, password, nickname):
    return json.dumps(self._collab.register(email, password, nickname))

def collab_login(self, email, password):
    return json.dumps(self._collab.login(email, password))

def collab_logout(self):
    self._collab.logout()
    return json.dumps({"ok": True})

def collab_is_logged_in(self):
    return json.dumps({"logged_in": self._collab.is_logged_in()})

def collab_get_me(self):
    return json.dumps(self._collab.get_me())

def collab_update_me(self, nickname, avatar_url):
    return json.dumps(self._collab.update_me(nickname, avatar_url))

# ── 协作：分享 ──
def collab_create_share(self, subject, year, season, paper_type, expiry):
    return json.dumps(self._collab.create_share(subject, int(year), season, paper_type, expiry))

def collab_get_share(self, code):
    return json.dumps(self._collab.get_share(code))

def collab_delete_share(self, code):
    return json.dumps(self._collab.delete_share(code))

def collab_list_shares(self):
    return json.dumps(self._collab.list_my_shares())

# ── 协作：小组 ──
def collab_create_group(self, name, description):
    return json.dumps(self._collab.create_group(name, description))

def collab_join_group(self, invite_code):
    return json.dumps(self._collab.join_group(invite_code))

# ... 其余小组和评价方法同理
```

**const.py 新增：**

```python
COLLAB_SERVER_URL = os.environ.get("CPAPER_COLLAB_URL", "https://cpaper-api.fly.dev")
```

**预计工作量：** 1 天

---

### 任务 10：桌面端 UI 集成 — 协作面板

**文件路径：**
- `src/ui_v2.html`（修改：新增协作面板 HTML）
- `src/ui_v2.js`（修改：新增协作 JS 逻辑）
- `src/ui_v2.css`（修改：新增协作样式）

**UI 新增内容：**

1. **左侧导航栏新增按钮：**
   - "分享" 按钮（link 图标）
   - "小组" 按钮（users 图标）
   - "评价" 按钮（star 图标）

2. **用户登录状态区域（导航栏底部）：**
   - 未登录：显示"登录"按钮，点击弹出登录/注册对话框
   - 已登录：显示头像 + 昵称，点击弹出用户菜单（个人信息、退出）

3. **分享面板 (`pnl-share`)：**
   - 创建分享表单（选择科目/年份/季节、过期时间）
   - 我的分享列表（短码、访问次数、过期时间、删除按钮）
   - 打开分享输入框（输入短码查看他人分享）

4. **小组面板 (`pnl-groups`)：**
   - 我的小组列表卡片
   - 创建小组表单
   - 加入小组（输入邀请码）
   - 小组详情视图（成员列表、共享试卷列表、下载进度）
   - 添加试卷到小组

5. **评价面板 (`pnl-reviews`)：**
   - 搜索评价（按科目/年份/季节筛选）
   - 提交评价表单（星级评分、难度选择、标签、评语）
   - 评价列表（卡片式展示，显示评分、难度、评语）
   - 评分统计图表

**预计工作量：** 2.5 天

---

### 任务 11：Dockerfile + 部署配置

**文件路径：**
- `server/Dockerfile`
- `server/fly.toml`（Fly.io 配置）
- `server/.env.example`

**关键代码结构：**

```dockerfile
# server/Dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 GOOS=linux go build -o server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates sqlite
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
VOLUME ["/app/data"]
CMD ["./server"]
```

```toml
# server/fly.toml
app = "cpaper-api"
primary_region = "hkg"

[build]
  dockerfile = "Dockerfile"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true

[env]
  PORT = "8080"
  DB_PATH = "/app/data/cpaper.db"

[[mounts]]
  source = "cpaper_data"
  destination = "/app/data"
```

**预计工作量：** 0.5 天

---

### 任务总览

| # | 任务 | 工作量 | 依赖 |
|---|------|--------|------|
| 1 | Go 服务端基础设施 | 1.5 天 | 无 |
| 2 | 中间件实现 | 1 天 | 任务 1 |
| 3 | 用户系统 | 1.5 天 | 任务 1, 2 |
| 4 | 分享链接模块 | 1 天 | 任务 3 |
| 5 | 学习小组模块 | 2 天 | 任务 3 |
| 6 | 试卷评价模块 | 1 天 | 任务 3 |
| 7 | 路由注册 + 集成测试 | 1.5 天 | 任务 2-6 |
| 8 | 桌面端 Python 客户端 | 1.5 天 | 任务 7 |
| 9 | 桌面端 API 桥接层 | 1 天 | 任务 8 |
| 10 | 桌面端 UI 集成 | 2.5 天 | 任务 9 |
| 11 | 部署配置 | 0.5 天 | 任务 7 |
| **合计** | | **15 天** | |

**建议执行顺序：** 任务 1 → 2 → 3 → (4, 5, 6 并行) → 7 → (8, 11 并行) → 9 → 10

---

## 五、前后端集成方案

### 5.1 通信架构

```
┌─────────────────────────────────────────────────┐
│  桌面端 (Python/pywebview)                        │
│                                                   │
│  ui_v2.js  ←→  pywebview JS Bridge  ←→  api.py  │
│                                                  │
│  api.py  ──uses──→  collab_client.py             │
│                          │                        │
│                          │ HTTP (requests)        │
│                          ▼                        │
│  ┌─────────────────────────────────────────┐     │
│  │  Go 协作服务端 (Fly.io / Railway)       │     │
│  │  HTTPS + JWT + SQLite                   │     │
│  └─────────────────────────────────────────┘     │
└─────────────────────────────────────────────────┘
```

### 5.2 调用流程示例：创建分享

```
1. 用户在 UI 点击"创建分享"
2. ui_v2.js 调用: pywebview.api.collab_create_share("9709", 2023, "Jun", "qp", "7d")
3. api.py 中 collab_create_share() 调用 self._collab.create_share(...)
4. collab_client.py 发送 HTTP POST 到服务端:
   POST https://cpaper-api.fly.dev/api/share
   Headers: {Authorization: "Bearer <jwt>"}
   Body: {subject: "9709", year: 2023, season: "Jun", paper_type: "qp", expiry: "7d"}
5. 服务端处理请求，创建分享记录，返回 {code: "Xy3kM9", ...}
6. collab_client.py 返回 dict 给 api.py
7. api.py 返回 JSON 字符串给 JS
8. ui_v2.js 解析结果，显示分享码给用户
```

### 5.3 SSE 实时通信集成

```python
# collab_client.py 中的 SSE 订阅
def subscribe_group_events(self, group_id: int, callback) -> threading.Thread:
    def _listen():
        url = f"{self._base_url}/api/groups/{group_id}/events"
        headers = {"Authorization": f"Bearer {self._token}"}
        resp = requests.get(url, headers=headers, stream=True, timeout=(5, None))
        for line in resp.iter_lines():
            if line:
                event = self._parse_sse(line)
                if event:
                    callback(event)
    t = threading.Thread(target=_listen, daemon=True)
    t.start()
    return t
```

### 5.4 离线降级策略

当协作服务端不可用时（网络断开、服务器宕机），桌面端应：

1. **静默降级** — 协作功能按钮显示为灰色，tooltip 提示"服务暂时不可用"
2. **不影响核心功能** — 搜索、下载、收藏等本地功能完全正常
3. **重试机制** — `collab_client.py` 内部对 5xx 错误自动重试 3 次
4. **缓存用户状态** — JWT token 和用户信息缓存到本地文件，离线时仍可显示已登录状态

---

## 六、依赖清单

### 6.1 Go Modules（服务端）

```go
// go.mod
require (
    github.com/go-chi/chi/v5    v5.1.0    // HTTP 路由
    github.com/go-chi/cors      v1.2.1    // CORS 中间件
    github.com/golang-jwt/jwt/v5 v5.2.1   // JWT 签发/验证
    github.com/mattn/go-sqlite3  v1.14.24 // SQLite 驱动 (CGO)
    golang.org/x/crypto          v0.31.0  // bcrypt 密码哈希
    golang.org/x/time            v0.9.0   // rate.Limiter（速率限制）
)
```

### 6.2 Python Packages（桌面端新增）

```
# requirements.txt 新增（无新增，requests 已有）
# collab_client.py 仅依赖标准库 + requests，无需额外包
```

桌面端 v6.0-alpha 不需要新增 Python 依赖。`collab_client.py` 使用已有的 `requests` 库进行 HTTP 调用。

### 6.3 系统依赖（构建时）

```
Go 1.22+
GCC / CGO（go-sqlite3 需要 CGO 编译）
```

---

## 七、测试策略

### 7.1 Go 服务端单元测试

| 测试文件 | 覆盖范围 | 关键用例 |
|----------|----------|----------|
| `handlers/auth_test.go` | 注册、登录、token 刷新 | 邮箱重复注册、密码错误、token 过期 |
| `handlers/share_test.go` | 创建/获取/删除分享 | 短码唯一性、过期时间生效、权限校验 |
| `handlers/group_test.go` | 小组 CRUD、成员管理 | 邀请码加入、非成员拒绝、owner 权限 |
| `handlers/review_test.go` | 评价 CRUD、统计 | 评分范围校验、一人一卷一评去重 |
| `middleware/auth_test.go` | JWT 中间件 | 有效 token、过期 token、无 token |
| `middleware/ratelimit_test.go` | 速率限制 | 正常请求、超限 429 |

**测试工具：** `net/http/httptest` + `testing` 标准库

```go
// 示例：注册测试
func TestRegister(t *testing.T) {
    db := setupTestDB(t)
    defer db.Close()
    handler := NewAuthHandler(db, testConfig)

    body := `{"email":"test@example.com","password":"password123","nickname":"Test"}`
    req := httptest.NewRequest("POST", "/api/auth/register", strings.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    w := httptest.NewRecorder()
    handler.Register(w, req)

    assert.Equal(t, 200, w.Code)
    var resp map[string]interface{}
    json.Unmarshal(w.Body.Bytes(), &resp)
    assert.NotEmpty(t, resp["access_token"])
}
```

### 7.2 Go 集成测试

使用内存 SQLite 数据库进行端到端测试：

```go
func setupTestDB(t *testing.T) *sql.DB {
    db, err := sql.Open("sqlite3", ":memory:")
    require.NoError(t, err)
    database.Migrate(db)
    return db
}
```

测试场景：
- 完整的注册 → 登录 → 创建分享 → 访问分享流程
- 创建小组 → 邀请加入 → 添加试卷 → 更新进度流程
- 提交评价 → 查询评价 → 统计评分流程

### 7.3 Python 客户端测试

**文件路径：** `tests/test_collab_client.py`

```python
import pytest
from unittest.mock import patch, MagicMock
from backend.collab_client import CollabClient

class TestCollabClient:
    def test_login_success(self):
        client = CollabClient("http://localhost:8080")
        with patch.object(client._session, 'post') as mock_post:
            mock_post.return_value = MagicMock(
                status_code=200,
                json=lambda: {"access_token": "abc", "refresh_token": "def", "user": {"id": 1}}
            )
            result = client.login("test@example.com", "pass123")
            assert result["ok"]
            assert client.is_logged_in()

    def test_login_failure(self):
        client = CollabClient("http://localhost:8080")
        with patch.object(client._session, 'post') as mock_post:
            mock_post.return_value = MagicMock(
                status_code=401,
                json=lambda: {"error": "invalid credentials"}
            )
            result = client.login("test@example.com", "wrong")
            assert not result["ok"]

    def test_create_share_offline(self):
        client = CollabClient("http://localhost:8080")
        client._token = "valid_token"
        with patch.object(client._session, 'post') as mock_post:
            mock_post.side_effect = requests.ConnectionError("offline")
            result = client.create_share("9709", 2023, "Jun")
            assert not result["ok"]
            assert "网络" in result.get("error", "") or "连接" in result.get("error", "")
```

### 7.4 UI 手动测试清单

| 场景 | 验证点 |
|------|--------|
| 未登录状态 | 协作功能按钮显示登录提示 |
| 注册 → 登录 | 流程顺畅，token 持久化 |
| 创建分享 | 分享码正确显示，可复制 |
| 打开分享 | 输入短码后正确显示试卷信息 |
| 创建小组 | 邀请码生成，可复制 |
| 加入小组 | 凭邀请码成功加入 |
| 小组详情 | 成员列表、试卷列表正确展示 |
| 提交评价 | 评分、难度选择正常，提交成功 |
| 评价列表 | 按科目筛选正确，评分统计正确 |
| 离线降级 | 服务不可用时功能灰色，不影响搜索/下载 |
| 暗色主题 | 协作面板在暗色主题下样式正确 |

---

## 八、部署方案

### 8.1 Fly.io 免费实例部署

**为什么选择 Fly.io：**
- 免费额度：3 个共享 CPU 实例 + 3GB 持久化存储
- 支持 SQLite（挂载 Volume）
- 自动 HTTPS
- 香港区域（hkg），对国内用户延迟低

**部署步骤：**

```bash
# 1. 安装 flyctl
curl -L https://fly.io/install.sh | sh

# 2. 登录
fly auth login

# 3. 在 server/ 目录初始化
cd server/
fly launch --name cpaper-api --region hkg

# 4. 创建持久化卷（SQLite 数据存储）
fly volumes create cpaper_data --region hkg --size 1

# 5. 设置 JWT secret
fly secrets set JWT_SECRET=$(openssl rand -base64 32)

# 6. 部署
fly deploy

# 7. 验证
fly status
curl https://cpaper-api.fly.dev/api/health
```

### 8.2 备选方案：Railway

如果 Fly.io 不可用，可选择 Railway：
- 免费额度：$5/月
- 支持 Docker 部署
- 自动 HTTPS
- 但不支持持久化 Volume（需要改用 Turso 或其他方案）

### 8.3 本地开发部署

```bash
# Go 服务端本地启动
cd server/
export JWT_SECRET=dev-secret-key
export PORT=8080
export DB_PATH=./dev.db
go run ./cmd/server

# 桌面端配置服务端地址
export CPAPER_COLLAB_URL=http://localhost:8080
cd src/
python main.py
```

### 8.4 监控与运维

- **健康检查：** `GET /api/health` 返回服务状态和 SQLite 连接状态
- **日志：** Go 标准 log 包，Fly.io 自动收集
- **数据库备份：** 定期 `sqlite3 data.db ".backup backup.db"` 或 Fly.io Volume 快照
- **过期清理：** 后台 goroutine 每小时清理过期分享记录

---

## 九、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Fly.io 免费实例冷启动慢 | 首次请求延迟 5-10s | 设置 `auto_start_machines = true`；客户端加 loading 提示 |
| SQLite 并发写入锁 | 高并发时写入排队 | WAL 模式 + `_busy_timeout=5000`；免费实例用户量小，不是问题 |
| CGO 交叉编译复杂 | macOS/Windows 构建不同 | Docker 多阶段构建，统一 Linux 二进制 |
| JWT secret 泄露 | 安全风险 | 使用 Fly.io secrets 管理，不硬编码 |
| 桌面端 UI 空间有限 | 协作面板拥挤 | 使用 tab 切换，不新增独立面板，复用现有导航栏模式 |

---

## 十、附录

### 10.1 现有代码文件清单（需要修改的）

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `src/backend/api.py` | 修改 | 新增 `CollabClient` 实例 + 协作方法 |
| `src/backend/const.py` | 修改 | 新增 `COLLAB_SERVER_URL` 常量 |
| `src/ui_v2.html` | 修改 | 新增协作导航按钮 + 面板 + 登录对话框 |
| `src/ui_v2.js` | 修改 | 新增协作相关 JS 函数 |
| `src/ui_v2.css` | 修改 | 新增协作面板样式 |
| `requirements.txt` | 不变 | 无新增依赖 |
| `.gitignore` | 修改 | 新增 `server/data.db`、`server/dev.db` |

### 10.2 新增文件清单

| 文件 | 说明 |
|------|------|
| `server/go.mod` | Go 模块定义 |
| `server/go.sum` | 依赖校验 |
| `server/cmd/server/main.go` | 服务端入口 |
| `server/internal/config/config.go` | 配置加载 |
| `server/internal/database/db.go` | 数据库连接 |
| `server/internal/database/migrations.go` | Schema 迁移 |
| `server/internal/middleware/auth.go` | JWT 中间件 |
| `server/internal/middleware/ratelimit.go` | 速率限制中间件 |
| `server/internal/middleware/cors.go` | CORS 中间件 |
| `server/internal/middleware/logger.go` | 日志中间件 |
| `server/internal/models/user.go` | 用户模型 |
| `server/internal/models/share.go` | 分享模型 |
| `server/internal/models/group.go` | 小组模型 |
| `server/internal/models/review.go` | 评价模型 |
| `server/internal/handlers/auth.go` | 认证 Handler |
| `server/internal/handlers/share.go` | 分享 Handler |
| `server/internal/handlers/group.go` | 小组 Handler |
| `server/internal/handlers/review.go` | 评价 Handler |
| `server/internal/handlers/sse.go` | SSE Handler |
| `server/internal/router/router.go` | 路由注册 |
| `server/Dockerfile` | Docker 构建文件 |
| `server/fly.toml` | Fly.io 部署配置 |
| `server/.env.example` | 环境变量示例 |
| `src/backend/collab_client.py` | Python 协作客户端 |
| `tests/test_collab_client.py` | 客户端单元测试 |

