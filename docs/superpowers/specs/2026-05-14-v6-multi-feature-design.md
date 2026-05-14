# C-Paper v6.0 功能设计文档

> 主题：移动端 + 协作 + 智能化
> 版本：v6.0
> 日期：2026-05-14
> 状态：草稿

---

## 一、概述

### 1.1 背景

C-Paper v5.2 是一个功能成熟的跨平台桌面应用。v6.0 是项目最大的版本跃迁，新增三大方向：
- **多端覆盖**：从桌面扩展到移动端
- **协作联机**：用户系统 + 分享 + 学习小组 + 试卷评价
- **智能化**：AI 试卷分析、OCR 题目提取、智能去重

### 1.2 目标

1. **移动端 App** — iOS + Android 独立原生应用
2. **分享链接** — 一键生成试卷分享链接，其他用户凭链接快速搜索/下载
3. **学习小组** — 创建/加入小组，成员共享试卷列表和下载进度
4. **试卷评价** — 对历年试卷评分、标记难度、写评语
5. **AI 试卷分析** — LLM 分析试卷考点分布、重复题型
6. **OCR 题目提取** — 从 PDF 提取题目文本，支持全文搜索
7. **智能去重** — 识别不同年份的重复/相似题目，标注相似度

### 1.3 架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                        客户端层                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ macOS App │  │ Windows  │  │ iOS App  │  ┌──────────┐       │
│  │ (pywebview)│  │ App      │  │ (SwiftUI)│  │ Android  │       │
│  └─────┬─────┘  └─────┬────┘  └─────┬────┘  │ App      │       │
│        │              │              │       └─────┬─────┘       │
│        ▼              ▼              ▼             ▼             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    本地引擎层                              │   │
│  │  搜索/下载引擎  │  插件系统  │  OCR引擎  │  AI分析引擎     │   │
│  │  (直连数据源)   │  (Python钩子)│(本地OCR) │ (用户自带Key)   │   │
│  └─────────────────────────────────────────────────────────┘   │
│        │                                                         │
│        ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 协作服务端 (轻量)                          │   │
│  │  用户系统  │  分享服务  │  小组服务  │  评价服务           │   │
│  │  (免费实例) │  (短链接)  │  (实时同步)│  (评分/评语)       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 非目标

- 不实现应用内购买/付费系统（首期免费使用）
- 不实现试卷内容托管（版权原因，搜索/下载仍从第三方获取）
- 不实现 AI 模型训练/微调（使用外部 LLM API）
- 移动端首期不做插件系统（技术限制，后续迭代）

---

## 二、协作服务端

### 2.1 技术选型

| 维度 | 选择 |
|---|---|
| 语言 | Go（编译后二进制小，内存低，适合免费实例） |
| 框架 | 标准库 net/http + 路由库（chi 或 gin 探索阶段定） |
| 数据库 | SQLite（零配置，免费实例通常不带独立 DB 服务） |
| 认证 | bcrypt 密码哈希 + JWT（邮箱登录）+ OAuth 2.0（Apple/飞书） |
| 部署 | 免费云实例（如 Fly.io free tier, Railway, Deta Space） |

### 2.2 API 设计

#### 账号系统

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/register` | 邮箱+密码注册 |
| POST | `/api/auth/login` | 邮箱+密码登录，返回 JWT |
| POST | `/api/auth/refresh` | 刷新 JWT |
| GET | `/api/auth/oauth/apple` | Apple OAuth 回调 |
| GET | `/api/auth/oauth/lark` | 飞书 OAuth 回调 |
| GET | `/api/me` | 获取当前用户信息 |
| PUT | `/api/me` | 更新用户信息（头像、昵称） |

#### 分享链接

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/share` | 创建试卷分享（subject, year, season, 过期时间） |
| GET | `/api/share/:code` | 获取分享内容（无需登录） |
| DELETE | `/api/share/:code` | 删除分享 |
| GET | `/api/shares` | 我的分享列表 |

分享码为 6~8 位短码（大小写字母+数字），如 `Xy3kM9`。设置过期时间（1天/7天/30天/永久）。

#### 学习小组

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/groups` | 创建小组 |
| POST | `/api/groups/:id/join` | 加入小组（凭邀请码） |
| POST | `/api/groups/:id/leave` | 退出小组 |
| GET | `/api/groups` | 我的小组列表 |
| GET | `/api/groups/:id` | 小组详情（成员、共享列表） |
| POST | `/api/groups/:id/papers` | 添加共享试卷 |
| DELETE | `/api/groups/:id/papers/:paperId` | 移除共享试卷 |
| GET | `/api/groups/:id/progress` | 成员下载进度 |

#### 试卷评价

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/reviews` | 提交评价（rating 1-5, difficulty 1-5, tags[], comment） |
| GET | `/api/reviews?subject=X&year=Y` | 获取某试卷的评价列表 |
| GET | `/api/reviews/stats?subject=X` | 某科目各年评分统计 |
| DELETE | `/api/reviews/:id` | 删除我的评价 |

