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
    let financialDomain: TransactionFinancialDomain
    let primaryKind: TransactionPrimaryKind
    let transferSubtype: TransactionTransferSubtype?
    let debtIntent: TransactionDebtIntent?
    let entryStatus: TransactionEntryStatus
    let title: String
    let note: String?
    let amountMinor: Int64
    let reportingExpenseMinor: Int64?
    let reportingIncomeMinor: Int64?
    let sourceCurrencyCode: String?
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
    let categoryColorHex: String?
    let categoryParentID: UUID?
    let categoryParentName: String?
    let categoryParentIconSymbolName: String?
    let categoryParentColorHex: String?
    let counterpartyName: String?
    let isArchived: Bool

    init(
        id: UUID,
        financialDomain: TransactionFinancialDomain = .ordinary,
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype?,
        debtIntent: TransactionDebtIntent?,
        entryStatus: TransactionEntryStatus,
        title: String,
        note: String?,
        amountMinor: Int64,
        reportingExpenseMinor: Int64? = nil,
        reportingIncomeMinor: Int64? = nil,
        sourceCurrencyCode: String? = nil,
        occurredAt: Date,
        createdAt: Date,
        sourceWalletID: UUID?,
        sourceWalletName: String?,
        sourceWalletKind: LedgerWalletKind?,
        destinationWalletID: UUID?,
        destinationWalletName: String?,
        destinationWalletKind: LedgerWalletKind?,
        categoryID: UUID?,
        categoryName: String?,
        categoryIconSymbolName: String?,
        categoryColorHex: String?,
        categoryParentID: UUID?,
        categoryParentName: String?,
        categoryParentIconSymbolName: String?,
        categoryParentColorHex: String?,
        counterpartyName: String?,
        isArchived: Bool
    ) {
        self.id = id
        self.financialDomain = financialDomain
        self.primaryKind = primaryKind
        self.transferSubtype = transferSubtype
        self.debtIntent = debtIntent
        self.entryStatus = entryStatus
        self.title = title
        self.note = note
        self.amountMinor = amountMinor
        self.reportingExpenseMinor = reportingExpenseMinor
        self.reportingIncomeMinor = reportingIncomeMinor
        self.sourceCurrencyCode = sourceCurrencyCode
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.sourceWalletID = sourceWalletID
        self.sourceWalletName = sourceWalletName
        self.sourceWalletKind = sourceWalletKind
        self.destinationWalletID = destinationWalletID
        self.destinationWalletName = destinationWalletName
        self.destinationWalletKind = destinationWalletKind
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryIconSymbolName = categoryIconSymbolName
        self.categoryColorHex = categoryColorHex
        self.categoryParentID = categoryParentID
        self.categoryParentName = categoryParentName
        self.categoryParentIconSymbolName = categoryParentIconSymbolName
        self.categoryParentColorHex = categoryParentColorHex
        self.counterpartyName = counterpartyName
        self.isArchived = isArchived
    }
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

nonisolated struct OverviewCategorySpendingSlice: Equatable, Identifiable {
    let id: String
    let categoryID: UUID?
    let name: String
    let iconSymbolName: String
    let colorHex: String
    let amountMinor: Int64
    let childSlices: [OverviewCategorySpendingSlice]

    var canDrillDown: Bool {
        categoryID != nil && !childSlices.isEmpty
    }

    var withoutChildren: OverviewCategorySpendingSlice {
        OverviewCategorySpendingSlice(
            id: id,
            categoryID: categoryID,
            name: name,
            iconSymbolName: iconSymbolName,
            colorHex: colorHex,
            amountMinor: amountMinor,
            childSlices: []
        )
    }
}

nonisolated struct OverviewCategorySpendingMonthSnapshot: Equatable, Identifiable {
    let monthStart: Date
    let title: String
    let currencyCode: String
    let slices: [OverviewCategorySpendingSlice]

    var id: String {
        String(Int(monthStart.timeIntervalSince1970))
    }

    var totalExpenseMinor: Int64 {
        slices.reduce(into: Int64.zero) { partialResult, slice in
            partialResult += slice.amountMinor
        }
    }

    var topSlices: [OverviewCategorySpendingSlice] {
        Array(slices.prefix(3))
    }

    func drilldownSlices(for categoryID: UUID) -> [OverviewCategorySpendingSlice] {
        slices.first { $0.categoryID == categoryID }?.childSlices ?? []
    }
}

