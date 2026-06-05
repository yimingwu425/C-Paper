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

    func fetchSubjects() async throws -> [Subject] {
        var subjects = PastPapersSubjectDirectory.seed.compactMap { code, directory -> Subject? in
            SubjectNormalizer.subject(fromDirectoryName: directory.relPath.split(separator: "/").last.map(String.init) ?? code)
        }
        var challengeSeen = false
        var errors: [String] = []

        for level in PastPapersLevel.allCases {
            let url = caieURL(level.viewPath)
            do {
                let html = String(decoding: try await networkClient.data(for: requestBuilder.get(url)), as: UTF8.self)
                if CloudflareChallengeDetector.isChallenge(html: html) {
                    challengeSeen = true
                    continue
                }
                let entries = PastPapersEntriesExtractor.entries(from: html)
                subjects.append(contentsOf: entries.compactMap(subject(from:)))
            } catch let error as NetworkClientError where error.isLikelyChallenge {
                challengeSeen = true
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let deduped = SubjectNormalizer.deduplicate(subjects)
        if !deduped.isEmpty {
            return deduped
        }
        if challengeSeen {
            throw PaperSourceError.sourceUnavailable("PastPapers 暂不可用：Cloudflare challenge 拦截了科目目录")
        }
        throw PaperSourceError.sourceUnavailable(
            "PastPapers 暂不可用：无法读取科目目录\(errors.isEmpty ? "" : "（\(errors.joined(separator: "; "))）")"
        )
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

    private func subject(from entry: PastPapersEntry) -> Subject? {
        guard entry.isDir else { return nil }
        return SubjectNormalizer.subject(fromDirectoryName: entry.name)
            ?? SubjectNormalizer.subject(fromDirectoryName: entry.relPath.split(separator: "/").last.map(String.init) ?? entry.relPath)
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
