import SwiftData
import SwiftUI

struct PlanningBudgetEditorTarget: Identifiable {
    let id = UUID()
    let budget: BudgetPlan?
    let selectedMonth: Date
    let preferredParentCategoryID: UUID?
}

enum PlanningBudgetEditorScope {
    static func visibleCategories(
        _ categories: [TransactionCategory],
        categoryOwnerMap: [UUID: UUID],
        targetOwnerUserID: UUID?,
        signedInUserID: UUID?
    ) -> [TransactionCategory] {
        MistiaRecordOwnershipStore.visibleRecords(
            categories,
            entity: .category,
            ownerMap: categoryOwnerMap,
            subjectUserID: targetOwnerUserID,
            signedInUserID: signedInUserID
        )
    }

    static func visibleBudgets(
        _ budgets: [BudgetPlan],
        budgetOwnerMap: [UUID: UUID],
        targetOwnerUserID: UUID?,
        signedInUserID: UUID?
    ) -> [BudgetPlan] {
        MistiaRecordOwnershipStore.visibleRecords(
            budgets,
            entity: .budgetPlan,
            ownerMap: budgetOwnerMap,
            subjectUserID: targetOwnerUserID,
            signedInUserID: signedInUserID
        )
    }
}

extension TransactionCategory {
    var planningFamilyBudgetSpendingScope: PlanningFamilyBudgetSpendingCategoryScope {
        PlanningFamilyBudgetSpendingCategoryScope(
            categoryName: localizedDisplayName,
            categoryParentName: parentCategory?.localizedDisplayName,
            categoryIsParent: isParentCategory,
            familyBudgetSpendingEnabled: familyBudgetSpendingEnabled
        )
    }
}

struct PlanningGoalEditorTarget: Identifiable {
    let id = UUID()
    let goal: SavingsGoal?
}

struct PlanningBillEditorTarget: Identifiable {
    let id = UUID()
    let plan: RecurringBillPlan?
    let dueItem: PlanningRecurringDueSnapshot?
    let selectedMonth: Date
}

@MainActor
enum PlanningBillPauseActions {
    static func pause(
        _ plan: RecurringBillPlan,
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now
    ) throws {
        guard plan.scheduleKind == .recurring else { return }
        plan.isPaused = true
        plan.pausedAt = referenceDate
        plan.resumeStartMonth = nil
        plan.updatedAt = referenceDate

        try modelContext.save()
        MistiaRecurringBillMaintenance.resolveNotifications(for: plan.id, modelContext: modelContext)
        sessionStore.recordUpsert(
            entity: .recurringBillPlan,
            recordID: plan.id,
            modifiedAt: referenceDate
        )
    }

