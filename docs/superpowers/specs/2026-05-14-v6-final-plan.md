# C-Paper v6.0 最终阶段实现计划

> **阶段:** v6.0（最终发布）
> **主题:** iOS App 全部功能稳定 + 全面测试
> **日期:** 2026-05-14
> **前置依赖:** v6.0-alpha（协作服务端 + 桌面端集成）、v6.0-beta（AI/OCR/去重桌面端）、v6.0-rc（iOS App 首发）

---

## 一、概述

v6.0 最终阶段是整个 v6.0 版本线的收尾工作。前三阶段已分别交付了协作服务端、桌面端智能化功能、iOS App 基础框架。本阶段的核心目标是：

1. 将 AI 分析、OCR、智能去重三大智能化功能完整移植到 iOS 端
2. 补齐 Dynamic Island、离线模式等平台特性
3. 全面性能优化
4. 端到端测试覆盖
5. App Store 发布准备
6. 桌面端 + 服务端最终稳定化

---

## 二、iOS 端 AI 分析集成

### 2.1 架构设计

在 iOS 端复用桌面端 v6.0-beta 的 AI 分析逻辑，但使用 Swift 原生实现，不依赖 Python 后端。

**核心模块：**

| 模块 | 文件路径 | 职责 |
|---|---|---|
| `LLMService` | `ios/Services/LLMService.swift` | LLM API 调用封装，支持 OpenAI / Anthropic / 通义千问 |
| `AnalysisCache` | `ios/Services/AnalysisCache.swift` | SwiftData 本地缓存分析结果 |
| `AIAnalysisView` | `ios/Views/Analysis/AIAnalysisView.swift` | 分析结果展示 UI |
| `APIKeyStore` | `ios/Services/APIKeyStore.swift` | Keychain 安全存储 API Key |

### 2.2 LLM API 调用实现

**`LLMService` 接口设计：**

```swift
protocol LLMProvider {
    var name: String { get }
    var baseURL: String { get }
    func analyze(text: String, model: String) async throws -> AnalysisResult
}

struct AnalysisResult: Codable {
    let paperInfo: PaperInfo
    let topics: [TopicDistribution]
    let difficultyDistribution: DifficultyDistribution
    let repeatedFromPrevious: [RepeatedQuestion]
    let summary: String
}
```

**支持的 Provider：**

| Provider | 默认模型 | API 格式 |
|---|---|---|
| OpenAI | gpt-4o-mini | `/v1/chat/completions` |
| Anthropic | claude-sonnet-4-20250514 | `/v1/messages` |
| 通义千问 | qwen-turbo | `/v1/chat/completions`（兼容 OpenAI 格式） |

**关键实现细节：**

- 使用 `URLSession` 的 `bytes(for:)` 方法支持流式响应，提升长文本分析的用户体验
- API Key 通过 iOS Keychain（`Security` 框架）存储，不写入 UserDefaults 或文件
- 请求超时设置：连接超时 10s，读取超时 120s（LLM 分析可能较慢）
- 实现请求取消支持（用户可中途取消分析）

### 2.3 本地缓存分析结果

使用 SwiftData 模型缓存，与桌面端 SQLite 缓存逻辑对齐：

```swift
@Model
class CachedAnalysis {
    var paperFilename: String      // 关联试卷文件名
    var subject: String
    var year: Int
    var analysisJSON: Data         // 完整 AnalysisResult 的 JSON
    var summary: String            // 摘要文本（列表展示用）
    var createdAt: Date
    var provider: String           // 使用的 LLM provider
    var model: String              // 使用的模型名称
}
```

**缓存策略：**
- 同一试卷（按 filename 唯一标识）只分析一次，后续直接读缓存
- 缓存无过期机制（试卷内容不变）
- 用户可手动删除缓存重新分析
- 缓存数据随 SwiftData 自动通过 iCloud 同步到用户其他设备

### 2.4 UI 设计

- 试卷详情页底部新增"AI 分析"按钮（液态玻璃风格 `.glassEffect`）
- 分析进行中显示进度指示器 + 可取消按钮
- 分析结果以卡片形式展示：
  - 考点分布：使用 Swift Charts 的 `SectorMark` 饼图
  - 难度分布：`BarMark` 条形图
  - 重复题型：列表展示，点击跳转到关联试卷
  - 摘要文本：Markdown 渲染
- 支持导出为 PDF 报告（使用 `PDFKit` 渲染）

### 2.5 首次使用引导

- 检测到未配置 API Key 时，弹出引导 Sheet
- 引导内容：说明 AI 分析功能、API Key 获取方式、隐私说明
- 提供快速跳转到设置页配置 Key 的入口

