import AppKit
import Foundation
import Observation
import PDFKit

private enum SaveDirectoryAvailability {
    case ready(URL)
    case creatable(URL)
    case unavailable(String)
}

@MainActor
@Observable
final class AppModel {
    var route: AppRoute = .search
    var subjects: [Subject] = []
    var favorites: [Subject] = []
    var selectedSubject: Subject?
    var manualSubjectCode: String = ""
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedSeason: Season = .nov
    var batchYearFrom: Int = max(2000, Calendar.current.component(.year, from: Date()) - 2)
    var batchYearTo: Int = Calendar.current.component(.year, from: Date())
    var batchSeasons: Set<Season> = Set(Season.allCases)
    var batchPaperGroups: Set<Int> = [1, 2, 3, 4, 5, 6]
    var searchResults: [PaperFile] = []
    var searchGroups: [NativePaperGroup] = []
    var searchResultSourceID: PaperSourceID?
    var searchUsedAutomaticFallback = false
    var batchPreview: [PaperFile] = []
    var batchGroups: [NativePaperGroup] = []
    var batchPreviewSourceIDs: [PaperSourceID] = []
    var batchPreviewSuccessfulQueryCount = 0
    var batchPreviewAutomaticFallbackQueryCount = 0
    var downloads: [DownloadTaskItem] = []
    var selectedPreview: PaperFile? {
        didSet {
            guard selectedPreview?.id != oldValue?.id else { return }
            pendingPreviewRepairFileID = nil
            previewLoadState = .idle
            previewLoadRevision = 0
        }
    }
    var expandedPaperComponents: Set<String> = []
    var settings = DownloadSettings()
    var downloadSnapshot = DownloadStatusSnapshot(phase: .idle, done: 0, total: 0, success: 0, message: "Ready", failed: nil, cancelled: nil, skipped: nil)
    var updateStatus: UpdateStatus = .idle
    var pendingUpdatePrompt: AppUpdateRelease?
    var didRunStartupUpdateCheck = false
    var isLoading = false
    var isSettingsPresented = false
    var errorMessage: String?
    var sourceNotice: SourceNotice?
    var downloadNotice: DownloadNotice?
    var downloadRecoveryNotice: DownloadRecoveryNotice?
    var downloadRecoveredCleanedPartialCount = 0
    var downloadIntegrityNotice: DownloadIntegrityNotice?
    var downloadIntegrityStatesByTaskID: [Int: DownloadTaskIntegrityState] = [:]
    var settingsNotice: SettingsNotice?
    var favoriteNotice: FavoriteNotice?
    var saveDirectoryNotice: SaveDirectoryNotice?
    var supportDirectoryNotice: SupportDirectoryNotice?
    var updateNotice: UpdateNotice?
    var previewLoadState: PreviewLoadState = .idle
    var lastDiagnostic: SupportDiagnostic?
    var diagnosticsByContext: [SupportDiagnosticContext: SupportDiagnostic] = [:]
    var lastDownloadFailureDiagnosticSignature: String?
    var lastDownloadIntegrityDiagnosticSignature: String?
    var previewLoadRevision = 0
    var pendingPreviewRepairFileID: String?

    @ObservationIgnored let backend: NativeBackendService
    @ObservationIgnored private let openDownloadedFile: (URL) -> Bool
    @ObservationIgnored var pollTask: Task<Void, Never>?

    init(
        backend: NativeBackendService,
        openDownloadedFile: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.backend = backend
        self.openDownloadedFile = openDownloadedFile
    }

    static func live() throws -> AppModel {
        AppModel(backend: try NativeBackendService())
    }

    var completedDownloadCount: Int {
        downloads.filter { $0.status == .done || $0.status == .skipped }.count
    }

    var failedDownloadCount: Int {
        downloads.filter { $0.status == .failed }.count
    }

    var retryableFailedDownloadCount: Int {
        downloads.filter { $0.status == .failed && $0.recoveryAction.allowsQueueRetry }.count
    }

    var cancelledDownloadCount: Int {
        downloads.filter { $0.status == .cancelled }.count
    }

    var skippedDownloadCount: Int {
        downloads.filter { $0.status == .skipped }.count
    }

    var activeDownloadCount: Int {
        downloads.filter { $0.status == .pending || $0.status == .downloading }.count
    }

    var hasRetryableFailedDownloads: Bool {
        retryableFailedDownloadCount > 0
    }

    var interruptedFailedDownloadCount: Int {
        downloads.filter { $0.status == .failed && $0.errorType == .interrupted }.count
    }

