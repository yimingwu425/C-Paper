import Foundation

enum NetworkClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case rateLimited(statusCode: Int, retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case httpStatus(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case let .rateLimited(statusCode, retryAfter):
            if let retryAfter {
                let retryText = retryAfter.rounded(.towardZero) == retryAfter
                    ? "\(Int(retryAfter))"
                    : String(format: "%.1f", retryAfter)
                return "Server rate limit reached (HTTP \(statusCode)). Please retry in \(retryText) seconds."
            }
            return "Server rate limit reached (HTTP \(statusCode)). Please try again shortly."
        case let .serverError(statusCode):
            return "Server error with HTTP \(statusCode)"
        case let .httpStatus(statusCode):
            return "Unexpected HTTP status \(statusCode)"
        case let .decodingFailed(message):
            return "Failed to decode response: \(message)"
        }
    }
}

protocol NetworkClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

final class NetworkClient: NetworkClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let nowProvider: @Sendable () -> Date

    init(
        timeout: TimeInterval = 20,
        userAgent: String = HTTPRequestBuilder.defaultUserAgent,
        proxy: ProxyConfiguration = ProxyConfiguration(url: nil),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        self.session = URLSession(configuration: proxy.applying(to: configuration))
        self.nowProvider = nowProvider
    }

    init(session: URLSession, nowProvider: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.nowProvider = nowProvider
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkClientError.invalidResponse
        }
        try Self.validate(httpResponse, now: nowProvider)
        return data
    }

    func validate(_ response: HTTPURLResponse) throws {
        try Self.validate(response, now: nowProvider)
    }

    static func validate(
        _ response: HTTPURLResponse,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 429:
            throw NetworkClientError.rateLimited(
                statusCode: response.statusCode,
                retryAfter: retryAfter(from: response, now: now)
            )
        case 500..<600:
            throw NetworkClientError.serverError(statusCode: response.statusCode)
        default:
            throw NetworkClientError.httpStatus(response.statusCode)
        }
    }

    private static func retryAfter(
        from response: HTTPURLResponse,
        now: @escaping @Sendable () -> Date
    ) -> TimeInterval? {
        guard
            let rawValue = response.value(forHTTPHeaderField: "Retry-After")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty
        else {
            return nil
        }

        if let seconds = TimeInterval(rawValue) {
            guard seconds >= 0, seconds.isFinite else {
                return nil
            }
            return seconds
        }

        guard let retryDate = httpDate(from: rawValue) else {
            return nil
        }

        let interval = retryDate.timeIntervalSince(now())
        return interval > 0 ? interval : nil
    }

    private static func httpDate(from rawValue: String) -> Date? {
        let formats = [
            "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'",
            "EEEE',' dd-MMM-yy HH':'mm':'ss 'GMT'",
            "EEE MMM d HH':'mm':'ss yyyy"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
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
