import Foundation

nonisolated struct BudgetPlanSnapshot: Equatable, Identifiable {
    let id: UUID
    let categoryID: UUID?
    let categoryName: String
    let categoryIconSymbolName: String
    let categoryColorHex: String
    let categoryParentID: UUID?
    let categoryParentName: String?
    let categoryParentIconSymbolName: String?
    let categoryParentColorHex: String?
    let categoryIsParent: Bool
    let limitMinor: Int64
    let rolloverEnabled: Bool
    let currencyCode: String
    let monthAnchor: Date

    init(
        id: UUID,
        categoryID: UUID?,
        categoryName: String,
        categoryIconSymbolName: String,
        categoryColorHex: String,
        limitMinor: Int64,
        rolloverEnabled: Bool,
        currencyCode: String,
        monthAnchor: Date,
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil,
        categoryParentIconSymbolName: String? = nil,
        categoryParentColorHex: String? = nil,
        categoryIsParent: Bool = false
    ) {
        self.id = id
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryIconSymbolName = categoryIconSymbolName
        self.categoryColorHex = categoryColorHex
        self.categoryParentID = categoryParentID
        self.categoryParentName = categoryParentName
        self.categoryParentIconSymbolName = categoryParentIconSymbolName
        self.categoryParentColorHex = categoryParentColorHex
        self.categoryIsParent = categoryIsParent
        self.limitMinor = limitMinor
        self.rolloverEnabled = rolloverEnabled
        self.currencyCode = currencyCode
        self.monthAnchor = monthAnchor
    }

    var branchCategoryID: UUID? {
        categoryIsParent ? categoryID : (categoryParentID ?? categoryID)
    }

    var branchCategoryName: String {
        categoryIsParent ? categoryName : (categoryParentName ?? categoryName)
    }

    var branchIconSymbolName: String {
        categoryIsParent ? categoryIconSymbolName : (categoryParentIconSymbolName ?? categoryIconSymbolName)
    }

    var branchColorHex: String {
        categoryIsParent ? categoryColorHex : (categoryParentColorHex ?? categoryColorHex)
    }
}

nonisolated enum PlanningBudgetTone: String, Equatable {
    case calm
    case warning
    case critical
}

nonisolated enum PlanningBudgetHealth: String, Equatable {
    case stable
    case caution
    case exceeded

    var title: String {
        switch self {
        case .stable:
            L10n.shared.corelogic.planning.stable
        case .caution:
            L10n.shared.corelogic.planning.needsAttention
        case .exceeded:
            L10n.shared.corelogic.planning.exceeded
        }
    }
}

nonisolated struct PlanningBudgetRowSnapshot: Equatable, Identifiable {
    let id: UUID
    let categoryID: UUID?
    let name: String
    let iconSymbolName: String
    let colorHex: String
    let spentMinor: Int64
    let limitMinor: Int64
    let currencyCode: String
    let daysRemaining: Int
    let isPastMonth: Bool

    var progress: Double {
        guard limitMinor > 0 else { return 0 }
        return Double(spentMinor) / Double(limitMinor)
    }

    var progressClamped: Double {
        min(max(progress, 0), 1)
    }

    var health: PlanningBudgetHealth {
        PlanningLogic.health(forProgress: progress)
    }

    var tone: PlanningBudgetTone {
        PlanningLogic.tone(forProgress: progress)
    }
}

nonisolated struct PlanningBudgetSummarySnapshot: Equatable {
    let totalBudgetMinor: Int64
    let spentMinor: Int64
    let remainingMinor: Int64
    let health: PlanningBudgetHealth

    var progress: Double {
        guard totalBudgetMinor > 0 else { return 0 }
        return Double(spentMinor) / Double(totalBudgetMinor)
    }

    var progressClamped: Double {
        min(max(progress, 0), 1)
    }
}

nonisolated enum PlanningBudgetBranchMode: Equatable {
    case parentOnly
    case parentWithChildren
    case childOnly
}

nonisolated struct PlanningBudgetBranchRowSnapshot: Equatable, Identifiable {
    let id: UUID
    let parentCategoryID: UUID?
    let name: String
    let iconSymbolName: String
    let colorHex: String
    let spentMinor: Int64
    let limitMinor: Int64
    let currencyCode: String
    let daysRemaining: Int
    let isPastMonth: Bool
    let mode: PlanningBudgetBranchMode
    let parentBudgetID: UUID?
    let primaryBudgetID: UUID?
    let allocatedChildLimitMinor: Int64
    let unallocatedLimitMinor: Int64
    let childRows: [PlanningBudgetRowSnapshot]

    var progress: Double {
        guard limitMinor > 0 else { return 0 }
        return Double(spentMinor) / Double(limitMinor)
    }

    var progressClamped: Double {
        min(max(progress, 0), 1)
    }

    var health: PlanningBudgetHealth {
        PlanningLogic.health(forProgress: progress)
    }

    var tone: PlanningBudgetTone {
        PlanningLogic.tone(forProgress: progress)
    }
}

nonisolated enum PlanningBudgetAllocationValidationResult: Equatable {
    case valid
    case childBudgetsExceedParent(childTotalMinor: Int64, parentLimitMinor: Int64)
    case parentLimitBelowChildren(childTotalMinor: Int64, parentLimitMinor: Int64)
}

nonisolated struct SavingsGoalSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let targetMinor: Int64
    let currentSavedMinor: Int64
    let targetDate: Date
    let linkedWalletID: UUID?
    let currencyCode: String
    let sortOrder: Int
}

nonisolated struct PlanningGoalRowSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let targetMinor: Int64
    let currentSavedMinor: Int64
    let targetDate: Date
    let monthlyRequiredMinor: Int64
    let currencyCode: String

    var progress: Double {
        guard targetMinor > 0 else { return 0 }
        return Double(currentSavedMinor) / Double(targetMinor)
    }

    var progressClamped: Double {
        min(max(progress, 0), 1)
    }
}

nonisolated struct PlanningGoalSummarySnapshot: Equatable {
    let activeCount: Int
    let totalSavedMinor: Int64
    let nearestGoalName: String?
}

nonisolated struct PlanningCreditCardAccountSnapshot: Equatable, Identifiable {
    let id: UUID
    let walletID: UUID
    let walletName: String
    let issuerName: String
    let network: CreditCardNetwork
    let last4: String
    let dueDay: Int
    let statementClosingDay: Int
    let paymentSourceWalletID: UUID?
    let paymentSourceWalletName: String?
    let currencyCode: String
    let currentDebtMinor: Int64
    let availableCreditMinor: Int64
    let openedAt: Date
    let autoPayEnabled: Bool

    init(
        id: UUID,
        walletID: UUID,
        walletName: String,
        issuerName: String,
        network: CreditCardNetwork,
        last4: String,
        dueDay: Int,
        statementClosingDay: Int,
        paymentSourceWalletID: UUID?,
        paymentSourceWalletName: String?,
        currencyCode: String,
        currentDebtMinor: Int64,
        availableCreditMinor: Int64,
        openedAt: Date,
        autoPayEnabled: Bool = true
    ) {
        self.id = id
        self.walletID = walletID
        self.walletName = walletName
        self.issuerName = issuerName
        self.network = network
        self.last4 = last4
        self.dueDay = dueDay
        self.statementClosingDay = statementClosingDay
        self.paymentSourceWalletID = paymentSourceWalletID
        self.paymentSourceWalletName = paymentSourceWalletName
        self.currencyCode = currencyCode
        self.currentDebtMinor = currentDebtMinor
        self.availableCreditMinor = availableCreditMinor
        self.openedAt = openedAt
        self.autoPayEnabled = autoPayEnabled
    }
}

