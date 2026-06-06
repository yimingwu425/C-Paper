import Foundation

typealias FileTransferProgressHandler = @Sendable (_ progress: Double?) async -> Void

final class HTTPFileTransferClient: @unchecked Sendable {
    typealias SessionFactory = @Sendable (_ configuration: URLSessionConfiguration) -> URLSession

    private let session: URLSession
    private let requestBuilder: HTTPRequestBuilder
    private let fileManager: FileManager
    private let chunkSize: Int

    init(
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder(),
        proxy: ProxyConfiguration = ProxyConfiguration(url: nil),
        fileManager: FileManager = .default,
        chunkSize: Int = 64_000,
        sessionFactory: @escaping SessionFactory = { URLSession(configuration: $0) }
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestBuilder.timeout
        configuration.timeoutIntervalForResource = requestBuilder.timeout
        self.session = sessionFactory(proxy.applying(to: configuration))
        self.requestBuilder = requestBuilder
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    init(
        session: URLSession,
        requestBuilder: HTTPRequestBuilder = HTTPRequestBuilder(),
        fileManager: FileManager = .default,
        chunkSize: Int = 64_000
    ) {
        self.session = session
        self.requestBuilder = requestBuilder
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    func transfer(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping FileTransferProgressHandler
    ) async throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: destinationURL)

        let request = requestBuilder.get(sourceURL)
        var completed = false
        var handle: FileHandle?
        defer {
            try? handle?.close()
            if !completed {
                try? fileManager.removeItem(at: destinationURL)
            }
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkClientError.invalidResponse
        }
        try NetworkClient.validate(httpResponse)

        let expectedLength = httpResponse.expectedContentLength
        await progress(expectedLength > 0 ? 0 : nil)

        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: destinationURL)

        var receivedLength: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            receivedLength += 1

            if buffer.count >= chunkSize {
                try handle?.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    await progress(min(Double(receivedLength) / Double(expectedLength), 0.99))
                }
            }
        }

        if !buffer.isEmpty {
            try handle?.write(contentsOf: buffer)
        }

        await progress(1)
        completed = true
    }
}