    var downloadRecoverySummary: String? {
        guard interruptedFailedDownloadCount > 0 else { return nil }
        if downloadRecoveredCleanedPartialCount > 0 {
            return "当前队列包含 \(interruptedFailedDownloadCount) 个从上次会话恢复的失败任务，启动时已清理 \(downloadRecoveredCleanedPartialCount) 个残留临时文件。"
        }
        return "当前队列包含 \(interruptedFailedDownloadCount) 个从上次会话恢复的失败任务，可直接重试失败项。"
    }

    func downloadIntegrityState(for taskID: Int) -> DownloadTaskIntegrityState? {
        downloadIntegrityStatesByTaskID[taskID]
    }

    var batchSeasonList: [Season] {
        Season.allCases.filter { batchSeasons.contains($0) }
    }

    var isSelectedSubjectFavorite: Bool {
        guard let activeSubject else { return false }
        return favorites.contains { $0.code == activeSubject.code }
    }

    var backendRuntimePath: String {
        backend.appSupportPath
    }

    var supportDirectoryPath: String {
        backend.supportDirectoryPath
    }

    var activeSubject: Subject? {
        if let selectedSubject {
            return selectedSubject
        }
        guard let code = SubjectNormalizer.subjectCode(in: manualSubjectCode) else {
            return nil
        }
        return Subject(code: code, name: "手动输入 \(code)")
    }

    var hasSearchSubject: Bool {
        activeSubject != nil
    }

    var searchResultSourceSummary: String? {
        guard let searchResultSourceID else { return nil }
        if searchUsedAutomaticFallback {
            return "当前结果来自 \(searchResultSourceID.title)，系统已自动跳过更慢或不可用的前置来源。"
        }
        return "当前结果来自 \(searchResultSourceID.title)。"
    }

    var downloadedUpdateState: DownloadedUpdateState? {
        guard case let .downloaded(state) = updateStatus else { return nil }
        return state
    }

    var updateDownloadedSummary: String? {
        downloadedUpdateState?.persistentSummary
    }

    var batchPreviewSourceSummary: String? {
        guard !batchPreview.isEmpty, !batchPreviewSourceIDs.isEmpty, batchPreviewSuccessfulQueryCount > 0 else {
            return nil
        }

        let sourceTitles = batchPreviewSourceIDs.map(\.title)
        let sourceDescription: String
        if sourceTitles.count == 1, let sourceTitle = sourceTitles.first {
            sourceDescription = "结果均来自 \(sourceTitle)"
        } else {
            sourceDescription = "结果来自 \(sourceTitles.joined(separator: "、"))"
        }

        if batchPreviewAutomaticFallbackQueryCount > 0 {
            return "本次预览成功获取 \(batchPreviewSuccessfulQueryCount) 个年份/考季查询，\(sourceDescription)，其中 \(batchPreviewAutomaticFallbackQueryCount) 次查询触发自动回退。"
        }

        return "本次预览成功获取 \(batchPreviewSuccessfulQueryCount) 个年份/考季查询，\(sourceDescription)。"
    }

    var previewLoadRequest: PreviewLoadRequest? {
        guard let selectedPreview else { return nil }
        return PreviewLoadRequest(fileID: selectedPreview.id, revision: previewLoadRevision)
    }

    func clearError() {
        errorMessage = nil
    }

    func retryPreview() {
        guard selectedPreview != nil else { return }
        previewLoadState = .idle
        previewLoadRevision += 1
    }

    func redownloadSelectedPreviewFile() async {
        guard let selectedPreview else { return }
        await startSingleFileDownload(selectedPreview, forcedDuplicateMode: .overwrite)
        if downloadSnapshot.isRunning {
            pendingPreviewRepairFileID = selectedPreview.id
            return
        }
        guard self.selectedPreview?.id == selectedPreview.id else { return }
        if downloads.contains(where: { $0.filename == selectedPreview.filename && $0.status == .done }) {
            retryPreview()
        }
    }

    func closePreview() {
        selectedPreview = nil
        previewLoadState = .idle
    }

    func revealPreviewFile() {
        guard let localURL = previewLoadState.localURL else { return }
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            handleMissingPreviewFile(localURL)
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([localURL])
    }

    @discardableResult
    func recordDiagnostic(
        context: SupportDiagnosticContext,
        message: String,
        details: [SupportDiagnosticDetail] = []
    ) -> SupportDiagnostic {
        var diagnostic = SupportDiagnostic(
            context: context,
            message: message,
            details: details,
            supportDirectoryPath: backend.supportDirectoryPath
        )
        if let reportURL = try? backend.writeSupportDiagnostic(diagnostic) {
            diagnostic = diagnostic.withReportURL(reportURL)
        }
        lastDiagnostic = diagnostic
        diagnosticsByContext[context] = diagnostic
        return diagnostic
    }

