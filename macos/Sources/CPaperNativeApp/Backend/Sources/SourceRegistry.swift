import Foundation

enum SourceRegistryMode: Equatable {
    case automatic
    case manual(PaperSourceID)
}

final class SourceRegistry {
    static let automaticOrder: [PaperSourceID] = [.frankcie, .papaCambridge, .pastPapers, .easyPaper]

    private let sources: [PaperSourceID: any PaperSource]
    private let automaticOrder: [PaperSourceID]

    init(
        sources: [any PaperSource] = [
            FrankcieSource(),
            PapaCambridgeSource(),
            PastPapersSource(),
            EasyPaperSource()
        ],
        automaticOrder: [PaperSourceID] = SourceRegistry.automaticOrder
    ) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.automaticOrder = automaticOrder
    }

    func source(for sourceID: PaperSourceID) -> (any PaperSource)? {
        sources[sourceID]
    }

    func search(_ query: PaperSourceQuery, mode: SourceRegistryMode = .automatic) async throws -> SourceSearchResult {
        switch mode {
        case .automatic:
            return try await searchAutomatically(query)
        case let .manual(sourceID):
            guard let source = sources[sourceID] else {
                throw PaperSourceError.unsupportedSource(sourceID)
            }
            var result = try await source.search(query)
            result.attempts = [.success(sourceID, count: result.components.count)]
            return result
        }
    }

    private func searchAutomatically(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        var attempts: [SourceAttempt] = []

        for sourceID in automaticOrder {
            guard let source = sources[sourceID] else { continue }

            do {
                var result = try await source.search(query)
                attempts.append(.success(sourceID, count: result.components.count))
                if !result.components.isEmpty {
                    result.attempts = attempts
                    return result
                }
            } catch {
                attempts.append(.failure(sourceID, error: error))
            }
        }

        throw PaperSourceError.allSourcesUnavailable(attempts)
    }
}
