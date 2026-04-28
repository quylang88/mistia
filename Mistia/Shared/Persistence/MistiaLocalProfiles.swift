import Foundation

enum MistiaLocalProfileKind: String, Codable {
    case cloudUser
    case guestUnbound
}

struct MistiaLocalProfileDescriptor: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: MistiaLocalProfileKind
    var cloudUserID: UUID?
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        kind: MistiaLocalProfileKind,
        cloudUserID: UUID? = nil,
        createdAt: Date = .now,
        lastUsedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.cloudUserID = cloudUserID
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    var isCloudUserProfile: Bool {
        kind == .cloudUser && cloudUserID != nil
    }
}
