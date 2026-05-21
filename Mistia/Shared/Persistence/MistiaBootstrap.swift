import Foundation
import SwiftData

struct MistiaCategoryResetResult {
    let restoredSystemCategoryCount: Int
    let archivedCustomCategoryCount: Int
}

enum MistiaBootstrap {
    static func cleanupExpiredArchivedData(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        guard sessionStore.canManageSync else { return }

        let thresholdDate = MistiaCalendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        var didDelete = false
        
        var txDescriptor = FetchDescriptor<LedgerTransaction>()
        txDescriptor.predicate = #Predicate<LedgerTransaction> { $0.isArchived == true }
        for transaction in try modelContext.fetch(txDescriptor) {
            if let archivedAt = transaction.archivedAt, archivedAt < thresholdDate {
                if transaction.deletedAt == nil {
                    transaction.markDeleted(at: .now)
                    sessionStore.recordDelete(
                        entity: .transaction,
                        recordID: transaction.id,
                        modifiedAt: transaction.updatedAt
                    )
                    didDelete = true
                } else if sessionStore.canHardPurge(entity: .transaction, recordID: transaction.id) {
                    try TransactionReceiptImageStore().deleteReceipt(
                        for: transaction.id,
                        context: modelContext,
                        saveContext: false
                    )
                    modelContext.delete(transaction)
                    didDelete = true
                }
            }
        }
        
        var walletDescriptor = FetchDescriptor<LedgerWallet>()
        walletDescriptor.predicate = #Predicate<LedgerWallet> { $0.isArchived == true }
        for wallet in try modelContext.fetch(walletDescriptor) {
            if let archivedAt = wallet.archivedAt, archivedAt < thresholdDate {
                if wallet.deletedAt == nil {
                    wallet.markDeleted(at: .now)
                    sessionStore.recordDelete(
                        entity: .wallet,
                        recordID: wallet.id,
                        modifiedAt: wallet.updatedAt
                    )
                    didDelete = true
                } else if sessionStore.canHardPurge(entity: .wallet, recordID: wallet.id) {
                    modelContext.delete(wallet)
                    didDelete = true
                }
            }
        }
        
        var categoryDescriptor = FetchDescriptor<TransactionCategory>()
        categoryDescriptor.predicate = #Predicate<TransactionCategory> { $0.isArchived == true }
        for category in try modelContext.fetch(categoryDescriptor) {
            if let archivedAt = category.archivedAt, archivedAt < thresholdDate {
                if category.deletedAt == nil {
                    category.markDeleted(at: .now)
                    sessionStore.recordDelete(
                        entity: .category,
                        recordID: category.id,
                        modifiedAt: category.updatedAt
                    )
                    didDelete = true
                } else if sessionStore.canHardPurge(entity: .category, recordID: category.id) {
                    modelContext.delete(category)
                    didDelete = true
                }
            }
        }
        
        if didDelete {
            try modelContext.save()
        }
    }

