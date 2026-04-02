import Foundation

nonisolated struct BudgetPlanSnapshot: Equatable, Identifiable {
    let id: UUID
    let categoryID: UUID?
    let categoryName: String
    let categoryIconSymbolName: String
    let categoryColorHex: String
    let limitMinor: Int64
    let rolloverEnabled: Bool
    let currencyCode: String
    let monthAnchor: Date
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
            mistiaLocalized(vi: "Ổn định", en: "Stable", ja: "安定")
        case .caution:
            mistiaLocalized(vi: "Cần chú ý", en: "Needs attention", ja: "注意")
        case .exceeded:
            mistiaLocalized(vi: "Vượt kế hoạch", en: "Exceeded", ja: "超過")
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
    let network: CreditCardNetwork
    let last4: String
    let dueDay: Int
    let paymentSourceWalletID: UUID?
    let currencyCode: String
    let currentDebtMinor: Int64
    let openedAt: Date
}

nonisolated struct PlanningBillSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let amountMinor: Int64?
    let dueDay: Int
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let createdAt: Date
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
    let amountMinor: Int64?
    let dueDate: Date
    let frequencyMonths: Int
    let totalCycles: Int?
    let paymentWalletID: UUID?
    let currencyCode: String
    let status: PlanningDueOccurrenceStatus
    let linkedTransactionID: UUID?
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

