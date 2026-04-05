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

    static func replaceLocalData(
        with snapshot: MistiaRemoteSnapshot,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        try clearAllData(context: context)

        var walletByID: [UUID: LedgerWallet] = [:]
        var categoryByID: [UUID: TransactionCategory] = [:]

        for row in snapshot.activeWallets {
            let wallet = LedgerWallet(
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
                updatedAt: row.updatedAt
            )
            context.insert(wallet)
            walletByID[row.id] = wallet
        }

        for row in snapshot.activeCategories {
            let category = TransactionCategory(
                id: row.id,
                name: row.name,
                kind: TransactionCategoryKind(rawValue: row.kindRawValue) ?? .expense,
                iconSymbolName: row.iconSymbolName,
                iconColorHex: row.iconColorHex,
                systemKey: row.systemKey,
                isSystem: row.isSystem,
                sortOrder: row.sortOrder,
                isArchived: row.isArchived,
                archivedAt: row.archivedAt,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
            context.insert(category)
            categoryByID[row.id] = category
        }

        for row in snapshot.activeCreditCardProfiles {
            let profile = CreditCardProfile(
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
                wallet: row.walletID.flatMap { walletByID[$0] },
                paymentSourceWallet: row.paymentSourceWalletID.flatMap { walletByID[$0] }
            )
            if let walletID = row.walletID, let wallet = walletByID[walletID] {
                wallet.creditCardProfile = profile
            }
            context.insert(profile)
        }

        for row in snapshot.activeTransactions {
            let transaction = LedgerTransaction(
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
                sourceWallet: row.sourceWalletID.flatMap { walletByID[$0] },
                destinationWallet: row.destinationWalletID.flatMap { walletByID[$0] },
                category: row.categoryID.flatMap { categoryByID[$0] },
                counterpartyName: row.counterpartyName,
                normalizedCounterpartyKey: row.normalizedCounterpartyKey,
                isArchived: row.isArchived,
                archivedAt: row.archivedAt
            )
            context.insert(transaction)
        }

        for row in snapshot.activeBudgetPlans {
            let plan = BudgetPlan(
                id: row.id,
                category: row.categoryID.flatMap { categoryByID[$0] },
                monthAnchor: row.monthAnchor,
                limitMinor: row.limitMinor,
                rolloverEnabled: row.rolloverEnabled,
                currencyCode: row.currencyCode,
                isArchived: row.isArchived,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
            context.insert(plan)
        }

        for row in snapshot.activeSavingsGoals {
            let goal = SavingsGoal(
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
                updatedAt: row.updatedAt
            )
            context.insert(goal)
        }

        for row in snapshot.activeRecurringBillPlans {
            let plan = RecurringBillPlan(
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
                updatedAt: row.updatedAt
            )
            context.insert(plan)
        }

        for row in snapshot.activeInstallmentPlans {
            let plan = InstallmentPlan(
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
                updatedAt: row.updatedAt
            )
            context.insert(plan)
        }

        for row in snapshot.activeDueOccurrences {
            let record = DueOccurrenceRecord(
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
                updatedAt: row.updatedAt
            )
            context.insert(record)
        }

        try context.save()
    }

    static func clearAllData(in container: ModelContainer) throws {
        let context = ModelContext(container)
        try clearAllData(context: context)
    }

    private static func clearAllData(context: ModelContext) throws {
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
            deletedAt: nil
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
            deletedAt: nil
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
            systemKey: category.systemKey,
            isSystem: category.isSystem,
            sortOrder: category.sortOrder,
            isArchived: category.isArchived,
            archivedAt: category.archivedAt,
            createdAt: category.createdAt,
            updatedAt: category.updatedAt,
            deletedAt: nil
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
            deletedAt: nil,
            isArchived: transaction.isArchived,
            archivedAt: transaction.archivedAt
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
            deletedAt: nil
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
            deletedAt: nil
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
            deletedAt: nil
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
            deletedAt: nil
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
            deletedAt: nil
        )
    }
}
