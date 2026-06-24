import Foundation
import XCTest
@testable import CPaperNativeApp

final class LiveSourceTests: XCTestCase {
    func testLiveSubjectFallbackCanPopulateSearchInputsWithoutFrankcie() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        let registry = SourceRegistry(sources: [
            UnavailableLiveSource(id: .frankcie),
            EasyPaperSource(),
            PastPapersSource(),
            PapaCambridgeSource()
        ])
        let subjects = try await registry.fetchSubjects()

        XCTAssertTrue(subjects.contains { $0.code == "9709" })
    }

    func testLiveAutomaticSearchFallbackReturnsDownloadablePDFWhenFrankcieIsUnavailable() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        let registry = SourceRegistry(sources: [
            UnavailableLiveSource(id: .frankcie),
            EasyPaperSource(),
            PastPapersSource(),
            PapaCambridgeSource()
        ])
        let result = try await registry.search(sampleQuery)
        let questionPaper = try XCTUnwrap(result.components.first { $0.filename == "9709_s23_qp_12.pdf" })

        XCTAssertFalse(result.components.isEmpty)
        XCTAssertEqual(result.attempts.first?.sourceID, .frankcie)
        XCTAssertEqual(result.attempts.first?.status, .failed)
        XCTAssertEqual(result.attempts.last?.status, .success)
        XCTAssertEqual(result.sourceID, questionPaper.sourceID)

        try await assertDownloadablePDF(questionPaper.url)
    }

    func testLiveManualEasyPaperSearchStaysOnSelectedSource() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        let registry = SourceRegistry(sources: [
            FrankcieSource(),
            EasyPaperSource(),
            PastPapersSource(),
            PapaCambridgeSource()
        ])
        let result = try await registry.search(sampleQuery, mode: .manual(.easyPaper))
        let questionPaper = try XCTUnwrap(result.components.first { $0.filename == "9709_s23_qp_12.pdf" })

        XCTAssertFalse(result.components.isEmpty)
        XCTAssertEqual(result.sourceID, .easyPaper)
        XCTAssertEqual(questionPaper.sourceID, .easyPaper)
        XCTAssertEqual(result.attempts.map(\.sourceID), [.easyPaper])
        XCTAssertEqual(result.attempts.map(\.status), [.success])

        try await assertDownloadablePDF(questionPaper.url)
    }

    func testLiveManualPapaCambridgeKeepsClearUnavailableReasonOrReturnsOwnPDF() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        let registry = SourceRegistry(sources: [
            FrankcieSource(),
            EasyPaperSource(),
            PastPapersSource(),
            PapaCambridgeSource()
        ])

        do {
            let result = try await registry.search(sampleQuery, mode: .manual(.papaCambridge))
            let questionPaper = try XCTUnwrap(result.components.first { $0.filename == "9709_s23_qp_12.pdf" })

            XCTAssertFalse(result.components.isEmpty)
            XCTAssertEqual(result.sourceID, .papaCambridge)
            XCTAssertEqual(questionPaper.sourceID, .papaCambridge)
            XCTAssertEqual(result.attempts.map(\.sourceID), [.papaCambridge])
            XCTAssertEqual(result.attempts.map(\.status), [.success])

            try await assertDownloadablePDF(questionPaper.url)
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("Unexpected manual PapaCambridge error: \(error)")
            }
            XCTAssertTrue(message.contains("PapaCambridge"))
            XCTAssertTrue(message.contains("暂不可用"))
        }
    }

    func testLiveEasyPaperSearchReturnsDownloadablePDF() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        let result = try await EasyPaperSource().search(sampleQuery)
        let questionPaper = try XCTUnwrap(result.components.first { $0.filename == "9709_s23_qp_12.pdf" })

        XCTAssertEqual(questionPaper.sourceID, .easyPaper)
        XCTAssertEqual(questionPaper.url.scheme, "https")
        XCTAssertNotNil(questionPaper.url.easyPaperFilePath)

        try await assertDownloadablePDF(questionPaper.url)
    }

    func testLivePastPapersReturnsPDFsOrClearUnavailableReason() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        do {
            let result = try await PastPapersSource().search(sampleQuery)
            let questionPaper = try XCTUnwrap(result.components.first { $0.filename == "9709_s23_qp_12.pdf" })
            XCTAssertTrue(result.components.allSatisfy { $0.url.absoluteString.lowercased().contains(".pdf") })
            try await assertDownloadablePDF(questionPaper.url)
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("PastPapers returned unexpected source error: \(error)")
            }
            XCTAssertTrue(message.contains("PastPapers"))
        }
    }

    func testLivePapaCambridgeReturnsPDFsOrClearUnavailableReason() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_SOURCE_TESTS"] == "1",
            "Set RUN_LIVE_SOURCE_TESTS=1 to verify third-party source websites."
        )

        do {
            let result = try await PapaCambridgeSource().search(sampleQuery)
            let questionPaper = try XCTUnwrap(result.components.first { $0.filename == "9709_s23_qp_12.pdf" })
            XCTAssertTrue(result.components.allSatisfy { $0.url.absoluteString.lowercased().contains(".pdf") })
            try await assertDownloadablePDF(questionPaper.url)
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("PapaCambridge returned unexpected source error: \(error)")
            }
            XCTAssertTrue(message.contains("PapaCambridge"))
        }
    }

    private var sampleQuery: PaperSourceQuery {
        PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun")
    }

    private func assertDownloadablePDF(_ url: URL) async throws {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
                XCTAssertEqual(httpResponse.statusCode, 200)
                XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
                return
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        throw try XCTUnwrap(lastError)
    }
}

private struct UnavailableLiveSource: PaperSource {
    let id: PaperSourceID

    func fetchSubjects() async throws -> [Subject] {
        throw PaperSourceError.sourceUnavailable("\(id.title) forced unavailable in live smoke")
    }

    func search(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        throw PaperSourceError.sourceUnavailable("\(id.title) forced unavailable in live smoke")
    }

    func healthCheck() async -> SourceHealth {
        SourceHealth(sourceID: id, status: .unavailable)
    }
}
