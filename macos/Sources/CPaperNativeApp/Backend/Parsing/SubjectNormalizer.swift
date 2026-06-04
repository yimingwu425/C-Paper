import Foundation

enum SubjectNormalizer {
    static func subject(fromFrankcie item: [String: String]) -> Subject? {
        let code = item["value"] ?? item["code"] ?? item["id"]
        let name = item["text"] ?? item["name"] ?? item["title"]
        guard let code, !code.isEmpty, let name, !name.isEmpty else {
            return nil
        }
        return Subject(code: code, name: name)
    }

    static func subjectCode(in text: String) -> String? {
        let pattern = #"(?<!\d)(\d{4})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    static func subject(fromDirectoryName value: String) -> Subject? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\s*(.+?)(?:\s*\((\d{4})\)|[-\s]+(\d{4}))\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 4,
              let nameRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }

        let codeRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
        guard let resolvedCodeRange = Range(codeRange, in: trimmed) else {
            return nil
        }

        let code = String(trimmed[resolvedCodeRange])
        let name = String(trimmed[nameRange])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))
        guard !code.isEmpty, !name.isEmpty else { return nil }
        return Subject(code: code, name: name)
    }

    static func deduplicate(_ subjects: [Subject]) -> [Subject] {
        var seen: Set<String> = []
        var result: [Subject] = []
        for subject in subjects.sorted(by: { $0.code < $1.code }) where !seen.contains(subject.code) {
            seen.insert(subject.code)
            result.append(subject)
        }
        return result
    }
}