    static func resume(
        _ plan: RecurringBillPlan,
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) throws {
        guard plan.scheduleKind == .recurring else { return }
        plan.isPaused = false
        plan.pausedAt = nil
        plan.resumeStartMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        plan.updatedAt = referenceDate

        try modelContext.save()
        sessionStore.recordUpsert(
            entity: .recurringBillPlan,
            recordID: plan.id,
            modifiedAt: referenceDate
        )

        Task { @MainActor in
            await MistiaRecurringBillMaintenance.run(
                modelContext: modelContext,
                sessionStore: sessionStore,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }
}

struct PlanningInstallmentEditorTarget: Identifiable {
    let id = UUID()
    let plan: InstallmentPlan?
    let dueItem: PlanningRecurringDueSnapshot?
    let selectedMonth: Date
}

struct PlanningCreditCardEditorTarget: Identifiable {
    let id = UUID()
    let wallet: LedgerWallet?
    let dueItem: PlanningCreditCardDueSnapshot?
    let selectedMonth: Date
}

enum PlanningPersistenceError: LocalizedError {
    case missingWallet
    case missingDestinationWallet
    case missingCategory
    case insufficientWalletBalance

    var errorDescription: String? {
        switch self {
        case .missingWallet:
            L10n.planning.planning.aMatchingPaymentWalletCouldNotBe
        case .missingDestinationWallet:
            L10n.planning.planning.theDestinationCreditCardCouldNotBe
        case .missingCategory:
            L10n.planning.planning.theSystemCategoryForThisPaymentCould
        case .insufficientWalletBalance:
            L10n.transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction
        }
    }
}

enum PlanningDueRowTone {
    case normal
    case warning
    case overdue
    case paid
    case skipped

    var color: Color {
        switch self {
        case .normal:
            Color(hex: "#5B7BFF")
        case .warning:
            Color(hex: "#F59B3F")
        case .overdue:
            Color(hex: "#F45C7E")
        case .paid:
            .mint
        case .skipped:
            .secondary
        }
    }
}

struct PlanningSavedDuePayment {
    let transaction: LedgerTransaction
    let occurrenceID: UUID
    let subjectUserID: UUID?
}

struct PlanningUndoneDuePayment {
    let deletedTransactionID: UUID?
    let deletedOccurrenceID: UUID?
}

enum PlanningPersistenceSupport {
    static func saveDuePayment(
        draft: PlanningDuePaymentDraft,
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        selectedMonth: Date,
        scheduledDate: Date,
        wallets: [LedgerWallet],
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext,
        actorUserID: UUID?,
        calendar: Calendar = MistiaCalendar.current
    ) throws -> PlanningSavedDuePayment {
        let now = Date()

        guard let sourceWallet = wallets.first(where: { $0.id == draft.sourceWalletID }) else {
            throw PlanningPersistenceError.missingWallet
        }
        try validateSourceWalletCanCoverPayment(
            sourceWallet: sourceWallet,
            amountMinor: draft.amountMinor,
            wallets: wallets,
            modelContext: modelContext
        )

        let transaction = LedgerTransaction(
            primaryKind: draft.primaryKind,
            transferSubtype: draft.transferSubtype,
            amountMinor: draft.amountMinor,
            occurredAt: now
        )

        transaction.title = draft.title
        transaction.entryStatus = .posted
        transaction.amountMinor = draft.amountMinor
        transaction.occurredAt = now
        transaction.updatedAt = now
        transaction.sourceWallet = sourceWallet

        if let destinationWalletID = draft.destinationWalletID {
            guard let destinationWallet = wallets.first(where: { $0.id == destinationWalletID }) else {
                throw PlanningPersistenceError.missingDestinationWallet
            }
            transaction.destinationWallet = destinationWallet
            transaction.category = nil
        } else if let systemKey = draft.categorySystemKey {
            transaction.destinationWallet = nil
            transaction.category = try MistiaBootstrap.ensureSystemCategory(systemKey, modelContext: modelContext)
        } else {
            throw PlanningPersistenceError.missingCategory
        }

        modelContext.insert(transaction)
        let ownershipScopes = try modelContext.fetch(FetchDescriptor<OwnedRecordScope>())
        let subjectUserID = TransactionAuditStore.resolveOwnerUserID(
            forWalletID: sourceWallet.id,
            ownershipScopes: ownershipScopes
        )
        if let subjectUserID {
            try MistiaRecordOwnershipStore.upsert(
                entity: .transaction,
                recordID: transaction.id,
                ownerUserID: subjectUserID,
                updatedAt: now,
                context: modelContext
            )
        }
        if let createdByUserID = actorUserID ?? subjectUserID {
            try TransactionAuditStore.upsert(
                transactionID: transaction.id,
                createdByUserID: createdByUserID,
                lastModifiedByUserID: actorUserID ?? createdByUserID,
                updatedAt: now,
                context: modelContext
            )
        }
        let occurrence = try upsertOccurrence(
            sourceKind: sourceKind,
            sourceID: sourceID,
            selectedMonth: selectedMonth,
            scheduledDate: scheduledDate,
            amountMinor: draft.amountMinor,
            linkedTransactionID: transaction.id,
            occurrences: occurrences,
            modelContext: modelContext,
            paidAt: now,
            calendar: calendar
        )

        try modelContext.save()
        return PlanningSavedDuePayment(
            transaction: transaction,
            occurrenceID: occurrence.id,
            subjectUserID: subjectUserID
        )
    }

    private static func validateSourceWalletCanCoverPayment(
        sourceWallet: LedgerWallet,
        amountMinor: Int64,
        wallets: [LedgerWallet],
        modelContext: ModelContext
    ) throws {
        guard amountMinor > 0 else { return }

        let sourceWalletID = sourceWallet.id
        let activeTransactions = try modelContext.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in
                    transaction.deletedAt == nil &&
                    (transaction.sourceWallet?.id == sourceWalletID || transaction.destinationWallet?.id == sourceWalletID)
                }
            )
        )
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: wallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: activeTransactions.lazy.map(\.planningRecordSnapshot)
        )
        let sourceSnapshot = TransactionWalletSnapshot(
            id: sourceWallet.id,
            kind: sourceWallet.kind,
            openingBalanceMinor: sourceWallet.openingBalanceMinor
        )
        if sourceWallet.kind == .creditCard {
            let balance = TransactionLogic.creditCardBalance(
                creditLimitMinor: sourceWallet.creditCardProfile?.creditLimitMinor ?? 0,
                wallet: sourceSnapshot,
                balanceIndex: balanceIndex
            )
            guard balance.canCover(amountMinor: amountMinor) else {
                throw PlanningPersistenceError.insufficientWalletBalance
            }
        } else {
            let currentBalance = balanceIndex.balance(for: sourceSnapshot)
            guard currentBalance >= amountMinor else {
                throw PlanningPersistenceError.insufficientWalletBalance
            }
        }
    }

    @discardableResult
    static func saveDueSkip(
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        selectedMonth: Date,
        scheduledDate: Date,
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext,
        actorUserID: UUID?,
        calendar: Calendar = MistiaCalendar.current
    ) throws -> DueOccurrenceRecord {
        let occurrence = try upsertOccurrence(
            sourceKind: sourceKind,
            sourceID: sourceID,
            selectedMonth: selectedMonth,
            scheduledDate: scheduledDate,
            amountMinor: nil,
            linkedTransactionID: nil,
            occurrences: occurrences,
            modelContext: modelContext,
            status: .skipped,
            calendar: calendar
        )
        let now = Date()
        if let actorUserID {
            try MistiaRecordOwnershipStore.upsert(
                entity: .dueOccurrenceRecord,
                recordID: occurrence.id,
                ownerUserID: actorUserID,
                updatedAt: now,
                context: modelContext
            )
        }
        try modelContext.save()
        return occurrence
    }

    @discardableResult
    static func undoDueSkip(
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        selectedMonth: Date,
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext,
        calendar: Calendar = MistiaCalendar.current
    ) throws -> UUID? {
        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)
        let matchingOccurrences = occurrences.filter {
            $0.sourceKind == sourceKind
                && $0.sourceID == sourceID
                && $0.selectedMonthKey == monthKey
                && $0.status == .skipped
        }
        guard let targetRecord = matchingOccurrences.first else { return nil }
        let recordID = targetRecord.id
        for occurrence in matchingOccurrences {
            modelContext.delete(occurrence)
        }
        try modelContext.save()
        return recordID
    }

    @discardableResult
    static func undoDuePayment(
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        selectedMonth: Date,
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext,
        calendar: Calendar = MistiaCalendar.current
    ) throws -> PlanningUndoneDuePayment {
        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)
        let matchingOccurrences = occurrences.filter {
            $0.sourceKind == sourceKind
                && $0.sourceID == sourceID
                && $0.selectedMonthKey == monthKey
                && $0.status == .paid
        }

        var deletedTransactionID: UUID?
        var deletedOccurrenceID: UUID?

        for occurrence in matchingOccurrences {
            deletedOccurrenceID = occurrence.id
            if let txID = occurrence.linkedTransactionID {
                deletedTransactionID = txID
                let txs = try modelContext.fetch(
                    FetchDescriptor<LedgerTransaction>(
                        predicate: #Predicate<LedgerTransaction> { $0.id == txID }
                    )
                )
                for tx in txs {
                    modelContext.delete(tx)
                }
            }
            modelContext.delete(occurrence)
        }

        try modelContext.save()
        return PlanningUndoneDuePayment(
            deletedTransactionID: deletedTransactionID,
            deletedOccurrenceID: deletedOccurrenceID
        )
    }

    @discardableResult
    static func upsertOccurrence(
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        selectedMonth: Date,
        scheduledDate: Date,
        amountMinor: Int64?,
        linkedTransactionID: UUID?,
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext,
        paidAt: Date? = nil,
        status: PlanningDueOccurrenceStatus? = nil,
        calendar: Calendar = MistiaCalendar.current
    ) throws -> DueOccurrenceRecord {
        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)
        let legacyCreditCardDueMonthKey = sourceKind == .creditCard
            ? PlanningLogic.monthKey(for: scheduledDate, calendar: calendar)
            : monthKey
        let now = Date()
        let resolvedStatus: PlanningDueOccurrenceStatus = status ?? (paidAt == nil ? .pending : .paid)
        let matchingOccurrences = occurrences.filter {
            $0.sourceKind == sourceKind
                && $0.sourceID == sourceID
                && (
                    $0.selectedMonthKey == monthKey
                        || (sourceKind == .creditCard && $0.selectedMonthKey == legacyCreditCardDueMonthKey)
                )
        }
        if let existing = matchingOccurrences.first {
            for occurrence in matchingOccurrences {
                occurrence.selectedMonthKey = monthKey
                occurrence.scheduledDate = scheduledDate
                occurrence.amountMinorSnapshot = amountMinor
                occurrence.status = resolvedStatus
                occurrence.paidAt = paidAt
                occurrence.linkedTransactionID = linkedTransactionID
                occurrence.updatedAt = now
            }
            return existing
        } else {
            let record = DueOccurrenceRecord(
                sourceKind: sourceKind,
                sourceID: sourceID,
                selectedMonthKey: monthKey,
                scheduledDate: scheduledDate,
                amountMinorSnapshot: amountMinor,
                status: resolvedStatus,
                paidAt: paidAt,
                linkedTransactionID: linkedTransactionID,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(record)
            return record
        }
    }

    static func deleteOccurrences(
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext
    ) {
        let now = Date()
        occurrences
            .filter { $0.sourceKind == sourceKind && $0.sourceID == sourceID }
            .forEach { occurrence in
                occurrence.markDeleted(at: now)
            }
    }
}

