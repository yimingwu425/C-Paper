import Foundation
import XCTest
@testable import CPaperNativeApp

final class LiveSourceTests: XCTestCase {
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
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
    }
}
