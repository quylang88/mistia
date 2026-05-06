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

    func testVisibleRowsExcludeFutureLocalRowsAndLegacyDueSoon() {
        let referenceDate = Date(timeIntervalSince1970: 1_777_800_000)
        let visibleRow = AppNotificationRecord(
            key: "visible",
            createdAt: referenceDate.addingTimeInterval(-60),
            title: "Visible",
            body: "Visible row",
            kind: .lowWallet,
            source: .system
        )
        let futureRow = AppNotificationRecord(
            key: "future",
            createdAt: referenceDate.addingTimeInterval(3600),
            title: "Future",
            body: "Future row",
            kind: .lowWallet,
            source: .localReminder
        )
        let obsoleteDueSoonRow = AppNotificationRecord(
            key: "due-soon",
            createdAt: referenceDate.addingTimeInterval(-120),
            title: "Due soon",
            body: "Old generic due reminder",
            kind: .dueSoon,
            source: .localReminder
        )

        let rows = [visibleRow, futureRow, obsoleteDueSoonRow]
        let visibleRows = MistiaNotificationStore.visibleRows(
            rows,
            userID: nil,
            referenceDate: referenceDate
        )

        XCTAssertEqual(visibleRows.map(\.key), ["visible"])
        XCTAssertEqual(
            MistiaNotificationStore.unreadCount(
                rows: rows,
                userID: nil,
                referenceDate: referenceDate
            ),
            1
        )
    }

    func testNotificationPayloadDecodingSupportsCreditPayloadAndLegacyBillMetadata() throws {
        let statementMonthKey = "2026-05"
        let linkedWalletID = UUID()
        let creditPayload = CreditCardNotificationActionPayload(
            actionKind: .autoPaymentFailed,
            statementMonthKey: statementMonthKey,
            dueDate: Date(timeIntervalSince1970: 1_777_800_000),
            linkedPaymentWalletID: linkedWalletID,
            walletName: "Visa",
            currencyCode: "JPY"
        )
        let creditMetadata = try XCTUnwrap(
            String(
                data: JSONEncoder.mistiaSyncEncoder.encode(creditPayload),
                encoding: .utf8
            )
        )
        let creditRow = AppNotificationRecord(
            key: "credit",
            title: "Credit",
            body: "Credit body",
            kind: .creditCardAutoPaymentFailed,
            source: .system,
            metadataJSON: creditMetadata
        )

        XCTAssertEqual(creditRow.creditCardActionPayload?.statementMonthKey, statementMonthKey)
        XCTAssertEqual(creditRow.creditCardActionPayload?.linkedPaymentWalletID, linkedWalletID)
        XCTAssertEqual(creditRow.creditCardActionPayload?.actionKind, .autoPaymentFailed)
        XCTAssertEqual(creditRow.topUpTransferDestinationWalletID, linkedWalletID)

        let legacyBillMetadata = """
        {"sourceKind":"recurringBill","sourceId":"11111111-1111-1111-1111-111111111111","dueMonthKey":"2026-05","dueDate":"2026-05-10T00:00:00Z","requiresAmountInput":false,"currencyCode":"JPY","billName":"Water"}
        """
        let billRow = AppNotificationRecord(
            key: "bill",
            title: "Bill",
            body: "Bill body",
            kind: .billPaymentRequired,
            source: .system,
            metadataJSON: legacyBillMetadata
        )

        XCTAssertEqual(billRow.dueActionPayload?.dueMonthKey, "2026-05")
        XCTAssertEqual(billRow.dueActionPayload?.billName, "Water")
        XCTAssertNil(billRow.dueActionPayload?.linkedPaymentWalletID)
        XCTAssertNil(billRow.topUpTransferDestinationWalletID)

        let billPayload = DueNotificationActionPayload(
            sourceKind: PlanningDueSourceKind.recurringBill.rawValue,
            sourceID: UUID(),
            dueMonthKey: "2026-05",
            dueDate: Date(timeIntervalSince1970: 1_777_800_000),
            requiresAmountInput: false,
            currencyCode: "JPY",
            billName: "Internet",
            linkedPaymentWalletID: linkedWalletID
        )
        let billMetadata = try XCTUnwrap(
            String(
                data: JSONEncoder.mistiaSyncEncoder.encode(billPayload),
                encoding: .utf8
            )
        )
        let billFailedRow = AppNotificationRecord(
            key: "bill-failed",
            title: "Bill",
            body: "Bill body",
            kind: .billAutoPaymentFailed,
            source: .system,
            metadataJSON: billMetadata
        )

        XCTAssertEqual(billFailedRow.topUpTransferDestinationWalletID, linkedWalletID)
    }

    func testClearAllRemovesEveryNotificationRow() throws {
        let context = ModelContext(try makeContainer())
        context.insert(AppNotificationRecord(key: "one", title: "One", body: "One", kind: .lowWallet, source: .system))
        context.insert(AppNotificationRecord(key: "two", title: "Two", body: "Two", kind: .familyActivity, source: .family))
        try context.save()

        XCTAssertEqual(try MistiaNotificationStore.clearAll(in: context), 2)
        XCTAssertEqual(try fetchNotifications(in: context).count, 0)
    }

    func testClearLocalDeviceLiveDataPreservesUserProfileAndClearsFinanceSyncAndNotifications() throws {
        let container = try makeFullContainer()
        let context = ModelContext(container)
        let userID = UUID()

        context.insert(
            UserAccountProfile(
                userID: userID,
                email: "user@example.com",
                displayName: "User",
                lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        context.insert(
            LedgerWallet(
                name: "Cash",
                kind: .cash,
                iconSymbolName: "banknote.fill",
                iconColorHex: "#2DAA9E"
            )
        )
        context.insert(
            SyncConflict(
                entityRawValue: MistiaSyncEntity.wallet.rawValue,
                recordID: UUID(),
                conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                localPayloadJSON: "{}",
                remotePayloadJSON: "{}",
                baseVersion: 1,
                remoteVersion: 2
            )
        )
        context.insert(AppNotificationRecord(key: "notice", title: "Notice", body: "Notice", kind: .lowWallet, source: .system))
        try context.save()

        try MistiaSyncLocalStore.clearLocalDeviceLiveData(in: container)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<UserAccountProfile>()).map(\.userID), [userID])
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<LedgerWallet>()).count, 0)
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<SyncConflict>()).count, 0)
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<AppNotificationRecord>()).count, 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([AppNotificationRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeFullContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
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
