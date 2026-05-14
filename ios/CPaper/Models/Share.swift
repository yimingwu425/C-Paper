import Foundation
import SwiftData

@Model
final class Share {
    var id: String
    var code: String
    var subject: String
    var year: Int
    var season: String
    var paperType: String
    var expiresAt: Date?
    var viewCount: Int
    var createdAt: Date

    init(id: String, code: String, subject: String, year: Int, season: String, paperType: String) {
        self.id = id
        self.code = code
        self.subject = subject
        self.year = year
        self.season = season
        self.paperType = paperType
        self.viewCount = 0
        self.createdAt = Date()
    }
}
