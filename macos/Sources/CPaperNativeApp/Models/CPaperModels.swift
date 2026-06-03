import Foundation

enum AppRoute: String, CaseIterable, Identifiable, Codable {
    case search
    case batch
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "搜索"
        case .batch: "批量"
        case .downloads: "下载"
        }
    }

    var symbolName: String {
        switch self {
        case .search: "magnifyingglass"
        case .batch: "square.stack.3d.down.right"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct Subject: Identifiable, Hashable, Codable {
    let code: String
    let name: String

    var id: String { code }
    var displayName: String { "\(code) · \(cleanName)" }

    private var cleanName: String {
        let escapedCode = NSRegularExpression.escapedPattern(for: code)
        let withoutCode = name.replacingOccurrences(
            of: #"^\s*\#(escapedCode)\s*[-·]\s*"#,
            with: "",
            options: .regularExpression
        )
        return withoutCode.replacingOccurrences(
            of: #"\s*-\s*.*视频.*$"#,
            with: "",
            options: .regularExpression
        )
    }
}

enum Season: String, CaseIterable, Identifiable, Codable, Hashable {
    case mar = "Mar"
    case jun = "Jun"
    case nov = "Nov"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mar: "Mar 春"
        case .jun: "Jun 夏"
        case .nov: "Nov 冬"
        }
    }
}

enum DuplicateMode: String, CaseIterable, Identifiable, Codable {
    case overwrite
    case skip
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite: "覆盖下载"
        case .skip: "跳过已下载"
        case .missing: "只补缺失"
        }
    }
}

enum PaperSourceID: String, CaseIterable, Identifiable, Codable, Hashable {
    case automatic
    case frankcie
    case papaCambridge
    case pastPapers
    case easyPaper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .frankcie: "Frankcie"
        case .papaCambridge: "PapaCambridge"
        case .pastPapers: "PastPapers"
        case .easyPaper: "EasyPaper"
        }
    }

    var allowsFallback: Bool { self == .automatic }
}

struct PaperComponent: Codable, Hashable {
    let sourceID: PaperSourceID
    let filename: String
    let url: URL
    let paperType: String
    let subjectCode: String?
    let sy: String?
    let number: String?
    let label: String?

    var year: Int? {
        PaperFilenameParser.year(fromSY: sy)
    }

    var seasonName: String? {
        PaperFilenameParser.seasonName(fromSY: sy)
    }

    var asPaperFile: PaperFile {
        PaperFile(
            filename: filename,
            url: url,
            year: year,
            season: seasonName,
            paperType: paperType.uppercased(),
            subjectCode: subjectCode,
            number: number,
            label: label,
            sourceID: sourceID
        )
    }
}

struct NativePaperGroup: Codable, Hashable {
    let sourceID: PaperSourceID
    let subjectCode: String?
    let sy: String?
    let number: String?
    let paperGroup: Int?
    let qp: PaperComponent?
    let ms: PaperComponent?
    let extras: [PaperComponent]

    var files: [PaperFile] {
        [qp, ms].compactMap { $0?.asPaperFile } + extras.map(\.asPaperFile)
    }
}

struct PaperFile: Identifiable, Hashable, Codable {
    let filename: String
    let url: URL
    let year: Int?
    let season: String?
    let paperType: String?
    let subjectCode: String?
    let number: String?
    let label: String?
    var sourceID: PaperSourceID = .frankcie

    var id: String { url.absoluteString }

    var componentKey: String? {
        if paperType?.uppercased() == "GT" {
            return "gt"
        }
        guard let number, !number.isEmpty else { return label }
        return number
    }

    var componentTitle: String {
        guard let componentKey, !componentKey.isEmpty else { return "Other" }
        if componentKey.lowercased() == "gt" {
            return "Grade Threshold"
        }
        return "Paper \(componentKey)"
    }

    var subtitle: String {
        [sourceID == .frankcie ? nil : sourceID.title, subjectCode, season, year.map(String.init), paperType, number]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct BackendPaperGroup: Codable, Hashable {
    let subject: String?
    let sy: String?
    let number: String?
    let paperGroup: Int?
    let qp: String?
    let ms: String?
    let filename: String?
    let ftype: String?
    let label: String?

    enum CodingKeys: String, CodingKey {
        case subject
        case sy
        case number
        case paperGroup = "paper_group"
        case qp
        case ms
        case filename
        case ftype
        case label
    }
}

struct SearchPayload: Codable {
    let groups: [NativePaperGroup]
    let files: [PaperFile]
    let sourceID: PaperSourceID?
    let warnings: [String]

    init(groups: [NativePaperGroup], files: [PaperFile]? = nil, sourceID: PaperSourceID? = nil, warnings: [String] = []) {
        self.groups = groups
        self.files = files ?? groups.flatMap(\.files)
        self.sourceID = sourceID
        self.warnings = warnings
    }
}

struct BatchPreviewPayload: Codable {
    let groups: [NativePaperGroup]
    let files: [PaperFile]
    let warnings: [String]

    init(groups: [NativePaperGroup], files: [PaperFile]? = nil, warnings: [String] = []) {
        self.groups = groups
        self.files = files ?? groups.flatMap(\.files)
        self.warnings = warnings
    }
}

struct SearchParams: Encodable {
    let subject: String
    let year: Int
    let season: String
}

struct BatchPreviewParams: Encodable {
    let code: String
    let yearFrom: Int
    let yearTo: Int
    let seasons: [String]
    let paperGroups: [Int]

    enum CodingKeys: String, CodingKey {
        case code
        case yearFrom = "year_from"
        case yearTo = "year_to"
        case seasons
        case paperGroups = "pgs"
    }
}

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
    }

    var progress: Double {
        switch status {
        case .done, .skipped: 1
        case .downloading: 0.55
        case .failed, .cancelled, .pending: 0
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
