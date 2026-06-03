import Foundation
import XCTest
@testable import CPaperNativeApp

final class SourceRegistryTests: XCTestCase {
    func testAutomaticModeFallsBackOnErrorsAndEmptyResultsInStableOrder() async throws {
        let parsed = PaperFilenameParser.parse("9709_s23_qp_12.pdf")!
        let success = PaperComponent.sourceComponent(
            sourceID: .pastPapers,
            parsed: parsed,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )

        let frankcie = StubSource(id: .frankcie) { _ in
            throw PaperSourceError.sourceUnavailable("Frankcie down")
        }
        let papa = StubSource(id: .papaCambridge) { _ in
            SourceSearchResult(sourceID: .papaCambridge, components: [])
        }
        let pastPapers = StubSource(id: .pastPapers) { _ in
            SourceSearchResult(sourceID: .pastPapers, components: [success])
        }
        let easyPaper = StubSource(id: .easyPaper) { _ in
            XCTFail("EasyPaper should not be called after a successful fallback")
            return SourceSearchResult(sourceID: .easyPaper, components: [])
        }

        let registry = SourceRegistry(sources: [frankcie, papa, pastPapers, easyPaper])
        let result = try await registry.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.sourceID, .pastPapers)
        XCTAssertEqual(result.components, [success])
        XCTAssertEqual(result.attempts.map(\.sourceID), [.frankcie, .papaCambridge, .pastPapers])
        XCTAssertEqual(result.attempts.map(\.status), [.failed, .empty, .success])
        XCTAssertEqual(frankcie.callCount, 1)
        XCTAssertEqual(papa.callCount, 1)
        XCTAssertEqual(pastPapers.callCount, 1)
        XCTAssertEqual(easyPaper.callCount, 0)
    }

    func testManualModeDoesNotFallbackOnEmptyResults() async throws {
        let frankcie = StubSource(id: .frankcie) { _ in
            SourceSearchResult(sourceID: .frankcie, components: [])
        }
        let papa = StubSource(id: .papaCambridge) { _ in
            XCTFail("Manual mode must not fallback to PapaCambridge")
            return SourceSearchResult(sourceID: .papaCambridge, components: [])
        }

        let registry = SourceRegistry(sources: [frankcie, papa])
        let result = try await registry.search(
            PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"),
            mode: .manual(.frankcie)
        )

        XCTAssertEqual(result.sourceID, .frankcie)
        XCTAssertTrue(result.components.isEmpty)
        XCTAssertEqual(result.attempts.map(\.sourceID), [.frankcie])
        XCTAssertEqual(result.attempts.map(\.status), [.empty])
        XCTAssertEqual(frankcie.callCount, 1)
        XCTAssertEqual(papa.callCount, 0)
    }
}

private final class StubSource: PaperSource, @unchecked Sendable {
    let id: PaperSourceID
    private let handler: @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    init(
        id: PaperSourceID,
        handler: @escaping @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    ) {
        self.id = id
        self.handler = handler
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        lock.withLock {
            calls += 1
        }
        return try await handler(query)
    }

    func healthCheck() async -> SourceHealth {
        SourceHealth(sourceID: id, status: .available)
    }
}
