import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaSystemCategoryRemoteApplyTests: XCTestCase {
    func testSyncUploadRecordDecodeReadsSnakeCaseUserIDPayload() throws {
        let userID = UUID()
        let walletID = UUID()
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let row = RemoteLedgerWallet(
            userID: userID,
            id: walletID,
            name: "Cloud wallet",
            kindRawValue: LedgerWalletKind.cash.rawValue,
            iconSymbolName: "wallet.pass.fill",
            iconColorHex: "#6E3BC2",
            currencyCode: "JPY",
            openingBalanceMinor: 2_000,
            institutionDisplayName: nil,
            institutionPresetKey: nil,
            sortOrder: 1,
            isArchived: false,
            archivedAt: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncVersion: 4,
            lastModifiedByDeviceID: UUID()
        )

        let json = try MistiaSyncUploadRecord.wallet(row).asJSONString()
        XCTAssertTrue(json.contains("user_id"))

        guard case .wallet(let decoded) = try MistiaSyncUploadRecord.decode(entity: .wallet, jsonString: json) else {
            return XCTFail("Expected wallet payload")
        }
        XCTAssertEqual(decoded.userID, userID)
        XCTAssertEqual(decoded.name, "Cloud wallet")
    }

    func testSystemCategoryExportKeepsOneRecordWithLocalizedNameColumns() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(
            TransactionCategory(
                id: MistiaSystemCategoryIdentity.canonicalID(for: categoryKey),
                name: categoryKey.japaneseTitle,
                kind: categoryKey.kind,
                iconSymbolName: categoryKey.iconSymbolName,
                iconColorHex: categoryKey.iconColorHex,
                hierarchyRole: .parent,
                systemKey: categoryKey.rawValue,
                isSystem: true,
                cloudSyncEnabled: true,
                sortOrder: 0
            )
        )
        try context.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshot(for: userID, from: container)

        XCTAssertEqual(snapshot.categories.count, 1)
        XCTAssertEqual(snapshot.categories.first?.name, categoryKey.legacyVietnameseName)
        XCTAssertEqual(snapshot.categories.first?.nameEnglish, categoryKey.englishTitle)
        XCTAssertEqual(snapshot.categories.first?.nameJapanese, categoryKey.japaneseTitle)
    }

    func testRemoteSystemCategoryApplyNormalizesLocalizedNameColumns() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()
        let remoteSnapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [
                RemoteTransactionCategory(
                    userID: userID,
                    id: categoryID,
                    name: categoryKey.englishTitle,
                    kindRawValue: categoryKey.kind.rawValue,
                    iconSymbolName: categoryKey.iconSymbolName,
                    iconColorHex: categoryKey.iconColorHex,
                    isFavorite: false,
                    parentCategoryID: nil,
                    hierarchyRoleRawValue: TransactionCategoryHierarchyRole.parent.rawValue,
                    systemKey: categoryKey.rawValue,
                    isSystem: true,
                    sortOrder: 0,
                    isArchived: false,
                    archivedAt: nil,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    syncVersion: 1,
                    lastModifiedByDeviceID: nil
                )
            ],
            settlementGroups: [],
            settlementParticipants: [],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            remoteSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: container
        )

        let category = try fetchCategory(id: categoryID, in: container)
        XCTAssertEqual(category.name, categoryKey.legacyVietnameseName)
        XCTAssertEqual(category.nameEnglish, categoryKey.englishTitle)
        XCTAssertEqual(category.nameJapanese, categoryKey.japaneseTitle)
    }

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

    func testExplicitCloudConflictResolutionCanOverwriteNewerLocalSystemCategory() throws {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let localUpdatedAt = remoteUpdatedAt.addingTimeInterval(3_600)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: categoryID,
            name: "Local active",
            updatedAt: localUpdatedAt,
            isArchived: false,
            cloudSyncEnabled: false,
            remoteVersion: 7,
            in: container
        )

        let remoteSnapshot = try makeRemoteSnapshot(
            userID: userID,
            key: categoryKey,
            id: categoryID,
            name: "Cloud archived",
            updatedAt: remoteUpdatedAt,
            isArchived: true,
            remoteVersion: 8
        )
        guard let remoteCategory = remoteSnapshot.categories.first else {
            return XCTFail("Expected remote category")
        }

        try MistiaSyncLocalStore.applyRemoteRecord(
            .category(remoteCategory),
            preservesLocalSystemDefaults: false,
            in: container
        )

        let category = try fetchCategory(id: categoryID, in: container)
        XCTAssertEqual(category.name, "Cloud archived")
        XCTAssertTrue(category.isArchived)
        XCTAssertEqual(category.remoteVersion, 8)
        XCTAssertEqual(category.updatedAt.timeIntervalSince1970, remoteUpdatedAt.timeIntervalSince1970, accuracy: 0.001)
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
        let memberSystemCategoryID = memberRemoteSystemCategoryID
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
        let memberCategoryID = memberRemoteCategoryID
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

    func testFamilyImportKeepsMemberCustomCategorySeparateWhenNameAndKindMatchLocalCategory() throws {
        let localUserID = UUID()
        let memberUserID = UUID()
        let localCategoryID = UUID()
        let memberCategoryID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()
        let remoteContainer = try makeContainer()

        try insertCustomCategory(
            id: localCategoryID,
            name: "Ăn sáng",
            kind: .expense,
            updatedAt: updatedAt,
            in: container
        )
        try MistiaRecordOwnershipStore.upsert(
            entity: .category,
            recordID: localCategoryID,
            ownerUserID: localUserID,
            updatedAt: updatedAt,
            in: container
        )
        try insertCustomCategory(
            id: memberCategoryID,
            name: "Ăn sáng",
            kind: .expense,
            updatedAt: updatedAt.addingTimeInterval(600),
            in: remoteContainer
        )

        let remoteSnapshot = try MistiaSyncLocalStore.exportSnapshot(for: memberUserID, from: remoteContainer)
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            remoteSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: [memberUserID],
            in: container
        )

        let localCategory = try fetchCategory(id: localCategoryID, in: container)
        let memberCategory = try fetchCategory(id: memberCategoryID, in: container)
        XCTAssertEqual(localCategory.name, "Ăn sáng")
        XCTAssertEqual(memberCategory.name, "Ăn sáng")
        XCTAssertFalse(memberCategory.isSystem)
        XCTAssertEqual(try fetchCategoryOwner(id: localCategoryID, in: container), localUserID)
        XCTAssertEqual(try fetchCategoryOwner(id: memberCategoryID, in: container), memberUserID)
        XCTAssertNotEqual(localCategory.id, memberCategory.id)
    }

    func testFamilyImportRepointsLegacyFamilyScopedSystemCategoryToCloudID() throws {
        let localUserID = UUID()
        let memberUserID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let memberRemoteCategoryID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: canonicalID,
            ownerUserID: memberUserID
        )
        let legacyCategoryID = MistiaSystemCategoryIdentity.familyScopedID(
            remoteCategoryID: memberRemoteCategoryID,
            ownerUserID: memberUserID
        )
        let transactionID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: legacyCategoryID,
            name: "Legacy Member Sinh hoạt",
            updatedAt: updatedAt,
            isArchived: false,
            cloudSyncEnabled: true,
            remoteVersion: 7,
            in: container
        )
        try MistiaRecordOwnershipStore.upsert(
            entity: .category,
            recordID: legacyCategoryID,
            ownerUserID: memberUserID,
            updatedAt: updatedAt,
            in: container
        )
        try insertTransaction(
            id: transactionID,
            title: "Member lunch",
            categoryID: legacyCategoryID,
            ownerUserID: memberUserID,
            updatedAt: updatedAt,
            in: container
        )

        let memberSnapshot = try makeRemoteSnapshot(
            userID: memberUserID,
            key: categoryKey,
            id: canonicalID,
            name: "Member Sinh hoạt",
            updatedAt: updatedAt.addingTimeInterval(600),
            isArchived: false,
            remoteVersion: 8
        )
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            memberSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: [memberUserID],
            in: container
        )

        let memberCategory = try fetchCategory(id: memberRemoteCategoryID, in: container)
        let legacyCategory = try fetchCategory(id: legacyCategoryID, in: container)
        let transaction = try fetchTransaction(id: transactionID, in: container)
        XCTAssertEqual(memberCategory.name, "Member Sinh hoạt")
        XCTAssertEqual(try fetchCategoryOwner(id: memberRemoteCategoryID, in: container), memberUserID)
        XCTAssertEqual(transaction.category?.id, memberRemoteCategoryID)
        XCTAssertNotNil(legacyCategory.deletedAt)
        XCTAssertFalse(legacyCategory.cloudSyncEnabled)
    }

    func testFamilyImportRepointsOnlyMemberReferencesWhenLegacyCategoryUsedCanonicalID() throws {
        let localUserID = UUID()
        let memberUserID = UUID()
        let categoryKey = MistiaSystemCategoryParentKey.expenseFood
        let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let memberRemoteCategoryID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: canonicalID,
            ownerUserID: memberUserID
        )
        let selfTransactionID = UUID()
        let memberTransactionID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let container = try makeContainer()

        try insertSystemCategory(
            key: categoryKey,
            id: canonicalID,
            name: "Sinh hoạt",
            updatedAt: updatedAt,
            isArchived: false,
            cloudSyncEnabled: false,
            remoteVersion: 0,
            in: container
        )
        try MistiaRecordOwnershipStore.upsert(
            entity: .category,
            recordID: canonicalID,
            ownerUserID: memberUserID,
            updatedAt: updatedAt,
            in: container
        )
        try insertTransaction(
            id: selfTransactionID,
            title: "Self lunch",
            categoryID: canonicalID,
            ownerUserID: localUserID,
            updatedAt: updatedAt,
            in: container
        )
        try insertTransaction(
            id: memberTransactionID,
            title: "Member lunch",
            categoryID: canonicalID,
            ownerUserID: memberUserID,
            updatedAt: updatedAt,
            in: container
        )

        let memberSnapshot = try makeRemoteSnapshot(
            userID: memberUserID,
            key: categoryKey,
            id: canonicalID,
            name: "Member Sinh hoạt",
            updatedAt: updatedAt.addingTimeInterval(600),
            isArchived: false,
            remoteVersion: 8
        )
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            memberSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: [memberUserID],
            in: container
        )

        let selfTransaction = try fetchTransaction(id: selfTransactionID, in: container)
        let memberTransaction = try fetchTransaction(id: memberTransactionID, in: container)
        let canonicalCategory = try fetchCategory(id: canonicalID, in: container)
        XCTAssertEqual(selfTransaction.category?.id, canonicalID)
        XCTAssertEqual(memberTransaction.category?.id, memberRemoteCategoryID)
        XCTAssertNil(canonicalCategory.deletedAt)
        XCTAssertNil(try fetchCategoryOwner(id: canonicalID, in: container))
        XCTAssertEqual(try fetchCategoryOwner(id: memberRemoteCategoryID, in: container), memberUserID)
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

    func testUploadSnapshotExportsDefaultSystemCategory() throws {
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

        XCTAssertEqual(snapshot.categories.map(\.id), [
            MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: categoryID,
                ownerUserID: userID
            )
        ])
    }

    func testCategoryMutationExportsDefaultChildCategory() throws {
        let userID = UUID()
        let childKey = MistiaSystemCategoryKey.dineOut
        let child = makeSystemCategory(key: childKey)
        let parent = try XCTUnwrap(child.parentCategory)
        child.cloudSyncEnabled = true
        child.remoteVersion = 1
        parent.cloudSyncEnabled = true
        parent.remoteVersion = 1
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(parent)
        context.insert(child)
        try context.save()

        let mutation = MistiaSyncMutation(
            entity: .category,
            recordID: child.id,
            subjectUserID: userID,
            kind: .upsert,
            modifiedAt: child.updatedAt,
            baseVersion: child.remoteVersion
        )

        let record = try MistiaSyncLocalStore.exportRecord(for: mutation, from: container)

        guard case .category(let row) = record else {
            return XCTFail("Expected exported category")
        }
        XCTAssertEqual(
            row.id,
            MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: childKey),
                ownerUserID: userID
            )
        )
    }

    func testExportCategoryRecordSynthesizesMissingSystemParent() throws {
        let userID = UUID()
        let parentKey = MistiaSystemCategoryParentKey.expenseFood
        let remoteParentID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: parentKey),
            ownerUserID: userID
        )

        let record = try MistiaSyncLocalStore.exportCategoryRecord(
            remoteCategoryID: remoteParentID,
            subjectUserID: userID,
            from: try makeContainer()
        )

        guard case .category(let row) = record else {
            return XCTFail("Expected synthesized parent category")
        }

        XCTAssertEqual(row.id, remoteParentID)
        XCTAssertEqual(row.systemKey, parentKey.rawValue)
        XCTAssertNil(row.parentCategoryID)
        XCTAssertNil(row.deletedAt)
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
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
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

    private func insertTransaction(
        id: UUID,
        title: String,
        categoryID: UUID,
        ownerUserID: UUID,
        updatedAt: Date,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let category = try XCTUnwrap(categories.first { $0.id == categoryID })
        let transaction = LedgerTransaction(
            id: id,
            primaryKind: .expense,
            title: title,
            amountMinor: 100_000,
            updatedAt: updatedAt,
            category: category
        )
        context.insert(transaction)
        context.insert(OwnedRecordScope(entity: .transaction, recordID: id, ownerUserID: ownerUserID, updatedAt: updatedAt))
        try context.save()
    }

    private func fetchTransaction(id: UUID, in container: ModelContainer) throws -> LedgerTransaction {
        let context = ModelContext(container)
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        return try XCTUnwrap(transactions.first { $0.id == id })
    }
}