---

## 三、iOS 端 OCR 集成

### 3.1 技术方案

使用 Apple 原生 Vision Framework 的 `VNRecognizeTextRequest`，零第三方依赖。

**核心模块：**

| 模块 | 文件路径 | 职责 |
|---|---|---|
| `OCREngine` | `ios/Services/OCREngine.swift` | PDF 页面渲染 + Vision OCR 封装 |
| `TextIndexer` | `ios/Services/TextIndexer.swift` | SQLite FTS5 全文索引 |
| `OCRProgressView` | `ios/Views/OCR/OCRProgressView.swift` | OCR 进度展示 |

### 3.2 OCR 工作流程

```
PDF 文件
  → PDFKit 渲染每页为 CGImage（300 DPI）
  → VNRecognizeTextRequest 识别（recognitionLevel: .accurate）
  → 按题号正则分段（匹配 Q1, Q2, ... 或 1., 2., ... 模式）
  → 数学公式标记为 [formula] 占位符
  → 结构化文本存入 SwiftData
  → 写入 SQLite FTS5 索引
```

### 3.3 Vision Framework 调用细节

```swift
func recognizeText(from image: CGImage) async throws -> [RecognizedTextBlock] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = true
    request.customWords = ["∫", "∑", "√", "π", "θ", "∞"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    guard let results = request.results else { return [] }
    return results.compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return RecognizedTextBlock(
            text: candidate.string,
            confidence: candidate.confidence,
            boundingBox: observation.boundingBox
        )
    }
}
```

**性能优化：**
- 使用 `TaskGroup` 并发处理多页（限制并发数为 CPU 核心数）
- 每页处理完成后立即更新进度 UI
- 大 PDF（>50 页）分批处理，避免内存峰值过高
- 后台处理使用 `.background` QoS，不阻塞 UI

### 3.4 全文搜索（FTS5）

```swift
class TextIndexer {
    func indexPaper(filename: String, questions: [QuestionText]) { ... }
    func search(keyword: String) -> [SearchResult] { ... }
    func removeIndex(filename: String) { ... }
}
```

**搜索结果展示：**
- 搜索框支持关键词搜索 OCR 提取的题目文本
- 结果列表显示匹配的试卷名、题号、匹配文本片段（高亮关键词）
- 点击结果跳转到对应试卷的对应页面

### 3.5 数学公式处理策略

与桌面端 v6.0-beta 保持一致：
- 数学公式识别率低的部分标记为 `[formula]`
- 保留公式在 PDF 中的原始位置截图
- AI 分析时将 `[formula]` 作为上下文传递给 LLM，由 LLM 推断公式含义

---

## 四、iOS 端智能去重

### 4.1 技术方案

使用 Core ML 加载 sentence-transformers 模型（转换为 Core ML 格式），在设备端完成 embedding 计算和向量相似度比对。

**核心模块：**

| 模块 | 文件路径 | 职责 |
|---|---|---|
| `EmbeddingService` | `ios/Services/EmbeddingService.swift` | Core ML 模型加载 + embedding 计算 |
| `DedupEngine` | `ios/Services/DedupEngine.swift` | 向量索引 + 相似度比对 |
| `SimilarityDB` | `ios/Services/SimilarityDB.swift` | SQLite 存储相似对 |
| `DedupResultView` | `ios/Views/Dedup/DedupResultView.swift` | 去重结果展示 |

### 4.2 Core ML 模型集成

**模型准备：**
- 将 `all-MiniLM-L6-v2`（80MB）通过 `coremltools` 转换为 `.mlmodel` 格式
- 模型打包到 App Bundle 中（首次启动时解压）
- 转换脚本（CI/CD 中运行）：

```python
import coremltools as ct
from sentence_transformers import SentenceTransformer
model = SentenceTransformer('all-MiniLM-L6-v2')
mlmodel = ct.convert(
    model,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS18,
)
mlmodel.save("EmbeddingModel.mlpackage")
```

**设备端推理：**

```swift
class EmbeddingService {
    private let model: EmbeddingModel

    func computeEmbedding(text: String) async throws -> [Float] {
        let input = EmbeddingModelInput(text: text)
        let output = try await model.prediction(input: input)
        return output.embedding
    }
}
```

### 4.3 向量相似度计算

**方案选择：** 不引入 FAISS（iOS 端无官方 Swift 支持），使用轻量级方案：

- 题库规模 < 5000 题时：暴力计算余弦相似度（SIMD 优化）
- 题库规模 >= 5000 题时：使用 Annoy 的 Swift 移植或 HNSW 简单实现

