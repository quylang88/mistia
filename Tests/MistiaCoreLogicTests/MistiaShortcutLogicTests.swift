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
        XCTAssertEqual(resolution.presentation.icon, .systemImage("externaldrive.fill.badge.icloud"))
        XCTAssertEqual(resolution.presentation.action, .backupRestore)
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
            .systemImage("externaldrive.fill.badge.icloud")
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
