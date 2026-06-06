import AppKit
import Foundation

typealias PreviewTransferWriter = @Sendable (_ sourceURL: URL, _ destinationURL: URL, _ proxyURL: String) async throws -> Void

final class NativeBackendService: @unchecked Sendable {
    private let paths: AppStoragePaths
    private let settingsStore: SettingsStore
    private let favoritesStore: FavoritesStore
    private let historyStore: DownloadHistoryStore
    private let cacheStore: SearchCacheStore
    private let downloadManager: DownloadManager
    private let updateService: UpdateService
    private let previewTransfer: PreviewTransferWriter
    private let fileManager: FileManager

    init(
        paths: AppStoragePaths? = nil,
        downloadManager: DownloadManager? = nil,
        updateService: UpdateService? = nil,
        previewTransfer: @escaping PreviewTransferWriter = NativeBackendService.defaultPreviewTransfer,
        fileManager: FileManager = .default
    ) throws {
        let resolvedPaths = try paths ?? AppStoragePaths()
        self.paths = resolvedPaths
        self.fileManager = fileManager
        self.settingsStore = SettingsStore(paths: resolvedPaths)
        self.favoritesStore = FavoritesStore(paths: resolvedPaths)
        let historyStore = DownloadHistoryStore(paths: resolvedPaths)
        self.historyStore = historyStore
        self.cacheStore = SearchCacheStore(paths: resolvedPaths)
        self.previewTransfer = previewTransfer
        let historyRecorder = DownloadHistoryRecorder(store: historyStore)
        self.downloadManager = downloadManager ?? DownloadManager(completionRecorder: { task in
            await historyRecorder.record(task)
        })
        self.updateService = updateService ?? UpdateService()
        try LegacyCacheMigrator(paths: resolvedPaths).migrateIfNeeded()
    }

    var appSupportPath: String {
        paths.appSupportDirectory.path
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
        let registry = registry(proxyURL: settings.proxyURL)
        let mode = registryMode(for: settings.sourceMode)

        for year in yearFrom...yearTo {
            for season in seasons {
                do {
                    let query = PaperSourceQuery(subjectCode: subject.code, year: year, season: season.rawValue)
                    let result = try await registry.search(query, mode: mode)
                    allGroups.append(contentsOf: result.groups.filter { paperGroups.contains($0.paperGroup ?? 0) })
                    warnings.append(contentsOf: self.warnings(from: result.attempts))
                } catch {
                    warnings.append("\(year)/\(season.rawValue): \(error.localizedDescription)")
                }
            }
        }

        return BatchPreviewPayload(groups: allGroups, warnings: warnings)
    }

    @MainActor
    func chooseDirectory() async -> String {
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

    func cancelDownloads() async {
        await downloadManager.cancel()
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

    func previewURL(for file: PaperFile, settings: DownloadSettings) async throws -> URL {
        if let localDownloadedFileURL = localDownloadedFileURL(for: file, saveDirectory: settings.saveDirectory) {
            return localDownloadedFileURL
        }

        let cacheURL = previewCacheURL(for: file)
        if fileManager.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let sourceURL = try DownloadSourceURLResolver.resolvedSourceURL(for: file)
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await previewTransfer(sourceURL, cacheURL, settings.proxyURL)
        return cacheURL
    }

    private func registry(proxyURL: String) -> SourceRegistry {
        let client = NetworkClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        return SourceRegistry(sources: [
            FrankcieSource(networkClient: client),
            EasyPaperSource(networkClient: client),
            PastPapersSource(networkClient: client),
            PapaCambridgeSource(networkClient: client)
        ])
    }

    private func registryMode(for sourceMode: PaperSourceID) -> SourceRegistryMode {
        sourceMode == .automatic ? .automatic : .manual(sourceMode)
    }

    private func warnings(from attempts: [SourceAttempt]) -> [String] {
        attempts
            .filter { $0.status != .success }
            .map { "\($0.sourceID.title): \($0.message)" }
    }

    private func localDownloadedFileURL(for file: PaperFile, saveDirectory: String) -> URL? {
        let expandedPath = (saveDirectory as NSString).expandingTildeInPath

        let mergedURL = URL(fileURLWithPath: expandedPath).appendingPathComponent(file.filename)
        if fileManager.fileExists(atPath: mergedURL.path) {
            return mergedURL
        }

        if let year = file.year.map(String.init), let type = file.paperType?.uppercased() {
            let subfolder = (type == "QP" || type == "MS") ? type : ""
            let splitURL = URL(fileURLWithPath: expandedPath)
                .appendingPathComponent(year)
                .appendingPathComponent(subfolder)
                .appendingPathComponent(file.filename)
            if fileManager.fileExists(atPath: splitURL.path) {
                return splitURL
            }
        }

        return nil
    }

    private func previewCacheURL(for file: PaperFile) -> URL {
        paths.cacheDirectory
            .appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent(file.filename)
    }

    private static func defaultPreviewTransfer(sourceURL: URL, destinationURL: URL, proxyURL: String) async throws {
        let client = HTTPFileTransferClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        try await client.transfer(from: sourceURL, to: destinationURL) { _ in }
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
