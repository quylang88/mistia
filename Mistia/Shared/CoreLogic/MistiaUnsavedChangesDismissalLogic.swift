import Foundation

public enum MistiaUnsavedChangesDismissalMode: Equatable {
    case creating
    case editing
}

public struct MistiaUnsavedChangesDismissalPrompt: Equatable {
    public let title: String
    public let message: String
    public let cancelButtonTitle: String
    public let discardButtonTitle: String

    public init(mode: MistiaUnsavedChangesDismissalMode) {
        switch mode {
        case .creating:
            title = "Đóng mà không lưu?"
            message = "Thông tin bạn vừa nhập chưa được lưu. Nếu đóng bây giờ, các thay đổi này sẽ bị mất."
        case .editing:
            title = "Bỏ thay đổi?"
            message = "Bạn đã chỉnh sửa nội dung nhưng chưa lưu. Nếu đóng bây giờ, các thay đổi này sẽ không được áp dụng."
        }

        cancelButtonTitle = "Hủy"
        discardButtonTitle = "Đóng"
    }
}

public enum MistiaUnsavedChangesDismissalDecision: Equatable {
    case dismissImmediately
    case confirmDiscard

    public static func make(hasUnsavedChanges: Bool) -> Self {
        hasUnsavedChanges ? .confirmDiscard : .dismissImmediately
    }
}

public struct MistiaSharedExpenseParticipantDismissalSnapshot: Equatable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MistiaSharedExpenseBillDismissalSnapshot: Equatable {
    public let id: UUID
    public let modeRawValue: String
    public let hasStagedTransaction: Bool
    public let existingTransactionID: UUID?

    public init(
        id: UUID,
        modeRawValue: String,
        hasStagedTransaction: Bool,
        existingTransactionID: UUID?
    ) {
        self.id = id
        self.modeRawValue = modeRawValue
        self.hasStagedTransaction = hasStagedTransaction
        self.existingTransactionID = existingTransactionID
    }
}

public struct MistiaSharedExpenseDismissalSnapshot: Equatable {
    public let eventTitle: String
    public let participantRows: [MistiaSharedExpenseParticipantDismissalSnapshot]
    public let selectedSharedWalletID: UUID?
    public let selectedSharedCategoryID: UUID?
    public let eventNote: String
    public let linkedBillIDs: [UUID]
    public let billRows: [MistiaSharedExpenseBillDismissalSnapshot]

    public init(
        eventTitle: String,
        participantRows: [MistiaSharedExpenseParticipantDismissalSnapshot],
        selectedSharedWalletID: UUID?,
        selectedSharedCategoryID: UUID?,
        eventNote: String,
        linkedBillIDs: [UUID],
        billRows: [MistiaSharedExpenseBillDismissalSnapshot]
    ) {
        self.eventTitle = eventTitle
        self.participantRows = participantRows
        self.selectedSharedWalletID = selectedSharedWalletID
        self.selectedSharedCategoryID = selectedSharedCategoryID
        self.eventNote = eventNote
        self.linkedBillIDs = linkedBillIDs
        self.billRows = billRows
    }
}

public enum MistiaSharedExpenseDismissalDecision {
    public static func hasUnsavedChanges(
        baseline: MistiaSharedExpenseDismissalSnapshot,
        current: MistiaSharedExpenseDismissalSnapshot
    ) -> Bool {
        baseline != current
    }
}
