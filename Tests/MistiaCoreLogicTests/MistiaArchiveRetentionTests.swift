import XCTest
@testable import MistiaCoreLogic

final class MistiaArchiveRetentionTests: XCTestCase {
    func testAutomaticCleanupAllowsOnlyRecordsOwnedBySignedInUser() {
        let signedInUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let familyOwnerUserID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!

        XCTAssertTrue(
            MistiaArchiveRetention.canAutomaticallyCleanup(
                recordOwnerUserID: signedInUserID,
                signedInUserID: signedInUserID
            )
        )
        XCTAssertFalse(
            MistiaArchiveRetention.canAutomaticallyCleanup(
                recordOwnerUserID: familyOwnerUserID,
                signedInUserID: signedInUserID
            )
        )
    }

    func testAutomaticCleanupRejectsRecordsWithoutAnOwnershipClaim() {
        let signedInUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!

        XCTAssertFalse(
            MistiaArchiveRetention.canAutomaticallyCleanup(
                recordOwnerUserID: nil,
                signedInUserID: signedInUserID
            )
        )
    }

    func testCleanupProtectionIndexBlocksQueuedAndConflictedRecords() {
        let queuedTransactionID = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
        let conflictedWalletID = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!
        let unprotectedCategoryID = UUID(uuidString: "50000000-0000-4000-8000-000000000005")!
        let index = MistiaArchiveCleanupProtectionIndex(
            queuedRecordIDs: [
                "LEDGER_TRANSACTIONS:\(queuedTransactionID.uuidString)"
            ],
            conflictedRecordIDs: [
                "ledger_wallets:\(conflictedWalletID.uuidString.lowercased())"
            ]
        )

        XCTAssertFalse(index.canHardPurge(entity: .transaction, recordID: queuedTransactionID))
        XCTAssertFalse(index.canHardPurge(entity: .wallet, recordID: conflictedWalletID))
        XCTAssertTrue(index.canHardPurge(entity: .category, recordID: unprotectedCategoryID))
    }
}
