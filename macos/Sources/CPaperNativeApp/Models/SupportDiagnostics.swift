import Foundation

enum SupportDiagnosticContext: String, Codable, Equatable, Hashable, Sendable {
    case general
    case startup
    case supportDirectory
    case settings
    case favorites
    case saveDirectory
    case sourceProvider
    case download
    case downloadIntegrity
    case preview
    case update

    var title: String {
        switch self {
        case .general:
            "应用"
        case .startup:
            "启动"
        case .supportDirectory:
            "支持文件夹"
        case .settings:
            "设置"
        case .favorites:
            "收藏"
        case .saveDirectory:
            "保存目录"
        case .sourceProvider:
            "资料来源"
        case .download:
            "下载"
        case .downloadIntegrity:
            "已下载文件"
        case .preview:
            "预览"
        case .update:
            "更新"
        }
    }
}

struct SupportDiagnosticDetail: Equatable, Sendable {
    let label: String
    let value: String
}

struct SupportDiagnostic: Equatable, Sendable {
    let context: SupportDiagnosticContext
    let createdAt: Date
    let message: String
    let details: [SupportDiagnosticDetail]
    let supportDirectoryPath: String?
    let reportURL: URL?

    init(
        context: SupportDiagnosticContext,
        message: String,
        details: [SupportDiagnosticDetail] = [],
        supportDirectoryPath: String? = nil,
        reportURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.context = context
        self.createdAt = createdAt
        self.message = Self.redact(message)
        self.details = details.map { detail in
            SupportDiagnosticDetail(label: detail.label, value: Self.redact(detail.value))
        }
        self.supportDirectoryPath = supportDirectoryPath.map(Self.redact)
        self.reportURL = reportURL
    }

    var reportText: String {
        var lines = [
            "C-Paper Diagnostics",
            "Time: \(Self.timestampString(from: createdAt))",
            "Area: \(context.title)",
            "Message: \(message)"
        ]

        if let supportDirectoryPath {
            lines.append("Support Directory: \(supportDirectoryPath)")
        }
        if let reportURL {
            lines.append("Report File: \(Self.redact(reportURL.path))")
        }
        if !details.isEmpty {
            lines.append("Details:")
            lines.append(contentsOf: details.map { "- \($0.label): \($0.value)" })
        }
        return lines.joined(separator: "\n")
    }

    func withReportURL(_ url: URL) -> SupportDiagnostic {
        SupportDiagnostic(
            context: context,
            message: message,
            details: details,
            supportDirectoryPath: supportDirectoryPath,
            reportURL: url,
            createdAt: createdAt
        )
    }

    static func redact(_ value: String) -> String {
        var redacted = value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        redacted = replacing(
            pattern: #"([A-Za-z][A-Za-z0-9+.-]*://)([^/\s@:]+(:[^/\s@]*)?@)"#,
            in: redacted,
            with: "$1<redacted>@"
        )
        redacted = replacing(
            pattern: #"/paperdownload/dir_v3/[^?\s/#]+"#,
            in: redacted,
            with: "/paperdownload/dir_v3/<redacted>"
        )
        redacted = replacing(
            pattern: #"(?i)\b(token|access_token|api_key|password|refresh_token|key|secret|sig|signature|x-amz-signature|x-goog-signature|x-ms-signature)=([^&\s]+)"#,
            in: redacted,
            with: "$1=<redacted>"
        )
        redacted = replacing(
            pattern: #"/Users/[^/\s]+/"#,
            in: redacted,
            with: "~/"
        )
        return redacted
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func replacing(pattern: String, in value: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: template
        )
    }
}
