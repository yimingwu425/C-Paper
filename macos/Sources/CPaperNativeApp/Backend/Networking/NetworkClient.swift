import Foundation

enum NetworkClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case rateLimited(statusCode: Int)
    case serverError(statusCode: Int)
    case httpStatus(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid HTTP response"
        case let .rateLimited(statusCode):
            "Rate limited with HTTP \(statusCode)"
        case let .serverError(statusCode):
            "Server error with HTTP \(statusCode)"
        case let .httpStatus(statusCode):
            "Unexpected HTTP status \(statusCode)"
        case let .decodingFailed(message):
            "Failed to decode response: \(message)"
        }
    }
}

protocol NetworkClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

final class NetworkClient: NetworkClientProtocol, @unchecked Sendable {
    private let session: URLSession

    init(
        timeout: TimeInterval = 20,
        userAgent: String = HTTPRequestBuilder.defaultUserAgent,
        proxy: ProxyConfiguration = ProxyConfiguration(url: nil)
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        self.session = URLSession(configuration: proxy.applying(to: configuration))
    }

    init(session: URLSession) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkClientError.invalidResponse
        }
        try Self.validate(httpResponse)
        return data
    }

    func validate(_ response: HTTPURLResponse) throws {
        try Self.validate(response)
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 429:
            throw NetworkClientError.rateLimited(statusCode: response.statusCode)
        case 500..<600:
            throw NetworkClientError.serverError(statusCode: response.statusCode)
        default:
            throw NetworkClientError.httpStatus(response.statusCode)
        }
    }
}

extension NetworkClientProtocol {
    func get(_ url: URL, builder: HTTPRequestBuilder = HTTPRequestBuilder()) async throws -> Data {
        try await data(for: builder.get(url))
    }

    func postForm(
        _ url: URL,
        form: [String: String],
        builder: HTTPRequestBuilder = HTTPRequestBuilder()
    ) async throws -> Data {
        try await data(for: builder.postForm(url, form: form))
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        from request: URLRequest,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let responseData = try await data(for: request)
        do {
            return try decoder.decode(type, from: responseData)
        } catch {
            throw NetworkClientError.decodingFailed(error.localizedDescription)
        }
    }
}
