import Foundation

enum SourceNoticeLevel: Equatable, Sendable {
    case automaticFallback
    case warning
    case failure

    var title: String {
        switch self {
        case .automaticFallback:
            return "已自动切换到可用来源"
        case .warning:
            return "部分来源未完全返回结果"
        case .failure:
            return "当前检索未完成"
        }
    }
}

enum SourceNoticeAction: Equatable, Sendable {
    case retryLoadSubjects
    case retrySearch
    case retryBatchPreview

    var title: String {
        switch self {
        case .retryLoadSubjects:
            return "重新加载科目"
        case .retrySearch:
            return "重试搜索"
        case .retryBatchPreview:
            return "重试预览"
        }
    }
}

struct SourceNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let level: SourceNoticeLevel
    let action: SourceNoticeAction?

    var message: String {
        diagnostic.message
    }
}

struct DownloadNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let action: DownloadNoticeAction

    var message: String {
        diagnostic.message
    }
}

enum DownloadNoticeAction: Equatable, Sendable {
    case retrySearchDownload
    case retryBatchDownload
    case retrySingleFileDownload(file: PaperFile, origin: AppRoute)

    var title: String {
        "重试下载"
    }

    var route: AppRoute {
        switch self {
        case .retrySearchDownload:
            return .search
        case .retryBatchDownload:
            return .batch
        case let .retrySingleFileDownload(_, origin):
            return origin
        }
    }
}

struct SettingsNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic

    var message: String {
        diagnostic.message
    }
}

struct FavoriteNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let action: FavoriteNoticeAction

    var message: String {
        diagnostic.message
    }
}

enum FavoriteNoticeAction: Equatable, Sendable {
    case retryAdd(subject: Subject)
    case retryRemove(subject: Subject)

    var title: String {
        switch self {
        case .retryAdd:
            return "重试收藏"
        case .retryRemove:
            return "重试移除"
        }
    }
}

struct SaveDirectoryNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let action: SaveDirectoryNoticeAction

    var message: String {
        diagnostic.message
    }
}

struct SupportDirectoryNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic

    var message: String {
        diagnostic.message
    }
}

enum SaveDirectoryNoticeAction: Equatable, Sendable {
    case openSettings

    var title: String {
        switch self {
        case .openSettings:
            return "打开设置"
        }
    }
}

struct DownloadRecoveryNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let recoveredTaskCount: Int
    let cleanedPartialCount: Int

    var message: String {
        if cleanedPartialCount > 0 {
            return "检测到 \(recoveredTaskCount) 个上次中断的任务，已清理 \(cleanedPartialCount) 个残留临时文件。可直接重试失败项。"
        }
        return "检测到 \(recoveredTaskCount) 个上次中断的任务。可直接重试失败项。"
    }
}

struct DownloadIntegrityNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let missingFileCount: Int
    let invalidFileCount: Int
    let retryableTaskIDs: [Int]

    var message: String {
        if invalidFileCount == 0 && missingFileCount == 1 {
            return "发现 1 个已完成的下载文件已丢失。下载记录仍保留，但对应文件需要重新下载。"
        }
        if invalidFileCount == 0 {
            return "发现 \(missingFileCount) 个已完成的下载文件已丢失。下载记录仍保留，但对应文件需要重新下载。"
        }
        if missingFileCount == 0 && invalidFileCount == 1 {
            return "发现 1 个已完成的下载文件已不可用。下载记录仍保留，但对应文件需要重新下载或检查。"
        }
        if missingFileCount == 0 {
            return "发现 \(invalidFileCount) 个已完成的下载文件已不可用。下载记录仍保留，但对应文件需要重新下载或检查。"
        }
        return "发现 \(missingFileCount) 个已完成的下载文件已丢失，另有 \(invalidFileCount) 个已不可用。下载记录仍保留，但对应文件需要重新下载或检查。"
    }

    var retryActionTitle: String? {
        guard !retryableTaskIDs.isEmpty else { return nil }
        return "重新下载受影响文件"
    }
}

struct UpdateNotice: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let action: UpdateNoticeAction

    var message: String {
        diagnostic.message
    }
}

enum UpdateNoticeAction: Equatable, Sendable {
    case retryCheck
    case retryDownload
    case openDownloadedDMG

    var title: String {
        switch self {
        case .retryCheck:
            return "重新检查"
        case .retryDownload:
            return "重试下载"
        case .openDownloadedDMG:
            return "打开 DMG"
        }
    }
}

