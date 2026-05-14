import Foundation
import SwiftData

@Model
final class Favorite {
    @Attribute(.unique) var subjectCode: String
    var subjectName: String
    var addedAt: Date

    init(subjectCode: String, subjectName: String) {
        self.subjectCode = subjectCode
        self.subjectName = subjectName
        self.addedAt = Date()
    }
}
