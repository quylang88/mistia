import XCTest
@testable import MistiaCoreLogic

final class MistiaRecordOwnershipTests: XCTestCase {
    func testOwnerMapsBuildsRequestedEntitiesAndKeepsLatestScope() {
        let walletID = UUID()
        let categoryID = UUID()
        let transactionID = UUID()
        let oldOwnerID = UUID()
        let newOwnerID = UUID()
        let categoryOwnerID = UUID()
        let transactionOwnerID = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let scopes = [
            OwnedRecordScope(entity: .wallet, recordID: walletID, ownerUserID: oldOwnerID, updatedAt: olderDate),
            OwnedRecordScope(entity: .wallet, recordID: walletID, ownerUserID: newOwnerID, updatedAt: newerDate),
            OwnedRecordScope(entity: .category, recordID: categoryID, ownerUserID: categoryOwnerID, updatedAt: olderDate),
            OwnedRecordScope(entity: .transaction, recordID: transactionID, ownerUserID: transactionOwnerID, updatedAt: olderDate)
        ]

        let ownerMaps = MistiaRecordOwnershipStore.ownerMaps(
            from: scopes,
            entities: [.wallet, .category]
        )

        XCTAssertEqual(ownerMaps[.wallet][walletID], newOwnerID)
        XCTAssertEqual(ownerMaps[.category][categoryID], categoryOwnerID)
        XCTAssertNil(ownerMaps[.transaction][transactionID])
    }

    func testVisibleCategoryRecordsUseSelectedSubjectOwnerOnly() {
        let selfUserID = UUID()
        let memberUserID = UUID()
        let selfParent = category(name: "Sinh hoạt")
        let memberParent = category(name: "Sinh hoạt")
        let ownerMap = [
            selfParent.id: selfUserID,
            memberParent.id: memberUserID
        ]

        let selfResult = MistiaRecordOwnershipStore.visibleRecords(
            [selfParent, memberParent],
            entity: .category,
            ownerMap: ownerMap,
            subjectUserID: selfUserID,
            signedInUserID: selfUserID
        )
        let memberResult = MistiaRecordOwnershipStore.visibleRecords(
            [selfParent, memberParent],
            entity: .category,
            ownerMap: ownerMap,
            subjectUserID: memberUserID,
            signedInUserID: selfUserID
        )

        XCTAssertEqual(selfResult.map(\.id), [selfParent.id])
        XCTAssertEqual(memberResult.map(\.id), [memberParent.id])
    }

    private func category(name: String) -> TransactionCategory {
        TransactionCategory(
            name: name,
            kind: .expense,
            iconSymbolName: "folder.fill",
            iconColorHex: "#8A8A8E",
            hierarchyRole: .parent
        )
    }
}
