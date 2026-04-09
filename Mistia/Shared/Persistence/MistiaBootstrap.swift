import Foundation
import SwiftData

enum MistiaBootstrap {
    static func cleanupExpiredArchivedData(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        guard sessionStore.canManageSync else { return }

        let thresholdDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
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
        var existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        let existingWallets = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
            .filter { $0.deletedAt == nil }
        var didMutate = false
        var categoriesNeedingSync: [TransactionCategory] = []

        if normalizeLegacyDefaultIconColors(
            categories: existingCategories,
            wallets: existingWallets
        ) {
            didMutate = true
        }

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

        if didMutate {
            try modelContext.save()
            if let sessionStore {
                queueCategoryUpserts(categoriesNeedingSync, sessionStore: sessionStore)
            }
        }
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

        guard let seed = ManagementPresetData.defaultCategorySeeds.first(where: { $0.systemKey == systemKey }) else {
            fatalError("Missing seed for system category \(systemKey.rawValue)")
        }
        let parentCategory = try parentCategory(for: systemKey, modelContext: modelContext)

        let category = TransactionCategory(
            name: seed.name,
            kind: seed.kind,
            iconSymbolName: seed.iconSymbolName,
            iconColorHex: seed.iconColorHex,
            parentCategory: parentCategory,
            hierarchyRole: .child,
            systemKey: systemKey.rawValue,
            isSystem: true,
            sortOrder: nextChildSortOrder(
                for: seed.kind,
                parentID: parentCategory?.id,
                categories: existingCategories
            ),
            isArchived: seed.startsArchived
        )
        modelContext.insert(category)
        try modelContext.save()
        return category
    }

    private static func ensureDefaultParentCategories(
        modelContext: ModelContext,
        categories: inout [TransactionCategory],
        categoriesNeedingSync: inout [TransactionCategory]
    ) -> ([MistiaSystemCategoryParentKey: TransactionCategory], Bool) {
        var parentByKey: [MistiaSystemCategoryParentKey: TransactionCategory] = [:]
        var didMutate = false

        for seed in ManagementPresetData.defaultCategoryParentSeeds {
            if let existing = categories.first(where: { $0.systemKey == seed.systemKey.rawValue }) {
                if existing.hierarchyRole != .parent || existing.parentCategory != nil {
                    existing.hierarchyRole = .parent
                    existing.parentCategory = nil
                    existing.updatedAt = .now
                    categoriesNeedingSync.append(existing)
                    didMutate = true
                }
                parentByKey[seed.systemKey] = existing
                continue
            }

            let category = TransactionCategory(
                name: seed.name,
                kind: seed.kind,
                iconSymbolName: seed.iconSymbolName,
                iconColorHex: seed.iconColorHex,
                hierarchyRole: .parent,
                systemKey: seed.systemKey.rawValue,
                isSystem: true,
                sortOrder: nextParentSortOrder(for: seed.kind, categories: categories)
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

        for seed in ManagementPresetData.defaultCategorySeeds {
            guard let systemKey = seed.systemKey else { continue }
            guard categories.first(where: { $0.systemKey == systemKey.rawValue }) == nil else { continue }
            let parentCategory = parentByKey[MistiaCategoryHierarchy.defaultParentKey(for: systemKey)]

            let category = TransactionCategory(
                name: seed.name,
                kind: seed.kind,
                iconSymbolName: seed.iconSymbolName,
                iconColorHex: seed.iconColorHex,
                parentCategory: parentCategory,
                hierarchyRole: .child,
                systemKey: systemKey.rawValue,
                isSystem: true,
                sortOrder: nextChildSortOrder(
                    for: seed.kind,
                    parentID: parentCategory?.id,
                    categories: categories
                ),
                isArchived: seed.startsArchived
            )
            modelContext.insert(category)
            categories.append(category)
            categoriesNeedingSync.append(category)
            didMutate = true
        }

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

            guard needsRoleUpdate || needsParentUpdate else { continue }

            category.hierarchyRole = desiredRole
            category.parentCategory = normalizedParent
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

        let uniqueCategories = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }).values
        for category in uniqueCategories {
            sessionStore.recordUpsert(
                entity: .category,
                recordID: category.id,
                modifiedAt: category.updatedAt
            )
        }
    }

    private static func normalizeLegacyDefaultIconColors(
        categories: [TransactionCategory],
        wallets: [LedgerWallet]
    ) -> Bool {
        var didMutate = false

        for wallet in wallets {
            guard let migratedColorHex = wallet.kind.migratedLegacyDefaultColorHex(
                for: wallet.iconColorHex,
                symbolName: wallet.iconSymbolName
            ) else {
                continue
            }

            wallet.iconColorHex = migratedColorHex
            wallet.updatedAt = .now
            didMutate = true
        }

        for category in categories where !category.isSystem && category.systemKey == nil {
            guard let migratedColorHex = category.kind.migratedLegacyDefaultColorHex(
                for: category.iconColorHex,
                symbolName: category.iconSymbolName
            ) else {
                continue
            }

            category.iconColorHex = migratedColorHex
            category.updatedAt = .now
            didMutate = true
        }

        return didMutate
    }
}
