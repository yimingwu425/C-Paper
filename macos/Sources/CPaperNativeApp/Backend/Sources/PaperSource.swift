import Foundation

struct PaperSourceQuery: Equatable, Sendable {
    var subjectCode: String
    var year: Int?
    var season: String?

    init(subjectCode: String, year: Int? = nil, season: String? = nil) {
        self.subjectCode = SubjectNormalizer.subjectCode(in: subjectCode)
            ?? subjectCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.year = year
        self.season = season
    }

    var seasonPrefix: String? {
        switch season?.lowercased() {
        case "mar", "march", "m":
            "m"
        case "jun", "june", "s", "summer":
            "s"
        case "nov", "november", "w", "winter":
            "w"
        default:
            nil
        }
    }
}

protocol PaperSource: Sendable {
    var id: PaperSourceID { get }
    var displayName: String { get }

    func fetchSubjects() async throws -> [Subject]
    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult
    func healthCheck() async -> SourceHealth
}

extension PaperSource {
    var displayName: String { id.title }

    func fetchSubjects() async throws -> [Subject] {
        throw PaperSourceError.sourceUnavailable("\(id.title) 暂不支持科目列表")
    }
}

enum SourceHealthStatus: String, Codable, Equatable {
    case available
    case unavailable
    case degraded
}

struct SourceHealth: Codable, Equatable {
    let sourceID: PaperSourceID
    let status: SourceHealthStatus
    let message: String?

    init(sourceID: PaperSourceID, status: SourceHealthStatus, message: String? = nil) {
        self.sourceID = sourceID
        self.status = status
        self.message = message
    }

    var isAvailable: Bool {
        status == .available || status == .degraded
    }
}

enum SourceAttemptStatus: String, Codable, Equatable, Sendable {
    case success
    case empty
    case failed
}

struct SourceAttempt: Codable, Equatable, Sendable {
    let sourceID: PaperSourceID
    let status: SourceAttemptStatus
    let resultCount: Int
    let errorMessage: String?
    let durationMilliseconds: Int?

    var message: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        switch status {
        case .success:
            return "\(resultCount) 个结果"
        case .empty:
            return "无结果"
        case .failed:
            return "失败"
        }
    }

    var diagnosticMessage: String {
        guard let durationMilliseconds else {
            return message
        }
        return "\(message)（耗时 \(durationMilliseconds) ms）"
    }

    static func success(
        _ sourceID: PaperSourceID,
        count: Int,
        durationMilliseconds: Int? = nil
    ) -> SourceAttempt {
        SourceAttempt(
            sourceID: sourceID,
            status: count > 0 ? .success : .empty,
            resultCount: count,
            errorMessage: nil,
            durationMilliseconds: durationMilliseconds
        )
    }

    static func failure(
        _ sourceID: PaperSourceID,
        error: Error,
        durationMilliseconds: Int? = nil
    ) -> SourceAttempt {
        SourceAttempt(
            sourceID: sourceID,
            status: .failed,
            resultCount: 0,
            errorMessage: error.localizedDescription,
            durationMilliseconds: durationMilliseconds
        )
    }
}

struct SourceSearchResult: Codable, Equatable, Sendable {
    let sourceID: PaperSourceID
    let components: [PaperComponent]
    let groups: [NativePaperGroup]
    var attempts: [SourceAttempt]

    init(sourceID: PaperSourceID, components: [PaperComponent], attempts: [SourceAttempt] = []) {
        self.sourceID = sourceID
        self.components = components
        self.groups = PaperGrouper.groups(from: components)
        self.attempts = attempts
    }
}

enum PaperSourceError: Error, Equatable, LocalizedError {
    case sourceUnavailable(String)
    case invalidResponse(String)
    case unsupportedSource(PaperSourceID)
    case allSourcesUnavailable([SourceAttempt])

    var errorDescription: String? {
        switch self {
        case let .sourceUnavailable(message):
            message
        case let .invalidResponse(message):
            message
        case let .unsupportedSource(sourceID):
            "不支持的来源：\(sourceID.title)"
        case let .allSourcesUnavailable(attempts):
            "所有来源均不可用（共尝试 \(attempts.count) 个）"
        }
    }
}

extension PaperComponent {
    static func sourceComponent(
        sourceID: PaperSourceID,
        parsed: ParsedPaperFilename,
        url: URL,
        label: String? = nil
    ) -> PaperComponent {
        PaperComponent(
            sourceID: sourceID,
            filename: parsed.filename,
            url: url,
            paperType: parsed.type,
            subjectCode: parsed.subject,
            sy: parsed.sy,
            number: parsed.number.isEmpty ? nil : parsed.number,
            label: label
        )
    }

    func matches(_ query: PaperSourceQuery) -> Bool {
        guard subjectCode == query.subjectCode else { return false }
        if let year = query.year, self.year != year {
            return false
        }
        if let prefix = query.seasonPrefix, sy?.hasPrefix(prefix) != true {
            return false
        }
        return true
    }
}
