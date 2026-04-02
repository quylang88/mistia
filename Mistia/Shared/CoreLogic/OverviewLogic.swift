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

nonisolated enum OverviewStatementKind: String, Equatable {
    case monthlySummary
    case creditCard
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
    let counterpartyName: String?
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
}

nonisolated struct OverviewDashboardSnapshot: Equatable {
    let hero: OverviewHeroSnapshot
    let budgetAlerts: [OverviewBudgetAlertSnapshot]
    let dueAlerts: [OverviewDueAlertSnapshot]
    let recentTransactions: [OverviewRecentTransactionSnapshot]
}

nonisolated struct OverviewStatementWalletRow: Equatable, Identifiable {
    let id: UUID
    let name: String
    let kindTitle: String
    let openingBalanceMinor: Int64
    let currentBalanceMinor: Int64
    let currencyCode: String
}

nonisolated struct OverviewStatementTransactionRow: Equatable, Identifiable {
    let id: UUID
    let occurredAt: Date
    let title: String
    let kindTitle: String
    let accountText: String
    let detailText: String
    let amountMinor: Int64
    let currencyCode: String
    let cashflowStyle: OverviewCashflowStyle
    let statusTitle: String
}

nonisolated struct OverviewMonthlyStatementSnapshot: Equatable {
    let generatedAt: Date
    let period: DateInterval
    let totalAssetBalanceMinor: Int64
    let totalIncomeMinor: Int64
    let totalExpenseMinor: Int64
    let netCashflowMinor: Int64
    let wallets: [OverviewStatementWalletRow]
    let chartPoints: [OverviewChartPoint]
    let transactions: [OverviewStatementTransactionRow]
    let currencyCode: String
}

nonisolated struct OverviewCreditCardStatementCardSnapshot: Equatable, Identifiable {
    let id: UUID
    let walletName: String
    let iconSymbolName: String
    let issuerName: String
    let networkTitle: String
    let last4: String
    let creditLimitMinor: Int64
    let currentDebtMinor: Int64
    let availableCreditMinor: Int64
    let utilization: Double
    let statementClosingDay: Int
    let paymentDueDay: Int
    let paymentSourceWalletName: String?
    let cycle: DateInterval
    let nextPaymentDate: Date
    let charges: [OverviewStatementTransactionRow]
    let payments: [OverviewStatementTransactionRow]
    let currencyCode: String
}

nonisolated struct OverviewCreditCardStatementSnapshot: Equatable {
    let generatedAt: Date
    let cards: [OverviewCreditCardStatementCardSnapshot]
}

