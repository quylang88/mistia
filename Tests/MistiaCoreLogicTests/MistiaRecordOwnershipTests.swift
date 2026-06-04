import XCTest
@testable import MistiaCoreLogic

final class MistiaRecordOwnershipTests: XCTestCase {
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
