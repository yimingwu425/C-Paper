import Foundation
import XCTest
@testable import CPaperNativeApp

struct MockTransferResponse: Sendable {
    let response: HTTPURLResponse
    let chunks: [Data]
    var chunkDelayNanoseconds: UInt64 = 0
}

final class MockTransferURLProtocol: URLProtocol, @unchecked Sendable {
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

func makeTransferSession(configuration: URLSessionConfiguration? = nil) -> URLSession {
    let configuration = configuration ?? URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockTransferURLProtocol.self]
    return URLSession(configuration: configuration)
}

actor RequestRecorder {
    private var requests: [URLRequest] = []

    func first() -> URLRequest? {
        requests.first
    }

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

actor ProgressRecorder {
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

final class SessionConfigurationRecorder: @unchecked Sendable {
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