nonisolated struct OverviewStatementDocument: Equatable {
    let kind: OverviewStatementKind
    let filename: String
    let html: String
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
        let rows = PlanningLogic.budgetRows(
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
                    iconSymbolName: "creditcard.fill",
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
            .filter { $0.entryStatus == .posted }
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
                    cashflowStyle: cashflowStyle(for: transaction)
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

    static func monthlyStatement(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> OverviewMonthlyStatementSnapshot {
        let monthStart = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let monthEnd = calendar.dateInterval(of: .month, for: referenceDate)?.end ?? referenceDate
        let statementPeriod = DateInterval(start: monthStart, end: min(referenceDate, monthEnd))
        let chartPoints = recentSevenDaySpendingChartPoints(
            from: transactionRecords,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let heroSnapshot = hero(
            wallets: wallets,
            transactionRecords: transactionRecords,
            currencyCode: currencyCode,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let walletRows = wallets
            .filter { $0.kind != .creditCard }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
            .map { wallet in
                OverviewStatementWalletRow(
                    id: wallet.id,
                    name: wallet.name,
                    kindTitle: wallet.kind.title,
                    openingBalanceMinor: wallet.openingBalanceMinor,
                    currentBalanceMinor: TransactionLogic.effectiveBalance(
                        for: TransactionWalletSnapshot(
                            id: wallet.id,
                            kind: wallet.kind,
                            openingBalanceMinor: wallet.openingBalanceMinor
                        ),
                        records: transactionRecords
                    ),
                    currencyCode: wallet.currencyCode
                )
            }

        let transactionRows = transactions
            .filter { $0.entryStatus == .posted && contains($0.occurredAt, in: statementPeriod) }
            .sorted(by: transactionSort)
            .map { makeStatementRow(from: $0, currencyCode: currencyCode) }

        return OverviewMonthlyStatementSnapshot(
            generatedAt: referenceDate,
            period: statementPeriod,
            totalAssetBalanceMinor: heroSnapshot.totalAssetBalanceMinor,
            totalIncomeMinor: heroSnapshot.incomeThisMonthMinor,
            totalExpenseMinor: heroSnapshot.expenseThisMonthMinor,
            netCashflowMinor: heroSnapshot.incomeThisMonthMinor - heroSnapshot.expenseThisMonthMinor,
            wallets: walletRows,
            chartPoints: chartPoints,
            transactions: transactionRows,
            currencyCode: currencyCode
        )
    }

    static func creditCardStatement(
        accounts: [OverviewCreditCardStatementAccountSnapshot],
        transactions: [OverviewTransactionSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> OverviewCreditCardStatementSnapshot {
        let cards = accounts
            .sorted {
                $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending
            }
            .map { account in
                let cycle = creditCardStatementCycle(
                    statementClosingDay: account.statementClosingDay,
                    referenceDate: referenceDate,
                    calendar: calendar
                )

                let charges = transactions
                    .filter {
                        $0.entryStatus == .posted
                            && $0.primaryKind == .expense
                            && $0.sourceWalletID == account.walletID
                            && contains($0.occurredAt, in: cycle)
                    }
                    .sorted(by: transactionSort)
                    .map { makeStatementRow(from: $0, currencyCode: account.currencyCode) }

                let payments = transactions
                    .filter {
                        $0.entryStatus == .posted
                            && $0.primaryKind == .transfer
                            && $0.transferSubtype == .internalTransfer
                            && $0.destinationWalletID == account.walletID
                            && contains($0.occurredAt, in: cycle)
                    }
                    .sorted(by: transactionSort)
                    .map { makeStatementRow(from: $0, currencyCode: account.currencyCode) }

                let availableCredit = max(account.creditLimitMinor - account.currentDebtMinor, 0)
                let utilization = account.creditLimitMinor > 0
                    ? Double(account.currentDebtMinor) / Double(account.creditLimitMinor)
                    : 0

                return OverviewCreditCardStatementCardSnapshot(
                    id: account.id,
                    walletName: account.walletName,
                    iconSymbolName: account.iconSymbolName,
                    issuerName: account.issuerName,
                    networkTitle: account.network.title,
                    last4: account.last4,
                    creditLimitMinor: account.creditLimitMinor,
                    currentDebtMinor: account.currentDebtMinor,
                    availableCreditMinor: availableCredit,
                    utilization: utilization,
                    statementClosingDay: account.statementClosingDay,
                    paymentDueDay: account.paymentDueDay,
                    paymentSourceWalletName: account.paymentSourceWalletName,
                    cycle: cycle,
                    nextPaymentDate: nextPaymentDate(
                        paymentDueDay: account.paymentDueDay,
                        cycleEnd: cycle.end,
                        calendar: calendar
                    ),
                    charges: charges,
                    payments: payments,
                    currencyCode: account.currencyCode
                )
            }

        return OverviewCreditCardStatementSnapshot(
            generatedAt: referenceDate,
            cards: cards
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

    static func renderMonthlyStatement(
        _ statement: OverviewMonthlyStatementSnapshot
    ) -> OverviewStatementDocument {
        let language = MistiaAppLanguage.current
        let filename = "mistia-sao-ke-tong-hop-\(yearMonthToken(for: statement.period.start)).html"
        let body = """
        <div class="hero">
          <div>
            <div class="eyebrow">Mistia Statement</div>
            <h1>\(htmlEscaped(mistiaLocalized(vi: "Sao kê tổng hợp tháng", en: "Monthly summary statement", ja: "月次サマリーステートメント", language: language)))</h1>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Kỳ sao kê", en: "Statement period", ja: "対象期間", language: language))): \(htmlEscaped(fullDateString(for: statement.period.start))) - \(htmlEscaped(fullDateString(for: statement.period.end)))</p>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Xuất lúc", en: "Generated at", ja: "出力日時", language: language))) \(htmlEscaped(dateTimeString(for: statement.generatedAt)))</p>
          </div>
          <div class="hero-amount">\(htmlEscaped(statement.totalAssetBalanceMinor.formattedCurrency(code: statement.currencyCode)))</div>
        </div>

        <div class="grid three">
          \(summaryCard(title: mistiaLocalized(vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産", language: language), value: statement.totalAssetBalanceMinor.formattedCurrency(code: statement.currencyCode), accentClass: "green"))
          \(summaryCard(title: mistiaLocalized(vi: "Thu tháng này", en: "Income this month", ja: "今月の収入", language: language), value: statement.totalIncomeMinor.formattedCurrency(code: statement.currencyCode), accentClass: "blue"))
          \(summaryCard(title: mistiaLocalized(vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出", language: language), value: statement.totalExpenseMinor.formattedCurrency(code: statement.currencyCode), accentClass: "red"))
        </div>

        <div class="grid two">
          <section class="panel">
            <div class="panel-header">
              <h2>\(htmlEscaped(mistiaLocalized(vi: "Chênh lệch dòng tiền", en: "Net cashflow", ja: "キャッシュフロー差額", language: language)))</h2>
              <span>\(htmlEscaped(statement.netCashflowMinor.formattedCurrency(code: statement.currencyCode)))</span>
            </div>
            \(renderChart(points: statement.chartPoints, currencyCode: statement.currencyCode))
          </section>
          <section class="panel">
            <div class="panel-header">
              <h2>\(htmlEscaped(mistiaLocalized(vi: "Ví tài sản", en: "Asset wallets", ja: "資産ウォレット", language: language)))</h2>
              <span>\(statement.wallets.count) \(htmlEscaped(mistiaLocalized(vi: "ví", en: "wallets", ja: "件", language: language)))</span>
            </div>
            \(renderWalletTable(rows: statement.wallets))
          </section>
        </div>

        <section class="panel">
          <div class="panel-header">
            <h2>\(htmlEscaped(mistiaLocalized(vi: "Giao dịch tháng hiện tại", en: "Transactions this month", ja: "今月の取引", language: language)))</h2>
            <span>\(statement.transactions.count) \(htmlEscaped(mistiaLocalized(vi: "mục", en: "items", ja: "件", language: language)))</span>
          </div>
          \(renderTransactionTable(rows: statement.transactions, emptyMessage: mistiaLocalized(vi: "Chưa có giao dịch nào trong tháng này.", en: "No transactions in this month yet.", ja: "今月の取引はまだありません。", language: language)))
        </section>
        """

        return OverviewStatementDocument(
            kind: .monthlySummary,
            filename: filename,
            html: renderDocument(
                title: mistiaLocalized(vi: "Mistia Sao kê tổng hợp", en: "Mistia Monthly Summary", ja: "Mistia 月次サマリー", language: language),
                subtitle: mistiaLocalized(vi: "Tổng hợp tài sản, dòng tiền và giao dịch tháng hiện tại", en: "A summary of assets, cashflow, and transactions for the current month", ja: "今月の資産、キャッシュフロー、取引のサマリー", language: language),
                body: body
            )
        )
    }

    static func renderCreditCardStatement(
        _ statement: OverviewCreditCardStatementSnapshot
    ) -> OverviewStatementDocument {
        let language = MistiaAppLanguage.current
        let filename = "mistia-sao-ke-the-tin-dung-\(yearMonthToken(for: statement.generatedAt)).html"
        let sections: String

        if statement.cards.isEmpty {
            sections = """
            <section class="panel empty">
              <h2>\(htmlEscaped(mistiaLocalized(vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません", language: language)))</h2>
              <p>\(htmlEscaped(mistiaLocalized(vi: "Hiện tại bạn chưa thêm thẻ nào vào Mistia nên không có sao kê để xuất.", en: "You have not added any cards to Mistia yet, so there is no statement to export.", ja: "Mistia にカードがまだ追加されていないため、書き出せる明細がありません。", language: language)))</p>
            </section>
            """
        } else {
            sections = statement.cards.map { card in
                """
                <section class="panel card-panel">
                  <div class="panel-header">
                    <div>
                      <div class="eyebrow">\(htmlEscaped(card.networkTitle)) • •••• \(htmlEscaped(card.last4))</div>
                      <h2>\(htmlEscaped(card.walletName))</h2>
                      <p>\(htmlEscaped(card.issuerName.isEmpty ? mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード", language: language) : card.issuerName))</p>
                    </div>
                    <div class="badge">\(htmlEscaped(mistiaLocalized(vi: "Tỷ lệ sử dụng", en: "Utilization", ja: "利用率", language: language))) \(htmlEscaped(percentText(card.utilization)))</div>
                  </div>

                  <div class="grid four">
                    \(summaryCard(title: mistiaLocalized(vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高", language: language), value: card.currentDebtMinor.formattedCurrency(code: card.currencyCode), accentClass: "red"))
                    \(summaryCard(title: mistiaLocalized(vi: "Hạn mức", en: "Credit limit", ja: "利用限度額", language: language), value: card.creditLimitMinor.formattedCurrency(code: card.currencyCode), accentClass: "blue"))
                    \(summaryCard(title: mistiaLocalized(vi: "Hạn mức còn lại", en: "Available credit", ja: "利用可能額", language: language), value: card.availableCreditMinor.formattedCurrency(code: card.currencyCode), accentClass: "green"))
                    \(summaryCard(title: mistiaLocalized(vi: "Ngày thanh toán tiếp theo", en: "Next payment date", ja: "次回支払日", language: language), value: fullDateString(for: card.nextPaymentDate), accentClass: "orange"))
                  </div>

                  <div class="meta-grid">
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Kỳ sao kê hiện tại", en: "Current cycle", ja: "現在の締め期間", language: language)))</span>
                      <strong>\(htmlEscaped(fullDateString(for: card.cycle.start))) - \(htmlEscaped(fullDateString(for: card.cycle.end.addingTimeInterval(-1))))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日", language: language)))</span>
                      <strong>\(htmlEscaped(mistiaLocalized(vi: "\(card.statementClosingDay) hằng tháng", en: "Day \(card.statementClosingDay) each month", ja: "毎月 \(card.statementClosingDay) 日", language: language)))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Ngày thanh toán", en: "Payment due day", ja: "支払日", language: language)))</span>
                      <strong>\(htmlEscaped(mistiaLocalized(vi: "\(card.paymentDueDay) hằng tháng", en: "Day \(card.paymentDueDay) each month", ja: "毎月 \(card.paymentDueDay) 日", language: language)))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払い元ウォレット", language: language)))</span>
                      <strong>\(htmlEscaped(card.paymentSourceWalletName ?? mistiaLocalized(vi: "Chưa cài đặt", en: "Not set", ja: "未設定", language: language)))</strong>
                    </div>
                  </div>

                  <div class="grid two">
                    <section class="subpanel">
                      <div class="panel-header">
                        <h3>\(htmlEscaped(mistiaLocalized(vi: "Chi tiêu trong kỳ", en: "Charges in cycle", ja: "期間内の利用", language: language)))</h3>
                        <span>\(card.charges.count) \(htmlEscaped(mistiaLocalized(vi: "mục", en: "items", ja: "件", language: language)))</span>
                      </div>
                      \(renderTransactionTable(rows: card.charges, emptyMessage: mistiaLocalized(vi: "Không có chi tiêu nào trong kỳ sao kê này.", en: "There are no charges in this cycle.", ja: "この締め期間の利用はありません。", language: language)))
                    </section>
                    <section class="subpanel">
                      <div class="panel-header">
                        <h3>\(htmlEscaped(mistiaLocalized(vi: "Thanh toán vào thẻ", en: "Payments to card", ja: "カードへの支払い", language: language)))</h3>
                        <span>\(card.payments.count) \(htmlEscaped(mistiaLocalized(vi: "mục", en: "items", ja: "件", language: language)))</span>
                      </div>
                      \(renderTransactionTable(rows: card.payments, emptyMessage: mistiaLocalized(vi: "Chưa có giao dịch thanh toán vào thẻ trong kỳ.", en: "There are no card payments in this cycle.", ja: "この期間のカード支払いはありません。", language: language)))
                    </section>
                  </div>
                </section>
                """
            }
            .joined(separator: "\n")
        }

        let body = """
        <div class="hero">
          <div>
            <div class="eyebrow">Mistia Statement</div>
            <h1>\(htmlEscaped(mistiaLocalized(vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細", language: language)))</h1>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Bản tổng hợp cho các thẻ đang hoạt động trong Mistia.", en: "A summary of active cards in Mistia.", ja: "Mistia で利用中のカードをまとめた明細です。", language: language)))</p>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Xuất lúc", en: "Generated at", ja: "出力日時", language: language))) \(htmlEscaped(dateTimeString(for: statement.generatedAt)))</p>
          </div>
          <div class="hero-amount">\(statement.cards.count) \(htmlEscaped(mistiaLocalized(vi: "thẻ", en: "cards", ja: "枚", language: language)))</div>
        </div>
        \(sections)
        """

        return OverviewStatementDocument(
            kind: .creditCard,
            filename: filename,
            html: renderDocument(
                title: mistiaLocalized(vi: "Mistia Sao kê thẻ tín dụng", en: "Mistia Credit Card Statement", ja: "Mistia クレジットカード明細", language: language),
                subtitle: mistiaLocalized(vi: "Tổng hợp dư nợ, hạn mức và giao dịch trong kỳ sao kê hiện tại", en: "A summary of debt, credit limits, and transactions in the current cycle", ja: "現在の締め期間における残高、利用枠、取引のサマリー", language: language),
                body: body
            )
        )
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

    private static func cashflowStyle(
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

    private static func makeStatementRow(
        from transaction: OverviewTransactionSnapshot,
        currencyCode: String
    ) -> OverviewStatementTransactionRow {
        OverviewStatementTransactionRow(
            id: transaction.id,
            occurredAt: transaction.occurredAt,
            title: transaction.title,
            kindTitle: transactionKindTitle(for: transaction),
            accountText: statementAccountText(for: transaction),
            detailText: statementDetailText(for: transaction),
            amountMinor: transaction.amountMinor,
            currencyCode: currencyCode,
            cashflowStyle: cashflowStyle(for: transaction),
            statusTitle: transaction.entryStatus.title
        )
    }

    private static func transactionKindTitle(
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

    private static func statementAccountText(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense, .income:
            return transaction.sourceWalletName ?? mistiaLocalized(vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択")
        case .transfer:
            let source = transaction.sourceWalletName ?? mistiaLocalized(vi: "Nguồn", en: "Source", ja: "出金元")
            let destination = transaction.destinationWalletName ?? mistiaLocalized(vi: "Đích", en: "Destination", ja: "入金先")
            return "\(source) -> \(destination)"
        }
    }

    private static func statementDetailText(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense, .income:
            if let category = transaction.categoryName, !category.isEmpty {
                return category
            }
            return transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "-"
        case .transfer:
            if transaction.transferSubtype == .debt {
                return transaction.counterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? mistiaLocalized(vi: "Công nợ", en: "Debt", ja: "貸し借り")
            }
            return transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "-"
        }
    }

    private static func nextPaymentDate(
        paymentDueDay: Int,
        cycleEnd: Date,
        calendar: Calendar
    ) -> Date {
        let reference = calendar.date(byAdding: .day, value: 1, to: cycleEnd) ?? cycleEnd
        let referenceMonthStart = PlanningLogic.startOfMonth(for: reference, calendar: calendar)
        let currentMonthDue = scheduledDay(
            paymentDueDay,
            inMonthContaining: referenceMonthStart,
            calendar: calendar
        )

        if currentMonthDue >= calendar.startOfDay(for: reference) {
            return currentMonthDue
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: referenceMonthStart) ?? referenceMonthStart
        return scheduledDay(paymentDueDay, inMonthContaining: nextMonth, calendar: calendar)
    }

    private static func closingDate(
        near date: Date,
        statementClosingDay: Int,
        calendar: Calendar
    ) -> Date {
        scheduledDay(statementClosingDay, inMonthContaining: date, calendar: calendar)
    }

    private static func scheduledDay(
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

    private static func yearMonthToken(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
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

    private static func contains(
        _ date: Date,
        in interval: DateInterval
    ) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static func renderDocument(
        title: String,
        subtitle: String,
        body: String
    ) -> String {
        let language = MistiaAppLanguage.current
        return """
        <!doctype html>
        <html lang="\(language.rawValue)">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(htmlEscaped(title))</title>
          <style>
            :root {
              color-scheme: light;
              --bg: #eef2ff;
              --bg-soft: #f8faff;
              --panel: rgba(255,255,255,0.78);
              --panel-strong: rgba(255,255,255,0.92);
              --text: #14213d;
              --muted: #5b6480;
              --line: rgba(91,123,255,0.14);
              --shadow: 0 24px 60px rgba(28, 34, 65, 0.12);
              --green: #2daa9e;
              --orange: #f59b3f;
              --red: #f45c7e;
              --blue: #5b7bff;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif;
              background:
                radial-gradient(circle at top left, rgba(91,123,255,0.22), transparent 30%),
                radial-gradient(circle at top right, rgba(45,170,158,0.18), transparent 28%),
                linear-gradient(180deg, #f8faff 0%, #edf2ff 100%);
              color: var(--text);
            }
            .page {
              width: min(1120px, calc(100vw - 40px));
              margin: 32px auto;
              padding: 28px;
              border: 1px solid rgba(255,255,255,0.72);
              border-radius: 28px;
              background: rgba(255,255,255,0.62);
              backdrop-filter: blur(20px);
              box-shadow: var(--shadow);
            }
            .page-title { margin: 0 0 6px; font-size: 30px; }
            .page-subtitle { margin: 0 0 28px; color: var(--muted); font-size: 15px; }
            .hero, .panel, .subpanel {
              background: linear-gradient(180deg, var(--panel-strong), var(--panel));
              border: 1px solid var(--line);
              border-radius: 24px;
              box-shadow: 0 16px 36px rgba(20, 33, 61, 0.08);
            }
            .hero {
              display: flex;
              justify-content: space-between;
              align-items: flex-end;
              gap: 20px;
              padding: 24px;
              margin-bottom: 20px;
            }
            .hero h1, .panel h2, .subpanel h3 { margin: 0; }
            .hero p { margin: 4px 0 0; color: var(--muted); }
            .hero-amount {
              font-size: clamp(28px, 4vw, 46px);
              font-weight: 700;
              text-align: right;
            }
            .eyebrow {
              text-transform: uppercase;
              letter-spacing: 0.16em;
              font-size: 12px;
              color: var(--blue);
              font-weight: 700;
              margin-bottom: 8px;
            }
            .grid {
              display: grid;
              gap: 16px;
              margin-bottom: 20px;
            }
            .grid.two { grid-template-columns: repeat(2, minmax(0, 1fr)); }
            .grid.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
            .grid.four { grid-template-columns: repeat(4, minmax(0, 1fr)); }
            .summary-card {
              padding: 18px 18px 16px;
              border-radius: 20px;
              background: rgba(255,255,255,0.64);
              border: 1px solid rgba(91,123,255,0.12);
            }
            .summary-card span {
              display: block;
              margin-bottom: 10px;
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              color: var(--muted);
            }
            .summary-card strong {
              font-size: 22px;
              line-height: 1.25;
            }
            .summary-card.green strong { color: var(--green); }
            .summary-card.orange strong { color: var(--orange); }
            .summary-card.red strong { color: var(--red); }
            .summary-card.blue strong { color: var(--blue); }
            .panel, .subpanel {
              padding: 20px;
            }
            .subpanel { padding: 18px; }
            .panel-header {
              display: flex;
              align-items: flex-start;
              justify-content: space-between;
              gap: 16px;
              margin-bottom: 18px;
            }
            .panel-header span, .panel-header p {
              color: var(--muted);
              margin: 4px 0 0;
            }
            .chart {
              display: grid;
              grid-template-columns: repeat(7, minmax(0, 1fr));
              gap: 12px;
              align-items: end;
              min-height: 220px;
            }
            .chart-bar {
              display: flex;
              flex-direction: column;
              justify-content: flex-end;
              gap: 10px;
              min-height: 200px;
            }
            .chart-fill {
              border-radius: 16px 16px 10px 10px;
              min-height: 12px;
              box-shadow: inset 0 1px 1px rgba(255,255,255,0.2);
            }
            .chart-meta strong {
              display: block;
              font-size: 13px;
            }
            .chart-meta span {
              color: var(--muted);
              font-size: 12px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
            }
            th, td {
              text-align: left;
              padding: 12px 10px;
              border-bottom: 1px solid rgba(91,123,255,0.12);
              vertical-align: top;
            }
            th {
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              color: var(--muted);
            }
            td strong {
              display: block;
              margin-bottom: 4px;
            }
            .amount-income { color: var(--green); font-weight: 700; }
            .amount-expense { color: var(--red); font-weight: 700; }
            .amount-neutral { color: var(--blue); font-weight: 700; }
            .badge {
              display: inline-flex;
              align-items: center;
              padding: 8px 12px;
              border-radius: 999px;
              background: rgba(91,123,255,0.10);
              color: var(--blue);
              font-weight: 700;
            }
            .meta-grid {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 12px;
              margin: 18px 0 20px;
            }
            .meta-item {
              padding: 14px 16px;
              border-radius: 18px;
              background: rgba(255,255,255,0.58);
              border: 1px solid rgba(91,123,255,0.10);
            }
            .meta-item span {
              display: block;
              margin-bottom: 6px;
              color: var(--muted);
              font-size: 12px;
            }
            .empty {
              text-align: center;
              padding: 34px 24px;
            }
            @media (max-width: 900px) {
              .grid.two, .grid.three, .grid.four, .meta-grid {
                grid-template-columns: 1fr;
              }
              .hero {
                flex-direction: column;
                align-items: flex-start;
              }
              .hero-amount {
                text-align: left;
              }
              .chart {
                gap: 10px;
              }
            }
          </style>
        </head>
        <body>
          <main class="page">
            <h1 class="page-title">\(htmlEscaped(title))</h1>
            <p class="page-subtitle">\(htmlEscaped(subtitle))</p>
            \(body)
          </main>
        </body>
        </html>
        """
    }

    private static func renderChart(
        points: [OverviewChartPoint],
        currencyCode: String
    ) -> String {
        let maxValue = max(points.map(\.valueMinor).max() ?? 0, 1)

        let bars = points.map { point in
            let height = max(Double(point.valueMinor) / Double(maxValue), point.valueMinor > 0 ? 0.12 : 0.04)
            return """
            <div class="chart-bar">
              <div class="chart-fill" style="height: \(Int((height * 160).rounded()))px; background: \(barColor(for: point.intensity));"></div>
              <div class="chart-meta">
                <strong>\(htmlEscaped(point.label))</strong>
                <span>\(htmlEscaped(point.valueMinor.formattedCurrency(code: currencyCode)))</span>
              </div>
            </div>
            """
        }.joined(separator: "\n")

        return "<div class=\"chart\">\(bars)</div>"
    }

    private static func renderWalletTable(
        rows: [OverviewStatementWalletRow]
    ) -> String {
        guard !rows.isEmpty else {
            return "<div class=\"empty\"><p>\(htmlEscaped(mistiaLocalized(vi: "Chưa có ví tài sản nào.", en: "There are no asset wallets yet.", ja: "資産ウォレットはまだありません。")))</p></div>"
        }

        let body = rows.map { row in
            """
            <tr>
              <td><strong>\(htmlEscaped(row.name))</strong>\(htmlEscaped(row.kindTitle))</td>
              <td>\(htmlEscaped(row.openingBalanceMinor.formattedCurrency(code: row.currencyCode)))</td>
              <td>\(htmlEscaped(row.currentBalanceMinor.formattedCurrency(code: row.currencyCode)))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <table>
          <thead>
            <tr>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Ví", en: "Wallet", ja: "ウォレット")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Số dư đầu kỳ", en: "Opening balance", ja: "期首残高")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Số dư hiện tại", en: "Current balance", ja: "現在残高")))</th>
            </tr>
          </thead>
          <tbody>
            \(body)
          </tbody>
        </table>
        """
    }

    private static func renderTransactionTable(
        rows: [OverviewStatementTransactionRow],
        emptyMessage: String
    ) -> String {
        guard !rows.isEmpty else {
            return "<div class=\"empty\"><p>\(htmlEscaped(emptyMessage))</p></div>"
        }

        let body = rows.map { row in
            """
            <tr>
              <td>\(htmlEscaped(dateTimeString(for: row.occurredAt)))</td>
              <td><strong>\(htmlEscaped(row.title))</strong>\(htmlEscaped(row.detailText))</td>
              <td>\(htmlEscaped(row.kindTitle))</td>
              <td>\(htmlEscaped(row.accountText))</td>
              <td class="amount-\(row.cashflowStyle.rawValue)">\(htmlEscaped(displayAmount(for: row)))</td>
              <td>\(htmlEscaped(row.statusTitle))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <table>
          <thead>
            <tr>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Ngày giờ", en: "Date & time", ja: "日時")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Giao dịch", en: "Transaction", ja: "取引")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Loại", en: "Type", ja: "種類")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Tài khoản", en: "Account", ja: "口座")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Trạng thái", en: "Status", ja: "状態")))</th>
            </tr>
          </thead>
          <tbody>
            \(body)
          </tbody>
        </table>
        """
    }

    private static func displayAmount(
        for row: OverviewStatementTransactionRow
    ) -> String {
        let raw = row.amountMinor.formattedCurrency(code: row.currencyCode)
        switch row.cashflowStyle {
        case .income:
            return "+" + raw
        case .expense:
            return "-" + raw
        case .neutral:
            return raw
        }
    }

    private static func summaryCard(
        title: String,
        value: String,
        accentClass: String
    ) -> String {
        """
        <div class="summary-card \(accentClass)">
          <span>\(htmlEscaped(title))</span>
          <strong>\(htmlEscaped(value))</strong>
        </div>
        """
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func barColor(for intensity: Double) -> String {
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

    private static func fullDateString(for date: Date) -> String {
        MistiaDateFormatting.fullDateString(for: date)
    }

    private static func dateTimeString(for date: Date) -> String {
        MistiaDateFormatting.dateTimeString(for: date)
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