extension BudgetPlan {
    func planningSnapshot(calendar: Calendar = MistiaCalendar.current) -> BudgetPlanSnapshot {
        let snapshotCategoryName = localizedCategoryNameSnapshot()
        let snapshotParentName = localizedCategoryParentNameSnapshot()
        return BudgetPlanSnapshot(
            id: id,
            categoryID: categoryIDSnapshot ?? category?.id,
            categoryName: snapshotCategoryName ?? category?.localizedDisplayName ?? L10n.planning.planning.deletedCategory,
            categoryIconSymbolName: categoryIconSymbolNameSnapshot ?? category?.iconSymbolName ?? "questionmark.circle.fill",
            categoryColorHex: categoryColorHexSnapshot ?? category?.iconColorHex ?? "#8A8A8E",
            limitMinor: limitMinor,
            rolloverEnabled: rolloverEnabled,
            currencyCode: currencyCode,
            monthAnchor: PlanningLogic.startOfMonth(for: monthAnchor, calendar: calendar),
            categoryParentID: categoryParentIDSnapshot ?? category?.parentCategory?.id,
            categoryParentName: snapshotParentName ?? category?.parentCategory?.localizedDisplayName,
            categoryParentIconSymbolName: categoryParentIconSymbolNameSnapshot ?? category?.parentCategory?.iconSymbolName,
            categoryParentColorHex: categoryParentColorHexSnapshot ?? category?.parentCategory?.iconColorHex,
            categoryIsParent: categoryIsParentSnapshotRawValue ?? category?.isParentCategory ?? false,
            includesFamilySpending: includesFamilySpending
        )
    }