    static func seedDefaultCategoriesIfNeeded(
        modelContext: ModelContext,
        sessionStore: SessionStore? = nil
    ) throws {
        var repairResult = try MistiaSystemCategorySyncSupport.reconcileDuplicateSystemCategories(
            modelContext: modelContext
        )
        let ownershipScopes = try modelContext.fetch(FetchDescriptor<OwnedRecordScope>())
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        var existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter {
                $0.deletedAt == nil
                    && !MistiaSystemCategorySyncSupport.isFamilyScopedSystemCategory(
                        $0,
                        categoryOwnerMap: categoryOwnerMap
                    )
            }
        var didMutate = false
        var categoriesNeedingSync: [TransactionCategory] = []

        let (parentByKey, didSeedParents) = ensureDefaultParentCategories(
            modelContext: modelContext,
            categories: &existingCategories,
            categoriesNeedingSync: &categoriesNeedingSync
        )
        if didSeedParents {
            didMutate = true
        }
        let didSeedLeaves = ensureDefaultLeafCategories(
            modelContext: modelContext,
            categories: &existingCategories,
            parentByKey: parentByKey,
            categoriesNeedingSync: &categoriesNeedingSync
        )
        if didSeedLeaves {
            didMutate = true
        }

        let normalizedCategoryIDs = normalizeCategoryHierarchy(
            categories: existingCategories,
            parentByKey: parentByKey
        )
        if !normalizedCategoryIDs.isEmpty {
            didMutate = true
            categoriesNeedingSync.append(contentsOf: existingCategories.filter { normalizedCategoryIDs.contains($0.id) })
        }

        try MistiaSystemCategorySyncSupport.refreshCategorySyncEligibility(
            modelContext: modelContext,
            repairResult: &repairResult
        )

        if didMutate {
            try modelContext.save()
        }

        if let sessionStore {
            let syncEligibleIDs = Set(existingCategories.filter { $0.cloudSyncEnabled }.map(\.id))
            let repairedCategories = existingCategories.filter { 
                repairResult.categoryIDsNeedingSync.contains($0.id) && $0.cloudSyncEnabled 
            }
            let validCategoriesNeedingSync = categoriesNeedingSync.filter { syncEligibleIDs.contains($0.id) }
            
            queueCategoryUpserts(repairedCategories + validCategoriesNeedingSync, sessionStore: sessionStore)
            queueRepairRecordUpserts(
                recordIDs: repairResult.transactionIDsNeedingSync,
                entity: .transaction,
                modelContext: modelContext,
                sessionStore: sessionStore
            )
            queueRepairRecordUpserts(
                recordIDs: repairResult.budgetPlanIDsNeedingSync,
                entity: .budgetPlan,
                modelContext: modelContext,
                sessionStore: sessionStore
            )
            queueRepairRecordUpserts(
                recordIDs: repairResult.recurringBillPlanIDsNeedingSync,
                entity: .recurringBillPlan,
                modelContext: modelContext,
                sessionStore: sessionStore
            )
        }
    }

