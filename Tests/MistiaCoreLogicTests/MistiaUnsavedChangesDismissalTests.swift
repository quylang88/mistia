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
}
