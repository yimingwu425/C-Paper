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

    func testFrankcieReportsLocalizedInvalidJSONErrors() {
        XCTAssertThrowsError(
            try FrankcieResponseParser.components(
                from: Data("not-json".utf8),
                baseURL: URL(string: "https://cie.fraft.cn")!
            )
        ) { error in
            XCTAssertEqual(
                error as? PaperSourceError,
                .invalidResponse("FrankCIE 返回了无效的 JSON")
            )
            XCTAssertEqual(error.localizedDescription, "FrankCIE 返回了无效的 JSON")
        }

        XCTAssertThrowsError(
            try FrankcieSubjectParser.subjects(from: Data("not-json".utf8))
        ) { error in
            XCTAssertEqual(
                error as? PaperSourceError,
                .invalidResponse("FrankCIE 返回了无效的科目 JSON")
            )
            XCTAssertEqual(error.localizedDescription, "FrankCIE 返回了无效的科目 JSON")
        }
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

    func testPastPapersParsesNextEntriesIntoStaticPDFURLs() async throws {
        let html = #"""
        <html>
          <body>
            <script>
              self.__next_f.push(["{\"entries\":[{\"name\":\"9709_s23_ms_12.pdf\",\"relPath\":\"A-Level/Mathematics-9709/2023-May-June/9709_s23_ms_12.pdf\",\"isDir\":false},{\"name\":\"9709_s23_qp_12.pdf\",\"relPath\":\"A-Level/Mathematics-9709/2023-May-June/9709_s23_qp_12.pdf\",\"isDir\":false},{\"name\":\"9709_s23_video.mp4\",\"relPath\":\"A-Level/Mathematics-9709/2023-May-June/9709_s23_video.mp4\",\"isDir\":false}]}"]);
            </script>
          </body>
        </html>
        """#.data(using: .utf8)!

        let client = MockNetworkClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/caie/a-level/mathematics-9709/2023-may-june")
            return html
        }
        let source = PastPapersSource(baseURL: URL(string: "https://pastpapers.co")!, networkClient: client)

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.sourceID, .pastPapers)
        XCTAssertEqual(result.components.map(\.filename), ["9709_s23_ms_12.pdf", "9709_s23_qp_12.pdf"])
        XCTAssertEqual(
            result.components.map(\.url.absoluteString),
            [
                "https://pastpapers.co/caie/A-Level/Mathematics-9709/2023-May-June/9709_s23_ms_12.pdf",
                "https://pastpapers.co/caie/A-Level/Mathematics-9709/2023-May-June/9709_s23_qp_12.pdf"
            ]
        )
    }

    func testPastPapersParsesEntriesWhenJSONKeyOrderChanges() async throws {
        let html = #"""
        <html>
          <body>
            <script>
              self.__next_f.push(["{\"entries\":[{\"relPath\":\"A-Level/Mathematics-9709/2023-May-June/9709_s23_ms_12.pdf\",\"isDir\":false,\"name\":\"9709_s23_ms_12.pdf\"},{\"isDir\":false,\"name\":\"9709_s23_qp_12.pdf\",\"relPath\":\"A-Level/Mathematics-9709/2023-May-June/9709_s23_qp_12.pdf\"}]}"]);
            </script>
          </body>
        </html>
        """#.data(using: .utf8)!

        let client = MockNetworkClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/caie/a-level/mathematics-9709/2023-may-june")
            return html
        }
        let source = PastPapersSource(baseURL: URL(string: "https://pastpapers.co")!, networkClient: client)

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.components.map(\.filename), ["9709_s23_ms_12.pdf", "9709_s23_qp_12.pdf"])
    }

    func testPastPapersFallsBackToVerifiedStaticPDFsWhenDirectoryIsChallenged() async throws {
        let client = MockNetworkClient { request in
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.url?.path, "/caie/a-level/mathematics-9709/2023-may-june")
                return Data("<title>Just a moment...</title>".utf8)
            }

            XCTAssertEqual(request.httpMethod, "HEAD")
            let path = request.url?.path ?? ""
            if path.hasSuffix("/9709_s23_qp_12.pdf") || path.hasSuffix("/9709_s23_ms_12.pdf") {
                return Data()
            }
            throw NetworkClientError.httpStatus(404)
        }
        let source = PastPapersSource(baseURL: URL(string: "https://pastpapers.co")!, networkClient: client)

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(Set(result.components.map(\.filename)), ["9709_s23_qp_12.pdf", "9709_s23_ms_12.pdf"])
        XCTAssertTrue(result.components.allSatisfy { $0.url.host == "pastpapers.co" })
    }

    func testPastPapersDiscoversNonSeedSubjectFromLevelEntries() async throws {
        let emptyEntries = #"{"entries":[]}"#.data(using: .utf8)!
        let igcseEntries = #"""
        <script>{"entries":[{"name":"Chemistry-0620","relPath":"IGCSE/Chemistry-0620","isDir":true}]}</script>
        """#.data(using: .utf8)!
        let paperEntries = #"""
        <script>{"entries":[{"name":"0620_s23_qp_12.pdf","relPath":"IGCSE/Chemistry-0620/2023-May-June/0620_s23_qp_12.pdf","isDir":false}]}</script>
        """#.data(using: .utf8)!
        let client = MockNetworkClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            switch request.url?.path {
            case "/caie/a-level":
                return emptyEntries
            case "/caie/igcse":
                return igcseEntries
            case "/caie/igcse/chemistry-0620/2023-may-june":
                return paperEntries
            default:
                throw NetworkClientError.httpStatus(404)
            }
        }
        let source = PastPapersSource(baseURL: URL(string: "https://pastpapers.co")!, networkClient: client)

        let result = try await source.search(PaperSourceQuery(subjectCode: "0620", year: 2023, season: "Jun"))

        XCTAssertEqual(result.components.map(\.filename), ["0620_s23_qp_12.pdf"])
        XCTAssertEqual(result.components.first?.url.absoluteString, "https://pastpapers.co/caie/IGCSE/Chemistry-0620/2023-May-June/0620_s23_qp_12.pdf")
    }

    func testPapaCambridgeBuildsVerifiedDirectPDFURLsFromSessionPage() async throws {
        let html = #"""
        <html>
          <body>
            <a href="/viewer/caie/as-and-a-level-mathematics-9709-2023-may-june/9709_s23_qp_12.pdf">9709_s23_qp_12.pdf</a>
            <a href="/viewer/caie/syllabus.pdf">syllabus.pdf</a>
          </body>
        </html>
        """#.data(using: .utf8)!
        let client = MockNetworkClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/papers/caie/as-and-a-level-mathematics-9709-2023-may-june"):
                return html
            case ("HEAD", "/directories/CAIE/CAIE-pastpapers/upload/9709_s23_qp_12.pdf"):
                return Data()
            default:
                throw NetworkClientError.httpStatus(404)
            }
        }
        let source = PapaCambridgeSource(baseURL: URL(string: "https://pastpapers.papacambridge.com")!, networkClient: client)

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.components.map(\.filename), ["9709_s23_qp_12.pdf"])
        XCTAssertEqual(result.components.first?.url.absoluteString, "https://pastpapers.papacambridge.com/directories/CAIE/CAIE-pastpapers/upload/9709_s23_qp_12.pdf")
    }

    func testPapaCambridgeFallsBackToGETWhenHeadProbeIsBlocked() async throws {
        let html = #"""
        <html>
          <body>
            <a href="/viewer/caie/as-and-a-level-mathematics-9709-2023-may-june/9709_s23_qp_12.pdf">9709_s23_qp_12.pdf</a>
          </body>
        </html>
        """#.data(using: .utf8)!
        let client = MockNetworkClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/papers/caie/as-and-a-level-mathematics-9709-2023-may-june"):
                return html
            case ("HEAD", "/directories/CAIE/CAIE-pastpapers/upload/9709_s23_qp_12.pdf"):
                throw NetworkClientError.httpStatus(405)
            case ("GET", "/directories/CAIE/CAIE-pastpapers/upload/9709_s23_qp_12.pdf"):
                return Data("pdf".utf8)
            default:
                throw NetworkClientError.httpStatus(404)
            }
        }
        let source = PapaCambridgeSource(baseURL: URL(string: "https://pastpapers.papacambridge.com")!, networkClient: client)

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertEqual(result.components.map(\.filename), ["9709_s23_qp_12.pdf"])
    }

    func testPapaCambridgeReportsCloudflareChallengeAsUnavailable() async throws {
        let client = MockNetworkClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return Data("<html><title>Just a moment...</title></html>".utf8)
        }
        let source = PapaCambridgeSource(baseURL: URL(string: "https://pastpapers.papacambridge.com")!, networkClient: client)

        do {
            _ = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))
            XCTFail("PapaCambridge challenge should be reported as unavailable")
        } catch let error as PaperSourceError {
            guard case let .sourceUnavailable(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("PapaCambridge"))
            XCTAssertTrue(message.contains("Cloudflare"))
            XCTAssertTrue(message.contains("暂不可用"))
        }
    }

    func testEasyPaperSearchUsesEncryptedDirectoryAPIAndStoresRefreshableFilePath() async throws {
        let rootResponse = "iQ9xgnNO3+fFvnA+5LNnpwktR8VRKwQIAeZV+sqpHltExpiP9r1eEkMVXkF%fo@~[C.4L1.ZDcppk0Ow7Y%fo@~[C.4L1.ZDcp3kS5AUFLQI4RT7J6rJcl0AbExmVJn1L612XmYtYQeUDjDPxJvHPjcLIuPpmaOLPc%fo@~[C.4L1.ZDcpKxrszyh36JWH3ofbUG5AiMIY7PupPAvDS4MkYc="
        let summerResponse = "iQ9xgnNO3+fFvnA+5LNnpwktR8VRKwQIAeZV+sqpHluqzCkKYOJ9QQvO4EZuuZfAyvpHjMEDJgyN5J%fo@~[C.4L1.ZDcpowuVTZPIZ7M5MnMtyHv2AjUZA7izbzXW5mJd6ygD3Wj4tZtd21z+JBxYkL0FyUcRcr8erMe1iVUlNKhoPr3ay0P8ADUAt0BVpuCGWKpyGMYPM8+C7Um+IwLbl0wnAuUTOR1pE7EqAgq5h+cEhQnJ68zdvPRs6tyttwaVffO0NHeMl5YtiOsI1JGxSvYj51zKGk3Io1KDPYqfWyDpiXtb6rERO8jA="
        let calls = CallRecorder()
        let client = MockNetworkClient { request in
            await calls.append(request.url?.path ?? "")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.path.contains("/paperdownload/dir_v3/") == true)
            return Data((await calls.count) == 1 ? rootResponse.utf8 : summerResponse.utf8)
        }
        let source = EasyPaperSource(
            apiBaseURL: URL(string: "https://server.easy-paper.com")!,
            pdfBaseURL: URL(string: "https://server.easy-paper.com")!,
            networkClient: client,
            crypto: EasyPaperCrypto(
                randomString: { String(repeating: "A", count: $0) },
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        )

        let result = try await source.search(PaperSourceQuery(subjectCode: "9709", year: 2023, season: "Jun"))

        XCTAssertTrue(result.components.contains { $0.filename == "9709_s23_qp_12.pdf" })
        XCTAssertTrue(result.components.contains { $0.filename == "9709_s23_ms_12.pdf" })
        XCTAssertTrue(result.components.contains { $0.filename == "9709_s23_gt.pdf" })
        XCTAssertTrue(result.components.allSatisfy { $0.url.path.contains("/paperdownload/dir_v3/") })
        XCTAssertEqual(
            result.components.first?.url.easyPaperFilePath,
            "CAIE|AS and A Level|Mathematics (9709)|2023|Summer|9709_s23_qp_12.pdf"
        )
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

private actor CallRecorder {
    private var values: [String] = []

    var count: Int {
        values.count
    }

    func append(_ value: String) {
        values.append(value)
    }
}
