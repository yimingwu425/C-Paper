import Foundation
import Observation

enum BackendConnectionState: Equatable {
    case checking
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .checking: "正在初始化原生后端"
        case .connected: "原生后端已就绪"
        case .failed: "原生后端不可用"
        }
    }

    var detail: String {
        switch self {
        case .checking: "正在启动本地后端"
        case .connected: "本地后端可用"
        case .failed(let message): message
        }
    }

    var isAvailable: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

@MainActor
@Observable
final class AppModel {
    var route: AppRoute = .search
    var subjects: [Subject] = []
    var favorites: [Subject] = []
    var selectedSubject: Subject?
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedSeason: Season = .nov
    var batchYearFrom: Int = max(2000, Calendar.current.component(.year, from: Date()) - 2)
    var batchYearTo: Int = Calendar.current.component(.year, from: Date())
    var batchSeasons: Set<Season> = Set(Season.allCases)
    var batchPaperGroups: Set<Int> = [1, 2, 3, 4, 5, 6]
    var searchResults: [PaperFile] = []
    var searchGroups: [NativePaperGroup] = []
    var batchPreview: [PaperFile] = []
    var batchGroups: [NativePaperGroup] = []
    var downloads: [DownloadTaskItem] = []
    var selectedPreview: PaperFile?
    var expandedPaperComponents: Set<String> = []
    var settings = DownloadSettings()
    var downloadSnapshot = DownloadStatusSnapshot(phase: "idle", done: 0, total: 0, success: 0, message: "Ready", failed: nil, cancelled: nil, skipped: nil)
    var backendState: BackendConnectionState = .checking
    var isLoading = false
    var isSettingsPresented = false
    var errorMessage: String?

    @ObservationIgnored let backend: NativeBackendService
    @ObservationIgnored var pollTask: Task<Void, Never>?

    init(backend: NativeBackendService? = nil) {
        if let backend {
            self.backend = backend
        } else {
            self.backend = try! NativeBackendService()
        }
    }

    var completedDownloadCount: Int {
        downloads.filter { $0.status == .done || $0.status == .skipped }.count
    }

    var failedDownloadCount: Int {
        downloads.filter { $0.status == .failed }.count
    }

    var activeDownloadCount: Int {
        downloads.filter { $0.status == .pending || $0.status == .downloading }.count
    }

    var batchSeasonList: [Season] {
        Season.allCases.filter { batchSeasons.contains($0) }
    }

    var isSelectedSubjectFavorite: Bool {
        guard let selectedSubject else { return false }
        return favorites.contains { $0.code == selectedSubject.code }
    }

    var backendRuntimePath: String {
        backend.appSupportPath
    }

    func bootstrap() async {
        backendState = .checking
        await loadSettings()
        await loadSubjects()
        await loadFavorites()
        await refreshDownloads()
    }

    func clearError() {
        errorMessage = nil
    }

    func selectFavorite(_ subject: Subject) {
        selectedSubject = subjects.first { $0.code == subject.code } ?? subject
        route = .search
    }

    func addSelectedSubjectToFavorites() async {
        guard let selectedSubject, !isSelectedSubjectFavorite else { return }

        do {
            try backend.addFavorite(selectedSubject)
            await loadFavorites()
        } catch {
            handleBackendError(error)
        }
    }

    func removeFavorite(_ subject: Subject) async {
        do {
            try backend.removeFavorite(code: subject.code)
            await loadFavorites()
        } catch {
            handleBackendError(error)
        }
    }

