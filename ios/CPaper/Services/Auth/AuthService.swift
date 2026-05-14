import Foundation
import AuthenticationServices

@Observable
final class AuthService {
    var currentUser: UserResponse?
    var isAuthenticated: Bool { currentUser != nil }

    private let apiClient: APIClient
    private let tokenManager: TokenManager

    init(apiClient: APIClient, tokenManager: TokenManager) {
        self.apiClient = apiClient
        self.tokenManager = tokenManager
    }

    func restoreSession() async {
        guard tokenManager.isAuthenticated else { return }
        do {
            currentUser = try await apiClient.get("/api/me")
        } catch {
            tokenManager.clearTokens()
        }
    }

    func login(email: String, password: String) async throws {
        let body = ["email": email, "password": password]
        let response: AuthResponse = try await apiClient.post("/api/auth/login", body: body)
        tokenManager.saveTokens(access: response.accessToken, refresh: response.refreshToken)
        currentUser = response.user
    }

    func register(email: String, password: String, nickname: String) async throws {
        let body = ["email": email, "password": password, "nickname": nickname]
        let response: AuthResponse = try await apiClient.post("/api/auth/register", body: body)
        tokenManager.saveTokens(access: response.accessToken, refresh: response.refreshToken)
        currentUser = response.user
    }

    func logout() {
        tokenManager.clearTokens()
        currentUser = nil
    }
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: UserResponse

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct UserResponse: Codable {
    let id: Int
    let email: String
    let nickname: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email, nickname
        case avatarUrl = "avatar_url"
    }
}
