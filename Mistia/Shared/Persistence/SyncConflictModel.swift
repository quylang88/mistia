import Foundation
import SwiftData

@Model
nonisolated final class SyncConflict {
    @Attribute(.unique) var id: UUID
    var entityRawValue: String
    var recordID: UUID
    var conflictKindRawValue: String
    var localPayloadJSON: String
    var remotePayloadJSON: String
    var baseVersion: Int64
    var remoteVersion: Int64
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityRawValue: String,
        recordID: UUID,
        conflictKindRawValue: String,
        localPayloadJSON: String,
        remotePayloadJSON: String,
        baseVersion: Int64,
        remoteVersion: Int64,
        createdAt: Date = .now
    ) {
        self.id = id
        self.entityRawValue = entityRawValue
        self.recordID = recordID
        self.conflictKindRawValue = conflictKindRawValue
        self.localPayloadJSON = localPayloadJSON
        self.remotePayloadJSON = remotePayloadJSON
        self.baseVersion = baseVersion
        self.remoteVersion = remoteVersion
        self.createdAt = createdAt
    }
}
