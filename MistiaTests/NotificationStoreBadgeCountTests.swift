import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class NotificationStoreBadgeCountTests: XCTestCase {
    func testUnreadCountInContextMatchesVisibleUnreadCountForRecipient() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currentUserID = UUID()
        let otherUserID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

        let rows = [
            notification(key: "current.local", recipientUserID: currentUserID),
            notification(key: "current.system", source: .system, recipientUserID: currentUserID),
            notification(key: "current.read", isRead: true, recipientUserID: currentUserID),
            notification(key: "current.due", kind: .dueSoon, recipientUserID: currentUserID),
            notification(key: "current.future", createdAt: referenceDate.addingTimeInterval(3600), recipientUserID: currentUserID),
            notification(key: "other.local", recipientUserID: otherUserID),
            notification(key: "unscoped.local")
        ]
        rows.forEach(context.insert)
        try context.save()

        XCTAssertEqual(
            MistiaNotificationStore.unreadCount(
                in: context,
                userID: currentUserID,
                referenceDate: referenceDate
            ),
            2
        )
    }

    func testUnreadCountInContextKeepsLegacyUnscopedLocalBehavior() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currentUserID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

        let rows = [
            notification(key: "unscoped.local"),
            notification(key: "unscoped.system", source: .system),
            notification(key: "current.local", recipientUserID: currentUserID),
            notification(key: "unscoped.remote", source: .remote),
            notification(key: "unscoped.read", isRead: true),
            notification(key: "unscoped.future", createdAt: referenceDate.addingTimeInterval(3600))
        ]
        rows.forEach(context.insert)
        try context.save()

        XCTAssertEqual(
            MistiaNotificationStore.unreadCount(
                in: context,
                userID: nil,
                referenceDate: referenceDate
            ),
            2
        )
    }

    private func notification(
        key: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_779_900_000),
        kind: MistiaAppNotificationKind = .lowWallet,
        source: MistiaAppNotificationSource = .localReminder,
        isRead: Bool = false,
        recipientUserID: UUID? = nil
    ) -> AppNotificationRecord {
        AppNotificationRecord(
            key: key,
            createdAt: createdAt,
            updatedAt: createdAt,
            title: key,
            body: key,
            kind: kind,
            source: source,
            isRead: isRead,
            recipientUserID: recipientUserID
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