struct PreviewFailureState: Equatable, Sendable {
    let diagnostic: SupportDiagnostic
    let suggestsRedownload: Bool
}

enum PreviewLoadState: Equatable {
    case idle
    case loading
    case loaded(URL)
    case failed(PreviewFailureState)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var localURL: URL? {
        if case let .loaded(url) = self {
            return url
        }
        return nil
    }

    var failureDiagnostic: SupportDiagnostic? {
        if case let .failed(failure) = self {
            return failure.diagnostic
        }
        return nil
    }

    var failureState: PreviewFailureState? {
        if case let .failed(failure) = self {
            return failure
        }
        return nil
    }
}

struct SearchWorkflowPresentation: Equatable, Sendable {
    let showsSourceSummary: Bool
    let showsSourceNotice: Bool
    let showsDownloadNotice: Bool

    init(
        resultCount: Int,
        sourceSummary: String?,
        sourceID: PaperSourceID?,
        sourceNotice: SourceNotice?,
        downloadNotice: DownloadNotice?
    ) {
        showsSourceSummary = resultCount > 0 && sourceSummary != nil && sourceID != nil
        showsSourceNotice = sourceNotice != nil
        showsDownloadNotice = downloadNotice?.action.route == .search
    }
}

struct BatchPreviewWorkflowPresentation: Equatable, Sendable {
    let showsSourceSummary: Bool
    let showsSourceNotice: Bool
    let showsDownloadNotice: Bool

    init(
        previewCount: Int,
        sourceSummary: String?,
        sourceNotice: SourceNotice?,
        downloadNotice: DownloadNotice?
    ) {
        showsSourceSummary = previewCount > 0 && sourceSummary != nil
        showsSourceNotice = sourceNotice != nil
        showsDownloadNotice = downloadNotice?.action.route == .batch
    }
}

struct UpdateWorkflowPresentation: Equatable, Sendable {
    let canAccessDownloadedFile: Bool
    let revealActionTitle: String
    let primaryInstallActionTitle: String
    let prefersOpeningDownloadedFile: Bool

    init(status: UpdateStatus) {
        canAccessDownloadedFile = status.canAccessDownloadedFile
        revealActionTitle = canAccessDownloadedFile ? "显示文件" : "显示支持文件夹"
        primaryInstallActionTitle = canAccessDownloadedFile ? "打开已下载更新" : "下载更新"
        prefersOpeningDownloadedFile = canAccessDownloadedFile
    }
}

enum RootRefreshAction: Equatable, Sendable {
    case search
    case batchPreview
    case refreshDownloads
}

struct RootWorkflowPresentation: Equatable, Sendable {
    let showsUpdateNotice: Bool
    let showsSupportDirectoryNotice: Bool
    let updateNoticeTopPadding: Double
    let refreshAction: RootRefreshAction
    let disablesRefreshButton: Bool
    let showsErrorAlert: Bool
    let showsErrorAlertDiagnosticActions: Bool
    let showsPendingUpdatePrompt: Bool
    let pendingUpdatePromptPrimaryActionTitle: String
    let pendingUpdatePromptMessage: String?

    init(
        route: AppRoute,
        isLoading: Bool,
        updateNotice: UpdateNotice?,
        supportDirectoryNotice: SupportDirectoryNotice?,
        pendingUpdatePrompt: AppUpdateRelease?,
        errorMessage: String?,
        lastDiagnostic: SupportDiagnostic?,
        updateStatus: UpdateStatus,
        currentVersion: String
    ) {
        let updateWorkflowPresentation = UpdateWorkflowPresentation(status: updateStatus)
        showsUpdateNotice = updateNotice != nil
        showsSupportDirectoryNotice = supportDirectoryNotice != nil
        updateNoticeTopPadding = supportDirectoryNotice == nil ? 24 : 12
        disablesRefreshButton = isLoading
        showsErrorAlert = errorMessage != nil
        showsErrorAlertDiagnosticActions = lastDiagnostic != nil
        showsPendingUpdatePrompt = pendingUpdatePrompt != nil
        pendingUpdatePromptPrimaryActionTitle = updateWorkflowPresentation.primaryInstallActionTitle

        switch route {
        case .search:
            refreshAction = .search
        case .batch:
            refreshAction = .batchPreview
        case .downloads:
            refreshAction = .refreshDownloads
        }

        if let pendingUpdatePrompt {
            if updateWorkflowPresentation.prefersOpeningDownloadedFile {
                pendingUpdatePromptMessage = "当前版本 \(currentVersion)，最新版本 \(pendingUpdatePrompt.version)。已检测到本地已下载的更新 DMG，可直接打开安装；如果 macOS 阻止启动，请到“系统设置 > 隐私与安全性”允许打开 C-Paper。"
            } else {
                pendingUpdatePromptMessage = "当前版本 \(currentVersion)，最新版本 \(pendingUpdatePrompt.version)。下载完成后打开 DMG 安装；如果 macOS 阻止启动，请到“系统设置 > 隐私与安全性”允许打开 C-Paper。"
            }
        } else {
            pendingUpdatePromptMessage = nil
        }
    }
}