nonisolated enum PlanningCreditCardStatementState: String, Equatable {
    case unclosed
    case payable
    case paid
    case overdue
}

nonisolated enum PlanningCreditCardAutoPaymentDecision: Equatable {
    case notDue
    case alreadyPaid
    case missingLinkedWallet
    case insufficientFunds(availableMinor: Int64, requiredMinor: Int64)
    case payable
}

nonisolated struct PlanningCreditCardStatementSnapshot: Equatable, Identifiable {
    let id: String
    let walletID: UUID
    let walletName: String
    let issuerName: String
    let network: CreditCardNetwork
    let last4: String
    let statementMonth: Date
    let closingDate: Date
    let dueDate: Date
    let amountMinor: Int64
    let availableCreditMinor: Int64
    let paymentSourceWalletID: UUID?
    let paymentSourceWalletName: String?
    let currencyCode: String
    let status: PlanningDueOccurrenceStatus
    let linkedTransactionID: UUID?
    let state: PlanningCreditCardStatementState

    var isPayable: Bool {
        state == .payable || state == .overdue
    }
}

nonisolated struct PlanningCurrencyAmountTotalSnapshot: Equatable, Identifiable {
    let currencyCode: String
    let amountMinor: Int64

    var id: String { currencyCode }
}

nonisolated struct PlanningBillSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let categorySystemKey: MistiaSystemCategoryKey?
    let categoryName: String?
    let categoryIconSymbolName: String?
    let categoryColorHex: String?
    let amountMinor: Int64?
    let dueDay: Int
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let createdAt: Date
    let scheduleKind: PlanningBillScheduleKind
    let paymentStartDay: Int
    let paymentStartDate: Date?
    let firstScheduledMonth: Date?
    let hasExplicitDueDate: Bool
    let dueDate: Date?
    let autoPayEnabled: Bool
    let autoPayDay: Int?
    let autoPayDate: Date?

    init(
        id: UUID,
        name: String,
        iconSymbolName: String,
        categorySystemKey: MistiaSystemCategoryKey?,
        categoryName: String? = nil,
        categoryIconSymbolName: String? = nil,
        categoryColorHex: String? = nil,
        amountMinor: Int64?,
        dueDay: Int,
        frequencyMonths: Int,
        paymentWalletID: UUID?,
        currencyCode: String,
        createdAt: Date,
        scheduleKind: PlanningBillScheduleKind = .recurring,
        paymentStartDay: Int? = nil,
        paymentStartDate: Date? = nil,
        firstScheduledMonth: Date? = nil,
        hasExplicitDueDate: Bool = false,
        dueDate: Date? = nil,
        autoPayEnabled: Bool = false,
        autoPayDay: Int? = nil,
        autoPayDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.categorySystemKey = categorySystemKey
        self.categoryName = categoryName
        self.categoryIconSymbolName = categoryIconSymbolName
        self.categoryColorHex = categoryColorHex
        self.amountMinor = amountMinor
        self.dueDay = dueDay
        self.frequencyMonths = frequencyMonths
        self.paymentWalletID = paymentWalletID
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.scheduleKind = scheduleKind
        self.paymentStartDay = paymentStartDay ?? dueDay
        self.paymentStartDate = paymentStartDate
        self.firstScheduledMonth = firstScheduledMonth
        self.hasExplicitDueDate = hasExplicitDueDate
        self.dueDate = dueDate
        self.autoPayEnabled = autoPayEnabled
        self.autoPayDay = autoPayDay
        self.autoPayDate = autoPayDate
    }
}

nonisolated struct PlanningInstallmentSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let amountPerCycleMinor: Int64
    let dueDay: Int
    let totalCycles: Int?
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let createdAt: Date
}

nonisolated struct PlanningDueOccurrenceSnapshot: Equatable, Identifiable {
    let id: UUID
    let sourceKind: PlanningDueSourceKind
    let sourceID: UUID
    let selectedMonthKey: String
    let scheduledDate: Date
    let amountMinorSnapshot: Int64?
    let status: PlanningDueOccurrenceStatus
    let linkedTransactionID: UUID?
}

nonisolated struct PlanningCreditCardDueSnapshot: Equatable, Identifiable {
    let id: UUID
    let walletID: UUID
    let walletName: String
    let network: CreditCardNetwork
    let last4: String
    let amountMinor: Int64
    let availableCreditMinor: Int64
    let statementMonth: Date
    let dueDate: Date
    let paymentSourceWalletID: UUID?
    let currencyCode: String
    let status: PlanningDueOccurrenceStatus
    let linkedTransactionID: UUID?
}

nonisolated struct PlanningRecurringDueSnapshot: Equatable, Identifiable {
    let id: UUID
    let sourceKind: PlanningDueSourceKind
    let sourceID: UUID
    let name: String
    let iconSymbolName: String
    let categorySystemKey: MistiaSystemCategoryKey?
    let categoryName: String?
    let categoryIconSymbolName: String?
    let categoryColorHex: String?
    let amountMinor: Int64?
    let paymentStartDate: Date
    let dueDate: Date
    let hasExplicitDueDate: Bool
    let scheduleKind: PlanningBillScheduleKind
    let frequencyMonths: Int
    let totalCycles: Int?
    let paymentWalletID: UUID?
    let currencyCode: String
    let status: PlanningDueOccurrenceStatus
    let linkedTransactionID: UUID?
    let autoPayEnabled: Bool
    let autoPayDate: Date?

    init(
        id: UUID,
        sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        name: String,
        iconSymbolName: String,
        categorySystemKey: MistiaSystemCategoryKey?,
        categoryName: String? = nil,
        categoryIconSymbolName: String? = nil,
        categoryColorHex: String? = nil,
        amountMinor: Int64?,
        paymentStartDate: Date? = nil,
        dueDate: Date,
        hasExplicitDueDate: Bool = true,
        scheduleKind: PlanningBillScheduleKind = .recurring,
        frequencyMonths: Int,
        totalCycles: Int?,
        paymentWalletID: UUID?,
        currencyCode: String,
        status: PlanningDueOccurrenceStatus,
        linkedTransactionID: UUID?,
        autoPayEnabled: Bool = false,
        autoPayDate: Date? = nil
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.categorySystemKey = categorySystemKey
        self.categoryName = categoryName
        self.categoryIconSymbolName = categoryIconSymbolName
        self.categoryColorHex = categoryColorHex
        self.amountMinor = amountMinor
        self.paymentStartDate = paymentStartDate ?? dueDate
        self.dueDate = dueDate
        self.hasExplicitDueDate = hasExplicitDueDate && (paymentStartDate ?? dueDate) != dueDate
        self.scheduleKind = scheduleKind
        self.frequencyMonths = frequencyMonths
        self.totalCycles = totalCycles
        self.paymentWalletID = paymentWalletID
        self.currencyCode = currencyCode
        self.status = status
        self.linkedTransactionID = linkedTransactionID
        self.autoPayEnabled = autoPayEnabled
        self.autoPayDate = autoPayDate
    }
}

nonisolated struct PlanningDueSummarySnapshot: Equatable {
    let upcomingCount: Int
    let totalDueMinor: Int64
    let overdueCount: Int
}

nonisolated struct PlanningDuePaymentDraft: Equatable {
    let primaryKind: TransactionPrimaryKind
    let transferSubtype: TransactionTransferSubtype?
    let title: String
    let amountMinor: Int64
    let sourceWalletID: UUID
    let destinationWalletID: UUID?
    let categorySystemKey: MistiaSystemCategoryKey?
}

