import Foundation

@Observable
final class ShareService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createShare(subject: String, year: Int, season: String, paperType: String, expiry: String) async throws -> ShareResponse {
        let body = CreateShareBody(subject: subject, year: year, season: season, paper_type: paperType, expiry: expiry)
        return try await apiClient.post("/api/share", body: body)
    }

    func getShare(code: String) async throws -> ShareResponse {
        try await apiClient.get("/api/share/\(code)")
    }

    func deleteShare(code: String) async throws {
        let _: DeleteResponse = try await apiClient.delete("/api/share/\(code)")
    }

    func listMyShares() async throws -> [ShareResponse] {
        try await apiClient.get("/api/share/list")
    }
}

struct CreateShareBody: Encodable {
    let subject: String
    let year: Int
    let season: String
    let paper_type: String
    let expiry: String
}

struct ShareResponse: Codable {
    let id: Int?
    let code: String?
    let subject: String?
    let year: Int?
    let season: String?
    let viewCount: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, code, subject, year, season, error
        case viewCount = "view_count"
    }
}

struct DeleteResponse: Codable {
    let ok: Bool?
}