    @discardableResult
    static func resetCategoriesToSystemDefaults(
        modelContext: ModelContext
    ) throws -> MistiaCategoryResetResult {
        var categories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
        let now = Date()
        var didMutate = false
        var restoredSystemCategoryIDs: Set<UUID> = []
        var archivedCustomCategoryCount = 0
        var parentByKey: [MistiaSystemCategoryParentKey: TransactionCategory] = [:]

        for (index, seed) in ManagementPresetData.defaultCategoryParentSeeds.enumerated() {
            let (category, didCreate) = defaultSystemCategory(
                rawSystemKey: seed.systemKey.rawValue,
                canonicalID: MistiaSystemCategoryIdentity.canonicalID(for: seed.systemKey),
                create: {
                    TransactionCategory(
                        id: MistiaSystemCategoryIdentity.canonicalID(for: seed.systemKey),
                        name: seed.name,
                        nameEnglish: seed.nameEnglish,
                        nameJapanese: seed.nameJapanese,
                        kind: seed.kind,
                        iconSymbolName: seed.iconSymbolName,
                        iconColorHex: seed.iconColorHex,
                        hierarchyRole: .parent,
                        systemKey: seed.systemKey.rawValue,
                        isSystem: true,
                        cloudSyncEnabled: true,
                        sortOrder: index
                    )
                },
                categories: &categories,
                modelContext: modelContext
            )

            if didCreate {
                didMutate = true
                restoredSystemCategoryIDs.insert(category.id)
            }
            if resetParentCategory(category, with: seed, sortOrder: index, now: now) {
                didMutate = true
                restoredSystemCategoryIDs.insert(category.id)
            }
            parentByKey[seed.systemKey] = category
        }

        let childSortOrders = Dictionary(
            grouping: ManagementPresetData.defaultCategorySeeds,
            by: { (seed: ManagementCategorySeed) -> MistiaSystemCategoryParentKey? in
                guard let systemKey = seed.systemKey else { return nil }
                return systemKey.parentKey ?? MistiaCategoryHierarchy.uncategorizedParentKey(for: systemKey.kind)
            }
        )

        for seed in ManagementPresetData.defaultCategorySeeds {
            guard let systemKey = seed.systemKey else { continue }
            let parentKey = MistiaCategoryHierarchy.defaultParentKey(for: systemKey)
            let parentCategory = parentByKey[parentKey]
            let siblingSeeds = childSortOrders[parentKey] ?? []
            let sortOrder = siblingSeeds.firstIndex(where: { $0.systemKey == systemKey }) ?? 0

            let (category, didCreate) = defaultSystemCategory(
                rawSystemKey: systemKey.rawValue,
                canonicalID: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
                create: {
                    TransactionCategory(
                        id: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
                        name: seed.name,
                        nameEnglish: seed.nameEnglish,
                        nameJapanese: seed.nameJapanese,
                        kind: seed.kind,
                        iconSymbolName: seed.iconSymbolName,
                        iconColorHex: seed.iconColorHex,
                        parentCategory: parentCategory,
                        hierarchyRole: .child,
                        systemKey: systemKey.rawValue,
                        isSystem: true,
                        cloudSyncEnabled: true,
                        sortOrder: sortOrder,
                        isArchived: seed.startsArchived,
                        archivedAt: seed.startsArchived ? now : nil
                    )
                },
                categories: &categories,
                modelContext: modelContext
            )

            if didCreate {
                didMutate = true
                restoredSystemCategoryIDs.insert(category.id)
            }
            if resetLeafCategory(
                category,
                with: seed,
                parentCategory: parentCategory,
                sortOrder: sortOrder,
                now: now
            ) {
                didMutate = true
                restoredSystemCategoryIDs.insert(category.id)
            }
        }

        let activeParentKeys = Set(ManagementPresetData.defaultCategoryParentSeeds.map(\.systemKey.rawValue))
        let activeLeafKeys = Set(ManagementPresetData.defaultCategorySeeds.compactMap(\.systemKey?.rawValue))
        let activeSystemKeys = activeParentKeys.union(activeLeafKeys)

        for category in categories where category.deletedAt == nil {
            if category.isSystem, let systemKey = category.systemKey, !activeSystemKeys.contains(systemKey) {
                if !category.isArchived {
                    category.isArchived = true
                    category.archivedAt = category.archivedAt ?? now
                    category.updatedAt = now
                    didMutate = true
                    restoredSystemCategoryIDs.insert(category.id)
                }
                continue
            }

            guard !category.isSystem, !category.isArchived else { continue }
            category.isArchived = true
            category.archivedAt = category.archivedAt ?? now
            category.updatedAt = now
            archivedCustomCategoryCount += 1
            didMutate = true
        }

        if didMutate {
            try modelContext.save()
        }

        var repairResult = try MistiaSystemCategorySyncSupport.reconcileDuplicateSystemCategories(
            modelContext: modelContext
        )
        try MistiaSystemCategorySyncSupport.refreshCategorySyncEligibility(
            modelContext: modelContext,
            repairResult: &repairResult
        )

        return MistiaCategoryResetResult(
            restoredSystemCategoryCount: restoredSystemCategoryIDs.count,
            archivedCustomCategoryCount: archivedCustomCategoryCount
        )
    }

