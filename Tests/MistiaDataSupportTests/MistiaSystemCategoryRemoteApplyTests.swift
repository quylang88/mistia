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

    func testStaleRemoteSystemGuardStillImportsMemberCustomCategories() throws {
        let localUserID = UUID()
        let memberUserID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let customCategoryID = UUID()
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let localUpdatedAt = remoteUpdatedAt.addingTimeInterval(3_600)
        let container = try makeContainer()
        let remoteContainer = try makeContainer()

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
        try insertSystemCategory(
            key: categoryKey,
            id: categoryID,
            name: "Archived Sinh hoạt",
            updatedAt: remoteUpdatedAt,
            isArchived: true,
            cloudSyncEnabled: true,
            remoteVersion: 8,
            in: remoteContainer
        )
        try insertCustomCategory(
            id: customCategoryID,
            name: "Ăn sáng",
            kind: .expense,
            updatedAt: remoteUpdatedAt,
            in: remoteContainer
        )

        let remoteSnapshot = try MistiaSyncLocalStore.exportSnapshot(
            for: memberUserID,
            from: remoteContainer
        )
        XCTAssertEqual(remoteSnapshot.categories.count, 2)

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            remoteSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            familyCategoryScopedTo: localUserID,
            in: container
        )

        let memberRemoteSystemCategoryID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: categoryID,
            ownerUserID: memberUserID
        )
        let memberSystemCategoryID = MistiaSystemCategoryIdentity.familyScopedID(
            remoteCategoryID: memberRemoteSystemCategoryID,
            ownerUserID: memberUserID
        )
        let systemCategory = try fetchCategory(id: categoryID, in: container)
        let memberSystemCategory = try fetchCategory(id: memberSystemCategoryID, in: container)
        let customCategory = try fetchCategory(id: customCategoryID, in: container)
        let systemOwnerUserID = try fetchCategoryOwner(id: categoryID, in: container)
        let memberSystemOwnerUserID = try fetchCategoryOwner(id: memberSystemCategoryID, in: container)
        let customOwnerUserID = try fetchCategoryOwner(id: customCategoryID, in: container)
        XCTAssertEqual(systemCategory.name, "Sinh hoạt")
        XCTAssertFalse(systemCategory.isArchived)
        XCTAssertNil(systemOwnerUserID)
        XCTAssertEqual(memberSystemCategory.name, "Archived Sinh hoạt")
        XCTAssertTrue(memberSystemCategory.isArchived)
        XCTAssertEqual(memberSystemOwnerUserID, memberUserID)
        XCTAssertEqual(customCategory.name, "Ăn sáng")
        XCTAssertFalse(customCategory.isSystem)
        XCTAssertEqual(customOwnerUserID, memberUserID)
        XCTAssertEqual(customCategory.updatedAt.timeIntervalSince1970, remoteUpdatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFamilyImportKeepsMemberSystemCategorySeparateFromLocalSystemCategory() throws {
        let localUserID = UUID()
        let memberUserID = UUID()
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
        try MistiaRecordOwnershipStore.upsert(
            entity: .category,
            recordID: categoryID,
            ownerUserID: localUserID,
            updatedAt: localUpdatedAt,
            in: container
        )

        let memberSnapshot = try makeRemoteSnapshot(
            userID: memberUserID,
            key: categoryKey,
            id: categoryID,
            name: "Member Sinh hoạt",
            updatedAt: remoteUpdatedAt.addingTimeInterval(7_200),
            isArchived: false,
            remoteVersion: 12
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            memberSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            familyCategoryScopedTo: localUserID,
            in: container
        )

        let memberRemoteCategoryID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: categoryID,
            ownerUserID: memberUserID
        )
        let memberCategoryID = MistiaSystemCategoryIdentity.familyScopedID(
            remoteCategoryID: memberRemoteCategoryID,
            ownerUserID: memberUserID
        )
        let category = try fetchCategory(id: categoryID, in: container)
        let memberCategory = try fetchCategory(id: memberCategoryID, in: container)
        let ownerUserID = try fetchCategoryOwner(id: categoryID, in: container)
        let memberOwnerUserID = try fetchCategoryOwner(id: memberCategoryID, in: container)
        XCTAssertEqual(category.name, "Sinh hoạt")
        XCTAssertEqual(ownerUserID, localUserID)
        XCTAssertEqual(memberCategory.name, "Member Sinh hoạt")
        XCTAssertEqual(memberOwnerUserID, memberUserID)
    }

    func testSystemCategoryReconcileKeepsFamilyScopedMemberCategorySeparate() throws {
        let memberUserID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let memberRemoteCategoryID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: categoryID,
            ownerUserID: memberUserID
        )
        let memberCategoryID = MistiaSystemCategoryIdentity.familyScopedID(
            remoteCategoryID: memberRemoteCategoryID,
            ownerUserID: memberUserID
        )
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: categoryID,
            name: "Sinh hoạt",
            updatedAt: updatedAt,
            isArchived: false,
            cloudSyncEnabled: false,
            remoteVersion: 0,
            in: container
        )
        try insertSystemCategory(
            key: categoryKey,
            id: memberCategoryID,
            name: "Member Sinh hoạt",
            updatedAt: updatedAt.addingTimeInterval(600),
            isArchived: true,
            cloudSyncEnabled: true,
            remoteVersion: 8,
            in: container
        )
        try MistiaRecordOwnershipStore.upsert(
            entity: .category,
            recordID: memberCategoryID,
            ownerUserID: memberUserID,
            updatedAt: updatedAt,
            in: container
        )

        _ = try MistiaSystemCategorySyncSupport.reconcileDuplicateSystemCategories(
            modelContext: ModelContext(container)
        )

        let category = try fetchCategory(id: categoryID, in: container)
        let memberCategory = try fetchCategory(id: memberCategoryID, in: container)
        let memberOwnerUserID = try fetchCategoryOwner(id: memberCategoryID, in: container)
        XCTAssertEqual(category.name, "Sinh hoạt")
        XCTAssertEqual(memberCategory.name, "Member Sinh hoạt")
        XCTAssertTrue(memberCategory.isArchived)
        XCTAssertEqual(memberOwnerUserID, memberUserID)
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

    func testSystemCategoryArchiveDeleteAndCustomChangesAreSyncEligible() {
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let defaultCategory = makeSystemCategory(key: categoryKey)
        XCTAssertFalse(MistiaSystemCategorySyncSupport.shouldQueueCategoryMutation(defaultCategory))
        XCTAssertFalse(MistiaSystemCategorySyncSupport.shouldExportCategory(defaultCategory))

        let archivedCategory = makeSystemCategory(
            key: categoryKey,
            isArchived: true,
            archivedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldQueueCategoryMutation(archivedCategory))
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(archivedCategory))

        let deletedCategory = makeSystemCategory(
            key: categoryKey,
            deletedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldQueueCategoryMutation(deletedCategory))
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(deletedCategory))

        let renamedCategory = makeSystemCategory(key: categoryKey, name: "Sinh hoạt tuỳ chỉnh")
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldQueueCategoryMutation(renamedCategory))

        let retintedCategory = makeSystemCategory(key: categoryKey, iconColorHex: "#123456")
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(retintedCategory))

        let favoriteCategory = makeSystemCategory(key: categoryKey, isFavorite: true)
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(favoriteCategory))

        let reorderedCategory = makeSystemCategory(key: categoryKey, sortOrder: 999)
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(reorderedCategory))

        let childCategory = makeSystemCategory(key: MistiaSystemCategoryKey.dineOut)
        XCTAssertFalse(MistiaSystemCategorySyncSupport.shouldExportCategory(childCategory))

        let reparentedChildCategory = makeSystemCategory(
            key: MistiaSystemCategoryKey.dineOut,
            parentKey: .expenseOther
        )
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(reparentedChildCategory))

        let reorderedChildCategory = makeSystemCategory(
            key: MistiaSystemCategoryKey.dineOut,
            sortOrder: 999
        )
        XCTAssertTrue(MistiaSystemCategorySyncSupport.shouldExportCategory(reorderedChildCategory))
    }

    func testUploadSnapshotDoesNotExportStaleCloudSyncedDefaultSystemCategory() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: categoryID,
            name: categoryKey.title,
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000),
            isArchived: false,
            cloudSyncEnabled: true,
            remoteVersion: 4,
            in: container
        )

        let snapshot = try MistiaSyncLocalStore.exportSnapshotForUpload(
            for: userID,
            from: container
        )

        XCTAssertTrue(snapshot.categories.isEmpty)
    }

    func testUploadSnapshotStillExportsReferencedDefaultSystemCategoryDependencies() throws {
        let userID = UUID()
        let parentKey = MistiaSystemCategoryParentKey.expenseFood
        let childKey = MistiaSystemCategoryKey.dineOut
        let parent = makeSystemCategory(key: parentKey)
        let child = makeSystemCategory(key: childKey)
        child.parentCategory = parent
        child.cloudSyncEnabled = false
        parent.cloudSyncEnabled = false
        let transaction = LedgerTransaction(
            primaryKind: .expense,
            title: "Team lunch",
            amountMinor: 100_000,
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000),
            category: child
        )
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(parent)
        context.insert(child)
        context.insert(transaction)
        try context.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshotForUpload(
            for: userID,
            from: container
        )
        let categoryIDs = Set(snapshot.categories.map(\.id))

        XCTAssertEqual(categoryIDs, [
            MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: parentKey),
                ownerUserID: userID
            ),
            MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: childKey),
                ownerUserID: userID
            )
        ])
    }

    func testUploadSnapshotExportsLocallyPromotedSystemCategoryBeforeFirstRemoteVersion() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryKey.dineOut
        let category = makeSystemCategory(key: categoryKey)
        category.cloudSyncEnabled = true
        category.remoteVersion = 0
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(category.parentCategory!)
        context.insert(category)
        try context.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshotForUpload(
            for: userID,
            from: container
        )
        let categoryIDs = Set(snapshot.categories.map(\.id))

        XCTAssertTrue(categoryIDs.contains(
            MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: categoryKey),
                ownerUserID: userID
            )
        ))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSystemCategory(
        key: MistiaSystemCategoryParentKey,
        name: String? = nil,
        iconColorHex: String? = nil,
        isFavorite: Bool = false,
        sortOrder: Int? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> TransactionCategory {
        TransactionCategory(
            id: MistiaSystemCategoryIdentity.canonicalID(for: key),
            name: name ?? key.title,
            kind: key.kind,
            iconSymbolName: key.iconSymbolName,
            iconColorHex: iconColorHex ?? key.iconColorHex,
            isFavorite: isFavorite,
            hierarchyRole: .parent,
            systemKey: key.rawValue,
            isSystem: true,
            cloudSyncEnabled: false,
            sortOrder: sortOrder ?? MistiaSystemCategoryParentKey.activeDefaults.firstIndex(of: key) ?? 0,
            isArchived: isArchived,
            archivedAt: archivedAt,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000),
            deletedAt: deletedAt
        )
    }

    private func makeSystemCategory(
        key: MistiaSystemCategoryKey,
        name: String? = nil,
        iconColorHex: String? = nil,
        isFavorite: Bool = false,
        parentKey: MistiaSystemCategoryParentKey? = nil,
        sortOrder: Int? = nil,
        isArchived: Bool? = nil,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> TransactionCategory {
        let defaultParentKey = MistiaCategoryHierarchy.defaultParentKey(for: key)
        let resolvedParentKey = parentKey ?? defaultParentKey
        let parent = makeSystemCategory(key: resolvedParentKey)

        return TransactionCategory(
            id: MistiaSystemCategoryIdentity.canonicalID(for: key),
            name: name ?? key.title,
            kind: key.kind,
            iconSymbolName: key.iconSymbolName,
            iconColorHex: iconColorHex ?? key.iconColorHex,
            isFavorite: isFavorite,
            parentCategory: parent,
            hierarchyRole: .child,
            systemKey: key.rawValue,
            isSystem: true,
            cloudSyncEnabled: false,
            sortOrder: sortOrder ?? MistiaSystemCategoryKey.activeDefaults.firstIndex(of: key) ?? 0,
            isArchived: isArchived ?? !key.isActiveDefault,
            archivedAt: archivedAt,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000),
            deletedAt: deletedAt
        )
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

    private func insertCustomCategory(
        id: UUID,
        name: String,
        kind: TransactionCategoryKind,
        updatedAt: Date,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let category = TransactionCategory(
            id: id,
            name: name,
            kind: kind,
            iconSymbolName: "fork.knife",
            iconColorHex: "#FF8A00",
            isFavorite: true,
            hierarchyRole: .child,
            isSystem: false,
            cloudSyncEnabled: true,
            sortOrder: 20,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: updatedAt
        )
        context.insert(category)
        try context.save()
    }

    private func fetchCategory(id: UUID, in container: ModelContainer) throws -> TransactionCategory {
        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        return try XCTUnwrap(categories.first { $0.id == id })
    }

    private func fetchCategoryOwner(id: UUID, in container: ModelContainer) throws -> UUID? {
        try MistiaRecordOwnershipStore.ownerUserID(
            entity: .category,
            recordID: id,
            in: container
        )
    }
}
