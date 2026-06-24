import AppKit
import Foundation

final class NativeBackendService: @unchecked Sendable {
    typealias SourceRegistryBuilder = @Sendable (String) -> SourceRegistry
    typealias DirectoryChooser = @MainActor @Sendable () async -> String

    private let paths: AppStoragePaths
    private let fileManager: FileManager
    private let settingsStore: SettingsStore
    private let favoritesStore: FavoritesStore
    private let historyStore: DownloadHistoryStore
    private let sessionStore: DownloadSessionStore
    private let cacheStore: SearchCacheStore
    private let downloadManager: DownloadManager
    private let updateService: UpdateService
    private let previewService: PreviewFileService
    private let supportDiagnosticsStore: SupportDiagnosticsStore
    private let sourceRegistryBuilder: SourceRegistryBuilder
    private let directoryChooser: DirectoryChooser

    init(
        paths: AppStoragePaths? = nil,
        downloadManager: DownloadManager? = nil,
        updateService: UpdateService? = nil,
        previewTransfer: @escaping PreviewFileService.TransferWriter = PreviewFileService.defaultTransfer,
        sourceRegistryBuilder: @escaping SourceRegistryBuilder = NativeBackendService.makeLiveRegistry,
        directoryChooser: @escaping DirectoryChooser = NativeBackendService.defaultChooseDirectory,
        fileManager: FileManager = .default
    ) throws {
        let resolvedPaths = try paths ?? AppStoragePaths()
        self.paths = resolvedPaths
        self.fileManager = fileManager
        self.settingsStore = SettingsStore(paths: resolvedPaths)
        self.favoritesStore = FavoritesStore(paths: resolvedPaths)
        let historyStore = DownloadHistoryStore(paths: resolvedPaths)
        self.historyStore = historyStore
        let sessionStore = DownloadSessionStore(paths: resolvedPaths, fileManager: fileManager)
        self.sessionStore = sessionStore
        self.cacheStore = SearchCacheStore(paths: resolvedPaths)
        self.previewService = PreviewFileService(
            paths: resolvedPaths,
            transfer: previewTransfer,
            fileSystem: StagedFileSystem(fileManager: fileManager)
        )
        self.supportDiagnosticsStore = SupportDiagnosticsStore(paths: resolvedPaths, fileManager: fileManager)
        self.sourceRegistryBuilder = sourceRegistryBuilder
        self.directoryChooser = directoryChooser
        let historyRecorder = DownloadHistoryRecorder(store: historyStore)
        self.downloadManager = downloadManager ?? DownloadManager(
            completionRecorder: { task in
                await historyRecorder.record(task)
            },
            sessionStore: sessionStore
        )
        self.updateService = updateService ?? UpdateService()
        try LegacyCacheMigrator(paths: resolvedPaths).migrateIfNeeded()
    }

    var appSupportPath: String {
        paths.appSupportDirectory.path
    }

    var supportDirectoryPath: String {
        supportDiagnosticsStore.directoryURL.path
    }

    func defaultSaveDirectory() -> String {
        "~/Downloads/C-Paper"
    }

    func loadSettings() -> DownloadSettings {
        var settings = settingsStore.load()
        if settings.saveDirectory.isEmpty {
            settings.saveDirectory = defaultSaveDirectory()
        }
        return settings
    }

    func saveSettings(_ settings: DownloadSettings) throws {
        try settingsStore.save(settings)
    }

    func loadFavorites() -> [Subject] {
        favoritesStore.load()
    }

    func addFavorite(_ subject: Subject) throws {
        try favoritesStore.add(subject)
    }

    func removeFavorite(code: String) throws {
        try favoritesStore.remove(code: code)
    }

    func loadSubjects(proxyURL: String, sourceMode: PaperSourceID = .automatic) async throws -> [Subject] {
        let cacheKey = "subjects"
        let cacheSource = sourceMode == .automatic ? PaperSourceID.automatic : sourceMode
        if let cached: [Subject] = cacheStore.load([Subject].self, source: cacheSource, key: cacheKey), !cached.isEmpty {
            return cached
        }

        let subjects = try await registry(proxyURL: proxyURL)
            .fetchSubjects(mode: registryMode(for: sourceMode))
        if !subjects.isEmpty {
            try? cacheStore.save(subjects, source: cacheSource, key: cacheKey)
        }
        return subjects
    }