    static func ensureSystemCategory(
        _ systemKey: MistiaSystemCategoryKey,
        modelContext: ModelContext
    ) throws -> TransactionCategory {
        try seedDefaultCategoriesIfNeeded(modelContext: modelContext)

        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        if let existing = existingCategories.first(where: { $0.systemKey == systemKey.rawValue }) {
            return existing
        }

        let seed = ManagementPresetData.defaultCategorySeeds.first(where: { $0.systemKey == systemKey })
        let parentCategory = try parentCategory(for: systemKey, modelContext: modelContext)

        let category = TransactionCategory(
            id: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
            name: seed?.name ?? systemKey.legacyVietnameseName,
            nameEnglish: seed?.nameEnglish ?? systemKey.englishTitle,
            nameJapanese: seed?.nameJapanese ?? systemKey.japaneseTitle,
            kind: seed?.kind ?? systemKey.kind,
            iconSymbolName: seed?.iconSymbolName ?? systemKey.iconSymbolName,
            iconColorHex: seed?.iconColorHex ?? systemKey.iconColorHex,
            parentCategory: parentCategory,
            hierarchyRole: .child,
            systemKey: systemKey.rawValue,
            isSystem: true,
            cloudSyncEnabled: true,
            sortOrder: nextChildSortOrder(
                for: seed?.kind ?? systemKey.kind,
                parentID: parentCategory?.id,
                categories: existingCategories
            ),
            isArchived: seed?.startsArchived ?? !systemKey.isActiveDefault
        )
        modelContext.insert(category)
        try modelContext.save()
        return category
    }

    private static func defaultSystemCategory(
        rawSystemKey: String,
        canonicalID: UUID,
        create: () -> TransactionCategory,
        categories: inout [TransactionCategory],
        modelContext: ModelContext
    ) -> (TransactionCategory, Bool) {
        if let existing = categories.first(where: { $0.id == canonicalID })
            ?? categories.first(where: { $0.systemKey == rawSystemKey }) {
            return (existing, false)
        }

        let category = create()
        modelContext.insert(category)
        categories.append(category)
        return (category, true)
    }

    private static func resetParentCategory(
        _ category: TransactionCategory,
        with seed: ManagementCategoryParentSeed,
        sortOrder: Int,
        now: Date
    ) -> Bool {
        var didMutate = false

        didMutate = assignIfNeeded(&category.name, seed.name) || didMutate
        didMutate = assignIfNeeded(&category.nameEnglish, seed.nameEnglish) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, seed.nameJapanese) || didMutate
        didMutate = assignIfNeeded(&category.kindRawValue, seed.kind.rawValue) || didMutate
        didMutate = assignIfNeeded(&category.iconSymbolName, seed.iconSymbolName) || didMutate
        didMutate = assignIfNeeded(&category.iconColorHex, seed.iconColorHex) || didMutate
        didMutate = assignIfNeeded(&category.hierarchyRoleRawValue, TransactionCategoryHierarchyRole.parent.rawValue) || didMutate
        if category.parentCategory != nil {
            category.parentCategory = nil
            didMutate = true
        }
        didMutate = assignIfNeeded(&category.systemKey, seed.systemKey.rawValue) || didMutate
        didMutate = assignIfNeeded(&category.isSystem, true) || didMutate
        didMutate = assignIfNeeded(&category.cloudSyncEnabled, true) || didMutate
        didMutate = assignIfNeeded(&category.sortOrder, sortOrder) || didMutate
        didMutate = assignIfNeeded(&category.favoriteRawValue, Optional(false)) || didMutate
        didMutate = assignIfNeeded(&category.isArchived, false) || didMutate
        if category.archivedAt != nil {
            category.archivedAt = nil
            didMutate = true
        }
        if category.deletedAt != nil {
            category.deletedAt = nil
            didMutate = true
        }

