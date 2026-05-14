import Foundation
import SwiftData

struct MistiaSystemCategoryRepairResult {
    var categoryIDsNeedingSync: Set<UUID> = []
    var transactionIDsNeedingSync: Set<UUID> = []
    var budgetPlanIDsNeedingSync: Set<UUID> = []
    var recurringBillPlanIDsNeedingSync: Set<UUID> = []

    var didMutateAnything: Bool {
        !categoryIDsNeedingSync.isEmpty
            || !transactionIDsNeedingSync.isEmpty
            || !budgetPlanIDsNeedingSync.isEmpty
            || !recurringBillPlanIDsNeedingSync.isEmpty
    }
}

private extension RemoteTransactionCategory {
    nonisolated func replacingCategoryReferences(_ mappings: [UUID: UUID]) -> RemoteTransactionCategory {
        guard !mappings.isEmpty else { return self }
        var row = self
        if let parentCategoryID,
           let replacementID = mappings[parentCategoryID] {
            row.parentCategoryID = replacementID
        }
        return row
    }
}

private extension RemoteLedgerTransaction {
    nonisolated func replacingCategoryReferences(_ mappings: [UUID: UUID]) -> RemoteLedgerTransaction {
        guard !mappings.isEmpty else { return self }
        var row = self
        if let categoryID,
           let replacementID = mappings[categoryID] {
            row.categoryID = replacementID
        }
        return row
    }
}

private extension RemoteBudgetPlan {
    nonisolated func replacingCategoryReferences(_ mappings: [UUID: UUID]) -> RemoteBudgetPlan {
        guard !mappings.isEmpty else { return self }
        var row = self
        if let categoryID,
           let replacementID = mappings[categoryID] {
            row.categoryID = replacementID
        }
        return row
    }
}

private extension RemoteRecurringBillPlan {
    nonisolated func replacingCategoryReferences(_ mappings: [UUID: UUID]) -> RemoteRecurringBillPlan {
        guard !mappings.isEmpty else { return self }
        var row = self
        if let categoryID,
           let replacementID = mappings[categoryID] {
            row.categoryID = replacementID
        }
        return row
    }
}

private nonisolated struct MistiaRemoteSystemCategoryKey: Hashable {
    let userID: UUID
    let systemKey: String
}

@MainActor
enum MistiaSystemCategorySyncSupport {
    nonisolated static func deduplicatingRemoteSystemCategories(
        _ snapshot: MistiaRemoteSnapshot,
        preferCloudScopedIDs: Bool = false
    ) -> MistiaRemoteSnapshot {
        let systemCategories = snapshot.categories.filter {
            $0.isSystem && $0.systemKey != nil
        }
        guard !systemCategories.isEmpty else { return snapshot }

        let categoryByID = Dictionary(
            snapshot.categories.map { ($0.id, $0) },
            uniquingKeysWith: latestRemoteCategory
        )
        let groups = Dictionary(grouping: systemCategories) { row in
            MistiaRemoteSystemCategoryKey(userID: row.userID, systemKey: row.systemKey ?? "")
        }
        var replacementByID: [UUID: UUID] = [:]
        var preferredByKey: [MistiaRemoteSystemCategoryKey: RemoteTransactionCategory] = [:]

        for (key, group) in groups where !key.systemKey.isEmpty {
            let activeRows = group.filter { $0.deletedAt == nil }
            let candidateRows = activeRows.isEmpty ? group : activeRows
            guard let source = candidateRows.max(by: { remoteCategoryPriority($0) < remoteCategoryPriority($1) }) else {
                continue
            }
            let hasActiveRow = !activeRows.isEmpty

            let cloudScopedID = MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: key.systemKey),
                ownerUserID: key.userID
            )
            let hasCloudScopedRow = group.contains { $0.id == cloudScopedID }
            let preferredID = (preferCloudScopedIDs || hasCloudScopedRow) ? cloudScopedID : source.id
            let duplicateCount = group.filter { $0.id != preferredID }.count

            guard source.id != preferredID || duplicateCount > 0 else {
                continue
            }

