import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaNotificationStoreTests: XCTestCase {
    func testRemoteMergeKeepsLocalReadStateWhenCloudStillUnread() throws {
        let currentUserID = UUID()
        let otherUserID = UUID()
        let notificationID = UUID()
        let context = ModelContext(try makeContainer())
        let createdAt = Date(timeIntervalSince1970: 1_772_300_000)

        try MistiaNotificationStore.applyRemoteNotifications(
            [
                makeRemoteNotification(
                    id: notificationID,
                    sourceEventKey: "permission:\(notificationID.uuidString)",
                    userID: currentUserID,
                    createdAt: createdAt
                ),
                makeRemoteNotification(
                    sourceEventKey: "other-user",
                    userID: otherUserID,
                    createdAt: createdAt
                )
            ],
            currentUserID: currentUserID,
            in: context
        )

        var rows = try fetchNotifications(in: context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(MistiaNotificationStore.unreadCount(rows: rows, userID: currentUserID), 1)
        XCTAssertEqual(MistiaNotificationStore.unreadCount(rows: rows, userID: otherUserID), 0)

        XCTAssertEqual(try MistiaNotificationStore.markAllAsRead(for: currentUserID, in: context), [notificationID])
        rows = try fetchNotifications(in: context)
        let localReadAt = try XCTUnwrap(rows.first?.readAt)
        XCTAssertEqual(MistiaNotificationStore.unreadCount(rows: rows, userID: currentUserID), 0)

        try MistiaNotificationStore.applyRemoteNotifications(
            [
                makeRemoteNotification(
                    id: notificationID,
                    sourceEventKey: "permission:\(notificationID.uuidString)",
                    userID: currentUserID,
                    title: "Updated title",
                    createdAt: createdAt,
                    syncVersion: 2
                )
            ],
            currentUserID: currentUserID,
            in: context
        )

        let mergedRow = try XCTUnwrap(try fetchNotifications(in: context).first)
        XCTAssertTrue(mergedRow.isRead)
        XCTAssertEqual(mergedRow.readAt, localReadAt)
        XCTAssertTrue(mergedRow.needsReadSync)
        XCTAssertEqual(mergedRow.title, "Updated title")
    }

    func testRemoteMergeDeduplicatesActivityBySourceEventKey() throws {
        let currentUserID = UUID()
        let firstRemoteID = UUID()
        let retryRemoteID = UUID()
        let sourceEventKey = "family-activity:transaction:\(UUID().uuidString):upsert:4:\(UUID().uuidString)"
        let context = ModelContext(try makeContainer())

        try MistiaNotificationStore.applyRemoteNotifications(
            [
                makeRemoteNotification(
                    id: firstRemoteID,
                    sourceEventKey: sourceEventKey,
                    userID: currentUserID,
                    kindRawValue: "family_activity",
                    resourceTypeRawValue: "transaction",
                    body: "A vừa tạo một giao dịch trên ví của bạn."
                )
            ],
            currentUserID: currentUserID,
            in: context
        )

        try MistiaNotificationStore.applyRemoteNotifications(
            [
                makeRemoteNotification(
                    id: retryRemoteID,
                    sourceEventKey: sourceEventKey,
                    userID: currentUserID,
                    kindRawValue: "family_activity",
                    resourceTypeRawValue: "transaction",
                    body: "A vừa cập nhật giao dịch trên ví của bạn.",
                    syncVersion: 2
                )
            ],
            currentUserID: currentUserID,
            in: context
        )

        let rows = try fetchNotifications(in: context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, retryRemoteID)
        XCTAssertEqual(rows.first?.key, sourceEventKey)
        XCTAssertEqual(rows.first?.kind, .familyActivity)
        XCTAssertEqual(rows.first?.resourceType, .transaction)
        XCTAssertEqual(rows.first?.body, "A vừa cập nhật giao dịch trên ví của bạn.")
    }

    func testUnreadCountIgnoresFamilyNotificationsForOtherUsers() throws {
        let currentUserID = UUID()
        let otherUserID = UUID()
        let context = ModelContext(try makeContainer())

        context.insert(
            AppNotificationRecord(
                key: "current",
                title: "Current",
                body: "Current user",
                kind: .permissionRequestReceived,
                source: .family,
                recipientUserID: currentUserID
            )
        )
        context.insert(
            AppNotificationRecord(
                key: "other",
                title: "Other",
                body: "Other user",
                kind: .permissionRequestReceived,
                source: .family,
                recipientUserID: otherUserID
            )
        )
        try context.save()

        let rows = try fetchNotifications(in: context)
        XCTAssertEqual(MistiaNotificationStore.unreadCount(rows: rows, userID: currentUserID), 1)
        XCTAssertEqual(MistiaNotificationStore.unreadCount(rows: rows, userID: otherUserID), 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([AppNotificationRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fetchNotifications(in context: ModelContext) throws -> [AppNotificationRecord] {
        try context.fetch(FetchDescriptor<AppNotificationRecord>())
    }

    private func makeRemoteNotification(
        id: UUID = UUID(),
        sourceEventKey: String,
        userID: UUID,
        kindRawValue: String = "permission_request_received",
        resourceTypeRawValue: String? = "wallet",
        permissionScopeRawValue: String? = "use",
        actionStateRawValue: String = "pending",
        title: String = "Xin quyền",
        body: String = "A muốn dùng ví của bạn.",
        readAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_772_300_000),
        syncVersion: Int64 = 1
    ) -> FamilyNotificationRemoteRecord {
        FamilyNotificationRemoteRecord(
            id: id,
            sourceEventKey: sourceEventKey,
            familyID: UUID(),
            userID: userID,
            actorUserID: UUID(),
            kindRawValue: kindRawValue,
            resourceTypeRawValue: resourceTypeRawValue,
            resourceID: UUID(),
            permissionScopeRawValue: permissionScopeRawValue,
            permissionRequestID: UUID(),
            actionStateRawValue: actionStateRawValue,
            title: title,
            body: body,
            metadata: nil,
            readAt: readAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            syncVersion: syncVersion
        )
    }
}