        if didMutate {
            category.updatedAt = now
        }
        return didMutate
    }

    private static func resetLeafCategory(
        _ category: TransactionCategory,
        with seed: ManagementCategorySeed,
        parentCategory: TransactionCategory?,
        sortOrder: Int,
        now: Date
    ) -> Bool {
        var didMutate = false

        didMutate = assignIfNeeded(&category.name, seed.name) || didMutate
        didMutate = assignIfNeeded(&category.nameEnglish, seed.nameEnglish) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, seed.nameJapanese) || didMutate
        didMutate = assignIfNeeded(&category.kindRawValue, seed.kind.rawValue) || didMutate
        didMutate = assignIfNeeded(&category.iconSymbolName, seed.iconSymbolName) || didMutate
        didMutate = assignIfNeeded(&category.iconColorHex, seed.iconColorHex) || didMutate
        didMutate = assignIfNeeded(&category.hierarchyRoleRawValue, TransactionCategoryHierarchyRole.child.rawValue) || didMutate
        if category.parentCategory?.id != parentCategory?.id {
            category.parentCategory = parentCategory
            didMutate = true
        }
        didMutate = assignIfNeeded(&category.systemKey, seed.systemKey?.rawValue) || didMutate
        didMutate = assignIfNeeded(&category.isSystem, true) || didMutate
        didMutate = assignIfNeeded(&category.cloudSyncEnabled, true) || didMutate
        didMutate = assignIfNeeded(&category.sortOrder, sortOrder) || didMutate
        didMutate = assignIfNeeded(&category.favoriteRawValue, Optional(false)) || didMutate
        didMutate = assignIfNeeded(&category.isArchived, seed.startsArchived) || didMutate
        let desiredArchivedAt = seed.startsArchived ? (category.archivedAt ?? now) : nil
        if category.archivedAt != desiredArchivedAt {
            category.archivedAt = desiredArchivedAt
            didMutate = true
        }
        if category.deletedAt != nil {
            category.deletedAt = nil
            didMutate = true
        }

        if didMutate {
            category.updatedAt = now
        }
        return didMutate
    }

    private static func assignIfNeeded<Value: Equatable>(
        _ value: inout Value,
        _ nextValue: Value
    ) -> Bool {
        guard value != nextValue else { return false }
        value = nextValue
        return true
    }

    private static func ensureDefaultParentCategories(
        modelContext: ModelContext,
        categories: inout [TransactionCategory],
        categoriesNeedingSync: inout [TransactionCategory]
    ) -> ([MistiaSystemCategoryParentKey: TransactionCategory], Bool) {
        var parentByKey: [MistiaSystemCategoryParentKey: TransactionCategory] = [:]
        var didMutate = false

        for (index, seed) in ManagementPresetData.defaultCategoryParentSeeds.enumerated() {
            if let existing = categories.first(where: { $0.systemKey == seed.systemKey.rawValue }) {
                let didUpdateExisting = normalizeParentCategory(existing, with: seed, sortOrder: index)
                didMutate = didUpdateExisting || didMutate
                if didUpdateExisting {
                    categoriesNeedingSync.append(existing)
                }
                parentByKey[seed.systemKey] = existing
                continue
            }

            let category = TransactionCategory(
                id: MistiaSystemCategoryIdentity.canonicalID(for: seed.systemKey),
                name: seed.name,
                nameEnglish: seed.nameEnglish,
                nameJapanese: seed.nameJapanese,
                kind: seed.kind,
                iconSymbolName: seed.iconSymbolName,
                iconColorHex: seed.iconColorHex,
                hierarchyRole: .parent,
                systemKey: seed.systemKey.rawValue,
                isSystem: true,
                cloudSyncEnabled: true,
                sortOrder: index
            )
            modelContext.insert(category)
            categories.append(category)
            categoriesNeedingSync.append(category)
            parentByKey[seed.systemKey] = category
            didMutate = true
        }

        return (parentByKey, didMutate)
    }

    private static func ensureDefaultLeafCategories(
        modelContext: ModelContext,
        categories: inout [TransactionCategory],
        parentByKey: [MistiaSystemCategoryParentKey: TransactionCategory],
        categoriesNeedingSync: inout [TransactionCategory]
    ) -> Bool {
        var didMutate = false

        let childSortOrders = Dictionary(
            grouping: ManagementPresetData.defaultCategorySeeds,
            by: { (seed: ManagementCategorySeed) -> MistiaSystemCategoryParentKey? in
                guard let systemKey = seed.systemKey else { return nil }
                return systemKey.parentKey ?? MistiaCategoryHierarchy.uncategorizedParentKey(for: systemKey.kind)
            }
        )

        for seed in ManagementPresetData.defaultCategorySeeds {
            guard let systemKey = seed.systemKey else { continue }
            let parentCategory = parentByKey[MistiaCategoryHierarchy.defaultParentKey(for: systemKey)]
            let parentKey = parentCategory?.mistiaSystemCategoryParentKey
            let siblingSeeds = parentKey.flatMap { childSortOrders[$0] } ?? []
            let sortOrder = siblingSeeds.firstIndex(where: { $0.systemKey == systemKey }) ?? 0

            if let existing = categories.first(where: { $0.systemKey == systemKey.rawValue }) {
                let didUpdateExisting = normalizeLeafCategory(
                    existing,
                    with: seed,
                    parentCategory: parentCategory,
                    sortOrder: sortOrder
                )
                didMutate = didUpdateExisting || didMutate
                if didUpdateExisting {
                    categoriesNeedingSync.append(existing)
                }
                continue
            }

            let category = TransactionCategory(
                id: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
                name: seed.name,
                nameEnglish: seed.nameEnglish,
                nameJapanese: seed.nameJapanese,
                kind: seed.kind,
                iconSymbolName: seed.iconSymbolName,
                iconColorHex: seed.iconColorHex,
                parentCategory: parentCategory,
                hierarchyRole: .child,
                systemKey: systemKey.rawValue,
                isSystem: true,
                cloudSyncEnabled: true,
                sortOrder: sortOrder,
                isArchived: seed.startsArchived
            )
            modelContext.insert(category)
            categories.append(category)
            categoriesNeedingSync.append(category)
            didMutate = true
        }

        didMutate = archiveInactiveSystemCategories(
            categories: categories,
            categoriesNeedingSync: &categoriesNeedingSync
        ) || didMutate

        return didMutate
    }

    private static func normalizeCategoryHierarchy(
        categories: [TransactionCategory],
        parentByKey: [MistiaSystemCategoryParentKey: TransactionCategory]
    ) -> Set<UUID> {
        var mutatedCategoryIDs: Set<UUID> = []
        let now = Date()

        for category in categories {
            guard category.deletedAt == nil else { continue }

            let desiredRole: TransactionCategoryHierarchyRole
            let desiredParent: TransactionCategory?

            if category.mistiaSystemCategoryParentKey != nil {
                desiredRole = .parent
                desiredParent = nil
            } else if let storedRole = category.hierarchyRoleRawValue.flatMap(TransactionCategoryHierarchyRole.init(rawValue:)) {
                desiredRole = storedRole
                if storedRole == .parent {
                    desiredParent = nil
                } else {
                    desiredParent = resolvedParent(for: category, parentByKey: parentByKey)
                }
            } else if let leafKey = category.mistiaSystemCategoryKey {
                desiredRole = .child
                desiredParent = parentByKey[MistiaCategoryHierarchy.defaultParentKey(for: leafKey)]
            } else {
                desiredRole = .child
                desiredParent = resolvedParent(for: category, parentByKey: parentByKey)
            }

            let normalizedParent = desiredRole == .parent ? nil : desiredParent
            let needsRoleUpdate = category.hierarchyRoleRawValue != desiredRole.rawValue
            let needsParentUpdate = category.parentCategory?.id != normalizedParent?.id
            let needsFavoriteReset = desiredRole == .parent && category.isFavorite

            guard needsRoleUpdate || needsParentUpdate || needsFavoriteReset else { continue }

            category.hierarchyRole = desiredRole
            category.parentCategory = normalizedParent
            if desiredRole == .parent {
                category.isFavorite = false
            }
            category.updatedAt = now
            mutatedCategoryIDs.insert(category.id)
        }

        return mutatedCategoryIDs
    }

    private static func resolvedParent(
        for category: TransactionCategory,
        parentByKey: [MistiaSystemCategoryParentKey: TransactionCategory]
    ) -> TransactionCategory? {
        if let currentParent = category.parentCategory,
           currentParent.deletedAt == nil,
           currentParent.parentCategory == nil,
           currentParent.kind == category.kind,
           currentParent.id != category.id {
            return currentParent
        }

        if let leafKey = category.mistiaSystemCategoryKey {
            return parentByKey[MistiaCategoryHierarchy.defaultParentKey(for: leafKey)]
        }

        return parentByKey[MistiaCategoryHierarchy.uncategorizedParentKey(for: category.kind)]
    }

    private static func parentCategory(
        for systemKey: MistiaSystemCategoryKey,
        modelContext: ModelContext
    ) throws -> TransactionCategory? {
        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        let parentKey = MistiaCategoryHierarchy.defaultParentKey(for: systemKey)
        return existingCategories.first(where: { $0.systemKey == parentKey.rawValue })
    }

    private static func normalizeParentCategory(
        _ category: TransactionCategory,
        with seed: ManagementCategoryParentSeed,
        sortOrder: Int
    ) -> Bool {
        var didMutate = false
        let now = Date()

        if Set(seed.systemKey.knownDefaultNames()).contains(category.name.trimmingCharacters(in: .whitespacesAndNewlines)) {
            didMutate = assignIfNeeded(&category.name, seed.name) || didMutate
        }
        didMutate = assignIfNeeded(&category.nameEnglish, seed.nameEnglish) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, seed.nameJapanese) || didMutate
        // Removed forced overrides for kind, iconSymbolName, and iconColorHex
        // to allow users to customize system parent categories freely.
        if category.hierarchyRole != .parent {
            category.hierarchyRole = .parent
            didMutate = true
        }
        if category.parentCategory != nil {
            category.parentCategory = nil
            didMutate = true
        }
        if category.isFavorite {
            category.isFavorite = false
            didMutate = true
        }
        if category.sortOrder != sortOrder {
            category.sortOrder = sortOrder
            didMutate = true
        }
        // Removed forced overrides for isArchived to allow user archival state to persist.
        if !category.isSystem {
            category.isSystem = true
            didMutate = true
        }

        if didMutate {
            category.updatedAt = now
        }
        return didMutate
    }

    private static func normalizeLeafCategory(
        _ category: TransactionCategory,
        with seed: ManagementCategorySeed,
        parentCategory: TransactionCategory?,
        sortOrder: Int
    ) -> Bool {
        var didMutate = false
        let now = Date()

        if let systemKey = seed.systemKey,
           Set(systemKey.knownDefaultNames()).contains(category.name.trimmingCharacters(in: .whitespacesAndNewlines)) {
            didMutate = assignIfNeeded(&category.name, seed.name) || didMutate
        }
        didMutate = assignIfNeeded(&category.nameEnglish, seed.nameEnglish) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, seed.nameJapanese) || didMutate
        // Removed forced overrides for iconSymbolName, and iconColorHex
        // to allow users to customize system child categories freely.
        if category.parentCategory?.id != parentCategory?.id {
            category.parentCategory = parentCategory
            didMutate = true
        }
        if category.hierarchyRole != .child {
            category.hierarchyRole = .child
            didMutate = true
        }
        if category.sortOrder != sortOrder {
            category.sortOrder = sortOrder
            didMutate = true
        }
        // Removed forced overrides for isArchived to allow user archival state to persist.
        if !category.isSystem {
            category.isSystem = true
            didMutate = true
        }

        if didMutate {
            category.updatedAt = now
        }
        return didMutate
    }

    private static func archiveInactiveSystemCategories(
        categories: [TransactionCategory],
        categoriesNeedingSync: inout [TransactionCategory]
    ) -> Bool {
        let activeParentKeys = Set(ManagementPresetData.defaultCategoryParentSeeds.map(\.systemKey.rawValue))
        let activeLeafKeys = Set(ManagementPresetData.defaultCategorySeeds.compactMap(\.systemKey?.rawValue))
        let activeKeys = activeParentKeys.union(activeLeafKeys)
        let now = Date()
        var didMutate = false

        for category in categories {
            guard category.deletedAt == nil, category.isSystem, let systemKey = category.systemKey else { continue }
            guard !activeKeys.contains(systemKey) else { continue }
            guard !category.isArchived else { continue }

            category.isArchived = true
            category.archivedAt = category.archivedAt ?? now
            category.updatedAt = now
            categoriesNeedingSync.append(category)
            didMutate = true
        }

        return didMutate
    }

    private static func nextParentSortOrder(
        for kind: TransactionCategoryKind,
        categories: [TransactionCategory]
    ) -> Int {
        let visible = categories
            .filter { !$0.isArchived && $0.kind == kind && $0.parentCategory == nil }
            .map(\.sortOrder)
            .max() ?? -1

        return visible + 1
    }

    private static func nextChildSortOrder(
        for kind: TransactionCategoryKind,
        parentID: UUID?,
        categories: [TransactionCategory]
    ) -> Int {
        let visible = categories
            .filter {
                !$0.isArchived
                    && $0.kind == kind
                    && $0.parentCategory?.id == parentID
            }
            .map(\.sortOrder)
            .max() ?? -1

        return visible + 1
    }

    private static func queueCategoryUpserts(
        _ categories: [TransactionCategory],
        sessionStore: SessionStore
    ) {
        guard sessionStore.canManageSync else { return }

        let uniqueCategories = Dictionary(
            categories.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        ).values
        for category in uniqueCategories {
            sessionStore.recordUpsert(
                entity: .category,
                recordID: category.id,
                modifiedAt: category.updatedAt
            )
        }
    }

    private static func queueRepairRecordUpserts(
        recordIDs: Set<UUID>,
        entity: MistiaSyncEntity,
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) {
        guard !recordIDs.isEmpty else { return }

        switch entity {
        case .transaction:
            let records = (try? modelContext.fetch(FetchDescriptor<LedgerTransaction>())) ?? []
            for record in records where recordIDs.contains(record.id) {
                sessionStore.recordUpsert(entity: entity, recordID: record.id, modifiedAt: record.updatedAt)
            }
        case .budgetPlan:
            let records = (try? modelContext.fetch(FetchDescriptor<BudgetPlan>())) ?? []
            for record in records where recordIDs.contains(record.id) {
                sessionStore.recordUpsert(entity: entity, recordID: record.id, modifiedAt: record.updatedAt)
            }
        case .recurringBillPlan:
            let records = (try? modelContext.fetch(FetchDescriptor<RecurringBillPlan>())) ?? []
            for record in records where recordIDs.contains(record.id) {
                sessionStore.recordUpsert(entity: entity, recordID: record.id, modifiedAt: record.updatedAt)
            }
        case .wallet, .creditCardProfile, .category, .savingsGoal, .installmentPlan, .dueOccurrenceRecord:
            break
        }
    }

    private static func queuePlanningUpserts<Record: PersistentModel>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        sessionStore: SessionStore
    ) where Record: AnyObject {
        guard sessionStore.canManageSync else { return }

        let uniqueRecords = Dictionary(records.compactMap { record in
            switch record {
            case let goal as SavingsGoal:
                (goal.id, goal.updatedAt)
            case let recurringBill as RecurringBillPlan:
                (recurringBill.id, recurringBill.updatedAt)
            case let installment as InstallmentPlan:
                (installment.id, installment.updatedAt)
            default:
                nil
            }
        }, uniquingKeysWith: max)

        for (recordID, updatedAt) in uniqueRecords {
            sessionStore.recordUpsert(
                entity: entity,
                recordID: recordID,
                modifiedAt: updatedAt
            )
        }
    }

}
