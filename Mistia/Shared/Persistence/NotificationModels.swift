import Foundation
import SwiftData

enum MistiaAppNotificationSource: String, Codable, CaseIterable {
    case localReminder
    case system
    case remote
}

enum MistiaAppNotificationKind: String, Codable, CaseIterable {
    case dueSoon
    case lowWallet
    case familyPlaceholder
}

@Model
final class AppNotificationRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var body: String
    var kindRawValue: String
    var sourceRawValue: String
    var isRead: Bool
    var actionRoute: String?

    init(
        id: UUID = UUID(),
        key: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        source: MistiaAppNotificationSource,
        isRead: Bool = false,
        actionRoute: String? = nil
    ) {
        self.id = id
        self.key = key
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.body = body
        self.kindRawValue = kind.rawValue
        self.sourceRawValue = source.rawValue
        self.isRead = isRead
        self.actionRoute = actionRoute
    }

    var kind: MistiaAppNotificationKind {
        get { MistiaAppNotificationKind(rawValue: kindRawValue) ?? .dueSoon }
        set { kindRawValue = newValue.rawValue }
    }

    var source: MistiaAppNotificationSource {
        get { MistiaAppNotificationSource(rawValue: sourceRawValue) ?? .system }
        set { sourceRawValue = newValue.rawValue }
    }
}

