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
