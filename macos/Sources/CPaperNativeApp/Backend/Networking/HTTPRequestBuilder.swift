import Foundation

struct HTTPRequestBuilder: Sendable {
    static let defaultUserAgent = BackendConstants.userAgent

    var userAgent: String
    var timeout: TimeInterval
    var additionalHeaders: [String: String]

    init(
        userAgent: String = HTTPRequestBuilder.defaultUserAgent,
        timeout: TimeInterval = 20,
        additionalHeaders: [String: String] = [:]
    ) {
        self.userAgent = userAgent
        self.timeout = timeout
        self.additionalHeaders = additionalHeaders
    }

    func get(_ url: URL) -> URLRequest {
        var request = baseRequest(url)
        request.httpMethod = "GET"
        return request
    }

    func head(_ url: URL) -> URLRequest {
        var request = baseRequest(url)
        request.httpMethod = "HEAD"
        return request
    }

    func postForm(_ url: URL, form: [String: String]) -> URLRequest {
        var request = baseRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { key, value in "\(percentEncode(key))=\(percentEncode(value))" }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    private func baseRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
