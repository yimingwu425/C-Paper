import Foundation

@Observable
final class ReviewService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createReview(subject: String, year: Int, season: String, paperType: String,
                      filename: String, rating: Int, difficulty: Int,
                      tags: [String], comment: String) async throws -> ReviewResponse {
        let body = CreateReviewBody(
            subject: subject, year: year, season: season, paper_type: paperType,
            filename: filename, rating: rating, difficulty: difficulty, tags: tags, comment: comment
        )
        return try await apiClient.post("/api/reviews", body: body)
    }

    func listReviews(subject: String, year: Int = 0, season: String = "") async throws -> [ReviewResponse] {
        var path = "/api/reviews?subject=\(subject)"
        if year > 0 { path += "&year=\(year)" }
        if !season.isEmpty { path += "&season=\(season)" }
        return try await apiClient.get(path)
    }

    func deleteReview(id: String) async throws {
        let _: OkResponse = try await apiClient.delete("/api/reviews/\(id)")
    }
}

struct CreateReviewBody: Encodable {
    let subject: String
    let year: Int
    let season: String
    let paper_type: String
    let filename: String
    let rating: Int
    let difficulty: Int
    let tags: [String]
    let comment: String
}

struct ReviewResponse: Codable {
    let id: Int?
    let userId: Int?
    let userNickname: String?
    let subject: String?
    let year: Int?
    let rating: Int?
    let difficulty: Int?
    let comment: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, subject, year, rating, difficulty, comment, error
        case userId = "user_id"
        case userNickname = "user_nickname"
    }
}
