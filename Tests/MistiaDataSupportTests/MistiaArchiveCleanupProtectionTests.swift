import SwiftData
import XCTest
@testable import MistiaCoreLogic

final class MistiaArchiveCleanupProtectionTests: XCTestCase {
    func testConflictedRecordIDsReturnsCanonicalKeysForEveryConflict() throws {
        let transactionID = UUID(uuidString: "60000000-0000-4000-8000-000000000006")!
        let walletID = UUID(uuidString: "70000000-0000-4000-8000-000000000007")!
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(makeConflict(entity: .transaction, recordID: transactionID))
        context.insert(makeConflict(entity: .wallet, recordID: walletID))
        try context.save()

        XCTAssertEqual(
            try MistiaSyncLocalStore.conflictedRecordIDs(in: container),
            [
                "ledger_transactions:\(transactionID.uuidString.lowercased())",
                "ledger_wallets:\(walletID.uuidString.lowercased())"
            ]
        )
    }

    private func makeConflict(
        entity: MistiaSyncEntity,
        recordID: UUID
    ) -> SyncConflict {
        SyncConflict(
            entityRawValue: entity.rawValue,
            recordID: recordID,
            conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
            localPayloadJSON: "{}",
            remotePayloadJSON: "{}",
            baseVersion: 1,
            remoteVersion: 2
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SyncConflict.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
