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
