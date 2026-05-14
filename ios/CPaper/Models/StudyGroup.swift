import Foundation
import SwiftData

@Model
final class StudyGroup {
    var id: String
    var name: String
    var descriptionText: String
    var inviteCode: String
    var ownerId: String
    var memberCount: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var members: [GroupMember]

    @Relationship(deleteRule: .cascade)
    var papers: [GroupPaper]

    init(id: String, name: String, description: String, inviteCode: String, ownerId: String) {
        self.id = id
        self.name = name
        self.descriptionText = description
        self.inviteCode = inviteCode
        self.ownerId = ownerId
        self.memberCount = 0
        self.createdAt = Date()
        self.members = []
        self.papers = []
    }
}

@Model
final class GroupMember {
    var id: UUID
    var userId: String
    var nickname: String
    var avatarURL: String?
    var role: String
    var joinedAt: Date
    var group: StudyGroup?

    init(userId: String, nickname: String, role: String) {
        self.id = UUID()
        self.userId = userId
        self.nickname = nickname
        self.role = role
        self.joinedAt = Date()
    }
}

@Model
final class GroupPaper {
    var id: String
    var subject: String
    var year: Int
    var season: String
    var paperType: String
    var filename: String
    var downloadURL: String?
    var addedBy: String
    var createdAt: Date
    var group: StudyGroup?

    init(id: String, subject: String, year: Int, season: String, paperType: String, filename: String, addedBy: String) {
        self.id = id
        self.subject = subject
        self.year = year
        self.season = season
        self.paperType = paperType
        self.filename = filename
        self.addedBy = addedBy
        self.createdAt = Date()
    }
}
