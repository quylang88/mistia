import XCTest
@testable import MistiaCoreLogic

final class FamilyMemberViewingToolbarLogicTests: XCTestCase {
    func testPresentationUsesMemberNameForExitPromptAndAccessibility() {
        let presentation = FamilyMemberViewingToolbarLogic.presentation(
            displayName: "Trang Nguyen"
        )

        XCTAssertEqual(presentation.initials, "TR")
        XCTAssertEqual(presentation.exitTitle, L10n.shared.family.memberViewing.exitTitle)
        XCTAssertEqual(
            presentation.exitMessage,
            L10n.shared.family.memberViewing.exitMessage("Trang Nguyen")
        )
        XCTAssertEqual(
            presentation.accessibilityLabel,
            L10n.shared.family.memberViewing.avatarAccessibility("Trang Nguyen")
        )
    }

    func testPresentationFallsBackToTwoUppercaseCharactersForShortNames() {
        let presentation = FamilyMemberViewingToolbarLogic.presentation(displayName: "an")

        XCTAssertEqual(presentation.initials, "AN")
    }
}
