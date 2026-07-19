import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class MistiaRecurringBillNotificationBatchTests: XCTestCase {
    func testPreparationDeletesForeignRowsAndResolvesPausedBillRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let activeUserID = UUID()
        let pausedBillID = UUID()
        let foreignBillID = UUID()
        let activeBillID = UUID()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let pausedActionable = makeNotification(
            key: "paused.actionable",
            kind: .billOverdue,
            billID: pausedBillID,
            recipientUserID: activeUserID
        )
        let pausedSuccess = makeNotification(
            key: "paused.success",
            kind: .billAutoPaymentSucceeded,
            billID: pausedBillID,
            recipientUserID: activeUserID
        )
        let foreignActionable = makeNotification(
            key: "foreign.actionable",
            kind: .billPaymentRequired,
            billID: foreignBillID,
            recipientUserID: activeUserID
        )
        let activeActionable = makeNotification(
            key: "active.actionable",
            kind: .billPaymentRequired,
            billID: activeBillID,
            recipientUserID: activeUserID
        )
        [pausedActionable, pausedSuccess, foreignActionable, activeActionable].forEach(context.insert)
        try context.save()

        let batch = MistiaRecurringBillNotificationBatch(
            modelContext: context,
            billOwnerMap: [
                pausedBillID: activeUserID,
                foreignBillID: UUID(),
                activeBillID: activeUserID
            ],
            activeUserID: activeUserID,
            pausedBillIDs: [pausedBillID],
            now: now
        )
        batch.saveIfNeeded()

        let rows = try context.fetch(FetchDescriptor<AppNotificationRecord>())
        let rowsByKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        XCTAssertNil(rowsByKey[foreignActionable.key])
        XCTAssertEqual(rowsByKey[pausedActionable.key]?.isRead, true)
        XCTAssertEqual(rowsByKey[pausedActionable.key]?.readAt, now)
        XCTAssertEqual(rowsByKey[pausedActionable.key]?.actionState, .resolved)
        XCTAssertEqual(rowsByKey[pausedActionable.key]?.updatedAt, now)
        XCTAssertEqual(rowsByKey[pausedSuccess.key]?.isRead, false)
        XCTAssertEqual(rowsByKey[activeActionable.key]?.isRead, false)
    }

    func testUpsertReusesThePreparedKeyIndex() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let activeUserID = UUID()
        let billID = UUID()
        var batch = MistiaRecurringBillNotificationBatch(
            modelContext: context,
            billOwnerMap: [billID: activeUserID],
            activeUserID: activeUserID,
            pausedBillIDs: []
        )

        batch.upsert(
            key: "mistia.bill.test.\(billID.uuidString.lowercased())",
            title: "First",
            body: "First body",
            kind: .billPaymentRequired,
            recipientUserID: activeUserID,
            billID: billID,
            metadataJSON: nil,
            forceUnread: false
        )
        batch.upsert(
            key: "mistia.bill.test.\(billID.uuidString.lowercased())",
            title: "Second",
            body: "Second body",
            kind: .billOverdue,
            recipientUserID: activeUserID,
            billID: billID,
            metadataJSON: "{}",
            forceUnread: true
        )
        batch.saveIfNeeded()

        let rows = try context.fetch(FetchDescriptor<AppNotificationRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Second")
        XCTAssertEqual(rows.first?.body, "Second body")
        XCTAssertEqual(rows.first?.kind, .billOverdue)
        XCTAssertEqual(rows.first?.metadataJSON, "{}")
        XCTAssertEqual(rows.first?.isRead, false)
    }

    private func makeNotification(
        key: String,
        kind: MistiaAppNotificationKind,
        billID: UUID,
        recipientUserID: UUID
    ) -> AppNotificationRecord {
        AppNotificationRecord(
            key: key,
            title: key,
            body: key,
            kind: kind,
            source: .system,
            recipientUserID: recipientUserID,
            resourceType: .bill,
            resourceID: billID
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