struct SettingsWorkflowPresentation: Equatable, Sendable {
    let showsSupportDirectoryNotice: Bool
    let showsSettingsNotice: Bool
    let canCopyLatestDiagnostic: Bool

    init(
        supportDirectoryNotice: SupportDirectoryNotice?,
        settingsNotice: SettingsNotice?,
        lastDiagnostic: SupportDiagnostic?
    ) {
        showsSupportDirectoryNotice = supportDirectoryNotice != nil
        showsSettingsNotice = settingsNotice != nil
        canCopyLatestDiagnostic = lastDiagnostic != nil
    }
}

struct UpdateSettingsWorkflowPresentation: Equatable, Sendable {
    let showsUpdateNotice: Bool
    let showsDownloadedSummary: Bool
    let showsDestinationPath: Bool
    let checkButtonTitle: String
    let disablesCheckButton: Bool
    let showsDownloadButton: Bool
    let disablesDownloadButton: Bool
    let showsOpenDownloadedButton: Bool
    let showsRevealDownloadedButton: Bool

    init(
        status: UpdateStatus,
        updateNotice: UpdateNotice?,
        downloadedSummary: String?
    ) {
        let updateWorkflowPresentation = UpdateWorkflowPresentation(status: status)
        showsUpdateNotice = updateNotice != nil
        showsDestinationPath = status.destinationURL != nil
        showsDownloadButton = status.availableRelease != nil
        showsOpenDownloadedButton = updateWorkflowPresentation.canAccessDownloadedFile
        showsRevealDownloadedButton = updateWorkflowPresentation.canAccessDownloadedFile

        if case .checking = status {
            checkButtonTitle = "检查中"
            disablesCheckButton = true
        } else if case .downloading = status {
            checkButtonTitle = "检查更新"
            disablesCheckButton = true
        } else {
            checkButtonTitle = "检查更新"
            disablesCheckButton = false
        }

        if case .downloading = status {
            disablesDownloadButton = true
        } else {
            disablesDownloadButton = false
        }

        if case .downloaded = status {
            showsDownloadedSummary = downloadedSummary != nil
        } else {
            showsDownloadedSummary = false
        }
    }
}

enum DownloadsHeaderAction: Equatable, Sendable {
    case cancelRunning
    case retryFailed
    case none
}

enum DownloadsQueueBadge: Equatable, Sendable {
    case running
    case attention
    case none
}

struct DownloadsWorkflowPresentation: Equatable, Sendable {
    let showsSaveDirectoryNotice: Bool
    let showsRecoveryNotice: Bool
    let showsRecoverySummary: Bool
    let showsIntegrityNotice: Bool
    let showsCopyDiagnosticButton: Bool
    let showsEmptyState: Bool
    let headerAction: DownloadsHeaderAction
    let queueBadge: DownloadsQueueBadge

    init(
        snapshot: DownloadStatusSnapshot,
        failedDownloadCount: Int,
        hasRetryableFailedDownloads: Bool,
        hasSaveDirectoryNotice: Bool,
        hasRecoveryNotice: Bool,
        hasRecoverySummary: Bool,
        hasIntegrityNotice: Bool,
        downloadCount: Int
    ) {
        showsSaveDirectoryNotice = hasSaveDirectoryNotice
        showsRecoveryNotice = hasRecoveryNotice
        showsRecoverySummary = hasRecoverySummary
        showsIntegrityNotice = hasIntegrityNotice
        showsEmptyState = downloadCount == 0

        if snapshot.isRunning {
            headerAction = .cancelRunning
            queueBadge = .running
        } else if hasRetryableFailedDownloads {
            headerAction = .retryFailed
            queueBadge = .attention
        } else {
            headerAction = .none
            queueBadge = failedDownloadCount > 0 ? .attention : .none
        }

        showsCopyDiagnosticButton = !snapshot.isRunning && failedDownloadCount > 0
    }
}

struct PreviewLoadRequest: Equatable, Sendable {
    let fileID: String?
    let revision: Int
}
