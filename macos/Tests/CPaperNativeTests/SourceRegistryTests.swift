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
            XCTAssertTrue(message.contains("FrankCIE"))
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

    func testManualSubjectModeDoesNotFallbackAndReportsUnavailableOnEmptyResults() async throws {
        let frankcie = StubSource(
            id: .frankcie,
            subjectHandler: {
                []
            },
            searchHandler: { _ in
                SourceSearchResult(sourceID: .frankcie, components: [])
            }
        )
        let easyPaper = StubSource(
            id: .easyPaper,
            subjectHandler: {
                XCTFail("Manual subject mode must not fallback to EasyPaper")
                return []
            },
            searchHandler: { _ in
                SourceSearchResult(sourceID: .easyPaper, components: [])
            }
        )

        let registry = SourceRegistry(sources: [frankcie, easyPaper])
        do {
            _ = try await registry.fetchSubjects(mode: .manual(.frankcie))
            XCTFail("Manual subject mode should report unavailable instead of returning an empty success")
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("FrankCIE"))
            XCTAssertTrue(message.contains("暂不可用"))
            XCTAssertTrue(message.contains("科目目录"))
        }

        XCTAssertEqual(frankcie.subjectCallCount, 1)
        XCTAssertEqual(easyPaper.subjectCallCount, 0)
    }

    func testManualModePreservesSelectedSourceUnavailableReasonWithoutFallback() async throws {
        let papa = StubSource(id: .papaCambridge) { _ in
            throw PaperSourceError.sourceUnavailable("PapaCambridge 暂不可用：Cloudflare challenge 拦截了目录页，需要重新适配")
        }
        let easyPaper = StubSource(id: .easyPaper) { _ in
            XCTFail("Manual mode must not fallback to EasyPaper after PapaCambridge fails")
            return SourceSearchResult(sourceID: .easyPaper, components: [])
        }

        let registry = SourceRegistry(sources: [papa, easyPaper])
        do {
            _ = try await registry.search(
                PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"),
                mode: .manual(.papaCambridge)
            )
            XCTFail("Manual mode should preserve the selected source failure")
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("PapaCambridge"))
            XCTAssertTrue(message.contains("Cloudflare"))
            XCTAssertTrue(message.contains("重新适配"))
        }

        XCTAssertEqual(papa.callCount, 1)
        XCTAssertEqual(easyPaper.callCount, 0)
    }

    func testSourceAttemptMessagesUseLocalizedFallbackText() {
        XCTAssertEqual(SourceAttempt.success(.frankcie, count: 2).message, "2 个结果")
        XCTAssertEqual(SourceAttempt.success(.frankcie, count: 0).message, "无结果")
        XCTAssertEqual(
            SourceAttempt(
                sourceID: .frankcie,
                status: .failed,
                resultCount: 0,
                errorMessage: nil,
                durationMilliseconds: nil
            ).message,
            "失败"
        )
    }

    func testSourceAttemptDiagnosticMessageIncludesMeasuredDurationWhenPresent() {
        let attempt = SourceAttempt.success(.pastPapers, count: 0, durationMilliseconds: 48213)

        XCTAssertEqual(attempt.message, "无结果")
        XCTAssertEqual(attempt.diagnosticMessage, "无结果（耗时 48213 ms）")
    }

    func testAutomaticModeRecordsAttemptDurations() async throws {
        let frankcie = StubSource(id: .frankcie) { _ in
            try await Task.sleep(nanoseconds: 15_000_000)
            throw PaperSourceError.sourceUnavailable("Frankcie down")
        }
        let easyPaper = StubSource(id: .easyPaper) { _ in
            try await Task.sleep(nanoseconds: 15_000_000)
            return SourceSearchResult(sourceID: .easyPaper, components: [])
        }
        let papa = StubSource(id: .papaCambridge) { _ in
            try await Task.sleep(nanoseconds: 15_000_000)
            throw PaperSourceError.sourceUnavailable("PapaCambridge down")
        }

        let registry = SourceRegistry(sources: [frankcie, easyPaper, papa], automaticOrder: [.frankcie, .easyPaper, .papaCambridge])

        do {
            _ = try await registry.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))
            XCTFail("Expected all sources to be unavailable")
        } catch let error as PaperSourceError {
            guard case let .allSourcesUnavailable(attempts) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(attempts.map(\.sourceID), [.frankcie, .easyPaper, .papaCambridge])
            XCTAssertEqual(attempts.map(\.status), [.failed, .empty, .failed])
            XCTAssertTrue(attempts.allSatisfy { ($0.durationMilliseconds ?? -1) >= 0 })
            XCTAssertTrue(attempts.allSatisfy { $0.durationMilliseconds != nil })
        }
    }

    func testAutomaticModeTimesOutSlowSearchAndFallsBackToNextSource() async throws {
        let parsed = PaperFilenameParser.parse("9709_s23_qp_12.pdf")!
        let success = PaperComponent.sourceComponent(
            sourceID: .easyPaper,
            parsed: parsed,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )
        let slowFrankcie = StubSource(id: .frankcie) { _ in
            try await Task.sleep(nanoseconds: 200_000_000)
            return SourceSearchResult(sourceID: .frankcie, components: [])
        }
        let easyPaper = StubSource(id: .easyPaper) { _ in
            SourceSearchResult(sourceID: .easyPaper, components: [success])
        }

        let registry = SourceRegistry(
            sources: [slowFrankcie, easyPaper],
            automaticOrder: [.frankcie, .easyPaper],
            automaticAttemptTimeout: 0.05
        )

        let result = try await registry.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.sourceID, .easyPaper)
        XCTAssertEqual(result.attempts.map(\.sourceID), [.frankcie, .easyPaper])
        XCTAssertEqual(result.attempts.map(\.status), [.failed, .success])
        XCTAssertTrue(result.attempts[0].message.contains("搜索超时"))
        XCTAssertNotNil(result.attempts[0].durationMilliseconds)
        XCTAssertGreaterThanOrEqual(result.attempts[0].durationMilliseconds ?? 0, 45)
    }

    func testAutomaticSubjectFetchTimesOutSlowSourceAndFallsBack() async throws {
        let slowFrankcie = StubSource(
            id: .frankcie,
            subjectHandler: {
                try await Task.sleep(nanoseconds: 200_000_000)
                return [Subject(code: "9709", name: "Mathematics")]
            },
            searchHandler: { _ in
                SourceSearchResult(sourceID: .frankcie, components: [])
            }
        )
        let easyPaper = StubSource(
            id: .easyPaper,
            subjectHandler: {
                [Subject(code: "0620", name: "Chemistry")]
            },
            searchHandler: { _ in
                SourceSearchResult(sourceID: .easyPaper, components: [])
            }
        )

        let registry = SourceRegistry(
            sources: [slowFrankcie, easyPaper],
            automaticOrder: [.frankcie, .easyPaper],
            automaticAttemptTimeout: 0.05
        )

        let subjects = try await registry.fetchSubjects()

        XCTAssertEqual(subjects.map(\.code), ["0620"])
        XCTAssertEqual(slowFrankcie.subjectCallCount, 1)
        XCTAssertEqual(easyPaper.subjectCallCount, 1)
    }

    func testManualModeDoesNotApplyAutomaticTimeoutBoundary() async throws {
        let parsed = PaperFilenameParser.parse("9709_s23_qp_12.pdf")!
        let success = PaperComponent.sourceComponent(
            sourceID: .papaCambridge,
            parsed: parsed,
            url: URL(string: "https://example.test/9709_s23_qp_12.pdf")!
        )
        let slowPapa = StubSource(id: .papaCambridge) { _ in
            try await Task.sleep(nanoseconds: 120_000_000)
            return SourceSearchResult(sourceID: .papaCambridge, components: [success])
        }

        let registry = SourceRegistry(
            sources: [slowPapa],
            automaticOrder: [.papaCambridge],
            automaticAttemptTimeout: 0.05
        )

        let result = try await registry.search(
            PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"),
            mode: .manual(.papaCambridge)
        )

        XCTAssertEqual(result.sourceID, .papaCambridge)
        XCTAssertEqual(result.attempts.map(\.status), [.success])
        XCTAssertEqual(slowPapa.callCount, 1)
    }

    func testPaperSourceErrorsUseLocalizedDescriptions() {
        XCTAssertEqual(PaperSourceError.unsupportedSource(.easyPaper).errorDescription, "不支持的来源：EasyPaper")
        XCTAssertEqual(
            PaperSourceError.allSourcesUnavailable([
                .failure(.frankcie, error: PaperSourceError.sourceUnavailable("boom")),
                .success(.easyPaper, count: 0)
            ]).errorDescription,
            "所有来源均不可用（共尝试 2 个）"
        )
    }

    func testBackendNoResultsDescriptionIncludesAttemptDuration() {
        let error = BackendError.noResults([
            .failure(.frankcie, error: PaperSourceError.sourceUnavailable("无结果"), durationMilliseconds: 18750),
            .success(.easyPaper, count: 0, durationMilliseconds: 420)
        ])

        XCTAssertEqual(
            error.errorDescription,
            "未找到试卷（FrankCIE: 无结果（耗时 18750 ms）；EasyPaper: 无结果（耗时 420 ms））"
        )
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