```swift
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    var dotProduct: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
    vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
    vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
    return dotProduct / (sqrt(normA) * sqrt(normB))
}
```

**相似度阈值（与桌面端一致）：**
- `> 0.80`：高度相似（红色标签）
- `> 0.65`：可能相关（黄色标签）
- `< 0.65`：不标记

### 4.4 去重工作流程

```
新试卷 OCR 完成
  → 按题号分割文本
  → 每道题计算 embedding（Core ML）
  → 与已有题库向量比对（余弦相似度）
  → 相似度 > 阈值 → 存入 SimilarityDB
  → UI 展示"相似题"标签
```

### 4.5 首次索引构建

- 首次使用去重功能时，提示用户需要构建索引
- 后台运行，显示进度（"正在分析 X/Y 份试卷..."）
- 使用 BackgroundTasks 框架，支持 App 切到后台继续处理
- 预计耗时：100 份试卷约 3-5 分钟（A15 及以上芯片）

---

## 五、Dynamic Island 下载进度展示

### 5.1 技术方案

使用 iOS 16.1+ 的 `ActivityKit` 框架，创建 Live Activity 在 Dynamic Island 和锁屏展示下载进度。

**核心模块：**

| 模块 | 文件路径 | 职责 |
|---|---|---|
| `DownloadActivity` | `ios/Models/DownloadActivity.swift` | Live Activity 数据模型 |
| `ActivityManager` | `ios/Services/ActivityManager.swift` | 创建/更新/结束 Activity |
| `DownloadActivityWidget` | `ios/Widget/DownloadActivityWidget.swift` | Dynamic Island UI（Widget Extension） |

### 5.2 Live Activity 数据模型

```swift
struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var completedCount: Int
        var totalCount: Int
        var currentFile: String
        var isDownloading: Bool
    }

    var subjectName: String
    var startedAt: Date
}
```

### 5.3 Dynamic Island 展示

**Compact 展示（刘海两侧）：**
- 左侧：下载图标 + 已完成数量
- 右侧：进度环（CircularProgressView）

**Expanded 展示（长按）：**
- 科目名称、进度条、当前下载文件名、预计剩余时间、取消按钮

### 5.4 生命周期管理

```swift
class ActivityManager {
    private var currentActivity: Activity<DownloadActivityAttributes>?

    func startActivity(subject: String, total: Int) { ... }
    func updateProgress(completed: Int, total: Int, currentFile: String) { ... }
    func endActivity() { ... }
}
```

- 更新频率限制：最多每 2 秒更新一次，避免系统节流

---

## 六、离线模式完善

### 6.1 离线功能清单

| 功能 | 离线可用 | 说明 |
|---|---|---|
| 浏览已下载试卷 | 是 | 本地文件系统 |
| PDF 预览 | 是 | PDFKit 本地渲染 |
| OCR 文本提取 | 是 | Vision Framework 本地运行 |
| AI 分析 | 否 | 需要 LLM API 网络连接 |
| 智能去重 | 是 | Core ML 本地推理 |
| 全文搜索 | 是 | SQLite FTS5 本地索引 |
| 科目搜索 | 否 | 需要服务端 API |
| 批量下载 | 否 | 需要网络连接 |
| 分享链接 | 否 | 需要协作服务端 |
| 学习小组 | 部分 | 缓存数据可浏览，实时更新不可用 |
| 试卷评价 | 部分 | 可查看缓存评价，提交需联网 |

### 6.2 网络状态监听

```swift
import Network

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    @Published var isConnected = true
    @Published var connectionType: ConnectionType = .wifi

    enum ConnectionType { case wifi, cellular, none }
}
```

### 6.3 离线降级策略

- **全局网络状态指示器**：顶部状态栏显示网络状态图标
- **离线提示**：在需要网络的功能处显示"无网络连接"提示
- **数据缓存**：科目列表缓存（24h）、小组数据缓存、评价数据缓存
- **离线队列**：写操作在离线时加入本地队列，联网后自动提交
- **SSE 重连**：断开后自动重连（指数退避，最大间隔 30s）

---

## 七、性能优化

### 7.1 启动时间优化

**目标：冷启动 < 1.5s（iPhone 15 及以上）**

| 优化项 | 措施 |
|---|---|
| SwiftData 延迟初始化 | 首次访问数据时才创建 container |
| Core ML 模型延迟加载 | 去重功能首次使用时才加载模型 |
| 网络请求延迟 | 启动后 500ms 才发起后台请求 |
| 减少主线程阻塞 | 所有 I/O 操作移到后台线程 |

### 7.2 内存优化

**目标：正常使用 < 150MB，PDF 预览峰值 < 300MB**