### 2.3 数据模型

```
users
  id, email, password_hash, nickname, avatar_url, oauth_provider,
  oauth_id, created_at, updated_at

shares
  id, user_id, code, subject, year, season, paper_type,
  expires_at, view_count, created_at

groups
  id, name, description, invite_code, owner_id, created_at

group_members
  group_id, user_id, role(owner/admin/member), joined_at

group_papers
  id, group_id, added_by, subject, year, season, paper_type,
  filename, download_url, created_at

group_downloads
  group_paper_id, user_id, status(pending/downloaded), updated_at

reviews
  id, user_id, subject, year, season, paper_type, filename,
  rating(1-5), difficulty(1-5), tags(json), comment, created_at

review_reactions
  review_id, user_id, reaction(helpful/useful/etc)
```

### 2.4 实时通信

学习小组的下载进度更新使用 **Server-Sent Events (SSE)**，避免 WebSocket 开销：

```
每个客户端下载完成后 → POST /api/groups/:id/progress（更新 group_downloads 表）
                  → 服务端推送 SSE 事件给所有在线组员
```

SSE 端点：
```
GET /api/groups/:id/events
→ stream: event: progress_update, data: {"user":"xxx","paper":"yyy","status":"downloaded"}
```

### 2.5 安全设计

| 措施 | 说明 |
|---|---|
| 密码哈希 | bcrypt cost=12 |
| JWT 签名 | HS256, 7天过期 + refresh token 30天 |
| 速率限制 | 每 IP 每分钟最多 60 请求，注册/登录接口 5 次/分钟 |
| CORS | 仅允许客户端 origin |
| 输入验证 | 所有输入做长度/格式校验，防 SQL 注入（参数化查询） |
| 分享保护 | 必选过期时间，默认 7 天 |

---

## 三、移动端 App

### 3.1 技术选型

| 平台 | 技术 |
|---|---|
| iOS | SwiftUI + Combine（最小支持 iOS 17） |
| Android | Jetpack Compose + Kotlin（最小支持 API 30） |
| 共享代码 | 不追求跨平台代码复用，两个原生 App 各自开发 |
| 网络层 | Alamofire (iOS) / Retrofit (Android) |

### 3.2 功能范围

移动端首期包含以下功能（对标桌面端 v5.2 核心功能）：

| 功能 | iOS | Android | 说明 |
|---|---|---|---|
| 科目搜索 | ✓ | ✓ | 同桌面端搜索流程 |
| 批量下载 | ✓ | ✓ | 多线程下载，限速，断点续传 |
| 文件预览 | ✓ | ✓ | 内嵌 PDF 查看器 |
| 收藏管理 | ✓ | ✓ | 云端同步（通过协作服务端） |
| 主题切换 | ✓ | ✓ | 明/暗主题 |
| 账号登录 | ✓ | ✓ | 邮箱 + Apple/飞书 OAuth |
| 分享链接 | ✓ | ✓ | 创建/打开分享 |
| 学习小组 | ✓ | ✓ | 创建/加入/查看 |
| 试卷评价 | ✓ | ✓ | 评分+评语 |
| AI 分析 | ✓ | ✓ | 本地 AI 分析（需配 API key） |
| OCR 提取 | ✓ | ✓ | 本地 OCR |
| 智能去重 | ✓ | ✗ | iOS 先做，Android 后续 |

### 3.3 UI 设计原则

- 底部 Tab 导航（搜索、小组、收藏、我的）
- 下拉刷新 + 无限滚动
- 原生手势支持（滑动删除收藏等）
- 适配 iOS Dynamic Island / Android 通知栏下载进度

### 3.4 与桌面端的差异

| 差异 | 说明 |
|---|---|
| 插件系统 | 移动端首期不支持 |
| 代理配置 | 移动端不支持（系统级代理即可） |
| 快捷键 | 不适用 |
| 下载目录 | iOS 默认 Files App 目录，Android 默认 Downloads |

---

## 四、AI 试卷分析

### 4.1 功能描述

用户选择一个已下载的 PDF 试卷，点击"AI 分析"，系统：
1. 本地 OCR 提取 PDF 文本（见第五节）
2. 提取的文本发送给 LLM API
3. LLM 返回结构化分析结果
4. 结果在客户端缓存，关联到该试卷

