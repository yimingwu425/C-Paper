import Foundation
import SwiftData

@Model
final class Paper {
    var id: String
    var subject: String
    var subjectName: String
    var year: Int
    var season: String
    var paperType: String
    var paperNumber: String
    var filename: String
    var downloadURL: String
    var localPath: String?
    var isDownloaded: Bool
    var downloadedAt: Date?
    var isFavorite: Bool
    var createdAt: Date

    init(id: String, subject: String, subjectName: String, year: Int, season: String,
         paperType: String, paperNumber: String, filename: String, downloadURL: String) {
        self.id = id
        self.subject = subject
        self.subjectName = subjectName
        self.year = year
        self.season = season
        self.paperType = paperType
        self.paperNumber = paperNumber
        self.filename = filename
        self.downloadURL = downloadURL
        self.localPath = nil
        self.isDownloaded = false
        self.downloadedAt = nil
        self.isFavorite = false
        self.createdAt = Date()
    }
}
