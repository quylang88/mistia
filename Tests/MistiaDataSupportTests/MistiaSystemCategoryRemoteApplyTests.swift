import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaSystemCategoryRemoteApplyTests: XCTestCase {
    func testStaleRemoteArchiveDoesNotHideNewerLocalDefaultSystemCategory() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let localUpdatedAt = remoteUpdatedAt.addingTimeInterval(3_600)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: categoryID,
            name: "Sinh hoạt",
            updatedAt: localUpdatedAt,
            isArchived: false,
            cloudSyncEnabled: false,
            remoteVersion: 7,
            in: container
        )

        let staleRemoteSnapshot = try makeRemoteSnapshot(
            userID: userID,
            key: categoryKey,
            id: categoryID,
            name: "Archived Sinh hoạt",
            updatedAt: remoteUpdatedAt,
            isArchived: true,
            remoteVersion: 8
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            staleRemoteSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: container
        )

        let category = try fetchCategory(id: categoryID, in: container)
        XCTAssertEqual(category.name, "Sinh hoạt")
        XCTAssertFalse(category.isArchived)
        XCTAssertNil(category.archivedAt)
        XCTAssertNil(category.deletedAt)
        XCTAssertEqual(category.updatedAt.timeIntervalSince1970, localUpdatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testNewerRemoteArchiveCanStillApplyToSystemCategory() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let localUpdatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let remoteUpdatedAt = localUpdatedAt.addingTimeInterval(3_600)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: categoryID,
            name: "Sinh hoạt",
            updatedAt: localUpdatedAt,
            isArchived: false,
            cloudSyncEnabled: false,
            remoteVersion: 7,
            in: container
        )

        let newerRemoteSnapshot = try makeRemoteSnapshot(
            userID: userID,
            key: categoryKey,
            id: categoryID,
            name: "Archived Sinh hoạt",
            updatedAt: remoteUpdatedAt,
            isArchived: true,
            remoteVersion: 8
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            newerRemoteSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: container
        )

        let category = try fetchCategory(id: categoryID, in: container)
        XCTAssertEqual(category.name, "Archived Sinh hoạt")
        XCTAssertTrue(category.isArchived)
        XCTAssertNotNil(category.archivedAt)
        XCTAssertEqual(category.updatedAt.timeIntervalSince1970, remoteUpdatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func insertSystemCategory(
        key: MistiaSystemCategoryParentKey,
        id: UUID,
        name: String,
        updatedAt: Date,
        isArchived: Bool,
        cloudSyncEnabled: Bool,
        remoteVersion: Int64,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let category = TransactionCategory(
            id: id,
            name: name,
            kind: key.kind,
            iconSymbolName: key.iconSymbolName,
            iconColorHex: key.iconColorHex,
            hierarchyRole: .parent,
            systemKey: key.rawValue,
            isSystem: true,
            cloudSyncEnabled: cloudSyncEnabled,
            sortOrder: 0,
            isArchived: isArchived,
            archivedAt: isArchived ? updatedAt : nil,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: updatedAt,
            remoteVersion: remoteVersion
        )
        context.insert(category)
        try context.save()
    }

    private func makeRemoteSnapshot(
        userID: UUID,
        key: MistiaSystemCategoryParentKey,
        id: UUID,
        name: String,
        updatedAt: Date,
        isArchived: Bool,
        remoteVersion: Int64
    ) throws -> MistiaRemoteSnapshot {
        let container = try makeContainer()
        try insertSystemCategory(
            key: key,
            id: id,
            name: name,
            updatedAt: updatedAt,
            isArchived: isArchived,
            cloudSyncEnabled: true,
            remoteVersion: remoteVersion,
            in: container
        )

        let snapshot = try MistiaSyncLocalStore.exportSnapshot(for: userID, from: container)
        XCTAssertEqual(snapshot.categories.count, 1)
        return snapshot
    }

    private func fetchCategory(id: UUID, in container: ModelContainer) throws -> TransactionCategory {
        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        return try XCTUnwrap(categories.first { $0.id == id })
    }
}
