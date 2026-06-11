import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class MistiaSystemCategorySyncSupportTests: XCTestCase {
    func testOwnerMapKeepsLatestDuplicateScope() {
        let recordID = UUID()
        let ownerA = UUID()
        let ownerB = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_770_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let scopes = [
            OwnedRecordScope(
                entity: .category,
                recordID: recordID,
                ownerUserID: ownerA,
                updatedAt: olderDate
            ),
            OwnedRecordScope(
                entity: .category,
                recordID: recordID,
                ownerUserID: ownerB,
                updatedAt: newerDate
            )
        ]

        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .category)

        XCTAssertEqual(ownerMap[recordID], ownerB)
    }

    func testReconcileDuplicateSystemCategoriesDeletesSameIDDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let categoryID = MistiaSystemCategoryIdentity.canonicalID(for: .importGoods)
        let olderDate = Date(timeIntervalSince1970: 1_770_000_000)
        let newerDate = olderDate.addingTimeInterval(60)

        let original = makeImportGoodsCategory(
            id: categoryID,
            name: "Nhập hàng",
            updatedAt: olderDate,
            remoteVersion: 0,
            cloudSyncEnabled: false
        )
        let duplicate = makeImportGoodsCategory(
            id: categoryID,
            name: "Nhập hàng đã chỉnh",
            updatedAt: newerDate,
            remoteVersion: 3,
            cloudSyncEnabled: true
        )
        let transaction = LedgerTransaction(
            primaryKind: .expense,
            title: "Mua hàng",
            amountMinor: 10_000,
            updatedAt: olderDate,
            remoteVersion: 2,
            category: duplicate
        )

        context.insert(original)
        context.insert(duplicate)
        context.insert(transaction)

        let result = try MistiaSystemCategorySyncSupport.reconcileDuplicateSystemCategories(
            modelContext: context
        )

        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(categories.count, 1)
        let remaining = try XCTUnwrap(categories.first)
        XCTAssertEqual(remaining.id, categoryID)
        XCTAssertEqual(remaining.name, "Nhập hàng đã chỉnh")
        XCTAssertEqual(remaining.remoteVersion, 3)
        XCTAssertTrue(remaining.cloudSyncEnabled)
        XCTAssertEqual(transaction.category?.id, categoryID)
        XCTAssertEqual(transaction.category?.name, "Nhập hàng đã chỉnh")
        XCTAssertTrue(result.categoryIDsNeedingSync.contains(categoryID))
        XCTAssertTrue(result.transactionIDsNeedingSync.contains(transaction.id))
    }

    func testReconcileDuplicateSystemCategoriesDeletesCustomSameIDDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let categoryID = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_770_000_000)
        let newerDate = olderDate.addingTimeInterval(60)

        let original = makeCustomCategory(
            id: categoryID,
            name: "Old custom",
            updatedAt: olderDate,
            remoteVersion: 0,
            cloudSyncEnabled: false
        )
        let duplicate = makeCustomCategory(
            id: categoryID,
            name: "New custom",
            updatedAt: newerDate,
            remoteVersion: 4,
            cloudSyncEnabled: true
        )
        let transaction = LedgerTransaction(
            primaryKind: .expense,
            title: "Custom category spending",
            amountMinor: 20_000,
            updatedAt: olderDate,
            remoteVersion: 2,
            category: original
        )

        context.insert(original)
        context.insert(duplicate)
        context.insert(transaction)

        let result = try MistiaSystemCategorySyncSupport.reconcileDuplicateSystemCategories(
            modelContext: context
        )

        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(categories.count, 1)
        let remaining = try XCTUnwrap(categories.first)
        XCTAssertEqual(remaining.id, categoryID)
        XCTAssertEqual(remaining.name, "New custom")
        XCTAssertEqual(remaining.remoteVersion, 4)
        XCTAssertTrue(remaining.cloudSyncEnabled)
        XCTAssertEqual(transaction.category?.id, categoryID)
        XCTAssertEqual(transaction.category?.name, "New custom")
        XCTAssertTrue(result.categoryIDsNeedingSync.contains(categoryID))
        XCTAssertTrue(result.transactionIDsNeedingSync.contains(transaction.id))
    }

    func testRemoteSystemCategoryDedupeKeepsCloudScopedIDAndRemapsReferences() {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryKey.electricity
        let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let cloudScopedID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: canonicalID,
            ownerUserID: userID
        )
        let olderDate = Date(timeIntervalSince1970: 1_770_000_000)
        let newerDate = olderDate.addingTimeInterval(3_600)
        let canonicalRow = makeRemoteSystemCategory(
            userID: userID,
            id: canonicalID,
            key: categoryKey,
            name: "Điện Ga",
            updatedAt: newerDate
        )
        let cloudScopedRow = makeRemoteSystemCategory(
            userID: userID,
            id: cloudScopedID,
            key: categoryKey,
            name: "Electricity",
            updatedAt: olderDate
        )
        let budget = RemoteBudgetPlan(
            userID: userID,
            id: UUID(),
            categoryID: canonicalID,
            monthAnchor: olderDate,
            limitMinor: 100_000,
            rolloverEnabled: false,
            currencyCode: "VND",
            isArchived: false,
            createdAt: olderDate,
            updatedAt: olderDate,
            deletedAt: nil,
            syncVersion: 1,
            lastModifiedByDeviceID: nil
        )
        let snapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [canonicalRow, cloudScopedRow],
            settlementGroups: [],
            settlementObligations: [],
            transactions: [],
            budgetPlans: [budget],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )

        let deduped = MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(snapshot)

        XCTAssertEqual(deduped.categories.count, 1)
        XCTAssertEqual(deduped.categories.first?.id, cloudScopedID)
        XCTAssertEqual(deduped.categories.first?.name, "Điện Ga")
        XCTAssertEqual(deduped.budgetPlans.first?.categoryID, cloudScopedID)
    }

    func testRemoteSystemCategoryDedupeCanNormalizeLegacyCanonicalRowForUpload() {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryKey.parking
        let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let cloudScopedID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: canonicalID,
            ownerUserID: userID
        )
        let updatedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let canonicalRow = makeRemoteSystemCategory(
            userID: userID,
            id: canonicalID,
            key: categoryKey,
            name: "Gửi xe",
            updatedAt: updatedAt
        )
        let snapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [canonicalRow],
            settlementGroups: [],
            settlementObligations: [],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )

        let deduped = MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
            snapshot,
            preferCloudScopedIDs: true
        )

        XCTAssertEqual(deduped.categories.count, 1)
        XCTAssertEqual(deduped.categories.first?.id, cloudScopedID)
        XCTAssertEqual(deduped.categories.first?.name, "Gửi xe")
    }

    func testRemoteSystemCategoryDedupeDoesNotResurrectDeletedOnlyRows() {
        let userID = UUID()
        let categoryKey = MistiaSystemCategoryKey.parking
        let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: categoryKey)
        let deletedAt = Date(timeIntervalSince1970: 1_770_003_600)
        var deletedRow = makeRemoteSystemCategory(
            userID: userID,
            id: canonicalID,
            key: categoryKey,
            name: "Gửi xe",
            updatedAt: deletedAt
        )
        deletedRow.deletedAt = deletedAt
        let snapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [deletedRow],
            settlementGroups: [],
            settlementObligations: [],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )

        let deduped = MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
            snapshot,
            preferCloudScopedIDs: true
        )

        XCTAssertEqual(deduped.categories.count, 1)
        XCTAssertEqual(deduped.categories.first?.deletedAt, deletedAt)
    }

    func testFamilyRefreshPrunesStaleFamilyScopedSystemCategories() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let localUserID = UUID()
        let memberUserID = UUID()
        let categoryKey = MistiaSystemCategoryKey.electricity
        let olderRemoteID = UUID()
        let currentRemoteID = MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: categoryKey),
            ownerUserID: memberUserID
        )
        let staleLocalID = MistiaSystemCategoryIdentity.familyScopedID(
            remoteCategoryID: olderRemoteID,
            ownerUserID: memberUserID
        )
        let currentLocalID = MistiaSystemCategoryIdentity.familyScopedID(
            remoteCategoryID: currentRemoteID,
            ownerUserID: memberUserID
        )
        let olderDate = Date(timeIntervalSince1970: 1_770_000_000)
        let staleCategory = TransactionCategory(
            id: staleLocalID,
            name: "Điện Ga",
            kind: .expense,
            iconSymbolName: categoryKey.iconSymbolName,
            iconColorHex: categoryKey.iconColorHex,
            hierarchyRole: .child,
            systemKey: categoryKey.rawValue,
            isSystem: true,
            cloudSyncEnabled: true,
            sortOrder: 0,
            createdAt: olderDate,
            updatedAt: olderDate,
            remoteVersion: 1
        )
        let transaction = LedgerTransaction(
            primaryKind: .expense,
            title: "Electric bill",
            amountMinor: 10_000,
            updatedAt: olderDate,
            remoteVersion: 1,
            category: staleCategory
        )
        context.insert(staleCategory)
        context.insert(transaction)
        context.insert(
            OwnedRecordScope(
                entity: .category,
                recordID: staleLocalID,
                ownerUserID: memberUserID,
                updatedAt: olderDate
            )
        )

        let remoteRow = makeRemoteSystemCategory(
            userID: memberUserID,
            id: currentRemoteID,
            key: categoryKey,
            name: "Điện Ga",
            updatedAt: olderDate.addingTimeInterval(60)
        )
        let snapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [remoteRow],
            settlementGroups: [],
            settlementObligations: [],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: [memberUserID],
            in: container
        )

        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let stale = try XCTUnwrap(categories.first { $0.id == staleLocalID })
        let current = try XCTUnwrap(categories.first { $0.id == currentLocalID })
        XCTAssertNotNil(stale.deletedAt)
        XCTAssertNil(current.deletedAt)
        XCTAssertEqual(transaction.category?.id, currentLocalID)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeImportGoodsCategory(
        id: UUID,
        name: String,
        updatedAt: Date,
        remoteVersion: Int64,
        cloudSyncEnabled: Bool
    ) -> TransactionCategory {
        TransactionCategory(
            id: id,
            name: name,
            kind: .expense,
            iconSymbolName: MistiaSystemCategoryKey.importGoods.iconSymbolName,
            iconColorHex: MistiaSystemCategoryKey.importGoods.iconColorHex,
            hierarchyRole: .child,
            systemKey: MistiaSystemCategoryKey.importGoods.rawValue,
            isSystem: true,
            cloudSyncEnabled: cloudSyncEnabled,
            sortOrder: 0,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: remoteVersion
        )
    }

    private func makeRemoteSystemCategory(
        userID: UUID,
        id: UUID,
        key: MistiaSystemCategoryKey,
        name: String,
        updatedAt: Date
    ) -> RemoteTransactionCategory {
        RemoteTransactionCategory(
            userID: userID,
            id: id,
            name: name,
            kindRawValue: key.kind.rawValue,
            iconSymbolName: key.iconSymbolName,
            iconColorHex: key.iconColorHex,
            isFavorite: false,
            parentCategoryID: nil,
            hierarchyRoleRawValue: TransactionCategoryHierarchyRole.child.rawValue,
            systemKey: key.rawValue,
            isSystem: true,
            sortOrder: 0,
            isArchived: false,
            archivedAt: nil,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            syncVersion: 1,
            lastModifiedByDeviceID: nil
        )
    }

    private func makeCustomCategory(
        id: UUID,
        name: String,
        updatedAt: Date,
        remoteVersion: Int64,
        cloudSyncEnabled: Bool
    ) -> TransactionCategory {
        TransactionCategory(
            id: id,
            name: name,
            kind: .expense,
            iconSymbolName: "tag.fill",
            iconColorHex: "#6E56CF",
            isFavorite: false,
            hierarchyRole: .child,
            systemKey: nil,
            isSystem: false,
            cloudSyncEnabled: cloudSyncEnabled,
            sortOrder: 0,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            remoteVersion: remoteVersion
        )
    }
}