    func refreshCategorySnapshot() {
        guard let category else { return }

        categoryIDSnapshot = category.id
        categoryNameSnapshot = category.name
        categoryNameEnglishSnapshot = category.nameEnglish
        categoryNameJapaneseSnapshot = category.nameJapanese
        categoryIconSymbolNameSnapshot = category.iconSymbolName
        categoryColorHexSnapshot = category.iconColorHex
        categoryHierarchyRoleSnapshotRawValue = category.hierarchyRole.rawValue
        categoryIsParentSnapshotRawValue = category.isParentCategory

        if let parent = category.parentCategory {
            categoryParentIDSnapshot = parent.id
            categoryParentNameSnapshot = parent.name
            categoryParentNameEnglishSnapshot = parent.nameEnglish
            categoryParentNameJapaneseSnapshot = parent.nameJapanese
            categoryParentIconSymbolNameSnapshot = parent.iconSymbolName
            categoryParentColorHexSnapshot = parent.iconColorHex
            categoryPathSnapshot = "\(parent.name) / \(category.name)"
            categoryPathEnglishSnapshot = joinedCategoryPath(
                parent: parent.nameEnglish,
                child: category.nameEnglish
            )
            categoryPathJapaneseSnapshot = joinedCategoryPath(
                parent: parent.nameJapanese,
                child: category.nameJapanese
            )
        } else {
            categoryParentIDSnapshot = nil
            categoryParentNameSnapshot = nil
            categoryParentNameEnglishSnapshot = nil
            categoryParentNameJapaneseSnapshot = nil
            categoryParentIconSymbolNameSnapshot = nil
            categoryParentColorHexSnapshot = nil
            categoryPathSnapshot = category.name
            categoryPathEnglishSnapshot = category.nameEnglish
            categoryPathJapaneseSnapshot = category.nameJapanese
        }
    }

