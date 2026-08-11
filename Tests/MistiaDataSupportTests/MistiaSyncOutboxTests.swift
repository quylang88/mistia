import Foundation
import XCTest
@testable import MistiaCoreLogic

final class MistiaSyncOutboxTests: XCTestCase {
    func testOutboxReloadsWhenAnotherInstanceWritesSameDefaultsKey() throws {
        let suiteName = makeDefaultsSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "mistia-sync-outbox-cache-test"
        let firstOutbox = MistiaSyncOutbox(defaults: defaults, key: key)
        let secondOutbox = MistiaSyncOutbox(defaults: defaults, key: key)
        let userID = UUID()
        let firstMutation = MistiaSyncMutation(
            entity: .wallet,
            recordID: UUID(),
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let secondMutation = MistiaSyncMutation(
            entity: .category,
            recordID: UUID(),
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 20)
        )

        firstOutbox.enqueue(firstMutation)
        XCTAssertEqual(firstOutbox.allMutations, [firstMutation])

        secondOutbox.enqueue(secondMutation)

        XCTAssertEqual(
            Set(firstOutbox.allMutations.map(\.id)),
            Set([firstMutation.id, secondMutation.id])
        )
    }

    func testClearUpdatesCachedMutations() throws {
        let suiteName = makeDefaultsSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let outbox = MistiaSyncOutbox(defaults: defaults, key: "mistia-sync-outbox-clear-cache-test")
        outbox.enqueue(
            MistiaSyncMutation(
                entity: .transaction,
                recordID: UUID(),
                subjectUserID: UUID(),
                kind: .upsert,
                modifiedAt: Date()
            )
        )
        XCTAssertEqual(outbox.allMutations.count, 1)

        outbox.clear()

        XCTAssertTrue(outbox.allMutations.isEmpty)
    }

    func testBatchEnqueueKeepsLastIncomingMutationForSameRecord() throws {
        let suiteName = makeDefaultsSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let outbox = MistiaSyncOutbox(defaults: defaults, key: "mistia-sync-outbox-batch-dedupe-test")
        let userID = UUID()
        let recordID = UUID()
        let preserved = MistiaSyncMutation(
            entity: .wallet,
            recordID: UUID(),
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 5)
        )
        let existing = MistiaSyncMutation(
            entity: .category,
            recordID: recordID,
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let firstIncoming = MistiaSyncMutation(
            entity: .category,
            recordID: recordID,
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        let lastIncoming = MistiaSyncMutation(
            entity: .category,
            recordID: recordID,
            subjectUserID: userID,
            kind: .delete,
            modifiedAt: Date(timeIntervalSince1970: 15)
        )

        outbox.enqueue([preserved, existing])
        outbox.enqueue([firstIncoming, lastIncoming])

        XCTAssertEqual(outbox.allMutations, [preserved, lastIncoming])
    }

    func testRewriteRecordIDsCollapsesMappedCategoryCollisions() throws {
        let suiteName = makeDefaultsSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let outbox = MistiaSyncOutbox(defaults: defaults, key: "mistia-sync-outbox-rewrite-dedupe-test")
        let userID = UUID()
        let sourceID = UUID()
        let destinationID = UUID()
        let olderDestination = MistiaSyncMutation(
            entity: .category,
            recordID: destinationID,
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 10),
            baseVersion: 1
        )
        let newerSource = MistiaSyncMutation(
            entity: .category,
            recordID: sourceID,
            subjectUserID: userID,
            kind: .delete,
            modifiedAt: Date(timeIntervalSince1970: 20),
            baseVersion: 2
        )

        outbox.enqueue([olderDestination, newerSource])
        outbox.rewriteRecordIDs(entity: .category, mappings: [sourceID: destinationID])

        XCTAssertEqual(
            outbox.allMutations,
            [
                MistiaSyncMutation(
                    entity: .category,
                    recordID: destinationID,
                    subjectUserID: userID,
                    kind: .delete,
                    modifiedAt: Date(timeIntervalSince1970: 20),
                    baseVersion: 2
                )
            ]
        )
    }

    func testLegacyValuationMutationIsPrunedBeforeOutboxDecode() throws {
        let suiteName = makeDefaultsSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "mistia-sync-outbox-prune-investment-valuations-test"
        let walletMutation = MistiaSyncMutation(
            entity: .wallet,
            recordID: UUID(),
            subjectUserID: UUID(),
            kind: .upsert,
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let encoded = try JSONEncoder.mistiaSyncEncoder.encode([walletMutation])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        var valuationRow = try XCTUnwrap(rows.first)
        valuationRow["entity"] = "investment_valuations"
        defaults.set(
            try JSONSerialization.data(withJSONObject: rows + [valuationRow]),
            forKey: key
        )

        let outbox = MistiaSyncOutbox(defaults: defaults, key: key)

        XCTAssertEqual(outbox.allMutations, [walletMutation])
        let persisted = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("investment_valuations"))
    }

    private func makeDefaultsSuiteName() -> String {
        "MistiaSyncOutboxTests.\(UUID().uuidString)"
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