### 4.2 LLM 调用

| 维度 | 选择 |
|---|---|
| API | OpenAI API、Anthropic API、通义千问 API（用户可配置） |
| API Key | 用户自带，存储在客户端本地，不上传服务端 |
| 模型 | 用户可选（如 GPT-4o-mini 性价比高，Sonnet 分析质量好） |
| 缓存 | 分析结果本地缓存，同一试卷不重复分析 |

### 4.3 分析输出

```json
{
  "paper_info": {
    "subject": "9709 Mathematics",
    "year": 2023,
    "season": "Summer",
    "paper_number": 12,
    "total_marks": 75,
    "question_count": 10
  },
  "topics": [
    {"name": "Differentiation", "questions": [1, 5, 7], "total_marks": 22},
    {"name": "Integration", "questions": [2, 8, 10], "total_marks": 25}
  ],
  "difficulty_distribution": {
    "easy": 3, "medium": 4, "hard": 3
  },
  "repeated_from_previous": [
    {"question": 4, "similar_to": "9709_s22_qp_12 Q3", "similarity": 0.85}
  ],
  "summary": "本卷以微积分为主(62%)，其中第7题、第10题为新题型..."
}
```

### 4.4 UI 展示

- 分析结果以卡片形式展示
- 考点分布用饼图/条形图可视化
- 重复题型高亮并附链接到相似试卷
- 支持导出为 Markdown/PDF 报告

### 4.5 安全与隐私

- 提取的文本只在本地处理，上传到 LLM API 是用户行为（用户控制 key）
- 分析结果保存本地，不上传服务端
- 首次使用时提示用户配置 API key，附说明引导

---

## 五、OCR 题目提取

### 5.1 功能描述

从 PDF 试卷中提取题目文本，有两个使用场景：
1. 为 AI 分析提供文本输入
2. 独立使用：提取后可全文搜索题目内容

### 5.2 技术方案

| 维度 | 选择 |
|---|---|
| PDF 工具 | pdfplumber (Python/macOS/Windows) / PDFKit (iOS) / PdfRenderer (Android) |
| OCR 引擎 | Tesseract 5.x（本地，无需网络） |
| 预处理 | 图片增强（去噪、二值化、倾斜校正）提高识别率 |
| 语言 | 英文为主（数学符号/公式单独处理） |

### 5.3 工作流程

```
PDF 文件
  → 提取每页为图片（高 DPI）
  → 图片预处理（去噪/二值化）
  → Tesseract OCR 识别
  → 后处理（数学符号修正、排版整理）
  → 输出结构化文本（按题目编号分段）
  → 建立全文索引（用于搜索）
```

### 5.4 数学公式处理

CIE 数学试卷包含大量公式。OCR 对纯文本准确率高（>95%），但对数学公式（积分号、分式、根号）识别率有限。策略：
- 数学公式标记为 `[formula]` 占位符
- 保留公式截图，分析报告中用图片展示
- 未来可考虑专用数学 OCR 模型（如 Nougat）

### 5.5 全文搜索

OCR 提取的文本建立本地 FTS（全文搜索）索引：
- 用户在搜索框输入关键词（如 "integration by parts"）
- 返回匹配的试卷和题目位置
- 高亮显示匹配文本

技术：SQLite FTS5（移动端和桌面端均可）

---

## 六、智能去重

### 6.1 功能描述

跨年份/季节比较试卷，识别重复或高度相似的题目。帮助用户：
- 避免重复练习相同题目
- 了解出题规律（某题反复出现说明是高频考点）
- 筛选新题（只看近 N 年新出现的题型）

### 6.2 技术方案

| 维度 | 选择 |
|---|---|
| 文本提取 | OCR 提取（第五节） |
| 文本向量化 | sentence-transformers（`all-MiniLM-L6-v2` 本地运行，80MB 模型） |
| 相似度计算 | 余弦相似度，阈值 >0.80 标记为"高度相似"，>0.65 标记为"可能相关" |
| 索引 | FAISS 或 Annoy（本地向量索引，毫秒级检索） |
| 存储 | SQLite 存相似对，UI 展示关联试卷列表 |

### 6.3 工作流程

```
OCR 提取文本
  → 分题（按题号分割）
  → 每道题生成 embedding（本地模型）
  → 存入本地向量索引
  → 新试卷加入时自动与已有题库比对
  → 相似度 > 阈值 → 标记关联
```

### 6.4 UI 展示

