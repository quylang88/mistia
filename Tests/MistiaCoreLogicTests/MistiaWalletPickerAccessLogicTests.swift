import XCTest
@testable import MistiaCoreLogic

final class MistiaWalletPickerAccessLogicTests: XCTestCase {
    func testSelfContextShowsOnlySelfWalletsWithoutOwnerSuffix() {
        let selfID = UUID()
        let memberID = UUID()
        let selfWallet = wallet(name: "Cash", ownerUserID: selfID, sortOrder: 0)
        let memberWallet = wallet(name: "Member Cash", ownerUserID: memberID, sortOrder: 1)

        let result = MistiaWalletPickerAccessLogic.availableWallets(
            from: [selfWallet, memberWallet],
            context: MistiaWalletPickerAccessContext(
                currentSelfUserID: selfID,
                targetOwnerUserID: selfID,
                usableWalletIDs: [memberWallet.id]
            )
        )

        XCTAssertEqual(result.map(\.id), [selfWallet.id])
        XCTAssertEqual(
            MistiaWalletPickerAccessLogic.title(
                for: selfWallet,
                currentSelfUserID: selfID,
                memberDisplayNames: [selfID: "Me"],
                labelMode: .contextual
            ),
            "Cash"
        )
    }

    func testMemberContextShowsOnlyUsableMemberWalletsWithOwnerSuffix() {
        let selfID = UUID()
        let memberID = UUID()
        let usableMemberWallet = wallet(name: "Savings", ownerUserID: memberID, sortOrder: 0)
        let blockedMemberWallet = wallet(name: "Private", ownerUserID: memberID, sortOrder: 1)
        let selfWallet = wallet(name: "Cash", ownerUserID: selfID, sortOrder: 2)

        let result = MistiaWalletPickerAccessLogic.availableWallets(
            from: [selfWallet, usableMemberWallet, blockedMemberWallet],
            context: MistiaWalletPickerAccessContext(
                currentSelfUserID: selfID,
                targetOwnerUserID: memberID,
                usableWalletIDs: [usableMemberWallet.id]
            )
        )

        XCTAssertEqual(result.map(\.id), [usableMemberWallet.id])
        XCTAssertEqual(
            MistiaWalletPickerAccessLogic.title(
                for: usableMemberWallet,
                currentSelfUserID: selfID,
                memberDisplayNames: [memberID: "Trang"],
                labelMode: .contextual
            ),
            "Savings • Trang"
        )
    }

    func testFamilyTransferLabelsBothSourceAndDestinationWithOwnerName() {
        let selfID = UUID()
        let memberID = UUID()
        let sourceWallet = wallet(name: "Main", ownerUserID: selfID, sortOrder: 0)
        let destinationWallet = wallet(name: "Pocket", ownerUserID: memberID, sortOrder: 1)

        let sourceWallets = MistiaWalletPickerAccessLogic.availableWallets(
            from: [sourceWallet, destinationWallet],
            context: MistiaWalletPickerAccessContext(
                currentSelfUserID: selfID,
                targetOwnerUserID: selfID,
                usableWalletIDs: [destinationWallet.id],
                excludesCreditCards: true
            )
        )
        let destinationWallets = MistiaWalletPickerAccessLogic.availableWallets(
            from: [sourceWallet, destinationWallet],
            context: MistiaWalletPickerAccessContext(
                currentSelfUserID: selfID,
                targetOwnerUserID: memberID,
                usableWalletIDs: [destinationWallet.id]
            )
        )

        XCTAssertEqual(sourceWallets.map(\.id), [sourceWallet.id])
        XCTAssertEqual(destinationWallets.map(\.id), [destinationWallet.id])
        XCTAssertEqual(
            MistiaWalletPickerAccessLogic.title(
                for: sourceWallet,
                currentSelfUserID: selfID,
                memberDisplayNames: [selfID: "Me", memberID: "Trang"],
                labelMode: .alwaysShowsOwner
            ),
            "Main • Me"
        )
        XCTAssertEqual(
            MistiaWalletPickerAccessLogic.title(
                for: destinationWallet,
                currentSelfUserID: selfID,
                memberDisplayNames: [selfID: "Me", memberID: "Trang"],
                labelMode: .alwaysShowsOwner
            ),
            "Pocket • Trang"
        )
    }

    func testPreferredCrossOwnerWalletIsNotOfferedWithoutUseAccess() {
        let selfID = UUID()
        let memberID = UUID()
        let otherMemberID = UUID()
        let memberWallet = wallet(name: "Member", ownerUserID: memberID, sortOrder: 0)
        let otherWallet = wallet(name: "Other", ownerUserID: otherMemberID, sortOrder: 1)

        let result = MistiaWalletPickerAccessLogic.availableWallets(
            from: [memberWallet, otherWallet],
            context: MistiaWalletPickerAccessContext(
                currentSelfUserID: selfID,
                targetOwnerUserID: memberID,
                usableWalletIDs: [memberWallet.id],
                preferredWalletIDs: [otherWallet.id]
            )
        )

        XCTAssertEqual(result.map(\.id), [memberWallet.id])
    }

    private func wallet(
        id: UUID = UUID(),
        name: String,
        ownerUserID: UUID,
        kind: LedgerWalletKind = .cash,
        sortOrder: Int,
        isArchived: Bool = false,
        deletedAt: Date? = nil
    ) -> MistiaWalletPickerWalletSnapshot {
        MistiaWalletPickerWalletSnapshot(
            id: id,
            name: name,
            ownerUserID: ownerUserID,
            kind: kind,
            sortOrder: sortOrder,
            createdAt: Date(timeIntervalSince1970: TimeInterval(sortOrder)),
            isArchived: isArchived,
            deletedAt: deletedAt
        )
    }
}
