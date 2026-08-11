import Foundation
import SwiftData

/// Frozen InvestmentAsset shape shipped in schema V8.
/// Keep this type unchanged so stores created by the previous release can migrate to V9.
enum MistiaSchemaV8InvestmentModels {
    @Model
    final class InvestmentAsset {
        @Attribute(.unique) var id: UUID
        var ownerUserID: UUID
        var channelID: UUID
        var name: String
        var currencyCode: String
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            ownerUserID: UUID,
            channelID: UUID,
            name: String,
            currencyCode: String,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.ownerUserID = ownerUserID
            self.channelID = channelID
            self.name = name
            self.currencyCode = currencyCode
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }
}
