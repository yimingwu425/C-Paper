import Foundation

enum PastPapersLevel: CaseIterable {
    case aLevel
    case igcse
    case oLevel

    var viewPath: String {
        switch self {
        case .aLevel: "a-level"
        case .igcse: "igcse"
        case .oLevel: "o-level"
        }
    }
}

struct PastPapersSubjectDirectory {
    let level: PastPapersLevel
    let relPath: String

    var viewSubjectSlug: String {
        relPath.split(separator: "/").last.map { String($0).lowercased() } ?? relPath.lowercased()
    }

    static let seed: [String: PastPapersSubjectDirectory] = [
        "9709": PastPapersSubjectDirectory(level: .aLevel, relPath: "A-Level/Mathematics-9709")
    ]
}

struct PastPapersSeason {
    let sy: String
    let viewSlug: String
    let staticDirectoryNames: [String]

    init?(query: PaperSourceQuery, year: Int) {
        let shortYear = String(format: "%02d", year % 100)
        switch query.seasonPrefix {
        case "m":
            sy = "m\(shortYear)"
            viewSlug = "\(year)-march"
            staticDirectoryNames = ["\(year)-March", "\(year)-Feb-March"]
        case "s":
            sy = "s\(shortYear)"
            viewSlug = "\(year)-may-june"
            staticDirectoryNames = ["\(year)-May-June"]
        case "w":
            sy = "w\(shortYear)"
            viewSlug = "\(year)-oct-nov"
            staticDirectoryNames = ["\(year)-Oct-Nov", "\(year)-October-November"]
        default:
            return nil
        }
    }

    func candidateFilenames(subjectCode: String) -> [String] {
        let paperNumbers = (1...6).flatMap { group in
            (1...3).map { variant in "\(group)\(variant)" }
        }
        return ["qp", "ms"].flatMap { type in
            paperNumbers.map { number in "\(subjectCode)_\(sy)_\(type)_\(number).pdf" }
        }
    }
}

struct PastPapersEntry: Hashable {
    let name: String
    let relPath: String
    let isDir: Bool

    func matchesSubjectCode(_ subjectCode: String) -> Bool {
        let normalizedCode = subjectCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.hasSuffix("-\(normalizedCode)")
            || name.contains("(\(normalizedCode))")
            || relPath.hasSuffix("-\(normalizedCode)")
            || relPath.contains("(\(normalizedCode))")
    }
}

enum PastPapersEntriesExtractor {
    static func entries(from html: String) -> [PastPapersEntry] {
        var seen = Set<PastPapersEntry>()
        var entries: [PastPapersEntry] = []

        for candidate in [html, normalizedRSCText(from: html)] {
            for entry in parseEntries(from: candidate) where seen.insert(entry).inserted {
                entries.append(entry)
            }
        }

        return entries
    }

    private static func normalizedRSCText(from html: String) -> String {
        html
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private static func parseEntries(from text: String) -> [PastPapersEntry] {
        let pattern = #"\{[^{}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard let objectRange = Range(match.range, in: text)
            else {
                return nil
            }

            let objectText = String(text[objectRange])
            guard let data = objectText.data(using: .utf8),
                  let candidate = try? JSONDecoder().decode(CandidateEntry.self, from: data)
            else {
                return nil
            }

            return PastPapersEntry(
                name: candidate.name,
                relPath: candidate.relPath,
                isDir: candidate.isDir
            )
        }
    }

    private struct CandidateEntry: Decodable {
        let name: String
        let relPath: String
        let isDir: Bool
    }
}
