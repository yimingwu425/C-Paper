import Foundation
import SwiftData

@Model
final class DownloadTask {
    var id: UUID
    var filename: String
    var savePath: String
    var status: String
    var progress: Double
    var error: String?
    var fileSize: Int64
    var downloadedSize: Int64
    var createdAt: Date
    var completedAt: Date?

    init(filename: String, savePath: String) {
        self.id = UUID()
        self.filename = filename
        self.savePath = savePath
        self.status = "pending"
        self.progress = 0.0
        self.fileSize = 0
        self.downloadedSize = 0
        self.createdAt = Date()
    }
}
