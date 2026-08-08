import XCTest
@testable import MistiaCoreLogic

final class MistiaShortcutLogicTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

    func testResolveKeepsPersonalUtilitySelections() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .backupRestore,
            input: makeInput()
        )

        XCTAssertEqual(resolution.selection, .backupRestore)
        XCTAssertEqual(resolution.presentation.title, "Sao lưu & Khôi phục")
        XCTAssertEqual(resolution.presentation.icon, .systemImage("externaldrive.badge.icloud"))
        XCTAssertEqual(resolution.presentation.action, .backupRestore)
    }

    func testResolveKeepsReceiptScanSelection() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .receiptScan,
            input: makeInput()
        )

        XCTAssertEqual(resolution.selection, .receiptScan)
        XCTAssertEqual(resolution.presentation.title, "Quét bill")
        XCTAssertEqual(resolution.presentation.icon, .systemImage("doc.viewfinder"))
        XCTAssertEqual(resolution.presentation.action, .receiptScan)
    }

    func testResolveKeepsArchivedItemsSelection() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .archivedItems,
            input: makeInput()
        )

        XCTAssertEqual(resolution.selection, .archivedItems)
        XCTAssertEqual(resolution.presentation.icon, .systemImage("archivebox"))
        XCTAssertEqual(resolution.presentation.action, .archivedItems)
    }

    func testResolveKeepsFamilyOverviewSelection() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .familyOverview,
            input: makeInput()
        )

        XCTAssertEqual(resolution.selection, .familyOverview)
        XCTAssertEqual(resolution.presentation.icon, .systemImage("person.3"))
    }

    func testResolveKeepsSyncNowSelection() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .syncNow,
            input: makeInput()
        )

        XCTAssertEqual(resolution.selection, .syncNow)
        XCTAssertEqual(resolution.presentation.icon, .systemImage("arrow.triangle.2.circlepath.icloud"))
        XCTAssertEqual(resolution.presentation.action, .syncNow)
    }

    func testResolveKeepsInvestmentSelectionAsLocalAction() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .investment,
            input: makeInput()
        )

        XCTAssertEqual(resolution.selection, .investment)
        XCTAssertEqual(resolution.presentation.title, "Đầu tư")
        XCTAssertEqual(resolution.presentation.icon, .systemImage("chart.line.uptrend.xyaxis"))
        XCTAssertEqual(resolution.presentation.action, .investment)
        XCTAssertFalse(resolution.presentation.action.requiresRemoteAction)
    }

    func testRemoteCapablePinnedActionsRequireRemoteAvailability() {
        let familyID = UUID()
        let memberID = UUID()

        XCTAssertTrue(MistiaShortcutResolvedAction.familyOverview(familyID: familyID).requiresRemoteAction)
        XCTAssertTrue(MistiaShortcutResolvedAction.memberOverview(userID: memberID).requiresRemoteAction)
        XCTAssertTrue(MistiaShortcutResolvedAction.receiptScan.requiresRemoteAction)
        XCTAssertTrue(MistiaShortcutResolvedAction.syncNow.requiresRemoteAction)

        XCTAssertFalse(MistiaShortcutResolvedAction.backupRestore.requiresRemoteAction)
        XCTAssertFalse(MistiaShortcutResolvedAction.archivedItems.requiresRemoteAction)
    }

    func testResolveFallsBackToProfileWhenFamilyOverviewIsUnavailable() {
        let resolution = MistiaShortcutLogic.resolve(
            selection: .familyOverview,
            input: makeInput(
                familyID: nil,
                canOpenFamilyHome: false
            )
        )

        XCTAssertEqual(resolution.selection, .backupRestore)
        XCTAssertEqual(resolution.presentation.title, "Sao lưu & Khôi phục")
        XCTAssertEqual(
            resolution.presentation.icon,
            .systemImage("externaldrive.badge.icloud")
        )
    }

    func testResolveKeepsSelectedMemberWhenMemberCanBeViewed() {
        let memberID = UUID()
        let resolution = MistiaShortcutLogic.resolve(
            selection: MistiaShortcutSelection(kind: .familyMember, memberUserID: memberID),
            input: makeInput(
                members: [
                    MistiaShortcutMemberContext(
                        userID: memberID,
                        displayName: "Binh",
                        initials: "BI",
                        avatarURL: URL(string: "https://example.com/binh.png"),
                        canView: true,
                        isCurrentUser: false
                    )
                ]
            )
        )

        XCTAssertEqual(
            resolution.selection,
            MistiaShortcutSelection(kind: .familyMember, memberUserID: memberID)
        )
        XCTAssertEqual(resolution.presentation.title, "Binh")
        XCTAssertEqual(
            resolution.presentation.icon,
            .memberAvatar(initials: "BI", avatarURL: URL(string: "https://example.com/binh.png"))
        )
        XCTAssertEqual(resolution.presentation.action, .memberOverview(userID: memberID))
    }

    func testResolveFallsBackToProfileWhenMemberCannotBeViewed() {
        let memberID = UUID()
        let resolution = MistiaShortcutLogic.resolve(
            selection: MistiaShortcutSelection(kind: .familyMember, memberUserID: memberID),
            input: makeInput(
                members: [
                    MistiaShortcutMemberContext(
                        userID: memberID,
                        displayName: "Binh",
                        initials: "BI",
                        avatarURL: nil,
                        canView: false,
                        isCurrentUser: false
                    )
                ]
            )
        )

        XCTAssertEqual(resolution.selection, .backupRestore)
        XCTAssertEqual(resolution.presentation.title, "Sao lưu & Khôi phục")
    }

    func testResolveFallsBackToProfileWhenMemberMatchesCurrentUser() {
        let currentUserID = UUID()
        let resolution = MistiaShortcutLogic.resolve(
            selection: MistiaShortcutSelection(kind: .familyMember, memberUserID: currentUserID),
            input: makeInput(
                members: [
                    MistiaShortcutMemberContext(
                        userID: currentUserID,
                        displayName: "Quy",
                        initials: "QY",
                        avatarURL: nil,
                        canView: true,
                        isCurrentUser: true
                    )
                ]
            )
        )

        XCTAssertEqual(resolution.selection, .backupRestore)
        XCTAssertEqual(resolution.presentation.title, "Sao lưu & Khôi phục")
    }

    func testMemberShortcutTapPromptsExitWhenTargetIsAlreadyViewedMember() {
        let memberID = UUID()

        XCTAssertEqual(
            MistiaShortcutInteractionLogic.memberOverviewTapAction(
                targetUserID: memberID,
                currentViewedMemberUserID: memberID
            ),
            .promptExitMemberView
        )
    }

    private func makeInput(
        familyID: UUID? = UUID(),
        canOpenFamilyHome: Bool = true,
        members: [MistiaShortcutMemberContext] = []
    ) -> MistiaShortcutResolveInput {
        MistiaShortcutResolveInput(
            currentUserInitials: "QL",
            currentUserAvatarURL: URL(string: "file:///tmp/me.png"),
            familyID: familyID,
            canOpenFamilyHome: canOpenFamilyHome,
            members: members
        )
    }
}
