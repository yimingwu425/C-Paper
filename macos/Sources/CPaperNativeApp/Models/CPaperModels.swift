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
        case .frankcie: "FrankCIE"
        case .papaCambridge: "PapaCambridge"
        case .pastPapers: "PastPapers"
        case .easyPaper: "EasyPaper"
        }
    }

    var allowsFallback: Bool { self == .automatic }
}
