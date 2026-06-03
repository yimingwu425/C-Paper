import Foundation

struct PapaCambridgeSource: PaperSource {
    let id: PaperSourceID = .papaCambridge
    private let provider: HTMLProviderSource

    init(
        entryURL: URL = BackendConstants.papaCambridgeBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        extractor: HTMLPaperLinkExtractor = HTMLPaperLinkExtractor()
    ) {
        self.provider = HTMLProviderSource(id: .papaCambridge, entryURL: entryURL, networkClient: networkClient, extractor: extractor)
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        try await provider.search(query)
    }

    func healthCheck() async -> SourceHealth {
        await provider.healthCheck()
    }
}

struct PastPapersSource: PaperSource {
    let id: PaperSourceID = .pastPapers
    private let provider: HTMLProviderSource

    init(
        entryURL: URL = BackendConstants.pastPapersBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        extractor: HTMLPaperLinkExtractor = HTMLPaperLinkExtractor()
    ) {
        self.provider = HTMLProviderSource(id: .pastPapers, entryURL: entryURL, networkClient: networkClient, extractor: extractor)
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        try await provider.search(query)
    }

    func healthCheck() async -> SourceHealth {
        await provider.healthCheck()
    }
}

struct EasyPaperSource: PaperSource {
    let id: PaperSourceID = .easyPaper
    private let provider: HTMLProviderSource

    init(
        entryURL: URL = BackendConstants.easyPaperBaseURL,
        networkClient: any NetworkClientProtocol = NetworkClient(),
        extractor: HTMLPaperLinkExtractor = HTMLPaperLinkExtractor()
    ) {
        self.provider = HTMLProviderSource(id: .easyPaper, entryURL: entryURL, networkClient: networkClient, extractor: extractor)
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        try await provider.search(query)
    }

    func healthCheck() async -> SourceHealth {
        await provider.healthCheck()
    }
}

private struct HTMLProviderSource: PaperSource {
    let id: PaperSourceID
    let entryURL: URL
    let networkClient: any NetworkClientProtocol
    let extractor: HTMLPaperLinkExtractor
    let requestBuilder: HTTPRequestBuilder

    init(
        id: PaperSourceID,
        entryURL: URL,
        networkClient: any NetworkClientProtocol,
        extractor: HTMLPaperLinkExtractor,
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder()
    ) {
        self.id = id
        self.entryURL = entryURL
        self.networkClient = networkClient
        self.extractor = extractor
        self.requestBuilder = requestBuilder
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        let htmlData = try await networkClient.data(for: requestBuilder.get(entryURL))
        let components = try extractor.extractPDFLinks(
            from: String(decoding: htmlData, as: UTF8.self),
            baseURL: entryURL,
            sourceID: id
        )
        .filter { $0.matches(query) }

        guard !components.isEmpty else {
            throw PaperSourceError.sourceUnavailable("\(id.title) did not expose direct CIE PDF links")
        }

        return SourceSearchResult(sourceID: id, components: components)
    }

    func healthCheck() async -> SourceHealth {
        do {
            let htmlData = try await networkClient.data(for: requestBuilder.get(entryURL))
            let components = try extractor.extractPDFLinks(
                from: String(decoding: htmlData, as: UTF8.self),
                baseURL: entryURL,
                sourceID: id
            )
            guard !components.isEmpty else {
                return SourceHealth(sourceID: id, status: .unavailable, message: "No direct CIE PDF links found")
            }
            return SourceHealth(sourceID: id, status: .available)
        } catch {
            return SourceHealth(sourceID: id, status: .unavailable, message: error.localizedDescription)
        }
    }
}
