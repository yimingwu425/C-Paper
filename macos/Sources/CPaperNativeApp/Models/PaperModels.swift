import Foundation

struct PaperComponent: Codable, Hashable, Sendable {
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

struct NativePaperGroup: Codable, Hashable, Sendable {
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
    let usedAutomaticFallback: Bool
    let warnings: [String]

    init(
        groups: [NativePaperGroup],
        files: [PaperFile]? = nil,
        sourceID: PaperSourceID? = nil,
        usedAutomaticFallback: Bool = false,
        warnings: [String] = []
    ) {
        self.groups = groups
        self.files = files ?? groups.flatMap(\.files)
        self.sourceID = sourceID
        self.usedAutomaticFallback = usedAutomaticFallback
        self.warnings = warnings
    }
}

struct BatchPreviewPayload: Codable {
    let groups: [NativePaperGroup]
    let files: [PaperFile]
    let sourceIDs: [PaperSourceID]
    let successfulQueryCount: Int
    let automaticFallbackQueryCount: Int
    let warnings: [String]

    init(
        groups: [NativePaperGroup],
        files: [PaperFile]? = nil,
        sourceIDs: [PaperSourceID] = [],
        successfulQueryCount: Int = 0,
        automaticFallbackQueryCount: Int = 0,
        warnings: [String] = []
    ) {
        self.groups = groups
        self.files = files ?? groups.flatMap(\.files)
        self.sourceIDs = sourceIDs
        self.successfulQueryCount = successfulQueryCount
        self.automaticFallbackQueryCount = automaticFallbackQueryCount
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