nonisolated enum PlanningDuePaymentError: Error, Equatable {
    case missingAmount
    case missingSourceWallet
    case missingDestinationWallet
}

extension PlanningDuePaymentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAmount:
            L10n.shared.corelogic.planning.enterAPaymentAmountBeforeContinuing
        case .missingSourceWallet:
            L10n.shared.corelogic.planning.chooseAPaymentWalletBeforeContinuing
        case .missingDestinationWallet:
            L10n.shared.corelogic.planning.theDestinationWalletForThisPaymentCould
        }
    }
}

nonisolated enum PlanningLogic {
    static func health(forProgress progress: Double) -> PlanningBudgetHealth {
        if progress >= 1.0 {
            return .exceeded
        }

        if progress >= 0.6 {
            return .caution
        }

        return .stable
    }

    static func tone(forProgress progress: Double) -> PlanningBudgetTone {
        if progress >= 1.0 {
            return .critical
        }

        if progress >= 0.8 {
            return .warning
        }

        return .calm
    }

    static func budgetRows(
        plans: [BudgetPlanSnapshot],
        records: [TransactionRecordSnapshot],
        selectedMonth: Date,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current,
        exchangeRates: [MistiaExchangeRate] = []
    ) -> [PlanningBudgetRowSnapshot] {
        let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth)
        let spentByCategory = Dictionary(grouping: records.filter { record in
            guard record.entryStatus == .posted,
                  TransactionLogic.isExpenseSpending(record),
                  record.categoryID != nil,
                  let monthInterval
            else {
                return false
            }

            return record.occurredAt >= monthInterval.start
                && record.occurredAt < monthInterval.end
        }, by: \.categoryID)

        let remainingDays = daysRemainingInMonth(for: selectedMonth, referenceDate: referenceDate, calendar: calendar)
        let isPastMonth = isPastMonth(selectedMonth, referenceDate: referenceDate, calendar: calendar)

        return plans
            .map { plan in
                let spent = spentByCategory[plan.categoryID]?
                    .reduce(into: Int64.zero) { partial, record in
                        partial += reportingAmount(
                            for: record,
                            currencyCode: plan.currencyCode,
                            exchangeRates: exchangeRates
                        )
                    } ?? 0

                return PlanningBudgetRowSnapshot(
                    id: plan.id,
                    categoryID: plan.categoryID,
                    name: plan.categoryName,
                    iconSymbolName: plan.categoryIconSymbolName,
                    colorHex: plan.categoryColorHex,
                    spentMinor: spent,
                    limitMinor: plan.limitMinor,
                    currencyCode: plan.currencyCode,
                    daysRemaining: remainingDays,
                    isPastMonth: isPastMonth
                )
            }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress {
                    return lhs.progress > rhs.progress
                }
                if lhs.daysRemaining != rhs.daysRemaining {
                    return lhs.daysRemaining < rhs.daysRemaining
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func budgetSummary(
        from rows: [PlanningBudgetRowSnapshot],
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = []
    ) -> PlanningBudgetSummarySnapshot {
        let totalBudget = rows.reduce(into: Int64.zero) { partial, row in
            partial += reportingAmount(
                amountMinor: row.limitMinor,
                sourceCurrencyCode: row.currencyCode,
                currencyCode: reportingCurrencyCode ?? row.currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let spent = rows.reduce(into: Int64.zero) { partial, row in
            partial += reportingAmount(
                amountMinor: row.spentMinor,
                sourceCurrencyCode: row.currencyCode,
                currencyCode: reportingCurrencyCode ?? row.currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let remaining = max(totalBudget - spent, 0)

        return PlanningBudgetSummarySnapshot(
            totalBudgetMinor: totalBudget,
            spentMinor: spent,
            remainingMinor: remaining,
            health: health(forProgress: totalBudget > 0 ? Double(spent) / Double(totalBudget) : 0)
        )
    }

    static func budgetBranchRows(
        plans: [BudgetPlanSnapshot],
        records: [TransactionRecordSnapshot],
        selectedMonth: Date,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current,
        exchangeRates: [MistiaExchangeRate] = []
    ) -> [PlanningBudgetBranchRowSnapshot] {
        let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth)
        let expenseRecordsInMonth = records.filter { record in
            guard record.entryStatus == .posted,
                  TransactionLogic.isExpenseSpending(record),
                  let monthInterval
            else {
                return false
            }

            return record.occurredAt >= monthInterval.start
                && record.occurredAt < monthInterval.end
        }
        let spentByCategory = Dictionary(grouping: expenseRecordsInMonth, by: \.categoryID)
        let spentByBranch = Dictionary(grouping: expenseRecordsInMonth) { record in
            record.categoryParentID ?? record.categoryID
        }

        let remainingDays = daysRemainingInMonth(for: selectedMonth, referenceDate: referenceDate, calendar: calendar)
        let isPastMonth = isPastMonth(selectedMonth, referenceDate: referenceDate, calendar: calendar)

        return Dictionary(grouping: plans) { $0.branchCategoryID }
            .compactMap { branchID, branchPlans in
                guard let branchID else { return nil }

                let parentPlan = branchPlans.first(where: { $0.categoryIsParent })
                let childPlans = branchPlans.filter { !$0.categoryIsParent }
                let branchTemplate = parentPlan ?? childPlans.first
                guard let branchTemplate else { return nil }

                let childRows = childPlans
                    .map { plan in
                        let spent = spentByCategory[plan.categoryID]?
                            .reduce(into: Int64.zero) { partial, record in
                                partial += reportingAmount(
                                    for: record,
                                    currencyCode: plan.currencyCode,
                                    exchangeRates: exchangeRates
                                )
                            } ?? 0

                        return PlanningBudgetRowSnapshot(
                            id: plan.id,
                            categoryID: plan.categoryID,
                            name: plan.categoryName,
                            iconSymbolName: plan.categoryIconSymbolName,
                            colorHex: plan.categoryColorHex,
                            spentMinor: spent,
                            limitMinor: plan.limitMinor,
                            currencyCode: plan.currencyCode,
                            daysRemaining: remainingDays,
                            isPastMonth: isPastMonth
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.progress != rhs.progress {
                            return lhs.progress > rhs.progress
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }

                if let parentPlan {
                    let spent = spentByBranch[branchID]?
                        .reduce(into: Int64.zero) { partial, record in
                            partial += reportingAmount(
                                for: record,
                                currencyCode: parentPlan.currencyCode,
                                exchangeRates: exchangeRates
                            )
                        } ?? 0
                    let allocatedChildLimit = childRows.reduce(into: Int64.zero) { partial, row in
                        partial += reportingAmount(
                            amountMinor: row.limitMinor,
                            sourceCurrencyCode: row.currencyCode,
                            currencyCode: parentPlan.currencyCode,
                            exchangeRates: exchangeRates
                        )
                    }

                    return PlanningBudgetBranchRowSnapshot(
                        id: branchID,
                        parentCategoryID: branchTemplate.branchCategoryID,
                        name: parentPlan.branchCategoryName,
                        iconSymbolName: parentPlan.branchIconSymbolName,
                        colorHex: parentPlan.branchColorHex,
                        spentMinor: spent,
                        limitMinor: parentPlan.limitMinor,
                        currencyCode: parentPlan.currencyCode,
                        daysRemaining: remainingDays,
                        isPastMonth: isPastMonth,
                        mode: childRows.isEmpty ? .parentOnly : .parentWithChildren,
                        parentBudgetID: parentPlan.id,
                        primaryBudgetID: parentPlan.id,
                        allocatedChildLimitMinor: allocatedChildLimit,
                        unallocatedLimitMinor: max(parentPlan.limitMinor - allocatedChildLimit, 0),
                        childRows: childRows
                    )
                }

                if childRows.count == 1, let childRow = childRows.first {
                    return PlanningBudgetBranchRowSnapshot(
                        id: branchID,
                        parentCategoryID: branchTemplate.branchCategoryID,
                        name: childRow.name,
                        iconSymbolName: childRow.iconSymbolName,
                        colorHex: childRow.colorHex,
                        spentMinor: childRow.spentMinor,
                        limitMinor: childRow.limitMinor,
                        currencyCode: childRow.currencyCode,
                        daysRemaining: childRow.daysRemaining,
                        isPastMonth: childRow.isPastMonth,
                        mode: .childOnly,
                        parentBudgetID: nil,
                        primaryBudgetID: childRow.id,
                        allocatedChildLimitMinor: childRow.limitMinor,
                        unallocatedLimitMinor: 0,
                        childRows: []
                    )
                }

                let spent = childRows.reduce(into: Int64.zero) { partial, row in
                    partial += reportingAmount(
                        amountMinor: row.spentMinor,
                        sourceCurrencyCode: row.currencyCode,
                        currencyCode: branchTemplate.currencyCode,
                        exchangeRates: exchangeRates
                    )
                }
                let limit = childRows.reduce(into: Int64.zero) { partial, row in
                    partial += reportingAmount(
                        amountMinor: row.limitMinor,
                        sourceCurrencyCode: row.currencyCode,
                        currencyCode: branchTemplate.currencyCode,
                        exchangeRates: exchangeRates
                    )
                }

                return PlanningBudgetBranchRowSnapshot(
                    id: branchID,
                    parentCategoryID: branchTemplate.branchCategoryID,
                    name: branchTemplate.branchCategoryName,
                    iconSymbolName: branchTemplate.branchIconSymbolName,
                    colorHex: branchTemplate.branchColorHex,
                    spentMinor: spent,
                    limitMinor: limit,
                    currencyCode: branchTemplate.currencyCode,
                    daysRemaining: remainingDays,
                    isPastMonth: isPastMonth,
                    mode: .childOnly,
                    parentBudgetID: nil,
                    primaryBudgetID: nil,
                    allocatedChildLimitMinor: limit,
                    unallocatedLimitMinor: 0,
                    childRows: childRows
                )
            }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress {
                    return lhs.progress > rhs.progress
                }
                if lhs.daysRemaining != rhs.daysRemaining {
                    return lhs.daysRemaining < rhs.daysRemaining
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func budgetSummary(
        from rows: [PlanningBudgetBranchRowSnapshot],
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = []
    ) -> PlanningBudgetSummarySnapshot {
        let totalBudget = rows.reduce(into: Int64.zero) { partial, row in
            partial += reportingAmount(
                amountMinor: row.limitMinor,
                sourceCurrencyCode: row.currencyCode,
                currencyCode: reportingCurrencyCode ?? row.currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let spent = rows.reduce(into: Int64.zero) { partial, row in
            partial += reportingAmount(
                amountMinor: row.spentMinor,
                sourceCurrencyCode: row.currencyCode,
                currencyCode: reportingCurrencyCode ?? row.currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let remaining = max(totalBudget - spent, 0)

        return PlanningBudgetSummarySnapshot(
            totalBudgetMinor: totalBudget,
            spentMinor: spent,
            remainingMinor: remaining,
            health: health(forProgress: totalBudget > 0 ? Double(spent) / Double(totalBudget) : 0)
            )
    }

    static func validateBudgetAllocation(
        categoryID: UUID?,
        branchCategoryID: UUID?,
        categoryIsParent: Bool,
        categoryIsChild: Bool,
        limitMinor: Int64,
        monthAnchor: Date,
        plans: [BudgetPlanSnapshot],
        editingBudgetID: UUID? = nil,
        calendar: Calendar = MistiaCalendar.current
    ) -> PlanningBudgetAllocationValidationResult {
        guard let branchCategoryID else {
            return .valid
        }

        let selectedMonth = startOfMonth(for: monthAnchor, calendar: calendar)
        let branchPlans = plans.filter { plan in
            guard plan.id != editingBudgetID else { return false }
            return plan.branchCategoryID == branchCategoryID
                && startOfMonth(for: plan.monthAnchor, calendar: calendar) == selectedMonth
        }

        let childLimitTotal = branchPlans.reduce(into: Int64.zero) { partial, plan in
            guard !plan.categoryIsParent else { return }
            partial += plan.limitMinor
        }

        if categoryIsParent {
            guard limitMinor >= childLimitTotal else {
                return .parentLimitBelowChildren(
                    childTotalMinor: childLimitTotal,
                    parentLimitMinor: limitMinor
                )
            }

            return .valid
        }

        guard categoryIsChild else {
            return .valid
        }

        if let parentPlan = branchPlans.first(where: { $0.categoryIsParent }) {
            let projectedChildLimitTotal = childLimitTotal + limitMinor
            guard projectedChildLimitTotal <= parentPlan.limitMinor else {
                return .childBudgetsExceedParent(
                    childTotalMinor: projectedChildLimitTotal,
                    parentLimitMinor: parentPlan.limitMinor
                )
            }
        }

        return .valid
    }

    static func goalRows(
        goals: [SavingsGoalSnapshot],
        selectedMonth: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> [PlanningGoalRowSnapshot] {
        goals
            .map { goal in
                let remainingAmount = max(goal.targetMinor - goal.currentSavedMinor, 0)
                let monthCount = max(monthsRemaining(from: selectedMonth, to: goal.targetDate, calendar: calendar), 1)
                let monthlyRequired = remainingAmount == 0
                    ? 0
                    : Int64(ceil(Double(remainingAmount) / Double(monthCount)))

                return PlanningGoalRowSnapshot(
                    id: goal.id,
                    name: goal.name,
                    iconSymbolName: goal.iconSymbolName,
                    targetMinor: goal.targetMinor,
                    currentSavedMinor: goal.currentSavedMinor,
                    targetDate: goal.targetDate,
                    monthlyRequiredMinor: monthlyRequired,
                    currencyCode: goal.currencyCode
                )
            }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress {
                    return lhs.progress > rhs.progress
                }
                if lhs.targetDate != rhs.targetDate {
                    return lhs.targetDate < rhs.targetDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func goalSummary(
        from rows: [PlanningGoalRowSnapshot],
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = []
    ) -> PlanningGoalSummarySnapshot {
        let nearest = rows.max { lhs, rhs in
            if lhs.progress != rhs.progress {
                return lhs.progress < rhs.progress
            }
            return lhs.targetDate > rhs.targetDate
        }

        return PlanningGoalSummarySnapshot(
            activeCount: rows.count,
            totalSavedMinor: rows.reduce(into: Int64.zero) { partial, row in
                partial += reportingAmount(
                    amountMinor: row.currentSavedMinor,
                    sourceCurrencyCode: row.currencyCode,
                    currencyCode: reportingCurrencyCode ?? row.currencyCode,
                    exchangeRates: exchangeRates
                )
            },
            nearestGoalName: nearest?.name
        )
    }

    static func creditCardDueItems(
        accounts: [PlanningCreditCardAccountSnapshot],
        records: [TransactionRecordSnapshot] = [],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [PlanningCreditCardDueSnapshot] {
        creditCardStatementsDue(
            in: selectedMonth,
            accounts: accounts,
            records: records,
            occurrences: occurrences,
            referenceDate: referenceDate,
            calendar: calendar
        )
        .filter { $0.state != .unclosed && $0.amountMinor > 0 }
        .map { statement in
            PlanningCreditCardDueSnapshot(
                id: statement.walletID,
                walletID: statement.walletID,
                walletName: statement.walletName,
                network: statement.network,
                last4: statement.last4,
                amountMinor: statement.amountMinor,
                availableCreditMinor: statement.availableCreditMinor,
                statementMonth: statement.statementMonth,
                dueDate: statement.dueDate,
                paymentSourceWalletID: statement.paymentSourceWalletID,
                currencyCode: statement.currencyCode,
                status: statement.status,
                linkedTransactionID: statement.linkedTransactionID
            )
        }
        .sorted(by: dueSort)
    }

    static func creditCardStatementsDue(
        in selectedMonth: Date,
        accounts: [PlanningCreditCardAccountSnapshot],
        records: [TransactionRecordSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [PlanningCreditCardStatementSnapshot] {
        let selectedMonthStart = startOfMonth(for: selectedMonth, calendar: calendar)
        let candidateMonths = (-2...0).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: selectedMonthStart)
        }

        return creditCardStatementItems(
            accounts: accounts,
            records: records,
            occurrences: occurrences,
            statementMonths: candidateMonths,
            referenceDate: referenceDate,
            calendar: calendar
        )
        .filter { isSameMonth($0.dueDate, other: selectedMonthStart, calendar: calendar) }
        .sorted(by: dueSort)
    }

    static func creditCardStatementItems(
        accounts: [PlanningCreditCardAccountSnapshot],
        records: [TransactionRecordSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        statementMonths: [Date],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [PlanningCreditCardStatementSnapshot] {
        let months = Dictionary(
            grouping: statementMonths.map { startOfMonth(for: $0, calendar: calendar) },
            by: { monthKey(for: $0, calendar: calendar) }
        )
            .compactMap { $0.value.first }
            .sorted()

        return accounts.flatMap { account in
            months.compactMap { month in
                creditCardStatementItem(
                    account: account,
                    records: records,
                    occurrences: occurrences,
                    statementMonth: month,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
        }
        .sorted(by: dueSort)
    }

    static func creditCardStatementClosingDate(
        statementMonth: Date,
        statementClosingDay: Int,
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        let nextMonth = calendar.date(
            byAdding: .month,
            value: 1,
            to: startOfMonth(for: statementMonth, calendar: calendar)
        ) ?? statementMonth
        return scheduledDate(dueDay: statementClosingDay, selectedMonth: nextMonth, calendar: calendar)
    }

    static func creditCardStatementDueDate(
        statementMonth: Date,
        statementClosingDay: Int,
        paymentDueDay: Int,
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        let closingDate = creditCardStatementClosingDate(
            statementMonth: statementMonth,
            statementClosingDay: statementClosingDay,
            calendar: calendar
        )
        let closingMonth = startOfMonth(for: closingDate, calendar: calendar)
        let sameMonthDue = scheduledDate(
            dueDay: paymentDueDay,
            selectedMonth: closingMonth,
            calendar: calendar
        )

        if sameMonthDue >= closingDate {
            return sameMonthDue
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: closingMonth) ?? closingMonth
        return scheduledDate(dueDay: paymentDueDay, selectedMonth: nextMonth, calendar: calendar)
    }

    static func recurringBillDueItems(
        bills: [PlanningBillSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> [PlanningRecurringDueSnapshot] {
        dueItems(
            sourceKind: .recurringBill,
            selectedMonth: selectedMonth,
            calendar: calendar
        ) { monthKey in
            bills.compactMap { bill in
                let window = recurringBillWindow(
                    for: bill,
                    selectedMonth: selectedMonth,
                    calendar: calendar
                )
                guard let window else { return nil }

                let occurrence = occurrenceRecord(
                    for: .recurringBill,
                    sourceID: bill.id,
                    monthKey: monthKey,
                    occurrences: occurrences
                )

                return PlanningRecurringDueSnapshot(
                    id: bill.id,
                    sourceKind: .recurringBill,
                    sourceID: bill.id,
                    name: bill.name,
                    iconSymbolName: bill.iconSymbolName,
                    categorySystemKey: bill.categorySystemKey,
                    categoryName: bill.categoryName,
                    categoryIconSymbolName: bill.categoryIconSymbolName,
                    categoryColorHex: bill.categoryColorHex,
                    amountMinor: occurrence?.amountMinorSnapshot ?? bill.amountMinor,
                    paymentStartDate: window.paymentStartDate,
                    dueDate: window.dueDate,
                    hasExplicitDueDate: window.hasExplicitDueDate,
                    scheduleKind: bill.scheduleKind,
                    frequencyMonths: bill.frequencyMonths,
                    totalCycles: nil,
                    paymentWalletID: bill.paymentWalletID,
                    currencyCode: bill.currencyCode,
                    status: occurrence?.status ?? .pending,
                    linkedTransactionID: occurrence?.linkedTransactionID,
                    autoPayEnabled: bill.autoPayEnabled,
                    autoPayDate: window.autoPayDate
                )
            }
        }
    }

    static func recurringBillAmountTotalsByCurrency(
        _ items: [PlanningRecurringDueSnapshot]
    ) -> [PlanningCurrencyAmountTotalSnapshot] {
        Dictionary(grouping: items) { item in
            MistiaCurrencyLogic.normalizedCode(item.currencyCode)
        }
        .compactMap { currencyCode, groupedItems in
            let total = groupedItems.reduce(into: Int64.zero) { partial, item in
                guard item.sourceKind == .recurringBill,
                      let amountMinor = item.amountMinor,
                      amountMinor > 0 else {
                    return
                }
                partial += amountMinor
            }
            guard total > 0 else { return nil }
            return PlanningCurrencyAmountTotalSnapshot(
                currencyCode: currencyCode,
                amountMinor: total
            )
        }
        .sorted { lhs, rhs in
            lhs.currencyCode.localizedCaseInsensitiveCompare(rhs.currencyCode) == .orderedAscending
        }
    }

    static func installmentDueItems(
        plans: [PlanningInstallmentSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> [PlanningRecurringDueSnapshot] {
        dueItems(
            sourceKind: .installment,
            selectedMonth: selectedMonth,
            calendar: calendar
        ) { monthKey in
            plans.compactMap { plan in
                guard isScheduledMonth(
                    selectedMonth: selectedMonth,
                    anchorDate: plan.createdAt,
                    frequencyMonths: plan.frequencyMonths,
                    totalCycles: plan.totalCycles,
                    calendar: calendar
                ) else {
                    return nil
                }

                let occurrence = occurrenceRecord(
                    for: .installment,
                    sourceID: plan.id,
                    monthKey: monthKey,
                    occurrences: occurrences
                )

                return PlanningRecurringDueSnapshot(
                    id: plan.id,
                    sourceKind: .installment,
                    sourceID: plan.id,
                    name: plan.name,
                    iconSymbolName: plan.iconSymbolName,
                    categorySystemKey: .loanRepayment,
                    amountMinor: occurrence?.amountMinorSnapshot ?? plan.amountPerCycleMinor,
                    dueDate: scheduledDate(dueDay: plan.dueDay, selectedMonth: selectedMonth, calendar: calendar),
                    frequencyMonths: plan.frequencyMonths,
                    totalCycles: plan.totalCycles,
                    paymentWalletID: plan.paymentWalletID,
                    currencyCode: plan.currencyCode,
                    status: occurrence?.status ?? .pending,
                    linkedTransactionID: occurrence?.linkedTransactionID
                )
            }
        }
    }

    static func dueSummary(
        creditStatements: [PlanningCreditCardStatementSnapshot],
        recurring: [PlanningRecurringDueSnapshot],
        selectedMonth: Date,
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> PlanningDueSummarySnapshot {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let windowEnd = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
        let selectedMonthStart = startOfMonth(for: selectedMonth, calendar: calendar)

        let pendingStatements = creditStatements.filter {
            $0.status == .pending
                && $0.amountMinor > 0
                && isSameMonth($0.dueDate, other: selectedMonthStart, calendar: calendar)
        }
        let pendingRecurring = recurring.filter {
            $0.status == .pending
                && isSameMonth($0.paymentStartDate, other: selectedMonthStart, calendar: calendar)
        }

        // Sắp đến hạn: Trong vòng 7 ngày tới
        let upcomingCards = pendingStatements.filter { $0.dueDate >= startOfToday && $0.dueDate <= windowEnd }
        let upcomingRecurring = pendingRecurring.filter {
            ($0.paymentStartDate >= startOfToday && $0.paymentStartDate <= windowEnd)
                || ($0.hasExplicitDueDate && $0.dueDate >= startOfToday && $0.dueDate <= windowEnd)
        }
        let upcomingCount = upcomingCards.count + upcomingRecurring.count

        let totalDueCards = pendingStatements.reduce(into: Int64.zero) { partial, statement in
            partial += reportingAmount(
                amountMinor: statement.amountMinor,
                sourceCurrencyCode: statement.currencyCode,
                currencyCode: reportingCurrencyCode ?? statement.currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let totalDueRecurring = pendingRecurring.reduce(into: Int64.zero) { partial, item in
            guard let amountMinor = item.amountMinor else { return }
            partial += reportingAmount(
                amountMinor: amountMinor,
                sourceCurrencyCode: item.currencyCode,
                currencyCode: reportingCurrencyCode ?? item.currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let totalDueMinor = totalDueCards + totalDueRecurring

        // Quá hạn
        let overdueCount: Int
        if isPastMonth(selectedMonth, referenceDate: referenceDate, calendar: calendar) {
            overdueCount = pendingStatements.count + pendingRecurring.count
        } else if isSameMonth(selectedMonth, other: referenceDate, calendar: calendar) {
            let overdueCards = pendingStatements.filter { $0.dueDate < startOfToday }
            let overdueRecurring = pendingRecurring.filter { $0.dueDate < startOfToday }
            overdueCount = overdueCards.count + overdueRecurring.count
        } else {
            overdueCount = 0
        }

        return PlanningDueSummarySnapshot(
            upcomingCount: upcomingCount,
            totalDueMinor: totalDueMinor,
            overdueCount: overdueCount
        )
    }

    static func dueSummary(
        creditCards: [PlanningCreditCardDueSnapshot],
        recurring: [PlanningRecurringDueSnapshot],
        selectedMonth: Date,
        reportingCurrencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> PlanningDueSummarySnapshot {
        let statements = creditCards.map { card in
            PlanningCreditCardStatementSnapshot(
                id: "\(card.walletID.uuidString.lowercased())-\(monthKey(for: card.dueDate, calendar: calendar))",
                walletID: card.walletID,
                walletName: card.walletName,
                issuerName: "",
                network: card.network,
                last4: card.last4,
                statementMonth: selectedMonth,
                closingDate: selectedMonth,
                dueDate: card.dueDate,
                amountMinor: card.amountMinor,
                availableCreditMinor: card.availableCreditMinor,
                paymentSourceWalletID: card.paymentSourceWalletID,
                paymentSourceWalletName: nil,
                currencyCode: card.currencyCode,
                status: card.status,
                linkedTransactionID: card.linkedTransactionID,
                state: card.status == .paid ? .paid : .payable
            )
        }
        return dueSummary(
            creditStatements: statements,
            recurring: recurring,
            selectedMonth: selectedMonth,
            reportingCurrencyCode: reportingCurrencyCode,
            exchangeRates: exchangeRates,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func makePaymentDraft(
        for creditCard: PlanningCreditCardDueSnapshot,
        overrideAmountMinor: Int64? = nil
    ) throws -> PlanningDuePaymentDraft {
        guard let sourceWalletID = creditCard.paymentSourceWalletID else {
            throw PlanningDuePaymentError.missingSourceWallet
        }

        let amount = overrideAmountMinor ?? creditCard.amountMinor
        guard amount > 0 else {
            throw PlanningDuePaymentError.missingAmount
        }

        return PlanningDuePaymentDraft(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ \(creditCard.walletName)",
            amountMinor: amount,
            sourceWalletID: sourceWalletID,
            destinationWalletID: creditCard.walletID,
            categorySystemKey: nil
        )
    }

    static func makePaymentDraft(
        for statement: PlanningCreditCardStatementSnapshot,
        overrideAmountMinor: Int64? = nil
    ) throws -> PlanningDuePaymentDraft {
        guard let sourceWalletID = statement.paymentSourceWalletID else {
            throw PlanningDuePaymentError.missingSourceWallet
        }

        let amount = overrideAmountMinor ?? statement.amountMinor
        guard amount > 0 else {
            throw PlanningDuePaymentError.missingAmount
        }

        return PlanningDuePaymentDraft(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ \(statement.walletName)",
            amountMinor: amount,
            sourceWalletID: sourceWalletID,
            destinationWalletID: statement.walletID,
            categorySystemKey: nil
        )
    }

    static func makePaymentDraft(
        for recurringItem: PlanningRecurringDueSnapshot,
        overrideAmountMinor: Int64? = nil,
        sourceWalletIDOverride: UUID? = nil
    ) throws -> PlanningDuePaymentDraft {
        guard let sourceWalletID = sourceWalletIDOverride ?? recurringItem.paymentWalletID else {
            throw PlanningDuePaymentError.missingSourceWallet
        }

        let amount = overrideAmountMinor ?? recurringItem.amountMinor
        guard let amount, amount > 0 else {
            throw PlanningDuePaymentError.missingAmount
        }

        let systemKey: MistiaSystemCategoryKey
        switch recurringItem.sourceKind {
        case .recurringBill:
            systemKey = recurringItem.categorySystemKey ?? .billing
        case .installment:
            systemKey = .loanRepayment
        case .creditCard:
            systemKey = .billing
        }

        return PlanningDuePaymentDraft(
            primaryKind: .expense,
            transferSubtype: nil,
            title: recurringItem.name,
            amountMinor: amount,
            sourceWalletID: sourceWalletID,
            destinationWalletID: nil,
            categorySystemKey: systemKey
        )
    }

    static func monthKey(for date: Date, calendar: Calendar = MistiaCalendar.current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func month(from key: String, calendar: Calendar = MistiaCalendar.current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components)
    }

    static func startOfMonth(for date: Date, calendar: Calendar = MistiaCalendar.current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func endOfMonth(for date: Date, calendar: Calendar = MistiaCalendar.current) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            return date
        }

        return interval.end.addingTimeInterval(-1)
    }

    static func scheduledDate(
        dueDay: Int,
        selectedMonth: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        let monthStart = startOfMonth(for: selectedMonth, calendar: calendar)
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let clampedDay = min(max(dueDay, 1), maxDay)

        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
    }

    private struct RecurringBillWindow {
        let paymentStartDate: Date
        let dueDate: Date
        let hasExplicitDueDate: Bool
        let autoPayDate: Date?
    }

    private static func recurringBillWindow(
        for bill: PlanningBillSnapshot,
        selectedMonth: Date,
        calendar: Calendar
    ) -> RecurringBillWindow? {
        switch bill.scheduleKind {
        case .recurring:
            guard isScheduledMonth(
                selectedMonth: selectedMonth,
                anchorDate: bill.firstScheduledMonth ?? bill.createdAt,
                frequencyMonths: bill.frequencyMonths,
                totalCycles: nil,
                calendar: calendar
            ) else {
                return nil
            }

            let paymentStartDate = scheduledDate(
                dueDay: bill.paymentStartDay,
                selectedMonth: selectedMonth,
                calendar: calendar
            )
            let hasExplicitDueDate = bill.hasExplicitDueDate && bill.dueDay != bill.paymentStartDay
            let dueDate: Date
            if hasExplicitDueDate {
                let dueMonth = bill.dueDay < bill.paymentStartDay
                    ? calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    : selectedMonth
                dueDate = scheduledDate(dueDay: bill.dueDay, selectedMonth: dueMonth, calendar: calendar)
            } else {
                dueDate = paymentStartDate
            }

            return RecurringBillWindow(
                paymentStartDate: paymentStartDate,
                dueDate: dueDate,
                hasExplicitDueDate: hasExplicitDueDate,
                autoPayDate: autoPayDate(
                    enabled: bill.autoPayEnabled,
                    autoPayDay: bill.autoPayDay,
                    paymentStartDay: bill.paymentStartDay,
                    paymentStartDate: paymentStartDate,
                    dueDay: bill.dueDay,
                    dueDate: dueDate,
                    hasExplicitDueDate: hasExplicitDueDate,
                    selectedMonth: selectedMonth,
                    calendar: calendar
                )
            )

        case .oneTime:
            guard let paymentStartDate = bill.paymentStartDate else { return nil }
            guard isSameMonth(paymentStartDate, other: selectedMonth, calendar: calendar) else { return nil }

            let hasExplicitDueDate = bill.hasExplicitDueDate
                && bill.dueDate != nil
                && calendar.startOfDay(for: bill.dueDate ?? paymentStartDate) != calendar.startOfDay(for: paymentStartDate)
                && calendar.startOfDay(for: bill.dueDate ?? paymentStartDate) >= calendar.startOfDay(for: paymentStartDate)
            let dueDate = hasExplicitDueDate ? (bill.dueDate ?? paymentStartDate) : paymentStartDate
            let autoPayDate = bill.autoPayEnabled
                ? normalizedAutoPayDate(bill.autoPayDate, paymentStartDate: paymentStartDate, dueDate: dueDate, calendar: calendar)
                : nil

            return RecurringBillWindow(
                paymentStartDate: paymentStartDate,
                dueDate: dueDate,
                hasExplicitDueDate: hasExplicitDueDate,
                autoPayDate: autoPayDate
            )
        }
    }

    private static func autoPayDate(
        enabled: Bool,
        autoPayDay: Int?,
        paymentStartDay: Int,
        paymentStartDate: Date,
        dueDay: Int,
        dueDate: Date,
        hasExplicitDueDate: Bool,
        selectedMonth: Date,
        calendar: Calendar
    ) -> Date? {
        guard enabled else { return nil }
        guard hasExplicitDueDate, let autoPayDay else {
            return paymentStartDate
        }

        let autoPayMonth = dueDay < paymentStartDay && autoPayDay < paymentStartDay
            ? calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            : selectedMonth
        let candidate = scheduledDate(dueDay: autoPayDay, selectedMonth: autoPayMonth, calendar: calendar)
        return normalizedAutoPayDate(candidate, paymentStartDate: paymentStartDate, dueDate: dueDate, calendar: calendar)
    }

    private static func normalizedAutoPayDate(
        _ candidate: Date?,
        paymentStartDate: Date,
        dueDate: Date,
        calendar: Calendar
    ) -> Date {
        guard let candidate else { return paymentStartDate }
        let day = calendar.startOfDay(for: candidate)
        let start = calendar.startOfDay(for: paymentStartDate)
        let due = calendar.startOfDay(for: dueDate)
        guard day >= start, day <= due else { return paymentStartDate }
        return day
    }

    private static func creditCardStatementItem(
        account: PlanningCreditCardAccountSnapshot,
        records: [TransactionRecordSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        statementMonth: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> PlanningCreditCardStatementSnapshot? {
        let monthStart = startOfMonth(for: statementMonth, calendar: calendar)
        let closingDate = creditCardStatementClosingDate(
            statementMonth: monthStart,
            statementClosingDay: account.statementClosingDay,
            calendar: calendar
        )
        let dueDate = creditCardStatementDueDate(
            statementMonth: monthStart,
            statementClosingDay: account.statementClosingDay,
            paymentDueDay: account.dueDay,
            calendar: calendar
        )
        let statementMonthKey = monthKey(for: monthStart, calendar: calendar)
        let legacyDueMonthKey = monthKey(for: dueDate, calendar: calendar)
        let occurrence = occurrenceRecord(
            for: .creditCard,
            sourceID: account.walletID,
            monthKey: statementMonthKey,
            occurrences: occurrences
        ) ?? occurrenceRecord(
            for: .creditCard,
            sourceID: account.walletID,
            monthKey: legacyDueMonthKey,
            occurrences: occurrences
        )
        let computedAmount = creditCardStatementAmount(
            walletID: account.walletID,
            records: records,
            statementMonth: monthStart,
            calendar: calendar
        )
        let matchedOccurrence = occurrence.flatMap { occurrence -> PlanningDueOccurrenceSnapshot? in
            guard let snapshotAmount = occurrence.amountMinorSnapshot,
                  snapshotAmount == computedAmount,
                  computedAmount > 0 else {
                return nil
            }
            return occurrence
        }
        let amount = matchedOccurrence?.amountMinorSnapshot ?? computedAmount
        if calendar.compare(
            account.openedAt,
            to: endOfMonth(for: monthStart, calendar: calendar),
            toGranularity: .second
        ) == .orderedDescending,
           matchedOccurrence == nil,
           amount <= 0 {
            return nil
        }

        let inferredPayment = creditCardStatementPaymentRecord(
            walletID: account.walletID,
            amountMinor: amount,
            closingDate: closingDate,
            records: records,
            calendar: calendar
        )
        let status: PlanningDueOccurrenceStatus =
            matchedOccurrence?.status == .paid || inferredPayment != nil
            ? .paid
            : .pending
        let linkedTransactionID = matchedOccurrence?.status == .paid
            ? matchedOccurrence?.linkedTransactionID ?? inferredPayment?.id
            : inferredPayment?.id ?? matchedOccurrence?.linkedTransactionID
        let state = creditCardStatementState(
            status: status,
            amountMinor: amount,
            closingDate: closingDate,
            dueDate: dueDate,
            referenceDate: referenceDate,
            calendar: calendar
        )

        return PlanningCreditCardStatementSnapshot(
            id: "\(account.walletID.uuidString.lowercased())-\(monthKey(for: monthStart, calendar: calendar))",
            walletID: account.walletID,
            walletName: account.walletName,
            issuerName: account.issuerName,
            network: account.network,
            last4: account.last4,
            statementMonth: monthStart,
            closingDate: closingDate,
            dueDate: dueDate,
            amountMinor: amount,
            availableCreditMinor: account.availableCreditMinor,
            paymentSourceWalletID: account.paymentSourceWalletID,
            paymentSourceWalletName: account.paymentSourceWalletName,
            currencyCode: account.currencyCode,
            status: status,
            linkedTransactionID: linkedTransactionID,
            state: state
        )
    }

    private static func creditCardStatementAmount(
        walletID: UUID,
        records: [TransactionRecordSnapshot],
        statementMonth: Date,
        calendar: Calendar
    ) -> Int64 {
        guard let monthInterval = calendar.dateInterval(of: .month, for: statementMonth) else {
            return 0
        }

        return records.reduce(into: Int64.zero) { partial, record in
            guard record.entryStatus == .posted,
                  !record.isArchived,
                  TransactionLogic.isExpenseSpending(record),
                  record.sourceWalletID == walletID,
                  record.occurredAt >= monthInterval.start,
                  record.occurredAt < monthInterval.end
            else {
                return
            }

            partial += record.amountMinor
        }
    }

    static func creditCardStatementPaymentRecord(
        walletID: UUID,
        amountMinor: Int64,
        closingDate: Date,
        records: [TransactionRecordSnapshot],
        calendar: Calendar = MistiaCalendar.current
    ) -> TransactionRecordSnapshot? {
        guard amountMinor > 0 else { return nil }
        let closingDay = calendar.startOfDay(for: closingDate)

        return records
            .filter { record in
                guard record.entryStatus == .posted,
                      !record.isArchived,
                      record.primaryKind == .transfer,
                      record.transferSubtype == .internalTransfer,
                      record.destinationWalletID == walletID,
                      record.occurredAt >= closingDay
                else {
                    return false
                }

                let paidAmount = record.destinationAmountMinor ?? record.amountMinor
                return paidAmount >= amountMinor
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }
                return $0.createdAt < $1.createdAt
            }
            .first
    }

    static func creditCardStatementState(
        status: PlanningDueOccurrenceStatus,
        amountMinor: Int64,
        closingDate: Date,
        dueDate: Date,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> PlanningCreditCardStatementState {
        if status == .paid {
            return .paid
        }

        let today = calendar.startOfDay(for: referenceDate)
        let closingDay = calendar.startOfDay(for: closingDate)
        if today < closingDay {
            return .unclosed
        }

        if amountMinor <= 0 {
            return .paid
        }

        if calendar.startOfDay(for: dueDate) < today {
            return .overdue
        }

        return .payable
    }

    static func paidCreditCardStatementForExpense(
        account: PlanningCreditCardAccountSnapshot,
        records: [TransactionRecordSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        occurredAt: Date,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> PlanningCreditCardStatementSnapshot? {
        let statements = creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: occurrences,
            statementMonths: [occurredAt],
            referenceDate: referenceDate,
            calendar: calendar
        )

        guard let statement = statements.first, statement.state == .paid else {
            return nil
        }

        return statement
    }

    static func creditCardAutoPaymentDecision(
        statement: PlanningCreditCardStatementSnapshot,
        sourceWalletBalanceMinor: Int64?,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> PlanningCreditCardAutoPaymentDecision {
        guard statement.status == .pending, statement.state != .paid, statement.amountMinor > 0 else {
            return .alreadyPaid
        }

        let today = calendar.startOfDay(for: referenceDate)
        let dueDay = calendar.startOfDay(for: statement.dueDate)
        guard today >= dueDay else {
            return .notDue
        }
        let lastRetryDay = calendar.date(byAdding: .day, value: 5, to: dueDay) ?? dueDay
        guard today <= lastRetryDay else {
            return .notDue
        }

        guard statement.paymentSourceWalletID != nil, let sourceWalletBalanceMinor else {
            return .missingLinkedWallet
        }

        guard sourceWalletBalanceMinor >= statement.amountMinor else {
            return .insufficientFunds(
                availableMinor: sourceWalletBalanceMinor,
                requiredMinor: statement.amountMinor
            )
        }

        return .payable
    }

    private static func reportingAmount(
        for record: TransactionRecordSnapshot,
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate]
    ) -> Int64 {
        MistiaCurrencyLogic.reportingMinorAmount(
            for: record,
            reportingCurrencyCode: currencyCode,
            rates: exchangeRates
        ) ?? 0
    }

    private static func reportingAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String,
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate]
    ) -> Int64 {
        MistiaCurrencyLogic.reportingMinorAmount(
            amountMinor: amountMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            reportingCurrencyCode: currencyCode,
            rates: exchangeRates
        ) ?? 0
    }

    static func monthsRemaining(
        from selectedMonth: Date,
        to targetDate: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> Int {
        let start = startOfMonth(for: selectedMonth, calendar: calendar)
        let targetMonth = startOfMonth(for: targetDate, calendar: calendar)
        let difference = calendar.dateComponents([.month], from: start, to: targetMonth).month ?? 0
        return max(difference + 1, 1)
    }

    private static func dueItems(
        sourceKind: PlanningDueSourceKind,
        selectedMonth: Date,
        calendar: Calendar,
        builder: (_ monthKey: String) -> [PlanningRecurringDueSnapshot]
    ) -> [PlanningRecurringDueSnapshot] {
        builder(monthKey(for: selectedMonth, calendar: calendar))
            .sorted(by: dueSort)
    }

    private static func occurrenceRecord(
        for sourceKind: PlanningDueSourceKind,
        sourceID: UUID,
        monthKey: String,
        occurrences: [PlanningDueOccurrenceSnapshot]
    ) -> PlanningDueOccurrenceSnapshot? {
        occurrences.first(where: {
            $0.sourceKind == sourceKind
                && $0.sourceID == sourceID
                && $0.selectedMonthKey == monthKey
        })
    }

    private static func isScheduledMonth(
        selectedMonth: Date,
        anchorDate: Date,
        frequencyMonths: Int,
        totalCycles: Int?,
        calendar: Calendar
    ) -> Bool {
        let anchorMonth = startOfMonth(for: anchorDate, calendar: calendar)
        let targetMonth = startOfMonth(for: selectedMonth, calendar: calendar)
        let monthDelta = calendar.dateComponents([.month], from: anchorMonth, to: targetMonth).month ?? 0

        guard monthDelta >= 0 else { return false }

        let cycleLength = max(frequencyMonths, 1)
        guard monthDelta % cycleLength == 0 else { return false }

        let cycleIndex = monthDelta / cycleLength
        if let totalCycles {
            return cycleIndex < totalCycles
        }

        return true
    }

    private static func isSameMonth(
        _ lhs: Date,
        other rhs: Date,
        calendar: Calendar
    ) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    private static func isPastMonth(
        _ selectedMonth: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        let lhs = startOfMonth(for: selectedMonth, calendar: calendar)
        let rhs = startOfMonth(for: referenceDate, calendar: calendar)
        return lhs < rhs
    }

    private static func daysRemainingInMonth(
        for selectedMonth: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        let monthEnd = endOfMonth(for: selectedMonth, calendar: calendar)
        if isPastMonth(selectedMonth, referenceDate: referenceDate, calendar: calendar) {
            return 0
        }

        if isSameMonth(selectedMonth, other: referenceDate, calendar: calendar) {
            let start = calendar.startOfDay(for: referenceDate)
            return max((calendar.dateComponents([.day], from: start, to: monthEnd).day ?? 0) + 1, 0)
        }

        let monthStart = startOfMonth(for: selectedMonth, calendar: calendar)
        return (calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 0) + 1
    }

    private nonisolated static func dueSort<T: DueSortable>(lhs: T, rhs: T) -> Bool {
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private nonisolated struct PendingDueSnapshot: Equatable {
    let date: Date
    let amountMinor: Int64?
}

private nonisolated protocol DueSortable {
    var dueDate: Date { get }
    var displayName: String { get }
}

nonisolated extension PlanningCreditCardDueSnapshot: DueSortable {
    fileprivate var displayName: String { walletName }
}

nonisolated extension PlanningCreditCardStatementSnapshot: DueSortable {
    fileprivate var displayName: String { walletName }
}

nonisolated extension PlanningRecurringDueSnapshot: DueSortable {
    fileprivate var displayName: String { name }
}