    func localizedCategoryPathSnapshot(
        for language: MistiaAppLanguage = .current
    ) -> String? {
        switch language {
        case .vietnamese:
            return nonBlankSnapshot(categoryPathSnapshot) ?? localizedCategoryNameSnapshot(for: language)
        case .english:
            return nonBlankSnapshot(categoryPathEnglishSnapshot)
                ?? nonBlankSnapshot(categoryPathSnapshot)
                ?? localizedCategoryNameSnapshot(for: language)
        case .japanese:
            return nonBlankSnapshot(categoryPathJapaneseSnapshot)
                ?? nonBlankSnapshot(categoryPathSnapshot)
                ?? localizedCategoryNameSnapshot(for: language)
        }
    }

    private func localizedCategoryNameSnapshot(
        for language: MistiaAppLanguage = .current
    ) -> String? {
        switch language {
        case .vietnamese:
            return nonBlankSnapshot(categoryNameSnapshot)
        case .english:
            return nonBlankSnapshot(categoryNameEnglishSnapshot) ?? nonBlankSnapshot(categoryNameSnapshot)
        case .japanese:
            return nonBlankSnapshot(categoryNameJapaneseSnapshot) ?? nonBlankSnapshot(categoryNameSnapshot)
        }
    }

    private func localizedCategoryParentNameSnapshot(
        for language: MistiaAppLanguage = .current
    ) -> String? {
        switch language {
        case .vietnamese:
            return nonBlankSnapshot(categoryParentNameSnapshot)
        case .english:
            return nonBlankSnapshot(categoryParentNameEnglishSnapshot) ?? nonBlankSnapshot(categoryParentNameSnapshot)
        case .japanese:
            return nonBlankSnapshot(categoryParentNameJapaneseSnapshot) ?? nonBlankSnapshot(categoryParentNameSnapshot)
        }
    }

    private func joinedCategoryPath(parent: String?, child: String?) -> String? {
        guard let parent = nonBlankSnapshot(parent),
              let child = nonBlankSnapshot(child)
        else {
            return nil
        }
        return "\(parent) / \(child)"
    }

    private func nonBlankSnapshot(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

nonisolated enum PlanningBudgetSnapshotMaintenance {
    @discardableResult
    static func populateMissingCategorySnapshots(
        modelContext: ModelContext
    ) throws -> [MistiaBootstrapSyncMutation] {
        let missingIDDescriptor = FetchDescriptor<BudgetPlan>(
            predicate: #Predicate { budget in
                budget.deletedAt == nil && budget.categoryIDSnapshot == nil
            }
        )
        let missingNameDescriptor = FetchDescriptor<BudgetPlan>(
            predicate: #Predicate { budget in
                budget.deletedAt == nil && budget.categoryNameSnapshot == nil
            }
        )
        var budgets = try modelContext.fetch(missingIDDescriptor)
        var fetchedBudgetIDs = Set(budgets.map(\.id))
        for budget in try modelContext.fetch(missingNameDescriptor)
            where fetchedBudgetIDs.insert(budget.id).inserted {
            budgets.append(budget)
        }
        let now = Date()
        var mutations: [MistiaBootstrapSyncMutation] = []
        mutations.reserveCapacity(budgets.count)

        for budget in budgets {
            guard budget.category != nil else { continue }

            budget.refreshCategorySnapshot()
            budget.updatedAt = now
            mutations.append(
                MistiaBootstrapSyncMutation(
                    entity: .budgetPlan,
                    recordID: budget.id,
                    modifiedAt: now
                )
            )
        }

        guard !mutations.isEmpty else { return [] }
        try modelContext.save()
        return mutations
    }

