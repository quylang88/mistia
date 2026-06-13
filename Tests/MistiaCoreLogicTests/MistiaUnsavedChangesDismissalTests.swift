import XCTest
@testable import MistiaCoreLogic

final class MistiaUnsavedChangesDismissalTests: XCTestCase {
    func testCreationPromptUsesProfessionalDiscardCopy() {
        let prompt = MistiaUnsavedChangesDismissalPrompt(mode: .creating)

        XCTAssertEqual(prompt.title, "Đóng mà không lưu?")
        XCTAssertEqual(prompt.message, "Thông tin bạn vừa nhập chưa được lưu. Nếu đóng bây giờ, các thay đổi này sẽ bị mất.")
        XCTAssertEqual(prompt.cancelButtonTitle, "Hủy")
        XCTAssertEqual(prompt.discardButtonTitle, "Đóng")
    }

    func testEditingPromptExplainsChangedDataWillNotBeSaved() {
        let prompt = MistiaUnsavedChangesDismissalPrompt(mode: .editing)

        XCTAssertEqual(prompt.title, "Bỏ thay đổi?")
        XCTAssertEqual(prompt.message, "Bạn đã chỉnh sửa nội dung nhưng chưa lưu. Nếu đóng bây giờ, các thay đổi này sẽ không được áp dụng.")
        XCTAssertEqual(prompt.cancelButtonTitle, "Hủy")
        XCTAssertEqual(prompt.discardButtonTitle, "Đóng")
    }

    func testDismissalDecisionOnlyRequiresConfirmationWhenDraftChanged() {
        XCTAssertEqual(
            MistiaUnsavedChangesDismissalDecision.make(hasUnsavedChanges: false),
            .dismissImmediately
        )
        XCTAssertEqual(
            MistiaUnsavedChangesDismissalDecision.make(hasUnsavedChanges: true),
            .confirmDiscard
        )
    }

    func testSharedExpenseEditDetectsPersistedLinkedBillAddedDuringSession() {
        let billID = UUID(uuidString: "AA67B2E4-4F28-44C1-8D5D-5BB71936C1A9")!
        let baseline = MistiaSharedExpenseDismissalSnapshot(
            eventTitle: "Tokyo Trip",
            participantRows: [],
            selectedSharedWalletID: nil,
            selectedSharedCategoryID: nil,
            eventNote: "",
            linkedBillIDs: [],
            billRows: []
        )
        let current = MistiaSharedExpenseDismissalSnapshot(
            eventTitle: "Tokyo Trip",
            participantRows: [],
            selectedSharedWalletID: nil,
            selectedSharedCategoryID: nil,
            eventNote: "",
            linkedBillIDs: [billID],
            billRows: []
        )

        XCTAssertTrue(
            MistiaSharedExpenseDismissalDecision.hasUnsavedChanges(
                baseline: baseline,
                current: current
            )
        )
    }
}
