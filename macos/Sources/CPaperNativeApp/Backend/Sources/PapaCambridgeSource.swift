import Foundation

struct PapaCambridgeSource: PaperSource {
    let id: PaperSourceID = .papaCambridge

    private let baseURL: URL
    private let networkClient: any NetworkClientProtocol
    private let requestBuilder: HTTPRequestBuilder

    init(
        baseURL: URL = BackendConstants.papaCambridgePastPapersBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder()
    ) {
        self.baseURL = baseURL
        self.networkClient = networkClient
        self.requestBuilder = requestBuilder
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        guard let slug = PapaCambridgeSubjectSlugs.slug(for: query.subjectCode) else {
            throw PaperSourceError.sourceUnavailable("PapaCambridge 暂不可用：缺少 \(query.subjectCode) 的目录映射，需要重新适配")
        }
        guard let year = query.year, let seasonPaths = seasonPaths(for: query) else {
            throw PaperSourceError.invalidResponse("PapaCambridge 需要指定年份和季度")
        }

        var lastError: Error?
        for seasonPath in seasonPaths {
            let sessionURL = baseURL
                .appendingPathComponent("papers")
                .appendingPathComponent("caie")
                .appendingPathComponent("\(slug)-\(year)-\(seasonPath)")

            do {
                let data = try await networkClient.data(for: requestBuilder.get(sessionURL))
                let html = String(decoding: data, as: UTF8.self)
                if CloudflareChallengeDetector.isChallenge(html: html) {
                    throw PaperSourceError.sourceUnavailable("PapaCambridge 暂不可用：Cloudflare challenge 拦截了目录页，需要重新适配")
                }
                let components = await verifiedComponents(from: html, query: query)
                if !components.isEmpty {
                    return SourceSearchResult(sourceID: id, components: components)
                }
                lastError = PaperSourceError.sourceUnavailable("PapaCambridge 暂不可用：目录页没有暴露可验证的 PDF 直链，需要重新适配")
            } catch let error as PaperSourceError {
                lastError = error
            } catch let error as NetworkClientError {
                if error.isLikelyChallenge {
                    lastError = PaperSourceError.sourceUnavailable("PapaCambridge 暂不可用：Cloudflare challenge 拦截了 HTTP 客户端，需要重新适配")
                } else {
                    lastError = error
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? PaperSourceError.sourceUnavailable("PapaCambridge 暂不可用：没有可下载试卷")
    }

    func healthCheck() async -> SourceHealth {
        do {
            _ = try await search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))
            return SourceHealth(sourceID: id, status: .available)
        } catch {
            return SourceHealth(sourceID: id, status: .unavailable, message: error.localizedDescription)
        }
    }

    private func verifiedComponents(from html: String, query: PaperSourceQuery) async -> [PaperComponent] {
        var components: [PaperComponent] = []
        for component in PapaCambridgePDFCandidateExtractor.components(from: html, baseURL: baseURL, sourceID: id) {
            guard component.matches(query), await pdfExists(at: component.url) else {
                continue
            }
            components.append(component)
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

    private func seasonPaths(for query: PaperSourceQuery) -> [String]? {
        switch query.seasonPrefix {
        case "m": ["march", "feb-march"]
        case "s": ["may-june"]
        case "w": ["oct-nov", "october-november"]
        default: nil
        }
    }
}

private enum PapaCambridgePDFCandidateExtractor {
    private static let filenamePattern = #"\b\d+_[mws]\d{2}_(?:qp|ms|ci|gt|er|ir|in|sr)(?:_\d+)?\.pdf\b"#

    static func components(from html: String, baseURL: URL, sourceID: PaperSourceID) -> [PaperComponent] {
        guard let regex = try? NSRegularExpression(pattern: filenamePattern, options: [.caseInsensitive]) else {
            return []
        }
        var seenFilenames = Set<String>()
        let range = NSRange(html.startIndex..., in: html)

        return regex.matches(in: html, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: html) else { return nil }
            let filename = String(html[swiftRange]).lowercased()
            guard seenFilenames.insert(filename).inserted,
                  let parsed = PaperFilenameParser.parse(filename)
            else {
                return nil
            }
            let url = baseURL
                .appendingPathComponent("directories")
                .appendingPathComponent("CAIE")
                .appendingPathComponent("CAIE-pastpapers")
                .appendingPathComponent("upload")
                .appendingPathComponent(filename)
            return .sourceComponent(sourceID: sourceID, parsed: parsed, url: url)
        }
    }
}

enum PapaCambridgeSubjectSlugs {
    private static let seed: [String: String] = [
        "9709": "as-and-a-level-mathematics-9709"
    ]

    static func slug(for subjectCode: String) -> String? {
        seed[subjectCode]
    }
}
