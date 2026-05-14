import Foundation
import SwiftData

@Model
final class Review {
    var id: String
    var userId: String
    var userNickname: String
    var subject: String
    var year: Int
    var season: String
    var paperType: String
    var filename: String
    var rating: Int
    var difficulty: Int
    var tags: [String]
    var comment: String
    var createdAt: Date

    init(id: String, userId: String, userNickname: String, subject: String, year: Int,
         season: String, paperType: String, filename: String, rating: Int, difficulty: Int,
         tags: [String], comment: String) {
        self.id = id
        self.userId = userId
        self.userNickname = userNickname
        self.subject = subject
        self.year = year
        self.season = season
        self.paperType = paperType
        self.filename = filename
        self.rating = rating
        self.difficulty = difficulty
        self.tags = tags
        self.comment = comment
        self.createdAt = Date()
    }
}
