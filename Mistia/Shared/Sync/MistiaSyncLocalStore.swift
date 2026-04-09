import Foundation
import SwiftData

enum MistiaSyncLocalStore {
    static func totalObjectCount(in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        return try fetchWallets(context).count
            + fetchCreditCardProfiles(context).count
            + fetchCategories(context).count
            + fetchTransactions(context).count
            + fetchBudgetPlans(context).count
            + fetchSavingsGoals(context).count
            + fetchRecurringBillPlans(context).count
            + fetchInstallmentPlans(context).count
            + fetchDueOccurrences(context).count
    }

    static func exportSnapshot(
        for userID: UUID,
        from container: ModelContainer
    ) throws -> MistiaRemoteSnapshot {
        let context = ModelContext(container)

        return MistiaRemoteSnapshot(
            wallets: try fetchWallets(context).map { RemoteLedgerWallet(local: $0, userID: userID) },
            creditCardProfiles: try fetchCreditCardProfiles(context).map { RemoteCreditCardProfile(local: $0, userID: userID) },
            categories: try fetchCategories(context).map { RemoteTransactionCategory(local: $0, userID: userID) },
            transactions: try fetchTransactions(context).map { RemoteLedgerTransaction(local: $0, userID: userID) },
            budgetPlans: try fetchBudgetPlans(context).map { RemoteBudgetPlan(local: $0, userID: userID) },
            savingsGoals: try fetchSavingsGoals(context).map { RemoteSavingsGoal(local: $0, userID: userID) },
            recurringBillPlans: try fetchRecurringBillPlans(context).map { RemoteRecurringBillPlan(local: $0, userID: userID) },
            installmentPlans: try fetchInstallmentPlans(context).map { RemoteInstallmentPlan(local: $0, userID: userID) },
            dueOccurrences: try fetchDueOccurrences(context).map { RemoteDueOccurrenceRecord(local: $0, userID: userID) }
        )
    }