            var preferred = source
            preferred.id = preferredID
            if hasActiveRow {
                preferred.deletedAt = nil
            }
            if let parentID = source.parentCategoryID,
               let parentRow = categoryByID[parentID],
               parentRow.userID == key.userID,
               parentRow.isSystem,
               let parentSystemKey = parentRow.systemKey {
                let parentCloudScopedID = MistiaSystemCategoryIdentity.cloudScopedID(
                    canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: parentSystemKey),
                    ownerUserID: key.userID
                )
                let parentHasCloudScopedRow = groups[
                    MistiaRemoteSystemCategoryKey(userID: key.userID, systemKey: parentSystemKey)
                ]?.contains { $0.id == parentCloudScopedID } == true
                preferred.parentCategoryID = (preferCloudScopedIDs || parentHasCloudScopedRow)
                    ? parentCloudScopedID
                    : parentID
            }
            preferredByKey[key] = preferred

            for row in group where row.id != preferredID {
                replacementByID[row.id] = preferredID
            }
        }

        guard !replacementByID.isEmpty || !preferredByKey.isEmpty else {
            return snapshot
        }

        var emittedPreferredKeys: Set<MistiaRemoteSystemCategoryKey> = []
        var categories: [RemoteTransactionCategory] = []

        for row in snapshot.categories {
            guard row.isSystem, let systemKey = row.systemKey else {
                categories.append(row.replacingCategoryReferences(replacementByID))
                continue
            }

            let key = MistiaRemoteSystemCategoryKey(userID: row.userID, systemKey: systemKey)
            guard let preferred = preferredByKey[key] else {
                categories.append(row.replacingCategoryReferences(replacementByID))
                continue
            }

            guard !emittedPreferredKeys.contains(key) else {
                continue
            }

            emittedPreferredKeys.insert(key)
            categories.append(preferred.replacingCategoryReferences(replacementByID))
        }

        return MistiaRemoteSnapshot(
            wallets: snapshot.wallets,
            creditCardProfiles: snapshot.creditCardProfiles,
            categories: categories,
            transactions: snapshot.transactions.map { $0.replacingCategoryReferences(replacementByID) },
            budgetPlans: snapshot.budgetPlans.map { $0.replacingCategoryReferences(replacementByID) },
            savingsGoals: snapshot.savingsGoals,
            recurringBillPlans: snapshot.recurringBillPlans.map { $0.replacingCategoryReferences(replacementByID) },
            installmentPlans: snapshot.installmentPlans,
            dueOccurrences: snapshot.dueOccurrences
        )
    }

    static func reconcileDuplicateSystemCategories(
        modelContext: ModelContext
    ) throws -> MistiaSystemCategoryRepairResult {
        var result = MistiaSystemCategoryRepairResult()
        let now = Date()

        try MistiaRecordOwnershipStore.reconcileDuplicateScopes(in: modelContext)
        let categories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
        let transactions = try modelContext.fetch(FetchDescriptor<LedgerTransaction>())
        let budgets = try modelContext.fetch(FetchDescriptor<BudgetPlan>())
        let recurringBills = try modelContext.fetch(FetchDescriptor<RecurringBillPlan>())
        let ownershipScopes = try modelContext.fetch(FetchDescriptor<OwnedRecordScope>())
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let conflicts = try modelContext.fetch(FetchDescriptor<SyncConflict>())
        let outbox = MistiaSyncOutbox()
        var didMutate = false
        var removedCategoryObjects: Set<ObjectIdentifier> = []

        let groupedByID = Dictionary(grouping: categories) { $0.id }
        for (_, group) in groupedByID where group.count > 1 {
            let canonicalCategory = preferredLocalCategory(in: group)
            for duplicate in group where duplicate !== canonicalCategory {
                didMutate = absorbCategorySyncState(from: duplicate, into: canonicalCategory) || didMutate
                repointCategoryReferences(
                    from: duplicate,
                    to: canonicalCategory,
                    transactions: transactions,
                    budgets: budgets,
                    recurringBills: recurringBills,
                    categories: categories,
                    now: now,
                    result: &result
                )

                if duplicate.remoteVersion > 0 || duplicate.cloudSyncEnabled {
                    result.categoryIDsNeedingSync.insert(canonicalCategory.id)
                }
                removedCategoryObjects.insert(ObjectIdentifier(duplicate))
                modelContext.delete(duplicate)
                didMutate = true
            }
        }

        let activeSystemCategories = categories.filter { category in
            !removedCategoryObjects.contains(ObjectIdentifier(category))
                && category.deletedAt == nil
                && category.isSystem
                && category.systemKey != nil
                && !isFamilyScopedSystemCategory(category, categoryOwnerMap: categoryOwnerMap)
        }
        let groupedBySystemKey = Dictionary(grouping: activeSystemCategories) { $0.systemKey ?? "" }

        for (rawSystemKey, group) in groupedBySystemKey where !rawSystemKey.isEmpty {
            let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: rawSystemKey)
            let preferred = preferredLocalCategory(in: group)
            let canonicalCategory: TransactionCategory

            if let existingCanonical = group.first(where: { $0.id == canonicalID }) {
                canonicalCategory = existingCanonical
                if preferred !== existingCanonical {
                    didMutate = mergeCategoryValues(from: preferred, into: existingCanonical) || didMutate
                }
            } else {
                let previousID = preferred.id
                preferred.id = canonicalID
                canonicalCategory = preferred
                didMutate = true

                rewriteCategoryIdentifiers(
                    from: [previousID: canonicalID],
                    modelContext: modelContext,
                    ownershipScopes: ownershipScopes,
                    conflicts: conflicts,
                    outbox: outbox
                )
            }

            for duplicate in group where duplicate !== canonicalCategory {
                didMutate = true
                repointCategoryReferences(
                    from: duplicate,
                    to: canonicalCategory,
                    transactions: transactions,
                    budgets: budgets,
                    recurringBills: recurringBills,
                    categories: categories,
                    now: now,
                    result: &result
                )
                if duplicate.id != canonicalCategory.id {
                    rewriteCategoryIdentifiers(
                        from: [duplicate.id: canonicalCategory.id],
                        modelContext: modelContext,
                        ownershipScopes: ownershipScopes,
                        conflicts: conflicts,
                        outbox: outbox
                    )
                }

                if duplicate.remoteVersion > 0 || duplicate.cloudSyncEnabled {
                    result.categoryIDsNeedingSync.insert(canonicalCategory.id)
                }
                removedCategoryObjects.insert(ObjectIdentifier(duplicate))
                modelContext.delete(duplicate)
            }
        }

        if didMutate {
            try modelContext.save()
        }

        return result
    }

    static func refreshCategorySyncEligibility(
        modelContext: ModelContext,
        repairResult: inout MistiaSystemCategoryRepairResult
    ) throws {
        let categories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
        let transactions = try modelContext.fetch(FetchDescriptor<LedgerTransaction>())
        let budgets = try modelContext.fetch(FetchDescriptor<BudgetPlan>())
        let recurringBills = try modelContext.fetch(FetchDescriptor<RecurringBillPlan>())
        let conflicts = try modelContext.fetch(FetchDescriptor<SyncConflict>())
        let ownershipScopes = try modelContext.fetch(FetchDescriptor<OwnedRecordScope>())
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let outbox = MistiaSyncOutbox()
        var didMutate = false

        let activeCategories = categories.filter {
            $0.deletedAt == nil
                && !isFamilyScopedSystemCategory($0, categoryOwnerMap: categoryOwnerMap)
        }
        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: preferredCategory)
        let baseReferencedCategoryIDs = collectReferencedCategoryIDs(
            transactions: transactions,
            budgets: budgets,
            recurringBills: recurringBills
        )
        let referencedCategoryIDs = expandedCategoryDependencyIDs(
            baseCategoryIDs: baseReferencedCategoryIDs,
            categoriesByID: categoriesByID
        )
        let conflictCategoryIDs = Set(
            conflicts
                .filter { $0.entity == .category }
                .map(\.recordID)
        )

        for category in activeCategories {
            let previousValue = category.cloudSyncEnabled
            let isReferenced = referencedCategoryIDs.contains(category.id)
            let isConflicted = conflictCategoryIDs.contains(category.id)
            let isCustomized = isCustomizedSystemCategory(category)

            let nextValue = isReferenced || isConflicted || isCustomized

            if previousValue != nextValue {
                category.cloudSyncEnabled = nextValue
                didMutate = true
                if nextValue {
                    repairResult.categoryIDsNeedingSync.insert(category.id)
                } else {
                    // When disabling sync for a category, we must also remove any pending 
                    // mutations for it from the outbox to prevent it from being pushed.
                    outbox.remove(entity: .category, recordID: category.id)
                }
            }
        }

        if didMutate {
            try modelContext.save()
        }
    }

    static func promoteCategoriesRequiredForSync(
        entity: MistiaSyncEntity,
        recordID: UUID,
        modifiedAt: Date,
        in container: ModelContainer
    ) throws -> [TransactionCategory] {
        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let categoryByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: preferredCategory)
        let requiredIDs = try requiredCategoryIDsForSync(
            entity: entity,
            recordID: recordID,
            context: context,
            categoryByID: categoryByID
        )

        guard !requiredIDs.isEmpty else { return [] }

        var promoted: [TransactionCategory] = []
        var didMutate = false

        for categoryID in requiredIDs {
            guard let category = categoryByID[categoryID] else { continue }
            guard !category.cloudSyncEnabled else { continue }

            category.cloudSyncEnabled = true
            if category.updatedAt < modifiedAt {
                category.updatedAt = modifiedAt
            }
            promoted.append(category)
            didMutate = true
        }

        if didMutate {
            try context.save()
        }

        return promoted.sorted { lhs, rhs in
            if lhs.hierarchyRole != rhs.hierarchyRole {
                return lhs.hierarchyRole == .parent
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    static func shouldQueueCategoryMutation(_ category: TransactionCategory) -> Bool {
        if category.cloudSyncEnabled { return true }
        if isSystemCategoryCloudSyncRequired(category) { return true }
        return false
    }

    nonisolated static func shouldExportCategory(_ category: TransactionCategory) -> Bool {
        category.cloudSyncEnabled || isSystemCategoryCloudSyncRequired(category)
    }

    static func isFamilyScopedSystemCategory(
        _ category: TransactionCategory,
        categoryOwnerMap: [UUID: UUID]
    ) -> Bool {
        guard category.isSystem,
              let rawSystemKey = category.systemKey,
              categoryOwnerMap[category.id] != nil else {
            return false
        }
        return category.id != MistiaSystemCategoryIdentity.canonicalID(for: rawSystemKey)
    }

    nonisolated static func isSystemCategoryCloudSyncRequired(_ category: TransactionCategory) -> Bool {
        guard category.isSystem else { return false }
        if category.deletedAt != nil { return true }
        return isCustomizedSystemCategory(category)
    }

    nonisolated static func isCustomizedSystemCategory(_ category: TransactionCategory) -> Bool {
        guard category.isSystem else { return false }
        let parentSystemKey = category.parentCategory?.systemKey
        return !isDefaultSystemCategoryState(
            rawSystemKey: category.systemKey,
            name: category.name,
            iconSymbolName: category.iconSymbolName,
            iconColorHex: category.iconColorHex,
            isFavorite: category.isFavorite,
            hierarchyRoleRawValue: category.hierarchyRoleRawValue,
            sortOrder: category.sortOrder,
            isArchived: category.isArchived,
            parentSystemKey: parentSystemKey
        )
    }

    static func isCustomizedRemoteSystemCategory(
        _ row: RemoteTransactionCategory,
        parentSystemKey: String?
    ) -> Bool {
        guard row.isSystem else { return false }
        return !isDefaultSystemCategoryState(
            rawSystemKey: row.systemKey,
            name: row.name,
            iconSymbolName: row.iconSymbolName,
            iconColorHex: row.iconColorHex,
            isFavorite: row.isFavorite,
            hierarchyRoleRawValue: row.hierarchyRoleRawValue,
            sortOrder: row.sortOrder,
            isArchived: row.isArchived,
            parentSystemKey: parentSystemKey
        )
    }

    static func canonicalizedSystemCategoryRow(
        _ row: RemoteTransactionCategory,
        parentSystemKey: String?
    ) -> RemoteTransactionCategory {
        guard let systemKey = row.systemKey else { return row }
        var canonical = row
        canonical.id = MistiaSystemCategoryIdentity.canonicalID(for: systemKey)
        canonical.parentCategoryID = parentSystemKey.map(MistiaSystemCategoryIdentity.canonicalID(for:))
        return canonical
    }

    private static func preferredLocalCategory(in categories: [TransactionCategory]) -> TransactionCategory {
        categories.max { lhs, rhs in
            categoryPriority(lhs) < categoryPriority(rhs)
        } ?? categories[0]
    }

    private static func categoryPriority(_ category: TransactionCategory) -> Int {
        var score = 0
        if category.id == MistiaSystemCategoryIdentity.canonicalID(for: category.systemKey ?? "") {
            score += 8
        }
        if category.cloudSyncEnabled {
            score += 16
        }
        if category.remoteVersion > 0 {
            score += 32
        }
        if isCustomizedSystemCategory(category) {
            score += 64
        }
        return score
    }

    nonisolated private static func latestRemoteCategory(
        _ lhs: RemoteTransactionCategory,
        _ rhs: RemoteTransactionCategory
    ) -> RemoteTransactionCategory {
        remoteCategoryPriority(lhs) >= remoteCategoryPriority(rhs) ? lhs : rhs
    }

    nonisolated private static func remoteCategoryPriority(_ row: RemoteTransactionCategory) -> Int {
        var score = Int(row.updatedAt.timeIntervalSince1970)
        if row.deletedAt == nil {
            score += 1_000_000_000
        }
        if row.isSystem,
           let systemKey = row.systemKey,
           row.id == MistiaSystemCategoryIdentity.cloudScopedID(
               canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
               ownerUserID: row.userID
           ) {
            score += 1_000
        }
        return score
    }

    private static func preferredCategory(
        _ lhs: TransactionCategory,
        _ rhs: TransactionCategory
    ) -> TransactionCategory {
        preferredLocalCategory(in: [lhs, rhs])
    }

    private static func absorbCategorySyncState(
        from source: TransactionCategory,
        into destination: TransactionCategory
    ) -> Bool {
        guard source !== destination else { return false }
        var didMutate = false

        if source.cloudSyncEnabled && !destination.cloudSyncEnabled {
            destination.cloudSyncEnabled = true
            didMutate = true
        }
        if destination.createdAt > source.createdAt {
            destination.createdAt = source.createdAt
            didMutate = true
        }
        if destination.updatedAt < source.updatedAt {
            destination.updatedAt = source.updatedAt
            didMutate = true
        }
        if destination.remoteVersion < source.remoteVersion {
            destination.remoteVersion = source.remoteVersion
            didMutate = true
        }

        return didMutate
    }

    private static func mergeCategoryValues(
        from source: TransactionCategory,
        into destination: TransactionCategory
    ) -> Bool {
        guard source !== destination else { return false }
        var didMutate = false

        if destination.name != source.name {
            destination.name = source.name
            didMutate = true
        }
        if destination.kindRawValue != source.kindRawValue {
            destination.kindRawValue = source.kindRawValue
            didMutate = true
        }
        if destination.iconSymbolName != source.iconSymbolName {
            destination.iconSymbolName = source.iconSymbolName
            didMutate = true
        }
        if destination.iconColorHex != source.iconColorHex {
            destination.iconColorHex = source.iconColorHex
            didMutate = true
        }
        if destination.favoriteRawValue != source.favoriteRawValue {
            destination.favoriteRawValue = source.favoriteRawValue
            didMutate = true
        }
        if destination.hierarchyRoleRawValue != source.hierarchyRoleRawValue {
            destination.hierarchyRoleRawValue = source.hierarchyRoleRawValue
            didMutate = true
        }
        if destination.parentCategory?.id != source.parentCategory?.id {
            destination.parentCategory = source.parentCategory
            didMutate = true
        }
        if destination.systemKey != source.systemKey {
            destination.systemKey = source.systemKey
            didMutate = true
        }
        if destination.isSystem != source.isSystem {
            destination.isSystem = source.isSystem
            didMutate = true
        }
        if destination.cloudSyncEnabled != source.cloudSyncEnabled {
            destination.cloudSyncEnabled = destination.cloudSyncEnabled || source.cloudSyncEnabled
            didMutate = true
        }
        if destination.sortOrder != source.sortOrder {
            destination.sortOrder = source.sortOrder
            didMutate = true
        }
        if destination.isArchived != source.isArchived {
            destination.isArchived = source.isArchived
            didMutate = true
        }
        if destination.archivedAt != source.archivedAt {
            destination.archivedAt = source.archivedAt
            didMutate = true
        }
        if destination.createdAt != source.createdAt {
            destination.createdAt = min(destination.createdAt, source.createdAt)
            didMutate = true
        }
        if destination.updatedAt != source.updatedAt {
            destination.updatedAt = max(destination.updatedAt, source.updatedAt)
            didMutate = true
        }
        if destination.deletedAt != source.deletedAt {
            destination.deletedAt = source.deletedAt
            didMutate = true
        }
        if destination.remoteVersion != source.remoteVersion {
            destination.remoteVersion = max(destination.remoteVersion, source.remoteVersion)
            didMutate = true
        }

        return didMutate
    }

    private static func repointCategoryReferences(
        from source: TransactionCategory,
        to destination: TransactionCategory,
        transactions: [LedgerTransaction],
        budgets: [BudgetPlan],
        recurringBills: [RecurringBillPlan],
        categories: [TransactionCategory],
        now: Date,
        result: inout MistiaSystemCategoryRepairResult
    ) {
        for transaction in transactions where transaction.category?.id == source.id {
            transaction.category = destination
            transaction.updatedAt = now
            if transaction.remoteVersion > 0 {
                result.transactionIDsNeedingSync.insert(transaction.id)
            }
        }

        for budget in budgets where budget.category?.id == source.id {
            budget.category = destination
            budget.updatedAt = now
            if budget.remoteVersion > 0 {
                result.budgetPlanIDsNeedingSync.insert(budget.id)
            }
        }

        for recurringBill in recurringBills where recurringBill.category?.id == source.id {
            recurringBill.category = destination
            recurringBill.updatedAt = now
            if recurringBill.remoteVersion > 0 {
                result.recurringBillPlanIDsNeedingSync.insert(recurringBill.id)
            }
        }

        for category in categories where category.parentCategory?.id == source.id {
            category.parentCategory = destination
            if category.updatedAt < now {
                category.updatedAt = now
            }
            if category.remoteVersion > 0 || category.cloudSyncEnabled {
                result.categoryIDsNeedingSync.insert(category.id)
            }
        }
    }

    private static func rewriteCategoryIdentifiers(
        from mappings: [UUID: UUID],
        modelContext: ModelContext,
        ownershipScopes: [OwnedRecordScope],
        conflicts: [SyncConflict],
        outbox: MistiaSyncOutbox
    ) {
        guard !mappings.isEmpty else { return }
        outbox.rewriteRecordIDs(entity: .category, mappings: mappings)

        for scope in ownershipScopes where scope.entity == .category {
            guard let replacement = mappings[scope.recordID] else { continue }
            if ownershipScopes.contains(where: {
                $0 !== scope && $0.entity == .category && $0.recordID == replacement
            }) {
                modelContext.delete(scope)
                continue
            }
            scope.recordID = replacement
            scope.id = OwnedRecordScope.scopeID(entity: .category, recordID: replacement)
        }

        for conflict in conflicts {
            if conflict.entity == .category, let replacement = mappings[conflict.recordID] {
                conflict.recordID = replacement
            }

            if let rewrittenLocal = rewriteConflictPayloadJSON(
                conflict.localPayloadJSON,
                entity: conflict.entity,
                mappings: mappings
            ) {
                conflict.localPayloadJSON = rewrittenLocal
            }
            if let rewrittenRemote = rewriteConflictPayloadJSON(
                conflict.remotePayloadJSON,
                entity: conflict.entity,
                mappings: mappings
            ) {
                conflict.remotePayloadJSON = rewrittenRemote
            }
        }
    }

    private static func collectReferencedCategoryIDs(
        transactions: [LedgerTransaction],
        budgets: [BudgetPlan],
        recurringBills: [RecurringBillPlan]
    ) -> Set<UUID> {
        var ids: Set<UUID> = []

        for transaction in transactions where transaction.deletedAt == nil {
            if let categoryID = transaction.category?.id {
                ids.insert(categoryID)
            }
        }

        for budget in budgets where budget.deletedAt == nil {
            if let categoryID = budget.category?.id {
                ids.insert(categoryID)
            }
        }

        for recurringBill in recurringBills where recurringBill.deletedAt == nil {
            if let categoryID = recurringBill.category?.id {
                ids.insert(categoryID)
            }
        }

        return ids
    }

    private static func expandedCategoryDependencyIDs(
        baseCategoryIDs: Set<UUID>,
        categoriesByID: [UUID: TransactionCategory]
    ) -> Set<UUID> {
        var expanded = baseCategoryIDs
        var didAdd = true

        while didAdd {
            didAdd = false
            for categoryID in Array(expanded) {
                guard let category = categoriesByID[categoryID],
                      let parentID = category.parentCategory?.id,
                      !expanded.contains(parentID) else {
                    continue
                }
                expanded.insert(parentID)
                didAdd = true
            }
        }

        return expanded
    }

    private static func requiredCategoryIDsForSync(
        entity: MistiaSyncEntity,
        recordID: UUID,
        context: ModelContext,
        categoryByID: [UUID: TransactionCategory]
    ) throws -> Set<UUID> {
        var ids: Set<UUID> = []

        switch entity {
        case .transaction:
            let descriptor = FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in
                    transaction.id == recordID
                }
            )
            if let transaction = try context.fetch(descriptor).first,
               let categoryID = transaction.category?.id {
                ids.insert(categoryID)
            }
        case .budgetPlan:
            let descriptor = FetchDescriptor<BudgetPlan>(
                predicate: #Predicate<BudgetPlan> { budget in
                    budget.id == recordID
                }
            )
            if let budget = try context.fetch(descriptor).first,
               let categoryID = budget.category?.id {
                ids.insert(categoryID)
            }
        case .recurringBillPlan:
            let descriptor = FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate<RecurringBillPlan> { plan in
                    plan.id == recordID
                }
            )
            if let plan = try context.fetch(descriptor).first,
               let categoryID = plan.category?.id {
                ids.insert(categoryID)
            }
        case .category:
            if let category = categoryByID[recordID] {
                ids.insert(category.id)
            }
        case .wallet, .creditCardProfile, .savingsGoal, .installmentPlan, .dueOccurrenceRecord:
            break
        }

        return expandedCategoryDependencyIDs(baseCategoryIDs: ids, categoriesByID: categoryByID)
    }

    nonisolated private static func isDefaultSystemCategoryState(
        rawSystemKey: String?,
        name: String,
        iconSymbolName: String,
        iconColorHex: String,
        isFavorite: Bool,
        hierarchyRoleRawValue: String?,
        sortOrder: Int,
        isArchived: Bool,
        parentSystemKey: String?
    ) -> Bool {
        guard let descriptor = MistiaSystemCategoryIdentity.descriptor(for: rawSystemKey) else {
            return false
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRole = hierarchyRoleRawValue.flatMap(TransactionCategoryHierarchyRole.init(rawValue:))
            ?? descriptor.hierarchyRole

        // We check against all known localized names and aliases to avoid marking default categories as customized
        let knownNames = descriptor.knownNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard knownNames.contains(normalizedName) else { return false }

        if iconSymbolName != descriptor.iconSymbolName {
            if let fallback = descriptor.fallbackIconSymbolName {
                guard iconSymbolName == fallback else { return false }
            } else {
                return false
            }
        }

        // We normalize the stored color to its nearest preset and compare with the default preset for this category
        let normalizedStoredHex = MistiaIconColorPalette.normalizedHex(iconColorHex)
        let presetStoredHex = MistiaIconColorPalette.presetHex(forDefault: normalizedStoredHex)
        guard presetStoredHex == descriptor.iconColorHex else { return false }

        guard !isFavorite else { return false }
        guard normalizedRole == descriptor.hierarchyRole else { return false }
        if let defaultSortOrder = descriptor.sortOrder {
            guard sortOrder == defaultSortOrder else { return false }
        }

        guard isArchived == descriptor.startsArchived else { return false }

        switch descriptor.hierarchyRole {
        case .parent:
            return parentSystemKey == nil
        case .child:
            // For children, we are lenient: if it has no parent but should have one, it might be a 
            // transient state during bootstrap, so we don't necessarily mark it customized 
            // if everything else is default. However, to be safe and avoid syncing 100+ categories,
            // we should ensure parents are correctly linked before this check.
            guard let parentSystemKey else { 
                return descriptor.defaultParentSystemKey == nil 
            }
            return parentSystemKey == descriptor.defaultParentSystemKey
        }
    }

    private static func rewriteConflictPayloadJSON(
        _ jsonString: String,
        entity: MistiaSyncEntity,
        mappings: [UUID: UUID]
    ) -> String? {
        guard let payload = try? MistiaSyncUploadRecord.decode(
            entity: entity,
            jsonString: jsonString
        ) else {
            return nil
        }

        return try? payload
            .remappingCategoryReferences(mappings)
            .asJSONString()
    }
}
