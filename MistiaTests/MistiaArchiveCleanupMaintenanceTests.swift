import Foundation
import SwiftData
import XCTest
@testable import Mistia

final class MistiaArchiveCleanupMaintenanceTests: XCTestCase {
    @MainActor
    func testCleanupExpiredArchivedDataReturnsEmptyWhenNoExpiredRecordsExist() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let signedInUserID = UUID()

        let recentDate = Date()
        let activeTx = LedgerTransaction(
            primaryKind: .expense,
            title: "Test Tx",
            amountMinor: 1000,
            occurredAt: recentDate,
            updatedAt: recentDate
        )
        context.insert(activeTx)
        try context.save()

        let protectionIndex = MistiaArchiveCleanupProtectionIndex(
            queuedRecordIDs: [],
            conflictedRecordIDs: []
        )

        let deleteMutations = try MistiaBootstrap.cleanupExpiredArchivedData(
            modelContext: context,
            signedInUserID: signedInUserID,
            cleanupProtectionIndex: protectionIndex
        )

        XCTAssertTrue(deleteMutations.isEmpty)
        XCTAssertNil(activeTx.deletedAt)
    }

    @MainActor
    func testCleanupExpiredArchivedDataSoftDeletesExpiredRecordAndReturnsMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let signedInUserID = UUID()

        let expiredDate = Date(timeIntervalSinceNow: -Double(MistiaArchiveRetention.retentionDays + 5) * 86400)
        let expiredTx = LedgerTransaction(
            primaryKind: .expense,
            title: "Expired Archived Tx",
            amountMinor: 5000,
            occurredAt: expiredDate,
            updatedAt: expiredDate,
            isArchived: true,
            archivedAt: expiredDate
        )
        context.insert(expiredTx)
        context.insert(
            OwnedRecordScope(
                entity: .transaction,
                recordID: expiredTx.id,
                ownerUserID: signedInUserID,
                updatedAt: expiredDate
            )
        )
        try context.save()

        let protectionIndex = MistiaArchiveCleanupProtectionIndex(
            queuedRecordIDs: [],
            conflictedRecordIDs: []
        )

        let deleteMutations = try MistiaBootstrap.cleanupExpiredArchivedData(
            modelContext: context,
            signedInUserID: signedInUserID,
            cleanupProtectionIndex: protectionIndex
        )

        XCTAssertEqual(deleteMutations.count, 1)
        XCTAssertEqual(deleteMutations.first?.recordID, expiredTx.id)
        XCTAssertEqual(deleteMutations.first?.entity, .transaction)
        XCTAssertNotNil(expiredTx.deletedAt)
    }

    @MainActor
    func testCleanupExpiredArchivedBillUsesArchiveUpdateTimeAndReturnsMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let signedInUserID = UUID()
        let expiredDate = Date(
            timeIntervalSinceNow: -Double(MistiaArchiveRetention.retentionDays + 5) * 86400
        )
        let bill = RecurringBillPlan(
            name: "Archived Internet",
            iconSymbolName: "wifi",
            dueDay: 5,
            isArchived: true,
            createdAt: expiredDate,
            updatedAt: expiredDate
        )
        context.insert(bill)
        context.insert(
            OwnedRecordScope(
                entity: .recurringBillPlan,
                recordID: bill.id,
                ownerUserID: signedInUserID,
                updatedAt: expiredDate
            )
        )
        try context.save()

        let deleteMutations = try MistiaBootstrap.cleanupExpiredArchivedData(
            modelContext: context,
            signedInUserID: signedInUserID,
            cleanupProtectionIndex: MistiaArchiveCleanupProtectionIndex(
                queuedRecordIDs: [],
                conflictedRecordIDs: []
            )
        )

        XCTAssertEqual(deleteMutations.count, 1)
        XCTAssertEqual(deleteMutations.first?.recordID, bill.id)
        XCTAssertEqual(deleteMutations.first?.entity, .recurringBillPlan)
        XCTAssertNotNil(bill.deletedAt)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
