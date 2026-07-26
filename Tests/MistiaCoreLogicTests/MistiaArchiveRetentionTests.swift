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
}