| 优化项 | 措施 |
|---|---|
| PDF 渲染 | 按需渲染，不预加载所有页面 |
| 图片缓存 | NSCache 限制 50MB |
| OCR 处理 | 逐页处理 |
| 向量索引 | 内存映射文件（mmap） |

### 7.3 电池优化

| 优化项 | 措施 |
|---|---|
| 后台任务 | BGTaskScheduler 系统调度 |
| 低电量模式 | 暂停后台索引构建 |

---

## 八、全面测试计划

### 8.1 单元测试（iOS XCTest）

| 测试模块 | 测试文件 | 覆盖范围 |
|---|---|---|
| LLMService | `LLMServiceTests.swift` | API 调用、错误处理、缓存命中、取消请求 |
| OCREngine | `OCREngineTests.swift` | 文本识别准确率、分题逻辑、公式标记 |
| EmbeddingService | `EmbeddingServiceTests.swift` | 模型加载、embedding 计算、相似度计算 |
| DedupEngine | `DedupEngineTests.swift` | 阈值判断、批量比对、索引构建 |
| TextIndexer | `TextIndexerTests.swift` | FTS5 索引写入、搜索、删除 |
| NetworkMonitor | `NetworkMonitorTests.swift` | 状态变化、重连逻辑 |
| ActivityManager | `ActivityManagerTests.swift` | Activity 创建/更新/结束 |

### 8.2 单元测试（桌面端 pytest）

| 测试模块 | 测试文件 | 覆盖范围 |
|---|---|---|
| AI 分析 | `test_ai_analyzer.py` | LLM 调用封装、prompt 构建、结果解析 |
| OCR 引擎 | `test_ocr_engine.py` | Tesseract 调用、分题、后处理 |
| 去重引擎 | `test_dedup_engine.py` | embedding 计算、FAISS 索引、相似度 |
| 协作客户端 | `test_collab_client.py` | API 调用、认证、错误处理 |

### 8.3 单元测试（服务端 Go testing）

| 测试模块 | 覆盖范围 |
|---|---|
| `auth_test.go` | 注册、登录、JWT 签发/校验 |
| `share_test.go` | 分享创建、访问、过期、删除 |
| `group_test.go` | 小组 CRUD、成员管理、权限校验 |
| `review_test.go` | 评价 CRUD、评分范围、去重 |
| `sse_test.go` | SSE 连接、事件推送、断线重连 |

### 8.4 UI 测试（XCUITest）

| 测试场景 | 测试步骤 |
|---|---|
| 搜索流程 | 选择科目 → 年份 → 搜索 → 结果列表 |
| 下载流程 | 选择试卷 → 下载 → 进度 → 完成 |
| AI 分析流程 | 选择试卷 → AI 分析 → 等待 → 查看报告 |
| OCR 流程 | 选择 PDF → OCR → 查看文本 → 搜索 |
| 去重流程 | 构建索引 → 查看相似题 → 详情 |
| 离线模式 | 断网 → 浏览 → 联网 → 刷新 |
| Dynamic Island | 下载中 → 查看 DI → 长按展开 |

### 8.5 性能测试

| 指标 | 目标 | 测试方法 |
|---|---|---|
| 冷启动时间 | < 1.5s | Instruments Time Profiler |
| 内存峰值（正常使用） | < 150MB | Instruments Allocations |
| 内存峰值（PDF 预览） | < 300MB | Instruments Leaks |
| OCR 处理速度（20 页） | < 60s（A15+） | 自定义 benchmark |
| Embedding 计算（10 题） | < 2s | 自定义 benchmark |
| 向量比对（1000 题） | < 500ms | 自定义 benchmark |
| 电池消耗（后台 1h） | < 3% | Instruments Energy Log |

### 8.6 兼容性测试

| 维度 | 范围 |
|---|---|
| iOS 版本 | 18.0, 18.1, 18.2, 18.3, 18.4 |
| 设备 | iPhone SE 3, iPhone 15, 15 Pro, 16, 16 Pro |
| 屏幕尺寸 | 4.7", 6.1", 6.7", 6.9" |
| 网络环境 | WiFi, 4G, 5G, 弱网 |
| macOS | 14, 15（桌面端） |
| Windows | 10, 11（桌面端） |

---

## 九、App Store 发布准备

### 9.1 签名与证书

| 项目 | 说明 |
|---|---|
| Apple Developer Account | 确认已注册 |
| App ID | `cn.fraft.cpaper` |
| Provisioning Profile | Distribution profile |
| Capabilities | Sign in with Apple, Associated Domains |

### 9.2 App Store Connect 配置

