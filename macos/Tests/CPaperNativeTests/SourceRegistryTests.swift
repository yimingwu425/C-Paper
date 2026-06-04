import Foundation
import XCTest
@testable import CPaperNativeApp

final class SourceRegistryTests: XCTestCase {
    func testAutomaticModeFallsBackOnErrorsAndEmptyResultsInStableOrder() async throws {
        let parsed = PaperFilenameParser.parse("9709_s23_qp_12.pdf")!
        let success = PaperComponent.sourceComponent(
            sourceID: .easyPaper,
            parsed: parsed,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )

        let frankcie = StubSource(id: .frankcie) { _ in
            throw PaperSourceError.sourceUnavailable("Frankcie down")
        }
        let easyPaper = StubSource(id: .easyPaper) { _ in
            SourceSearchResult(sourceID: .easyPaper, components: [success])
        }
        let pastPapers = StubSource(id: .pastPapers) { _ in
            XCTFail("PastPapers should not be called after EasyPaper succeeds")
            return SourceSearchResult(sourceID: .pastPapers, components: [])
        }
        let papa = StubSource(id: .papaCambridge) { _ in
            XCTFail("PapaCambridge should not be called after EasyPaper succeeds")
            return SourceSearchResult(sourceID: .papaCambridge, components: [])
        }

        let registry = SourceRegistry(sources: [frankcie, easyPaper, pastPapers, papa])
        let result = try await registry.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.sourceID, .easyPaper)
        XCTAssertEqual(result.components, [success])
        XCTAssertEqual(result.attempts.map(\.sourceID), [.frankcie, .easyPaper])
        XCTAssertEqual(result.attempts.map(\.status), [.failed, .success])
        XCTAssertEqual(frankcie.callCount, 1)
        XCTAssertEqual(easyPaper.callCount, 1)
        XCTAssertEqual(pastPapers.callCount, 0)
        XCTAssertEqual(papa.callCount, 0)
    }

    func testManualModeDoesNotFallbackAndReportsUnavailableOnEmptyResults() async throws {
        let frankcie = StubSource(id: .frankcie) { _ in
            SourceSearchResult(sourceID: .frankcie, components: [])
        }
        let papa = StubSource(id: .papaCambridge) { _ in
            XCTFail("Manual mode must not fallback to PapaCambridge")
            return SourceSearchResult(sourceID: .papaCambridge, components: [])
        }

        let registry = SourceRegistry(sources: [frankcie, papa])
        do {
            _ = try await registry.search(
                PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"),
                mode: .manual(.frankcie)
            )
            XCTFail("Manual mode should report unavailable instead of returning an empty success")
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Frankcie"))
            XCTAssertTrue(message.contains("暂不可用"))
            XCTAssertTrue(message.contains("重新适配"))
        }
        XCTAssertEqual(frankcie.callCount, 1)
        XCTAssertEqual(papa.callCount, 0)
    }

    func testFetchSubjectsFallsBackWhenFrankcieSubjectListFails() async throws {
        let frankcie = StubSource(
            id: .frankcie,
            subjectHandler: {
                throw PaperSourceError.sourceUnavailable("Frankcie subjects down")
            },
            searchHandler: { _ in
                SourceSearchResult(sourceID: .frankcie, components: [])
            }
        )
        let easyPaper = StubSource(
            id: .easyPaper,
            subjectHandler: {
                [
                    Subject(code: "9709", name: "Mathematics"),
                    Subject(code: "9709", name: "Duplicate"),
                    Subject(code: "0620", name: "Chemistry")
                ]
            },
            searchHandler: { _ in
                SourceSearchResult(sourceID: .easyPaper, components: [])
            }
        )
        let pastPapers = StubSource(id: .pastPapers) { _ in
            XCTFail("PastPapers should not be called after EasyPaper subjects succeed")
            return SourceSearchResult(sourceID: .pastPapers, components: [])
        }

        let registry = SourceRegistry(sources: [frankcie, easyPaper, pastPapers])
        let subjects = try await registry.fetchSubjects()

        XCTAssertEqual(subjects.map(\.code), ["0620", "9709"])
        XCTAssertEqual(frankcie.subjectCallCount, 1)
        XCTAssertEqual(easyPaper.subjectCallCount, 1)
        XCTAssertEqual(pastPapers.subjectCallCount, 0)
    }
}

private final class StubSource: PaperSource, @unchecked Sendable {
    let id: PaperSourceID
    private let subjectHandler: @Sendable () async throws -> [Subject]
    private let handler: @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    private let lock = NSLock()
    private var calls = 0
    private var subjectCalls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    var subjectCallCount: Int {
        lock.withLock { subjectCalls }
    }

    init(
        id: PaperSourceID,
        subjectHandler: @escaping @Sendable () async throws -> [Subject] = {
            throw PaperSourceError.sourceUnavailable("Subjects unavailable")
        },
        searchHandler handler: @escaping @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    ) {
        self.id = id
        self.subjectHandler = subjectHandler
        self.handler = handler
    }

    convenience init(
        id: PaperSourceID,
        handler: @escaping @Sendable (PaperSourceQuery) async throws -> SourceSearchResult
    ) {
        self.init(id: id, searchHandler: handler)
    }

    func fetchSubjects() async throws -> [Subject] {
        lock.withLock {
            subjectCalls += 1
        }
        return try await subjectHandler()
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
