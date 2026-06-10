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

        let thresholdDate = MistiaCalendar.current.date(
            byAdding: .day,
            value: -MistiaArchiveRetention.retentionDays,
            to: Date()
        ) ?? Date()
        
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
        let allCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
        let localizedNameCategoryIDs = normalizeLocalizedSystemCategoryNames(allCategories)
        var existingCategories = allCategories.filter {
            $0.deletedAt == nil
                && !MistiaSystemCategorySyncSupport.isFamilyScopedSystemCategory(
                    $0,
                    categoryOwnerMap: categoryOwnerMap
                )
        }
        var didMutate = false
        var categoriesNeedingSync: [TransactionCategory] = []
        if !localizedNameCategoryIDs.isEmpty {
            didMutate = true
            categoriesNeedingSync.append(
                contentsOf: existingCategories.filter { localizedNameCategoryIDs.contains($0.id) }
            )
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

    static func seedDefaultCategoriesForLaunchIfNeeded(
        modelContext: ModelContext,
        sessionStore: SessionStore? = nil
    ) throws {
        guard try needsDefaultCategoryLaunchRepair(modelContext: modelContext) else { return }
        try seedDefaultCategoriesIfNeeded(
            modelContext: modelContext,
            sessionStore: sessionStore
        )
    }

    private static func needsDefaultCategoryLaunchRepair(
        modelContext: ModelContext
    ) throws -> Bool {
        let expectedSystemKeys = expectedDefaultSystemKeys
        guard !expectedSystemKeys.isEmpty else { return false }

        let categories = try modelContext.fetch(
            FetchDescriptor<TransactionCategory>(
                predicate: #Predicate { category in
                    category.deletedAt == nil && category.isSystem == true
                }
            )
        )

        var categoryBySystemKey: [String: TransactionCategory] = [:]
        for category in categories {
            guard let systemKey = category.systemKey,
                  expectedSystemKeys.contains(systemKey),
                  categoryBySystemKey[systemKey] == nil else {
                continue
            }
            categoryBySystemKey[systemKey] = category
        }

        let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
        var expectedSortOrders: [String: Int] = [:]
        for (index, parent) in activeParents.enumerated() {
            expectedSortOrders[parent.id] = index
            let activeChildren = (parent.children ?? []).filter { $0.active }
            for (childIndex, child) in activeChildren.enumerated() {
                expectedSortOrders[child.id] = childIndex
            }
        }

        for systemKey in expectedSystemKeys {
            guard let category = categoryBySystemKey[systemKey] else { return true }
            if isBlank(category.name)
                || isBlank(category.nameEnglish)
                || isBlank(category.nameJapanese) {
                return true
            }

            guard let parsed = MistiaSystemCategoryRegistry.shared.category(for: systemKey) else {
                continue
            }

            if let expectedSort = expectedSortOrders[systemKey], category.sortOrder != expectedSort {
                return true
            }

            let expectedEn = parsed.translations["en"] ?? parsed.translations["vi"] ?? parsed.id
            let expectedJa = parsed.translations["ja"] ?? parsed.translations["vi"] ?? parsed.id
            if category.nameEnglish != expectedEn || category.nameJapanese != expectedJa {
                return true
            }

            let expectedVi = parsed.translations["vi"] ?? parsed.id
            if category.name != expectedVi && Set(parsed.knownDefaultNames()).contains(category.name.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return true
            }
        }

        return false
    }

    private static var expectedDefaultSystemKeys: Set<String> {
        let parentKeys = MistiaSystemCategoryRegistry.shared.allParents.map { $0.id }
        let leafKeys = MistiaSystemCategoryRegistry.shared.allParents.flatMap { $0.children ?? [] }.map { $0.id }
        return Set(parentKeys).union(leafKeys)
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
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
        var parentByKey: [String: TransactionCategory] = [:]

        let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
        for (index, parent) in activeParents.enumerated() {
            let (category, didCreate) = defaultSystemCategory(
                rawSystemKey: parent.id,
                canonicalID: MistiaSystemCategoryIdentity.canonicalID(for: parent.id),
                create: {
                    TransactionCategory(
                        id: MistiaSystemCategoryIdentity.canonicalID(for: parent.id),
                        name: parent.translations["vi"] ?? parent.id,
                        nameEnglish: parent.translations["en"] ?? parent.translations["vi"] ?? parent.id,
                        nameJapanese: parent.translations["ja"] ?? parent.translations["vi"] ?? parent.id,
                        kind: parent.kind(in: MistiaSystemCategoryRegistry.shared),
                        iconSymbolName: parent.icon,
                        iconColorHex: parent.color,
                        hierarchyRole: .parent,
                        systemKey: parent.id,
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
            if resetParentCategory(category, with: parent, sortOrder: index, now: now) {
                didMutate = true
                restoredSystemCategoryIDs.insert(category.id)
            }
            parentByKey[parent.id] = category
        }

        for parent in activeParents {
            let parentCategory = parentByKey[parent.id]
            let activeChildren = (parent.children ?? []).filter { $0.active }
            for (sortOrder, child) in activeChildren.enumerated() {
                let (category, didCreate) = defaultSystemCategory(
                    rawSystemKey: child.id,
                    canonicalID: MistiaSystemCategoryIdentity.canonicalID(for: child.id),
                    create: {
                        TransactionCategory(
                            id: MistiaSystemCategoryIdentity.canonicalID(for: child.id),
                            name: child.translations["vi"] ?? child.id,
                            nameEnglish: child.translations["en"] ?? child.translations["vi"] ?? child.id,
                            nameJapanese: child.translations["ja"] ?? child.translations["vi"] ?? child.id,
                            kind: parent.kind(in: MistiaSystemCategoryRegistry.shared),
                            iconSymbolName: child.icon,
                            iconColorHex: child.color,
                            parentCategory: parentCategory,
                            hierarchyRole: .child,
                            systemKey: child.id,
                            isSystem: true,
                            cloudSyncEnabled: true,
                            sortOrder: sortOrder,
                            isArchived: false,
                            archivedAt: nil
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
                    with: child,
                    parentCategory: parentCategory,
                    sortOrder: sortOrder,
                    now: now
                ) {
                    didMutate = true
                    restoredSystemCategoryIDs.insert(category.id)
                }
            }
        }

        let activeParentKeys = Set(activeParents.map { $0.id })
        let activeLeafKeys = Set(activeParents.flatMap { $0.children ?? [] }.filter { $0.active }.map { $0.id })
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
        try ensureSystemCategory(systemKey.rawValue, modelContext: modelContext)
    }

    static func ensureSystemCategory(
        _ rawSystemKey: String,
        modelContext: ModelContext
    ) throws -> TransactionCategory {
        try seedDefaultCategoriesIfNeeded(modelContext: modelContext)

        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        if let existing = existingCategories.first(where: { $0.systemKey == rawSystemKey }) {
            return existing
        }

        guard let parsed = MistiaSystemCategoryRegistry.shared.category(for: rawSystemKey) else {
            throw PlanningPersistenceError.missingCategory
        }

        let parentCategory = try parentCategory(for: rawSystemKey, modelContext: modelContext)

        let category = TransactionCategory(
            id: MistiaSystemCategoryIdentity.canonicalID(for: rawSystemKey),
            name: parsed.translations["vi"] ?? rawSystemKey,
            nameEnglish: parsed.translations["en"] ?? parsed.translations["vi"] ?? rawSystemKey,
            nameJapanese: parsed.translations["ja"] ?? parsed.translations["vi"] ?? rawSystemKey,
            kind: parsed.kind(in: MistiaSystemCategoryRegistry.shared),
            iconSymbolName: parsed.icon,
            iconColorHex: parsed.color,
            parentCategory: parentCategory,
            hierarchyRole: .child,
            systemKey: rawSystemKey,
            isSystem: true,
            cloudSyncEnabled: true,
            sortOrder: nextChildSortOrder(
                for: parsed.kind(in: MistiaSystemCategoryRegistry.shared),
                parentID: parentCategory?.id,
                categories: existingCategories
            ),
            isArchived: !parsed.active
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
        with parent: ParsedSystemCategory,
        sortOrder: Int,
        now: Date
    ) -> Bool {
        var didMutate = false

        let name = parent.translations["vi"] ?? parent.id
        let en = parent.translations["en"] ?? parent.translations["vi"] ?? parent.id
        let ja = parent.translations["ja"] ?? parent.translations["vi"] ?? parent.id
        let kind = parent.kind(in: MistiaSystemCategoryRegistry.shared)

        didMutate = assignIfNeeded(&category.name, name) || didMutate
        didMutate = assignIfNeeded(&category.nameEnglish, en) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, ja) || didMutate
        didMutate = assignIfNeeded(&category.kindRawValue, kind.rawValue) || didMutate
        didMutate = assignIfNeeded(&category.iconSymbolName, parent.icon) || didMutate
        didMutate = assignIfNeeded(&category.iconColorHex, parent.color) || didMutate
        didMutate = assignIfNeeded(&category.hierarchyRoleRawValue, TransactionCategoryHierarchyRole.parent.rawValue) || didMutate
        if category.parentCategory != nil {
            category.parentCategory = nil
            didMutate = true
        }
        didMutate = assignIfNeeded(&category.systemKey, parent.id) || didMutate
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
        with child: ParsedSystemCategory,
        parentCategory: TransactionCategory?,
        sortOrder: Int,
        now: Date
    ) -> Bool {
        var didMutate = false

        let name = child.translations["vi"] ?? child.id
        let en = child.translations["en"] ?? child.translations["vi"] ?? child.id
        let ja = child.translations["ja"] ?? child.translations["vi"] ?? child.id
        let kind = parentCategory?.kind ?? .expense

        didMutate = assignIfNeeded(&category.name, name) || didMutate
        didMutate = assignIfNeeded(&category.nameEnglish, en) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, ja) || didMutate
        didMutate = assignIfNeeded(&category.kindRawValue, kind.rawValue) || didMutate
        didMutate = assignIfNeeded(&category.iconSymbolName, child.icon) || didMutate
        didMutate = assignIfNeeded(&category.iconColorHex, child.color) || didMutate
        didMutate = assignIfNeeded(&category.hierarchyRoleRawValue, TransactionCategoryHierarchyRole.child.rawValue) || didMutate
        if category.parentCategory?.id != parentCategory?.id {
            category.parentCategory = parentCategory
            didMutate = true
        }
        didMutate = assignIfNeeded(&category.systemKey, child.id) || didMutate
        didMutate = assignIfNeeded(&category.isSystem, true) || didMutate
        didMutate = assignIfNeeded(&category.cloudSyncEnabled, true) || didMutate
        didMutate = assignIfNeeded(&category.sortOrder, sortOrder) || didMutate
        didMutate = assignIfNeeded(&category.favoriteRawValue, Optional(false)) || didMutate
        didMutate = assignIfNeeded(&category.isArchived, !child.active) || didMutate
        let desiredArchivedAt = !child.active ? (category.archivedAt ?? now) : nil
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

    private static func normalizeLocalizedSystemCategoryNames(
        _ categories: [TransactionCategory]
    ) -> Set<UUID> {
        var mutatedCategoryIDs: Set<UUID> = []
        let now = Date()

        for category in categories where category.deletedAt == nil && category.isSystem {
            let trimmedName = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var didMutate = false

            if let systemKey = category.systemKey,
               let parentKey = MistiaSystemCategoryParentKey(rawValue: systemKey),
               Set(parentKey.knownDefaultNames()).contains(trimmedName) {
                didMutate = assignIfNeeded(&category.name, parentKey.legacyVietnameseName) || didMutate
                didMutate = assignIfNeeded(&category.nameEnglish, parentKey.englishTitle) || didMutate
                didMutate = assignIfNeeded(&category.nameJapanese, parentKey.japaneseTitle) || didMutate
            } else if let systemKey = category.systemKey,
                      let categoryKey = MistiaSystemCategoryKey(rawValue: systemKey),
                      Set(categoryKey.knownDefaultNames()).contains(trimmedName) {
                didMutate = assignIfNeeded(&category.name, categoryKey.legacyVietnameseName) || didMutate
                didMutate = assignIfNeeded(&category.nameEnglish, categoryKey.englishTitle) || didMutate
                didMutate = assignIfNeeded(&category.nameJapanese, categoryKey.japaneseTitle) || didMutate
            }

            if didMutate {
                category.updatedAt = now
                mutatedCategoryIDs.insert(category.id)
            }
        }

        return mutatedCategoryIDs
    }

    private static func ensureDefaultParentCategories(
        modelContext: ModelContext,
        categories: inout [TransactionCategory],
        categoriesNeedingSync: inout [TransactionCategory]
    ) -> ([String: TransactionCategory], Bool) {
        var parentByKey: [String: TransactionCategory] = [:]
        var didMutate = false

        let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
        for (index, parent) in activeParents.enumerated() {
            if let existing = categories.first(where: { $0.systemKey == parent.id }) {
                let didUpdateExisting = normalizeParentCategory(existing, with: parent, sortOrder: index)
                didMutate = didUpdateExisting || didMutate
                if didUpdateExisting {
                    categoriesNeedingSync.append(existing)
                }
                parentByKey[parent.id] = existing
                continue
            }

            let category = TransactionCategory(
                id: MistiaSystemCategoryIdentity.canonicalID(for: parent.id),
                name: parent.translations["vi"] ?? parent.id,
                nameEnglish: parent.translations["en"] ?? parent.translations["vi"] ?? parent.id,
                nameJapanese: parent.translations["ja"] ?? parent.translations["vi"] ?? parent.id,
                kind: parent.kind(in: MistiaSystemCategoryRegistry.shared),
                iconSymbolName: parent.icon,
                iconColorHex: parent.color,
                hierarchyRole: .parent,
                systemKey: parent.id,
                isSystem: true,
                cloudSyncEnabled: true,
                sortOrder: index
            )
            modelContext.insert(category)
            categories.append(category)
            categoriesNeedingSync.append(category)
            parentByKey[parent.id] = category
            didMutate = true
        }

        return (parentByKey, didMutate)
    }

    private static func ensureDefaultLeafCategories(
        modelContext: ModelContext,
        categories: inout [TransactionCategory],
        parentByKey: [String: TransactionCategory],
        categoriesNeedingSync: inout [TransactionCategory]
    ) -> Bool {
        var didMutate = false

        let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
        for parent in activeParents {
            let parentCategory = parentByKey[parent.id]
            let activeChildren = (parent.children ?? []).filter { $0.active }
            for (sortOrder, child) in activeChildren.enumerated() {
                if let existing = categories.first(where: { $0.systemKey == child.id }) {
                    let didUpdateExisting = normalizeLeafCategory(
                        existing,
                        with: child,
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
                    id: MistiaSystemCategoryIdentity.canonicalID(for: child.id),
                    name: child.translations["vi"] ?? child.id,
                    nameEnglish: child.translations["en"] ?? child.translations["vi"] ?? child.id,
                    nameJapanese: child.translations["ja"] ?? child.translations["vi"] ?? child.id,
                    kind: parent.kind(in: MistiaSystemCategoryRegistry.shared),
                    iconSymbolName: child.icon,
                    iconColorHex: child.color,
                    parentCategory: parentCategory,
                    hierarchyRole: .child,
                    systemKey: child.id,
                    isSystem: true,
                    cloudSyncEnabled: true,
                    sortOrder: sortOrder,
                    isArchived: false
                )
                modelContext.insert(category)
                categories.append(category)
                categoriesNeedingSync.append(category)
                didMutate = true
            }
        }

        didMutate = archiveInactiveSystemCategories(
            categories: categories,
            categoriesNeedingSync: &categoriesNeedingSync
        ) || didMutate

        return didMutate
    }

    private static func normalizeCategoryHierarchy(
        categories: [TransactionCategory],
        parentByKey: [String: TransactionCategory]
    ) -> Set<UUID> {
        var mutatedCategoryIDs: Set<UUID> = []
        let now = Date()

        for category in categories {
            guard category.deletedAt == nil else { continue }

            let desiredRole: TransactionCategoryHierarchyRole
            let desiredParent: TransactionCategory?

            if let systemKey = category.systemKey,
               MistiaSystemCategoryRegistry.shared.parentId(for: systemKey) == nil {
                desiredRole = .parent
                desiredParent = nil
            } else if let storedRole = category.hierarchyRoleRawValue.flatMap(TransactionCategoryHierarchyRole.init(rawValue:)) {
                desiredRole = storedRole
                if storedRole == .parent {
                    desiredParent = nil
                } else {
                    desiredParent = resolvedParent(for: category, parentByKey: parentByKey)
                }
            } else if let systemKey = category.systemKey {
                desiredRole = .child
                if let parentId = MistiaSystemCategoryRegistry.shared.parentId(for: systemKey) {
                    desiredParent = parentByKey[parentId]
                } else {
                    desiredParent = resolvedParent(for: category, parentByKey: parentByKey)
                }
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
        parentByKey: [String: TransactionCategory]
    ) -> TransactionCategory? {
        if let currentParent = category.parentCategory,
           currentParent.deletedAt == nil,
           currentParent.parentCategory == nil,
           currentParent.kind == category.kind,
           currentParent.id != category.id {
            return currentParent
        }

        if let systemKey = category.systemKey,
           let parentId = MistiaSystemCategoryRegistry.shared.parentId(for: systemKey) {
            return parentByKey[parentId]
        }

        let uncategorizedKey = category.kind == .expense ? "parent_expense_uncategorized" : "parent_income_uncategorized"
        return parentByKey[uncategorizedKey]
    }

    private static func parentCategory(
        for rawSystemKey: String,
        modelContext: ModelContext
    ) throws -> TransactionCategory? {
        let existingCategories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            .filter { $0.deletedAt == nil }
        guard let parentId = MistiaSystemCategoryRegistry.shared.parentId(for: rawSystemKey) else {
            return nil
        }
        return existingCategories.first(where: { $0.systemKey == parentId })
    }

    private static func normalizeParentCategory(
        _ category: TransactionCategory,
        with parent: ParsedSystemCategory,
        sortOrder: Int
    ) -> Bool {
        var didMutate = false
        let now = Date()

        if Set(parent.knownDefaultNames()).contains(category.name.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let name = parent.translations["vi"] ?? parent.id
            didMutate = assignIfNeeded(&category.name, name) || didMutate
        }
        let en = parent.translations["en"] ?? parent.translations["vi"] ?? parent.id
        let ja = parent.translations["ja"] ?? parent.translations["vi"] ?? parent.id
        didMutate = assignIfNeeded(&category.nameEnglish, en) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, ja) || didMutate
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
        with child: ParsedSystemCategory,
        parentCategory: TransactionCategory?,
        sortOrder: Int
    ) -> Bool {
        var didMutate = false
        let now = Date()

        if Set(child.knownDefaultNames()).contains(category.name.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let name = child.translations["vi"] ?? child.id
            didMutate = assignIfNeeded(&category.name, name) || didMutate
        }
        let en = child.translations["en"] ?? child.translations["vi"] ?? child.id
        let ja = child.translations["ja"] ?? child.translations["vi"] ?? child.id
        didMutate = assignIfNeeded(&category.nameEnglish, en) || didMutate
        didMutate = assignIfNeeded(&category.nameJapanese, ja) || didMutate
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
        let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
        let activeParentKeys = Set(activeParents.map { $0.id })
        let activeLeafKeys = Set(activeParents.flatMap { $0.children ?? [] }.filter { $0.active }.map { $0.id })
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
