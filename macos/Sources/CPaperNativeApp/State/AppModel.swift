import AppKit
import Foundation
import Observation

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
    var batchPreview: [PaperFile] = []
    var batchGroups: [NativePaperGroup] = []
    var downloads: [DownloadTaskItem] = []
    var selectedPreview: PaperFile?
    var expandedPaperComponents: Set<String> = []
    var settings = DownloadSettings()
    var downloadSnapshot = DownloadStatusSnapshot(phase: "idle", done: 0, total: 0, success: 0, message: "Ready", failed: nil, cancelled: nil, skipped: nil)
    var updateStatus: UpdateStatus = .idle
    var pendingUpdatePrompt: AppUpdateRelease?
    var didRunStartupUpdateCheck = false
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
        guard let activeSubject else { return false }
        return favorites.contains { $0.code == activeSubject.code }
    }

    var backendRuntimePath: String {
        backend.appSupportPath
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

    func clearError() {
        errorMessage = nil
    }

    func handleBackendError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
