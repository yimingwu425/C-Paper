import Foundation

@Observable
final class TokenManager {
    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    var isAuthenticated: Bool { accessToken != nil }

    init() {
        self.accessToken = KeychainHelper.load(key: "cpaper_access_token")
        self.refreshToken = KeychainHelper.load(key: "cpaper_refresh_token")
    }

    func saveTokens(access: String, refresh: String) {
        self.accessToken = access
        self.refreshToken = refresh
        KeychainHelper.save(key: "cpaper_access_token", value: access)
        KeychainHelper.save(key: "cpaper_refresh_token", value: refresh)
    }

    func clearTokens() {
        self.accessToken = nil
        self.refreshToken = nil
        KeychainHelper.delete(key: "cpaper_access_token")
        KeychainHelper.delete(key: "cpaper_refresh_token")
    }

    func refreshIfNeeded() async throws {
        guard let refreshToken else { throw APIError.unauthorized }

        var request = URLRequest(url: URL(string: "\(Constants.baseURL)/api/auth/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            clearTokens()
            throw APIError.unauthorized
        }

        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        saveTokens(access: result.accessToken, refresh: result.refreshToken)
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
