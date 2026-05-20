import Foundation
import Observation
import SwiftUI

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
    var batchPreview: [PaperFile] = []
    var batchGroups: [BackendPaperGroup] = []
    var downloads: [DownloadTaskItem] = []
    var selectedPreview: PaperFile?
    var settings = DownloadSettings()
    var downloadSnapshot = DownloadStatusSnapshot(phase: "idle", done: 0, total: 0, success: 0, message: "Ready", failed: nil, cancelled: nil, skipped: nil)
    var isLoading = false
    var isSettingsPresented = false
    var errorMessage: String?

    @ObservationIgnored let bridge = PythonBridge()
    @ObservationIgnored var pollTask: Task<Void, Never>?

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

    func bootstrap() async {
        await loadSettings()
        await loadSubjects()
        await loadFavorites()
        await refreshDownloads()
    }

    func clearError() {
        errorMessage = nil
    }

    func selectFavorite(_ subject: Subject) {
        selectedSubject = subject
        route = .search
    }

    func loadSubjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await bridge.send(method: "get_subjects", params: EmptyParams(), payloadType: [Subject].self)
            subjects = payload.sorted { $0.code < $1.code }
            if let preferred = subjects.first(where: { $0.code == settings.lastSubject }) {
                selectedSubject = preferred
            } else if selectedSubject == nil {
                selectedSubject = subjects.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFavorites() async {
        do {
            favorites = try await bridge.send(method: "get_favorites", params: EmptyParams(), payloadType: [Subject].self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSettings() async {
        do {
            let loaded = try await bridge.send(method: "load_settings", params: EmptyParams(), payloadType: DownloadSettings.self)
            settings = loaded
            if let savedRoute = AppRoute(rawValue: loaded.lastMode) {
                route = savedRoute
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSettings() async {
        settings.lastSubject = selectedSubject?.code ?? ""
        settings.lastMode = route.rawValue

        do {
            let proxyResult = try await bridge.send(method: "set_proxy", params: ProxyParams(proxyURL: settings.proxyURL), payloadType: OKResult.self)
            guard proxyResult.ok else {
                throw PythonBridgeError.backend(proxyResult.error ?? "Unable to save proxy")
            }

            let saveResult = try await bridge.send(method: "save_settings", params: settings, payloadType: OKResult.self)
            guard saveResult.ok else {
                throw PythonBridgeError.backend(saveResult.error ?? "Unable to save settings")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseSaveDirectory() async {
        do {
            let path = try await bridge.send(method: "choose_directory", params: EmptyParams(), payloadType: String.self)
            if !path.isEmpty {
                settings.saveDirectory = path
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testProxy() async -> String {
        do {
            let result = try await bridge.send(method: "test_proxy", params: ProxyParams(proxyURL: settings.proxyURL), payloadType: ProxyResult.self)
            if result.ok, let latency = result.latencyMs {
                return "连接成功 (\(latency) ms)"
            }
            return result.error ?? "代理测试失败"
        } catch {
            return error.localizedDescription
        }
    }

    func search() async {
        guard let selectedSubject else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let params = SearchParams(subject: selectedSubject.code, year: selectedYear, season: selectedSeason.rawValue)
            let payload = try await bridge.send(method: "search", params: params, payloadType: SearchPayload.self)
            withAnimation(CPDesign.Motion.standard) {
                searchResults = payload.files
                selectedPreview = payload.files.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewBatch() async {
        guard let selectedSubject else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let params = BatchPreviewParams(
                code: selectedSubject.code,
                yearFrom: batchYearFrom,
                yearTo: batchYearTo,
                seasons: batchSeasonList.map(\.rawValue),
                paperGroups: batchPaperGroups.sorted()
            )
            let payload = try await bridge.send(method: "batch_preview", params: params, payloadType: BatchPreviewPayload.self)
            withAnimation(CPDesign.Motion.standard) {
                batchGroups = payload.groups
                batchPreview = payload.files
                selectedPreview = payload.files.first
            }
            if let warning = payload.warnings.first {
                errorMessage = warning
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startBatchDownload() async {
        guard !batchGroups.isEmpty else { return }

        do {
            let params = DownloadStartParams(
                groups: batchGroups,
                saveDir: settings.saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await bridge.send(method: "start_download", params: params, payloadType: DownloadStartResult.self)
            guard result.ok else {
                throw PythonBridgeError.backend("下载任务启动失败")
            }
            route = .downloads
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshDownloads() async {
        do {
            let snapshot = try await bridge.send(method: "get_status", params: EmptyParams(), payloadType: DownloadStatusSnapshot.self)
            let items = try await bridge.send(method: "get_download_list", params: EmptyParams(), payloadType: [DownloadTaskItem].self)
            downloadSnapshot = snapshot
            downloads = items.sorted { $0.id < $1.id }
            if snapshot.isRunning {
                startPollingDownloads()
            } else {
                stopPollingDownloads()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelDownloads() async {
        do {
            let result = try await bridge.send(method: "cancel_download", params: EmptyParams(), payloadType: OKResult.self)
            guard result.ok else {
                throw PythonBridgeError.backend(result.error ?? "取消下载失败")
            }
            await refreshDownloads()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func stopPollingDownloads() {
        pollTask?.cancel()
        pollTask = nil
    }
}
