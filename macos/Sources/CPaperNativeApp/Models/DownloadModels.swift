import Foundation

struct DownloadStartParams: Encodable {
    let groups: [NativePaperGroup]
    let saveDir: String
    let options: DownloadOptions

    enum CodingKeys: String, CodingKey {
        case groups
        case saveDir = "save_dir"
        case options
    }
}

struct DownloadOptions: Codable, Equatable {
    var rate: Double
    var threads: Int
    var merge: Bool
    var duplicateMode: DuplicateMode
    var includeMarkSchemes: Bool

    enum CodingKeys: String, CodingKey {
        case rate
        case threads
        case merge
        case duplicateMode = "dup_mode"
        case includeMarkSchemes = "include_ms"
    }
}

enum DownloadStatus: String, Codable, Hashable {
    case pending
    case downloading
    case done
    case failed
    case cancelled
    case skipped

    var title: String {
        switch self {
        case .pending: "等待"
        case .downloading: "下载中"
        case .done: "完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        case .skipped: "已跳过"
        }
    }
}

struct DownloadTaskItem: Identifiable, Hashable, Codable {
    let id: Int
    let filename: String
    let ftype: String
    let label: String
    let year: String
    let savePath: String
    let status: DownloadStatus
    let error: String
    let errorType: DownloadTaskErrorType?
    let progressFraction: Double?

    init(
        id: Int,
        filename: String,
        ftype: String,
        label: String,
        year: String,
        savePath: String,
        status: DownloadStatus,
        error: String,
        errorType: DownloadTaskErrorType?,
        progressFraction: Double? = nil
    ) {
        self.id = id
        self.filename = filename
        self.ftype = ftype
        self.label = label
        self.year = year
        self.savePath = savePath
        self.status = status
        self.error = error
        self.errorType = errorType
        self.progressFraction = progressFraction
    }

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case ftype
        case label
        case year
        case savePath = "save_path"
        case status
        case error
        case errorType = "error_type"
        case progressFraction = "progress_fraction"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        ftype = try container.decode(String.self, forKey: .ftype)
        label = try container.decode(String.self, forKey: .label)
        year = try container.decode(String.self, forKey: .year)
        savePath = try container.decode(String.self, forKey: .savePath)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        error = try container.decode(String.self, forKey: .error)
        progressFraction = try container.decodeIfPresent(Double.self, forKey: .progressFraction)

        let rawErrorType = try container.decodeIfPresent(String.self, forKey: .errorType)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawErrorType, !rawErrorType.isEmpty {
            errorType = DownloadTaskErrorType(rawValue: rawErrorType) ?? .unknown
        } else {
            errorType = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(filename, forKey: .filename)
        try container.encode(ftype, forKey: .ftype)
        try container.encode(label, forKey: .label)
        try container.encode(year, forKey: .year)
        try container.encode(savePath, forKey: .savePath)
        try container.encode(status, forKey: .status)
        try container.encode(error, forKey: .error)
        try container.encode(errorType?.rawValue ?? "", forKey: .errorType)
        try container.encodeIfPresent(progressFraction, forKey: .progressFraction)
    }

    var progress: Double {
        if let progressFraction {
            return min(max(progressFraction, 0), 1)
        }

        switch status {
        case .done, .skipped:
            return 1
        case .downloading:
            return 0.55
        case .failed, .cancelled, .pending:
            return 0
        }
    }

    var message: String {
        if status == .failed || status == .cancelled, let errorType {
            return errorType.userVisibleMessage
        }
        if let rawErrorMessage {
            return rawErrorMessage
        }
        return status.title
    }

    var rawErrorMessage: String? {
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var recoveryAction: DownloadTaskRecoveryAction {
        switch status {
        case .done, .skipped, .pending, .downloading:
            return .none
        case .cancelled:
            return .restartIfNeeded
        case .failed:
            switch errorType {
            case .network:
                return .retryNow
            case .rateLimit:
                return .retryLater
            case .interrupted:
                return .retryNow
            case .cancelled:
                return .restartIfNeeded
            case .unknown, nil:
                return .inspectDiagnostic
            }
        }
    }

    var workflowTag: DownloadTaskWorkflowTag? {
        guard status == .failed else { return nil }
        switch errorType {
        case .interrupted:
            return .recoveredInterruptedSession
        case .network, .rateLimit, .cancelled, .unknown, nil:
            return nil
        }
    }
}

enum DownloadTaskWorkflowTag: String, Codable, Hashable {
    case recoveredInterruptedSession = "recovered_interrupted_session"

    var title: String {
        switch self {
        case .recoveredInterruptedSession:
            return "上次会话"
        }
    }

    var summary: String {
        switch self {
        case .recoveredInterruptedSession:
            return "该任务来自上次中断后恢复的下载会话。"
        }
    }

    var symbolName: String {
        switch self {
        case .recoveredInterruptedSession:
            return "arrow.uturn.backward.circle"
        }
    }
}

enum DownloadTaskIntegrityState: String, Codable, Hashable {
    case missingFile = "missing_file"
    case unreadableFile = "unreadable_file"
    case emptyFile = "empty_file"
    case directoryPath = "directory_path"
    case nonRegularFile = "non_regular_file"

    var title: String {
        switch self {
        case .missingFile:
            return "文件丢失"
        case .unreadableFile:
            return "文件不可读"
        case .emptyFile:
            return "空文件"
        case .directoryPath, .nonRegularFile:
            return "路径异常"
        }
    }

