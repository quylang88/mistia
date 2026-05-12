import Foundation
import SwiftData

enum MistiaSyncLocalStore {
    static func totalObjectCount(in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        return try fetchWallets(context).count
            + fetchCreditCardProfiles(context).count
            + fetchCategories(context).count
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

        if try fetchWallets(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchCreditCardProfiles(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchTransactions(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchBudgetPlans(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchSavingsGoals(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchRecurringBillPlans(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchInstallmentPlans(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchDueOccurrences(context).contains(where: { $0.deletedAt == nil }) {
            return true
        }
        if try fetchCategories(context).contains(where: { $0.deletedAt == nil && !$0.isSystem }) {
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
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
        let goalOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
        let recurringOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let installmentOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)
        let allCategories = try fetchCategories(context)
            .filter { categoryOwnerMap[$0.id] == nil || categoryOwnerMap[$0.id] == userID }
        let wallets = try fetchWallets(context)
            .filter { walletOwnerMap[$0.id] == nil || walletOwnerMap[$0.id] == userID }
        let creditCardProfiles = try fetchCreditCardProfiles(context)
            .filter { profileOwnerMap[$0.id] == nil || profileOwnerMap[$0.id] == userID }
        let categories = allCategories.filter(MistiaSystemCategorySyncSupport.shouldExportCategory)
        let transactions = try fetchTransactions(context)
            .filter { transactionOwnerMap[$0.id] == nil || transactionOwnerMap[$0.id] == userID }
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

        return MistiaRemoteSnapshot(
            wallets: wallets.map { RemoteLedgerWallet(local: $0, userID: userID) },
            creditCardProfiles: creditCardProfiles.map { RemoteCreditCardProfile(local: $0, userID: userID) },
            categories: categories.map { RemoteTransactionCategory(local: $0, userID: userID) },
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
                    categoryID: recurringBillCategoryID(for: $0, categories: allCategories)
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
        let baseSnapshot = try exportSnapshot(for: userID, from: container)
        let supplementalCategories = try supplementalCategoriesForUpload(
            userID: userID,
            baseSnapshot: baseSnapshot,
            from: container
        )

        guard !supplementalCategories.isEmpty else {
            return baseSnapshot
        }

        return MistiaRemoteSnapshot(
            wallets: baseSnapshot.wallets,
            creditCardProfiles: baseSnapshot.creditCardProfiles,
            categories: baseSnapshot.categories + supplementalCategories,
            transactions: baseSnapshot.transactions,
            budgetPlans: baseSnapshot.budgetPlans,
            savingsGoals: baseSnapshot.savingsGoals,
            recurringBillPlans: baseSnapshot.recurringBillPlans,
            installmentPlans: baseSnapshot.installmentPlans,
            dueOccurrences: baseSnapshot.dueOccurrences
        )
    }

    static func exportRecord(
        for mutation: MistiaSyncMutation,
        from container: ModelContainer
    ) throws -> MistiaSyncUploadRecord? {
        let context = ModelContext(container)
        let subjectUserID = mutation.subjectUserID
        let auditMap = try TransactionAuditStore.auditMap(from: fetchTransactionAudits(context))

        switch mutation.entity {
        case .wallet:
            guard let wallet = try fetchWallets(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .wallet(RemoteLedgerWallet(local: wallet, userID: subjectUserID))
        case .creditCardProfile:
            guard let profile = try fetchCreditCardProfiles(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .creditCardProfile(RemoteCreditCardProfile(local: profile, userID: subjectUserID))
        case .category:
            guard let category = try fetchCategories(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            guard MistiaSystemCategorySyncSupport.shouldExportCategory(category) else {
                return nil
            }
            return .category(RemoteTransactionCategory(local: category, userID: subjectUserID))
        case .transaction:
            guard let transaction = try fetchTransactions(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .transaction(
                RemoteLedgerTransaction(
                    local: transaction,
                    userID: subjectUserID,
                    auditRecord: auditMap[transaction.id]
                )
            )
        case .budgetPlan:
            guard let plan = try fetchBudgetPlans(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .budgetPlan(RemoteBudgetPlan(local: plan, userID: subjectUserID))
        case .savingsGoal:
            guard let goal = try fetchSavingsGoals(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .savingsGoal(RemoteSavingsGoal(local: goal, userID: subjectUserID))
        case .recurringBillPlan:
            guard let plan = try fetchRecurringBillPlans(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            let categories = try fetchCategories(context)
            return .recurringBillPlan(
                RemoteRecurringBillPlan(
                    local: plan,
                    userID: subjectUserID,
                    categoryID: recurringBillCategoryID(for: plan, categories: categories)
                )
            )
        case .installmentPlan:
            guard let plan = try fetchInstallmentPlans(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .installmentPlan(RemoteInstallmentPlan(local: plan, userID: subjectUserID))
        case .dueOccurrenceRecord:
            guard let record = try fetchDueOccurrences(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .dueOccurrence(RemoteDueOccurrenceRecord(local: record, userID: subjectUserID))
        }
    }

    static func currentRemoteVersion(
        for entity: MistiaSyncEntity,
        recordID: UUID,
        from container: ModelContainer
    ) throws -> Int64 {
        let context = ModelContext(container)

        switch entity {
        case .wallet:
            return try fetchWallets(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .creditCardProfile:
            return try fetchCreditCardProfiles(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .category:
            return try fetchCategories(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .transaction:
            return try fetchTransactions(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .budgetPlan:
            return try fetchBudgetPlans(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .savingsGoal:
            return try fetchSavingsGoals(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .recurringBillPlan:
            return try fetchRecurringBillPlans(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .installmentPlan:
            return try fetchInstallmentPlans(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        case .dueOccurrenceRecord:
            return try fetchDueOccurrences(context).first(where: { $0.id == recordID })?.remoteVersion ?? 0
        }
    }

    static func detachFromCloud(in container: ModelContainer) throws {
        let context = ModelContext(container)

        try fetchWallets(context).forEach { $0.remoteVersion = 0 }
        try fetchCreditCardProfiles(context).forEach { $0.remoteVersion = 0 }
        try fetchCategories(context).forEach { $0.remoteVersion = 0 }
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
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)

        let wallets = try fetchWallets(context)
        let creditProfiles = try fetchCreditCardProfiles(context)
        let categories = try fetchCategories(context)
        let transactions = try fetchTransactions(context)
        let budgetPlans = try fetchBudgetPlans(context)
        let savingsGoals = try fetchSavingsGoals(context)
        let recurringBillPlans = try fetchRecurringBillPlans(context)
        let installmentPlans = try fetchInstallmentPlans(context)
        let dueOccurrences = try fetchDueOccurrences(context)
        var walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        var categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var profileByID = Dictionary(uniqueKeysWithValues: creditProfiles.map { ($0.id, $0) })
        var transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        var budgetByID = Dictionary(uniqueKeysWithValues: budgetPlans.map { ($0.id, $0) })
        var goalByID = Dictionary(uniqueKeysWithValues: savingsGoals.map { ($0.id, $0) })
        var recurringByID = Dictionary(uniqueKeysWithValues: recurringBillPlans.map { ($0.id, $0) })
        var installmentByID = Dictionary(uniqueKeysWithValues: installmentPlans.map { ($0.id, $0) })
        var occurrenceByID = Dictionary(uniqueKeysWithValues: dueOccurrences.map { ($0.id, $0) })

        for row in snapshot.wallets {
            try upsertWallet(row, context: context, walletByID: &walletByID)
        }

        for row in snapshot.categories {
            try upsertCategory(row, context: context, categoryByID: &categoryByID)
        }

        for row in snapshot.categories {
            applyCategoryHierarchy(row, categoryByID: categoryByID)
        }

        for row in snapshot.creditCardProfiles {
            try upsertCreditProfile(
                row,
                context: context,
                walletByID: walletByID,
                profileByID: &profileByID
            )
        }

        for row in snapshot.transactions {
            try upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        }

        for row in snapshot.budgetPlans {
            try upsertBudget(row, context: context, categoryByID: categoryByID, budgetByID: &budgetByID)
        }

        for row in snapshot.savingsGoals {
            try upsertGoal(row, context: context, walletByID: walletByID, goalByID: &goalByID)
        }

        for row in snapshot.recurringBillPlans {
            try upsertRecurringBill(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                recurringByID: &recurringByID
            )
        }

        for row in snapshot.installmentPlans {
            try upsertInstallment(row, context: context, walletByID: walletByID, installmentByID: &installmentByID)
        }

        for row in snapshot.dueOccurrences {
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
                remoteIDs: Set(snapshot.categories.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: transactions,
                remoteIDs: Set(snapshot.transactions.map(\.id)),
                protectedRecordIDs: protectedRecordIDs,
                context: context
            )
            pruneRecordsMissingFromRemote(
                existing: budgetPlans,
                remoteIDs: Set(snapshot.budgetPlans.map(\.id)),
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
                remoteIDs: Set(snapshot.recurringBillPlans.map(\.id)),
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

        try context.save()
    }

    static func applyRemoteRecord(
        _ record: MistiaSyncUploadRecord,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let wallets = try fetchWallets(context)
        let categories = try fetchCategories(context)
        var walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        var categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        switch record {
        case .wallet(let row):
            try upsertWallet(row, context: context, walletByID: &walletByID)
        case .creditCardProfile(let row):
            var profileByID = Dictionary(uniqueKeysWithValues: try fetchCreditCardProfiles(context).map { ($0.id, $0) })
            try upsertCreditProfile(row, context: context, walletByID: walletByID, profileByID: &profileByID)
        case .category(let row):
            try upsertCategory(row, context: context, categoryByID: &categoryByID)
            applyCategoryHierarchy(row, categoryByID: categoryByID)
        case .transaction(let row):
            var transactionByID = Dictionary(uniqueKeysWithValues: try fetchTransactions(context).map { ($0.id, $0) })
            try upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        case .budgetPlan(let row):
            var budgetByID = Dictionary(uniqueKeysWithValues: try fetchBudgetPlans(context).map { ($0.id, $0) })
            try upsertBudget(row, context: context, categoryByID: categoryByID, budgetByID: &budgetByID)
        case .savingsGoal(let row):
            var goalByID = Dictionary(uniqueKeysWithValues: try fetchSavingsGoals(context).map { ($0.id, $0) })
            try upsertGoal(row, context: context, walletByID: walletByID, goalByID: &goalByID)
        case .recurringBillPlan(let row):
            var recurringByID = Dictionary(uniqueKeysWithValues: try fetchRecurringBillPlans(context).map { ($0.id, $0) })
            try upsertRecurringBill(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                recurringByID: &recurringByID
            )
        case .installmentPlan(let row):
            var installmentByID = Dictionary(uniqueKeysWithValues: try fetchInstallmentPlans(context).map { ($0.id, $0) })
            try upsertInstallment(row, context: context, walletByID: walletByID, installmentByID: &installmentByID)
        case .dueOccurrence(let row):
            var occurrenceByID = Dictionary(uniqueKeysWithValues: try fetchDueOccurrences(context).map { ($0.id, $0) })
            try upsertDueOccurrence(row, context: context, occurrenceByID: &occurrenceByID)
        }

        try context.save()
    }

    static func mergeAccessibleTransactions(
        _ rows: [RemoteLedgerTransaction],
        protectedRecordIDs: Set<String>,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let wallets = try fetchWallets(context)
        let categories = try fetchCategories(context)
        let transactions = try fetchTransactions(context)
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let audits = try TransactionAuditStore.auditMap(from: fetchTransactionAudits(context))
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })

        for row in rows {
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

            if row.syncVersion > localTransaction.remoteVersion,
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
                    in: container
                )
            }

            try upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        }

        try context.save()
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
        try context.save()
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
        let context = ModelContext(container)
        let activeTransactions = try fetchTransactions(context)
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }
                return $0.createdAt < $1.createdAt
            }

        var duplicates: [MistiaSyncPossibleDuplicate] = []

        for index in activeTransactions.indices {
            let lhs = activeTransactions[index]
            guard index + 1 < activeTransactions.count else { continue }
            for rhs in activeTransactions[(index + 1)...] {
                let secondsApart = abs(lhs.occurredAt.timeIntervalSince(rhs.occurredAt))
                if secondsApart > 86_400 { break }
                guard lhs.id != rhs.id else { continue }
                guard lhs.amountMinor == rhs.amountMinor else { continue }
                guard lhs.primaryKindRawValue == rhs.primaryKindRawValue else { continue }
                guard lhs.sourceWallet?.id == rhs.sourceWallet?.id else { continue }

                let lhsText = [lhs.title, lhs.note ?? ""].joined(separator: " ").normalizedForDuplicateCheck
                let rhsText = [rhs.title, rhs.note ?? ""].joined(separator: " ").normalizedForDuplicateCheck
                let reason: MistiaSyncPossibleDuplicateReason = (lhsText == rhsText || lhsText.isEmpty || rhsText.isEmpty)
                    ? .sameDaySameAmountSameWallet
                    : (lhsText.hasCommonTokens(with: rhsText) ? .sameDaySameAmountSameWalletSimilarText : .sameDaySameAmountSameWallet)

                duplicates.append(
                    MistiaSyncPossibleDuplicate(
                        id: [lhs.id.uuidString.lowercased(), rhs.id.uuidString.lowercased()].sorted().joined(separator: ":"),
                        firstTransactionID: lhs.id,
                        secondTransactionID: rhs.id,
                        reason: reason
                    )
                )
            }
        }

        return duplicates
    }

    static func clearAllData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearAllData(context: context)
    }

    static func clearLocalDeviceLiveData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearLocalDeviceLiveData(context: context)
    }

    static func clearLocalDeviceLiveData(context: ModelContext) throws {
        try clearAllData(context: context)
        try MistiaNotificationStore.clearAll(in: context)
    }

    static func clearAllProfileData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearAllBackupRestorableData(context: context)
    }

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
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
        let goalOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
        let recurringOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let installmentOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)

        let wallets = try fetchWallets(context).filter { $0.deletedAt == nil }
        let creditCardProfiles = try fetchCreditCardProfiles(context).filter { $0.deletedAt == nil }
        let categories = try fetchCategories(context).filter { $0.deletedAt == nil }
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
                    categoryID: recurringBillCategoryID(for: recurring, categories: categories)
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

    private static func clearAllData(context: ModelContext) throws {
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

    private static func clearAllBackupRestorableData(context: ModelContext) throws {
        try clearAllData(context: context)

        for profile in try context.fetch(FetchDescriptor<UserAccountProfile>()) {
            context.delete(profile)
        }

        try context.save()
    }

    private static func clearBackupOperationalState(context: ModelContext) throws {
        for record in try fetchConflicts(context) {
            context.delete(record)
        }

        try context.save()
    }

    private static func upsertBackupUserProfiles(
        _ rows: [MistiaBackupUserAccountProfileV1],
        context: ModelContext
    ) throws {
        let existingProfiles = try context.fetch(FetchDescriptor<UserAccountProfile>())
        var profilesByUserID = Dictionary(uniqueKeysWithValues: existingProfiles.map { ($0.userID, $0) })

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

    private static func upsertBackupOwnershipScopes(
        _ rows: [MistiaBackupOwnedRecordScopeV1],
        context: ModelContext
    ) throws {
        let existingScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        var scopesByID = Dictionary(uniqueKeysWithValues: existingScopes.map { ($0.id, $0) })

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

    private static func upsertBackupTransactionAudits(
        _ rows: [MistiaBackupTransactionAuditRecordV1],
        context: ModelContext
    ) throws {
        let existingAudits = try fetchTransactionAudits(context)
        var auditsByTransactionID = Dictionary(uniqueKeysWithValues: existingAudits.map { ($0.transactionID, $0) })

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
            let key = "\(Record.syncEntity.rawValue):\(record.id.uuidString)"
            guard !protectedRecordIDs.contains(key) else { continue }
            context.delete(record)
        }
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
        categoryByID: inout [UUID: TransactionCategory]
    ) throws {
        if let existing = categoryByID[row.id],
           shouldPreserveLocalActiveSystemCategory(existing, over: row) {
            return
        }

        let category = categoryByID[row.id] ?? TransactionCategory(
            id: row.id,
            name: row.name,
            kind: TransactionCategoryKind(rawValue: row.kindRawValue) ?? .expense,
            iconSymbolName: row.iconSymbolName,
            iconColorHex: row.iconColorHex,
            isFavorite: row.isFavorite,
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

        category.name = row.name
        category.kind = TransactionCategoryKind(rawValue: row.kindRawValue) ?? .expense
        category.iconSymbolName = row.iconSymbolName
        category.iconColorHex = row.iconColorHex
        category.isFavorite = row.isFavorite
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

    private static func shouldPreserveLocalActiveSystemCategory(
        _ category: TransactionCategory,
        over row: RemoteTransactionCategory
    ) -> Bool {
        guard category.isSystem || row.isSystem else { return false }
        guard category.deletedAt == nil else { return false }
        guard category.updatedAt > row.updatedAt else { return false }
        return isActiveSystemDefaultCategory(rawSystemKey: category.systemKey ?? row.systemKey)
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
        transaction.occurredAt = row.occurredAt
        transaction.createdAt = row.createdAt
        transaction.updatedAt = row.updatedAt
        transaction.deletedAt = row.deletedAt
        transaction.remoteVersion = row.syncVersion
        transaction.counterpartyName = row.counterpartyName
        transaction.normalizedCounterpartyKey = row.normalizedCounterpartyKey
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

    private static func upsertBudget(
        _ row: RemoteBudgetPlan,
        context: ModelContext,
        categoryByID: [UUID: TransactionCategory],
        budgetByID: inout [UUID: BudgetPlan]
    ) throws {
        let budget = budgetByID[row.id] ?? BudgetPlan(
            id: row.id,
            category: row.categoryID.flatMap { categoryByID[$0] },
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
        let plan = recurringByID[row.id] ?? RecurringBillPlan(
            id: row.id,
            name: row.name,
            iconSymbolName: normalizedIconSymbolName,
            category: resolvedCategory,
            amountMinor: row.amountMinor,
            dueDay: row.dueDay,
            frequencyMonths: row.frequencyMonths,
            paymentWallet: row.paymentWalletID.flatMap { walletByID[$0] },
            currencyCode: row.currencyCode,
            isArchived: row.isArchived,
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
        plan.frequencyMonths = row.frequencyMonths
        plan.paymentWallet = row.paymentWalletID.flatMap { walletByID[$0] }
        plan.currencyCode = row.currencyCode
        plan.isArchived = row.isArchived
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

    private static func fetchWallets(_ context: ModelContext) throws -> [LedgerWallet] {
        try context.fetch(FetchDescriptor<LedgerWallet>())
    }

    private static func fetchCreditCardProfiles(_ context: ModelContext) throws -> [CreditCardProfile] {
        try context.fetch(FetchDescriptor<CreditCardProfile>())
    }

    private static func fetchCategories(_ context: ModelContext) throws -> [TransactionCategory] {
        try context.fetch(FetchDescriptor<TransactionCategory>())
    }

    private static func fetchTransactions(_ context: ModelContext) throws -> [LedgerTransaction] {
        try context.fetch(FetchDescriptor<LedgerTransaction>())
    }

    private static func fetchTransactionAudits(_ context: ModelContext) throws -> [TransactionAuditRecord] {
        try context.fetch(FetchDescriptor<TransactionAuditRecord>())
    }

    private static func fetchBudgetPlans(_ context: ModelContext) throws -> [BudgetPlan] {
        try context.fetch(FetchDescriptor<BudgetPlan>())
    }

    private static func fetchSavingsGoals(_ context: ModelContext) throws -> [SavingsGoal] {
        try context.fetch(FetchDescriptor<SavingsGoal>())
    }

    private static func fetchRecurringBillPlans(_ context: ModelContext) throws -> [RecurringBillPlan] {
        try context.fetch(FetchDescriptor<RecurringBillPlan>())
    }

    private static func recurringBillCategoryID(
        for plan: RecurringBillPlan,
        categories: [TransactionCategory]
    ) -> UUID? {
        if let categoryID = plan.category?.id {
            return categoryID
        }

        guard let systemKey = MistiaSystemCategoryKey.allCases.first(where: {
            $0.iconSymbolName == plan.iconSymbolName
        }) else {
            return nil
        }

        let matchingCategory = categories.first { category in
            guard category.deletedAt == nil else { return false }
            return category.systemKey == systemKey.rawValue
        }
        return matchingCategory?.id
    }

    private static func supplementalCategoriesForUpload(
        userID: UUID,
        baseSnapshot: MistiaRemoteSnapshot,
        from container: ModelContainer
    ) throws -> [RemoteTransactionCategory] {
        let context = ModelContext(container)
        let categories = try fetchCategories(context)
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var includedIDs = Set(baseSnapshot.categories.map(\.id))
        var queuedIDs: Set<UUID> = []
        var pendingIDs: [UUID] = []

        func queueCategoryID(_ id: UUID?) {
            guard let id else { return }
            guard !includedIDs.contains(id), !queuedIDs.contains(id) else { return }
            queuedIDs.insert(id)
            pendingIDs.append(id)
        }

        for row in baseSnapshot.transactions where row.deletedAt == nil {
            queueCategoryID(row.categoryID)
        }

        for row in baseSnapshot.budgetPlans where row.deletedAt == nil {
            queueCategoryID(row.categoryID)
        }

        for row in baseSnapshot.recurringBillPlans where row.deletedAt == nil {
            queueCategoryID(row.categoryID)
        }

        for row in baseSnapshot.categories where row.deletedAt == nil {
            queueCategoryID(row.parentCategoryID)
        }

        var supplemental: [RemoteTransactionCategory] = []
        var index = 0

        while index < pendingIDs.count {
            let categoryID = pendingIDs[index]
            index += 1

            guard let category = categoryByID[categoryID] else { continue }
            guard category.deletedAt == nil else {
                continue
            }

            includedIDs.insert(categoryID)
            supplemental.append(RemoteTransactionCategory(local: category, userID: userID))
            queueCategoryID(category.parentCategory?.id)
        }

        return supplemental
    }

    private static func fetchInstallmentPlans(_ context: ModelContext) throws -> [InstallmentPlan] {
        try context.fetch(FetchDescriptor<InstallmentPlan>())
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
        self.userID = userID
        self.id = category.id
        self.name = category.name
        self.kindRawValue = category.kindRawValue
        self.iconSymbolName = category.iconSymbolName
        self.iconColorHex = category.iconColorHex
        self.isFavorite = category.isFavorite
        self.parentCategoryID = category.parentCategory?.id
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
        self.occurredAt = transaction.occurredAt
        self.createdAt = transaction.createdAt
        self.updatedAt = transaction.updatedAt
        self.createdByUserID = createdByUserID
        self.lastModifiedByUserID = auditRecord?.lastModifiedByUserID ?? createdByUserID
        self.counterpartyName = transaction.counterpartyName
        self.normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        self.sourceWalletID = transaction.sourceWallet?.id
        self.destinationWalletID = transaction.destinationWallet?.id
        self.categoryID = transaction.category?.id
        self.deletedAt = transaction.deletedAt
        self.isArchived = transaction.isArchived
        self.archivedAt = transaction.archivedAt
        self.syncVersion = max(transaction.remoteVersion, 1)
        self.lastModifiedByDeviceID = nil
    }
}

private extension RemoteBudgetPlan {
    init(local plan: BudgetPlan, userID: UUID) {
        self.init(
            userID: userID,
            id: plan.id,
            categoryID: plan.category?.id,
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
        self.init(
            userID: userID,
            id: plan.id,
            name: plan.name,
            iconSymbolName: plan.iconSymbolName,
            categoryID: categoryID,
            amountMinor: plan.amountMinor,
            dueDay: plan.dueDay,
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

private enum MistiaBackupAvatarStore {
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
