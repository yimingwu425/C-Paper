import Foundation

struct ParsedPaperFilename: Equatable {
    let subject: String
    let sy: String
    let type: String
    let number: String
    let filename: String
}

enum PaperFilenameParser {
    private static let filenamePattern = #"^(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf$"#

    static func parse(_ filename: String) -> ParsedPaperFilename? {
        guard !filename.isEmpty,
              filename.lowercased().hasSuffix(".pdf"),
              !filename.contains(".."),
              !filename.contains("/"),
              !filename.contains("\\")
        else {
            return nil
        }

        guard let regex = try? NSRegularExpression(pattern: filenamePattern),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              match.numberOfRanges >= 5
        else {
            return nil
        }

        func value(at index: Int) -> String {
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: filename) else { return "" }
            return String(filename[swiftRange])
        }

        return ParsedPaperFilename(
            subject: value(at: 1),
            sy: value(at: 2),
            type: value(at: 3),
            number: value(at: 4),
            filename: filename
        )
    }

    static func year(fromSY sy: String?) -> Int? {
        guard let sy,
              sy.count > 1,
              ["m", "s", "w"].contains(String(sy.prefix(1))),
              let shortYear = Int(sy.dropFirst())
        else {
            return nil
        }
        return 2000 + shortYear
    }

    static func seasonName(fromSY sy: String?) -> String? {
        guard let first = sy?.first else { return nil }
        switch first {
        case "m": return "Mar"
        case "s": return "Jun"
        case "w": return "Nov"
        default: return nil
        }
    }

    static func syCode(season: Season, year: Int) -> String {
        let prefix: String
        switch season {
        case .mar: prefix = "m"
        case .jun: prefix = "s"
        case .nov: prefix = "w"
        }
        let shortYear = year % 100
        return "\(prefix)\(String(format: "%02d", shortYear))"
    }

    static func paperGroup(of number: String?) -> Int {
        guard let number, !number.isEmpty, let value = Int(number) else {
            return 0
        }
        return value >= 10 ? value / 10 : value
    }
}
