import Foundation

nonisolated enum OverviewTint: String, Equatable {
    case green
    case orange
    case red
    case blue
}

nonisolated enum OverviewCashflowStyle: String, Equatable {
    case income
    case expense
    case neutral
}

nonisolated struct OverviewWalletSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let kind: LedgerWalletKind
    let openingBalanceMinor: Int64
    let currencyCode: String
    let sortOrder: Int
    let createdAt: Date
}

nonisolated struct OverviewCreditCardStatementAccountSnapshot: Equatable, Identifiable {
    let id: UUID
    let walletID: UUID
    let walletName: String
    let iconSymbolName: String
    let issuerName: String
    let network: CreditCardNetwork
    let last4: String
    let creditLimitMinor: Int64
    let currentDebtMinor: Int64
    let availableCreditMinor: Int64
    let statementClosingDay: Int
    let paymentDueDay: Int
    let paymentSourceWalletName: String?
    let currencyCode: String
    let openedAt: Date
}

nonisolated struct OverviewTransactionSnapshot: Equatable, Identifiable {
    let id: UUID
    let primaryKind: TransactionPrimaryKind
    let transferSubtype: TransactionTransferSubtype?
    let debtIntent: TransactionDebtIntent?
    let entryStatus: TransactionEntryStatus
    let title: String
    let note: String?
    let amountMinor: Int64
    let occurredAt: Date
    let createdAt: Date
    let sourceWalletID: UUID?
    let sourceWalletName: String?
    let sourceWalletKind: LedgerWalletKind?
    let destinationWalletID: UUID?
    let destinationWalletName: String?
    let destinationWalletKind: LedgerWalletKind?
    let categoryID: UUID?
    let categoryName: String?
    let categoryIconSymbolName: String?  // Icon of transaction category
    let counterpartyName: String?
    let isArchived: Bool
}

nonisolated struct OverviewChartPoint: Equatable, Identifiable {
    let date: Date
    let label: String
    let valueMinor: Int64
    let intensity: Double

    var id: String {
        label + "-" + String(Int(date.timeIntervalSince1970))
    }
}

nonisolated struct OverviewWeekSpendingSnapshot: Equatable, Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let title: String
    let isCurrentWeek: Bool
    let points: [OverviewChartPoint]

    var id: String {
        String(Int(weekStart.timeIntervalSince1970))
    }
}

nonisolated struct OverviewHeroSnapshot: Equatable {
    let totalAssetBalanceMinor: Int64
    let incomeThisMonthMinor: Int64
    let expenseThisMonthMinor: Int64
    let weekPages: [OverviewWeekSpendingSnapshot]
    let currentWeekStart: Date
    let currencyCode: String
}

nonisolated struct OverviewBudgetAlertSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let spentMinor: Int64
    let limitMinor: Int64
    let currencyCode: String
    let progress: Double
    let daysRemaining: Int
    let tint: OverviewTint

    var progressPercentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

nonisolated struct OverviewDueAlertSnapshot: Equatable, Identifiable {
    let id: String
    let name: String
    let iconSymbolName: String
    let amountMinor: Int64?
    let dueDate: Date
    let dayDelta: Int
    let currencyCode: String
    let tint: OverviewTint
}

nonisolated struct OverviewRecentTransactionSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let amountMinor: Int64
    let currencyCode: String
    let occurredAt: Date
    let timeLabel: String
    let cashflowStyle: OverviewCashflowStyle
    let categoryIconSymbolName: String  // Icon of transaction category
}

nonisolated struct OverviewDashboardSnapshot: Equatable {
    let hero: OverviewHeroSnapshot
    let budgetAlerts: [OverviewBudgetAlertSnapshot]
    let dueAlerts: [OverviewDueAlertSnapshot]
    let recentTransactions: [OverviewRecentTransactionSnapshot]
}