- 浏览试卷时，每道题旁显示"相似题"标签
- 点击查看关联的试卷和题号
- 相似度以百分比展示
- 按科目/年份筛选去重结果

### 6.5 性能考虑

| 操作 | 预计耗时 | 说明 |
|---|---|---|
| OCR 一份试卷 (20页) | 30-60秒 | 取决于设备性能 |
| 生成 embedding (10题) | <1秒 | 本地模型，CPU 即可 |
| 与已有题库比对 (1000题) | <500ms | FAISS 索引 |
| 首次建立全库索引 | 3-10分钟 | 后台运行，仅需一次 |

---

## 七、与现有系统的集成

### 7.1 桌面端修改

| 文件 | 修改内容 |
|---|---|
| `src/backend/api.py` | 新增 AI 分析、OCR、去重、协作服务端 API 调用方法 |
| `src/backend/ocr_engine.py` | **新增**：PDF 提取 + Tesseract OCR 封装 |
| `src/backend/ai_analyzer.py` | **新增**：LLM 调用封装，prompt 管理 |
| `src/backend/dedup_engine.py` | **新增**：embedding + 相似度计算 + 索引 |
| `src/backend/collab_client.py` | **新增**：协作服务端 HTTP 客户端 |
| `src/ui_v2.html` | 新增 AI/OCR/去重按钮，分享/小组/评价面板 |
| `src/ui_v2.js` | 新增对应 JS 逻辑 |
| `src/ui_v2.css` | 新增相应样式 |

### 7.2 移动端新建

| 目录 | 内容 |
|---|---|
| `ios/` | SwiftUI 项目（Xcode workspace） |
| `android/` | Jetpack Compose 项目（Gradle） |
| `docs/mobile/` | 移动端技术文档 |

### 7.3 协作服务端新建

| 目录 | 内容 |
|---|---|
| `server/` | Go 服务端代码 |
| `server/migrations/` | SQLite 迁移脚本 |

---

## 八、测试策略

### 8.1 协作服务端

| 场景 | 验证点 |
|---|---|
| 注册/登录 | 密码哈希正确，JWT 签发/校验 |
| OAuth 登录 | Apple/飞书回调正确，关联已有账号 |
| 分享创建/访问 | 短码唯一，过期时间生效 |
| 小组操作 | 创建/加入/退出/权限校验 |
| 评价 CRUD | 评分范围校验，去重（一人一卷一评） |
| 速率限制 | 超限返回 429 |

### 8.2 AI/OCR/去重

| 场景 | 验证点 |
|---|---|
| OCR 提取 | 英文准确率 >95%，分题正确 |
| LLM 分析 | 输出 JSON schema 正确，cache 命中跳过调用 |
| 去重 | similarity >0.80 对人工抽检正确，无假阳性 |
| API 配置 | 未配 key 时有引导提示 |

### 8.3 移动端

| 场景 | 验证点 |
|---|---|
| 搜索/下载 | 功能与桌面端一致 |
| 登录 | OAuth 流程正常 |
| 分享/小组 | UI 正确展示，实时更新 |
| 离线 | 无网络时本地功能可用 |

---

## 九、发布策略

由于 v6.0 涉及多个独立交付物，建议分阶段发布：

| 阶段 | 交付物 | 预计 |
|---|---|---|
| v6.0-alpha | 协作服务端上线 + 桌面端集成（分享+小组+评价） | 先 |
| v6.0-beta | AI 分析 + OCR + 去重（桌面端） | 中 |
| v6.0-rc | iOS App 首发 | 后 |
| v6.0 | Android App + 全部功能稳定 | 最终 |

---

## 十、附录

### 10.1 依赖清单

```
Python (桌面端新增):
  pdfplumber, pytesseract, Pillow, sentence-transformers, faiss-cpu, openai

Go (服务端):
  golang.org/x/crypto, github.com/golang-jwt/jwt, github.com/mattn/go-sqlite3,
  github.com/go-chi/chi, github.com/go-chi/cors

iOS:
  PDFKit (built-in), Vision (built-in OCR), CryptoKit (built-in)

Android:
  ML Kit Text Recognition (built-in), Room (built-in)
```

### 10.2 风险与缓解

| 风险 | 缓解措施 |
|---|---|
| 免费服务器不稳定 | 客户端做离线降级，分享/小组不可用时提示，搜索/下载仍可用 |
| OCR 数学公式识别差 | 标注为 `[formula]`，后续迭代 |
| LLM API 费用 | 用户自带 key，结果缓存避免重复调用 |
| 移动端开发量大 | iOS 先发，Android 跟进 |
| embedding 模型大 | 使用 tiny 模型（80MB），首次下载时提示 |