    func copyLatestDiagnostic() {
        guard let lastDiagnostic else { return }
        copyDiagnostic(lastDiagnostic)
    }

    func copyDiagnostic(for context: SupportDiagnosticContext) {
        guard let diagnostic = diagnosticsByContext[context] else { return }
        copyDiagnostic(diagnostic)
    }

    func latestDiagnostic(for context: SupportDiagnosticContext) -> SupportDiagnostic? {
        diagnosticsByContext[context]
    }

    func loadSelectedPreviewIfNeeded() async {
        guard let selectedPreview, let request = previewLoadRequest else {
            previewLoadState = .idle
            return
        }

        previewLoadState = .loading

        do {
            let localURL = try await backend.previewURL(for: selectedPreview, settings: settings)
            guard request == previewLoadRequest, !Task.isCancelled else { return }
            guard validateLoadedPreviewFile(localURL, file: selectedPreview) else { return }
            previewLoadState = .loaded(localURL)
        } catch is CancellationError {
            guard request == previewLoadRequest else { return }
            if previewLoadState.isLoading {
                previewLoadState = .idle
            }
        } catch {
            guard request == previewLoadRequest, !Task.isCancelled else { return }
            let diagnostic = recordDiagnostic(
                context: .preview,
                message: error.localizedDescription,
                details: [
                    SupportDiagnosticDetail(label: "Filename", value: selectedPreview.filename),
                    SupportDiagnosticDetail(label: "Source URL", value: selectedPreview.url.absoluteString)
                ]
            )
            previewLoadState = .failed(
                PreviewFailureState(
                    diagnostic: diagnostic,
                    suggestsRedownload: false
                )
            )
        }
    }

    func handleMissingPreviewFile(_ localURL: URL) {
        let filename = selectedPreview?.filename ?? localURL.lastPathComponent
        let diagnostic = recordDiagnostic(
            context: .preview,
            message: "预览文件已丢失，请重新加载预览。",
            details: [
                SupportDiagnosticDetail(label: "Filename", value: filename),
                SupportDiagnosticDetail(label: "Cached File", value: localURL.path)
            ]
        )
        previewLoadState = .failed(
            PreviewFailureState(
                diagnostic: diagnostic,
                suggestsRedownload: false
            )
        )
        errorMessage = nil
    }

