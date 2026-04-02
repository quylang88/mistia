import XCTest
@testable import MistiaCoreLogic

final class OverviewLogicTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(
            MistiaAppLanguage.vietnamese.rawValue,
            forKey: MistiaAppLanguage.userDefaultsKey
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        super.tearDown()
    }

    func testTotalAssetBalanceExcludesCreditCardWallets() {
        let cash = OverviewWalletSnapshot(
            id: UUID(),
            name: "Tien mat",
            kind: .cash,
            openingBalanceMinor: 10_000,
            currencyCode: "JPY",
            sortOrder: 0,
            createdAt: makeDate(year: 2026, month: 4, day: 1)
        )
        let bank = OverviewWalletSnapshot(
            id: UUID(),
            name: "SMBC",
            kind: .bank,
            openingBalanceMinor: 20_000,
            currencyCode: "JPY",
            sortOrder: 1,
            createdAt: makeDate(year: 2026, month: 4, day: 1)
        )
        let card = OverviewWalletSnapshot(
            id: UUID(),
            name: "Card",
            kind: .creditCard,
            openingBalanceMinor: 8_000,
            currencyCode: "JPY",
            sortOrder: 2,
            createdAt: makeDate(year: 2026, month: 4, day: 1)
        )

        let records = [
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 2_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 2),
                sourceWalletID: cash.id,
                sourceWalletKind: .cash
            ),
            makeTransactionRecord(
                primaryKind: .income,
                amountMinor: 5_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 2),
                sourceWalletID: bank.id,
                sourceWalletKind: .bank
            ),
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 3_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 2),
                sourceWalletID: card.id,
                sourceWalletKind: .creditCard
            )
        ]

        XCTAssertEqual(
            OverviewLogic.totalAssetBalance(
                wallets: [cash, bank, card],
                transactionRecords: records
            ),
            33_000
        )
    }

    func testRecentSevenDaySpendingChartPointsFillsSevenDaysAndMapsIntensityFromLowToHigh() {
        let referenceDate = makeDate(year: 2026, month: 4, day: 7, hour: 12)
        let records = [
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 1_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 2, hour: 9)
            ),
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 4_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 6, hour: 19)
            )
        ]

        let points = OverviewLogic.recentSevenDaySpendingChartPoints(
            from: records,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points.map(\.valueMinor), [0, 1_000, 0, 0, 0, 4_000, 0])
        XCTAssertEqual(points[0].intensity, 0)
        XCTAssertEqual(points[5].intensity, 1)
    }

    func testWeeklySpendingPagesUseMondayToSundayForCurrentWeek() throws {
        let referenceDate = makeDate(year: 2026, month: 4, day: 9, hour: 12)
        let records = [
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 1_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 6, hour: 9)
            ),
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 2_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 8, hour: 18)
            ),
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 3_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 12, hour: 10)
            )
        ]

        let pages = OverviewLogic.weeklySpendingPages(
            from: records,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let currentWeek = try XCTUnwrap(pages.last)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(currentWeek.weekStart, makeDate(year: 2026, month: 4, day: 6))
        XCTAssertEqual(currentWeek.weekEnd, makeDate(year: 2026, month: 4, day: 12))
        XCTAssertEqual(
            currentWeek.title,
            OverviewLogic.weekRangeTitle(
                for: DateInterval(
                    start: makeDate(year: 2026, month: 4, day: 6),
                    end: makeDate(year: 2026, month: 4, day: 13)
                ),
                isCurrentWeek: true,
                calendar: calendar
            )
        )
        XCTAssertEqual(currentWeek.points.map(\.label), ["T2", "T3", "T4", "T5", "T6", "T7", "CN"])
        XCTAssertEqual(currentWeek.points.map(\.valueMinor), [1_000, 0, 2_000, 0, 0, 0, 3_000])
        XCTAssertEqual(try XCTUnwrap(currentWeek.points.first).intensity, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(currentWeek.points.last).intensity, 1, accuracy: 0.0001)
    }

    func testWeeklySpendingPagesIncludeEmptyWeeksUntilCurrentWeek() {
        let referenceDate = makeDate(year: 2026, month: 4, day: 22, hour: 10)
        let records = [
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 2_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 6, hour: 8)
            )
        ]

        let pages = OverviewLogic.weeklySpendingPages(
            from: records,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            pages.map(\.weekStart),
            [
                makeDate(year: 2026, month: 4, day: 6),
                makeDate(year: 2026, month: 4, day: 13),
                makeDate(year: 2026, month: 4, day: 20)
            ]
        )
        XCTAssertEqual(pages[1].points.map(\.valueMinor), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(
            pages[2].title,
            OverviewLogic.weekRangeTitle(
                for: DateInterval(
                    start: makeDate(year: 2026, month: 4, day: 20),
                    end: makeDate(year: 2026, month: 4, day: 27)
                ),
                isCurrentWeek: true,
                calendar: calendar
            )
        )
    }

    func testBudgetAlertsFilterOverFiftyPercentSortDescendingAndApplyThresholds() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 24)
        let foodCategory = UUID()
        let shoppingCategory = UUID()
        let travelCategory = UUID()
        let healthCategory = UUID()

        let budgets = [
            makeBudget(
                categoryID: foodCategory,
                name: "An uong",
                limitMinor: 10_000,
                monthAnchor: selectedMonth
            ),
            makeBudget(
                categoryID: shoppingCategory,
                name: "Mua sam",
                limitMinor: 10_000,
                monthAnchor: selectedMonth
            ),
            makeBudget(
                categoryID: travelCategory,
                name: "Du lich",
                limitMinor: 10_000,
                monthAnchor: selectedMonth
            ),
            makeBudget(
                categoryID: healthCategory,
                name: "Suc khoe",
                limitMinor: 10_000,
                monthAnchor: selectedMonth
            )
        ]

        let records = [
            makeTransactionRecord(primaryKind: .expense, amountMinor: 9_500, occurredAt: makeDate(year: 2026, month: 4, day: 4), categoryID: foodCategory),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 8_100, occurredAt: makeDate(year: 2026, month: 4, day: 5), categoryID: shoppingCategory),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 6_000, occurredAt: makeDate(year: 2026, month: 4, day: 6), categoryID: travelCategory),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 4_000, occurredAt: makeDate(year: 2026, month: 4, day: 7), categoryID: healthCategory)
        ]

        let alerts = OverviewLogic.budgetAlerts(
            budgets: budgets,
            transactionRecords: records,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(alerts.map(\.name), ["An uong", "Mua sam", "Du lich"])
        XCTAssertEqual(alerts[0].tint, .red)
        XCTAssertEqual(alerts[1].tint, .orange)
        XCTAssertEqual(alerts[2].tint, .orange)
    }

    func testDueAlertsMergeSourcesLimitToThreeAndFlagThreeDaysOrLessRed() {
        let referenceDate = makeDate(year: 2026, month: 4, day: 10, hour: 8)

        let creditCards = [
            PlanningCreditCardDueSnapshot(
                id: UUID(),
                walletID: UUID(),
                walletName: "Visa",
                network: .visa,
                last4: "1111",
                amountMinor: 10_000,
                dueDate: makeDate(year: 2026, month: 4, day: 12),
                paymentSourceWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        ]

        let recurring = [
            PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .recurringBill,
                sourceID: UUID(),
                name: "Internet",
                iconSymbolName: "wifi",
                amountMinor: 2_000,
                dueDate: makeDate(year: 2026, month: 4, day: 11),
                frequencyMonths: 1,
                totalCycles: nil,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            ),
            PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .installment,
                sourceID: UUID(),
                name: "Laptop",
                iconSymbolName: "laptopcomputer",
                amountMinor: 3_000,
                dueDate: makeDate(year: 2026, month: 4, day: 14),
                frequencyMonths: 1,
                totalCycles: 6,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            ),
            PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .recurringBill,
                sourceID: UUID(),
                name: "Dien",
                iconSymbolName: "bolt.fill",
                amountMinor: 1_000,
                dueDate: makeDate(year: 2026, month: 4, day: 17),
                frequencyMonths: 1,
                totalCycles: nil,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        ]

        let alerts = OverviewLogic.dueAlerts(
            creditCardDues: creditCards,
            recurringDues: recurring,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(alerts.count, 3)
        XCTAssertEqual(alerts.map(\.name), ["Internet", "Visa", "Laptop"])
        XCTAssertEqual(alerts[0].tint, .red)
        XCTAssertEqual(alerts[1].tint, .red)
        XCTAssertEqual(alerts[2].tint, .blue)
    }

    func testRelativeTimeLabelMatchesMinutesHoursTodayYesterdayAndFallbackDate() {
        let referenceDate = makeDate(year: 2026, month: 4, day: 10, hour: 18, minute: 0)

        XCTAssertEqual(
            OverviewLogic.relativeTimeLabel(
                for: makeDate(year: 2026, month: 4, day: 10, hour: 17, minute: 37),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            "23 phút trước"
        )
        XCTAssertEqual(
            OverviewLogic.relativeTimeLabel(
                for: makeDate(year: 2026, month: 4, day: 10, hour: 13, minute: 0),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            "5 tiếng trước"
        )
        XCTAssertEqual(
            OverviewLogic.relativeTimeLabel(
                for: makeDate(year: 2026, month: 4, day: 10, hour: 6, minute: 0),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            "Hôm nay"
        )
        XCTAssertEqual(
            OverviewLogic.relativeTimeLabel(
                for: makeDate(year: 2026, month: 4, day: 9, hour: 2, minute: 0),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            "Hôm qua"
        )
        XCTAssertEqual(
            OverviewLogic.relativeTimeLabel(
                for: makeDate(year: 2026, month: 4, day: 8, hour: 18, minute: 0),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            "Hôm kia"
        )
        XCTAssertEqual(
            OverviewLogic.relativeTimeLabel(
                for: makeDate(year: 2026, month: 4, day: 2, hour: 18, minute: 0),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            MistiaDateFormatting.shortDateString(
                for: makeDate(year: 2026, month: 4, day: 2, hour: 18, minute: 0),
                language: .vietnamese,
                calendar: calendar
            )
        )
    }

    func testCreditCardStatementCycleAndTransactionsInCycle() throws {
        let referenceDate = makeDate(year: 2026, month: 4, day: 2, hour: 12)
        let cardID = UUID()
        let account = OverviewCreditCardStatementAccountSnapshot(
            id: cardID,
            walletID: cardID,
            walletName: "SMBC Card",
            iconSymbolName: "creditcard.fill",
            issuerName: "SMBC",
            network: .visa,
            last4: "1234",
            creditLimitMinor: 100_000,
            currentDebtMinor: 20_000,
            statementClosingDay: 25,
            paymentDueDay: 10,
            paymentSourceWalletName: "SMBC Bank",
            currencyCode: "JPY",
            openedAt: makeDate(year: 2026, month: 1, day: 1)
        )

        let statement = OverviewLogic.creditCardStatement(
            accounts: [account],
            transactions: [
                makeOverviewTransaction(
                    primaryKind: .expense,
                    title: "Cafe",
                    amountMinor: 2_000,
                    occurredAt: makeDate(year: 2026, month: 3, day: 27),
                    sourceWalletID: cardID,
                    sourceWalletName: "SMBC Card",
                    sourceWalletKind: .creditCard
                ),
                makeOverviewTransaction(
                    primaryKind: .transfer,
                    transferSubtype: .internalTransfer,
                    title: "Thanh toan the",
                    amountMinor: 5_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 1),
                    sourceWalletID: UUID(),
                    sourceWalletName: "SMBC Bank",
                    sourceWalletKind: .bank,
                    destinationWalletID: cardID,
                    destinationWalletName: "SMBC Card",
                    destinationWalletKind: .creditCard
                ),
                makeOverviewTransaction(
                    primaryKind: .expense,
                    title: "Qua ky",
                    amountMinor: 1_000,
                    occurredAt: makeDate(year: 2026, month: 3, day: 25),
                    sourceWalletID: cardID,
                    sourceWalletName: "SMBC Card",
                    sourceWalletKind: .creditCard
                ),
                makeOverviewTransaction(
                    primaryKind: .expense,
                    title: "Ky sau",
                    amountMinor: 3_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 26),
                    sourceWalletID: cardID,
                    sourceWalletName: "SMBC Card",
                    sourceWalletKind: .creditCard
                )
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let card = try XCTUnwrap(statement.cards.first)
        XCTAssertEqual(card.cycle.start, makeDate(year: 2026, month: 3, day: 26))
        XCTAssertEqual(card.cycle.end, makeDate(year: 2026, month: 4, day: 26))
        XCTAssertEqual(card.charges.map(\.title), ["Cafe"])
        XCTAssertEqual(card.payments.map(\.title), ["Thanh toan the"])
    }

    func testMonthlyStatementRendererProducesStableFilenameAndExpectedSections() {
        let statement = OverviewMonthlyStatementSnapshot(
            generatedAt: makeDate(year: 2026, month: 4, day: 10),
            period: DateInterval(
                start: makeDate(year: 2026, month: 4, day: 1),
                end: makeDate(year: 2026, month: 4, day: 10)
            ),
            totalAssetBalanceMinor: 30_000,
            totalIncomeMinor: 20_000,
            totalExpenseMinor: 5_000,
            netCashflowMinor: 15_000,
            wallets: [
                OverviewStatementWalletRow(
                    id: UUID(),
                    name: "Tien mat",
                    kindTitle: "Tiền mặt",
                    openingBalanceMinor: 10_000,
                    currentBalanceMinor: 15_000,
                    currencyCode: "JPY"
                )
            ],
            chartPoints: [
                OverviewChartPoint(
                    date: makeDate(year: 2026, month: 4, day: 9),
                    label: "T5",
                    valueMinor: 2_000,
                    intensity: 0.6
                )
            ],
            transactions: [
                OverviewStatementTransactionRow(
                    id: UUID(),
                    occurredAt: makeDate(year: 2026, month: 4, day: 9, hour: 9),
                    title: "Luong",
                    kindTitle: "Thu nhap",
                    accountText: "SMBC",
                    detailText: "Luong",
                    amountMinor: 20_000,
                    currencyCode: "JPY",
                    cashflowStyle: .income,
                    statusTitle: "Đã ghi nhận"
                )
            ],
            currencyCode: "JPY"
        )

        let document = OverviewLogic.renderMonthlyStatement(statement)

        XCTAssertEqual(document.filename, "mistia-sao-ke-tong-hop-2026-04.html")
        XCTAssertTrue(document.html.contains("Sao kê tổng hợp tháng"))
        XCTAssertTrue(document.html.contains("Ví tài sản"))
        XCTAssertTrue(document.html.contains("Luong"))
    }

    func testMonthlyStatementKeepsRecentSevenDayChartInsteadOfWeeklyPager() {
        let referenceDate = makeDate(year: 2026, month: 4, day: 10, hour: 12)
        let wallet = OverviewWalletSnapshot(
            id: UUID(),
            name: "Tien mat",
            kind: .cash,
            openingBalanceMinor: 10_000,
            currencyCode: "JPY",
            sortOrder: 0,
            createdAt: makeDate(year: 2026, month: 4, day: 1)
        )
        let records = [
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 1_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 4, hour: 9)
            ),
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 3_000,
                occurredAt: makeDate(year: 2026, month: 4, day: 9, hour: 20)
            )
        ]

        let statement = OverviewLogic.monthlyStatement(
            wallets: [wallet],
            transactionRecords: records,
            transactions: [],
            currencyCode: "JPY",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(statement.chartPoints.count, 7)
        XCTAssertEqual(statement.chartPoints.map(\.valueMinor), [1_000, 0, 0, 0, 0, 3_000, 0])
    }

    private func makeBudget(
        categoryID: UUID,
        name: String,
        limitMinor: Int64,
        monthAnchor: Date
    ) -> BudgetPlanSnapshot {
        BudgetPlanSnapshot(
            id: UUID(),
            categoryID: categoryID,
            categoryName: name,
            categoryIconSymbolName: "fork.knife",
            categoryColorHex: "#FF9F1C",
            limitMinor: limitMinor,
            rolloverEnabled: false,
            currencyCode: "JPY",
            monthAnchor: monthAnchor
        )
    }

    private func makeTransactionRecord(
        primaryKind: TransactionPrimaryKind,
        amountMinor: Int64,
        occurredAt: Date,
        sourceWalletID: UUID? = UUID(),
        sourceWalletKind: LedgerWalletKind? = .cash,
        categoryID: UUID? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Test",
            note: nil,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }

    private func makeOverviewTransaction(
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        title: String,
        amountMinor: Int64,
        occurredAt: Date,
        sourceWalletID: UUID? = nil,
        sourceWalletName: String? = nil,
        sourceWalletKind: LedgerWalletKind? = nil,
        destinationWalletID: UUID? = nil,
        destinationWalletName: String? = nil,
        destinationWalletKind: LedgerWalletKind? = nil
    ) -> OverviewTransactionSnapshot {
        OverviewTransactionSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: nil,
            entryStatus: .posted,
            title: title,
            note: nil,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletName: sourceWalletName,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletName: destinationWalletName,
            destinationWalletKind: destinationWalletKind,
            categoryID: nil,
            categoryName: nil,
            counterpartyName: nil
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .distantPast
    }
}