nonisolated enum OverviewLogic {
    static func dashboard(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        transactions: [OverviewTransactionSnapshot],
        budgets: [BudgetPlanSnapshot],
        creditCardDues: [PlanningCreditCardDueSnapshot],
        recurringDues: [PlanningRecurringDueSnapshot],
        currencyCode: String,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> OverviewDashboardSnapshot {
        OverviewDashboardSnapshot(
            hero: hero(
                wallets: wallets,
                transactionRecords: transactionRecords,
                currencyCode: currencyCode,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            budgetAlerts: budgetAlerts(
                budgets: budgets,
                transactionRecords: transactionRecords,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            dueAlerts: dueAlerts(
                creditCardDues: creditCardDues,
                recurringDues: recurringDues,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            recentTransactions: recentTransactions(
                transactions: transactions,
                currencyCode: currencyCode,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    static func hero(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        currencyCode: String,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> OverviewHeroSnapshot {
        let monthInterval = calendar.dateInterval(of: .month, for: referenceDate)

        let incomeThisMonth = transactionRecords
            .filter { record in
                guard record.entryStatus == .posted,
                      record.primaryKind == .income,
                      let monthInterval
                else {
                    return false
                }

                return monthInterval.contains(record.occurredAt)
            }
            .reduce(into: Int64.zero) { partialResult, record in
                partialResult += record.amountMinor
            }

        let expenseThisMonth = transactionRecords
            .filter { record in
                guard record.entryStatus == .posted,
                      record.primaryKind == .expense,
                      let monthInterval
                else {
                    return false
                }

                return monthInterval.contains(record.occurredAt)
            }
            .reduce(into: Int64.zero) { partialResult, record in
                partialResult += record.amountMinor
            }

        return OverviewHeroSnapshot(
            totalAssetBalanceMinor: totalAssetBalance(
                wallets: wallets,
                transactionRecords: transactionRecords
            ),
            incomeThisMonthMinor: incomeThisMonth,
            expenseThisMonthMinor: expenseThisMonth,
            weekPages: weeklySpendingPages(
                from: transactionRecords,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            currentWeekStart: startOfMondayWeek(containing: referenceDate, calendar: calendar),
            currencyCode: currencyCode
        )
    }

    static func totalAssetBalance(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot]
    ) -> Int64 {
        wallets
            .filter { $0.kind != .creditCard }
            .reduce(into: Int64.zero) { partialResult, wallet in
                partialResult += TransactionLogic.effectiveBalance(
                    for: TransactionWalletSnapshot(
                        id: wallet.id,
                        kind: wallet.kind,
                        openingBalanceMinor: wallet.openingBalanceMinor
                    ),
                    records: transactionRecords
                )
            }
    }

    static func weeklySpendingPages(
        from transactionRecords: [TransactionRecordSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [OverviewWeekSpendingSnapshot] {
        let currentWeekStart = startOfMondayWeek(containing: referenceDate, calendar: calendar)
        let currentWeekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart

        let earliestExpenseWeekStart = transactionRecords
            .filter { $0.entryStatus == .posted && $0.primaryKind == .expense }
            .map { startOfMondayWeek(containing: $0.occurredAt, calendar: calendar) }
            .min()

        let firstWeekStart = earliestExpenseWeekStart ?? currentWeekStart
        var weekStart = firstWeekStart
        var pages: [OverviewWeekSpendingSnapshot] = []

        while weekStart <= currentWeekStart {
            let weekInterval = weekInterval(startingAt: weekStart, calendar: calendar)
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let dailyValues: [(date: Date, valueMinor: Int64)] = (0..<7).compactMap { dayOffset in
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                    return nil
                }

                let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let total = transactionRecords
                    .filter { record in
                        record.entryStatus == .posted
                            && record.primaryKind == .expense
                            && record.occurredAt >= day
                            && record.occurredAt < nextDay
                    }
                    .reduce(into: Int64.zero) { partialResult, record in
                        partialResult += record.amountMinor
                    }

                return (day, total)
            }

            let minimum = dailyValues.map(\.valueMinor).min() ?? 0
            let maximum = dailyValues.map(\.valueMinor).max() ?? 0
            let isCurrentWeek = weekStart == currentWeekStart

            pages.append(
                OverviewWeekSpendingSnapshot(
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    title: weekRangeTitle(
                        for: weekInterval,
                        isCurrentWeek: isCurrentWeek,
                        calendar: calendar
                    ),
                    isCurrentWeek: isCurrentWeek,
                    points: dailyValues.map { item in
                        OverviewChartPoint(
                            date: item.date,
                            label: weekdayLabel(for: item.date, calendar: calendar),
                            valueMinor: item.valueMinor,
                            intensity: normalizedIntensity(
                                value: item.valueMinor,
                                minimum: minimum,
                                maximum: maximum
                            )
                        )
                    }
                )
            )

            guard let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }
            weekStart = nextWeekStart
        }

        if pages.isEmpty {
            return [
                OverviewWeekSpendingSnapshot(
                    weekStart: currentWeekStart,
                    weekEnd: currentWeekEnd,
                    title: weekRangeTitle(
                        for: weekInterval(startingAt: currentWeekStart, calendar: calendar),
                        isCurrentWeek: true,
                        calendar: calendar
                    ),
                    isCurrentWeek: true,
                    points: (0..<7).compactMap { dayOffset in
                        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: currentWeekStart) else {
                            return nil
                        }

                        return OverviewChartPoint(
                            date: day,
                            label: weekdayLabel(for: day, calendar: calendar),
                            valueMinor: 0,
                            intensity: 0
                        )
                    }
                )
            ]
        }

        return pages
    }

    static func recentSevenDaySpendingChartPoints(
        from transactionRecords: [TransactionRecordSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [OverviewChartPoint] {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: startOfToday)
        }

        let values: [(date: Date, valueMinor: Int64)] = days.map { day in
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let total = transactionRecords
                .filter { record in
                    record.entryStatus == .posted
                        && record.primaryKind == .expense
                        && record.occurredAt >= day
                        && record.occurredAt < nextDay
                }
                .reduce(into: Int64.zero) { partialResult, record in
                    partialResult += record.amountMinor
                }
            return (day, total)
        }

        let minimum = values.map(\.valueMinor).min() ?? 0
        let maximum = values.map(\.valueMinor).max() ?? 0

        return values.map { item in
            OverviewChartPoint(
                date: item.date,
                label: weekdayLabel(for: item.date, calendar: calendar),
                valueMinor: item.valueMinor,
                intensity: normalizedIntensity(
                    value: item.valueMinor,
                    minimum: minimum,
                    maximum: maximum
                )
            )
        }
    }

    static func budgetAlerts(
        budgets: [BudgetPlanSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [OverviewBudgetAlertSnapshot] {
        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let rows = PlanningLogic.budgetBranchRows(
            plans: budgets.filter { !$0.categoryName.isEmpty && $0.monthAnchor == selectedMonth },
            records: transactionRecords,
            selectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        return rows
            .filter { $0.progress > 0.5 }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress {
                    return lhs.progress > rhs.progress
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(3)
            .map { row in
                OverviewBudgetAlertSnapshot(
                    id: row.id,
                    name: row.name,
                    iconSymbolName: row.iconSymbolName,
                    spentMinor: row.spentMinor,
                    limitMinor: row.limitMinor,
                    currencyCode: row.currencyCode,
                    progress: row.progress,
                    daysRemaining: row.daysRemaining,
                    tint: budgetTint(
                        progress: row.progress,
                        daysRemaining: row.daysRemaining
                    )
                )
            }
    }

    static func dueAlerts(
        creditCardDues: [PlanningCreditCardDueSnapshot],
        recurringDues: [PlanningRecurringDueSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [OverviewDueAlertSnapshot] {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        let items = creditCardDues
            .filter { $0.status == .pending }
            .map {
                DueCandidate(
                    id: "credit-\($0.walletID.uuidString)",
                    name: $0.walletName,
                    iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
                    amountMinor: $0.amountMinor,
                    dueDate: $0.dueDate,
                    currencyCode: $0.currencyCode
                )
            }
            + recurringDues
            .filter { $0.status == .pending }
            .map {
                DueCandidate(
                    id: "\($0.sourceKind.rawValue)-\($0.sourceID.uuidString)",
                    name: $0.name,
                    iconSymbolName: $0.iconSymbolName,
                    amountMinor: $0.amountMinor,
                    dueDate: $0.dueDate,
                    currencyCode: $0.currencyCode
                )
            }

        return items
            .compactMap { item in
                let dayDelta = calendar.dateComponents(
                    [.day],
                    from: startOfToday,
                    to: calendar.startOfDay(for: item.dueDate)
                ).day ?? 0

                guard (0...7).contains(dayDelta) else {
                    return nil
                }

                return OverviewDueAlertSnapshot(
                    id: item.id,
                    name: item.name,
                    iconSymbolName: item.iconSymbolName,
                    amountMinor: item.amountMinor,
                    dueDate: item.dueDate,
                    dayDelta: dayDelta,
                    currencyCode: item.currencyCode,
                    tint: dayDelta <= 3 ? .red : .blue
                )
            }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate {
                    return lhs.dueDate < rhs.dueDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(3)
            .map { $0 }
    }

    static func recentTransactions(
        transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [OverviewRecentTransactionSnapshot] {
        transactions
            .filter { $0.entryStatus == .posted && !$0.isArchived }
            .sorted(by: transactionSort)
            .prefix(5)
            .map { transaction in
                OverviewRecentTransactionSnapshot(
                    id: transaction.id,
                    title: transaction.title,
                    amountMinor: transaction.amountMinor,
                    currencyCode: currencyCode,
                    occurredAt: transaction.occurredAt,
                    timeLabel: relativeTimeLabel(
                        for: transaction.occurredAt,
                        referenceDate: referenceDate,
                        calendar: calendar
                    ),
                    cashflowStyle: cashflowStyle(for: transaction),
                    categoryIconSymbolName: transaction.categoryID != nil 
                        ? categoryIconToken(for: transaction)
                        : transactionKindIconToken(for: transaction)
                )
            }
    }

    static func relativeTimeLabel(
        for date: Date,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        MistiaDateFormatting.relativeTimeLabel(
            for: date,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func creditCardStatementCycle(
        statementClosingDay: Int,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let currentClosing = closingDate(
            near: startOfToday,
            statementClosingDay: statementClosingDay,
            calendar: calendar
        )

        if startOfToday <= currentClosing {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: startOfToday) ?? startOfToday
            let previousClosing = closingDate(
                near: previousMonth,
                statementClosingDay: statementClosingDay,
                calendar: calendar
            )
            let cycleStart = calendar.date(byAdding: .day, value: 1, to: previousClosing) ?? previousClosing
            let cycleEnd = calendar.date(byAdding: .day, value: 1, to: currentClosing) ?? currentClosing
            return DateInterval(start: cycleStart, end: cycleEnd)
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday) ?? startOfToday
        let nextClosing = closingDate(
            near: nextMonth,
            statementClosingDay: statementClosingDay,
            calendar: calendar
        )
        let cycleStart = calendar.date(byAdding: .day, value: 1, to: currentClosing) ?? currentClosing
        let cycleEnd = calendar.date(byAdding: .day, value: 1, to: nextClosing) ?? nextClosing
        return DateInterval(start: cycleStart, end: cycleEnd)
    }

    private static func budgetTint(progress: Double, daysRemaining: Int) -> OverviewTint {
        if progress > 0.9 || daysRemaining <= 5 {
            return .red
        }

        if progress > 0.75 || daysRemaining <= 10 {
            return .orange
        }

        return .green
    }

    static func cashflowStyle(
        for transaction: OverviewTransactionSnapshot
    ) -> OverviewCashflowStyle {
        switch transaction.primaryKind {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            switch transaction.transferSubtype {
            case .debt:
                switch transaction.debtIntent {
                case .borrow, .collect:
                    return .income
                case .lend, .repay:
                    return .expense
                case .none:
                    return .neutral
                }
            case .internalTransfer, .none:
                return .neutral
            }
        }
    }

    private static func categoryIconToken(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        // Return category icon if available, otherwise use transaction kind icon
        transaction.categoryIconSymbolName ?? transactionKindIconToken(for: transaction)
    }

    private static func transactionKindIconToken(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense:
            TransactionPrimaryKind.expense.financeIconToken
        case .income:
            TransactionPrimaryKind.income.financeIconToken
        case .transfer:
            TransactionPrimaryKind.transfer.financeIconToken
        }
    }

    static func transactionKindTitle(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense:
            return mistiaLocalized(vi: "Chi tiêu", en: "Expense", ja: "支出")
        case .income:
            return mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
        case .transfer:
            switch transaction.transferSubtype {
            case .internalTransfer:
                return mistiaLocalized(vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替")
            case .debt:
                return transaction.debtIntent?.title ?? mistiaLocalized(vi: "Công nợ", en: "Debt", ja: "貸し借り")
            case .none:
                return mistiaLocalized(vi: "Chuyển tiền", en: "Transfer", ja: "振替")
            }
        }
    }


    private static func closingDate(
        near date: Date,
        statementClosingDay: Int,
        calendar: Calendar
    ) -> Date {
        scheduledDay(statementClosingDay, inMonthContaining: date, calendar: calendar)
    }

    static func scheduledDay(
        _ day: Int,
        inMonthContaining date: Date,
        calendar: Calendar
    ) -> Date {
        let monthStart = PlanningLogic.startOfMonth(for: date, calendar: calendar)
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let clampedDay = min(max(day, 1), maxDay)
        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
    }

    private static func normalizedIntensity(
        value: Int64,
        minimum: Int64,
        maximum: Int64
    ) -> Double {
        guard maximum > minimum else {
            return maximum == 0 ? 0 : 0.5
        }

        return Double(value - minimum) / Double(maximum - minimum)
    }

    static func startOfMondayWeek(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    static func weekInterval(
        startingAt weekStart: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let normalizedWeekStart = calendar.startOfDay(for: weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
        return DateInterval(start: normalizedWeekStart, end: weekEnd)
    }

    static func weekRangeTitle(
        for interval: DateInterval,
        isCurrentWeek: Bool,
        calendar: Calendar = .current
    ) -> String {
        let weekEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        return MistiaDateFormatting.weekRangeTitle(
            start: interval.start,
            end: weekEnd,
            isCurrentWeek: isCurrentWeek,
            calendar: calendar
        )
    }

    private static func weekdayLabel(
        for date: Date,
        calendar: Calendar
    ) -> String {
        MistiaDateFormatting.weekdayLabel(for: date, calendar: calendar)
    }



    static func barColor(for intensity: Double) -> String {
        let clamped = min(max(intensity, 0), 1)
        let start = (red: 45.0, green: 170.0, blue: 158.0)
        let end = (red: 244.0, green: 92.0, blue: 126.0)

        let red = Int((start.red + (end.red - start.red) * clamped).rounded())
        let green = Int((start.green + (end.green - start.green) * clamped).rounded())
        let blue = Int((start.blue + (end.blue - start.blue) * clamped).rounded())

        return String(format: "rgb(%d, %d, %d)", red, green, blue)
    }

    private static func shortDateString(for date: Date) -> String {
        MistiaDateFormatting.shortDateString(for: date)
    }


    private static func transactionSort(
        lhs: OverviewTransactionSnapshot,
        rhs: OverviewTransactionSnapshot
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }
        return lhs.createdAt > rhs.createdAt
    }

}

private nonisolated struct DueCandidate: Equatable {
    let id: String
    let name: String
    let iconSymbolName: String
    let amountMinor: Int64?
    let dueDate: Date
    let currencyCode: String
}

extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