    func validateLoadedPreviewFile(_ localURL: URL, file: PaperFile) -> Bool {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            handleMissingPreviewFile(localURL)
            return false
        }
        guard PDFDocument(url: localURL) != nil else {
            handleUnreadablePreviewFile(localURL, file: file)
            return false
        }
        return true
    }

    func handleUnreadablePreviewFile(_ localURL: URL, file: PaperFile) {
        var details = [
            SupportDiagnosticDetail(label: "Filename", value: file.filename),
            SupportDiagnosticDetail(label: "Local File", value: localURL.path),
            SupportDiagnosticDetail(label: "Source URL", value: file.url.absoluteString)
        ]
        let message: String

        do {
            if try backend.discardManagedPreviewCacheFile(at: localURL) {
                message = "预览缓存已损坏，请重试预览。"
                details.append(
                    SupportDiagnosticDetail(label: "Recovery", value: "已移除损坏的预览缓存文件。")
                )
            } else {
                message = "预览文件无法打开，请重新下载或在浏览器中打开。"
            }
        } catch {
            message = "预览缓存已损坏，请重试预览。"
            details.append(
                SupportDiagnosticDetail(label: "Cache Cleanup", value: error.localizedDescription)
            )
        }

        let diagnostic = recordDiagnostic(
            context: .preview,
            message: message,
            details: details
        )
        previewLoadState = .failed(
            PreviewFailureState(
                diagnostic: diagnostic,
                suggestsRedownload: message == "预览文件无法打开，请重新下载或在浏览器中打开。"
            )
        )
        errorMessage = nil
    }

    func copyDiagnostic(_ diagnostic: SupportDiagnostic) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic.reportText, forType: .string)
    }

    func usableSaveDirectoryURL() -> URL? {
        switch saveDirectoryAvailability() {
        case let .ready(url), let .creatable(url):
            return url
        case .unavailable:
            return nil
        }
    }

    private func saveDirectoryAvailability() -> SaveDirectoryAvailability {
        let expandedPath = (settings.saveDirectory as NSString).expandingTildeInPath
        guard !expandedPath.isEmpty else {
            return .unavailable("尚未设置下载文件夹。")
        }

        let directoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                return .unavailable("保存路径指向文件而不是文件夹。")
            }
            guard FileManager.default.isReadableFile(atPath: directoryURL.path) else {
                return .unavailable("下载文件夹当前不可读。")
            }
            guard FileManager.default.isWritableFile(atPath: directoryURL.path) else {
                return .unavailable("下载文件夹当前不可写。")
            }
            return .ready(directoryURL)
        }

        var ancestorURL = directoryURL.deletingLastPathComponent()
        while true {
            if FileManager.default.fileExists(atPath: ancestorURL.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    return .unavailable("下载文件夹的上级路径不是文件夹。")
                }
                guard FileManager.default.isReadableFile(atPath: ancestorURL.path) else {
                    return .unavailable("下载文件夹的上级目录当前不可读。")
                }
                guard FileManager.default.isWritableFile(atPath: ancestorURL.path) else {
                    return .unavailable("下载文件夹的上级目录当前不可写，无法创建下载文件夹。")
                }
                return .creatable(directoryURL)
            }

            let parentURL = ancestorURL.deletingLastPathComponent()
            guard parentURL.path != ancestorURL.path else {
                return .unavailable("下载文件夹的上级目录不存在。")
            }
            ancestorURL = parentURL
        }
    }

    private func presentSaveDirectoryUnavailableNotice(reason: String) {
        let diagnostic = recordDiagnostic(
            context: .saveDirectory,
            message: "下载文件夹当前不可用，请先在设置中选择有效的保存目录。",
            details: [
                SupportDiagnosticDetail(label: "Save Directory", value: settings.saveDirectory),
                SupportDiagnosticDetail(label: "Reason", value: reason)
            ]
        )
        saveDirectoryNotice = SaveDirectoryNotice(
            diagnostic: diagnostic,
            action: .openSettings
        )
        errorMessage = nil
    }

    func revealSaveDirectory() {
        switch saveDirectoryAvailability() {
        case let .ready(directoryURL):
            saveDirectoryNotice = nil
            errorMessage = nil
            NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        case let .creatable(directoryURL):
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                saveDirectoryNotice = nil
                errorMessage = nil
                NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
            } catch {
                presentSaveDirectoryUnavailableNotice(reason: error.localizedDescription)
            }
        case let .unavailable(reason):
            presentSaveDirectoryUnavailableNotice(reason: reason)
        }
    }

    func dismissSaveDirectoryNotice() {
        saveDirectoryNotice = nil
    }

    func dismissSupportDirectoryNotice() {
        supportDirectoryNotice = nil
    }

    func performSaveDirectoryNoticeAction() {
        switch saveDirectoryNotice?.action {
        case .openSettings:
            isSettingsPresented = true
        case nil:
            break
        }
    }

    private func presentSupportDirectoryNotice(reason: String) {
        let diagnostic = recordDiagnostic(
            context: .supportDirectory,
            message: "支持文件夹无法打开，请检查应用支持目录权限。",
            details: [
                SupportDiagnosticDetail(label: "Support Directory", value: backend.supportDirectoryPath),
                SupportDiagnosticDetail(label: "Reason", value: reason)
            ]
        )
        supportDirectoryNotice = SupportDirectoryNotice(diagnostic: diagnostic)
        errorMessage = nil
    }

    func revealSupportDirectory() {
        let url = URL(fileURLWithPath: backend.supportDirectoryPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            presentSupportDirectoryNotice(reason: error.localizedDescription)
            return
        }
        supportDirectoryNotice = nil
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    func openDownloadedUpdateFile() -> Bool {
        guard let url = updateStatus.downloadedURL else {
            return false
        }
        return openDownloadedFile(url)
    }

    func handleBackendError(
        _ error: Error,
        context: SupportDiagnosticContext = .general,
        details: [SupportDiagnosticDetail] = []
    ) {
        presentDiagnosticError(error.localizedDescription, context: context, details: details)
    }

    @discardableResult
    func presentDiagnosticError(
        _ message: String,
        context: SupportDiagnosticContext = .general,
        details: [SupportDiagnosticDetail] = []
    ) -> SupportDiagnostic {
        let diagnostic = recordDiagnostic(
            context: context,
            message: message,
            details: details
        )
        errorMessage = diagnostic.message
        return diagnostic
    }
}
