import Foundation

struct FrankcieSource: PaperSource {
    let id: PaperSourceID = .frankcie

    private let baseURL: URL
    private let networkClient: any NetworkClientProtocol
    private let requestBuilder: HTTPRequestBuilder

    init(
        baseURL: URL = BackendConstants.frankcieBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder()
    ) {
        self.baseURL = baseURL
        self.networkClient = networkClient
        self.requestBuilder = requestBuilder
    }

    func fetchSubjects() async throws -> [Subject] {
        let url = baseURL
            .appendingPathComponent("obj")
            .appendingPathComponent("Common")
            .appendingPathComponent("Subject")
            .appendingPathComponent("combo")
        let data = try await networkClient.data(for: requestBuilder.postForm(url, form: [:]))
        return try FrankcieSubjectParser.subjects(from: data)
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        let url = baseURL
            .appendingPathComponent("obj")
            .appendingPathComponent("Common")
            .appendingPathComponent("Fetch")
            .appendingPathComponent("renum")
        var form = ["subject": query.subjectCode]
        if let year = query.year {
            form["year"] = String(year)
        }
        if let season = query.season {
            form["season"] = season
        }

        let data = try await networkClient.data(for: requestBuilder.postForm(url, form: form))
        let components = try FrankcieResponseParser.components(from: data, baseURL: baseURL)
            .filter { $0.matches(query) }
        return SourceSearchResult(sourceID: id, components: components)
    }

    func healthCheck() async -> SourceHealth {
        let url = baseURL
            .appendingPathComponent("obj")
            .appendingPathComponent("Common")
            .appendingPathComponent("Subject")
            .appendingPathComponent("combo")
        do {
            _ = try await networkClient.data(for: requestBuilder.postForm(url, form: [:]))
            return SourceHealth(sourceID: id, status: .available)
        } catch {
            return SourceHealth(sourceID: id, status: .unavailable, message: error.localizedDescription)
        }
    }
}

enum FrankcieSubjectParser {
    static func subjects(from data: Data) throws -> [Subject] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PaperSourceError.invalidResponse("FrankCIE 返回了无效的科目 JSON")
        }

        let subjects = collectDictionaries(from: json).compactMap { dictionary -> Subject? in
            let stringDictionary = dictionary.compactMapValues { $0 as? String }
            return SubjectNormalizer.subject(fromFrankcie: stringDictionary)
        }
        return SubjectNormalizer.deduplicate(subjects)
    }

    private static func collectDictionaries(from value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap(collectDictionaries)
        }
        if let array = value as? [Any] {
            return array.flatMap(collectDictionaries)
        }
        return []
    }
}

enum FrankcieResponseParser {
    static func components(from data: Data, baseURL: URL) throws -> [PaperComponent] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PaperSourceError.invalidResponse("FrankCIE 返回了无效的 JSON")
        }

        var seen: Set<String> = []
        var components: [PaperComponent] = []

        for filename in collectFilenames(from: json) {
            guard !seen.contains(filename) else { continue }
            seen.insert(filename)

            guard let parsed = PaperFilenameParser.parse(filename) else {
                continue
            }

            let redirURL = baseURL
                .appendingPathComponent("obj")
                .appendingPathComponent("Common")
                .appendingPathComponent("Fetch")
                .appendingPathComponent("redir")
                .appendingPathComponent(filename)
            components.append(.sourceComponent(sourceID: .frankcie, parsed: parsed, url: redirURL))
        }

        return components.sorted { lhs, rhs in
            lhs.filename < rhs.filename
        }
    }

    private static func collectFilenames(from value: Any) -> [String] {
        if let array = value as? [Any] {
            return array.flatMap(collectFilenames)
        }

        guard let dictionary = value as? [String: Any] else {
            if let string = value as? String {
                return filenameCandidates(from: string)
            }
            return []
        }

        let preferredKeys = ["file", "filename", "fname", "name", "url", "href", "path"]
        let direct = preferredKeys.flatMap { key -> [String] in
            guard let string = dictionary[key] as? String else { return [] }
            return filenameCandidates(from: string)
        }
        return direct + dictionary.values.flatMap(collectFilenames)
    }

    private static func filenameCandidates(from value: String) -> [String] {
        let candidate: String
        if let url = URL(string: value), !url.lastPathComponent.isEmpty {
            candidate = url.lastPathComponent
        } else {
            candidate = value
        }

        let clean = (candidate.removingPercentEncoding ?? candidate)
            .components(separatedBy: "?")[0]
            .components(separatedBy: "#")[0]
        return clean.lowercased().hasSuffix(".pdf") ? [clean] : []
    }
}
