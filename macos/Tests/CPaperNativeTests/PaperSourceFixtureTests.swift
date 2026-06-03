import Foundation
import XCTest
@testable import CPaperNativeApp

final class PaperSourceFixtureTests: XCTestCase {
    func testFrankcieParsesRenumJSONIntoRedirComponents() async throws {
        let fixture = """
        {
          "rows": [
            {"file": "9709_s23_qp_12.pdf"},
            {"name": "9709_s23_ms_12.pdf"},
            {"url": "https://example.test/files/not_a_cie_file.pdf"}
          ]
        }
        """.data(using: .utf8)!

        let client = MockNetworkClient { request in
            XCTAssertEqual(request.url?.path, "/obj/Common/Fetch/renum")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("subject=9709"))
            XCTAssertTrue(body.contains("year=2023"))
            XCTAssertTrue(body.contains("season=Jun"))
            return fixture
        }

        let source = FrankcieSource(
            baseURL: URL(string: "https://cie.fraft.cn")!,
            networkClient: client
        )

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.sourceID, .frankcie)
        XCTAssertEqual(result.components.map(\.filename), ["9709_s23_ms_12.pdf", "9709_s23_qp_12.pdf"])
        XCTAssertTrue(result.components.allSatisfy { $0.url.path.hasPrefix("/obj/Common/Fetch/redir/") })
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertNotNil(result.groups.first?.qp)
        XCTAssertNotNil(result.groups.first?.ms)
    }

    func testHTMLPaperLinkExtractorHandlesRelativePDFLinksAndIgnoresUnparseableNames() throws {
        let html = """
        <html>
          <body>
            <a href="/papers/9709_s23_qp_12.pdf">Question paper</a>
            <a href="../mark-schemes/9709_s23_ms_12.pdf?download=1&amp;source=test">Mark scheme</a>
            <a href="https://cdn.example.test/9709_s23_qp_12.pdf">Same filename on another host</a>
            <a href="/papers/syllabus.pdf">Syllabus</a>
            <a href="/papers/9709_s23_video.mp4">Video</a>
          </body>
        </html>
        """

        let extractor = HTMLPaperLinkExtractor()
        let components = try extractor.extractPDFLinks(
            from: html,
            baseURL: URL(string: "https://example.test/subjects/9709/index.html")!,
            sourceID: .papaCambridge
        )

        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(Set(components.map(\.filename)), ["9709_s23_qp_12.pdf", "9709_s23_ms_12.pdf"])
        XCTAssertTrue(components.contains { $0.url.absoluteString == "https://example.test/papers/9709_s23_qp_12.pdf" })
        XCTAssertTrue(components.contains { $0.url.absoluteString.contains("/mark-schemes/9709_s23_ms_12.pdf") })
        XCTAssertTrue(components.allSatisfy { $0.subjectCode == "9709" && $0.year == 2023 && $0.seasonName == "Jun" })
    }
}

private final class MockNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) async throws -> Data

    init(handler: @escaping @Sendable (URLRequest) async throws -> Data) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> Data {
        try await handler(request)
    }
}
