import Foundation

enum UpdateCheckSource {
    case startup
    case manual
}

struct AppUpdateRelease: Identifiable, Hashable, Codable, Sendable {
    let version: String
    let tagName: String
    let name: String
    let htmlURL: URL
    let assetName: String
    let downloadURL: URL

    var id: String { tagName }
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(current: String, latest: String)
    case available(AppUpdateRelease)
}

struct UpdateDownloadState: Equatable, Sendable {
    let release: AppUpdateRelease
    let progress: Double?
    let destinationURL: URL
}

enum DownloadedUpdateOrigin: Equatable, Sendable {
    case currentSession
    case restoredArtifact

    var badgeTitle: String {
        switch self {
        case .currentSession:
            return "本次下载"
        case .restoredArtifact:
            return "已恢复本地更新"
        }
    }
}

enum UpdateInstallState: Equatable, Sendable {
    case downloaded
    case requiresManualOpen
    case missingFile
    case invalidFile

    var message: String {
        switch self {
        case .downloaded:
            return "更新 DMG 已下载"
        case .requiresManualOpen:
            return "更新 DMG 已下载，等待手动打开"
        case .missingFile:
            return "更新文件丢失，请重新下载"
        case .invalidFile:
            return "更新文件不可用，请重新下载"
        }
    }

    var recoveryAction: UpdateNoticeAction? {
        switch self {
        case .downloaded:
            return nil
        case .requiresManualOpen:
            return .openDownloadedDMG
        case .missingFile, .invalidFile:
            return .retryDownload
        }
    }
}

struct DownloadedUpdateState: Equatable, Sendable {
    let release: AppUpdateRelease
    let fileURL: URL
    let installState: UpdateInstallState
    let origin: DownloadedUpdateOrigin

    init(
        release: AppUpdateRelease,
        fileURL: URL,
        installState: UpdateInstallState,
        origin: DownloadedUpdateOrigin = .currentSession
    ) {
        self.release = release
        self.fileURL = fileURL
        self.installState = installState
        self.origin = origin
    }

    var message: String {
        switch (origin, installState) {
        case (.restoredArtifact, .downloaded):
            return "已恢复本地更新 DMG"
        case (.restoredArtifact, .requiresManualOpen):
            return "已恢复本地更新 DMG，等待手动打开"
        case (_, .downloaded), (_, .requiresManualOpen), (_, .missingFile), (_, .invalidFile):
            return installState.message
        }
    }

    var persistentSummary: String {
        switch (origin, installState) {
        case (.restoredArtifact, .downloaded):
            return "当前更新包来自之前已下载的本地 DMG，不是本次会话刚下载的文件。"
        case (.restoredArtifact, .requiresManualOpen):
            return "当前更新包来自之前已下载的本地 DMG，不是本次会话刚下载的文件，可直接手动打开安装。"
        case (.currentSession, .downloaded):
            return "当前更新包已在本次会话下载完成。"
        case (.currentSession, .requiresManualOpen):
            return "当前更新包已在本次会话下载完成，但自动打开失败，需要手动打开安装。"
        case (_, .missingFile):
            return "之前记录的更新 DMG 当前不存在，不能继续安装，需要重新下载。"
        case (_, .invalidFile):
            return "之前记录的更新 DMG 当前不可用，不能继续安装，需要重新下载。"
        }
    }
}

enum UpdateFailurePhase: Equatable, Sendable {
    case check
    case download
}

struct UpdateFailureState: Equatable, Sendable {
    let phase: UpdateFailurePhase
    let message: String
    let release: AppUpdateRelease?
    let destinationURL: URL?

    init(
        phase: UpdateFailurePhase,
        message: String,
        release: AppUpdateRelease? = nil,
        destinationURL: URL? = nil
    ) {
        self.phase = phase
        self.message = message
        self.release = release
        self.destinationURL = destinationURL
    }

    var recoveryAction: UpdateNoticeAction {
        switch phase {
        case .check:
            return .retryCheck
        case .download:
            return .retryDownload
        }
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(current: String, latest: String)
    case available(AppUpdateRelease)
    case downloading(UpdateDownloadState)
    case downloaded(DownloadedUpdateState)
    case failed(UpdateFailureState)

    var message: String {
        switch self {
        case .idle:
            return "尚未检查更新"
        case .checking:
            return "正在检查 GitHub 最新版本"
        case let .upToDate(current, _):
            return "当前已是最新版 \(current)"
        case let .available(release):
            return "发现新版本 \(release.version)"
        case let .downloading(state):
            let progress = state.progress
            if let progress {
                return "正在下载更新 \(Int(progress * 100))%"
            }
            return "正在下载更新"
        case let .downloaded(state):
            return state.message
        case let .failed(failure):
            return failure.message
        }
    }

    var downloadedURL: URL? {
        if case let .downloaded(state) = self {
            return state.fileURL
        }
        return nil
    }

    var destinationURL: URL? {
        switch self {
        case let .downloading(state):
            return state.destinationURL
        case let .downloaded(state):
            return state.fileURL
        case let .failed(failure):
            return failure.destinationURL
        default:
            return nil
        }
    }

    var availableRelease: AppUpdateRelease? {
        switch self {
        case let .available(release):
            return release
        case let .downloading(state):
            return state.release
        case let .downloaded(state):
            return state.release
        case let .failed(failure):
            return failure.release
        default:
            return nil
        }
    }

    var recoveryAction: UpdateNoticeAction? {
        switch self {
        case let .downloaded(state):
            return state.installState.recoveryAction
        case let .failed(failure):
            return failure.recoveryAction
        default:
            return nil
        }
    }

    var canAccessDownloadedFile: Bool {
        guard case let .downloaded(state) = self else {
            return false
        }
        switch state.installState {
        case .downloaded, .requiresManualOpen:
            return true
        case .missingFile, .invalidFile:
            return false
        }
    }
}
