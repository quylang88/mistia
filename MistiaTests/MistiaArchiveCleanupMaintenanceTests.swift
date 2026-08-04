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
            displayTitle: "Test Tx",
            amountMinor: 1000,
            direction: .expense,
            transactionDate: recentDate,
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
            displayTitle: "Expired Archived Tx",
            amountMinor: 5000,
            direction: .expense,
            transactionDate: expiredDate,
            isArchived: true,
            archivedAt: expiredDate,
            updatedAt: expiredDate
        )
        context.insert(expiredTx)
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

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
