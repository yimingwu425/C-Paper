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
    let errorType: String
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
        errorType: String,
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
        if !error.isEmpty {
            return error
        }
        return status.title
    }
}

struct DownloadStatusSnapshot: Codable, Equatable {
    let phase: String
    let done: Int
    let total: Int
    let success: Int
    let message: String
    let failed: Int?
    let cancelled: Int?
    let skipped: Int?

    var isRunning: Bool { phase == "running" }
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