- 名称：C-Paper
- 副标题：CIE Past Papers Downloader
- 类别：教育（Education）
- 评分：4+
- 价格：免费
- 最低 iOS 版本：18.0

### 9.3 截图准备

| 设备 | 尺寸 |
|---|---|
| iPhone 16 Pro Max | 1320 x 2868 |
| iPhone 16 Pro | 1206 x 2622 |
| iPhone SE | 750 x 1334 |

### 9.4 审核注意事项

| 风险点 | 应对措施 |
|---|---|
| API Key 安全 | 说明 Key 存储在 Keychain，不上传服务器 |
| 版权 | 说明 App 不托管试卷内容 |
| 内购 | 无内购，完全免费 |
| 隐私政策 | 需要提供隐私政策 URL |
| Privacy Manifest | `PrivacyInfo.xcprivacy` 声明 API 使用原因 |

---

## 十、桌面端 + 服务端最终稳定化

### 10.1 桌面端 Bug Fix

| 编号 | 类别 | 描述 | 优先级 |
|---|---|---|---|
| D-01 | 兼容性 | pywebview macOS 15 渲染问题 | 高 |
| D-02 | 性能 | 大批量下载 UI 卡顿 | 中 |
| D-03 | 稳定性 | 代理切换时连接优雅关闭 | 中 |
| D-04 | 兼容性 | Windows 高 DPI 缩放 | 中 |

### 10.2 服务端稳定性

| 项目 | 措施 |
|---|---|
| SQLite 并发 | WAL 模式 + 连接池限制 |
| 错误恢复 | panic recovery middleware |
| 日志 | 结构化 JSON 日志 |
| 健康检查 | `GET /api/health` |
| 数据库备份 | 定时 `.backup` 命令 |

---

## 十一、版本发布 Checklist

### 11.1 代码冻结前

- [ ] 所有计划功能已完成开发
- [ ] 所有高优先级 Bug 已修复
- [ ] 代码审查完成
- [ ] 桌面端测试通过（`pytest tests/`）
- [ ] 服务端测试通过（`go test ./...`）
- [ ] iOS 测试通过（Xcode Test Navigator）
- [ ] 性能测试达标

### 11.2 iOS App 发布

- [ ] Xcode Archive 成功
- [ ] TestFlight 内测通过（3 人 3 天）
- [ ] 截图已上传
- [ ] App 描述已填写
- [ ] 隐私政策已配置
- [ ] Privacy Manifest 已包含
- [ ] 提交审核

### 11.3 桌面端发布

- [ ] macOS DMG 测试安装通过
- [ ] Windows 安装包测试通过
- [ ] GitHub Release 创建
- [ ] `version.json` 更新为 6.0.0

### 11.4 服务端发布

- [ ] Go 二进制编译成功
- [ ] 数据库迁移成功
- [ ] 健康检查响应正常
- [ ] 监控配置完成

### 11.5 发布后

- [ ] 监控 App Store 审核状态
- [ ] 监控服务端运行状态（24h）
- [ ] 收集首批用户反馈
- [ ] 准备 Hotfix 版本

---

## 十二、时间线估算

| 任务 | 预计工时 | 依赖 |
|---|---|---|
| iOS AI 分析集成 | 5 天 | v6.0-beta AI 模块 |
| iOS OCR 集成 | 4 天 | v6.0-beta OCR 模块 |
| iOS 智能去重 | 5 天 | iOS OCR 完成 |
| Dynamic Island | 2 天 | 无 |
| 离线模式完善 | 3 天 | iOS 核心功能完成 |
| 性能优化 | 3 天 | 全部功能完成 |
| 全面测试 | 5 天 | 全部功能完成 |
| App Store 准备 | 2 天 | 测试通过 |
| 桌面端稳定化 | 3 天 | 与 iOS 并行 |
| 服务端稳定化 | 2 天 | 与 iOS 并行 |
| **总计** | **约 34 天** | |

**关键路径：** iOS OCR → iOS 智能去重 → 性能优化 → 全面测试 → App Store 发布

---

## 十三、风险与缓解

| 风险 | 影响 | 缓解措施 |
|---|---|---|
| Core ML 模型转换失败 | 去重功能不可用 | 备选：NLEmbedding（系统内置，精度略低） |
| App Store 审核被拒 | 发布延迟 | 提前准备审核备注 |
| Vision OCR 准确率不足 | 用户体验差 | 优化预处理参数 |
| Dynamic Island 适配问题 | 功能不可用 | 降级为锁屏通知 |
| 免费服务器承载不足 | 协作功能不可用 | 客户端离线降级 |
| iOS 18 最低版本限制 | 部分用户无法使用 | App Store 描述中明确说明 |
