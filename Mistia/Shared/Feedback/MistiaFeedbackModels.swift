import Foundation

public enum MistiaFeedbackCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug = "bug"
    case feature = "feature"
    case general = "general"

    public var id: String { rawValue }
}

public struct MistiaFeedbackSubmission: Codable, Sendable {
    public let category: MistiaFeedbackCategory
    public let rating: Int?
    public let content: String
    public let deviceInfo: [String: String]?

    public init(
        category: MistiaFeedbackCategory,
        rating: Int? = nil,
        content: String,
        deviceInfo: [String: String]? = nil
    ) {
        self.category = category
        self.rating = rating
        self.content = content
        self.deviceInfo = deviceInfo
    }
}