nonisolated struct OverviewMonthlyCashflowSnapshot: Equatable, Identifiable {
    let monthStart: Date
    let incomeMinor: Int64
    let expenseMinor: Int64

    var id: String {
        String(Int(monthStart.timeIntervalSince1970))
    }
}

nonisolated struct OverviewHeroSnapshot: Equatable {
    let totalAssetBalanceMinor: Int64
    let incomeThisMonthMinor: Int64
    let expenseThisMonthMinor: Int64
    let weekPages: [OverviewWeekSpendingSnapshot]
    let categoryMonthPages: [OverviewCategorySpendingMonthSnapshot]
    let monthlyCashflowPages: [OverviewMonthlyCashflowSnapshot]
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
    let paceAssessment: PlanningBudgetPaceAssessment
    let tint: OverviewTint

    var health: PlanningBudgetHealth {
        paceAssessment.health
    }

    var daysRemaining: Int {
        paceAssessment.daysRemaining
    }

    var projectedSpentMinor: Int64 {
        paceAssessment.projectedSpentMinor
    }

    var remainingDailyAllowanceMinor: Int64 {
        paceAssessment.remainingDailyAllowanceMinor
    }

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
    // Typed routing — avoids string-prefix heuristics downstream
    let sourceKind: PlanningDueSourceKind
    let sourceID: UUID?        // walletID for .creditCard, planID for .recurringBill/.installment
    let dueMonthKey: String
    let requiresAmountInput: Bool
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
        balanceIndex: TransactionWalletBalanceIndex? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        additionalAssetValueMinor: Int64 = 0,
        familyTransactions: [FamilyAggregateTransactionSnapshot] = [],
        familySpendingAvailable: Bool = true,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> OverviewDashboardSnapshot {
        OverviewDashboardSnapshot(
            hero: hero(
                wallets: wallets,
                transactionRecords: transactionRecords,
                transactions: transactions,
                currencyCode: currencyCode,
                balanceIndex: balanceIndex,
                exchangeRates: exchangeRates,
                additionalAssetValueMinor: additionalAssetValueMinor,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            budgetAlerts: budgetAlerts(
                budgets: budgets,
                transactionRecords: transactionRecords,
                referenceDate: referenceDate,
                calendar: calendar,
                exchangeRates: exchangeRates,
                familyTransactions: familyTransactions,
                familySpendingAvailable: familySpendingAvailable
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
        transactions: [OverviewTransactionSnapshot] = [],
        currencyCode: String,
        balanceIndex: TransactionWalletBalanceIndex? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        additionalAssetValueMinor: Int64 = 0,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> OverviewHeroSnapshot {
        let monthlyCashflowPages = monthlyCashflowPages(
            from: transactionRecords,
            currencyCode: currencyCode,
            exchangeRates: exchangeRates,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let currentMonthStart = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let currentMonthCashflow = monthlyCashflowPages.first { $0.monthStart == currentMonthStart }

        return OverviewHeroSnapshot(
            totalAssetBalanceMinor: totalAssetBalance(
                wallets: wallets,
                transactionRecords: transactionRecords,
                balanceIndex: balanceIndex,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates,
                additionalAssetValueMinor: additionalAssetValueMinor
            ),
            incomeThisMonthMinor: currentMonthCashflow?.incomeMinor ?? 0,
            expenseThisMonthMinor: currentMonthCashflow?.expenseMinor ?? 0,
            weekPages: weeklySpendingPages(
                from: transactionRecords,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            categoryMonthPages: categorySpendingMonthPages(
                from: transactions,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            monthlyCashflowPages: monthlyCashflowPages,
            currentWeekStart: startOfMondayWeek(containing: referenceDate, calendar: calendar),
            currencyCode: currencyCode
        )
    }

    static func totalAssetBalance(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        balanceIndex: TransactionWalletBalanceIndex? = nil,
        currencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        additionalAssetValueMinor: Int64 = 0
    ) -> Int64 {
        let resolvedBalanceIndex = balanceIndex ?? TransactionLogic.walletBalanceIndex(
            wallets: wallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionRecords
        )

        let walletTotal = wallets
            .filter { $0.kind != .creditCard }
            .reduce(into: Int64.zero) { partialResult, wallet in
                let balance = resolvedBalanceIndex.balance(
                    for: TransactionWalletSnapshot(
                        id: wallet.id,
                        kind: wallet.kind,
                        openingBalanceMinor: wallet.openingBalanceMinor
                    )
                )
                guard let currencyCode else {
                    partialResult += balance
                    return
                }

                partialResult += reportingAmount(
                    amountMinor: balance,
                    sourceCurrencyCode: wallet.currencyCode,
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates
                )
            }
        let (total, overflow) = walletTotal.addingReportingOverflow(additionalAssetValueMinor)
        if overflow {
            return additionalAssetValueMinor >= 0 ? .max : .min
        }
        return total
    }

    static func weeklySpendingPages(
        from transactionRecords: [TransactionRecordSnapshot],
        currencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [OverviewWeekSpendingSnapshot] {
        let currentWeekStart = startOfMondayWeek(containing: referenceDate, calendar: calendar)
        let currentWeekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart
        var dailyTotalsByDay: [Date: Int64] = [:]
        var earliestExpenseWeekStart: Date?

        for record in transactionRecords where record.entryStatus == .posted && TransactionLogic.reportedExpenseAmount(for: record) != 0 {
            let day = calendar.startOfDay(for: record.occurredAt)
            dailyTotalsByDay[day, default: 0] += chartSpendingAmount(
                for: record,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates
            )

            let weekStart = startOfMondayWeek(containing: record.occurredAt, calendar: calendar)
            if earliestExpenseWeekStart.map({ weekStart < $0 }) ?? true {
                earliestExpenseWeekStart = weekStart
            }
        }

        let firstWeekStart = earliestExpenseWeekStart ?? currentWeekStart
        var weekStart = firstWeekStart
        var pages: [OverviewWeekSpendingSnapshot] = []

        while weekStart <= currentWeekStart {
            let weekInterval = weekInterval(startingAt: weekStart, calendar: calendar)
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let dailyValues = dailyChartValues(
                startingAt: weekStart,
                count: 7,
                totalsByDay: dailyTotalsByDay,
                calendar: calendar
            )
            let range = valueRange(for: dailyValues)
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
                                minimum: range.minimum,
                                maximum: range.maximum
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
        currencyCode: String? = nil,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [OverviewChartPoint] {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: startOfToday)
        }
        let firstDay = days.first ?? startOfToday
        let lastDayExclusive = calendar.date(byAdding: .day, value: 1, to: days.last ?? startOfToday) ?? startOfToday

        var totalsByDay: [Date: Int64] = [:]
        for record in transactionRecords where record.entryStatus == .posted && TransactionLogic.reportedExpenseAmount(for: record) != 0 {
            guard record.occurredAt >= firstDay,
                  record.occurredAt < lastDayExclusive else {
                continue
            }

            let day = calendar.startOfDay(for: record.occurredAt)
            totalsByDay[day, default: 0] += chartSpendingAmount(
                for: record,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates
            )
        }

        let values = days.map { day in
            (date: day, valueMinor: totalsByDay[day] ?? 0)
        }
        let range = valueRange(for: values)

        return values.map { item in
            OverviewChartPoint(
                date: item.date,
                label: weekdayLabel(for: item.date, calendar: calendar),
                valueMinor: item.valueMinor,
                intensity: normalizedIntensity(
                    value: item.valueMinor,
                    minimum: range.minimum,
                    maximum: range.maximum
                )
            )
        }
    }

    static func categorySpendingMonthPages(
        from transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [OverviewCategorySpendingMonthSnapshot] {
        let currentMonthStart = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        var transactionsByMonth: [Date: [OverviewTransactionSnapshot]] = [:]
        var earliestExpenseMonthStart: Date?

        for transaction in transactions where isCategorySpendingTransaction(transaction) {
            let monthStart = PlanningLogic.startOfMonth(for: transaction.occurredAt, calendar: calendar)
            transactionsByMonth[monthStart, default: []].append(transaction)
            if earliestExpenseMonthStart.map({ monthStart < $0 }) ?? true {
                earliestExpenseMonthStart = monthStart
            }
        }

        let firstMonthStart = earliestExpenseMonthStart ?? currentMonthStart
        var monthStart = firstMonthStart
        var pages: [OverviewCategorySpendingMonthSnapshot] = []

        while monthStart <= currentMonthStart {
            pages.append(
                categorySpendingMonth(
                    monthStart: monthStart,
                    transactionsInMonth: transactionsByMonth[monthStart] ?? [],
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates,
                    calendar: calendar
                )
            )

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                break
            }
            monthStart = nextMonth
        }

        if pages.isEmpty {
            return [
                categorySpendingMonth(
                    monthStart: currentMonthStart,
                    transactionsInMonth: transactionsByMonth[currentMonthStart] ?? [],
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates,
                    calendar: calendar
                )
            ]
        }

        return pages
    }

    static func monthlyCashflowPages(
        from transactionRecords: [TransactionRecordSnapshot],
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate] = [],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [OverviewMonthlyCashflowSnapshot] {
        let currentMonthStart = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        var totalsByMonth: [Date: (incomeMinor: Int64, expenseMinor: Int64)] = [:]
        var earliestMonthStart: Date?

        for record in transactionRecords where record.entryStatus == .posted {
            let incomeMinor = TransactionLogic.reportedIncomeAmount(for: record)
            let expenseMinor = TransactionLogic.reportedExpenseAmount(for: record)
            guard incomeMinor != 0 || expenseMinor != 0 else { continue }

            let monthStart = PlanningLogic.startOfMonth(for: record.occurredAt, calendar: calendar)
            guard monthStart <= currentMonthStart else { continue }

            if earliestMonthStart.map({ monthStart < $0 }) ?? true {
                earliestMonthStart = monthStart
            }

            if incomeMinor != 0 {
                totalsByMonth[monthStart, default: (0, 0)].incomeMinor += reportingAmount(
                    amountMinor: incomeMinor,
                    sourceCurrencyCode: record.sourceCurrencyCode,
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates
                )
            }
            if expenseMinor != 0 {
                totalsByMonth[monthStart, default: (0, 0)].expenseMinor += reportingAmount(
                    amountMinor: expenseMinor,
                    sourceCurrencyCode: record.sourceCurrencyCode,
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates
                )
            }
        }

        let firstMonthStart = earliestMonthStart ?? currentMonthStart
        var monthStart = firstMonthStart
        var pages: [OverviewMonthlyCashflowSnapshot] = []

        while monthStart <= currentMonthStart {
            let totals = totalsByMonth[monthStart] ?? (0, 0)
            pages.append(
                OverviewMonthlyCashflowSnapshot(
                    monthStart: monthStart,
                    incomeMinor: totals.incomeMinor,
                    expenseMinor: totals.expenseMinor
                )
            )

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                break
            }
            monthStart = nextMonth
        }

        return pages
    }

    static func categorySpendingMonth(
        from transactions: [OverviewTransactionSnapshot],
        selectedMonth: Date,
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate] = [],
        calendar: Calendar = MistiaCalendar.current
    ) -> OverviewCategorySpendingMonthSnapshot {
        let monthStart = PlanningLogic.startOfMonth(for: selectedMonth, calendar: calendar)
        let monthInterval = calendar.dateInterval(of: .month, for: monthStart)
        let transactionsInMonth = transactions.filter { transaction in
            guard isCategorySpendingTransaction(transaction),
                  let monthInterval
            else {
                return false
            }

            return transaction.occurredAt >= monthInterval.start
                && transaction.occurredAt < monthInterval.end
        }

        return categorySpendingMonth(
            monthStart: monthStart,
            transactionsInMonth: transactionsInMonth,
            currencyCode: currencyCode,
            exchangeRates: exchangeRates,
            calendar: calendar
        )
    }

    static func categorySpendingInterval(
        from transactions: [OverviewTransactionSnapshot],
        interval: DateInterval,
        title: String,
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate] = [],
        calendar: Calendar = MistiaCalendar.current
    ) -> OverviewCategorySpendingMonthSnapshot {
        let intervalTransactions = transactions.filter { transaction in
            isCategorySpendingTransaction(transaction)
                && interval.contains(transaction.occurredAt)
        }

        return OverviewCategorySpendingMonthSnapshot(
            monthStart: PlanningLogic.startOfMonth(for: interval.start, calendar: calendar),
            title: title,
            currencyCode: currencyCode,
            slices: categorySpendingSlices(
                from: intervalTransactions,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates
            )
        )
    }

    private static func categorySpendingMonth(
        monthStart: Date,
        transactionsInMonth: [OverviewTransactionSnapshot],
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate],
        calendar: Calendar
    ) -> OverviewCategorySpendingMonthSnapshot {
        OverviewCategorySpendingMonthSnapshot(
            monthStart: monthStart,
            title: MistiaDateFormatting.monthYearString(for: monthStart, calendar: calendar),
            currencyCode: currencyCode,
            slices: categorySpendingSlices(
                from: transactionsInMonth,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates
            )
        )
    }

    private static func chartSpendingAmount(
        for record: TransactionRecordSnapshot,
        currencyCode: String?,
        exchangeRates: [MistiaExchangeRate]
    ) -> Int64 {
        guard let currencyCode else {
            return TransactionLogic.reportedExpenseAmount(for: record)
        }
        return reportingAmount(
            amountMinor: TransactionLogic.reportedExpenseAmount(for: record),
            sourceCurrencyCode: record.sourceCurrencyCode,
            currencyCode: currencyCode,
            exchangeRates: exchangeRates
        )
    }

    private static func dailyChartValues(
        startingAt startDay: Date,
        count: Int,
        totalsByDay: [Date: Int64],
        calendar: Calendar
    ) -> [(date: Date, valueMinor: Int64)] {
        (0..<count).compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else {
                return nil
            }
            return (day, totalsByDay[day] ?? 0)
        }
    }

    private static func valueRange(
        for values: [(date: Date, valueMinor: Int64)]
    ) -> (minimum: Int64, maximum: Int64) {
        var minimum = values.first?.valueMinor ?? 0
        var maximum = minimum

        for item in values.dropFirst() {
            minimum = min(minimum, item.valueMinor)
            maximum = max(maximum, item.valueMinor)
        }

        return (minimum, maximum)
    }

    private static let uncategorizedSpendingSliceID = "uncategorized-expense"
    private static let uncategorizedSpendingName = L10n.shared.corelogic.overview.uncategorized
    private static let uncategorizedSpendingIcon = "tray.full.fill"
    private static let uncategorizedSpendingColorHex = "#8A8A8E"

    private static func isCategorySpendingTransaction(
        _ transaction: OverviewTransactionSnapshot
    ) -> Bool {
        guard transaction.entryStatus == .posted, !transaction.isArchived else {
            return false
        }

        if let reportingExpenseMinor = transaction.reportingExpenseMinor {
            return reportingExpenseMinor != 0
        }

        if isPaidForExpenseDebt(transaction) {
            return true
        }

        return transaction.primaryKind == .expense
            && !isAdjustment(transaction)
            && !isCreditCardPayment(transaction)
            && !isInstallmentPayment(transaction)
    }

    private static func reportedExpenseAmount(
        for transaction: OverviewTransactionSnapshot
    ) -> Int64 {
        if let reportingExpenseMinor = transaction.reportingExpenseMinor {
            return reportingExpenseMinor
        }
        return isCategorySpendingTransaction(transaction) ? transaction.amountMinor : 0
    }

    private static func isPaidForDebt(
        _ transaction: OverviewTransactionSnapshot
    ) -> Bool {
        transaction.primaryKind == .transfer
            && transaction.transferSubtype == .debt
            && transaction.debtIntent == .borrow
            && transaction.sourceWalletID == nil
    }

    private static func isPaidForExpenseDebt(
        _ transaction: OverviewTransactionSnapshot
    ) -> Bool {
        isPaidForDebt(transaction)
            && transaction.categoryID != nil
            && !isAdjustment(transaction)
            && !isInstallmentPayment(transaction)
    }

    private static func isAdjustment(
        _ transaction: OverviewTransactionSnapshot
    ) -> Bool {
        transaction.categoryID == MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID
            || transaction.categoryID == MistiaSystemCategoryIdentity.balanceAdjustmentIncomeID
    }

    private static func isInstallmentPayment(
        _ transaction: OverviewTransactionSnapshot
    ) -> Bool {
        transaction.categoryID == MistiaSystemCategoryIdentity.canonicalID(for: .loanRepayment)
    }

    private static func isCreditCardPayment(
        _ transaction: OverviewTransactionSnapshot
    ) -> Bool {
        let titleLooksLikeCardPayment = TransactionLogic.isCreditCardPaymentTitle(transaction.title)
        if transaction.primaryKind == .transfer {
            guard transaction.transferSubtype == .internalTransfer else { return false }
            return transaction.destinationWalletKind == .creditCard
                || (transaction.destinationWalletID != nil && titleLooksLikeCardPayment)
        }

        return transaction.primaryKind == .expense
            && transaction.sourceWalletKind != .creditCard
            && titleLooksLikeCardPayment
    }

    private static func normalizedCategoryName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func categoryBranchKey(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        let name = transaction.categoryParentName ?? transaction.categoryName ?? ""
        let normalized = normalizedCategoryName(name)
        guard !normalized.isEmpty else {
            return uncategorizedSpendingSliceID
        }
        return "category-name-\(normalized)"
    }

    private static func categoryChildKey(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        let name = transaction.categoryName ?? ""
        let normalized = normalizedCategoryName(name)
        guard !normalized.isEmpty else {
            return uncategorizedSpendingSliceID
        }
        return "category-name-\(normalized)"
    }

    private static func categorySpendingSlices(
        from transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate]
    ) -> [OverviewCategorySpendingSlice] {
        let groupedByBranch = Dictionary(grouping: transactions) { transaction in
            categoryBranchKey(for: transaction)
        }

        return groupedByBranch
            .map { _, branchTransactions in
                categoryBranchSlice(
                    from: branchTransactions,
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates
                )
            }
            .sorted(by: categorySliceSort)
    }

    private static func categoryBranchSlice(
        from transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate]
    ) -> OverviewCategorySpendingSlice {
        guard let template = transactions.first else {
            return uncategorizedCategorySlice(amountMinor: 0)
        }

        let amount = transactions.reduce(into: Int64.zero) { partialResult, transaction in
            partialResult += reportingAmount(
                amountMinor: reportedExpenseAmount(for: transaction),
                sourceCurrencyCode: transaction.sourceCurrencyCode,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates
            )
        }
        let categoryID = template.categoryParentID ?? template.categoryID
        let childSlices = Dictionary(grouping: transactions) { transaction in
            categoryChildKey(for: transaction)
        }
            .map { _, childTransactions in
                categoryChildSlice(
                    from: childTransactions,
                    currencyCode: currencyCode,
                    exchangeRates: exchangeRates
                )
            }
            .sorted(by: categorySliceSort)

        guard let categoryID else {
            return uncategorizedCategorySlice(amountMinor: amount, childSlices: childSlices)
        }

        return OverviewCategorySpendingSlice(
            id: categorySliceID(for: categoryID),
            categoryID: categoryID,
            name: template.categoryParentName ?? template.categoryName ?? uncategorizedSpendingName,
            iconSymbolName: template.categoryParentIconSymbolName
                ?? template.categoryIconSymbolName
                ?? uncategorizedSpendingIcon,
            colorHex: template.categoryParentColorHex
                ?? template.categoryColorHex
                ?? uncategorizedSpendingColorHex,
            amountMinor: amount,
            childSlices: childSlices.map(\.withoutChildren)
        )
    }

    private static func categoryChildSlice(
        from transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        exchangeRates: [MistiaExchangeRate]
    ) -> OverviewCategorySpendingSlice {
        guard let template = transactions.first else {
            return uncategorizedCategorySlice(amountMinor: 0)
        }

        let amount = transactions.reduce(into: Int64.zero) { partialResult, transaction in
            partialResult += reportingAmount(
                amountMinor: reportedExpenseAmount(for: transaction),
                sourceCurrencyCode: transaction.sourceCurrencyCode,
                currencyCode: currencyCode,
                exchangeRates: exchangeRates
            )
        }

        guard let categoryID = template.categoryID else {
            return uncategorizedCategorySlice(amountMinor: amount)
        }

        return OverviewCategorySpendingSlice(
            id: categorySliceID(for: categoryID),
            categoryID: categoryID,
            name: template.categoryName ?? uncategorizedSpendingName,
            iconSymbolName: template.categoryIconSymbolName ?? uncategorizedSpendingIcon,
            colorHex: template.categoryColorHex ?? uncategorizedSpendingColorHex,
            amountMinor: amount,
            childSlices: []
        )
    }

    private static func uncategorizedCategorySlice(
        amountMinor: Int64,
        childSlices: [OverviewCategorySpendingSlice] = []
    ) -> OverviewCategorySpendingSlice {
        OverviewCategorySpendingSlice(
            id: uncategorizedSpendingSliceID,
            categoryID: nil,
            name: uncategorizedSpendingName,
            iconSymbolName: uncategorizedSpendingIcon,
            colorHex: uncategorizedSpendingColorHex,
            amountMinor: amountMinor,
            childSlices: childSlices.map(\.withoutChildren)
        )
    }

    private static func categorySliceID(for categoryID: UUID) -> String {
        "category-\(categoryID.uuidString.lowercased())"
    }

    private static func categorySliceSort(
        lhs: OverviewCategorySpendingSlice,
        rhs: OverviewCategorySpendingSlice
    ) -> Bool {
        if lhs.amountMinor != rhs.amountMinor {
            return lhs.amountMinor > rhs.amountMinor
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    static func budgetAlerts(
        budgets: [BudgetPlanSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current,
        exchangeRates: [MistiaExchangeRate] = [],
        familyTransactions: [FamilyAggregateTransactionSnapshot] = [],
        familySpendingAvailable: Bool = true,
        includesStable: Bool = false,
        maximumCount: Int? = 3
    ) -> [OverviewBudgetAlertSnapshot] {
        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let activeBudgets = PlanningLogic.activeBudgetPlans(
            plans: budgets,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
        let rows = PlanningLogic.budgetBranchRows(
            plans: activeBudgets.filter { !$0.categoryName.isEmpty },
            records: transactionRecords,
            selectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar,
            exchangeRates: exchangeRates,
            familyTransactions: familyTransactions,
            familySpendingAvailable: familySpendingAvailable
        )

        let sortedRows = rows
            .filter { row in
                includesStable || row.health != .stable
            }
            .sorted { lhs, rhs in
                if lhs.health != rhs.health {
                    return budgetHealthRank(lhs.health) > budgetHealthRank(rhs.health)
                }
                if lhs.progress != rhs.progress {
                    return lhs.progress > rhs.progress
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        let visibleRows = maximumCount.map { Array(sortedRows.prefix($0)) } ?? sortedRows

        return visibleRows
            .map { row in
                OverviewBudgetAlertSnapshot(
                    id: row.id,
                    name: row.name,
                    iconSymbolName: row.iconSymbolName,
                    spentMinor: row.spentMinor,
                    limitMinor: row.limitMinor,
                    currencyCode: row.currencyCode,
                    progress: row.progress,
                    paceAssessment: row.paceAssessment,
                    tint: budgetTint(health: row.health)
                )
            }
    }

    static func dueAlerts(
        creditCardDues: [PlanningCreditCardDueSnapshot],
        recurringDues: [PlanningRecurringDueSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [OverviewDueAlertSnapshot] {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        struct DueCandidate {
            let id: String
            let name: String
            let iconSymbolName: String
            let amountMinor: Int64?
            let dueDate: Date
            let alertDate: Date
            let currencyCode: String
            let sourceKind: PlanningDueSourceKind
            let sourceID: UUID?
            let dueMonthKey: String
            let requiresAmountInput: Bool
        }

        let items: [DueCandidate] = creditCardDues
            .filter { $0.status == .pending }
            .map {
                DueCandidate(
                    id: "credit-\($0.walletID.uuidString)",
                    name: $0.walletName,
                    iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
                    amountMinor: $0.amountMinor,
                    dueDate: $0.dueDate,
                    alertDate: $0.dueDate,
                    currencyCode: $0.currencyCode,
                    sourceKind: .creditCard,
                    sourceID: $0.walletID,
                    dueMonthKey: PlanningLogic.monthKey(for: $0.statementMonth, calendar: calendar),
                    requiresAmountInput: false
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
                    alertDate: startOfToday < calendar.startOfDay(for: $0.paymentStartDate) ? $0.paymentStartDate : $0.dueDate,
                    currencyCode: $0.currencyCode,
                    sourceKind: $0.sourceKind,
                    sourceID: $0.sourceID,
                    dueMonthKey: PlanningLogic.monthKey(for: $0.paymentStartDate, calendar: calendar),
                    requiresAmountInput: $0.amountMinor == nil
                )
            }

        return items
            .compactMap { item in
                let dayDelta = calendar.dateComponents(
                    [.day],
                    from: startOfToday,
                    to: calendar.startOfDay(for: item.alertDate)
                ).day ?? 0

                guard (0...7).contains(dayDelta) else {
                    return nil
                }

                return OverviewDueAlertSnapshot(
                    id: item.id,
                    name: item.name,
                    iconSymbolName: item.iconSymbolName,
                    amountMinor: item.amountMinor,
                    dueDate: item.alertDate,
                    dayDelta: dayDelta,
                    currencyCode: item.currencyCode,
                    tint: dayDelta <= 3 ? .red : .blue,
                    sourceKind: item.sourceKind,
                    sourceID: item.sourceID,
                    dueMonthKey: item.dueMonthKey,
                    requiresAmountInput: item.requiresAmountInput
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
        calendar: Calendar = MistiaCalendar.current
    ) -> [OverviewRecentTransactionSnapshot] {
        transactions
            .filter {
                $0.entryStatus == .posted
                    && !$0.isArchived
                    && $0.financialDomain == .ordinary
            }
            .sorted(by: transactionSort)
            .prefix(5)
            .map { transaction in
                let rowCurrencyCode = MistiaCurrencyLogic.normalizedCode(
                    transaction.sourceCurrencyCode ?? currencyCode
                )
                return OverviewRecentTransactionSnapshot(
                    id: transaction.id,
                    title: transaction.title,
                    amountMinor: transaction.amountMinor,
                    currencyCode: rowCurrencyCode,
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
        calendar: Calendar = MistiaCalendar.current
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
        calendar: Calendar = MistiaCalendar.current
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

    private static func budgetTint(health: PlanningBudgetHealth) -> OverviewTint {
        switch health {
        case .stable:
            .green
        case .caution:
            .orange
        case .exceeded:
            .red
        }
    }

    private static func budgetHealthRank(_ health: PlanningBudgetHealth) -> Int {
        switch health {
        case .stable:
            0
        case .caution:
            1
        case .exceeded:
            2
        }
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
            case .familyTransfer:
                return transaction.destinationWalletID == nil ? .income : .expense
            case .debt:
                if isPaidForExpenseDebt(transaction) {
                    return .expense
                }
                if isPaidForDebt(transaction) {
                    return .neutral
                }
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
        sourceCurrencyCode: String?,
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

    static func transactionKindTitle(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense:
            return L10n.shared.corelogic.overview.expense
        case .income:
            return L10n.shared.corelogic.overview.income
        case .transfer:
            switch transaction.transferSubtype {
            case .internalTransfer:
                return L10n.shared.corelogic.overview.internalTransfer
            case .familyTransfer:
                return L10n.shared.corelogic.financeenums.family
            case .debt:
                return transaction.debtIntent?.title ?? L10n.shared.corelogic.overview.debt
            case .none:
                return L10n.shared.corelogic.overview.transfer
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
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    static func weekInterval(
        startingAt weekStart: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> DateInterval {
        let normalizedWeekStart = calendar.startOfDay(for: weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
        return DateInterval(start: normalizedWeekStart, end: weekEnd)
    }

    static func weekRangeTitle(
        for interval: DateInterval,
        isCurrentWeek: Bool,
        calendar: Calendar = MistiaCalendar.current
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


extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
