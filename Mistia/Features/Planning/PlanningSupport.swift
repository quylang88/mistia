import SwiftData
import SwiftUI

struct PlanningBudgetEditorTarget: Identifiable {
    let id = UUID()
    let budget: BudgetPlan?
    let selectedMonth: Date
    let preferredParentCategoryID: UUID?
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

    var errorDescription: String? {
        switch self {
        case .missingWallet:
            mistiaLocalized(vi: "Không tìm thấy ví thanh toán phù hợp.", en: "A matching payment wallet could not be found.", ja: "支払いに使うウォレットが見つかりません。")
        case .missingDestinationWallet:
            mistiaLocalized(vi: "Không tìm thấy thẻ tín dụng đích.", en: "The destination credit card could not be found.", ja: "振替先のクレジットカードが見つかりません。")
        case .missingCategory:
            mistiaLocalized(vi: "Không thể xác định danh mục hệ thống cho khoản thanh toán này.", en: "The system category for this payment could not be resolved.", ja: "この支払いに使うシステムカテゴリを特定できません。")
        }
    }
}

enum PlanningDueRowTone {
    case normal
    case warning
    case overdue
    case paid

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
        }
    }
}

struct PlanningSavedDuePayment {
    let transaction: LedgerTransaction
    let occurrenceID: UUID
    let subjectUserID: UUID?
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
        calendar: Calendar = .current
    ) throws -> PlanningSavedDuePayment {
        let now = Date()
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

        guard let sourceWallet = wallets.first(where: { $0.id == draft.sourceWalletID }) else {
            throw PlanningPersistenceError.missingWallet
        }
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
        calendar: Calendar = .current
    ) throws -> DueOccurrenceRecord {
        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)
        let now = Date()
        if let existing = occurrences.first(where: {
            $0.sourceKind == sourceKind
                && $0.sourceID == sourceID
                && $0.selectedMonthKey == monthKey
        }) {
            existing.scheduledDate = scheduledDate
            existing.amountMinorSnapshot = amountMinor
            existing.status = paidAt == nil ? .pending : .paid
            existing.paidAt = paidAt
            existing.linkedTransactionID = linkedTransactionID
            existing.updatedAt = now
            return existing
        } else {
            let record = DueOccurrenceRecord(
                sourceKind: sourceKind,
                sourceID: sourceID,
                selectedMonthKey: monthKey,
                scheduledDate: scheduledDate,
                amountMinorSnapshot: amountMinor,
                status: paidAt == nil ? .pending : .paid,
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
    func planningSnapshot(calendar: Calendar = .current) -> BudgetPlanSnapshot {
        BudgetPlanSnapshot(
            id: id,
            categoryID: category?.id,
            categoryName: category?.localizedDisplayName ?? mistiaLocalized(vi: "Danh mục đã xóa", en: "Deleted category", ja: "削除されたカテゴリ"),
            categoryIconSymbolName: category?.iconSymbolName ?? "questionmark.circle.fill",
            categoryColorHex: category?.iconColorHex ?? "#8A8A8E",
            limitMinor: limitMinor,
            rolloverEnabled: rolloverEnabled,
            currencyCode: currencyCode,
            monthAnchor: PlanningLogic.startOfMonth(for: monthAnchor, calendar: calendar),
            categoryParentID: category?.parentCategory?.id,
            categoryParentName: category?.parentCategory?.localizedDisplayName,
            categoryParentIconSymbolName: category?.parentCategory?.iconSymbolName,
            categoryParentColorHex: category?.parentCategory?.iconColorHex,
            categoryIsParent: category?.isParentCategory ?? false
        )
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

        return PlanningBillSnapshot(
            id: id,
            name: name,
            iconSymbolName: iconSymbolName,
            categorySystemKey: resolvedCategorySystemKey,
            amountMinor: amountMinor,
            dueDay: dueDay,
            frequencyMonths: frequencyMonths,
            paymentWalletID: paymentWallet?.id,
            currencyCode: currencyCode,
            createdAt: createdAt
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
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: title,
            note: note,
            amountMinor: amountMinor,
            isArchived: isArchived,
            occurredAt: occurredAt,
            createdAt: createdAt,
            sourceWalletID: sourceWallet?.id,
            sourceWalletKind: sourceWallet?.kind,
            destinationWalletID: destinationWallet?.id,
            destinationWalletKind: destinationWallet?.kind,
            categoryID: category?.id,
            categoryParentID: category?.parentCategory?.id,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
    }
}

extension LedgerWallet {
    func planningCreditCardSnapshot(
        records: [TransactionRecordSnapshot]
    ) -> PlanningCreditCardAccountSnapshot? {
        guard kind == .creditCard, !isArchived, let profile = creditCardProfile else {
            return nil
        }

        let debt = max(
            TransactionLogic.effectiveBalance(
                for: TransactionWalletSnapshot(
                    id: id,
                    kind: .creditCard,
                    openingBalanceMinor: openingBalanceMinor
                ),
                records: records
            ),
            0
        )
        
        let availableCredit = max(profile.creditLimitMinor - debt, 0)

        return PlanningCreditCardAccountSnapshot(
            id: id,
            walletID: id,
            walletName: name,
            network: profile.network,
            last4: profile.last4,
            dueDay: profile.paymentDueDay,
            paymentSourceWalletID: profile.paymentSourceWallet?.id,
            currencyCode: currencyCode,
            currentDebtMinor: debt,
            availableCreditMinor: availableCredit,
            openedAt: createdAt
        )
    }
}

extension PlanningCreditCardDueSnapshot {
    func tone(referenceDate: Date, calendar: Calendar = .current) -> PlanningDueRowTone {
        if status == .paid { return .paid }

        let startOfToday = calendar.startOfDay(for: referenceDate)
        if dueDate < startOfToday {
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
    func tone(referenceDate: Date, calendar: Calendar = .current) -> PlanningDueRowTone {
        if status == .paid { return .paid }

        let startOfToday = calendar.startOfDay(for: referenceDate)
        if dueDate < startOfToday {
            return .overdue
        }

        let warningDate = calendar.date(byAdding: .day, value: 3, to: startOfToday) ?? startOfToday
        if dueDate <= warningDate {
            return .warning
        }

        return .normal
    }
}
