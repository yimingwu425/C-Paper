import Foundation
import XCTest
@testable import CPaperNativeApp

final class HTTPFileTransferClientTests: XCTestCase {
    override func tearDown() {
        MockTransferURLProtocol.reset()
        super.tearDown()
    }

    func testTransferWritesResponseBodyToDestinationFile() async throws {
        let destinationURL = makeTransferDestinationURL()
        let payload = Data("shared-transfer".utf8)
        let requests = RequestRecorder()
        let progress = ProgressRecorder()
        let session = makeTransferSession()

        MockTransferURLProtocol.setHandler { request in
            await requests.record(request)
            return MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(payload.count)"]
                )!,
                chunks: [payload]
            )
        }

        let client = HTTPFileTransferClient(session: session)

        try await client.transfer(
            from: URL(string: "https://example.test/files/paper.pdf")!,
            to: destinationURL
        ) { value in
            await progress.record(value)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), payload)
        let firstRequest = await requests.first()
        let request = try XCTUnwrap(firstRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), HTTPRequestBuilder.defaultUserAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "*/*")
        let lastProgress = await progress.lastValue()
        XCTAssertEqual(lastProgress, 1)
    }

    func testTransferThrowsForNon2xxResponse() async throws {
        let destinationURL = makeTransferDestinationURL()
        let session = makeTransferSession()

        MockTransferURLProtocol.setHandler { request in
            MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "3"]
                )!,
                chunks: [Data("nope".utf8)]
            )
        }

        let client = HTTPFileTransferClient(session: session)

        do {
            try await client.transfer(
                from: URL(string: "https://example.test/files/missing.pdf")!,
                to: destinationURL
            ) { _ in }
            XCTFail("Expected HTTP status error")
        } catch let error as NetworkClientError {
            XCTAssertEqual(error, .httpStatus(404))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testTransferAppliesProxyConfigurationWhenBuildingSession() async throws {
        let destinationURL = makeTransferDestinationURL()
        let payload = Data("ok".utf8)
        let configurationRecorder = SessionConfigurationRecorder()

        let client = HTTPFileTransferClient(
            proxy: ProxyConfiguration(rawValue: "http://user:pass@proxy.example.com:8080"),
            sessionFactory: { configuration in
                configurationRecorder.record(configuration)
                return makeTransferSession(configuration: configuration)
            }
        )

        MockTransferURLProtocol.setHandler { request in
            MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(payload.count)"]
                )!,
                chunks: [payload]
            )
        }

        try await client.transfer(
            from: URL(string: "https://example.test/files/paper.pdf")!,
            to: destinationURL
        ) { _ in }

        let configuration = try XCTUnwrap(configurationRecorder.first())
        let dictionary = try XCTUnwrap(configuration.connectionProxyDictionary)
        XCTAssertEqual(dictionary["HTTPEnable"] as? Int, 1)
        XCTAssertEqual(dictionary["HTTPProxy"] as? String, "proxy.example.com")
        XCTAssertEqual(dictionary["HTTPPort"] as? Int, 8080)
        XCTAssertEqual(dictionary["HTTPProxyUsername"] as? String, "user")
        XCTAssertEqual(dictionary["HTTPProxyPassword"] as? String, "pass")
    }

    func testTransferReportsInitialIntermediateAndFinalProgress() async throws {
        let destinationURL = makeTransferDestinationURL()
        let payload = Data(repeating: 0x41, count: 128_000)
        let progress = ProgressRecorder()
        let session = makeTransferSession()

        MockTransferURLProtocol.setHandler { request in
            MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(payload.count)"]
                )!,
                chunks: [payload]
            )
        }

        let client = HTTPFileTransferClient(session: session)

        try await client.transfer(
            from: URL(string: "https://example.test/files/large.pdf")!,
            to: destinationURL
        ) { value in
            await progress.record(value)
        }

        let values = await progress.compactValues()
        XCTAssertEqual(try XCTUnwrap(values.first), 0, accuracy: 0.0001)
        XCTAssertTrue(values.contains(where: { $0 > 0 && $0 < 1 }))
        XCTAssertEqual(try XCTUnwrap(values.last), 1, accuracy: 0.0001)
    }

    func testTransferRemovesPartialFileWhenCancelled() async throws {
        let destinationURL = makeTransferDestinationURL()
        let progress = ProgressRecorder()
        let session = makeTransferSession()

        MockTransferURLProtocol.setHandler { request in
            MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "192000"]
                )!,
                chunks: [
                    Data(repeating: 0x41, count: 64_000),
                    Data(repeating: 0x42, count: 64_000),
                    Data(repeating: 0x43, count: 64_000)
                ],
                chunkDelayNanoseconds: 150_000_000
            )
        }

        let client = HTTPFileTransferClient(session: session)
        let task: Task<Void, Error> = Task {
            try await client.transfer(
                from: URL(string: "https://example.test/files/cancel.pdf")!,
                to: destinationURL
            ) { value in
                await progress.record(value)
            }
        }

        try await progress.waitForRecordedValue()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    private func makeTransferDestinationURL() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperTransferTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root.appendingPathComponent("download.part")
    }
}

private struct MockTransferResponse: Sendable {
    let response: HTTPURLResponse
    let chunks: [Data]
    var chunkDelayNanoseconds: UInt64 = 0
}

private final class MockTransferURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                guard let handler = MockTransferURLProtocolStorage.shared.handler() else {
                    throw URLError(.badServerResponse)
                }
                let result = try await handler(request)
                client?.urlProtocol(self, didReceive: result.response, cacheStoragePolicy: .notAllowed)
                for chunk in result.chunks {
                    if result.chunkDelayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: result.chunkDelayNanoseconds)
                    }
                    try Task.checkCancellation()
                    client?.urlProtocol(self, didLoad: chunk)
                }
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) async throws -> MockTransferResponse) {
        MockTransferURLProtocolStorage.shared.setHandler(handler)
    }

    static func reset() {
        MockTransferURLProtocolStorage.shared.reset()
    }
}

private final class MockTransferURLProtocolStorage: @unchecked Sendable {
    static let shared = MockTransferURLProtocolStorage()

    private let lock = NSLock()
    private var currentHandler: (@Sendable (URLRequest) async throws -> MockTransferResponse)?

    func setHandler(_ handler: @escaping @Sendable (URLRequest) async throws -> MockTransferResponse) {
        lock.lock()
        defer { lock.unlock() }
        currentHandler = handler
    }

    func handler() -> (@Sendable (URLRequest) async throws -> MockTransferResponse)? {
        lock.lock()
        defer { lock.unlock() }
        return currentHandler
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentHandler = nil
    }
}

private func makeTransferSession(configuration: URLSessionConfiguration? = nil) -> URLSession {
    let configuration = configuration ?? URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockTransferURLProtocol.self]
    return URLSession(configuration: configuration)
}

private actor RequestRecorder {
    private var requests: [URLRequest] = []

    func first() -> URLRequest? {
        requests.first
    }

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

private actor ProgressRecorder {
    private var recorded: [Double?] = []

    func compactValues() -> [Double] {
        recorded.compactMap { $0 }
    }

    func record(_ value: Double?) {
        recorded.append(value)
    }

    func waitForRecordedValue() async throws {
        for _ in 0..<100 {
            if !recorded.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for progress callback.")
    }

    func lastValue() -> Double? {
        recorded.last ?? nil
    }
}

private final class SessionConfigurationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var configurations: [URLSessionConfiguration] = []

    func first() -> URLSessionConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return configurations.first
    }

    func record(_ configuration: URLSessionConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        configurations.append(configuration)
    }
}