    func search(subject: Subject, year: Int, season: Season, settings: DownloadSettings) async throws -> SearchPayload {
        let query = PaperSourceQuery(subjectCode: subject.code, year: year, season: season.rawValue)
        let result = try await registry(proxyURL: settings.proxyURL).search(query, mode: registryMode(for: settings.sourceMode))
        return SearchPayload(
            groups: result.groups,
            sourceID: result.sourceID,
            usedAutomaticFallback: usedAutomaticFallback(from: result.attempts),
            warnings: warnings(from: result.attempts)
        )
    }

    func batchPreview(
        subject: Subject,
        yearFrom: Int,
        yearTo: Int,
        seasons: [Season],
        paperGroups: Set<Int>,
        settings: DownloadSettings
    ) async throws -> BatchPreviewPayload {
        guard 1900 <= yearFrom, yearFrom <= yearTo, yearTo <= 2100 else {
            throw BackendError.invalidResponse("年份范围无效")
        }
        guard !seasons.isEmpty, !paperGroups.isEmpty else {
            throw BackendError.invalidResponse("请至少选择一个季度和 Paper 类型")
        }
        let queryCount = (yearTo - yearFrom + 1) * seasons.count
        guard queryCount <= 100 else {
            throw BackendError.invalidResponse("查询数量过多（\(queryCount)），请缩小年份范围")
        }

        var allGroups: [NativePaperGroup] = []
        var warnings: [String] = []
        var sourceIDs: [PaperSourceID] = []
        let registry = registry(proxyURL: settings.proxyURL)
        let mode = registryMode(for: settings.sourceMode)
        var succeededQueries = 0
        var automaticFallbackQueryCount = 0

        for year in yearFrom...yearTo {
            for season in seasons {
                do {
                    let query = PaperSourceQuery(subjectCode: subject.code, year: year, season: season.rawValue)
                    let result = try await registry.search(query, mode: mode)
                    succeededQueries += 1
                    if !sourceIDs.contains(result.sourceID) {
                        sourceIDs.append(result.sourceID)
                    }
                    if usedAutomaticFallback(from: result.attempts) {
                        automaticFallbackQueryCount += 1
                    }
                    allGroups.append(contentsOf: result.groups.filter { paperGroups.contains($0.paperGroup ?? 0) })
                    warnings.append(contentsOf: self.warnings(from: result.attempts))
                } catch {
                    warnings.append("\(year)/\(season.rawValue): \(error.localizedDescription)")
                }
            }
        }

        guard succeededQueries > 0 else {
            throw PaperSourceError.sourceUnavailable(batchPreviewFailureMessage(for: warnings))
        }

        return BatchPreviewPayload(
            groups: allGroups,
            sourceIDs: sourceIDs,
            successfulQueryCount: succeededQueries,
            automaticFallbackQueryCount: automaticFallbackQueryCount,
            warnings: warnings
        )
    }

    @MainActor
    func chooseDirectory() async -> String {
        await directoryChooser()
    }

    @MainActor
    private static func defaultChooseDirectory() async -> String {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        return panel.runModal() == .OK ? (panel.url?.path ?? "") : ""
    }

    func testProxy(_ proxyURL: String) async -> ProxyResult {
        let start = Date()
        do {
            _ = try await loadSubjects(proxyURL: proxyURL)
            return ProxyResult(ok: true, latencyMs: Int(Date().timeIntervalSince(start) * 1_000), error: nil)
        } catch {
            return ProxyResult(ok: false, latencyMs: nil, error: error.localizedDescription)
        }
    }

    func startDownload(
        groups: [NativePaperGroup],
        saveDirectory: String,
        options: DownloadOptions,
        proxyURL: String
    ) async throws -> DownloadStartResult {
        let url = URL(fileURLWithPath: (saveDirectory as NSString).expandingTildeInPath)
        let downloadedFilenames = Set(historyStore.load().map(\.filename))
        let result = try await downloadManager.start(
            groups: groups,
            saveDirectory: url,
            options: options,
            downloadedFilenames: downloadedFilenames,
            proxyURL: proxyURL
        )
        return result
    }

    func downloadStatus() async -> DownloadStatusSnapshot {
        await downloadManager.status()
    }

    func downloadItems() async -> [DownloadTaskItem] {
        await downloadManager.items()
    }

    func consumeDownloadRecoverySummary() async -> DownloadSessionRecoverySummary? {
        await downloadManager.consumeRecoverySummary()
    }