    @MainActor
    static func populateMissingCategorySnapshots(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        let mutations = try populateMissingCategorySnapshots(modelContext: modelContext)
        for mutation in mutations {
            sessionStore.recordUpsert(
                entity: mutation.entity,
                recordID: mutation.recordID,
                modifiedAt: mutation.modifiedAt
            )
        }
    }
}

extension SavingsGoal {
    var planningSnapshot: SavingsGoalSnapshot {
        SavingsGoalSnapshot(
            id: id,
            name: name,
            iconSymbolName: iconSymbolName,
            targetMinor: targetMinor,
            currentSavedMinor: currentSavedMinor,
            targetDate: targetDate,
            linkedWalletID: linkedWallet?.id,
            currencyCode: currencyCode,
            sortOrder: sortOrder
        )
    }
}

extension RecurringBillPlan {
    var planningSnapshot: PlanningBillSnapshot {
        let resolvedCategorySystemKey =
            category?.mistiaSystemCategoryKey
            ?? MistiaFinanceIconRegistry.categoryKey(for: iconSymbolName)
        let resolvedScheduleKind = scheduleKind

        return PlanningBillSnapshot(
            id: id,
            name: name,
            iconSymbolName: iconSymbolName,
            categorySystemKey: resolvedCategorySystemKey,
            categoryName: category?.localizedDisplayName,
            categoryIconSymbolName: category?.iconSymbolName,
            categoryColorHex: category?.iconColorHex,
            amountMinor: amountMinor,
            dueDay: dueDay,
            frequencyMonths: frequencyMonths,
            paymentWalletID: paymentWallet?.id,
            currencyCode: currencyCode,
            createdAt: createdAt,
            scheduleKind: resolvedScheduleKind,
            paymentStartDay: resolvedPaymentStartDay,
            paymentStartDate: resolvedScheduleKind == .oneTime ? paymentStartDate : nil,
            firstScheduledMonth: firstScheduledMonth,
            hasExplicitDueDate: resolvedHasExplicitDueDate,
            dueDate: dueDate,
            autoPayEnabled: autoPayEnabled,
            autoPayDay: autoPayDay,
            autoPayDate: resolvedScheduleKind == .oneTime ? autoPayDate : nil,
            isPaused: isPaused,
            pausedAt: pausedAt,
            resumeStartMonth: resumeStartMonth
        )
    }
}

extension InstallmentPlan {
    var planningSnapshot: PlanningInstallmentSnapshot {
        PlanningInstallmentSnapshot(
            id: id,
            name: name,
            iconSymbolName: iconSymbolName,
            amountPerCycleMinor: amountPerCycleMinor,
            dueDay: dueDay,
            totalCycles: totalCycles,
            frequencyMonths: frequencyMonths,
            paymentWalletID: paymentWallet?.id,
            currencyCode: currencyCode,
            createdAt: createdAt
        )
    }
}

extension DueOccurrenceRecord {
    var planningSnapshot: PlanningDueOccurrenceSnapshot {
        PlanningDueOccurrenceSnapshot(
            id: id,
            sourceKind: sourceKind,
            sourceID: sourceID,
            selectedMonthKey: selectedMonthKey,
            scheduledDate: scheduledDate,
            amountMinorSnapshot: amountMinorSnapshot,
            status: status,
            linkedTransactionID: linkedTransactionID
        )
    }
}

extension LedgerTransaction {
    var planningRecordSnapshot: TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: id,
            financialDomain: financialDomain,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: title,
            note: note,
            amountMinor: amountMinor,
            settlementGroupID: settlementGroupID,
            settlementObligationID: settlementObligationID,
            settlementRole: settlementRole,
            reportingExpenseMinor: reportingExpenseMinor,
            reportingIncomeMinor: reportingIncomeMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            destinationCurrencyCode: destinationCurrencyCode,
            destinationAmountMinor: destinationAmountMinor,
            reportingCurrencyCode: reportingCurrencyCode,
            reportingAmountMinor: reportingAmountMinor,
            conversionModeRawValue: conversionModeRawValue,
            exchangeRateDecimalString: exchangeRateDecimalString,
            exchangeRateProvider: exchangeRateProvider,
            exchangeRateDate: exchangeRateDate,
            isArchived: isArchived,
            occurredAt: occurredAt,
            createdAt: createdAt,
            sourceWalletID: sourceWallet?.id,
            sourceWalletKind: sourceWallet?.kind,
            destinationWalletID: destinationWallet?.id,
            destinationWalletKind: destinationWallet?.kind,
            categoryID: category?.id,
            categoryName: category?.localizedDisplayName,
            categoryParentID: category?.parentCategory?.id,
            categoryParentName: category?.parentCategory?.localizedDisplayName,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
    }
}

