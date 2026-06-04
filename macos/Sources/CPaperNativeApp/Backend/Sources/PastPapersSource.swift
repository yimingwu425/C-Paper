import Foundation

struct PastPapersSource: PaperSource {
    let id: PaperSourceID = .pastPapers

    private let baseURL: URL
    private let networkClient: any NetworkClientProtocol
    private let requestBuilder: HTTPRequestBuilder

    init(
        baseURL: URL = BackendConstants.pastPapersBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder()
    ) {
        self.baseURL = baseURL
        self.networkClient = networkClient
        self.requestBuilder = requestBuilder
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        guard let year = query.year, let season = PastPapersSeason(query: query, year: year) else {
            throw PaperSourceError.invalidResponse("PastPapers 需要指定年份和季度")
        }

        let subjectDirectory = try await resolveSubjectDirectory(subjectCode: query.subjectCode)
        var listingError: Error?

        do {
            let components = try await loadListingComponents(
                subjectDirectory: subjectDirectory,
                year: year,
                season: season,
                query: query
            )
            if !components.isEmpty {
                return SourceSearchResult(sourceID: id, components: components)
            }
        } catch {
            listingError = error
        }

        let probedComponents = try await probeStaticPDFComponents(
            subjectDirectory: subjectDirectory,
            season: season,
            query: query
        )
        if !probedComponents.isEmpty {
            return SourceSearchResult(sourceID: id, components: probedComponents)
        }

        if let listingError {
            throw listingError
        }
        throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：未找到 \(query.subjectCode) \(year) \(query.season ?? "") 的可下载 PDF")
    }

    func healthCheck() async -> SourceHealth {
        do {
            _ = try await search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))
            return SourceHealth(sourceID: id, status: .available)
        } catch {
            return SourceHealth(sourceID: id, status: .unavailable, message: error.localizedDescription)
        }
    }

    private func resolveSubjectDirectory(subjectCode: String) async throws -> PastPapersSubjectDirectory {
        if let seeded = PastPapersSubjectDirectory.seed[subjectCode] {
            return seeded
        }

        var challengeSeen = false
        for level in PastPapersLevel.allCases {
            let url = caieURL(level.viewPath)
            do {
                let html = String(decoding: try await networkClient.data(for: requestBuilder.get(url)), as: UTF8.self)
                if CloudflareChallengeDetector.isChallenge(html: html) {
                    challengeSeen = true
                    continue
                }
                let entries = PastPapersEntriesExtractor.entries(from: html)
                if let entry = entries.first(where: { $0.isDir && $0.matchesSubjectCode(subjectCode) }) {
                    return PastPapersSubjectDirectory(level: level, relPath: entry.relPath)
                }
            } catch let error as NetworkClientError where error.isLikelyChallenge {
                challengeSeen = true
            }
        }

        if challengeSeen {
            throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：Cloudflare challenge 拦截了科目目录")
        }
        throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：缺少 \(subjectCode) 的目录映射")
    }

    private func loadListingComponents(
        subjectDirectory: PastPapersSubjectDirectory,
        year: Int,
        season: PastPapersSeason,
        query: PaperSourceQuery
    ) async throws -> [PaperComponent] {
        let listingURL = caieURL(
            subjectDirectory.level.viewPath,
            subjectDirectory.viewSubjectSlug,
            season.viewSlug
        )

        do {
            let html = String(decoding: try await networkClient.data(for: requestBuilder.get(listingURL)), as: UTF8.self)
            if CloudflareChallengeDetector.isChallenge(html: html) {
                throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：Cloudflare challenge 拦截了目录页")
            }
            let components = PastPapersEntriesExtractor.entries(from: html)
                .filter { !$0.isDir && $0.name.lowercased().hasSuffix(".pdf") }
                .compactMap { component(from: $0.name, relPath: $0.relPath) }
                .filter { $0.matches(query) }
            if !components.isEmpty {
                return components
            }
            throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：目录页没有返回可解析 PDF entries")
        } catch let error as NetworkClientError {
            if error.isLikelyChallenge {
                throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：Cloudflare challenge 拦截了 HTTP 客户端")
            }
            throw error
        }
    }

    private func probeStaticPDFComponents(
        subjectDirectory: PastPapersSubjectDirectory,
        season: PastPapersSeason,
        query: PaperSourceQuery
    ) async throws -> [PaperComponent] {
        var components: [PaperComponent] = []
        var seenRelPaths = Set<String>()

        for directoryName in season.staticDirectoryNames {
            for filename in season.candidateFilenames(subjectCode: query.subjectCode) {
                let relPath = "\(subjectDirectory.relPath)/\(directoryName)/\(filename)"
                guard seenRelPaths.insert(relPath).inserted else { continue }
                let url = caieFileURL(relPath: relPath)
                if await pdfExists(at: url),
                   let component = component(from: filename, relPath: relPath),
                   component.matches(query) {
                    components.append(component)
                }
            }
            if !components.isEmpty {
                return components
            }
        }

        return components
    }

    private func pdfExists(at url: URL) async -> Bool {
        do {
            _ = try await networkClient.data(for: requestBuilder.head(url))
            return true
        } catch {
            return false
        }
    }

    private func component(from filename: String, relPath: String) -> PaperComponent? {
        guard let parsed = PaperFilenameParser.parse(filename) else { return nil }
        return .sourceComponent(sourceID: id, parsed: parsed, url: caieFileURL(relPath: relPath))
    }

    private func caieURL(_ pathComponents: String...) -> URL {
        var url = baseURL.appendingPathComponent("caie")
        for pathComponent in pathComponents {
            url = url.appendingPathComponent(pathComponent)
        }
        return url
    }

    private func caieFileURL(relPath: String) -> URL {
        var url = baseURL.appendingPathComponent("caie")
        for segment in relPath.split(separator: "/") {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }
}

private enum PastPapersLevel: CaseIterable {
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

private struct PastPapersSubjectDirectory {
    let level: PastPapersLevel
    let relPath: String

    var viewSubjectSlug: String {
        relPath.split(separator: "/").last.map { String($0).lowercased() } ?? relPath.lowercased()
    }

    static let seed: [String: PastPapersSubjectDirectory] = [
        "9709": PastPapersSubjectDirectory(level: .aLevel, relPath: "A-Level/Mathematics-9709")
    ]
}

private struct PastPapersSeason {
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

private struct PastPapersEntry: Hashable {
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

private enum PastPapersEntriesExtractor {
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
        let pattern = #"\{[^{}]*"name"\s*:\s*"([^"]+)"[^{}]*"relPath"\s*:\s*"([^"]+)"[^{}]*"isDir"\s*:\s*(true|false)[^{}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 4,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let relPathRange = Range(match.range(at: 2), in: text),
                  let isDirRange = Range(match.range(at: 3), in: text)
            else {
                return nil
            }

            return PastPapersEntry(
                name: decodeJSONString(String(text[nameRange])),
                relPath: decodeJSONString(String(text[relPathRange])),
                isDir: String(text[isDirRange]) == "true"
            )
        }
    }

    private static func decodeJSONString(_ value: String) -> String {
        let json = "\"\(value)\""
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data)
        else {
            return value
        }
        return decoded
    }
}
