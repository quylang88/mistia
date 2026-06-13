import Foundation
import SwiftData

@Model
nonisolated final class UserAccountProfile {
    @Attribute(.unique) var userID: UUID
    var email: String
    var displayName: String
    var avatarFileName: String?
    var birthday: Date?
    var lastSyncAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        userID: UUID,
        email: String,
        displayName: String,
        avatarFileName: String? = nil,
        birthday: Date? = nil,
        lastSyncAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.avatarFileName = avatarFileName
        self.birthday = birthday
        self.lastSyncAt = lastSyncAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
