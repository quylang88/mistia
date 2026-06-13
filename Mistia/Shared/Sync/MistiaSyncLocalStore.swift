import Foundation
import SwiftData

nonisolated private struct FamilyScopedSystemCategoryKey: Hashable {
    let ownerUserID: UUID
    let systemKey: String
}

nonisolated enum MistiaSyncLocalStore {
    nonisolated private static func latestWallet(_ lhs: LedgerWallet, _ rhs: LedgerWallet) -> LedgerWallet {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestCreditProfile(_ lhs: CreditCardProfile, _ rhs: CreditCardProfile) -> CreditCardProfile {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestCategory(_ lhs: TransactionCategory, _ rhs: TransactionCategory) -> TransactionCategory {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestTransaction(_ lhs: LedgerTransaction, _ rhs: LedgerTransaction) -> LedgerTransaction {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestSettlementGroup(_ lhs: SettlementGroup, _ rhs: SettlementGroup) -> SettlementGroup {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestSettlementParticipant(_ lhs: SettlementParticipant, _ rhs: SettlementParticipant) -> SettlementParticipant {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestBudget(_ lhs: BudgetPlan, _ rhs: BudgetPlan) -> BudgetPlan {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestGoal(_ lhs: SavingsGoal, _ rhs: SavingsGoal) -> SavingsGoal {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestRecurringBill(_ lhs: RecurringBillPlan, _ rhs: RecurringBillPlan) -> RecurringBillPlan {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestInstallment(_ lhs: InstallmentPlan, _ rhs: InstallmentPlan) -> InstallmentPlan {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestOccurrence(_ lhs: DueOccurrenceRecord, _ rhs: DueOccurrenceRecord) -> DueOccurrenceRecord {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestProfile(_ lhs: UserAccountProfile, _ rhs: UserAccountProfile) -> UserAccountProfile {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestScope(_ lhs: OwnedRecordScope, _ rhs: OwnedRecordScope) -> OwnedRecordScope {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    nonisolated private static func latestAudit(_ lhs: TransactionAuditRecord, _ rhs: TransactionAuditRecord) -> TransactionAuditRecord {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    static func totalObjectCount(in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        return try fetchWallets(context).count
            + fetchCreditCardProfiles(context).count
            + fetchCategories(context).count
            + fetchSettlementGroups(context).count
            + fetchSettlementParticipants(context).count
            + fetchTransactions(context).count
            + fetchTransactionAudits(context).count
            + fetchBudgetPlans(context).count
            + fetchSavingsGoals(context).count
            + fetchRecurringBillPlans(context).count
            + fetchInstallmentPlans(context).count
            + fetchDueOccurrences(context).count
    }

    static func hasMeaningfulUserData(in container: ModelContainer) throws -> Bool {
        let context = ModelContext(container)

        if try fetchActiveWallet(context) != nil {
            return true
        }
        if try fetchActiveCreditCardProfile(context) != nil {
            return true
        }
        if try fetchActiveTransaction(context) != nil {
            return true
        }
        if try fetchActiveSettlementGroup(context) != nil {
            return true
        }
        if try fetchActiveSettlementParticipant(context) != nil {
            return true
        }
        if try fetchActiveBudgetPlan(context) != nil {
            return true
        }
        if try fetchActiveSavingsGoal(context) != nil {
            return true
        }
        if try fetchActiveRecurringBillPlan(context) != nil {
            return true
        }
        if try fetchActiveInstallmentPlan(context) != nil {
            return true
        }
        if try fetchActiveDueOccurrence(context) != nil {
            return true
        }
        if try fetchActiveUserCategory(context) != nil {
            return true
        }

        return false
    }

    static func reassignLocalOwnership(
        from previousOwnerUserID: UUID,
        to newOwnerUserID: UUID,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)

        for scope in try context.fetch(FetchDescriptor<OwnedRecordScope>()) where scope.ownerUserID == previousOwnerUserID {
            scope.ownerUserID = newOwnerUserID
            scope.updatedAt = .now
        }

        for audit in try fetchTransactionAudits(context) {
            if audit.createdByUserID == previousOwnerUserID {
                audit.createdByUserID = newOwnerUserID
            }
            if audit.lastModifiedByUserID == previousOwnerUserID {
                audit.lastModifiedByUserID = newOwnerUserID
            }
            audit.updatedAt = .now
        }

        try context.save()
    }

    static func exportSnapshot(
        for userID: UUID,
        from container: ModelContainer
    ) throws -> MistiaRemoteSnapshot {
        let context = ModelContext(container)
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let auditMap = try TransactionAuditStore.auditMap(from: fetchTransactionAudits(context))
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let profileOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .creditCardProfile)
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let settlementGroupOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementGroup)
        let settlementParticipantOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementParticipant)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
        let goalOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
        let recurringOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let installmentOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)
        let wallets = try fetchWallets(context)
            .filter { walletOwnerMap[$0.id] == nil || walletOwnerMap[$0.id] == userID }
        let creditCardProfiles = try fetchCreditCardProfiles(context)
            .filter { profileOwnerMap[$0.id] == nil || profileOwnerMap[$0.id] == userID }
        let transactions = try fetchTransactions(context)
            .filter { transactionOwnerMap[$0.id] == nil || transactionOwnerMap[$0.id] == userID }
        let settlementGroups = try fetchSettlementGroups(context)
            .filter { settlementGroupOwnerMap[$0.id] == nil || settlementGroupOwnerMap[$0.id] == userID }
        let settlementParticipants = try fetchSettlementParticipants(context)
            .filter { settlementParticipantOwnerMap[$0.id] == nil || settlementParticipantOwnerMap[$0.id] == userID }
        let budgetPlans = try fetchBudgetPlans(context)
            .filter { budgetOwnerMap[$0.id] == nil || budgetOwnerMap[$0.id] == userID }
        let savingsGoals = try fetchSavingsGoals(context)
            .filter { goalOwnerMap[$0.id] == nil || goalOwnerMap[$0.id] == userID }
        let recurringBillPlans = try fetchRecurringBillPlans(context)
            .filter { recurringOwnerMap[$0.id] == nil || recurringOwnerMap[$0.id] == userID }
        let installmentPlans = try fetchInstallmentPlans(context)
            .filter { installmentOwnerMap[$0.id] == nil || installmentOwnerMap[$0.id] == userID }
        let dueOccurrences = try fetchDueOccurrences(context)
            .filter { occurrenceOwnerMap[$0.id] == nil || occurrenceOwnerMap[$0.id] == userID }
        let categories = try fetchCategories(context)
            .filter { categoryOwnerMap[$0.id] == nil || categoryOwnerMap[$0.id] == userID }

        return MistiaRemoteSnapshot(
            wallets: wallets.map { RemoteLedgerWallet(local: $0, userID: userID) },
            creditCardProfiles: creditCardProfiles.map { RemoteCreditCardProfile(local: $0, userID: userID) },
            categories: categories.map { RemoteTransactionCategory(local: $0, userID: userID) },
            settlementGroups: settlementGroups.map { RemoteSettlementGroup(local: $0, userID: userID) },
            settlementParticipants: settlementParticipants.map { RemoteSettlementParticipant(local: $0, userID: userID) },
            transactions: transactions.map {
                RemoteLedgerTransaction(
                    local: $0,
                    userID: userID,
                    auditRecord: auditMap[$0.id]
                )
            },
            budgetPlans: budgetPlans.map { RemoteBudgetPlan(local: $0, userID: userID) },
            savingsGoals: savingsGoals.map { RemoteSavingsGoal(local: $0, userID: userID) },
            recurringBillPlans: recurringBillPlans.map {
                RemoteRecurringBillPlan(
                    local: $0,
                    userID: userID,
                    categoryID: recurringBillCategoryID(for: $0, userID: userID, categories: categories)
                )
            },
            installmentPlans: installmentPlans.map { RemoteInstallmentPlan(local: $0, userID: userID) },
            dueOccurrences: dueOccurrences.map { RemoteDueOccurrenceRecord(local: $0, userID: userID) }
        )
    }

    static func exportSnapshotForUpload(
        for userID: UUID,
        from container: ModelContainer
    ) throws -> MistiaRemoteSnapshot {
        try exportSnapshot(for: userID, from: container)
    }

    static func exportRecord(
        for mutation: MistiaSyncMutation,
        from container: ModelContainer
    ) throws -> MistiaSyncUploadRecord? {
        let context = ModelContext(container)
        let subjectUserID = mutation.subjectUserID

        switch mutation.entity {
        case .wallet:
            guard let wallet = try fetchWallet(id: mutation.recordID, context) else {
                return nil
            }
            return .wallet(RemoteLedgerWallet(local: wallet, userID: subjectUserID))
        case .creditCardProfile:
            guard let profile = try fetchCreditCardProfile(id: mutation.recordID, context) else {
                return nil
            }
            return .creditCardProfile(RemoteCreditCardProfile(local: profile, userID: subjectUserID))
        case .category:
            guard let category = try fetchCategory(id: mutation.recordID, context) else {
                return nil
            }
            return .category(RemoteTransactionCategory(local: category, userID: subjectUserID))
        case .transaction:
            guard let transaction = try fetchTransaction(id: mutation.recordID, context) else {
                return nil
            }
            let auditRecord = try TransactionAuditStore.fetch(
                transactionID: transaction.id,
                context: context
            )
            return .transaction(
                RemoteLedgerTransaction(
                    local: transaction,
                    userID: subjectUserID,
                    auditRecord: auditRecord
                )
            )
        case .settlementGroup:
            guard let group = try fetchSettlementGroup(id: mutation.recordID, context) else {
                return nil
            }
            return .settlementGroup(RemoteSettlementGroup(local: group, userID: subjectUserID))
        case .settlementParticipant:
            guard let participant = try fetchSettlementParticipant(id: mutation.recordID, context) else {
                return nil
            }
            return .settlementParticipant(RemoteSettlementParticipant(local: participant, userID: subjectUserID))
        case .budgetPlan:
            guard let plan = try fetchBudgetPlan(id: mutation.recordID, context) else {
                return nil
            }
            return .budgetPlan(RemoteBudgetPlan(local: plan, userID: subjectUserID))
        case .savingsGoal:
            guard let goal = try fetchSavingsGoal(id: mutation.recordID, context) else {
                return nil
            }
            return .savingsGoal(RemoteSavingsGoal(local: goal, userID: subjectUserID))
        case .recurringBillPlan:
            guard let plan = try fetchRecurringBillPlan(id: mutation.recordID, context) else {
                return nil
            }
            let categories = try fetchCategories(context)
            return .recurringBillPlan(
                RemoteRecurringBillPlan(
                    local: plan,
                    userID: subjectUserID,
                    categoryID: recurringBillCategoryID(for: plan, userID: subjectUserID, categories: categories)
                )
            )
        case .installmentPlan:
            guard let plan = try fetchInstallmentPlan(id: mutation.recordID, context) else {
                return nil
            }
            return .installmentPlan(RemoteInstallmentPlan(local: plan, userID: subjectUserID))
        case .dueOccurrenceRecord:
            guard let record = try fetchDueOccurrence(id: mutation.recordID, context) else {
                return nil
            }
            return .dueOccurrence(RemoteDueOccurrenceRecord(local: record, userID: subjectUserID))
        }
    }

    static func exportCategoryRecord(
        remoteCategoryID: UUID,
        subjectUserID: UUID,
        from container: ModelContainer
    ) throws -> MistiaSyncUploadRecord? {
        let context = ModelContext(container)
        let categories = try fetchCategories(context)
        guard let category = categories.first(where: { category in
            mistiaCloudCategoryID(for: category, userID: subjectUserID) == remoteCategoryID
                || category.id == remoteCategoryID
        }) else {
            return synthesizedSystemParentCategoryRecord(
                remoteCategoryID: remoteCategoryID,
                subjectUserID: subjectUserID
            )
        }
        guard category.deletedAt == nil else { return nil }
        return .category(RemoteTransactionCategory(local: category, userID: subjectUserID))
    }

    private static func synthesizedSystemParentCategoryRecord(
        remoteCategoryID: UUID,
        subjectUserID: UUID
    ) -> MistiaSyncUploadRecord? {
        guard let parent = MistiaSystemCategoryRegistry.shared.allParents.first(where: { p in
            let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: p.id)
            return MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: canonicalID,
                ownerUserID: subjectUserID
            ) == remoteCategoryID || canonicalID == remoteCategoryID
        }) else {
            return nil
        }

        let now = Date()
        let canonicalParentID = MistiaSystemCategoryIdentity.canonicalID(for: parent.id)
        let activeParents = MistiaSystemCategoryRegistry.shared.allParents.filter { $0.active }
        let sortOrder = activeParents.firstIndex(where: { $0.id == parent.id }) ?? 0

        return .category(
            RemoteTransactionCategory(
                userID: subjectUserID,
                id: MistiaSystemCategoryIdentity.cloudScopedID(
                    canonicalCategoryID: canonicalParentID,
                    ownerUserID: subjectUserID
                ),
                name: parent.translations["vi"] ?? parent.id,
                nameEnglish: parent.translations["en"] ?? parent.translations["vi"] ?? parent.id,
                nameJapanese: parent.translations["ja"] ?? parent.translations["vi"] ?? parent.id,
                kindRawValue: parent.kind(in: MistiaSystemCategoryRegistry.shared).rawValue,
                iconSymbolName: parent.icon,
                iconColorHex: MistiaIconColorPalette.presetHex(forDefault: parent.color),
                isFavorite: false,
                familyBudgetSpendingEnabled: false,
                parentCategoryID: nil,
                hierarchyRoleRawValue: TransactionCategoryHierarchyRole.parent.rawValue,
                systemKey: parent.id,
                isSystem: true,
                sortOrder: sortOrder,
                isArchived: !parent.active,
                archivedAt: parent.active ? nil : now,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                syncVersion: 1,
                lastModifiedByDeviceID: nil
            )
        )
    }

    static func currentRemoteVersion(
        for entity: MistiaSyncEntity,
        recordID: UUID,
        from container: ModelContainer
    ) throws -> Int64 {
        let context = ModelContext(container)

        switch entity {
        case .wallet:
            return try fetchWallet(id: recordID, context)?.remoteVersion ?? 0
        case .creditCardProfile:
            return try fetchCreditCardProfile(id: recordID, context)?.remoteVersion ?? 0
        case .category:
            return try fetchCategory(id: recordID, context)?.remoteVersion ?? 0
        case .transaction:
            return try fetchTransaction(id: recordID, context)?.remoteVersion ?? 0
        case .settlementGroup:
            return try fetchSettlementGroup(id: recordID, context)?.remoteVersion ?? 0
        case .settlementParticipant:
            return try fetchSettlementParticipant(id: recordID, context)?.remoteVersion ?? 0
        case .budgetPlan:
            return try fetchBudgetPlan(id: recordID, context)?.remoteVersion ?? 0
        case .savingsGoal:
            return try fetchSavingsGoal(id: recordID, context)?.remoteVersion ?? 0
        case .recurringBillPlan:
            return try fetchRecurringBillPlan(id: recordID, context)?.remoteVersion ?? 0
        case .installmentPlan:
            return try fetchInstallmentPlan(id: recordID, context)?.remoteVersion ?? 0
        case .dueOccurrenceRecord:
            return try fetchDueOccurrence(id: recordID, context)?.remoteVersion ?? 0
        }
    }

    static func detachFromCloud(in container: ModelContainer) throws {
        let context = ModelContext(container)

        try fetchWallets(context).forEach { $0.remoteVersion = 0 }
        try fetchCreditCardProfiles(context).forEach { $0.remoteVersion = 0 }
        try fetchCategories(context).forEach { $0.remoteVersion = 0 }
        try fetchSettlementGroups(context).forEach { $0.remoteVersion = 0 }
        try fetchSettlementParticipants(context).forEach { $0.remoteVersion = 0 }
        try fetchTransactions(context).forEach { $0.remoteVersion = 0 }
        try fetchBudgetPlans(context).forEach { $0.remoteVersion = 0 }
        try fetchSavingsGoals(context).forEach { $0.remoteVersion = 0 }
        try fetchRecurringBillPlans(context).forEach { $0.remoteVersion = 0 }
        try fetchInstallmentPlans(context).forEach { $0.remoteVersion = 0 }
        try fetchDueOccurrences(context).forEach { $0.remoteVersion = 0 }

        try fetchConflicts(context).forEach { context.delete($0) }
        try context.save()
    }

    static func applySnapshotIncrementally(
        _ snapshot: MistiaRemoteSnapshot,
        shouldPruneMissing: Bool,
        protectedRecordIDs: Set<String>,
        preserveLocalNewerRows: Bool = false,
        familyCategoryScopedTo localUserID: UUID? = nil,
        familyCategoryPruneOwnerIDs: Set<UUID> = [],
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        try applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: shouldPruneMissing,
            protectedRecordIDs: protectedRecordIDs,
            preserveLocalNewerRows: preserveLocalNewerRows,
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: familyCategoryPruneOwnerIDs,
            in: context
        )
        try context.save()
    }

    private static func applySnapshotIncrementally(
        _ snapshot: MistiaRemoteSnapshot,
        shouldPruneMissing: Bool,
        protectedRecordIDs: Set<String>,
        preserveLocalNewerRows: Bool,
        familyCategoryScopedTo localUserID: UUID?,
        familyCategoryPruneOwnerIDs: Set<UUID>,
        in context: ModelContext
    ) throws {
        let categories = try fetchCategories(context)
        let categoryIDMap = scopedCategoryIDMap(snapshot.categories, localUserID: localUserID)
        let categoryRows = scopedCategoryRows(
            snapshot.categories,
            categoryIDMap: categoryIDMap
        )
        let transactionRows = scopedTransactionRows(
            snapshot.transactions,
            categoryIDMap: categoryIDMap,
            localUserID: localUserID
        )
        let budgetRows = scopedBudgetRows(
            snapshot.budgetPlans,
            categoryIDMap: categoryIDMap,
            localUserID: localUserID
        )
        let recurringRows = scopedRecurringBillRows(
            snapshot.recurringBillPlans,
            categoryIDMap: categoryIDMap,
            localUserID: localUserID
        )

        let wallets = try fetchWallets(context)
        let creditProfiles = try fetchCreditCardProfiles(context)
        let settlementGroups = try fetchSettlementGroups(context)
        let settlementParticipants = try fetchSettlementParticipants(context)
        let transactions = try fetchTransactions(context)
        let budgetPlans = try fetchBudgetPlans(context)
        let savingsGoals = try fetchSavingsGoals(context)
        let recurringBillPlans = try fetchRecurringBillPlans(context)
        let installmentPlans = try fetchInstallmentPlans(context)
        let dueOccurrences = try fetchDueOccurrences(context)
        var walletByID = Dictionary(wallets.map { ($0.id, $0) }, uniquingKeysWith: latestWallet)
        var categoryByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: latestCategory)
        var profileByID = Dictionary(creditProfiles.map { ($0.id, $0) }, uniquingKeysWith: latestCreditProfile)
        var settlementGroupByID = Dictionary(settlementGroups.map { ($0.id, $0) }, uniquingKeysWith: latestSettlementGroup)
        var settlementParticipantByID = Dictionary(settlementParticipants.map { ($0.id, $0) }, uniquingKeysWith: latestSettlementParticipant)
        var transactionByID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: latestTransaction)
        var budgetByID = Dictionary(budgetPlans.map { ($0.id, $0) }, uniquingKeysWith: latestBudget)
        var goalByID = Dictionary(savingsGoals.map { ($0.id, $0) }, uniquingKeysWith: latestGoal)
        var recurringByID = Dictionary(recurringBillPlans.map { ($0.id, $0) }, uniquingKeysWith: latestRecurringBill)
        var installmentByID = Dictionary(installmentPlans.map { ($0.id, $0) }, uniquingKeysWith: latestInstallment)
        var occurrenceByID = Dictionary(dueOccurrences.map { ($0.id, $0) }, uniquingKeysWith: latestOccurrence)

        for row in snapshot.wallets {
            guard shouldApplyRemoteRow(
                row,
                entity: .wallet,
                existing: walletByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertWallet(row, context: context, walletByID: &walletByID)
        }

        for row in categoryRows {
            guard shouldApplyRemoteRow(
                row,
                entity: .category,
                existing: categoryByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertCategory(
                row,
                context: context,
                categoryByID: &categoryByID
            )
        }

        for row in categoryRows {
            applyCategoryHierarchy(row, categoryByID: categoryByID)
        }

        if let localUserID, !familyCategoryPruneOwnerIDs.isEmpty {
            try pruneStaleFamilyScopedCategories(
                ownerUserIDs: familyCategoryPruneOwnerIDs,
                keepCategoryIDs: Set(categoryRows.map(\.id)),
                localUserID: localUserID,
                context: context,
                categoryByID: &categoryByID
            )
        }

        for row in snapshot.creditCardProfiles {
            guard shouldApplyRemoteRow(
                row,
                entity: .creditCardProfile,
                existing: profileByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertCreditProfile(
                row,
                context: context,
                walletByID: walletByID,
                profileByID: &profileByID
            )
        }

        for row in snapshot.settlementGroups {
            guard shouldApplyRemoteRow(
                row,
                entity: .settlementGroup,
                existing: settlementGroupByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertSettlementGroup(row, context: context, groupByID: &settlementGroupByID)
        }

        for row in snapshot.settlementParticipants {
            guard shouldApplyRemoteRow(
                row,
                entity: .settlementParticipant,
                existing: settlementParticipantByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertSettlementParticipant(row, context: context, participantByID: &settlementParticipantByID)
        }

        for row in transactionRows {
            guard shouldApplyRemoteRow(
                row,
                entity: .transaction,
                existing: transactionByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        }

        for row in budgetRows {
            guard shouldApplyRemoteRow(
                row,
                entity: .budgetPlan,
                existing: budgetByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertBudget(row, context: context, categoryByID: categoryByID, budgetByID: &budgetByID)
        }

        for row in snapshot.savingsGoals {
            guard shouldApplyRemoteRow(
                row,
                entity: .savingsGoal,
                existing: goalByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertGoal(row, context: context, walletByID: walletByID, goalByID: &goalByID)
        }

        for row in recurringRows {
            guard shouldApplyRemoteRow(
                row,
                entity: .recurringBillPlan,
                existing: recurringByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertRecurringBill(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                recurringByID: &recurringByID
            )
        }

        for row in snapshot.installmentPlans {
            guard shouldApplyRemoteRow(
                row,
                entity: .installmentPlan,
                existing: installmentByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertInstallment(row, context: context, walletByID: walletByID, installmentByID: &installmentByID)
        }

        for row in snapshot.dueOccurrences {
            guard shouldApplyRemoteRow(
                row,
                entity: .dueOccurrenceRecord,
                existing: occurrenceByID[row.id],
                protectedRecordIDs: protectedRecordIDs,
                preserveLocalNewerRows: preserveLocalNewerRows
            ) else { continue }
            try upsertDueOccurrence(row, context: context, occurrenceByID: &occurrenceByID)
        }

        if shouldPruneMissing {
            pruneRecordsMissingFromRemote(
                existing: wallets,
                remoteIDs: Set(snapshot.wallets.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: creditProfiles,
                remoteIDs: Set(snapshot.creditCardProfiles.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: categories,
                remoteIDs: Set(categoryRows.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: settlementGroups,
                remoteIDs: Set(snapshot.settlementGroups.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: settlementParticipants,
                remoteIDs: Set(snapshot.settlementParticipants.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: transactions,
                remoteIDs: Set(transactionRows.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: budgetPlans,
                remoteIDs: Set(budgetRows.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: savingsGoals,
                remoteIDs: Set(snapshot.savingsGoals.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: recurringBillPlans,
                remoteIDs: Set(recurringRows.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: installmentPlans,
                remoteIDs: Set(snapshot.installmentPlans.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: dueOccurrences,
                remoteIDs: Set(snapshot.dueOccurrences.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
        }

    }


    static func applyRemoteRecord(
        _ record: MistiaSyncUploadRecord,
        localUserID: UUID? = nil,
        preservesLocalSystemDefaults: Bool = true,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let wallets = try fetchWallets(context)
        let categories = try fetchCategories(context)
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let categoryRemoteIDMap = remoteCategoryIDMap(
            categories: categories,
            ownerMap: MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        )
        var walletByID = Dictionary(wallets.map { ($0.id, $0) }, uniquingKeysWith: latestWallet)
        var categoryByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: latestCategory)

        switch record {
        case .wallet(let row):
            try upsertWallet(row, context: context, walletByID: &walletByID)
        case .creditCardProfile(let row):
            var profileByID = Dictionary(
                try fetchCreditCardProfiles(context).map { ($0.id, $0) },
                uniquingKeysWith: latestCreditProfile
            )
            try upsertCreditProfile(row, context: context, walletByID: walletByID, profileByID: &profileByID)
        case .category(let row):
            let categoryIDMap = scopedCategoryIDMap([row], localUserID: localUserID)
            guard let scopedRow = scopedCategoryRows([row], categoryIDMap: categoryIDMap).first else { return }
            try upsertCategory(
                scopedRow,
                context: context,
                categoryByID: &categoryByID,
                preservesLocalSystemDefaults: preservesLocalSystemDefaults
            )
            applyCategoryHierarchy(scopedRow, categoryByID: categoryByID)
        case .transaction(let row):
            var transactionByID = Dictionary(
                try fetchTransactions(context).map { ($0.id, $0) },
                uniquingKeysWith: latestTransaction
            )
            let scopedRow = scopedTransactionRows(
                [row],
                categoryIDMap: categoryRemoteIDMap,
                localUserID: row.userID
            ).first ?? row
            try upsertTransaction(
                scopedRow,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        case .settlementGroup(let row):
            var groupByID = Dictionary(
                try fetchSettlementGroups(context).map { ($0.id, $0) },
                uniquingKeysWith: latestSettlementGroup
            )
            try upsertSettlementGroup(row, context: context, groupByID: &groupByID)
        case .settlementParticipant(let row):
            var participantByID = Dictionary(
                try fetchSettlementParticipants(context).map { ($0.id, $0) },
                uniquingKeysWith: latestSettlementParticipant
            )
            try upsertSettlementParticipant(row, context: context, participantByID: &participantByID)
        case .budgetPlan(let row):
            var budgetByID = Dictionary(
                try fetchBudgetPlans(context).map { ($0.id, $0) },
                uniquingKeysWith: latestBudget
            )
            let scopedRow = scopedBudgetRows(
                [row],
                categoryIDMap: categoryRemoteIDMap,
                localUserID: row.userID
            ).first ?? row
            try upsertBudget(scopedRow, context: context, categoryByID: categoryByID, budgetByID: &budgetByID)
        case .savingsGoal(let row):
            var goalByID = Dictionary(
                try fetchSavingsGoals(context).map { ($0.id, $0) },
                uniquingKeysWith: latestGoal
            )
            try upsertGoal(row, context: context, walletByID: walletByID, goalByID: &goalByID)
        case .recurringBillPlan(let row):
            var recurringByID = Dictionary(
                try fetchRecurringBillPlans(context).map { ($0.id, $0) },
                uniquingKeysWith: latestRecurringBill
            )
            let scopedRow = scopedRecurringBillRows(
                [row],
                categoryIDMap: categoryRemoteIDMap,
                localUserID: row.userID
            ).first ?? row
            try upsertRecurringBill(
                scopedRow,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                recurringByID: &recurringByID
            )
        case .installmentPlan(let row):
            var installmentByID = Dictionary(
                try fetchInstallmentPlans(context).map { ($0.id, $0) },
                uniquingKeysWith: latestInstallment
            )
            try upsertInstallment(row, context: context, walletByID: walletByID, installmentByID: &installmentByID)
        case .dueOccurrence(let row):
            var occurrenceByID = Dictionary(
                try fetchDueOccurrences(context).map { ($0.id, $0) },
                uniquingKeysWith: latestOccurrence
            )
            try upsertDueOccurrence(row, context: context, occurrenceByID: &occurrenceByID)
        }

        try context.save()
    }

    static func mergeAccessibleTransactions(
        _ rows: [RemoteLedgerTransaction],
        protectedRecordIDs: Set<String>,
        familyCategoryScopedTo localUserID: UUID? = nil,
        preserveLocalNewerRows: Bool = true,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        try mergeAccessibleTransactions(
            rows,
            protectedRecordIDs: protectedRecordIDs,
            familyCategoryScopedTo: localUserID,
            preserveLocalNewerRows: preserveLocalNewerRows,
            in: context
        )
        try context.save()
    }

    static func applyAccessibleFinanceSnapshot(
        _ snapshot: MistiaRemoteSnapshot,
        protectedRecordIDs: Set<String>,
        familyCategoryScopedTo localUserID: UUID,
        familyCategoryPruneOwnerIDs: Set<UUID>,
        preserveLocalNewerRows: Bool,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let nonTransactionSnapshot = MistiaRemoteSnapshot(
            wallets: snapshot.wallets,
            creditCardProfiles: snapshot.creditCardProfiles,
            categories: snapshot.categories,
            settlementGroups: snapshot.settlementGroups,
            settlementParticipants: snapshot.settlementParticipants,
            transactions: [],
            budgetPlans: snapshot.budgetPlans,
            savingsGoals: snapshot.savingsGoals,
            recurringBillPlans: snapshot.recurringBillPlans,
            installmentPlans: snapshot.installmentPlans,
            dueOccurrences: snapshot.dueOccurrences
        )

        try applySnapshotIncrementally(
            nonTransactionSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: protectedRecordIDs,
            preserveLocalNewerRows: preserveLocalNewerRows,
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: familyCategoryPruneOwnerIDs,
            in: context
        )
        try mergeAccessibleTransactions(
            snapshot.transactions,
            protectedRecordIDs: protectedRecordIDs,
            familyCategoryScopedTo: localUserID,
            preserveLocalNewerRows: preserveLocalNewerRows,
            in: context
        )
        try context.save()
    }

    private static func mergeAccessibleTransactions(
        _ rows: [RemoteLedgerTransaction],
        protectedRecordIDs: Set<String>,
        familyCategoryScopedTo localUserID: UUID?,
        preserveLocalNewerRows: Bool,
        in context: ModelContext
    ) throws {
        let wallets = try fetchWallets(context)
        let categories = try fetchCategories(context)
        let transactions = try fetchTransactions(context)
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let audits = try TransactionAuditStore.auditMap(from: fetchTransactionAudits(context))
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let transactionRows = scopedTransactionRows(
            rows,
            categoryIDMap: remoteCategoryIDMap(
                categories: categories,
                ownerMap: categoryOwnerMap
            ),
            localUserID: localUserID
        )
        let walletByID = Dictionary(wallets.map { ($0.id, $0) }, uniquingKeysWith: latestWallet)
        let categoryByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: latestCategory)
        var transactionByID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: latestTransaction)

        for row in transactionRows {
            let storageKey = canonicalStorageKey(entity: .transaction, recordID: row.id)
            guard !protectedRecordIDs.contains(storageKey) else { continue }

            guard let localTransaction = transactionByID[row.id] else {
                try upsertTransaction(
                    row,
                    context: context,
                    walletByID: walletByID,
                    categoryByID: categoryByID,
                    transactionByID: &transactionByID
                )
                continue
            }

            guard row.syncVersion >= localTransaction.remoteVersion else {
                continue
            }

            let localOwnerUserID =
                transactionOwnerMap[localTransaction.id]
                ?? TransactionAuditStore.resolveOwnerUserID(
                    forWalletID: localTransaction.sourceWallet?.id,
                    ownershipScopes: ownershipScopes
                )
                ?? ownerUserID(
                    forWalletID: localTransaction.destinationWallet?.id,
                    ownerMap: walletOwnerMap
                )
                ?? row.userID

            let localRecord = MistiaSyncUploadRecord.transaction(
                RemoteLedgerTransaction(
                    local: localTransaction,
                    userID: localOwnerUserID,
                    auditRecord: audits[localTransaction.id]
                )
            )
            let remoteRecord = MistiaSyncUploadRecord.transaction(row)

            if preserveLocalNewerRows,
               row.syncVersion > localTransaction.remoteVersion,
               localTransaction.updatedAt > row.updatedAt,
               localRecord.payloadFingerprint != remoteRecord.payloadFingerprint {
                try saveConflict(
                    entity: .transaction,
                    recordID: row.id,
                    kind: row.deletedAt == nil ? .editEdit : .editDelete,
                    localDraft: localRecord,
                    remoteRecord: remoteRecord,
                    baseVersion: localTransaction.remoteVersion,
                    remoteVersion: row.syncVersion,
                    in: context
                )
                if localTransaction.deletedAt != nil, row.deletedAt == nil {
                    continue
                }
            }

            try upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        }

    }

    static func saveConflict(
        entity: MistiaSyncEntity,
        recordID: UUID,
        kind: MistiaSyncConflictKind,
        localDraft: MistiaSyncUploadRecord,
        remoteRecord: MistiaSyncUploadRecord,
        baseVersion: Int64,
        remoteVersion: Int64,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        try saveConflict(
            entity: entity,
            recordID: recordID,
            kind: kind,
            localDraft: localDraft,
            remoteRecord: remoteRecord,
            baseVersion: baseVersion,
            remoteVersion: remoteVersion,
            in: context
        )
        try context.save()
    }

    private static func saveConflict(
        entity: MistiaSyncEntity,
        recordID: UUID,
        kind: MistiaSyncConflictKind,
        localDraft: MistiaSyncUploadRecord,
        remoteRecord: MistiaSyncUploadRecord,
        baseVersion: Int64,
        remoteVersion: Int64,
        in context: ModelContext
    ) throws {
        let existing = try fetchConflicts(context).first {
            $0.entityRawValue == entity.rawValue && $0.recordID == recordID
        }

        let localJSON = try localDraft.asJSONString()
        let remoteJSON = try remoteRecord.asJSONString()

        let conflict = existing ?? SyncConflict(
            entityRawValue: entity.rawValue,
            recordID: recordID,
            conflictKindRawValue: kind.rawValue,
            localPayloadJSON: localJSON,
            remotePayloadJSON: remoteJSON,
            baseVersion: baseVersion,
            remoteVersion: remoteVersion
        )

        if existing == nil {
            context.insert(conflict)
        }

        conflict.conflictKindRawValue = kind.rawValue
        conflict.localPayloadJSON = localJSON
        conflict.remotePayloadJSON = remoteJSON
        conflict.baseVersion = baseVersion
        conflict.remoteVersion = remoteVersion
        conflict.createdAt = .now
    }

    static func fetchConflict(
        id: UUID,
        from container: ModelContainer
    ) throws -> SyncConflict? {
        let context = ModelContext(container)
        return try fetchConflicts(context).first(where: { $0.id == id })
    }

    static func removeConflict(
        id: UUID,
        from container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        guard let conflict = try fetchConflicts(context).first(where: { $0.id == id }) else {
            return
        }
        context.delete(conflict)
        try context.save()
    }

    static func hasConflict(
        entity: MistiaSyncEntity,
        recordID: UUID,
        in container: ModelContainer
    ) throws -> Bool {
        let context = ModelContext(container)
        return try fetchConflicts(context).contains {
            $0.entityRawValue == entity.rawValue && $0.recordID == recordID
        }
    }

    static func possibleDuplicateTransactions(
        in container: ModelContainer
    ) throws -> [MistiaSyncPossibleDuplicate] {
        []
    }

    static func possibleDuplicateTransactions(
        from activeTransactions: [LedgerTransaction]
    ) -> [MistiaSyncPossibleDuplicate] {
        []
    }

    @MainActor
    static func clearAllData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearAllData(context: context)
    }

    @MainActor
    static func clearLocalDeviceLiveData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearLocalDeviceLiveData(context: context)
    }

    @MainActor
    static func clearLocalDeviceLiveData(context: ModelContext) throws {
        try clearAllData(context: context)
        try MistiaNotificationStore.clearAll(in: context)
    }

    @MainActor
    static func clearAllProfileData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearAllBackupRestorableData(context: context)
    }

    @MainActor
    static func exportBackupEnvelope(
        from container: ModelContainer,
        fallbackOwnerUserID: UUID,
        appVersion: String,
        appBuild: String
    ) throws -> MistiaBackupEnvelopeV1 {
        let context = ModelContext(container)
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let auditRecords = try fetchTransactionAudits(context)
        let auditMap = TransactionAuditStore.auditMap(from: auditRecords)

        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let profileOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .creditCardProfile)
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let settlementGroupOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementGroup)
        let settlementParticipantOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementParticipant)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
        let goalOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
        let recurringOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let installmentOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)

        let wallets = try fetchWallets(context).filter { $0.deletedAt == nil }
        let creditCardProfiles = try fetchCreditCardProfiles(context).filter { $0.deletedAt == nil }
        let categories = try fetchCategories(context).filter { $0.deletedAt == nil }
        let settlementGroups = try fetchSettlementGroups(context).filter { $0.deletedAt == nil }
        let settlementParticipants = try fetchSettlementParticipants(context).filter { $0.deletedAt == nil }
        let transactions = try fetchTransactions(context).filter { $0.deletedAt == nil }
        let budgetPlans = try fetchBudgetPlans(context).filter { $0.deletedAt == nil }
        let savingsGoals = try fetchSavingsGoals(context).filter { $0.deletedAt == nil }
        let recurringBillPlans = try fetchRecurringBillPlans(context).filter { $0.deletedAt == nil }
        let installmentPlans = try fetchInstallmentPlans(context).filter { $0.deletedAt == nil }
        let dueOccurrences = try fetchDueOccurrences(context).filter { $0.deletedAt == nil }
        let userProfiles = try context.fetch(FetchDescriptor<UserAccountProfile>())

        let snapshot = MistiaRemoteSnapshot(
            wallets: wallets.map { wallet in
                var row = RemoteLedgerWallet(
                    local: wallet,
                    userID: walletOwnerMap[wallet.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = wallet.remoteVersion
                return row
            },
            creditCardProfiles: creditCardProfiles.map { profile in
                var row = RemoteCreditCardProfile(
                    local: profile,
                    userID: profileOwnerMap[profile.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = profile.remoteVersion
                return row
            },
            categories: categories.map { category in
                var row = RemoteTransactionCategory(
                    local: category,
                    userID: categoryOwnerMap[category.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = category.remoteVersion
                return row
            },
            settlementGroups: settlementGroups.map { group in
                var row = RemoteSettlementGroup(
                    local: group,
                    userID: settlementGroupOwnerMap[group.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = group.remoteVersion
                return row
            },
            settlementParticipants: settlementParticipants.map { participant in
                var row = RemoteSettlementParticipant(
                    local: participant,
                    userID: settlementParticipantOwnerMap[participant.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = participant.remoteVersion
                return row
            },
            transactions: transactions.map { transaction in
                var row = RemoteLedgerTransaction(
                    local: transaction,
                    userID: transactionOwnerMap[transaction.id] ?? fallbackOwnerUserID,
                    auditRecord: auditMap[transaction.id]
                )
                row.syncVersion = transaction.remoteVersion
                return row
            },
            budgetPlans: budgetPlans.map { budget in
                var row = RemoteBudgetPlan(
                    local: budget,
                    userID: budgetOwnerMap[budget.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = budget.remoteVersion
                return row
            },
            savingsGoals: savingsGoals.map { goal in
                var row = RemoteSavingsGoal(
                    local: goal,
                    userID: goalOwnerMap[goal.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = goal.remoteVersion
                return row
            },
            recurringBillPlans: recurringBillPlans.map { recurring in
                var row = RemoteRecurringBillPlan(
                    local: recurring,
                    userID: recurringOwnerMap[recurring.id] ?? fallbackOwnerUserID,
                    categoryID: recurringBillCategoryID(
                        for: recurring,
                        userID: recurringOwnerMap[recurring.id] ?? fallbackOwnerUserID,
                        categories: categories
                    )
                )
                row.syncVersion = recurring.remoteVersion
                return row
            },
            installmentPlans: installmentPlans.map { installment in
                var row = RemoteInstallmentPlan(
                    local: installment,
                    userID: installmentOwnerMap[installment.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = installment.remoteVersion
                return row
            },
            dueOccurrences: dueOccurrences.map { occurrence in
                var row = RemoteDueOccurrenceRecord(
                    local: occurrence,
                    userID: occurrenceOwnerMap[occurrence.id] ?? fallbackOwnerUserID
                )
                row.syncVersion = occurrence.remoteVersion
                return row
            }
        )

        let activeIDsByEntity: [MistiaSyncEntity: Set<UUID>] = [
            .wallet: Set(snapshot.wallets.map(\.id)),
            .creditCardProfile: Set(snapshot.creditCardProfiles.map(\.id)),
            .category: Set(snapshot.categories.map(\.id)),
            .settlementGroup: Set(snapshot.settlementGroups.map(\.id)),
            .settlementParticipant: Set(snapshot.settlementParticipants.map(\.id)),
            .transaction: Set(snapshot.transactions.map(\.id)),
            .budgetPlan: Set(snapshot.budgetPlans.map(\.id)),
            .savingsGoal: Set(snapshot.savingsGoals.map(\.id)),
            .recurringBillPlan: Set(snapshot.recurringBillPlans.map(\.id)),
            .installmentPlan: Set(snapshot.installmentPlans.map(\.id)),
            .dueOccurrenceRecord: Set(snapshot.dueOccurrences.map(\.id))
        ]

        let filteredOwnershipScopes = ownershipScopes.filter { scope in
            activeIDsByEntity[scope.entity]?.contains(scope.recordID) == true
        }
        let activeTransactionIDs = Set(snapshot.transactions.map(\.id))
        let filteredTransactionAudits = auditRecords.filter {
            activeTransactionIDs.contains($0.transactionID)
        }
        let avatarAssets = try MistiaBackupAvatarStore.loadAssets(for: userProfiles)

        return MistiaBackupEnvelopeV1(
            manifest: MistiaBackupManifestV1(
                backupFormatVersion: 1,
                exportedAt: .now,
                appVersion: appVersion,
                appBuild: appBuild,
                localSchemaVersion: 1
            ),
            snapshot: snapshot,
            userProfiles: userProfiles.map { MistiaBackupUserAccountProfileV1($0) },
            ownershipScopes: filteredOwnershipScopes.map { scope in
                MistiaBackupOwnedRecordScopeV1(
                    id: scope.id,
                    entityRawValue: scope.entityRawValue,
                    recordID: scope.recordID,
                    ownerUserID: scope.ownerUserID,
                    updatedAt: scope.updatedAt
                )
            },
            transactionAudits: filteredTransactionAudits.map { record in
                MistiaBackupTransactionAuditRecordV1(
                    transactionID: record.transactionID,
                    createdByUserID: record.createdByUserID,
                    lastModifiedByUserID: record.lastModifiedByUserID,
                    updatedAt: record.updatedAt
                )
            },
            avatarAssets: avatarAssets
        )
    }

    @MainActor
    static func restoreBackupEnvelope(
        _ envelope: MistiaBackupEnvelopeV1,
        mode: MistiaBackupRestoreMode,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)

        if mode == .replaceLocal {
            try clearAllBackupRestorableData(context: context)
        } else {
            try clearBackupOperationalState(context: context)
        }

        try applySnapshotIncrementally(
            envelope.snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: container
        )

        try clearBackupOperationalState(context: context)
        try upsertBackupUserProfiles(envelope.userProfiles, context: context)
        try upsertBackupOwnershipScopes(envelope.ownershipScopes, context: context)
        try upsertBackupTransactionAudits(envelope.transactionAudits, context: context)
        try context.save()
    }

    @MainActor
    private static func clearAllData(context: ModelContext) throws {
        try TransactionReceiptImageStore().deleteAll(context: context, saveContext: false)

        for record in try fetchConflicts(context) {
            context.delete(record)
        }

        for scope in try context.fetch(FetchDescriptor<OwnedRecordScope>()) {
            context.delete(scope)
        }

        for record in try fetchTransactionAudits(context) {
            context.delete(record)
        }

        for record in try fetchDueOccurrences(context) {
            context.delete(record)
        }

        for record in try fetchInstallmentPlans(context) {
            context.delete(record)
        }

        for record in try fetchRecurringBillPlans(context) {
            context.delete(record)
        }

        for record in try fetchSavingsGoals(context) {
            context.delete(record)
        }

        for record in try fetchBudgetPlans(context) {
            context.delete(record)
        }

        for record in try fetchSettlementParticipants(context) {
            context.delete(record)
        }

        for record in try fetchSettlementGroups(context) {
            context.delete(record)
        }

        for record in try fetchTransactions(context) {
            context.delete(record)
        }

        for record in try fetchCreditCardProfiles(context) {
            context.delete(record)
        }

        for record in try fetchWallets(context) {
            context.delete(record)
        }

        for record in try fetchCategories(context) {
            context.delete(record)
        }

        try context.save()
    }

    @MainActor
    private static func clearAllBackupRestorableData(context: ModelContext) throws {
        try clearAllData(context: context)

        for profile in try context.fetch(FetchDescriptor<UserAccountProfile>()) {
            context.delete(profile)
        }

        try context.save()
    }

    @MainActor
    private static func clearBackupOperationalState(context: ModelContext) throws {
        for record in try fetchConflicts(context) {
            context.delete(record)
        }

        try context.save()
    }

    @MainActor
    private static func upsertBackupUserProfiles(
        _ rows: [MistiaBackupUserAccountProfileV1],
        context: ModelContext
    ) throws {
        let existingProfiles = try context.fetch(FetchDescriptor<UserAccountProfile>())
        var profilesByUserID = Dictionary(existingProfiles.map { ($0.userID, $0) }, uniquingKeysWith: latestProfile)

        for row in rows {
            let profile = profilesByUserID[row.userID] ?? UserAccountProfile(
                userID: row.userID,
                email: row.email,
                displayName: row.displayName
            )

            if profilesByUserID[row.userID] == nil {
                context.insert(profile)
                profilesByUserID[row.userID] = profile
            }

            profile.email = row.email
            profile.displayName = row.displayName
            profile.avatarFileName = row.avatarFileName
            profile.birthday = row.birthday
            profile.lastSyncAt = row.lastSyncAt
            profile.createdAt = row.createdAt
            profile.updatedAt = row.updatedAt
        }
    }

    @MainActor
    private static func upsertBackupOwnershipScopes(
        _ rows: [MistiaBackupOwnedRecordScopeV1],
        context: ModelContext
    ) throws {
        let existingScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        var scopesByID = Dictionary(existingScopes.map { ($0.id, $0) }, uniquingKeysWith: latestScope)

        for row in rows {
            let entity = MistiaSyncEntity(rawValue: row.entityRawValue) ?? .transaction
            let scope = scopesByID[row.id] ?? OwnedRecordScope(
                entity: entity,
                recordID: row.recordID,
                ownerUserID: row.ownerUserID,
                updatedAt: row.updatedAt
            )

            if scopesByID[row.id] == nil {
                context.insert(scope)
                scopesByID[row.id] = scope
            }

            scope.entityRawValue = row.entityRawValue
            scope.recordID = row.recordID
            scope.ownerUserID = row.ownerUserID
            scope.updatedAt = row.updatedAt
        }
    }

    @MainActor
    private static func upsertBackupTransactionAudits(
        _ rows: [MistiaBackupTransactionAuditRecordV1],
        context: ModelContext
    ) throws {
        let existingAudits = try fetchTransactionAudits(context)
        var auditsByTransactionID = Dictionary(
            existingAudits.map { ($0.transactionID, $0) },
            uniquingKeysWith: latestAudit
        )

        for row in rows {
            let audit = auditsByTransactionID[row.transactionID] ?? TransactionAuditRecord(
                transactionID: row.transactionID,
                createdByUserID: row.createdByUserID,
                lastModifiedByUserID: row.lastModifiedByUserID,
                updatedAt: row.updatedAt
            )

            if auditsByTransactionID[row.transactionID] == nil {
                context.insert(audit)
                auditsByTransactionID[row.transactionID] = audit
            }

            audit.createdByUserID = row.createdByUserID
            audit.lastModifiedByUserID = row.lastModifiedByUserID
            audit.updatedAt = row.updatedAt
        }
    }

    private static func pruneRecordsMissingFromRemote<Record: MistiaSyncLocalRecord>(
        existing: [Record],
        remoteIDs: Set<UUID>,
        protectedRecordIDs: Set<String>,
        context: ModelContext
    ) {
        for record in existing {
            guard !remoteIDs.contains(record.id) else { continue }
            let key = canonicalStorageKey(entity: Record.syncEntity, recordID: record.id)
            guard !protectedRecordIDs.contains(key) else { continue }
            context.delete(record)
        }
    }

    private static func shouldApplyRemoteRow<Row: MistiaRemoteRow, Record: MistiaSyncLocalRecord>(
        _ row: Row,
        entity: MistiaSyncEntity,
        existing record: Record?,
        protectedRecordIDs: Set<String>,
        preserveLocalNewerRows: Bool
    ) -> Bool {
        let storageKey = canonicalStorageKey(entity: entity, recordID: row.id)
        guard !protectedRecordIDs.contains(storageKey) else {
            return false
        }

        guard
            preserveLocalNewerRows,
            let record,
            record.deletedAt != nil,
            row.deletedAt == nil,
            record.updatedAt > row.updatedAt
        else {
            return true
        }

        return false
    }

    private static func upsertWallet(
        _ row: RemoteLedgerWallet,
        context: ModelContext,
        walletByID: inout [UUID: LedgerWallet]
    ) throws {
        let wallet = walletByID[row.id] ?? LedgerWallet(
            id: row.id,
            name: row.name,
            kind: LedgerWalletKind(rawValue: row.kindRawValue) ?? .cash,
            iconSymbolName: row.iconSymbolName,
            iconColorHex: row.iconColorHex,
            currencyCode: row.currencyCode,
            openingBalanceMinor: row.openingBalanceMinor,
            institutionDisplayName: row.institutionDisplayName,
            institutionPresetKey: row.institutionPresetKey,
            sortOrder: row.sortOrder,
            isArchived: row.isArchived,
            archivedAt: row.archivedAt,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if walletByID[row.id] == nil {
            context.insert(wallet)
            walletByID[row.id] = wallet
        }

        wallet.name = row.name
        wallet.kind = LedgerWalletKind(rawValue: row.kindRawValue) ?? .cash
        wallet.iconSymbolName = row.iconSymbolName
        wallet.iconColorHex = row.iconColorHex
        wallet.currencyCode = row.currencyCode
        wallet.openingBalanceMinor = row.openingBalanceMinor
        wallet.institutionDisplayName = row.institutionDisplayName
        wallet.institutionPresetKey = row.institutionPresetKey
        wallet.sortOrder = row.sortOrder
        wallet.isArchived = row.isArchived
        wallet.archivedAt = row.archivedAt
        wallet.createdAt = row.createdAt
        wallet.updatedAt = row.updatedAt
        wallet.deletedAt = row.deletedAt
        wallet.remoteVersion = row.syncVersion
        try MistiaRecordOwnershipStore.upsert(
            entity: .wallet,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertCategory(
        _ row: RemoteTransactionCategory,
        context: ModelContext,
        categoryByID: inout [UUID: TransactionCategory],
        preservesLocalSystemDefaults: Bool = true
    ) throws {
        let resolvedNames = resolvedCategoryNames(for: row)
        if preservesLocalSystemDefaults,
           let existing = categoryByID[row.id],
           shouldPreserveLocalActiveSystemCategory(existing, over: row) {
            return
        }

        let category = categoryByID[row.id] ?? TransactionCategory(
            id: row.id,
            name: resolvedNames.name,
            nameEnglish: resolvedNames.nameEnglish,
            nameJapanese: resolvedNames.nameJapanese,
            kind: TransactionCategoryKind(rawValue: row.kindRawValue) ?? .expense,
            iconSymbolName: row.iconSymbolName,
            iconColorHex: row.iconColorHex,
            isFavorite: row.isFavorite,
            familyBudgetSpendingEnabled: row.familyBudgetSpendingEnabled,
            hierarchyRole: row.hierarchyRoleRawValue.flatMap(TransactionCategoryHierarchyRole.init(rawValue:)),
            systemKey: row.systemKey,
            isSystem: row.isSystem,
            cloudSyncEnabled: true,
            sortOrder: row.sortOrder,
            isArchived: row.isArchived,
            archivedAt: row.archivedAt,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if categoryByID[row.id] == nil {
            context.insert(category)
            categoryByID[row.id] = category
        }

        category.name = resolvedNames.name
        category.nameEnglish = resolvedNames.nameEnglish
        category.nameJapanese = resolvedNames.nameJapanese
        category.kind = TransactionCategoryKind(rawValue: row.kindRawValue) ?? .expense
        category.iconSymbolName = row.iconSymbolName
        category.iconColorHex = row.iconColorHex
        category.isFavorite = row.isFavorite
        category.familyBudgetSpendingEnabled = row.familyBudgetSpendingEnabled
        category.hierarchyRoleRawValue = row.hierarchyRoleRawValue
        category.systemKey = row.systemKey
        category.isSystem = row.isSystem
        category.cloudSyncEnabled = true
        category.sortOrder = row.sortOrder
        category.isArchived = row.isArchived
        category.archivedAt = row.archivedAt
        category.createdAt = row.createdAt
        category.updatedAt = row.updatedAt
        category.deletedAt = row.deletedAt
        category.remoteVersion = row.syncVersion

        try MistiaRecordOwnershipStore.upsert(
            entity: .category,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func resolvedCategoryNames(
        for row: RemoteTransactionCategory
    ) -> (name: String, nameEnglish: String?, nameJapanese: String?) {
        let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawSystemKey = row.systemKey,
           let parsed = MistiaSystemCategoryRegistry.shared.category(for: rawSystemKey),
           Set(parsed.knownDefaultNames()).contains(trimmedName) {
            let vi = parsed.translations["vi"] ?? rawSystemKey
            let en = parsed.translations["en"] ?? vi
            let ja = parsed.translations["ja"] ?? vi
            return (
                vi,
                nonBlank(row.nameEnglish) ?? en,
                nonBlank(row.nameJapanese) ?? ja
            )
        }

        return (row.name, row.nameEnglish, row.nameJapanese)
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func scopedCategoryRows(
        _ rows: [RemoteTransactionCategory],
        categoryIDMap: [UUID: UUID]
    ) -> [RemoteTransactionCategory] {
        rows.map { row in
            var scopedRow = row
            scopedRow.id = categoryIDMap[row.id] ?? row.id
            scopedRow.parentCategoryID = row.parentCategoryID.flatMap { categoryIDMap[$0] ?? $0 }
            return scopedRow
        }
    }

    private static func scopedTransactionRows(
        _ rows: [RemoteLedgerTransaction],
        categoryIDMap: [UUID: UUID],
        localUserID: UUID?
    ) -> [RemoteLedgerTransaction] {
        rows.map { row in
            var scopedRow = row
            scopedRow.categoryID = scopedCategoryID(
                row.categoryID,
                ownerUserID: row.userID,
                categoryIDMap: categoryIDMap,
                localUserID: localUserID
            )
            return scopedRow
        }
    }

    private static func scopedBudgetRows(
        _ rows: [RemoteBudgetPlan],
        categoryIDMap: [UUID: UUID],
        localUserID: UUID?
    ) -> [RemoteBudgetPlan] {
        rows.map { row in
            var scopedRow = row
            scopedRow.categoryID = scopedCategoryID(
                row.categoryID,
                ownerUserID: row.userID,
                categoryIDMap: categoryIDMap,
                localUserID: localUserID
            )
            return scopedRow
        }
    }

    private static func scopedRecurringBillRows(
        _ rows: [RemoteRecurringBillPlan],
        categoryIDMap: [UUID: UUID],
        localUserID: UUID?
    ) -> [RemoteRecurringBillPlan] {
        rows.map { row in
            var scopedRow = row
            scopedRow.categoryID = scopedCategoryID(
                row.categoryID,
                ownerUserID: row.userID,
                categoryIDMap: categoryIDMap,
                localUserID: localUserID
            )
            return scopedRow
        }
    }

    private static func scopedCategoryIDMap(
        _ rows: [RemoteTransactionCategory],
        localUserID: UUID?
    ) -> [UUID: UUID] {
        Dictionary(rows.map { row in
            let localID: UUID
            if (localUserID == nil || row.userID == localUserID),
               row.isSystem,
               let systemKey = row.systemKey {
                localID = MistiaSystemCategoryIdentity.canonicalID(for: systemKey)
            } else {
                localID = row.id
            }
            return (row.id, localID)
        }, uniquingKeysWith: { _, latest in latest })
    }

    private static func remoteCategoryIDMap(
        categories: [TransactionCategory],
        ownerMap: [UUID: UUID]
    ) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for category in categories {
            mapping[category.id] = category.id
            let ownerUserID = ownerMap[category.id]
            if category.isSystem,
               let systemKey = category.systemKey,
               let ownerUserID {
                let remoteID = MistiaSystemCategoryIdentity.cloudScopedID(
                    canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
                    ownerUserID: ownerUserID
                )
                mapping[remoteID] = category.id
            }
        }
        return mapping
    }

    private static func scopedCategoryID(
        _ remoteCategoryID: UUID?,
        ownerUserID: UUID,
        categoryIDMap: [UUID: UUID],
        localUserID: UUID?
    ) -> UUID? {
        guard let remoteCategoryID else { return nil }
        if let mappedID = categoryIDMap[remoteCategoryID] {
            return mappedID
        }
        return remoteCategoryID
    }

    private static func shouldPreserveLocalActiveSystemCategory(
        _ category: TransactionCategory,
        over row: RemoteTransactionCategory
    ) -> Bool {
        guard category.isSystem || row.isSystem else { return false }
        guard category.deletedAt == nil else { return false }
        guard let rawSystemKey = category.systemKey ?? row.systemKey,
              category.id == MistiaSystemCategoryIdentity.canonicalID(for: rawSystemKey) else {
            return false
        }
        if row.deletedAt != nil,
           isActiveSystemDefaultCategory(rawSystemKey: rawSystemKey) {
            return true
        }
        guard category.updatedAt > row.updatedAt else { return false }
        return isActiveSystemDefaultCategory(rawSystemKey: rawSystemKey)
    }

    private static func pruneStaleFamilyScopedCategories(
        ownerUserIDs: Set<UUID>,
        keepCategoryIDs: Set<UUID>,
        localUserID: UUID,
        context: ModelContext,
        categoryByID: inout [UUID: TransactionCategory]
    ) throws {
        let scopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .category)
        let now = Date()

        let categories = Array(categoryByID.values)
        let replacementByID = familyScopedCategoryReplacementMap(
            categories: categories,
            ownerMap: ownerMap,
            ownerUserIDs: ownerUserIDs,
            keepCategoryIDs: keepCategoryIDs,
            localUserID: localUserID
        )

        if !replacementByID.isEmpty {
            let transactions = try fetchTransactions(context)
            let budgets = try fetchBudgetPlans(context)
            let recurringBills = try fetchRecurringBillPlans(context)
            repointFamilyScopedCategoryReferences(
                replacementByID: replacementByID,
                categoryByID: categoryByID,
                ownerUserIDs: ownerUserIDs,
                transactionOwnerMap: MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .transaction),
                budgetOwnerMap: MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .budgetPlan),
                recurringOwnerMap: MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .recurringBillPlan),
                categoryOwnerMap: ownerMap,
                transactions: transactions,
                budgets: budgets,
                recurringBills: recurringBills,
                categories: categories,
                now: now
            )
        }

        let outbox = MistiaSyncOutbox()
        for category in categories {
            guard category.deletedAt == nil,
                  !keepCategoryIDs.contains(category.id),
                  let ownerUserID = ownerMap[category.id],
                  ownerUserID != localUserID,
                  ownerUserIDs.contains(ownerUserID) else {
                continue
            }

            if isCanonicalSystemCategory(category) {
                for scope in scopes where scope.entity == .category
                    && scope.recordID == category.id
                    && ownerUserIDs.contains(scope.ownerUserID) {
                    context.delete(scope)
                }
                outbox.remove(entity: .category, recordID: category.id)
                continue
            }

            category.deletedAt = now
            category.updatedAt = now
            category.cloudSyncEnabled = false
            outbox.remove(entity: .category, recordID: category.id)
        }
    }

    private static func familyScopedCategoryReplacementMap(
        categories: [TransactionCategory],
        ownerMap: [UUID: UUID],
        ownerUserIDs: Set<UUID>,
        keepCategoryIDs: Set<UUID>,
        localUserID: UUID
    ) -> [UUID: UUID] {
        var keptByOwnerSystemKey: [FamilyScopedSystemCategoryKey: UUID] = [:]

        for category in categories {
            guard keepCategoryIDs.contains(category.id),
                  category.isSystem,
                  let systemKey = category.systemKey,
                  let ownerUserID = ownerMap[category.id],
                  ownerUserID != localUserID,
                  ownerUserIDs.contains(ownerUserID) else {
                continue
            }
            keptByOwnerSystemKey[FamilyScopedSystemCategoryKey(ownerUserID: ownerUserID, systemKey: systemKey)] = category.id
        }

        var replacements: [UUID: UUID] = [:]
        for category in categories {
            guard !keepCategoryIDs.contains(category.id),
                  category.isSystem,
                  let systemKey = category.systemKey,
                  let ownerUserID = ownerMap[category.id],
                  ownerUserID != localUserID,
                  ownerUserIDs.contains(ownerUserID),
                  let replacementID = keptByOwnerSystemKey[
                      FamilyScopedSystemCategoryKey(ownerUserID: ownerUserID, systemKey: systemKey)
                  ],
                  replacementID != category.id else {
                continue
            }
            replacements[category.id] = replacementID
        }
        return replacements
    }

    private static func repointFamilyScopedCategoryReferences(
        replacementByID: [UUID: UUID],
        categoryByID: [UUID: TransactionCategory],
        ownerUserIDs: Set<UUID>,
        transactionOwnerMap: [UUID: UUID],
        budgetOwnerMap: [UUID: UUID],
        recurringOwnerMap: [UUID: UUID],
        categoryOwnerMap: [UUID: UUID],
        transactions: [LedgerTransaction],
        budgets: [BudgetPlan],
        recurringBills: [RecurringBillPlan],
        categories: [TransactionCategory],
        now: Date
    ) {
        for transaction in transactions {
            guard let categoryID = transaction.category?.id,
                  transactionOwnerMap[transaction.id].map(ownerUserIDs.contains) == true,
                  let replacementID = replacementByID[categoryID],
                  let replacement = categoryByID[replacementID] else {
                continue
            }
            transaction.category = replacement
            transaction.updatedAt = max(transaction.updatedAt, now)
        }

        for budget in budgets {
            guard let categoryID = budget.category?.id,
                  budgetOwnerMap[budget.id].map(ownerUserIDs.contains) == true,
                  let replacementID = replacementByID[categoryID],
                  let replacement = categoryByID[replacementID] else {
                continue
            }
            budget.category = replacement
            budget.updatedAt = max(budget.updatedAt, now)
        }

        for recurringBill in recurringBills {
            guard let categoryID = recurringBill.category?.id,
                  recurringOwnerMap[recurringBill.id].map(ownerUserIDs.contains) == true,
                  let replacementID = replacementByID[categoryID],
                  let replacement = categoryByID[replacementID] else {
                continue
            }
            recurringBill.category = replacement
            recurringBill.updatedAt = max(recurringBill.updatedAt, now)
        }

        for category in categories {
            guard let parentID = category.parentCategory?.id,
                  categoryOwnerMap[category.id].map(ownerUserIDs.contains) == true,
                  let replacementID = replacementByID[parentID],
                  let replacement = categoryByID[replacementID] else {
                continue
            }
            category.parentCategory = replacement
            category.updatedAt = max(category.updatedAt, now)
        }
    }

    private static func isCanonicalSystemCategory(_ category: TransactionCategory) -> Bool {
        guard category.isSystem, let systemKey = category.systemKey else { return false }
        return category.id == MistiaSystemCategoryIdentity.canonicalID(for: systemKey)
    }

    private static func isActiveSystemDefaultCategory(rawSystemKey: String?) -> Bool {
        guard let descriptor = MistiaSystemCategoryIdentity.descriptor(for: rawSystemKey) else {
            return false
        }
        return descriptor.sortOrder != nil && !descriptor.startsArchived
    }

    private static func applyCategoryHierarchy(
        _ row: RemoteTransactionCategory,
        categoryByID: [UUID: TransactionCategory]
    ) {
        guard let category = categoryByID[row.id] else { return }
        category.parentCategory = row.parentCategoryID.flatMap { categoryByID[$0] }
    }

    private static func upsertCreditProfile(
        _ row: RemoteCreditCardProfile,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        profileByID: inout [UUID: CreditCardProfile]
    ) throws {
        let profile = profileByID[row.id] ?? CreditCardProfile(
            id: row.id,
            issuerName: row.issuerName,
            network: CreditCardNetwork(rawValue: row.networkRawValue) ?? .visa,
            last4: row.last4,
            creditLimitMinor: row.creditLimitMinor,
            statementClosingDay: row.statementClosingDay,
            paymentDueDay: row.paymentDueDay,
            notes: row.notes,
            autoPayEnabled: row.autoPayEnabled,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if profileByID[row.id] == nil {
            context.insert(profile)
            profileByID[row.id] = profile
        }

        profile.issuerName = row.issuerName
        profile.network = CreditCardNetwork(rawValue: row.networkRawValue) ?? .visa
        profile.last4 = row.last4
        profile.creditLimitMinor = row.creditLimitMinor
        profile.statementClosingDay = row.statementClosingDay
        profile.paymentDueDay = row.paymentDueDay
        profile.notes = row.notes
        profile.autoPayEnabled = row.autoPayEnabled
        profile.createdAt = row.createdAt
        profile.updatedAt = row.updatedAt
        profile.deletedAt = row.deletedAt
        profile.remoteVersion = row.syncVersion
        profile.wallet = row.walletID.flatMap { walletByID[$0] }
        profile.paymentSourceWallet = row.paymentSourceWalletID.flatMap { walletByID[$0] }
        profile.wallet?.creditCardProfile = profile
        try MistiaRecordOwnershipStore.upsert(
            entity: .creditCardProfile,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertTransaction(
        _ row: RemoteLedgerTransaction,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        categoryByID: [UUID: TransactionCategory],
        transactionByID: inout [UUID: LedgerTransaction]
    ) throws {
        let transaction = transactionByID[row.id] ?? LedgerTransaction(
            id: row.id,
            primaryKind: TransactionPrimaryKind(rawValue: row.primaryKindRawValue) ?? .expense,
            transferSubtype: row.transferSubtypeRawValue.flatMap(TransactionTransferSubtype.init(rawValue:)),
            debtIntent: row.debtIntentRawValue.flatMap(TransactionDebtIntent.init(rawValue:)),
            entryStatus: TransactionEntryStatus(rawValue: row.entryStatusRawValue) ?? .posted,
            title: row.title,
            note: row.note,
            amountMinor: row.amountMinor,
            settlementGroupID: row.settlementGroupID,
            settlementObligationID: row.settlementObligationID,
            settlementRole: row.settlementRoleRawValue.flatMap(SettlementTransactionRole.init(rawValue:)),
            reportingExpenseMinor: row.reportingExpenseMinor,
            reportingIncomeMinor: row.reportingIncomeMinor,
            sourceCurrencyCode: row.sourceCurrencyCode,
            destinationCurrencyCode: row.destinationCurrencyCode,
            destinationAmountMinor: row.destinationAmountMinor,
            reportingCurrencyCode: row.reportingCurrencyCode,
            reportingAmountMinor: row.reportingAmountMinor,
            conversionModeRawValue: row.conversionModeRawValue,
            exchangeRateDecimalString: row.exchangeRateDecimalString,
            exchangeRateProvider: row.exchangeRateProvider,
            exchangeRateDate: row.exchangeRateDate,
            occurredAt: row.occurredAt,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion,
            sourceWallet: row.sourceWalletID.flatMap { walletByID[$0] },
            destinationWallet: row.destinationWalletID.flatMap { walletByID[$0] },
            category: row.categoryID.flatMap { categoryByID[$0] },
            counterpartyName: row.counterpartyName,
            normalizedCounterpartyKey: row.normalizedCounterpartyKey,
            isArchived: row.isArchived,
            archivedAt: row.archivedAt
        )

        if transactionByID[row.id] == nil {
            context.insert(transaction)
            transactionByID[row.id] = transaction
        }

        transaction.primaryKind = TransactionPrimaryKind(rawValue: row.primaryKindRawValue) ?? .expense
        transaction.transferSubtype = row.transferSubtypeRawValue.flatMap(TransactionTransferSubtype.init(rawValue:))
        transaction.debtIntent = row.debtIntentRawValue.flatMap(TransactionDebtIntent.init(rawValue:))
        transaction.entryStatus = TransactionEntryStatus(rawValue: row.entryStatusRawValue) ?? .posted
        transaction.title = row.title
        transaction.note = row.note
        transaction.amountMinor = row.amountMinor
        transaction.sourceCurrencyCode = row.sourceCurrencyCode
        transaction.destinationCurrencyCode = row.destinationCurrencyCode
        transaction.destinationAmountMinor = row.destinationAmountMinor
        transaction.reportingCurrencyCode = row.reportingCurrencyCode
        transaction.reportingAmountMinor = row.reportingAmountMinor
        transaction.conversionModeRawValue = row.conversionModeRawValue
        transaction.exchangeRateDecimalString = row.exchangeRateDecimalString
        transaction.exchangeRateProvider = row.exchangeRateProvider
        transaction.exchangeRateDate = row.exchangeRateDate
        transaction.occurredAt = row.occurredAt
        transaction.createdAt = row.createdAt
        transaction.updatedAt = row.updatedAt
        transaction.deletedAt = row.deletedAt
        transaction.remoteVersion = row.syncVersion
        transaction.counterpartyName = row.counterpartyName
        transaction.normalizedCounterpartyKey = row.normalizedCounterpartyKey
        transaction.settlementGroupID = row.settlementGroupID
        transaction.settlementObligationID = row.settlementObligationID
        transaction.settlementRoleRawValue = row.settlementRoleRawValue
        transaction.reportingExpenseMinor = row.reportingExpenseMinor
        transaction.reportingIncomeMinor = row.reportingIncomeMinor
        transaction.sourceWallet = row.sourceWalletID.flatMap { walletByID[$0] }
        transaction.destinationWallet = row.destinationWalletID.flatMap { walletByID[$0] }
        transaction.category = row.categoryID.flatMap { categoryByID[$0] }
        transaction.isArchived = row.isArchived
        transaction.archivedAt = row.archivedAt
        try MistiaRecordOwnershipStore.upsert(
            entity: .transaction,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
        try TransactionAuditStore.upsert(
            transactionID: row.id,
            createdByUserID: row.createdByUserID,
            lastModifiedByUserID: row.lastModifiedByUserID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertSettlementGroup(
        _ row: RemoteSettlementGroup,
        context: ModelContext,
        groupByID: inout [UUID: SettlementGroup]
    ) throws {
        let group = groupByID[row.id] ?? SettlementGroup(
            id: row.id,
            kind: SettlementKind(rawValue: row.kindRawValue) ?? .sharedExpense,
            status: SettlementStatus(rawValue: row.statusRawValue) ?? .open,
            title: row.title,
            currencyCode: row.currencyCode,
            occurredAt: row.occurredAt,
            totalMinor: row.totalMinor,
            expectedMinor: row.expectedMinor,
            settledMinor: row.settledMinor,
            organizerUserID: row.organizerUserID,
            note: row.note,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion,
            isArchived: row.isArchived,
            archivedAt: row.archivedAt
        )

        if groupByID[row.id] == nil {
            context.insert(group)
            groupByID[row.id] = group
        }

        group.kindRawValue = row.kindRawValue
        group.statusRawValue = row.statusRawValue
        group.title = row.title
        group.currencyCode = row.currencyCode
        group.occurredAt = row.occurredAt
        group.totalMinor = row.totalMinor
        group.expectedMinor = row.expectedMinor
        group.settledMinor = row.settledMinor
        group.organizerUserID = row.organizerUserID
        group.note = row.note
        group.createdAt = row.createdAt
        group.updatedAt = row.updatedAt
        group.deletedAt = row.deletedAt
        group.remoteVersion = row.syncVersion
        group.isArchived = row.isArchived
        group.archivedAt = row.archivedAt

        try MistiaRecordOwnershipStore.upsert(
            entity: .settlementGroup,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertSettlementParticipant(
        _ row: RemoteSettlementParticipant,
        context: ModelContext,
        participantByID: inout [UUID: SettlementParticipant]
    ) throws {
        let participant = participantByID[row.id] ?? SettlementParticipant(
            id: row.id,
            groupID: row.groupID,
            displayName: row.displayName,
            normalizedKey: row.normalizedKey,
            memberUserID: row.memberUserID,
            isSelf: row.isSelf,
            sortOrder: row.sortOrder,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if participantByID[row.id] == nil {
            context.insert(participant)
            participantByID[row.id] = participant
        }

        participant.groupID = row.groupID
        participant.displayName = row.displayName
        participant.normalizedKey = row.normalizedKey
        participant.memberUserID = row.memberUserID
        participant.isSelf = row.isSelf
        participant.sortOrder = row.sortOrder
        participant.createdAt = row.createdAt
        participant.updatedAt = row.updatedAt
        participant.deletedAt = row.deletedAt
        participant.remoteVersion = row.syncVersion

        try MistiaRecordOwnershipStore.upsert(
            entity: .settlementParticipant,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertBudget(
        _ row: RemoteBudgetPlan,
        context: ModelContext,
        categoryByID: [UUID: TransactionCategory],
        budgetByID: inout [UUID: BudgetPlan]
    ) throws {
        let budget = budgetByID[row.id] ?? BudgetPlan(
            id: row.id,
            category: row.categoryID.flatMap { categoryByID[$0] },
            categoryIDSnapshot: row.categoryIDSnapshot,
            categoryNameSnapshot: row.categoryNameSnapshot,
            categoryNameEnglishSnapshot: row.categoryNameEnglishSnapshot,
            categoryNameJapaneseSnapshot: row.categoryNameJapaneseSnapshot,
            categoryPathSnapshot: row.categoryPathSnapshot,
            categoryPathEnglishSnapshot: row.categoryPathEnglishSnapshot,
            categoryPathJapaneseSnapshot: row.categoryPathJapaneseSnapshot,
            categoryIconSymbolNameSnapshot: row.categoryIconSymbolNameSnapshot,
            categoryColorHexSnapshot: row.categoryColorHexSnapshot,
            categoryParentIDSnapshot: row.categoryParentIDSnapshot,
            categoryParentNameSnapshot: row.categoryParentNameSnapshot,
            categoryParentNameEnglishSnapshot: row.categoryParentNameEnglishSnapshot,
            categoryParentNameJapaneseSnapshot: row.categoryParentNameJapaneseSnapshot,
            categoryParentIconSymbolNameSnapshot: row.categoryParentIconSymbolNameSnapshot,
            categoryParentColorHexSnapshot: row.categoryParentColorHexSnapshot,
            categoryHierarchyRoleSnapshotRawValue: row.categoryHierarchyRoleSnapshotRawValue,
            categoryIsParentSnapshotRawValue: row.categoryIsParentSnapshot,
            includesFamilySpending: row.includesFamilySpending,
            monthAnchor: row.monthAnchor,
            limitMinor: row.limitMinor,
            rolloverEnabled: row.rolloverEnabled,
            currencyCode: row.currencyCode,
            isArchived: row.isArchived,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if budgetByID[row.id] == nil {
            context.insert(budget)
            budgetByID[row.id] = budget
        }

        budget.category = row.categoryID.flatMap { categoryByID[$0] }
        budget.categoryIDSnapshot = row.categoryIDSnapshot
        budget.categoryNameSnapshot = row.categoryNameSnapshot
        budget.categoryNameEnglishSnapshot = row.categoryNameEnglishSnapshot
        budget.categoryNameJapaneseSnapshot = row.categoryNameJapaneseSnapshot
        budget.categoryPathSnapshot = row.categoryPathSnapshot
        budget.categoryPathEnglishSnapshot = row.categoryPathEnglishSnapshot
        budget.categoryPathJapaneseSnapshot = row.categoryPathJapaneseSnapshot
        budget.categoryIconSymbolNameSnapshot = row.categoryIconSymbolNameSnapshot
        budget.categoryColorHexSnapshot = row.categoryColorHexSnapshot
        budget.categoryParentIDSnapshot = row.categoryParentIDSnapshot
        budget.categoryParentNameSnapshot = row.categoryParentNameSnapshot
        budget.categoryParentNameEnglishSnapshot = row.categoryParentNameEnglishSnapshot
        budget.categoryParentNameJapaneseSnapshot = row.categoryParentNameJapaneseSnapshot
        budget.categoryParentIconSymbolNameSnapshot = row.categoryParentIconSymbolNameSnapshot
        budget.categoryParentColorHexSnapshot = row.categoryParentColorHexSnapshot
        budget.categoryHierarchyRoleSnapshotRawValue = row.categoryHierarchyRoleSnapshotRawValue
        budget.categoryIsParentSnapshotRawValue = row.categoryIsParentSnapshot
        budget.includesFamilySpending = row.includesFamilySpending
        budget.monthAnchor = row.monthAnchor
        budget.limitMinor = row.limitMinor
        budget.rolloverEnabled = row.rolloverEnabled
        budget.currencyCode = row.currencyCode
        budget.isArchived = row.isArchived
        budget.createdAt = row.createdAt
        budget.updatedAt = row.updatedAt
        budget.deletedAt = row.deletedAt
        budget.remoteVersion = row.syncVersion
        try MistiaRecordOwnershipStore.upsert(
            entity: .budgetPlan,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertGoal(
        _ row: RemoteSavingsGoal,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        goalByID: inout [UUID: SavingsGoal]
    ) throws {
        let goal = goalByID[row.id] ?? SavingsGoal(
            id: row.id,
            name: row.name,
            iconSymbolName: row.iconSymbolName,
            targetMinor: row.targetMinor,
            currentSavedMinor: row.currentSavedMinor,
            targetDate: row.targetDate,
            linkedWallet: row.linkedWalletID.flatMap { walletByID[$0] },
            currencyCode: row.currencyCode,
            sortOrder: row.sortOrder,
            isArchived: row.isArchived,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if goalByID[row.id] == nil {
            context.insert(goal)
            goalByID[row.id] = goal
        }

        goal.name = row.name
        goal.iconSymbolName = row.iconSymbolName
        goal.targetMinor = row.targetMinor
        goal.currentSavedMinor = row.currentSavedMinor
        goal.targetDate = row.targetDate
        goal.linkedWallet = row.linkedWalletID.flatMap { walletByID[$0] }
        goal.currencyCode = row.currencyCode
        goal.sortOrder = row.sortOrder
        goal.isArchived = row.isArchived
        goal.createdAt = row.createdAt
        goal.updatedAt = row.updatedAt
        goal.deletedAt = row.deletedAt
        goal.remoteVersion = row.syncVersion
        try MistiaRecordOwnershipStore.upsert(
            entity: .savingsGoal,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertRecurringBill(
        _ row: RemoteRecurringBillPlan,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        categoryByID: [UUID: TransactionCategory],
        recurringByID: inout [UUID: RecurringBillPlan]
    ) throws {
        let resolvedCategory = row.categoryID.flatMap { categoryByID[$0] }
        let normalizedIconSymbolName = resolvedCategory?.iconSymbolName ?? row.iconSymbolName
        let scheduleKind = PlanningBillScheduleKind(rawValue: row.scheduleKindRawValue ?? "") ?? .recurring
        let paymentStartDate = scheduleKind == .oneTime ? row.paymentStartDate : nil
        let autoPayDate = scheduleKind == .oneTime ? row.autoPayDate : nil
        let plan = recurringByID[row.id] ?? RecurringBillPlan(
            id: row.id,
            name: row.name,
            iconSymbolName: normalizedIconSymbolName,
            category: resolvedCategory,
            amountMinor: row.amountMinor,
            dueDay: row.dueDay,
            scheduleKind: scheduleKind,
            paymentStartDay: row.paymentStartDay,
            paymentStartDate: paymentStartDate,
            firstScheduledMonth: row.firstScheduledMonth,
            hasExplicitDueDate: row.hasExplicitDueDate,
            dueDate: row.dueDate,
            autoPayEnabled: row.autoPayEnabled ?? false,
            autoPayDay: row.autoPayDay,
            autoPayDate: autoPayDate,
            frequencyMonths: row.frequencyMonths,
            paymentWallet: row.paymentWalletID.flatMap { walletByID[$0] },
            currencyCode: row.currencyCode,
            isArchived: row.isArchived,
            isPaused: row.isPaused,
            pausedAt: row.pausedAt,
            resumeStartMonth: row.resumeStartMonth,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if recurringByID[row.id] == nil {
            context.insert(plan)
            recurringByID[row.id] = plan
        }

        plan.name = row.name
        plan.iconSymbolName = normalizedIconSymbolName
        plan.category = resolvedCategory
        plan.amountMinor = row.amountMinor
        plan.dueDay = row.dueDay
        plan.scheduleKind = scheduleKind
        plan.paymentStartDay = row.paymentStartDay ?? row.dueDay
        plan.paymentStartDate = paymentStartDate
        plan.firstScheduledMonth = row.firstScheduledMonth
        plan.hasExplicitDueDate = row.hasExplicitDueDate ?? false
        plan.dueDate = row.dueDate
        plan.autoPayEnabled = row.autoPayEnabled ?? false
        plan.autoPayDay = row.autoPayDay
        plan.autoPayDate = autoPayDate
        plan.frequencyMonths = row.frequencyMonths
        plan.paymentWallet = row.paymentWalletID.flatMap { walletByID[$0] }
        plan.currencyCode = row.currencyCode
        plan.isArchived = row.isArchived
        plan.isPaused = row.isPaused
        plan.pausedAt = row.pausedAt
        plan.resumeStartMonth = row.resumeStartMonth
        plan.createdAt = row.createdAt
        plan.updatedAt = row.updatedAt
        plan.deletedAt = row.deletedAt
        plan.remoteVersion = row.syncVersion
        try MistiaRecordOwnershipStore.upsert(
            entity: .recurringBillPlan,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertInstallment(
        _ row: RemoteInstallmentPlan,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        installmentByID: inout [UUID: InstallmentPlan]
    ) throws {
        let plan = installmentByID[row.id] ?? InstallmentPlan(
            id: row.id,
            name: row.name,
            iconSymbolName: row.iconSymbolName,
            amountPerCycleMinor: row.amountPerCycleMinor,
            dueDay: row.dueDay,
            totalCycles: row.totalCycles,
            frequencyMonths: row.frequencyMonths,
            paymentWallet: row.paymentWalletID.flatMap { walletByID[$0] },
            currencyCode: row.currencyCode,
            isArchived: row.isArchived,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if installmentByID[row.id] == nil {
            context.insert(plan)
            installmentByID[row.id] = plan
        }

        plan.name = row.name
        plan.iconSymbolName = row.iconSymbolName
        plan.amountPerCycleMinor = row.amountPerCycleMinor
        plan.dueDay = row.dueDay
        plan.totalCycles = row.totalCycles
        plan.frequencyMonths = row.frequencyMonths
        plan.paymentWallet = row.paymentWalletID.flatMap { walletByID[$0] }
        plan.currencyCode = row.currencyCode
        plan.isArchived = row.isArchived
        plan.createdAt = row.createdAt
        plan.updatedAt = row.updatedAt
        plan.deletedAt = row.deletedAt
        plan.remoteVersion = row.syncVersion
        try MistiaRecordOwnershipStore.upsert(
            entity: .installmentPlan,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func upsertDueOccurrence(
        _ row: RemoteDueOccurrenceRecord,
        context: ModelContext,
        occurrenceByID: inout [UUID: DueOccurrenceRecord]
    ) throws {
        let record = occurrenceByID[row.id] ?? DueOccurrenceRecord(
            id: row.id,
            sourceKind: PlanningDueSourceKind(rawValue: row.sourceKindRawValue) ?? .creditCard,
            sourceID: row.sourceID,
            selectedMonthKey: row.selectedMonthKey,
            scheduledDate: row.scheduledDate,
            amountMinorSnapshot: row.amountMinorSnapshot,
            status: PlanningDueOccurrenceStatus(rawValue: row.statusRawValue) ?? .pending,
            paidAt: row.paidAt,
            linkedTransactionID: row.linkedTransactionID,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            remoteVersion: row.syncVersion
        )

        if occurrenceByID[row.id] == nil {
            context.insert(record)
            occurrenceByID[row.id] = record
        }

        record.sourceKind = PlanningDueSourceKind(rawValue: row.sourceKindRawValue) ?? .creditCard
        record.sourceID = row.sourceID
        record.selectedMonthKey = row.selectedMonthKey
        record.scheduledDate = row.scheduledDate
        record.amountMinorSnapshot = row.amountMinorSnapshot
        record.status = PlanningDueOccurrenceStatus(rawValue: row.statusRawValue) ?? .pending
        record.paidAt = row.paidAt
        record.linkedTransactionID = row.linkedTransactionID
        record.createdAt = row.createdAt
        record.updatedAt = row.updatedAt
        record.deletedAt = row.deletedAt
        record.remoteVersion = row.syncVersion
        try MistiaRecordOwnershipStore.upsert(
            entity: .dueOccurrenceRecord,
            recordID: row.id,
            ownerUserID: row.userID,
            updatedAt: row.updatedAt,
            context: context
        )
    }

    private static func fetchFirst<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        context: ModelContext
    ) throws -> Model? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchWallet(id: UUID, _ context: ModelContext) throws -> LedgerWallet? {
        try fetchFirst(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in
                    wallet.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveWallet(_ context: ModelContext) throws -> LedgerWallet? {
        try fetchFirst(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in
                    wallet.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchWallets(_ context: ModelContext) throws -> [LedgerWallet] {
        try context.fetch(FetchDescriptor<LedgerWallet>())
    }

    private static func fetchCreditCardProfile(id: UUID, _ context: ModelContext) throws -> CreditCardProfile? {
        try fetchFirst(
            FetchDescriptor<CreditCardProfile>(
                predicate: #Predicate<CreditCardProfile> { profile in
                    profile.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveCreditCardProfile(_ context: ModelContext) throws -> CreditCardProfile? {
        try fetchFirst(
            FetchDescriptor<CreditCardProfile>(
                predicate: #Predicate<CreditCardProfile> { profile in
                    profile.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchCreditCardProfiles(_ context: ModelContext) throws -> [CreditCardProfile] {
        try context.fetch(FetchDescriptor<CreditCardProfile>())
    }

    private static func fetchCategory(id: UUID, _ context: ModelContext) throws -> TransactionCategory? {
        try fetchFirst(
            FetchDescriptor<TransactionCategory>(
                predicate: #Predicate<TransactionCategory> { category in
                    category.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveUserCategory(_ context: ModelContext) throws -> TransactionCategory? {
        try fetchFirst(
            FetchDescriptor<TransactionCategory>(
                predicate: #Predicate<TransactionCategory> { category in
                    category.deletedAt == nil && !category.isSystem
                }
            ),
            context: context
        )
    }

    private static func fetchCategories(_ context: ModelContext) throws -> [TransactionCategory] {
        try context.fetch(FetchDescriptor<TransactionCategory>())
    }

    private static func fetchTransaction(id: UUID, _ context: ModelContext) throws -> LedgerTransaction? {
        try fetchFirst(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in
                    transaction.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveTransaction(_ context: ModelContext) throws -> LedgerTransaction? {
        try fetchFirst(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in
                    transaction.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchTransactions(_ context: ModelContext) throws -> [LedgerTransaction] {
        try context.fetch(FetchDescriptor<LedgerTransaction>())
    }

    private static func fetchSettlementGroup(id: UUID, _ context: ModelContext) throws -> SettlementGroup? {
        try fetchFirst(
            FetchDescriptor<SettlementGroup>(
                predicate: #Predicate<SettlementGroup> { group in
                    group.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveSettlementGroup(_ context: ModelContext) throws -> SettlementGroup? {
        try fetchFirst(
            FetchDescriptor<SettlementGroup>(
                predicate: #Predicate<SettlementGroup> { group in
                    group.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchSettlementGroups(_ context: ModelContext) throws -> [SettlementGroup] {
        try context.fetch(FetchDescriptor<SettlementGroup>())
    }

    private static func fetchSettlementParticipant(id: UUID, _ context: ModelContext) throws -> SettlementParticipant? {
        try fetchFirst(
            FetchDescriptor<SettlementParticipant>(
                predicate: #Predicate<SettlementParticipant> { participant in
                    participant.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveSettlementParticipant(_ context: ModelContext) throws -> SettlementParticipant? {
        try fetchFirst(
            FetchDescriptor<SettlementParticipant>(
                predicate: #Predicate<SettlementParticipant> { participant in
                    participant.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchSettlementParticipants(_ context: ModelContext) throws -> [SettlementParticipant] {
        try context.fetch(FetchDescriptor<SettlementParticipant>())
    }

    private static func fetchTransactionAudits(_ context: ModelContext) throws -> [TransactionAuditRecord] {
        try context.fetch(FetchDescriptor<TransactionAuditRecord>())
    }

    private static func fetchBudgetPlan(id: UUID, _ context: ModelContext) throws -> BudgetPlan? {
        try fetchFirst(
            FetchDescriptor<BudgetPlan>(
                predicate: #Predicate<BudgetPlan> { plan in
                    plan.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveBudgetPlan(_ context: ModelContext) throws -> BudgetPlan? {
        try fetchFirst(
            FetchDescriptor<BudgetPlan>(
                predicate: #Predicate<BudgetPlan> { plan in
                    plan.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchBudgetPlans(_ context: ModelContext) throws -> [BudgetPlan] {
        try context.fetch(FetchDescriptor<BudgetPlan>())
    }

    private static func fetchSavingsGoal(id: UUID, _ context: ModelContext) throws -> SavingsGoal? {
        try fetchFirst(
            FetchDescriptor<SavingsGoal>(
                predicate: #Predicate<SavingsGoal> { goal in
                    goal.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveSavingsGoal(_ context: ModelContext) throws -> SavingsGoal? {
        try fetchFirst(
            FetchDescriptor<SavingsGoal>(
                predicate: #Predicate<SavingsGoal> { goal in
                    goal.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchSavingsGoals(_ context: ModelContext) throws -> [SavingsGoal] {
        try context.fetch(FetchDescriptor<SavingsGoal>())
    }

    private static func fetchRecurringBillPlan(id: UUID, _ context: ModelContext) throws -> RecurringBillPlan? {
        try fetchFirst(
            FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate<RecurringBillPlan> { plan in
                    plan.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveRecurringBillPlan(_ context: ModelContext) throws -> RecurringBillPlan? {
        try fetchFirst(
            FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate<RecurringBillPlan> { plan in
                    plan.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchRecurringBillPlans(_ context: ModelContext) throws -> [RecurringBillPlan] {
        try context.fetch(FetchDescriptor<RecurringBillPlan>())
    }

    private static func recurringBillCategoryID(
        for plan: RecurringBillPlan,
        userID: UUID,
        categories: [TransactionCategory]
    ) -> UUID? {
        if let category = plan.category {
            return mistiaCloudCategoryID(for: category, userID: userID)
        }

        guard let parsed = MistiaSystemCategoryRegistry.shared.allParents
            .flatMap({ $0.children ?? [] })
            .first(where: { $0.icon == plan.iconSymbolName }) else {
            return nil
        }

        let matchingCategory = categories.first { category in
            guard category.deletedAt == nil else { return false }
            return category.systemKey == parsed.id
        }
        return mistiaCloudCategoryID(for: matchingCategory, userID: userID)
    }

    private static func fetchInstallmentPlan(id: UUID, _ context: ModelContext) throws -> InstallmentPlan? {
        try fetchFirst(
            FetchDescriptor<InstallmentPlan>(
                predicate: #Predicate<InstallmentPlan> { plan in
                    plan.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveInstallmentPlan(_ context: ModelContext) throws -> InstallmentPlan? {
        try fetchFirst(
            FetchDescriptor<InstallmentPlan>(
                predicate: #Predicate<InstallmentPlan> { plan in
                    plan.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchInstallmentPlans(_ context: ModelContext) throws -> [InstallmentPlan] {
        try context.fetch(FetchDescriptor<InstallmentPlan>())
    }

    private static func fetchDueOccurrence(id: UUID, _ context: ModelContext) throws -> DueOccurrenceRecord? {
        try fetchFirst(
            FetchDescriptor<DueOccurrenceRecord>(
                predicate: #Predicate<DueOccurrenceRecord> { record in
                    record.id == id
                }
            ),
            context: context
        )
    }

    private static func fetchActiveDueOccurrence(_ context: ModelContext) throws -> DueOccurrenceRecord? {
        try fetchFirst(
            FetchDescriptor<DueOccurrenceRecord>(
                predicate: #Predicate<DueOccurrenceRecord> { record in
                    record.deletedAt == nil
                }
            ),
            context: context
        )
    }

    private static func fetchDueOccurrences(_ context: ModelContext) throws -> [DueOccurrenceRecord] {
        try context.fetch(FetchDescriptor<DueOccurrenceRecord>())
    }

    private static func fetchConflicts(_ context: ModelContext) throws -> [SyncConflict] {
        try context.fetch(FetchDescriptor<SyncConflict>())
    }

    private static func canonicalStorageKey(
        entity: MistiaSyncEntity,
        recordID: UUID
    ) -> String {
        "\(entity.rawValue):\(recordID.uuidString.lowercased())"
    }

    private static func ownerUserID(
        forWalletID walletID: UUID?,
        ownerMap: [UUID: UUID]
    ) -> UUID? {
        guard let walletID else { return nil }
        return ownerMap[walletID]
    }
}

nonisolated private func mistiaCloudCategoryID(
    for category: TransactionCategory?,
    userID: UUID
) -> UUID? {
    guard let category else { return nil }
    guard category.isSystem, let systemKey = category.systemKey else {
        return category.id
    }
    return MistiaSystemCategoryIdentity.cloudScopedID(
        canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
        ownerUserID: userID
    )
}

private extension RemoteLedgerWallet {
    init(local wallet: LedgerWallet, userID: UUID) {
        self.init(
            userID: userID,
            id: wallet.id,
            name: wallet.name,
            kindRawValue: wallet.kindRawValue,
            iconSymbolName: wallet.iconSymbolName,
            iconColorHex: wallet.iconColorHex,
            currencyCode: wallet.currencyCode,
            openingBalanceMinor: wallet.openingBalanceMinor,
            institutionDisplayName: wallet.institutionDisplayName,
            institutionPresetKey: wallet.institutionPresetKey,
            sortOrder: wallet.sortOrder,
            isArchived: wallet.isArchived,
            archivedAt: wallet.archivedAt,
            createdAt: wallet.createdAt,
            updatedAt: wallet.updatedAt,
            deletedAt: wallet.deletedAt,
            syncVersion: max(wallet.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteCreditCardProfile {
    init(local profile: CreditCardProfile, userID: UUID) {
        self.init(
            userID: userID,
            id: profile.id,
            issuerName: profile.issuerName,
            networkRawValue: profile.networkRawValue,
            last4: profile.last4,
            creditLimitMinor: profile.creditLimitMinor,
            statementClosingDay: profile.statementClosingDay,
            paymentDueDay: profile.paymentDueDay,
            notes: profile.notes,
            walletID: profile.wallet?.id,
            paymentSourceWalletID: profile.paymentSourceWallet?.id,
            autoPayEnabled: profile.autoPayEnabled,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            deletedAt: profile.deletedAt,
            syncVersion: max(profile.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteTransactionCategory {
    init(local category: TransactionCategory, userID: UUID) {
        let names = category.syncNameFields
        self.userID = userID
        self.id = mistiaCloudCategoryID(for: category, userID: userID) ?? category.id
        self.name = names.name
        self.nameEnglish = names.nameEnglish
        self.nameJapanese = names.nameJapanese
        self.kindRawValue = category.kindRawValue
        self.iconSymbolName = category.iconSymbolName
        self.iconColorHex = category.iconColorHex
        self.isFavorite = category.isFavorite
        self.familyBudgetSpendingEnabled = category.familyBudgetSpendingEnabled
        self.parentCategoryID = mistiaCloudCategoryID(for: category.parentCategory, userID: userID)
        self.hierarchyRoleRawValue = category.hierarchyRoleRawValue
        self.systemKey = category.systemKey
        self.isSystem = category.isSystem
        self.sortOrder = category.sortOrder
        self.isArchived = category.isArchived
        self.archivedAt = category.archivedAt
        self.createdAt = category.createdAt
        self.updatedAt = category.updatedAt
        self.deletedAt = category.deletedAt
        self.syncVersion = max(category.remoteVersion, 1)
        self.lastModifiedByDeviceID = nil
    }
}

private extension TransactionCategory {
    var syncNameFields: (name: String, nameEnglish: String?, nameJapanese: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let systemKey,
           let parsed = MistiaSystemCategoryRegistry.shared.category(for: systemKey),
           Set(parsed.knownDefaultNames()).contains(trimmedName) {
            let vi = parsed.translations["vi"] ?? systemKey
            let en = parsed.translations["en"] ?? vi
            let ja = parsed.translations["ja"] ?? vi
            return (
                vi,
                nonBlank(nameEnglish) ?? en,
                nonBlank(nameJapanese) ?? ja
            )
        }

        return (name, nameEnglish, nameJapanese)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension RemoteLedgerTransaction {
    init(
        local transaction: LedgerTransaction,
        userID: UUID,
        auditRecord: TransactionAuditRecord?
    ) {
        let createdByUserID = auditRecord?.createdByUserID ?? userID
        self.userID = userID
        self.id = transaction.id
        self.primaryKindRawValue = transaction.primaryKindRawValue
        self.transferSubtypeRawValue = transaction.transferSubtypeRawValue
        self.debtIntentRawValue = transaction.debtIntentRawValue
        self.entryStatusRawValue = transaction.entryStatusRawValue
        self.title = transaction.title
        self.note = transaction.note
        self.amountMinor = transaction.amountMinor
        self.sourceCurrencyCode = transaction.sourceCurrencyCode
        self.destinationCurrencyCode = transaction.destinationCurrencyCode
        self.destinationAmountMinor = transaction.destinationAmountMinor
        self.reportingCurrencyCode = transaction.reportingCurrencyCode
        self.reportingAmountMinor = transaction.reportingAmountMinor
        self.conversionModeRawValue = transaction.conversionModeRawValue
        self.exchangeRateDecimalString = transaction.exchangeRateDecimalString
        self.exchangeRateProvider = transaction.exchangeRateProvider
        self.exchangeRateDate = transaction.exchangeRateDate
        self.occurredAt = transaction.occurredAt
        self.createdAt = transaction.createdAt
        self.updatedAt = transaction.updatedAt
        self.createdByUserID = createdByUserID
        self.lastModifiedByUserID = auditRecord?.lastModifiedByUserID ?? createdByUserID
        self.counterpartyName = transaction.counterpartyName
        self.normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        self.settlementGroupID = transaction.settlementGroupID
        self.settlementObligationID = transaction.settlementObligationID
        self.settlementRoleRawValue = transaction.settlementRoleRawValue
        self.reportingExpenseMinor = transaction.reportingExpenseMinor
        self.reportingIncomeMinor = transaction.reportingIncomeMinor
        self.sourceWalletID = transaction.sourceWallet?.id
        self.destinationWalletID = transaction.destinationWallet?.id
        self.categoryID = mistiaCloudCategoryID(for: transaction.category, userID: userID)
        self.deletedAt = transaction.deletedAt
        self.isArchived = transaction.isArchived
        self.archivedAt = transaction.archivedAt
        self.syncVersion = max(transaction.remoteVersion, 1)
        self.lastModifiedByDeviceID = nil
    }
}

private extension RemoteSettlementGroup {
    init(local group: SettlementGroup, userID: UUID) {
        self.userID = userID
        self.id = group.id
        self.kindRawValue = group.kindRawValue
        self.statusRawValue = group.statusRawValue
        self.title = group.title
        self.currencyCode = group.currencyCode
        self.occurredAt = group.occurredAt
        self.totalMinor = group.totalMinor
        self.expectedMinor = group.expectedMinor
        self.settledMinor = group.settledMinor
        self.organizerUserID = group.organizerUserID
        self.note = group.note
        self.createdAt = group.createdAt
        self.updatedAt = group.updatedAt
        self.deletedAt = group.deletedAt
        self.isArchived = group.isArchived
        self.archivedAt = group.archivedAt
        self.syncVersion = max(group.remoteVersion, 1)
        self.lastModifiedByDeviceID = nil
    }
}

private extension RemoteSettlementParticipant {
    init(local participant: SettlementParticipant, userID: UUID) {
        self.userID = userID
        self.id = participant.id
        self.groupID = participant.groupID
        self.displayName = participant.displayName
        self.normalizedKey = participant.normalizedKey
        self.memberUserID = participant.memberUserID
        self.isSelf = participant.isSelf
        self.sortOrder = participant.sortOrder
        self.createdAt = participant.createdAt
        self.updatedAt = participant.updatedAt
        self.deletedAt = participant.deletedAt
        self.syncVersion = max(participant.remoteVersion, 1)
        self.lastModifiedByDeviceID = nil
    }
}

private extension RemoteBudgetPlan {
    init(local plan: BudgetPlan, userID: UUID) {
        self.init(
            userID: userID,
            id: plan.id,
            categoryID: mistiaCloudCategoryID(for: plan.category, userID: userID),
            categoryIDSnapshot: plan.categoryIDSnapshot,
            categoryNameSnapshot: plan.categoryNameSnapshot,
            categoryNameEnglishSnapshot: plan.categoryNameEnglishSnapshot,
            categoryNameJapaneseSnapshot: plan.categoryNameJapaneseSnapshot,
            categoryPathSnapshot: plan.categoryPathSnapshot,
            categoryPathEnglishSnapshot: plan.categoryPathEnglishSnapshot,
            categoryPathJapaneseSnapshot: plan.categoryPathJapaneseSnapshot,
            categoryIconSymbolNameSnapshot: plan.categoryIconSymbolNameSnapshot,
            categoryColorHexSnapshot: plan.categoryColorHexSnapshot,
            categoryParentIDSnapshot: plan.categoryParentIDSnapshot,
            categoryParentNameSnapshot: plan.categoryParentNameSnapshot,
            categoryParentNameEnglishSnapshot: plan.categoryParentNameEnglishSnapshot,
            categoryParentNameJapaneseSnapshot: plan.categoryParentNameJapaneseSnapshot,
            categoryParentIconSymbolNameSnapshot: plan.categoryParentIconSymbolNameSnapshot,
            categoryParentColorHexSnapshot: plan.categoryParentColorHexSnapshot,
            categoryHierarchyRoleSnapshotRawValue: plan.categoryHierarchyRoleSnapshotRawValue,
            categoryIsParentSnapshot: plan.categoryIsParentSnapshotRawValue,
            includesFamilySpending: plan.includesFamilySpending,
            monthAnchor: plan.monthAnchor,
            limitMinor: plan.limitMinor,
            rolloverEnabled: plan.rolloverEnabled,
            currencyCode: plan.currencyCode,
            isArchived: plan.isArchived,
            createdAt: plan.createdAt,
            updatedAt: plan.updatedAt,
            deletedAt: plan.deletedAt,
            syncVersion: max(plan.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteSavingsGoal {
    init(local goal: SavingsGoal, userID: UUID) {
        self.init(
            userID: userID,
            id: goal.id,
            name: goal.name,
            iconSymbolName: goal.iconSymbolName,
            targetMinor: goal.targetMinor,
            currentSavedMinor: goal.currentSavedMinor,
            targetDate: goal.targetDate,
            linkedWalletID: goal.linkedWallet?.id,
            currencyCode: goal.currencyCode,
            sortOrder: goal.sortOrder,
            isArchived: goal.isArchived,
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt,
            deletedAt: goal.deletedAt,
            syncVersion: max(goal.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteRecurringBillPlan {
    init(local plan: RecurringBillPlan, userID: UUID, categoryID: UUID?) {
        let scheduleKind = plan.scheduleKind
        self.init(
            userID: userID,
            id: plan.id,
            name: plan.name,
            iconSymbolName: plan.iconSymbolName,
            categoryID: categoryID,
            amountMinor: plan.amountMinor,
            dueDay: plan.dueDay,
            scheduleKindRawValue: scheduleKind.rawValue,
            paymentStartDay: plan.resolvedPaymentStartDay,
            paymentStartDate: scheduleKind == .oneTime ? plan.paymentStartDate : nil,
            firstScheduledMonth: plan.firstScheduledMonth,
            hasExplicitDueDate: plan.resolvedHasExplicitDueDate,
            dueDate: plan.dueDate,
            autoPayEnabled: plan.autoPayEnabled,
            autoPayDay: plan.autoPayDay,
            autoPayDate: scheduleKind == .oneTime ? plan.autoPayDate : nil,
            frequencyMonths: plan.frequencyMonths,
            paymentWalletID: plan.paymentWallet?.id,
            currencyCode: plan.currencyCode,
            isArchived: plan.isArchived,
            isPaused: plan.isPaused,
            pausedAt: plan.pausedAt,
            resumeStartMonth: plan.resumeStartMonth,
            createdAt: plan.createdAt,
            updatedAt: plan.updatedAt,
            deletedAt: plan.deletedAt,
            syncVersion: max(plan.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteInstallmentPlan {
    init(local plan: InstallmentPlan, userID: UUID) {
        self.init(
            userID: userID,
            id: plan.id,
            name: plan.name,
            iconSymbolName: plan.iconSymbolName,
            amountPerCycleMinor: plan.amountPerCycleMinor,
            dueDay: plan.dueDay,
            totalCycles: plan.totalCycles,
            frequencyMonths: plan.frequencyMonths,
            paymentWalletID: plan.paymentWallet?.id,
            currencyCode: plan.currencyCode,
            isArchived: plan.isArchived,
            createdAt: plan.createdAt,
            updatedAt: plan.updatedAt,
            deletedAt: plan.deletedAt,
            syncVersion: max(plan.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteDueOccurrenceRecord {
    init(local record: DueOccurrenceRecord, userID: UUID) {
        self.init(
            userID: userID,
            id: record.id,
            sourceKindRawValue: record.sourceKindRawValue,
            sourceID: record.sourceID,
            selectedMonthKey: record.selectedMonthKey,
            scheduledDate: record.scheduledDate,
            amountMinorSnapshot: record.amountMinorSnapshot,
            statusRawValue: record.statusRawValue,
            paidAt: record.paidAt,
            linkedTransactionID: record.linkedTransactionID,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            syncVersion: max(record.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension String {
    var normalizedForDuplicateCheck: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func hasCommonTokens(with other: String) -> Bool {
        let lhs = Set(normalizedForDuplicateCheck.split(separator: " ").map(String.init))
        let rhs = Set(other.normalizedForDuplicateCheck.split(separator: " ").map(String.init))
        return !lhs.intersection(rhs).isEmpty
    }
}

enum MistiaBackupRestoreMode: String, CaseIterable, Identifiable, Codable {
    case merge
    case replaceLocal

    var id: String { rawValue }
}

struct MistiaBackupManifestV1: Codable {
    let backupFormatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let appBuild: String
    let localSchemaVersion: Int
}

struct MistiaBackupUserAccountProfileV1: Codable {
    let userID: UUID
    let email: String
    let displayName: String
    let avatarFileName: String?
    let birthday: Date?
    let lastSyncAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct MistiaBackupOwnedRecordScopeV1: Codable {
    let id: String
    let entityRawValue: String
    let recordID: UUID
    let ownerUserID: UUID
    let updatedAt: Date
}

struct MistiaBackupTransactionAuditRecordV1: Codable {
    let transactionID: UUID
    let createdByUserID: UUID
    let lastModifiedByUserID: UUID
    let updatedAt: Date
}

struct MistiaBackupAvatarAssetV1: Codable {
    let userID: UUID
    let fileName: String
    let imageData: Data
}

struct MistiaBackupEnvelopeV1: Codable {
    let manifest: MistiaBackupManifestV1
    let snapshot: MistiaRemoteSnapshot
    let userProfiles: [MistiaBackupUserAccountProfileV1]
    let ownershipScopes: [MistiaBackupOwnedRecordScopeV1]
    let transactionAudits: [MistiaBackupTransactionAuditRecordV1]
    let avatarAssets: [MistiaBackupAvatarAssetV1]
}

struct MistiaBackupValidationSummary {
    let manifest: MistiaBackupManifestV1
    let walletCount: Int
    let creditCardProfileCount: Int
    let categoryCount: Int
    let settlementGroupCount: Int
    let settlementParticipantCount: Int
    let transactionCount: Int
    let budgetPlanCount: Int
    let savingsGoalCount: Int
    let recurringBillPlanCount: Int
    let installmentPlanCount: Int
    let dueOccurrenceCount: Int
    let userProfileCount: Int
    let ownershipScopeCount: Int
    let transactionAuditCount: Int
    let avatarAssetCount: Int

    var activeRecordCount: Int {
        walletCount
            + creditCardProfileCount
            + categoryCount
            + settlementGroupCount
            + settlementParticipantCount
            + transactionCount
            + budgetPlanCount
            + savingsGoalCount
            + recurringBillPlanCount
            + installmentPlanCount
            + dueOccurrenceCount
    }
}

struct MistiaBackupExportResult {
    let fileName: String
    let data: Data
    let summary: MistiaBackupValidationSummary
}

struct MistiaBackupRestoreResult {
    let mode: MistiaBackupRestoreMode
    let summary: MistiaBackupValidationSummary
    let safetySnapshotURL: URL?
}

enum MistiaBackupStoreError: LocalizedError {
    case unsupportedBackupFormat(Int)
    case unsupportedLocalSchema(Int)
    case syncInProgress
    case invalidBackupPayload(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedBackupFormat(let version):
            "Unsupported Mistia backup format version \(version)."
        case .unsupportedLocalSchema(let version):
            "This backup was created for unsupported local schema version \(version)."
        case .syncInProgress:
            "Wait for the current sync to finish before restoring a snapshot."
        case .invalidBackupPayload(let message):
            message
        }
    }
}

@MainActor
enum MistiaBackupStore {
    static func exportBackup(
        from container: ModelContainer,
        fallbackOwnerUserID: UUID,
        appVersion: String,
        appBuild: String
    ) throws -> MistiaBackupExportResult {
        let envelope = try MistiaSyncLocalStore.exportBackupEnvelope(
            from: container,
            fallbackOwnerUserID: fallbackOwnerUserID,
            appVersion: appVersion,
            appBuild: appBuild
        )
        let data = try JSONEncoder.mistiaBackupEncoder.encode(envelope)
        let summary = MistiaBackupValidationSummary(envelope: envelope)
        return MistiaBackupExportResult(
            fileName: backupFileName(for: envelope.manifest.exportedAt),
            data: data,
            summary: summary
        )
    }

    static func validateBackup(_ data: Data) throws -> MistiaBackupValidationSummary {
        try MistiaBackupValidationSummary(envelope: decodeBackup(data))
    }

    static func restoreBackup(
        _ data: Data,
        mode: MistiaBackupRestoreMode,
        in container: ModelContainer,
        fallbackOwnerUserID: UUID,
        outbox: MistiaSyncOutbox? = nil
    ) throws -> MistiaBackupRestoreResult {
        let outbox = outbox ?? MistiaSyncOutbox()
        let envelope = try decodeBackup(data)
        let summary = MistiaBackupValidationSummary(envelope: envelope)
        let safetySnapshotURL: URL?

        if mode == .replaceLocal {
            let safetySnapshot = try exportBackup(
                from: container,
                fallbackOwnerUserID: fallbackOwnerUserID,
                appVersion: currentAppVersion(),
                appBuild: currentAppBuild()
            )
            safetySnapshotURL = try writeSafetySnapshot(
                data: safetySnapshot.data,
                exportedAt: safetySnapshot.summary.manifest.exportedAt
            )
            try MistiaBackupAvatarStore.clearAllAssets()
        } else {
            safetySnapshotURL = nil
        }

        outbox.clear()
        try MistiaSyncLocalStore.restoreBackupEnvelope(envelope, mode: mode, in: container)
        try MistiaBackupAvatarStore.writeAssets(envelope.avatarAssets)
        outbox.clear()

        return MistiaBackupRestoreResult(
            mode: mode,
            summary: summary,
            safetySnapshotURL: safetySnapshotURL
        )
    }

    private static func decodeBackup(_ data: Data) throws -> MistiaBackupEnvelopeV1 {
        let envelope: MistiaBackupEnvelopeV1

        do {
            envelope = try JSONDecoder.mistiaBackupDecoder.decode(MistiaBackupEnvelopeV1.self, from: data)
        } catch {
            throw MistiaBackupStoreError.invalidBackupPayload(String(describing: error))
        }

        guard envelope.manifest.backupFormatVersion == 1 else {
            throw MistiaBackupStoreError.unsupportedBackupFormat(envelope.manifest.backupFormatVersion)
        }
        guard envelope.manifest.localSchemaVersion == 1 else {
            throw MistiaBackupStoreError.unsupportedLocalSchema(envelope.manifest.localSchemaVersion)
        }

        return envelope
    }

    private static func currentAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func currentAppBuild() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private static func backupFileName(for date: Date) -> String {
        "mistia-snapshot-\(MistiaBackupFilenameFormatter.shared.string(from: date)).mistiabackup"
    }

    private static func writeSafetySnapshot(
        data: Data,
        exportedAt: Date
    ) throws -> URL {
        let directoryURL = try backupDirectoryURL()
        let url = directoryURL.appendingPathComponent(
            "mistia-safety-\(MistiaBackupFilenameFormatter.shared.string(from: exportedAt)).mistiabackup"
        )

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    private static func backupDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("MistiaBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}

nonisolated private enum MistiaBackupAvatarStore {
    static func loadAssets(for profiles: [UserAccountProfile]) throws -> [MistiaBackupAvatarAssetV1] {
        try profiles.compactMap { profile in
            guard let fileName = profile.avatarFileName else { return nil }
            let fileURL = avatarURL(forFileName: fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return MistiaBackupAvatarAssetV1(
                userID: profile.userID,
                fileName: fileName,
                imageData: try Data(contentsOf: fileURL)
            )
        }
    }

    static func writeAssets(_ assets: [MistiaBackupAvatarAssetV1]) throws {
        guard !assets.isEmpty else { return }
        let directoryURL = try avatarDirectoryURL()

        for asset in assets {
            let fileURL = directoryURL.appendingPathComponent(asset.fileName)
            try asset.imageData.write(to: fileURL, options: .atomic)
        }
    }

    static func clearAllAssets() throws {
        let directoryURL = try avatarDirectoryURL()
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }

    private static func avatarDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("ProfileAvatars", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func avatarURL(forFileName fileName: String) -> URL {
        let baseURL = (try? avatarDirectoryURL()) ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(fileName)
    }
}

private enum MistiaBackupFilenameFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private extension MistiaBackupValidationSummary {
    init(envelope: MistiaBackupEnvelopeV1) {
        self.init(
            manifest: envelope.manifest,
            walletCount: envelope.snapshot.wallets.count,
            creditCardProfileCount: envelope.snapshot.creditCardProfiles.count,
            categoryCount: envelope.snapshot.categories.count,
            settlementGroupCount: envelope.snapshot.settlementGroups.count,
            settlementParticipantCount: envelope.snapshot.settlementParticipants.count,
            transactionCount: envelope.snapshot.transactions.count,
            budgetPlanCount: envelope.snapshot.budgetPlans.count,
            savingsGoalCount: envelope.snapshot.savingsGoals.count,
            recurringBillPlanCount: envelope.snapshot.recurringBillPlans.count,
            installmentPlanCount: envelope.snapshot.installmentPlans.count,
            dueOccurrenceCount: envelope.snapshot.dueOccurrences.count,
            userProfileCount: envelope.userProfiles.count,
            ownershipScopeCount: envelope.ownershipScopes.count,
            transactionAuditCount: envelope.transactionAudits.count,
            avatarAssetCount: envelope.avatarAssets.count
        )
    }
}

private extension MistiaBackupUserAccountProfileV1 {
    init(profile: UserAccountProfile) {
        self.init(
            userID: profile.userID,
            email: profile.email,
            displayName: profile.displayName,
            avatarFileName: profile.avatarFileName,
            birthday: profile.birthday,
            lastSyncAt: profile.lastSyncAt,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    init(_ profile: UserAccountProfile) {
        self.init(profile: profile)
    }
}