    var summary: String {
        switch self {
        case .missingFile:
            return "该下载记录仍在，但对应文件已经不存在。"
        case .unreadableFile:
            return "该下载文件当前不可读，通常需要重新下载修复。"
        case .emptyFile:
            return "该下载文件为空，通常需要重新下载修复。"
        case .directoryPath:
            return "该下载路径当前指向目录而不是文件，需要手动检查。"
        case .nonRegularFile:
            return "该下载路径当前不是常规文件，需要手动检查。"
        }
    }

    var allowsRepairRetry: Bool {
        switch self {
        case .missingFile, .unreadableFile, .emptyFile:
            return true
        case .directoryPath, .nonRegularFile:
            return false
        }
    }
}

enum DownloadTaskErrorType: String, Codable, Hashable {
    case network
    case rateLimit = "rate_limit"
    case cancelled
    case interrupted
    case unknown

    var userVisibleMessage: String {
        switch self {
        case .network:
            return "网络错误，请稍后重试"
        case .rateLimit:
            return "服务器限流，请稍后重试"
        case .cancelled:
            return "用户取消"
        case .interrupted:
            return "上次下载在应用退出前中断，请重试"
        case .unknown:
            return "下载失败"
        }
    }
}

enum DownloadTaskRecoveryAction: String, Codable, Hashable {
    case none
    case retryNow = "retry_now"
    case retryLater = "retry_later"
    case inspectDiagnostic = "inspect_diagnostic"
    case restartIfNeeded = "restart_if_needed"

    var title: String {
        switch self {
        case .none:
            return "无需处理"
        case .retryNow:
            return "检查网络后重试"
        case .retryLater:
            return "稍后再试"
        case .inspectDiagnostic:
            return "复制诊断后重试"
        case .restartIfNeeded:
            return "如需继续请重新加入"
        }
    }

    var guidance: String? {
        switch self {
        case .none:
            return nil
        case .retryNow, .retryLater, .inspectDiagnostic, .restartIfNeeded:
            return title
        }
    }

    var allowsQueueRetry: Bool {
        switch self {
        case .retryNow, .retryLater:
            return true
        case .none, .inspectDiagnostic, .restartIfNeeded:
            return false
        }
    }
}

struct DownloadStatusSnapshot: Codable, Equatable {
    let phase: DownloadQueuePhase
    let done: Int
    let total: Int
    let success: Int
    let message: String
    let failed: Int?
    let cancelled: Int?
    let skipped: Int?

    var isRunning: Bool { phase == .running }
}

enum DownloadQueuePhase: String, Codable, Equatable {
    case idle
    case running
    case done
}

struct DownloadStartResult: Codable, Equatable {
    let ok: Bool
    let total: Int
    let skipped: Int
}

struct ProxyResult: Codable, Equatable {
    let ok: Bool
    let latencyMs: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case latencyMs = "latency_ms"
        case error
    }
}

struct OKResult: Codable, Equatable {
    let ok: Bool
    let error: String?
}

struct PDFURLResult: Codable, Equatable {
    let url: URL
}

struct ProxyParams: Encodable {
    let proxyURL: String

    enum CodingKeys: String, CodingKey {
        case proxyURL = "proxy_url"
    }
}

struct FavoriteParams: Encodable {
    let code: String
    let name: String
}

struct FileNameParams: Encodable {
    let filename: String
}

struct DownloadSettings: Codable, Equatable {
    var theme: String = "light"
    var saveDirectory: String = "~/Downloads/C-Paper"
    var includeMarkSchemes: Bool = true
    var rate: Double = 5
    var threads: Int = 4
    var mergeFolders: Bool = false
    var proxyURL: String = ""
    var lastSubject: String = ""
    var lastMode: String = AppRoute.search.rawValue
    var duplicateMode: DuplicateMode = .overwrite
    var sourceMode: PaperSourceID = .automatic

    enum CodingKeys: String, CodingKey {
        case theme
        case saveDirectory = "save_dir"
        case includeMarkSchemes = "include_ms"
        case rate
        case threads
        case mergeFolders = "merge"
        case proxyURL = "proxy_url"
        case lastSubject = "last_subject"
        case lastMode = "last_mode"
        case duplicateMode = "dup_mode"
        case sourceMode = "source_mode"
    }

    var downloadOptions: DownloadOptions {
        DownloadOptions(
            rate: rate,
            threads: threads,
            merge: mergeFolders,
            duplicateMode: duplicateMode,
            includeMarkSchemes: includeMarkSchemes
        )
    }
}

extension DownloadSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DownloadSettings()

        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
        saveDirectory = try container.decodeIfPresent(String.self, forKey: .saveDirectory) ?? defaults.saveDirectory
        includeMarkSchemes = try container.decodeIfPresent(Bool.self, forKey: .includeMarkSchemes) ?? defaults.includeMarkSchemes
        rate = try container.decodeIfPresent(Double.self, forKey: .rate) ?? defaults.rate
        threads = try container.decodeIfPresent(Int.self, forKey: .threads) ?? defaults.threads
        mergeFolders = try container.decodeIfPresent(Bool.self, forKey: .mergeFolders) ?? defaults.mergeFolders
        proxyURL = try container.decodeIfPresent(String.self, forKey: .proxyURL) ?? defaults.proxyURL
        lastSubject = try container.decodeIfPresent(String.self, forKey: .lastSubject) ?? defaults.lastSubject
        lastMode = try container.decodeIfPresent(String.self, forKey: .lastMode) ?? defaults.lastMode
        duplicateMode = try container.decodeIfPresent(DuplicateMode.self, forKey: .duplicateMode) ?? defaults.duplicateMode
        sourceMode = try container.decodeIfPresent(PaperSourceID.self, forKey: .sourceMode) ?? defaults.sourceMode
    }
}