nonisolated enum PlanningLogic {
    static func health(forProgress progress: Double) -> PlanningBudgetHealth {
        if progress > 1 {
            return .exceeded
        }

        if progress >= 0.7 {
            return .caution
        }

        return .stable
    }

    static func tone(forProgress progress: Double) -> PlanningBudgetTone {
        if progress >= 0.9 {
            return .critical
        }

        if progress >= 0.7 {
            return .warning
        }

        return .calm
    }

    static func budgetRows(
        plans: [BudgetPlanSnapshot],
        records: [TransactionRecordSnapshot],
        selectedMonth: Date,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [PlanningBudgetRowSnapshot] {
        let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth)
        let spentByCategory = Dictionary(grouping: records.filter { record in
            guard record.entryStatus == .posted,
                  record.primaryKind == .expense,
                  record.categoryID != nil,
                  let monthInterval
            else {
                return false
            }

            return monthInterval.contains(record.occurredAt)
        }, by: \.categoryID)

        let remainingDays = daysRemainingInMonth(for: selectedMonth, referenceDate: referenceDate, calendar: calendar)
        let isPastMonth = isPastMonth(selectedMonth, referenceDate: referenceDate, calendar: calendar)

        return plans
            .map { plan in
                let spent = spentByCategory[plan.categoryID]?
                    .reduce(into: Int64.zero) { partial, record in
                        partial += record.amountMinor
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

    static func budgetSummary(from rows: [PlanningBudgetRowSnapshot]) -> PlanningBudgetSummarySnapshot {
        let totalBudget = rows.reduce(into: Int64.zero) { partial, row in
            partial += row.limitMinor
        }
        let spent = rows.reduce(into: Int64.zero) { partial, row in
            partial += row.spentMinor
        }
        let remaining = max(totalBudget - spent, 0)

        return PlanningBudgetSummarySnapshot(
            totalBudgetMinor: totalBudget,
            spentMinor: spent,
            remainingMinor: remaining,
            health: health(forProgress: totalBudget > 0 ? Double(spent) / Double(totalBudget) : 0)
        )
    }

    static func goalRows(
        goals: [SavingsGoalSnapshot],
        selectedMonth: Date,
        calendar: Calendar = .current
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

    static func goalSummary(from rows: [PlanningGoalRowSnapshot]) -> PlanningGoalSummarySnapshot {
        let nearest = rows.max { lhs, rhs in
            if lhs.progress != rhs.progress {
                return lhs.progress < rhs.progress
            }
            return lhs.targetDate > rhs.targetDate
        }

        return PlanningGoalSummarySnapshot(
            activeCount: rows.count,
            totalSavedMinor: rows.reduce(into: Int64.zero) { partial, row in
                partial += row.currentSavedMinor
            },
            nearestGoalName: nearest?.name
        )
    }

    static func creditCardDueItems(
        accounts: [PlanningCreditCardAccountSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [PlanningCreditCardDueSnapshot] {
        let monthKey = monthKey(for: selectedMonth, calendar: calendar)

        return accounts
            .filter { account in
                calendar.compare(account.openedAt, to: endOfMonth(for: selectedMonth, calendar: calendar), toGranularity: .second) != .orderedDescending
            }
            .map { account in
                let scheduledDate = scheduledDate(
                    dueDay: account.dueDay,
                    selectedMonth: selectedMonth,
                    calendar: calendar
                )
                let occurrence = occurrenceRecord(
                    for: .creditCard,
                    sourceID: account.walletID,
                    monthKey: monthKey,
                    occurrences: occurrences
                )
                let amount = occurrence?.amountMinorSnapshot ?? account.currentDebtMinor

                return PlanningCreditCardDueSnapshot(
                    id: account.id,
                    walletID: account.walletID,
                    walletName: account.walletName,
                    network: account.network,
                    last4: account.last4,
                    amountMinor: amount,
                    dueDate: scheduledDate,
                    paymentSourceWalletID: account.paymentSourceWalletID,
                    currencyCode: account.currencyCode,
                    status: occurrence?.status ?? .pending,
                    linkedTransactionID: occurrence?.linkedTransactionID
                )
            }
            .sorted(by: dueSort)
    }

    static func recurringBillDueItems(
        bills: [PlanningBillSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        calendar: Calendar = .current
    ) -> [PlanningRecurringDueSnapshot] {
        dueItems(
            sourceKind: .recurringBill,
            selectedMonth: selectedMonth,
            calendar: calendar
        ) { monthKey in
            bills.compactMap { bill in
                guard isScheduledMonth(
                    selectedMonth: selectedMonth,
                    anchorDate: bill.createdAt,
                    frequencyMonths: bill.frequencyMonths,
                    totalCycles: nil,
                    calendar: calendar
                ) else {
                    return nil
                }

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
                    amountMinor: occurrence?.amountMinorSnapshot ?? bill.amountMinor,
                    dueDate: scheduledDate(dueDay: bill.dueDay, selectedMonth: selectedMonth, calendar: calendar),
                    frequencyMonths: bill.frequencyMonths,
                    totalCycles: nil,
                    paymentWalletID: bill.paymentWalletID,
                    currencyCode: bill.currencyCode,
                    status: occurrence?.status ?? .pending,
                    linkedTransactionID: occurrence?.linkedTransactionID
                )
            }
        }
    }

    static func installmentDueItems(
        plans: [PlanningInstallmentSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonth: Date,
        calendar: Calendar = .current
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
        creditCards: [PlanningCreditCardDueSnapshot],
        recurring: [PlanningRecurringDueSnapshot],
        selectedMonth: Date,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> PlanningDueSummarySnapshot {
        let pendingCards = creditCards.filter { $0.status == .pending }
        let pendingRecurring = recurring.filter { $0.status == .pending }
        let pendingCombined = pendingCards.map {
            PendingDueSnapshot(date: $0.dueDate, amountMinor: $0.amountMinor)
        } + pendingRecurring.map {
            PendingDueSnapshot(date: $0.dueDate, amountMinor: $0.amountMinor)
        }

        if isSameMonth(selectedMonth, other: referenceDate, calendar: calendar) {
            let start = calendar.startOfDay(for: referenceDate)
            let windowEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let overdue = pendingCombined.filter { $0.date < start }
            let upcoming = pendingCombined.filter { $0.date >= start && $0.date <= windowEnd }

            return PlanningDueSummarySnapshot(
                upcomingCount: upcoming.count,
                totalDueMinor: upcoming.reduce(into: Int64.zero) { partial, snapshot in
                    partial += snapshot.amountMinor ?? 0
                },
                overdueCount: overdue.count
            )
        }

        return PlanningDueSummarySnapshot(
            upcomingCount: pendingCombined.count,
            totalDueMinor: pendingCombined.reduce(into: Int64.zero) { partial, snapshot in
                partial += snapshot.amountMinor ?? 0
            },
            overdueCount: 0
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
        for recurringItem: PlanningRecurringDueSnapshot,
        overrideAmountMinor: Int64? = nil
    ) throws -> PlanningDuePaymentDraft {
        guard let sourceWalletID = recurringItem.paymentWalletID else {
            throw PlanningDuePaymentError.missingSourceWallet
        }

        let amount = overrideAmountMinor ?? recurringItem.amountMinor
        guard let amount, amount > 0 else {
            throw PlanningDuePaymentError.missingAmount
        }

        let systemKey: MistiaSystemCategoryKey = recurringItem.sourceKind == .recurringBill ? .billing : .loanRepayment

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

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func endOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            return date
        }

        return interval.end.addingTimeInterval(-1)
    }

    static func scheduledDate(
        dueDay: Int,
        selectedMonth: Date,
        calendar: Calendar = .current
    ) -> Date {
        let monthStart = startOfMonth(for: selectedMonth, calendar: calendar)
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let clampedDay = min(max(dueDay, 1), maxDay)

        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
    }

    static func monthsRemaining(
        from selectedMonth: Date,
        to targetDate: Date,
        calendar: Calendar = .current
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

nonisolated extension PlanningRecurringDueSnapshot: DueSortable {
    fileprivate var displayName: String { name }
}
