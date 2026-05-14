import Foundation

@Observable
final class GroupService {
    private let apiClient: APIClient
    private let sseClient = SSEClient()

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createGroup(name: String, description: String) async throws -> GroupResponse {
        let body = ["name": name, "description": description]
        return try await apiClient.post("/api/groups", body: body)
    }

    func joinGroup(inviteCode: String) async throws -> OkResponse {
        try await apiClient.post("/api/groups/0/join", body: ["invite_code": inviteCode])
    }

    func listGroups() async throws -> [GroupResponse] {
        try await apiClient.get("/api/groups")
    }

    func getGroup(id: String) async throws -> GroupDetailResponse {
        try await apiClient.get("/api/groups/\(id)")
    }

    func addPaper(groupId: String, subject: String, year: Int, season: String,
                  paperType: String, filename: String, downloadURL: String) async throws -> GroupPaperResponse {
        let body: [String: Any] = [
            "subject": subject, "year": year, "season": season,
            "paper_type": paperType, "filename": filename, "download_url": downloadURL
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        return try await apiClient.post("/api/groups/\(groupId)/papers", body: jsonData)
    }

    func updateProgress(groupId: String, paperId: String, status: String) async throws -> OkResponse {
        try await apiClient.post("/api/groups/\(groupId)/progress",
                                 body: ["group_paper_id": paperId, "status": status])
    }

    func subscribeEvents(groupId: String, token: String, onEvent: @escaping (SSEClient.SSEEvent) -> Void) {
        let url = URL(string: "\(Constants.baseURL)/api/groups/\(groupId)/events")!
        sseClient.onEvent = onEvent
        sseClient.connect(url: url, token: token)
    }

    func unsubscribe() {
        sseClient.disconnect()
    }
}

struct GroupResponse: Codable {
    let id: Int?
    let name: String?
    let description: String?
    let inviteCode: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, error
        case inviteCode = "invite_code"
    }
}

struct GroupDetailResponse: Codable {
    let group: GroupResponse?
    let members: [GroupMemberResponse]?
    let papers: [GroupPaperResponse]?
}

struct GroupMemberResponse: Codable {
    let userId: Int?
    let nickname: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case nickname, role
        case userId = "user_id"
    }
}

struct GroupPaperResponse: Codable {
    let id: Int?
    let filename: String?
    let subject: String?
    let year: Int?
}

struct OkResponse: Codable {
    let ok: Bool?
    let error: String?
}
