# C-Paper Code Wiki

> C-Paper 是面向 macOS 的 Cambridge International Education past paper 桌面工具，用于搜索、预览、批量下载试卷与 mark scheme。本 Wiki 以**当前活跃的 SwiftUI/AppKit 原生主线**为唯一权威范围，覆盖项目整体架构、模块职责、关键类与函数、依赖关系以及运行方式。
>
> 版本基线：`version.json` 中声明的 `6.0.5`（与 `Package.swift` / `BackendConstants.version` 一致）。

---

## 目录

- [1. 项目概述](#1-项目概述)
- [2. 整体架构](#2-整体架构)
- [3. 仓库目录结构](#3-仓库目录结构)
- [4. Swift 包与可执行目标](#4-swift-包与可执行目标)
- [5. 应用启动与主菜单层](#5-应用启动与主菜单层)
- [6. UI 层（SwiftUI / AppKit）](#6-ui-层swiftui--appkit)
- [7. 状态层（AppModel）](#7-状态层appmodel)
- [8. Backend 门面 `NativeBackendService`](#8-backend-门面-nativebackendservice)
- [9. 数据源层（Sources）](#9-数据源层sources)
- [10. 解析层（Parsing）](#10-解析层parsing)
- [11. 网络层（Networking）](#11-网络层networking)
- [12. 下载层（Downloads）](#12-下载层downloads)
- [13. 持久化层（Persistence）](#13-持久化层persistence)
- [14. 更新层（Updates）](#14-更新层updates)
- [15. 设计系统（Design）](#15-设计系统design)
- [16. 关键模型（Models）](#16-关键模型models)
- [17. 错误与诊断](#17-错误与诊断)
- [18. 测试套件](#18-测试套件)
- [19. 构建脚本与发布工作流](#19-构建脚本与发布工作流)
- [20. 运行、构建与发布](#20-运行构建与发布)
- [21. 依赖关系](#21-依赖关系)
- [22. 隐私、免责声明与数据源策略](#22-隐私免责声明与数据源策略)
- [23. 已知边界与项目规则](#23-已知边界与项目规则)

---

## 1. 项目概述

- **产品定位**：C-Paper 是一个 macOS 本地桌面工具，让 CIE 学生与教师按科目 / 年份 / 考季检索 past paper、PDF 预览、按年份范围批量下载、收藏常用科目、配置数据源与代理。
- **当前活跃实现**：根 `Package.swift` + `macos/Sources/CPaperNativeApp/` 下的 SwiftUI/AppKit + Swift-native backend，目标平台 `macOS 14+`。
- **旧实现（已归档）**：`legacy/python-backend/`、`legacy/pywebview/`，仅作为历史参考保留。Python 桥与 Python 桌面壳已不再启动、构建或打包。
- **数据来源**：第三方公开站点 `cie.fraft.cn`（FrankCIE）、`papacambridge.com`、`pastpapers.co`、`easy-paper.com`。自动模式下按 `FrankCIE → EasyPaper → PastPapers → PapaCambridge` 顺序回退。
- **本地数据目录**：`~/Library/Application Support/C-Paper/`，首次启动会从旧的 `~/.cie_cache/` 迁移可识别的设置、收藏与下载历史。

---

## 2. 整体架构

C-Paper 采用**单进程原生应用**结构，分为五层：

```text
┌────────────────────────────────────────────────────────────────┐
│  AppKit / SwiftUI 启动层                                        │
│  - main.swift / AppDelegate                                     │
│  - AppMenuController / AppMenuCommandCenter / AppMenuCommand    │
├────────────────────────────────────────────────────────────────┤
│  UI 层（Views/）                                                │
│  - RootView + AppBootCoordinator（启动/失败/就绪三态机）          │
│  - SearchView / BatchView / DownloadsView / SettingsView         │
│  - SidebarView / PageScaffold / WorkflowChrome / Design 系统    │
├────────────────────────────────────────────────────────────────┤
│  状态层（State/AppModel + AppModel+*.swift）                     │
│  - @Observable @MainActor 中央状态机                              │
│  - 工作流路由、诊断、UI 通知、下载轮询                            │
├────────────────────────────────────────────────────────────────┤
│  Backend 门面 NativeBackendService（Backend/Core）               │
│  - 协调 Settings / Favorites / History / Session / Cache /       │
│    Preview / Diagnostics / SourceRegistry / DownloadManager /   │
│    UpdateService                                                 │
├────────────────────────────────────────────────────────────────┤
│  领域服务                                                        │
│  - Sources（FrankCIE/EasyPaper/PastPapers/PapaCambridge + 公共） │
│  - Parsing（文件名 / 科目 / 分组 / HTML 链接）                    │
│  - Networking（URLSession、HTTP 请求构建、代理）                  │
│  - Downloads（队列、限流、熔断、阶段式文件写入、预览）             │
│  - Persistence（JSON 存储、设置、收藏、历史、会话、缓存）          │
│  - Updates（GitHub Release 检测与 DMG 下载）                      │
└────────────────────────────────────────────────────────────────┘
```

关键运行关系（与 `docs/PROJECT_INDEX.md` 一致）：

```text
CPaperNative.app
  → SwiftUI / AppKit UI
    → AppModel（@MainActor、@Observable）
      → NativeBackendService
        → SourceRegistry / Parser / Cache / DownloadManager / Persistence / UpdateService
```

应用启动后（`AppDelegate.applicationDidFinishLaunching`）会安装主菜单（即使未进入 ready UI 也会先装好），`ReadyRootView` 在显示后通过 `ReadyRootMenuBindings` 把菜单命令绑到当前 `AppModel`。

---

## 3. 仓库目录结构

```text
C-Paper/
├── Package.swift                  Swift Package 入口（macos/ 下的可执行 target）
├── Package.resolved               SPM 依赖锁定
├── version.json                   应用版本、发布说明、下载链接
├── README.md                      用户面向的安装与使用说明
├── MAINTENANCE_BASELINE.md        维护基线说明
├── LICENSE                        MIT 协议
├── cpaper-*.md                    三份设计/产品方案文档（中文）
│
├── .github/
│   ├── workflows/
│   │   ├── build.yml              native validate / package / release 工作流
│   │   └── legacy-release.yml     旧 pywebview 线路归档工作流
│   └── release-notes/             各版本发布说明（原生 + legacy 5.2.1）
│
├── macos/                         ★ 活跃实现
│   ├── Sources/CPaperNativeApp/   SwiftUI / AppKit 应用 + Swift-native backend
│   └── Tests/CPaperNativeTests/   活跃 Swift 测试
│
├── scripts/                       活跃原生构建/检查脚本
│   ├── build_native_dmg.sh        主 DMG 构建脚本
│   ├── check_release_docs.sh      发布文档一致性静态门
│   ├── check_repo_hygiene.sh      仓库卫生检查
│   ├── check_swift_quality.sh     Swift 质量门
│   ├── check_version_drift.sh     版本漂移检查
│   ├── run_native_release_audit.sh RC 审计入口
│   ├── verify_native_dmg.sh       DMG 验证入口
│   └── lib/                       共享 shell helpers
│       ├── native_dmg_helpers.sh
│       ├── swiftpm_retry_helpers.sh
│       └── version_helpers.sh
│
├── assets/                        共享图标和图片资源
│   ├── icon.icns
│   └── icon.iconset/  图标.jpg
│
├── docs/                          项目内部文档
│   ├── PROJECT_INDEX.md
│   ├── WORK_LOG.md
│   ├── RELEASE_AND_VALIDATION.md
│   └── RELEASE_CANDIDATE_AUDIT.md
│
├── legacy/                        ★ 已归档旧实现，不再构建
│   ├── python-backend/            Python 桥 + 后端 + 测试
│   ├── pywebview/                 旧 pywebview 桌面壳与打包脚本
│   └── README.md
│
└── .swiftlint.yml / .swiftformat  Swift 质量与格式工具配置
```

---

## 4. Swift 包与可执行目标

- 文件：[`Package.swift`](file:///Users/yimingwu/Documents/C-Paper/Package.swift)
- 工具链：`swift-tools-version: 6.0`
- 平台：`.macOS(.v14)`
- 产品（product）：`.executable(name: "CPaperNative", targets: ["CPaperNativeApp"])`
- 目标（target）：
  - `CPaperNativeApp`（executableTarget）：源码目录 `macos/Sources/CPaperNativeApp`，依赖 `SwiftSoup`、`swift-collections` 中的 `Collections` 产品
  - `CPaperNativeTests`（testTarget）：源码目录 `macos/Tests/CPaperNativeTests`，依赖 `ViewInspector`
- 入口：应用 `main.swift`（`macos/Sources/CPaperNativeApp/main.swift`）显式 `NSApplication.shared.run()`，因此没有使用 `@main` 属性。

---

## 5. 应用启动与主菜单层

### 5.1 应用启动

- [`main.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/main.swift)
  - 创建 `NSApplication.shared`，`AppDelegate` 设为 delegate，`activationPolicy = .regular`。
  - `app.finishLaunching()` 后立即 `delegate.showMainWindow()` → `app.activate(ignoringOtherApps: true)` → `app.run()`。
- [`AppDelegate.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/AppDelegate.swift)
  - 唯一入口 `applicationDidFinishLaunching`：先 `installMainMenuIfNeeded()` 再 `showMainWindow()`。
  - `showMainWindow`：用 `NSHostingView(rootView: RootView())` 装载 SwiftUI 树，配置无标题栏磨砂的 `NSWindow`（`.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`），窗口最小 1100×720，居中、置顶并激活。
  - `applicationShouldTerminateAfterLastWindowClosed` 返回 `true`。
  - `hasInstalledMainMenu` 标志位保证主菜单在多次启动路径（delegate / `showMainWindow`）下只安装一次。

### 5.2 主菜单层（中文 macOS 菜单栏）

- [`AppMenuCommand.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/AppMenuCommand.swift)
  - `enum AppMenuCommand`：13 个命令（`showAbout`、`showSettings`、`checkForUpdates`、`refreshCurrentView`、`showSearch/Batch/Downloads`、`revealSaveDirectory`、`copyLatestDiagnostic`、`revealSupportDirectory`、`openWebsite/GitHub`、`reportIssue`），命令名即 `rawValue`。
- [`AppMenuCommandCenter.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/AppMenuCommandCenter.swift)
  - `final class AppMenuCommandCenter: NSObject, NSMenuItemValidation`（`@MainActor`）。
  - 单例 `.shared`；通过 `bind(handler:canPerform:)` 注入执行/可用性回调，`unbind()` 取消绑定。
  - `validateMenuItem(_:)` 由 AppKit 询问时调用，输出 `canPerform(command)`。
  - `dispatchMenuItem(_:)` 由 NSMenuItem 自动转发（`action: #selector(AppMenuCommandCenter.dispatchMenuItem(_:))`），根据 `representedObject: AppMenuCommand` 调用 `dispatch`。
- [`AppMenuController.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/AppMenuController.swift)
  - `install()` 在 `NSApplication.mainMenu` 上构造六组菜单：`C-Paper`（关于 / 设置 ⌘, / 检查更新 / 服务 / 隐藏 ⌘h / 隐藏其他 ⌥⌘h / 显示全部 / 退出 ⌘q）、`文件`（显示下载文件夹、复制最近诊断、显示支持目录）、`编辑`（标准 ⌘z/⇧⌘z/⌘x/⌘c/⌘v/⌘a）、`显示`（刷新 ⌘r、搜索 ⌘1、批量 ⌘2、下载 ⌘3）、`窗口`、`帮助`。
  - `app.servicesMenu` / `app.windowsMenu` / `app.helpMenu` 同步设置给 AppKit。
  - 所有自定义项通过 `addCommandItem` 绑定到 `AppMenuCommandCenter`。

### 5.3 菜单与 UI 绑定

- [`Views/RootView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/RootView.swift) 中 `ReadyRootMenuBindings`
  - `.onAppear { ReadyRootMenuBindings.bind(model: model) }` / `.onDisappear { ReadyRootMenuBindings.unbind() }`，只把菜单和 `AppModel` 绑在 ready UI 显示期间。
  - `Environment.live()` 提供 `showAboutPanel`（`NSApp.orderFrontStandardAboutPanel`）和 `openURL`（`NSWorkspace.shared.open`）。
  - 静态 URL：`websiteURL = "https://yiming.us/c-paper"`，`gitHubURL = "https://github.com/yimingwu425/C-Paper"`，`issueURL = "https://github.com/yimingwu425/C-Paper/issues"`。
  - `canPerform(_:model:)` 在存在 modal 状态（设置页/错误/更新 prompt）或下载/检查进行中时禁用对应菜单项；只有当存在最近诊断时启用"复制最近诊断"。

---

## 6. UI 层（SwiftUI / AppKit）

入口是 [`RootView`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/RootView.swift)，它持有 [`AppBootCoordinator`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/State/AppBootCoordinator.swift) 并按阶段渲染：

- `.loading` → `StartupLoadingView`（磨砂面板 + ProgressView）
- `.ready(model)` → `ReadyRootView`（`NavigationSplitView` + 三栏式应用）
- `.failed(failure)` → `StartupFailureView`（重试 / 复制诊断 / 显示支持文件夹）

### 6.1 视图清单

| 视图文件 | 角色 |
| --- | --- |
| [`Views/RootView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/RootView.swift) | 入口三态 + `StatusToast` + 工具栏（刷新/下载/设置） |
| [`Views/SidebarView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/SidebarView.swift) | 路由切换 + 常用科目 + 收藏通知卡 |
| [`Views/SearchView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/SearchView.swift) | 搜索页：筛选 + 结果列表 + 预览面板 |
| [`Views/BatchView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/BatchView.swift) | 批量页：年份范围 + 季度 + Paper 类型筛选 + 预览面板 |
| [`Views/DownloadsView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/DownloadsView.swift) | 下载队列 / 中断恢复 / 文件完整性通知 |
| [`Views/SettingsView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/SettingsView.swift) | 设置表单（保存目录 / 数据源 / 代理 / 下载 / 关于 / 更新 / 支持） |
| [`Views/PDFPreviewView.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift) | PDFKit 预览容器，加载/失败态 + 重试 / 重新下载 |
| [`Views/PDFPreviewPaneLayout.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/PDFPreviewPaneLayout.swift) | 预览面板的布局工具 |
| [`Views/PaperResults.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/PaperResults.swift) | 结果行 / 分组 / 标题行 |
| [`Views/SearchControls.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/SearchControls.swift) | `SubjectPicker`（可搜索弹层） + 其它搜索控件 |
| [`Views/BatchFilterPanel.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/BatchFilterPanel.swift) | 批量规则面板（年份/季度/Paper） |
| [`Views/BatchPreviewPanel.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/BatchPreviewPanel.swift) | 批量预览结果列表 |
| [`Views/SettingsFormSections.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/SettingsFormSections.swift) | 设置页表单片段（保存目录、源、代理、下载参数） |
| [`Views/SettingsInfoSections.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift) | 设置页信息片段（关于、更新、支持） |
| [`Views/PageScaffold.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/PageScaffold.swift) | `ScrollableWorkflowPage` 通用页脚手架 |
| [`Views/WorkflowChrome.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift) | `ProductBackdrop`、`PageHero`、其它磨砂 chrome 元素 |
| [`Views/InspectionSupport.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Views/InspectionSupport.swift) | `Inspection<V>` + `inspectableSheet` / `inspectablePopover`（为 ViewInspector 测试提供入口） |

### 6.2 视图层关键点

- 所有视图都通过 `@Bindable var model: AppModel`（`@Observable` 包装）绑定到中央状态。
- 工具栏与 `appMenu` 的动作在同一份 `AppModel` 上工作，避免状态分裂。
- `RootView` 内 `.alert` 处理：通用错误 alert（带"复制诊断" / "显示支持文件夹"）、`pendingUpdatePrompt` 更新 alert。
- `StatusToast` 根据 `isLoading || downloadSnapshot.isRunning` 渲染顶部/底部状态条。
- `subjects.isEmpty` 时 `SubjectPicker` 自动隐藏下拉入口，转为可手动输入 4 位科目代码（`manualCode`）。

---

## 7. 状态层（AppModel）

文件：[`State/AppModel.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/State/AppModel.swift)（核心）、[`AppModel+Setup.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/State/AppModel+Setup.swift)、[`AppModel+PaperWorkflow.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPPaperNativeApp/State/AppModel+PaperWorkflow.swift)、[`AppModel+Updates.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift)、[`State/AppBootCoordinator.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/State/AppBootCoordinator.swift)。

### 7.1 `AppModel`（`@MainActor @Observable`）

- 主要字段：
  - 路由 `route: AppRoute`（`.search / .batch / .downloads`）
  - 科目与状态：`subjects`、`favorites`、`selectedSubject`、`manualSubjectCode`、`selectedYear`、`selectedSeason`
  - 批量状态：`batchYearFrom/To`、`batchSeasons: Set<Season>`、`batchPaperGroups: Set<Int>`
  - 搜索结果：`searchResults`、`searchGroups`、`searchResultSourceID`、`searchUsedAutomaticFallback`
  - 批量预览：`batchPreview`、`batchGroups`、`batchPreviewSourceIDs`、`batchPreviewSuccessfulQueryCount`、`batchPreviewAutomaticFallbackQueryCount`
  - 下载：`downloads: [DownloadTaskItem]`、`downloadSnapshot: DownloadStatusSnapshot`
  - 预览：`selectedPreview`、`previewLoadState`、`previewLoadRevision`、`pendingPreviewRepairFileID`
  - 设置：`settings: DownloadSettings`
  - 更新：`updateStatus: UpdateStatus`、`pendingUpdatePrompt: AppUpdateRelease?`
  - 通知：`sourceNotice`、`downloadNotice`、`downloadRecoveryNotice`、`downloadRecoveredCleanedPartialCount`、`downloadIntegrityNotice`、`downloadIntegrityStatesByTaskID`、`settingsNotice`、`favoriteNotice`、`saveDirectoryNotice`、`supportDirectoryNotice`、`updateNotice`
  - 诊断：`lastDiagnostic`、`diagnosticsByContext`、`lastDownloadFailureDiagnosticSignature`、`lastDownloadIntegrityDiagnosticSignature`
- 内部：`@ObservationIgnored let backend: NativeBackendService`、`openDownloadedFile`、`pollTask: Task<Void, Never>?`
- 构造：`init(backend:openDownloadedFile:)`；工厂 `static func live() throws -> AppModel` → `AppModel(backend: try NativeBackendService())`
- 派生属性：
  - 完成 / 失败 / 可重试 / 取消 / 跳过 / 进行中下载数量
  - `hasRetryableFailedDownloads`、`interruptedFailedCount`、`downloadRecoverySummary`
  - `batchSeasonList`、`isSelectedSubjectFavorite`
  - `backendRuntimePath`、`supportDirectoryPath`
  - `activeSubject`（优先 `selectedSubject`，否则解析 `manualSubjectCode`）
  - `searchResultSourceSummary`、`batchPreviewSourceSummary`
  - `previewLoadRequest: PreviewLoadRequest?`（用 `revision` 防止过期回调）
- 关键方法：
  - `clearError() / recordDiagnostic(...) / copyLatestDiagnostic() / copyDiagnostic(...)`
  - `loadSelectedPreviewIfNeeded()` / `retryPreview()` / `redownloadSelectedPreviewFile()` / `closePreview()` / `revealPreviewFile()` / `validateLoadedPreviewFile(...)`
  - `usableSaveDirectoryURL()` / `saveDirectoryAvailability()` 内部三态 `.ready/.creatable/.unavailable`
  - `revealSaveDirectory()` 自动在 `.creatable` 时创建并打开；不可用时显示通知
  - `revealSupportDirectory()`
  - `openDownloadedUpdateFile()` / `handleBackendError(_:context:details:)` / `presentDiagnosticError(_:context:details:)`

### 7.2 扩展方法

- `AppModel+Setup.swift`
  - `bootstrap()`：依次 `loadSettings / loadSubjects / loadFavorites / refreshDownloads`
  - `loadSubjects()` 走 `backend.loadSubjects(proxyURL:sourceMode:)`，失败时记录诊断
  - `loadFavorites()` 直接读 `backend.loadFavorites()`
  - `loadSettings()` 从 backend 读 `DownloadSettings`，并按 `lastMode` 还原 `route`
  - `saveSettings() / saveSettings(_:)`：写入时回填 `lastSubject`（当前活动科目 code）和 `lastMode`（当前 route）
  - 收藏添加/移除（`addSelectedSubjectToFavorites / removeFavorite / performFavoriteNoticeAction / handleFavoriteMutationFailure`）
  - 代理测试（`testProxy() / testProxy(_:)`）
- `AppModel+PaperWorkflow.swift`
  - `search()` / `previewBatch()`
  - `startSearchDownload / startBatchDownload / startSingleFileDownload` → 内部 `startDownload(...)`：
    - 调 `resolvedSaveDirectory()`：可用则 `.ready`；否则弹 `NSOpenPanel` 选目录；持久化失败返回 `.persistenceFailed(diagnostic)`
    - 调 `backend.startDownload(groups:saveDirectory:options:proxyURL:)`，成功后 `route = successRoute`、启动下载轮询
  - `refreshDownloads()`：拉取 `downloadStatus / downloadItems / consumeDownloadRecoverySummary`；调用 `recordRecoveredDownloadSessionIfNeeded` / `recordDownloadFailuresIfNeeded` / `recordCompletedDownloadIntegrityIfNeeded`；检查上次预览修复；按需启停 `startPollingDownloads`
  - `cancelDownloads / retryRecoverableDownloads / retryDownloadsNeedingRepair`
  - `startPollingDownloads / ensureDownloadPolling / stopPollingDownloads`（750ms 轮询）
  - `backendGroup(for:)` / `syCode(season:year:)`：把 `PaperFile` 转回 `NativePaperGroup`
  - `applySourceWarnings(_:)` / `recordSourceWarnings(_:)` / `sourceNoticeLevel(for:)`
  - 已完成文件完整性检查 `completedDownloadIntegrityIssue(for:)`（缺失 / 不可读 / 空 / 目录 / 非常规文件）
- `AppModel+Updates.swift`
  - `checkForUpdates(source:)`：调 `backend.checkForUpdate`；`available` 时若本地 DMG 完整则恢复为 `downloaded` 状态
  - `downloadAvailableUpdate()`：更新 `updateStatus = .downloading(...)`，调 `backend.downloadUpdate`，完成后 `openDownloadedUpdate()`
  - `openDownloadedUpdate()` / `revealDownloadedUpdate()` / `performUpdateNoticeAction()`
  - `downloadedUpdateFileAvailability(for:)`：检查路径存在 / 可读 / 常规 / 非空
  - `handleMissingDownloadedUpdateFile / handleInvalidDownloadedUpdateFile / handleDownloadedUpdateOpenFailure`

### 7.3 `AppBootCoordinator`

- `@MainActor @Observable`；`enum AppBootPhase { .loading, .ready(AppModel), .failed(AppBootFailure) }`
- `init(autoStart:makeModel:bootstrapModel:checkForStartupUpdates:)`，默认 `makeModel = { try AppModel.live() }`、`bootstrapModel = { await model.bootstrap() }`、`checkForStartupUpdates = { await model.checkForUpdates(source: .startup) }`
- `startIfNeeded()` / `retry()`：用 `attemptID` 防止过期回调覆盖更新后的阶段
- `AppBootFailure` 支持构造时把启动错误写到 `SupportDiagnosticsStore`，并提供 `revealSupportDirectory` / `supportDirectoryRevealErrorMessage(for:)` 给 `StartupFailureView` 使用

---

## 8. Backend 门面 `NativeBackendService`

文件：[`Backend/Core/NativeBackendService.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift)

- 类型：`final class NativeBackendService: @unchecked Sendable`
- 类型别名：
  - `SourceRegistryBuilder = @Sendable (String) -> SourceRegistry`
  - `DirectoryChooser = @MainActor @Sendable () async -> String`
- 内部持有的子服务：
  - `paths: AppStoragePaths`
  - `settingsStore / favoritesStore / historyStore / sessionStore / cacheStore`
  - `downloadManager: DownloadManager`
  - `updateService: UpdateService`
  - `previewService: PreviewFileService`
  - `supportDiagnosticsStore: SupportDiagnosticsStore`
  - `sourceRegistryBuilder / directoryChooser`
  - `fileManager`
- 构造依赖注入点：`paths / downloadManager / updateService / previewTransfer / sourceRegistryBuilder / directoryChooser / fileManager`，全部可选，默认值即可"上手运行"。
- 构造期会执行 `LegacyCacheMigrator(paths:).migrateIfNeeded()`。

主要 API（按域分类）：

| 域 | 方法 | 行为 |
| --- | --- | --- |
| 路径 | `appSupportPath / supportDirectoryPath` | 暴露 backend 实际目录给 UI |
| 路径 | `defaultSaveDirectory()` | `"~/Downloads/C-Paper"` |
| 设置 | `loadSettings() / saveSettings(_:)` | 读 / 写 `DownloadSettings`；`loadSettings` 自动填充默认 `saveDirectory` |
| 收藏 | `loadFavorites() / addFavorite(_:) / removeFavorite(code:)` | 委托给 `FavoritesStore` |
| 科目 | `loadSubjects(proxyURL:sourceMode:)` | 优先命中 `SearchCacheStore`（按 source 区分），否则走 `SourceRegistry.fetchSubjects`；命中后写回缓存 |
| 搜索 | `search(subject:year:season:settings:)` | 调 `registry.search`，包装 `SourceAttempt` → `SearchPayload`（含 `usedAutomaticFallback` / `warnings`） |
| 批量预览 | `batchPreview(...)` | 范围校验（年份/查询数 ≤ 100），按年份/季度循环，多次成功后才返回；任一查询成功即视为非失败 |
| 目录 | `chooseDirectory()` (`@MainActor`) | 默认实现打开 `NSOpenPanel` |
| 代理 | `testProxy(_:)` | 用 `loadSubjects` 间接测延迟 |
| 下载 | `startDownload(groups:saveDirectory:options:proxyURL:)` | 用 `Set(historyStore.load().map(\.filename))` 跳过已下载 |
| 下载 | `downloadStatus() / downloadItems() / consumeDownloadRecoverySummary()` | 直接代理到 `DownloadManager` |
| 下载 | `cancelDownloads() / retryRecoverableDownloads() / retryCompletedDownloadsNeedingRepair(ids:)` | |
| 更新 | `checkForUpdate(proxyURL:) / downloadUpdate(_:proxyURL:progress:) / updateDestinationURL(for:)` | 委托 `UpdateService` |
| 预览 | `previewURL(for:settings:)` | 优先命中已下载目录；命中走 `PreviewFileService` |
| 预览 | `discardManagedPreviewCacheFile(at:)` | 严格限定只能删除 `cache/preview/` 下的缓存 |
| 诊断 | `writeSupportDiagnostic(_:)` | 写支持文件并返回 `URL` |
| 内部 | `registry(proxyURL:)` / `registryMode(for:)` / `makeLiveRegistry(proxyURL:)` | `makeLiveRegistry` 默认注册 FrankCIE → EasyPaper → PastPapers → PapaCambridge |

`DownloadHistoryRecorder`（私有 actor）：下载完成后异步记录到 `DownloadHistoryStore`，避免阻塞 manager。

---

## 9. 数据源层（Sources）

目录：[`macos/Sources/CPaperNativeApp/Backend/Sources/`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/)

### 9.1 公共协议与模型

- [`PaperSource.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/PaperSource.swift)
  - `protocol PaperSource: Sendable`：要求 `id`、`displayName`、`fetchSubjects() async throws -> [Subject]`、`search(_:)`、`healthCheck() async -> SourceHealth`
  - `struct PaperSourceQuery`：`subjectCode`（构造时自动用 `SubjectNormalizer.subjectCode(in:)` 抽取 4 位数字 code）、`year?`、`season?`，提供 `seasonPrefix`（`m/s/w`）
  - `SourceHealthStatus`（`available/unavailable/degraded`）、`SourceHealth`
  - `SourceAttemptStatus`（`success/empty/failed`）、`SourceAttempt`（含 `durationMilliseconds`、`diagnosticMessage`）
  - `SourceSearchResult`（`sourceID/components/groups/attempts`）
  - `PaperSourceError`（`sourceUnavailable / invalidResponse / unsupportedSource / allSourcesUnavailable`）
  - `PaperComponent.sourceComponent(sourceID:parsed:url:label:)` 工厂
  - `PaperComponent.matches(_:)` 用 `subjectCode/year/seasonPrefix` 过滤
- [`PaperSourceID`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/CPaperModels.swift)：`automatic/frankcie/papaCambridge/pastPapers/easyPaper`，`automatic.allowsFallback = true`
- [`SourceRegistry.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/SourceRegistry.swift)
  - `enum SourceRegistryMode: .automatic / .manual(PaperSourceID)`
  - `automaticOrder: [.frankcie, .easyPaper, .pastPapers, .papaCambridge]`
  - `fetchSubjects(mode:)`：
    - `.automatic` 顺序尝试每个源，记录 `SourceAttempt`，第一个返回非空 `Subject` 即成功；全部失败 → `allSourcesUnavailable`
    - `.manual(id)`：直接调 `source.fetchSubjects`，空集抛 `sourceUnavailable("xxx 暂不可用或没有暴露科目目录")`
  - `search(_:mode:)`：自动模式下首条 `result.components` 非空即返回；`manual` 要求 `components` 非空
  - `runAutomaticAttempt` 使用 `withThrowingTaskGroup` 把单次操作和 `Task.sleep(timeout)` 竞争，实现 12s 自动超时

### 9.2 四个源

| 文件 | 来源 | 关键实现 |
| --- | --- | --- |
| [`FrankcieSource.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/FrankcieSource.swift) | `https://cie.fraft.cn` | `POST obj/Common/Subject/combo`（`FrankcieSubjectParser` 递归收集字典并 `subject(fromFrankcie:)`）；`POST obj/Common/Fetch/renum` 搜索（`FrankcieResponseParser` 提取 PDF 文件名并构造 redir URL） |
| [`EasyPaperSource.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/EasyPaperSource.swift) | `https://server.easy-paper.com` | 走 `paperdownload/dir_v3/<token>`；请求 / 响应均使用 `EasyPaperCrypto` 做 AES-CBC（CommonCrypto + 自定义随机前缀 / 自定义 IV / key）；文件路径存于 URL fragment 的 `easyPaperPath=base64(...)` |
| [`PastPapersSource.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/PastPapersSource.swift) | `https://pastpapers.co` | 解析 `caie/...` 目录页：先用 `PastPapersEntriesExtractor` 解 RSC JSON（`"file","filename","fname","name","url","href","path"` 字段），退化为 `season.candidateFilenames` 静态探测（`subjectCode_sy_type_nn.pdf` 命名规则，sy = `m/s/w` + 两位年份） |
| [`PapaCambridgeSource.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/PapaCambridgeSource.swift) | `https://pastpapers.papacambridge.com` | 仅在 `PapaCambridgeSubjectSlugs.seed`（当前只有 9709）里有映射时尝试；用 `PapaCambridgePDFCandidateExtractor` 正则提取 PDF 文件名；对每个候选做 `HEAD` 验证；遇到 Cloudflare challenge 通过 `CloudflareChallengeDetector.isChallenge(html:)` 显式抛 `sourceUnavailable`，不会绕过 |

### 9.3 其它

- [`PastPapersModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/PastPapersModels.swift)：`PastPapersLevel`（`aLevel/igcse/oLevel`）、`PastPapersSubjectDirectory`（含 `seed: 9709`）、`PastPapersSeason`（构造时用 `query.seasonPrefix` 决定 `sy` / `viewSlug` / `staticDirectoryNames`）、`PastPapersEntry` / `PastPapersEntriesExtractor`（解码嵌入在 HTML 里的 RSC 对象）
- [`SourceProviderSupport.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/SourceProviderSupport.swift)：`CloudflareChallengeDetector`（检测 "just a moment" / `cf-mitigated` / `challenge-platform`）、`NetworkClientError.isLikelyChallenge`（403 视作 challenge）
- [`SourceHealthChecker.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/SourceHealthChecker.swift)：批量 `healthCheck` 工具（对每个 `PaperSource` 调 `healthCheck()`）

---

## 10. 解析层（Parsing）

- [`PaperFilenameParser.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Parsing/PaperFilenameParser.swift)
  - 正则 `^(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf$`
  - 安全校验：`.pdf` 后缀、无路径分隔符、无 `..`、非隐藏文件
  - `year(fromSY:)` 把 `sy`（`mXX/sXX/wXX`）解析成 4 位年份（2000 + 后两位）
  - `seasonName(fromSY:)` 返回 `Mar/Jun/Nov`
  - `syCode(season:year:)` 反向构造 `sy`
  - `paperGroup(of:)` 把 paper number 收敛到分组（1..9 自映射，10+ 取十位）
- [`PaperGrouper.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Parsing/PaperGrouper.swift)
  - 把 `PaperComponent` 按 `sourceID|subject|sy|number` 配对成 QP/MS（无法配对时落入 `extras`）；对组按 `(paperGroup, number)` 排序
- [`SubjectNormalizer.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Parsing/SubjectNormalizer.swift)
  - `subject(fromFrankcie:)`：从 `value/code/id` + `text/name/title` 构造
  - `subjectCode(in:)`：正则 `(?<!\d)(\d{4})(?!\d)` 抽取 4 位科目代码（手动输入兼容）
  - `subject(fromDirectoryName:)`：解析 `Name (1234)` 或 `Name - 1234` 形式
  - `deduplicate(_:)`：按 code 去重
- [`HTMLPaperLinkExtractor.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Parsing/HTMLPaperLinkExtractor.swift)：基于 SwiftSoup 从 HTML 抓 `a[href]` 中 PDF 链接

---

## 11. 网络层（Networking）

- [`NetworkClient.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Networking/NetworkClient.swift)
  - `protocol NetworkClientProtocol: Sendable { func data(for: URLRequest) async throws -> Data }`
  - `final class NetworkClient: NetworkClientProtocol, @unchecked Sendable`
  - 默认 `URLSessionConfiguration.default` + User-Agent `C-Paper/<version> (macOS; SwiftNative)` + 可选代理
  - `NetworkClientError`：`invalidResponse / rateLimited(statusCode, retryAfter) / serverError / httpStatus / decodingFailed`
  - `validate(_:now:)`：`200..<300` 通过；`429` 转 `rateLimited` 并解析 `Retry-After`（秒数或 HTTP-date）；`500..<600` → `serverError`；其它 → `httpStatus`
  - 扩展：`get / postForm / decode<T>`
- [`HTTPRequestBuilder.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Networking/HTTPRequestBuilder.swift)
  - 构造 `URLRequest`：`get / head / postForm`；默认 20s 超时；表单 URL 编码并排序；附加头 `User-Agent / Accept: */*`
- [`HTTPFileTransferClient.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Networking/HTTPFileTransferClient.swift)
  - `typealias FileTransferProgressHandler = @Sendable (_ progress: Double?) async -> Void`
  - 基于 `URLSession.bytes(for:)` 流式写入文件（默认 64KB chunk），进度基于 `expectedContentLength` 计算，封顶 0.99
  - 失败 / 取消时 `defer` 中删除未完成文件
- [`ProxyConfiguration.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Networking/ProxyConfiguration.swift)
  - 解析 `http:// / https:// / socks5://` URL；构造 `connectionProxyDictionary`（含 `HTTPEnable/HTTPProxy/HTTPPort`、`SOCKSEnable/SOCKSProxy/SOCKSPort`、带凭据的 `*ProxyUsername/*Password`）
  - `applying(to: URLSessionConfiguration)` 注入到 `connectionProxyDictionary`

---

## 12. 下载层（Downloads）

### 12.1 队列 / 限流 / 熔断

- [`DownloadQueue.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadQueue.swift)
  - 基于 swift-collections `Deque<Element>` 的轻量 FIFO
- [`RateLimiter.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/RateLimiter.swift)
  - `actor RateLimiter`：根据 `rate`（req/s）算 `interval`，`acquire()` 等到下一个允许时间点
- [`CircuitBreaker.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/CircuitBreaker.swift)
  - `actor CircuitBreaker`：三态 `.closed/.open/.halfOpen`；`failureThreshold = 5`；`recoveryTimeout` 默认 30s
  - `allowRequest()`：open 且 `recoveryTimeout` 已到则 `halfOpen`；否则抛 `CircuitBreakerError.open`
  - `recordSuccess()` 清零回 `.closed`；`recordFailure()` 累计失败数达阈值则 `open`
  - `retryDelayBeforeNextRequest()` 返回 `Duration?` 供 manager 在 `waitForSafeRequestInstant` 等待

### 12.2 文件系统

- [`StagedFileSystem.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/StagedFileSystem.swift)
  - `stagedWrite(to:beforeFinalize:write:)`：先写 `<filename>.part.<UUID>`，成功后用 `replaceItemAt` 或 `moveItem` 原子替换到目标位置；`defer` 清理残留
  - `stagingURL(for:)` 把目标 URL 转成 `.part.<UUID>` 同目录临时文件
- [`DownloadDestinationBuilder.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift)
  - `build(groups:saveDirectory:options:downloadedFilenames:fileManager:)`：按组展开 → 仅保留 `QP/MS`（除非 `includeMarkSchemes = false`）→ 按 `merge` 决定 `root` 或 `root/<year>/<ftype>` → 应用 `DuplicateMode`（`overwrite / skip / missing`）→ 通过 `isContained` 防止目录穿越
  - `existingDownloadURL(for:saveDirectory:)`：先看 merged 目录，再看 `<year>/<ftype>` 拆分子目录
  - `safePDFFileName(_:url:)`：`.pdf` 后缀、`http(s)` URL、无路径分隔符 / `..`、非隐藏、不含禁止字符
  - `safeFolderComponent(_:)`：仅保留 `[A-Za-z0-9_-]`，其它替换为 `_`
  - 自定义错误 `DownloadDestinationError.invalidSaveDirectory`

### 12.3 URL 解析 / 预览

- [`DownloadSourceURLResolver.swift`](file:///Users/yimingwu/Documents/C-PaperNativeApp/Backend/Downloads/DownloadSourceURLResolver.swift)
  - EasyPaper 的真实文件 URL 通过 `URL.easyPaperFilePath`（fragment 里的 base64）拿原 `dir` 路径，再重新生成加密 token；其它源直接返回原 `url`
- [`PreviewFileService.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/PreviewFileService.swift)
  - `actor PreviewFileService`：先检查 `DownloadDestinationBuilder.existingDownloadURL`（用户已经下载过的文件直接预览），否则走 `cache/preview/<filename>` 缓存；同一缓存 URL 并发请求会合并为单个 `Task`
  - `previewURL(for:settings:)` 命中缓存或已有 Task 即返回；`withTaskCancellationHandler` 处理 `task.cancel()`
  - 写入仍走 `StagedFileSystem.stagedWrite`

### 12.4 下载管理器

- [`DownloadManager.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift)
  - `actor DownloadManager`
  - 状态：`queue: DownloadQueue<Int>`、`workItems: [Int: DownloadDestinationTask]`、`downloadItems: [Int: DownloadTaskItem]`、`snapshot: DownloadStatusSnapshot`、`isCancelled`、`runID: Int`、`runnerTask: Task<Void, Never>?`
  - 限流与熔断：`RateLimiter(rate:)`、`CircuitBreaker(recoveryTimeout:)`；最多重试 3 轮
  - 构造期 `DownloadSessionStore.restoreInterruptedSession()`：恢复上次未完成任务 → 清理 `.part.*` 残留 → 把 `pending/downloading` 标记为 `failed(.interrupted)`
  - `start(...)`：构造 `DownloadDestinationPlan` → 重置 runID / queue / 各项 → 拉起 `runnerTask.run(workers:runID:proxyURL:rateLimiter:circuitBreaker:)`
  - `run(workers:...)`：按 `workers` 数量 fan-out `workerLoop`；任一 worker 失败可整轮重试（最多 3 轮）
  - `workerLoop`：等待 `waitForSafeRequestInstant`（同时考虑 `RateLimiter` 冷却 + `CircuitBreaker` 等待） → 从队列取任务 → `download(_:...)` → 写文件 → 标 `done` / `failed` / `cancelled`
  - `download`：按 `try circuitBreaker.allowRequest() / rateLimiter.acquire() / checkCancellation()` 的顺序执行；错误分类：HTTP `429` → 更新冷却 + `.rateLimit`、NSURLError → `.network`、其它 → `.unknown`
  - `cancel()`：仅在 `snapshot.phase == .running` 时生效，置 `isCancelled = true`，把 `pending/downloading` 全部置 `cancelled`
  - `retryRecoverableFailedItems()` / `retryCompletedItemsNeedingRepair(ids:)`：基于 `lastOptions/lastProxyURL` 重新拉起
  - `consumeRecoverySummary()` / `status() / items()`：UI 轮询接口
  - `persistSessionIfPossible()`：每次状态变更都落盘 `download_session.json`，用于会话中断恢复
- [`DownloadDestinationTask`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift)：UI 列表项（`displayItem → DownloadTaskItem`）
- [`DownloadTestSupport.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Tests/CPaperNativeTests/DownloadTestSupport.swift) / [`TransferTestSupport.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Tests/CPaperNativeTests/TransferTestSupport.swift)：测试用的假 `SharedTransferWriter` / `FileTransferProgressHandler`

---

## 13. 持久化层（Persistence）

- [`AppStoragePaths.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/AppStoragePaths.swift)
  - `appSupportDirectory = ~/Library/Application Support/C-Paper`
  - `cacheDirectory = <appSupport>/cache`
  - `settingsURL / favoritesURL / downloadHistoryURL / downloadSessionURL / migrationMarkerURL`
- [`JSONFileStore.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/JSONFileStore.swift)
  - 泛型 `JSONFileStore<Value: Codable>`：原子写、损坏时备份到 `<filename>.corrupt.<ts>[.n]`
- [`SettingsStore`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/SettingsStore.swift) / [`FavoritesStore`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/FavoritesStore.swift) / [`DownloadHistoryStore`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/DownloadHistoryStore.swift) / [`DownloadSessionStore`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/DownloadSessionStore.swift) / [`SearchCacheStore`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/SearchCacheStore.swift) / [`SupportDiagnosticsStore`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/SupportDiagnosticsStore.swift)：分别包装 `JSONFileStore`
  - `SearchCacheStore`：24h TTL（`BackendConstants.cacheTTL`）；按 `PaperSourceID` 分目录，文件名取 base64
  - `DownloadHistoryStore`：`BackendConstants.historyMaxItems = 2_000` 上限
  - `DownloadSessionStore`：`restoreInterruptedSession()` 删 `*.part.*` 临时文件并把 `pending/downloading` 标 `failed(.interrupted)`
  - `SupportDiagnosticsStore`：写 `latest-diagnostic.txt` 到 `appSupport/Support/`
- [`LegacyCacheMigrator.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Persistence/LegacyCacheMigrator.swift)：从 `~/.cie_cache/` 迁移 `settings/favorites/download_history`（目标不存在才迁移），完成后写 `legacy_migration.json` 标记，避免重复

---

## 14. 更新层（Updates）

- [`UpdateService.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift)
  - `enum UpdateServiceError`：`invalidLatestRelease / noCompatibleDMGAsset / invalidVersion`
  - `struct AppVersion`：解析 `v?X.Y[.Z]`，实现 `Comparable` 用于版本比较
  - `final class UpdateService: @unchecked Sendable`（`@unchecked Sendable` 方便跨 actor 传递）
  - 注入点：`currentVersion`（默认 `BackendConstants.version`）、`latestReleaseURL`（默认 GitHub `releases/latest` API）、`updatesDirectory`（默认 `~/Downloads/C-Paper/Updates`）、`networkClientFactory` / `transferClientFactory` / `beforeFinalize` 钩子
  - `checkForUpdate(proxyURL:)` → `AppUpdateCheckResult`（`.upToDate / .available(AppUpdateRelease)`）
  - `downloadUpdate(_:proxyURL:progress:)`：先 `fileSystem.createDirectory`，再走 `stagedWrite(beforeFinalize:write:)` 写入 DMG；最后 `progress(1)`
  - `destinationURL(for:)`：用 `assetName.safeUpdateFilename` 过滤非法字符
  - 私有 `GitHubReleasePayload` / `GitHubReleaseAsset`：`isCompatibleDMG` 判定 = 名字含 `C-Paper-Native` + 含 `standalone` + `.dmg` 后缀
- [`UpdateModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/UpdateModels.swift)
  - `UpdateCheckSource`（`startup/manual`）
  - `AppUpdateRelease`（`version/tagName/name/htmlURL/assetName/downloadURL`）
  - `AppUpdateCheckResult` / `UpdateDownloadState` / `DownloadedUpdateState`（含 `origin: currentSession / restoredArtifact`）/ `UpdateInstallState`（`downloaded/requiresManualOpen/missingFile/invalidFile`）/ `UpdateFailureState` / `UpdateStatus`（`idle/checking/upToDate/available/downloading/downloaded/failed`）

---

## 15. 设计系统（Design）

目录：[`macos/Sources/CPaperNativeApp/Design/`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Design/)

- [`DesignSystem.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Design/DesignSystem.swift)
  - `CPDesign`：`Spacing (xs/sm/md/lg/xl)`、`Radius (control/panel/floating)`、`Motion (standard/tactile/gentle)`（提供 `reduceMotion` 适配）、`SurfaceRole (base/content/control/floating/modal)`（驱动 material / radius / shadow）、`GlassButtonProminence (subtle/normal/primary/destructive)`
- [`GlassSurface.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Design/GlassSurface.swift)：基础磨砂面板 + `LiquidGlassSurfaceModifier`
- [`GlassButtonStyle.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Design/GlassButtonStyle.swift)：基于 `GlassButtonProminence` 的按钮样式
- [`GlassControls.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Design/GlassControls.swift) / [`GlassIndicators.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Design/GlassIndicators.swift)：其它磨砂控件 / 指示器

---

## 16. 关键模型（Models）

目录：[`macos/Sources/CPaperNativeApp/Models/`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/)

- [`CPaperModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/CPaperModels.swift)
  - `AppRoute`（`search/batch/downloads` + title + SF Symbol）
  - `Subject`（`code / name`，自动清理显示名）
  - `Season`（`mar/jun/nov` → `Mar 春 / Jun 夏 / Nov 冬`）
  - `DuplicateMode`（`overwrite / skip / missing`）
  - `PaperSourceID`（`automatic / frankcie / papaCambridge / pastPapers / easyPaper`）
- [`PaperModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/PaperModels.swift)
  - `PaperComponent` / `NativePaperGroup`（含 `qp / ms / extras`） / `PaperFile`（UI 用，含 `componentKey / componentTitle / subtitle`）
  - `BackendPaperGroup`（历史兼容）
  - `SearchPayload` / `BatchPreviewPayload`（搜索/预览结果 + 元数据）
  - `SearchParams` / `BatchPreviewParams`
- [`DownloadModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/DownloadModels.swift)
  - `DownloadStartParams` / `DownloadOptions`（`rate / threads / merge / duplicateMode / includeMarkSchemes`）
  - `DownloadStatus`（`pending / downloading / done / failed / cancelled / skipped`）
  - `DownloadTaskItem`（自定义 `init(from:)` / `encode(to:)` 以保留 `errorType` 兼容）
  - `DownloadTaskWorkflowTag` / `DownloadTaskIntegrityState`（`missingFile / unreadableFile / emptyFile / directoryPath / nonRegularFile`）/ `DownloadTaskErrorType`（`network / rateLimit / cancelled / interrupted / unknown`）/ `DownloadTaskRecoveryAction`（`none / retryNow / retryLater / inspectDiagnostic / restartIfNeeded`）
  - `DownloadStatusSnapshot` / `DownloadQueuePhase` / `DownloadStartResult` / `ProxyResult` / `OKResult` / `PDFURLResult` / `ProxyParams` / `FavoriteParams` / `FileNameParams`
  - `DownloadSettings`（`theme/saveDirectory/includeMarkSchemes/rate/threads/mergeFolders/proxyURL/lastSubject/lastMode/duplicateMode/sourceMode`） + `downloadOptions` 转换
- [`UpdateModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/UpdateModels.swift)：见 §14
- [`SupportDiagnostics.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift)
  - `SupportDiagnosticContext`（`general/startup/supportDirectory/settings/favorites/saveDirectory/sourceProvider/download/downloadIntegrity/preview/update`）
  - `SupportDiagnosticDetail` / `SupportDiagnostic`（构造时 `Self.redact` 自动打码：URL 凭据、EasyPaper token、本地路径用户名、`token=...&access_token=...&key=...&sig=...&x-amz-signature=...`）
- [`WorkflowStateModels.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift)
  - 通知 / Notice：`SourceNotice` / `DownloadNotice` / `SettingsNotice` / `FavoriteNotice` / `SaveDirectoryNotice` / `SupportDirectoryNotice` / `DownloadRecoveryNotice` / `DownloadIntegrityNotice` / `UpdateNotice`
  - 状态：`PreviewLoadState`（`idle / loading / loaded(URL) / failed(PreviewFailureState)`）
  - 表现层：`SearchWorkflowPresentation` / `BatchPreviewWorkflowPresentation` / `UpdateWorkflowPresentation` / `RootWorkflowPresentation` / `SettingsWorkflowPresentation` / `UpdateSettingsWorkflowPresentation` / `DownloadsWorkflowPresentation` / `PreviewLoadRequest`
- [`SubjectPickerLogic.swift`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Models/SubjectPickerLogic.swift)：`filteredSubjects / subjectSelectionState / manualCodeState`

---

## 17. 错误与诊断

- [`BackendError`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Core/BackendError.swift)：`invalidURL / invalidResponse / sourceUnavailable / noResults / downloadInProgress / invalidFilename / fileSystem`
- [`NetworkClientError`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Networking/NetworkClient.swift)：见 §11
- [`PaperSourceError`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Sources/PaperSource.swift)：`sourceUnavailable / invalidResponse / unsupportedSource / allSourcesUnavailable`
- [`CircuitBreakerError`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/CircuitBreaker.swift)：`open`
- [`UpdateServiceError`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift)：`invalidLatestRelease / noCompatibleDMGAsset / invalidVersion`
- [`DownloadDestinationError`](file:///Users/yimingwu/Documents/C-Paper/macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift)：`invalidSaveDirectory`
- 诊断系统：`AppModel.recordDiagnostic(context:message:details:)` → `SupportDiagnosticsStore.write` → 写 `appSupport/Support/latest-diagnostic.txt`，UI 通过 `lastDiagnostic / diagnosticsByContext` 提供"复制诊断" / "显示支持文件夹" 入口；`SupportDiagnostic.redact` 负责把 `~/` 替换为 `~/`、把 `http://user:pass@` 改为 `<redacted>@`、EasyPaper token / 通用 `token=…&key=…&sig=…` 全部打码
- 启动失败：`AppBootFailure` 在构造时把 `Error` 转为 `SupportDiagnostic`，附带 `supportDirectoryURL`，让 `StartupFailureView` 可以在不依赖 `AppModel` 的情况下"显示支持文件夹"和"复制诊断"

---

## 18. 测试套件

目录：[`macos/Tests/CPaperNativeTests/`](file:///Users/yimingwu/Documents/C-Paper/macos/Tests/CPaperNativeTests/)

| 文件 | 覆盖 |
| --- | --- |
| `AppDelegateTests` | 启动后主菜单只安装一次、窗口属性 |
| `AppMenuCommandCenterTests` | 命令 bind/unbind、canPerform、`dispatchMenuItem` |
| `AppMenuControllerTests` | 菜单树结构（命令 → NSMenuItem） |
| `StartupBootCoordinatorTests` | 启动 → ready / failed，失败重试 attemptID 隔离 |
| `CircuitBreakerTests` | 三态转换、恢复超时 |
| `DownloadDestinationBuilderTests` | 计划构造、安全文件名、目录合并、重复策略 |
| `DownloadManagerTests` | 队列/限流/熔断/取消/中断恢复/重试 |
| `DownloadSessionStoreTests` | 中断会话恢复 + 临时文件清理 |
| `HTTPFileTransferClientTests` | 流式写入、进度、取消 |
| `LiveSourceTests` | 可选的 `RUN_LIVE_SOURCE_TESTS=1` 真实源 canary |
| `ModelTests` | 模型序列化 / Codable 兼容 |
| `NativeBackendServicePreviewTests` | `NativeBackendService.previewURL` 缓存命中 |
| `PDFPreviewPaneLayoutTests` | 预览面板布局 |
| `PaperParsingTests` | 文件名解析、SY 解析、组卷 |
| `PaperSourceFixtureTests` | 四个 `PaperSource` 在离线 fixture 上的行为 |
| `PersistenceTests` | `JSONFileStore`、损坏文件备份、迁移 |
| `RenderedWorkflowInteractionTests` | UI 集成（基于 ViewInspector） |
| `SmokeTests` | 冒烟 |
| `SourceRegistryTests` | 自动回退、手动模式、超时 |
| `StagedFileSystemTests` | 阶段式写入原子替换 |
| `SubjectPickerLogicTests` | 搜索过滤、状态切换 |
| `SupportDiagnosticsTests` | 诊断文本 / 打码 |
| `TransferTestSupport` | 测试 helper（不会作为独立测试） |
| `DownloadTestSupport` | 测试 helper |
| `UpdateServiceTests` | GitHub 响应解析 / 下载流程 |
| `WorkflowPresentationTests` | `RootWorkflowPresentation` 等表现层 |

默认入口：`swift test --jobs 1`（也通过 `scripts/run_native_release_audit.sh` 集中调度）。

---

## 19. 构建脚本与发布工作流

### 19.1 关键脚本

- [`scripts/build_native_dmg.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/build_native_dmg.sh)
  - 5 步：(1) `swift build -c <debug|release>` 并在 SWIFT_SCRATCH_PATH 重用上次构建结果；(2) 组装 `CPaperNative.app`（含 `Info.plist`、`AppIcon.icns`）；(3) 签名（默认 ad hoc，可选 Developer ID）并清理 bundle metadata；(4) 用 `hdiutil` 创建并美化 DMG（icon view、背景图、布局 96px、`.VolumeIcon.icns`）；(5) notarize（可选）+ `verify_codesign_best_effort` + `spctl --assess`
  - 通过 `scripts/lib/native_dmg_helpers.sh`、`swiftpm_retry_helpers.sh`、`version_helpers.sh` 复用
- [`scripts/verify_native_dmg.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/verify_native_dmg.sh)：DMG 验证入口（`hdiutil verify`、挂载检查、codesign 验证、`.background` 与 `Applications` symlink 检查）
- [`scripts/run_native_release_audit.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/run_native_release_audit.sh)
  - 1/8 shell 语法 → 2/8 `version.json` JSON 解析 → 3/8 workflow YAML 解析 → 4/8 发布文档一致性 → 5/8 版本漂移 → 6/8 仓库卫生 → 7/8 `swift test --jobs 1` → 8/8 可选 live canary
  - 可选参数：`--with-package`、`--with-live-sources`、`--release-candidate`（两者同时开启）
- [`scripts/check_release_docs.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/check_release_docs.sh)、[`check_repo_hygiene.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/check_repo_hygiene.sh)、[`check_swift_quality.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/check_swift_quality.sh)、[`check_version_drift.sh`](file:///Users/yimingwu/Documents/C-Paper/scripts/check_version_drift.sh)：单项静态门

### 19.2 GitHub Actions

- `.github/workflows/build.yml`：三段式 `validate / package / release`
  - `validate`：`shellcheck`/JSON/YAML/release docs/version drift/repo hygiene/Swift quality + `swift test --jobs 1`
  - `package`（依赖 `validate`，仅在 `push` / `workflow_dispatch`）：可选 Developer ID 配置 + `scripts/build_native_dmg.sh` + `verify_native_dmg.sh` + 上传 30 天 artifact
  - `release`（依赖 `package`，仅在 `push` `v*` tag）：从 `version.json` 渲染 release notes 并创建 GitHub Release
- `.github/workflows/legacy-release.yml`：归档，仅服务于 legacy 5.2.1
- `.github/release-notes/`：历史版本说明归档（`legacy-v5.2.1.md`、`native-v6.0.x.md`）

### 19.3 版本元数据

[`version.json`](file:///Users/yimingwu/Documents/C-Paper/version.json)：

```json
{
  "version": "6.0.5",
  "min_version": "6.0.0",
  "download_url": "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.5",
  "release_notes": "...",
  "force_update": false,
  "published_at": "2026-06-08T00:00:00Z"
}
```

`BackendConstants.version` / `Package.swift` / `scripts/build_native_dmg.sh`（`version_helpers.sh`）都会引用它，`check_version_drift.sh` 用来检查三处版本是否一致。

---

## 20. 运行、构建与发布

### 20.1 本地开发运行

```bash
swift run CPaperNative
```

应用会立刻进入主窗口 + 主菜单（先于 ready UI 安装）。`open` 之后可断点调试。

### 20.2 单元 / 集成测试

```bash
swift test --jobs 1
```

可选：跑真实源 canary（依赖网络与第三方可用性）：

```bash
RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests
```

### 20.3 一键发布候选审计

```bash
bash scripts/run_native_release_audit.sh
# 更严格的 RC 审计
bash scripts/run_native_release_audit.sh --release-candidate
```

### 20.4 本地构建 DMG

```bash
CONFIGURATION=release bash scripts/build_native_dmg.sh
bash scripts/verify_native_dmg.sh
```

产物：`dist/CPaperNative.app` 与 `dist/C-Paper-Native-<version>-standalone-<YYYYMMDD>.dmg`。

### 20.5 签名与公证

- 默认 ad hoc：本地直接可用，macOS 首次打开可能提示"无法验证开发者"，右键 → 打开。
- 可选 Developer ID：导出 `CPAPER_CODESIGN_IDENTITY`；如需公证，再导出 `CPAPER_NOTARY_KEYCHAIN_PROFILE`，`build_native_dmg.sh` 会在 DMG 生成后自动 `notarytool submit --wait` + `stapler staple`。
- CI 等价 secrets：`CPAPER_DEVELOPER_ID_CERT_P12_BASE64 / CPAPER_DEVELOPER_ID_CERT_PASSWORD / CPAPER_CODESIGN_IDENTITY / CPAPER_NOTARY_KEYCHAIN_PROFILE / CPAPER_NOTARY_APPLE_ID / CPAPER_NOTARY_TEAM_ID / CPAPER_NOTARY_APP_PASSWORD`。任一缺失则保持 ad hoc 路径。

### 20.6 用户安装

1. 从 [Releases](https://github.com/yimingwu425/C-Paper/releases) 下载 `C-Paper-Native-*-standalone-*.dmg`
2. 双击 DMG，把 `CPaperNative.app` 拖入 `/Applications`
3. 首次运行若遇安全提示：右键 → 打开 → 确认

---

## 21. 依赖关系

| 依赖 | 来源 | 用途 |
| --- | --- | --- |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup.git) `>= 2.13.4` | SwiftPM | `HTMLPaperLinkExtractor` 解析目录页 |
| [swift-collections](https://github.com/apple/swift-collections.git) `>= 1.1.0` | SwiftPM | `DownloadQueue` 使用 `Deque` |
| [ViewInspector](https://github.com/nalexn/ViewInspector.git) `>= 0.10.3` | SwiftPM（仅测试 target） | `RenderedWorkflowInteractionTests` 等 UI 测试 |
| `AppKit` / `SwiftUI` / `PDFKit` / `Observation` | Apple SDK | UI 与状态观察 |
| `Foundation` / `CryptoKit` 相关 | Apple SDK | 文件、URL、JSON、字符串 |
| `CommonCrypto` | Apple SDK | `EasyPaperCrypto` 做 AES-CBC 加密 / 解密 |
| 第三方上游 | 网络 | `cie.fraft.cn` / `papacambridge.com` / `pastpapers.co` / `easy-paper.com`（CIE past paper 公共数据源） |
| GitHub Releases API | 网络 | `UpdateService` 检查更新 / 下载 DMG |

没有其它第三方运行期依赖（legacy Python 栈完全独立于 native 主线）。

---

## 22. 隐私、免责声明与数据源策略

C-Paper **不上传、不收集、不分享**任何用户个人数据，本地状态保存于：

- `~/Library/Application Support/C-Paper/`（设置 / 收藏 / 下载历史 / 搜索缓存 / 诊断 / 下载会话）
- 用户在设置里选择的下载目录（默认 `~/Downloads/C-Paper`）

首次启动 6.x 会从 `~/.cie_cache/` 复制可识别的旧设置、收藏与下载历史。

应用搜索 / 下载的试卷 / 评分标准来自第三方公开站点（FrankCIE / PapaCambridge / PastPapers / EasyPaper），著作权归 Cambridge Assessment International Education 或对应权利方所有；项目仅整理可访问的公开链接，不存储、不托管原始文件。

数据源策略：

- **自动模式**：按 `FrankCIE → EasyPaper → PastPapers → PapaCambridge` 顺序回退；遇到 Cloudflare challenge 不会绕过，直接报告"不可用"。
- **手动模式**：严格使用所选源，失败不会自动跳到其它源；若所选手动源不暴露科目目录，应用会提示用户改用手动输入科目代码（这是预期的恢复路径，不是 bug）。

---

## 23. 已知边界与项目规则

按 [`AGENTS.md`](file:///Users/yimingwu/Documents/C-Paper/AGENTS.md) 与 [`docs/PROJECT_INDEX.md`](file:///Users/yimingwu/Documents/C-Paper/docs/PROJECT_INDEX.md)：

- 不要把 `legacy/` 当作主实现；只在任务明确涉及 legacy 时才动它。
- `macos/Sources/CPaperNativeApp/Backend/Sources/`、`Backend/Downloads/`、`Backend/Persistence/`、`scripts/build_native_dmg.sh` 是敏感区域，谨慎编辑。
- 优先复用 `Design/`、`Views/PageScaffold.swift`、`Views/WorkflowChrome.swift`、`DesignSystem` 中已有的视觉组件；不要引入新的视觉风格。
- 业务逻辑与 UI 渲染分离；保持 IO / 网络 / 文件系统代码与纯逻辑分离。
- 修改代码或配置后追加一行 `docs/WORK_LOG.md`。
- 默认用中文回复用户；不主动创建 markdown / README 文档（除非用户明确要求）。
- 高噪声路径不要扫（`.git/`、`node_modules/`、`dist/`、`build/`、`.build/`、`__pycache__/`、`.cache/`、`.worktrees/`）。
- 当细节不确定时，写"Unknown / not yet documented"，不要猜测。

### 关键不变量（来自源码）

- `NativeBackendService.discardManagedPreviewCacheFile(at:)` 严格校验路径必须在 `cache/preview/` 之下，否则返回 `false`，避免误删用户文件。
- `DownloadDestinationBuilder.safePDFFileName` 强制 `.pdf` 后缀、`http(s)`、无路径分隔符 / `..`、非隐藏、无禁用字符。
- `StagedFileSystem.stagedWrite` 用 `*.part.<UUID>` 临时文件 + 原子替换保证断电 / 取消不污染目标。
- `DownloadManager.run` 用 `runID` 防止上一次 run 的回调污染下一次；`persistSessionIfPossible` 在每次状态变更后写盘，实现"中断可恢复"。
- `SourceRegistry.runAutomaticAttempt` 12s 单源超时，避免某个源长时间挂起整体搜索。
- `RateLimiter` 冷却 + `CircuitBreaker` 互相独立，HTTP `429` 还会更新本地冷却门；UI 在 `waitForSafeRequestInstant` 处等待并显示"服务器限流 / 熔断器恢复中"。
- `AppMenuController.install` 在 `AppDelegate.applicationDidFinishLaunching` 即被调用，并在 `showMainWindow` 路径上幂等保护（`hasInstalledMainMenu`），主菜单在 ready UI 出现前就已就绪。
- `RootView` 通过 `.onAppear { ReadyRootMenuBindings.bind(model:) }` / `.onDisappear { ReadyRootMenuBindings.unbind() }` 严格把菜单命令与当前 `AppModel` 绑定，避免模型被销毁后菜单仍调用旧 handler。
- 所有用户可见文本统一中文（含菜单、错误、状态栏、设置页）。诊断 `SupportDiagnostic.redact` 自动打码 `~/`、URL 凭据、EasyPaper token、常见 `token/key/sig/...` 查询串。