extension LedgerWallet {
    func planningCreditCardSnapshot<Records: Sequence>(
        records: Records
    ) -> PlanningCreditCardAccountSnapshot? where Records.Element == TransactionRecordSnapshot {
        let walletSnapshot = TransactionWalletSnapshot(
            id: id,
            kind: kind,
            openingBalanceMinor: openingBalanceMinor
        )
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: [walletSnapshot],
            records: records
        )
        return planningCreditCardSnapshot(balanceIndex: balanceIndex)
    }

    func planningCreditCardSnapshot(
        records: [TransactionRecordSnapshot],
        occurrences _: [PlanningDueOccurrenceSnapshot]
    ) -> PlanningCreditCardAccountSnapshot? {
        let walletSnapshot = TransactionWalletSnapshot(
            id: id,
            kind: kind,
            openingBalanceMinor: openingBalanceMinor
        )
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: [walletSnapshot],
            records: records
        )
        return planningCreditCardSnapshot(balanceIndex: balanceIndex)
    }

    func planningCreditCardSnapshot(
        balanceIndex: TransactionWalletBalanceIndex
    ) -> PlanningCreditCardAccountSnapshot? {
        guard kind == .creditCard, !isArchived, let profile = creditCardProfile else {
            return nil
        }

        let walletSnapshot = TransactionWalletSnapshot(
            id: id,
            kind: kind,
            openingBalanceMinor: openingBalanceMinor
        )
        let balance = TransactionLogic.creditCardBalance(
            creditLimitMinor: profile.creditLimitMinor,
            wallet: walletSnapshot,
            balanceIndex: balanceIndex
        )

        return PlanningCreditCardAccountSnapshot(
            id: id,
            walletID: id,
            walletName: name,
            issuerName: profile.issuerName,
            network: profile.network,
            last4: profile.last4,
            dueDay: profile.paymentDueDay,
            statementClosingDay: profile.statementClosingDay,
            paymentSourceWalletID: profile.paymentSourceWallet?.id,
            paymentSourceWalletName: profile.paymentSourceWallet?.name,
            currencyCode: currencyCode,
            currentDebtMinor: balance.currentDebtMinor,
            availableCreditMinor: balance.availableCreditMinor,
            openedAt: createdAt,
            autoPayEnabled: profile.autoPayEnabled
        )
    }
}

extension PlanningCreditCardDueSnapshot {
    func tone(referenceDate: Date, calendar: Calendar = MistiaCalendar.current) -> PlanningDueRowTone {
        if status == .paid { return .paid }
        if status == .skipped { return .skipped }

        let startOfToday = calendar.startOfDay(for: referenceDate)
        if calendar.startOfDay(for: dueDate) < startOfToday {
            return .overdue
        }

        let warningDate = calendar.date(byAdding: .day, value: 3, to: startOfToday) ?? startOfToday
        if dueDate <= warningDate {
            return .warning
        }

        return .normal
    }
}

extension PlanningRecurringDueSnapshot {
    func tone(referenceDate: Date, calendar: Calendar = MistiaCalendar.current) -> PlanningDueRowTone {
        if status == .paid { return .paid }
        if status == .skipped { return .skipped }

        let startOfToday = calendar.startOfDay(for: referenceDate)
        if calendar.startOfDay(for: dueDate) < startOfToday {
            return .overdue
        }

        let comparisonDate = startOfToday < calendar.startOfDay(for: paymentStartDate)
            ? paymentStartDate
            : dueDate
        let warningDate = calendar.date(byAdding: .day, value: 3, to: startOfToday) ?? startOfToday
        if comparisonDate <= warningDate {
            return .warning
        }

        return .normal
    }
}