    func cancelDownloads() async {
        await downloadManager.cancel()
    }

    func retryRecoverableDownloads() async -> Bool {
        await downloadManager.retryRecoverableFailedItems()
    }

    func retryCompletedDownloadsNeedingRepair(ids: [Int]) async -> Bool {
        await downloadManager.retryCompletedItemsNeedingRepair(ids: ids)
    }

    func checkForUpdate(proxyURL: String) async throws -> AppUpdateCheckResult {
        try await updateService.checkForUpdate(proxyURL: proxyURL)
    }

    func downloadUpdate(
        _ release: AppUpdateRelease,
        proxyURL: String,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> URL {
        try await updateService.downloadUpdate(release, proxyURL: proxyURL, progress: progress)
    }

    func updateDestinationURL(for release: AppUpdateRelease) -> URL {
        updateService.destinationURL(for: release)
    }

    func previewURL(for file: PaperFile, settings: DownloadSettings) async throws -> URL {
        try await previewService.previewURL(for: file, settings: settings)
    }

    func discardManagedPreviewCacheFile(at url: URL) throws -> Bool {
        let standardizedURL = url.standardizedFileURL
        let previewCacheDirectoryURL = paths.cacheDirectory
            .appendingPathComponent("preview", isDirectory: true)
            .standardizedFileURL
        let previewCachePath = previewCacheDirectoryURL.path
        let candidatePath = standardizedURL.path
        guard candidatePath == previewCachePath || candidatePath.hasPrefix(previewCachePath + "/") else {
            return false
        }
        if fileManager.fileExists(atPath: standardizedURL.path) {
            try fileManager.removeItem(at: standardizedURL)
        }
        return true
    }

    func writeSupportDiagnostic(_ diagnostic: SupportDiagnostic) throws -> URL {
        try supportDiagnosticsStore.write(diagnostic)
    }

    private func registry(proxyURL: String) -> SourceRegistry {
        sourceRegistryBuilder(proxyURL)
    }

    private func registryMode(for sourceMode: PaperSourceID) -> SourceRegistryMode {
        sourceMode == .automatic ? .automatic : .manual(sourceMode)
    }

    private func warnings(from attempts: [SourceAttempt]) -> [String] {
        var warnings: [String] = []
        if let summary = sourceFallbackSummary(from: attempts) {
            warnings.append(summary)
        }
        warnings.append(contentsOf: attempts
            .filter { $0.status != .success }
            .map { "\($0.sourceID.title): \($0.diagnosticMessage)" }
        )
        return warnings
    }

    private func sourceFallbackSummary(from attempts: [SourceAttempt]) -> String? {
        guard
            attempts.count > 1,
            let successfulAttempt = attempts.last,
            successfulAttempt.status == .success
        else {
            return nil
        }

        let failedCount = attempts.dropLast().filter { $0.status != .success }.count
        guard failedCount > 0 else { return nil }

        if failedCount == 1 {
            return "首选来源响应过慢或不可用，已自动切换到 \(successfulAttempt.sourceID.title)，当前结果可继续使用。"
        }
        return "前 \(failedCount) 个来源响应过慢或不可用，已自动切换到 \(successfulAttempt.sourceID.title)，当前结果可继续使用。"
    }

    private func usedAutomaticFallback(from attempts: [SourceAttempt]) -> Bool {
        sourceFallbackSummary(from: attempts) != nil
    }

    private func batchPreviewFailureMessage(for warnings: [String]) -> String {
        guard let firstWarning = warnings.first, !firstWarning.isEmpty else {
            return "所选年份和季度均未能获取结果，请调整范围或稍后重试"
        }
        return "所选年份和季度均未能获取结果，请调整范围或稍后重试（例如：\(firstWarning)）"
    }

    private static func makeLiveRegistry(proxyURL: String) -> SourceRegistry {
        let client = NetworkClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        return SourceRegistry(sources: [
            FrankcieSource(networkClient: client),
            EasyPaperSource(networkClient: client),
            PastPapersSource(networkClient: client),
            PapaCambridgeSource(networkClient: client)
        ])
    }

}

private actor DownloadHistoryRecorder {
    private let store: DownloadHistoryStore

    init(store: DownloadHistoryStore) {
        self.store = store
    }

    func record(_ task: DownloadDestinationTask) {
        try? store.record(
            filename: task.filename,
            label: task.label,
            year: task.year,
            savePath: task.saveURL.path
        )
    }
}