    static func exportRecord(
        for mutation: MistiaSyncMutation,
        userID: UUID,
        from container: ModelContainer
    ) throws -> MistiaSyncUploadRecord? {
        let context = ModelContext(container)

        switch mutation.entity {
        case .wallet:
            guard let wallet = try fetchWallets(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .wallet(RemoteLedgerWallet(local: wallet, userID: userID))
        case .creditCardProfile:
            guard let profile = try fetchCreditCardProfiles(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .creditCardProfile(RemoteCreditCardProfile(local: profile, userID: userID))
        case .category:
            guard let category = try fetchCategories(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .category(RemoteTransactionCategory(local: category, userID: userID))
        case .transaction:
            guard let transaction = try fetchTransactions(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .transaction(RemoteLedgerTransaction(local: transaction, userID: userID))
        case .budgetPlan:
            guard let plan = try fetchBudgetPlans(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .budgetPlan(RemoteBudgetPlan(local: plan, userID: userID))
        case .savingsGoal:
            guard let goal = try fetchSavingsGoals(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .savingsGoal(RemoteSavingsGoal(local: goal, userID: userID))
        case .recurringBillPlan:
            guard let plan = try fetchRecurringBillPlans(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .recurringBillPlan(RemoteRecurringBillPlan(local: plan, userID: userID))
        case .installmentPlan:
            guard let plan = try fetchInstallmentPlans(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .installmentPlan(RemoteInstallmentPlan(local: plan, userID: userID))
        case .dueOccurrenceRecord:
            guard let record = try fetchDueOccurrences(context).first(where: { $0.id == mutation.recordID }) else {
                return nil
            }
            return .dueOccurrence(RemoteDueOccurrenceRecord(local: record, userID: userID))
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
            upsertWallet(row, context: context, walletByID: &walletByID)
        }

        for row in snapshot.categories {
            upsertCategory(row, context: context, categoryByID: &categoryByID)
        }

        for row in snapshot.categories {
            applyCategoryHierarchy(row, categoryByID: categoryByID)
        }

        for row in snapshot.creditCardProfiles {
            upsertCreditProfile(
                row,
                context: context,
                walletByID: walletByID,
                profileByID: &profileByID
            )
        }

        for row in snapshot.transactions {
            upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        }

        for row in snapshot.budgetPlans {
            upsertBudget(row, context: context, categoryByID: categoryByID, budgetByID: &budgetByID)
        }

        for row in snapshot.savingsGoals {
            upsertGoal(row, context: context, walletByID: walletByID, goalByID: &goalByID)
        }

        for row in snapshot.recurringBillPlans {
            upsertRecurringBill(row, context: context, walletByID: walletByID, recurringByID: &recurringByID)
        }

        for row in snapshot.installmentPlans {
            upsertInstallment(row, context: context, walletByID: walletByID, installmentByID: &installmentByID)
        }

        for row in snapshot.dueOccurrences {
            upsertDueOccurrence(row, context: context, occurrenceByID: &occurrenceByID)
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
            upsertWallet(row, context: context, walletByID: &walletByID)
        case .creditCardProfile(let row):
            var profileByID = Dictionary(uniqueKeysWithValues: try fetchCreditCardProfiles(context).map { ($0.id, $0) })
            upsertCreditProfile(row, context: context, walletByID: walletByID, profileByID: &profileByID)
        case .category(let row):
            upsertCategory(row, context: context, categoryByID: &categoryByID)
            applyCategoryHierarchy(row, categoryByID: categoryByID)
        case .transaction(let row):
            var transactionByID = Dictionary(uniqueKeysWithValues: try fetchTransactions(context).map { ($0.id, $0) })
            upsertTransaction(
                row,
                context: context,
                walletByID: walletByID,
                categoryByID: categoryByID,
                transactionByID: &transactionByID
            )
        case .budgetPlan(let row):
            var budgetByID = Dictionary(uniqueKeysWithValues: try fetchBudgetPlans(context).map { ($0.id, $0) })
            upsertBudget(row, context: context, categoryByID: categoryByID, budgetByID: &budgetByID)
        case .savingsGoal(let row):
            var goalByID = Dictionary(uniqueKeysWithValues: try fetchSavingsGoals(context).map { ($0.id, $0) })
            upsertGoal(row, context: context, walletByID: walletByID, goalByID: &goalByID)
        case .recurringBillPlan(let row):
            var recurringByID = Dictionary(uniqueKeysWithValues: try fetchRecurringBillPlans(context).map { ($0.id, $0) })
            upsertRecurringBill(row, context: context, walletByID: walletByID, recurringByID: &recurringByID)
        case .installmentPlan(let row):
            var installmentByID = Dictionary(uniqueKeysWithValues: try fetchInstallmentPlans(context).map { ($0.id, $0) })
            upsertInstallment(row, context: context, walletByID: walletByID, installmentByID: &installmentByID)
        case .dueOccurrence(let row):
            var occurrenceByID = Dictionary(uniqueKeysWithValues: try fetchDueOccurrences(context).map { ($0.id, $0) })
            upsertDueOccurrence(row, context: context, occurrenceByID: &occurrenceByID)
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

    private static func clearAllData(context: ModelContext) throws {
        for record in try fetchConflicts(context) {
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
    ) {
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
    }

    private static func upsertCategory(
        _ row: RemoteTransactionCategory,
        context: ModelContext,
        categoryByID: inout [UUID: TransactionCategory]
    ) {
        let category = categoryByID[row.id] ?? TransactionCategory(
            id: row.id,
            name: row.name,
            kind: TransactionCategoryKind(rawValue: row.kindRawValue) ?? .expense,
            iconSymbolName: row.iconSymbolName,
            iconColorHex: row.iconColorHex,
            hierarchyRole: row.hierarchyRoleRawValue.flatMap(TransactionCategoryHierarchyRole.init(rawValue:)),
            systemKey: row.systemKey,
            isSystem: row.isSystem,
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
        category.hierarchyRoleRawValue = row.hierarchyRoleRawValue
        category.systemKey = row.systemKey
        category.isSystem = row.isSystem
        category.sortOrder = row.sortOrder
        category.isArchived = row.isArchived
        category.archivedAt = row.archivedAt
        category.createdAt = row.createdAt
        category.updatedAt = row.updatedAt
        category.deletedAt = row.deletedAt
        category.remoteVersion = row.syncVersion
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
    ) {
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
    }

    private static func upsertTransaction(
        _ row: RemoteLedgerTransaction,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        categoryByID: [UUID: TransactionCategory],
        transactionByID: inout [UUID: LedgerTransaction]
    ) {
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
    }

    private static func upsertBudget(
        _ row: RemoteBudgetPlan,
        context: ModelContext,
        categoryByID: [UUID: TransactionCategory],
        budgetByID: inout [UUID: BudgetPlan]
    ) {
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
    }

    private static func upsertGoal(
        _ row: RemoteSavingsGoal,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        goalByID: inout [UUID: SavingsGoal]
    ) {
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
    }

    private static func upsertRecurringBill(
        _ row: RemoteRecurringBillPlan,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        recurringByID: inout [UUID: RecurringBillPlan]
    ) {
        let plan = recurringByID[row.id] ?? RecurringBillPlan(
            id: row.id,
            name: row.name,
            iconSymbolName: row.iconSymbolName,
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
        plan.iconSymbolName = row.iconSymbolName
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
    }

    private static func upsertInstallment(
        _ row: RemoteInstallmentPlan,
        context: ModelContext,
        walletByID: [UUID: LedgerWallet],
        installmentByID: inout [UUID: InstallmentPlan]
    ) {
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
    }

    private static func upsertDueOccurrence(
        _ row: RemoteDueOccurrenceRecord,
        context: ModelContext,
        occurrenceByID: inout [UUID: DueOccurrenceRecord]
    ) {
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

    private static func fetchBudgetPlans(_ context: ModelContext) throws -> [BudgetPlan] {
        try context.fetch(FetchDescriptor<BudgetPlan>())
    }

    private static func fetchSavingsGoals(_ context: ModelContext) throws -> [SavingsGoal] {
        try context.fetch(FetchDescriptor<SavingsGoal>())
    }

    private static func fetchRecurringBillPlans(_ context: ModelContext) throws -> [RecurringBillPlan] {
        try context.fetch(FetchDescriptor<RecurringBillPlan>())
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
        self.init(
            userID: userID,
            id: category.id,
            name: category.name,
            kindRawValue: category.kindRawValue,
            iconSymbolName: category.iconSymbolName,
            iconColorHex: category.iconColorHex,
            parentCategoryID: category.parentCategory?.id,
            hierarchyRoleRawValue: category.hierarchyRoleRawValue,
            systemKey: category.systemKey,
            isSystem: category.isSystem,
            sortOrder: category.sortOrder,
            isArchived: category.isArchived,
            archivedAt: category.archivedAt,
            createdAt: category.createdAt,
            updatedAt: category.updatedAt,
            deletedAt: category.deletedAt,
            syncVersion: max(category.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
    }
}

private extension RemoteLedgerTransaction {
    init(local transaction: LedgerTransaction, userID: UUID) {
        self.init(
            userID: userID,
            id: transaction.id,
            primaryKindRawValue: transaction.primaryKindRawValue,
            transferSubtypeRawValue: transaction.transferSubtypeRawValue,
            debtIntentRawValue: transaction.debtIntentRawValue,
            entryStatusRawValue: transaction.entryStatusRawValue,
            title: transaction.title,
            note: transaction.note,
            amountMinor: transaction.amountMinor,
            occurredAt: transaction.occurredAt,
            createdAt: transaction.createdAt,
            updatedAt: transaction.updatedAt,
            counterpartyName: transaction.counterpartyName,
            normalizedCounterpartyKey: transaction.normalizedCounterpartyKey,
            sourceWalletID: transaction.sourceWallet?.id,
            destinationWalletID: transaction.destinationWallet?.id,
            categoryID: transaction.category?.id,
            deletedAt: transaction.deletedAt,
            isArchived: transaction.isArchived,
            archivedAt: transaction.archivedAt,
            syncVersion: max(transaction.remoteVersion, 1),
            lastModifiedByDeviceID: nil
        )
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
    init(local plan: RecurringBillPlan, userID: UUID) {
        self.init(
            userID: userID,
            id: plan.id,
            name: plan.name,
            iconSymbolName: plan.iconSymbolName,
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