    func loadSubjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.loadSubjects(proxyURL: settings.proxyURL)
            markBackendConnected()
            subjects = payload.sorted { $0.code < $1.code }
            if let preferred = subjects.first(where: { $0.code == settings.lastSubject }) {
                selectedSubject = preferred
            } else if selectedSubject == nil {
                selectedSubject = subjects.first
            }
        } catch {
            handleBackendError(error)
        }
    }

    func loadFavorites() async {
        favorites = backend.loadFavorites()
        markBackendConnected()
    }

    func loadSettings() async {
        let loaded = backend.loadSettings()
        markBackendConnected()
        settings = loaded
        if let savedRoute = AppRoute(rawValue: loaded.lastMode) {
            route = savedRoute
        }
    }

    func saveSettings() async {
        settings.lastSubject = selectedSubject?.code ?? ""
        settings.lastMode = route.rawValue

        do {
            try backend.saveSettings(settings)
            markBackendConnected()
        } catch {
            handleBackendError(error)
        }
    }

    func chooseSaveDirectory() async {
        let path = await backend.chooseDirectory()
        if !path.isEmpty {
            settings.saveDirectory = path
        }
        markBackendConnected()
    }

    func testProxy() async -> String {
        let result = await backend.testProxy(settings.proxyURL)
        markBackendConnected()
        if result.ok, let latency = result.latencyMs {
            return "连接成功 (\(latency) ms)"
        }
        return result.error ?? "代理测试失败"
    }

    func search() async {
        guard let selectedSubject else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.search(subject: selectedSubject, year: selectedYear, season: selectedSeason, settings: settings)
            markBackendConnected()
            searchResults = payload.files
            searchGroups = payload.groups
            expandedPaperComponents = Set(payload.files.compactMap { $0.componentKey }.prefix(3))
            selectedPreview = nil
        } catch {
            handleBackendError(error)
        }
    }

    func previewBatch() async {
        guard let selectedSubject else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.batchPreview(
                subject: selectedSubject,
                yearFrom: batchYearFrom,
                yearTo: batchYearTo,
                seasons: batchSeasonList,
                paperGroups: batchPaperGroups,
                settings: settings
            )
            markBackendConnected()
            batchGroups = payload.groups
            batchPreview = payload.files
            selectedPreview = nil
            if let warning = payload.warnings.first {
                errorMessage = warning
            }
        } catch {
            handleBackendError(error)
        }
    }

    func startSearchDownload() async {
        guard !searchGroups.isEmpty else { return }

        do {
            let chosenDirectory = await backend.chooseDirectory()
            guard !chosenDirectory.isEmpty else {
                return
            }
            settings.saveDirectory = chosenDirectory

            let params = DownloadStartParams(
                groups: searchGroups,
                saveDir: settings.saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await backend.startDownload(groups: params.groups, saveDirectory: params.saveDir, options: params.options)
            guard result.ok else {
                throw BackendError.invalidResponse("下载任务启动失败")
            }
            markBackendConnected()
            route = .downloads
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            handleBackendError(error)
        }
    }

    func startSingleFileDownload(_ file: PaperFile) async {
        do {
            guard let saveDirectory = try await resolvedSaveDirectory() else {
                return
            }

            let params = DownloadStartParams(
                groups: [backendGroup(for: file)],
                saveDir: saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await backend.startDownload(groups: params.groups, saveDirectory: params.saveDir, options: params.options)
            guard result.ok else {
                throw BackendError.invalidResponse("下载任务启动失败")
            }
            markBackendConnected()
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            handleBackendError(error)
        }
    }

    func startBatchDownload() async {
        guard !batchGroups.isEmpty else { return }

        do {
            let chosenDirectory = await backend.chooseDirectory()
            guard !chosenDirectory.isEmpty else {
                return
            }
            settings.saveDirectory = chosenDirectory

            let params = DownloadStartParams(
                groups: batchGroups,
                saveDir: settings.saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await backend.startDownload(groups: params.groups, saveDirectory: params.saveDir, options: params.options)
            guard result.ok else {
                throw BackendError.invalidResponse("下载任务启动失败")
            }
            markBackendConnected()
            route = .downloads
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            handleBackendError(error)
        }
    }

    func refreshDownloads() async {
        let snapshot = await backend.downloadStatus()
        let items = await backend.downloadItems()
        markBackendConnected()
        downloadSnapshot = snapshot
        downloads = items.sorted { $0.id < $1.id }
        if snapshot.isRunning {
            ensureDownloadPolling()
        } else {
            stopPollingDownloads()
        }
    }

    func cancelDownloads() async {
        await backend.cancelDownloads()
        markBackendConnected()
        await refreshDownloads()
    }

    func startPollingDownloads() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshDownloads()
                if !downloadSnapshot.isRunning {
                    break
                }
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
        }
    }

    func ensureDownloadPolling() {
        guard pollTask == nil else { return }
        startPollingDownloads()
    }

    func stopPollingDownloads() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func markBackendConnected() {
        if backendState != .connected {
            backendState = .connected
        }
    }

    private func resolvedSaveDirectory() async throws -> String? {
        let expandedPath = (settings.saveDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if !expandedPath.isEmpty,
           FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return settings.saveDirectory
        }

        let chosenDirectory = await backend.chooseDirectory()
        guard !chosenDirectory.isEmpty else {
            return nil
        }
        settings.saveDirectory = chosenDirectory
        await saveSettings()
        return chosenDirectory
    }

    private func backendGroup(for file: PaperFile) -> NativePaperGroup {
        let type = file.paperType?.uppercased()
        let sy = syCode(season: file.season, year: file.year)
        let component = PaperComponent(
            sourceID: file.sourceID,
            filename: file.filename,
            url: file.url,
            paperType: file.paperType?.lowercased() ?? "",
            subjectCode: file.subjectCode,
            sy: sy,
            number: file.number,
            label: file.label
        )

        if type == "QP" {
            return NativePaperGroup(
                sourceID: file.sourceID,
                subjectCode: file.subjectCode,
                sy: sy,
                number: file.number,
                paperGroup: nil,
                qp: component,
                ms: nil,
                extras: []
            )
        }

        if type == "MS" {
            return NativePaperGroup(
                sourceID: file.sourceID,
                subjectCode: file.subjectCode,
                sy: sy,
                number: file.number,
                paperGroup: nil,
                qp: nil,
                ms: component,
                extras: []
            )
        }

        return NativePaperGroup(
            sourceID: file.sourceID,
            subjectCode: file.subjectCode,
            sy: sy,
            number: file.number,
            paperGroup: nil,
            qp: nil,
            ms: nil,
            extras: [component]
        )
    }

    private func syCode(season: String?, year: Int?) -> String? {
        guard let season, let year else { return nil }
        let prefix: String
        switch season {
        case "Mar":
            prefix = "m"
        case "Jun":
            prefix = "s"
        case "Nov":
            prefix = "w"
        default:
            prefix = "w"
        }
        let shortYear = String(year % 100)
        return "\(prefix)\(shortYear.count == 1 ? "0\(shortYear)" : shortYear)"
    }

    private func handleBackendError(_ error: Error) {
        let message = error.localizedDescription
        if !backendState.isAvailable {
            backendState = .failed(message)
        }
        errorMessage = message
    }
}
