import XCTest
@testable import MistiaCoreLogic

final class OverviewLogicTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
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

    func testTotalAssetBalanceConvertsWalletsToReportingCurrencyBeforeSumming() {
        let jpyWallet = OverviewWalletSnapshot(
            id: UUID(),
            name: "JPY",
            kind: .cash,
            openingBalanceMinor: 100,
            currencyCode: "JPY",
            sortOrder: 0,
            createdAt: makeDate(year: 2026, month: 4, day: 1)
        )
        let vndWallet = OverviewWalletSnapshot(
            id: UUID(),
            name: "VND",
            kind: .bank,
            openingBalanceMinor: 16_500,
            currencyCode: "VND",
            sortOrder: 1,
            createdAt: makeDate(year: 2026, month: 4, day: 1)
        )

        let total = OverviewLogic.totalAssetBalance(
            wallets: [jpyWallet, vndWallet],
            transactionRecords: [],
            currencyCode: "JPY",
            exchangeRates: [jpyVndRate]
        )

        XCTAssertEqual(total, 200)
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

    func testRecentSevenDaySpendingGroupsRawUTCInstantByJapanLocalDay() throws {
        let japanCalendar = MistiaCalendar.gregorian(
            locale: Locale(identifier: "ja_JP"),
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )
        let referenceDate = try makeDate(year: 2026, month: 5, day: 6, hour: 12, calendar: japanCalendar)
        let utcPreviousDayInstant = try makeDate(year: 2026, month: 5, day: 6, hour: 0, minute: 30, calendar: japanCalendar)
        let records = [
            makeTransactionRecord(
                primaryKind: .expense,
                amountMinor: 2_500,
                occurredAt: utcPreviousDayInstant
            )
        ]

        let points = OverviewLogic.recentSevenDaySpendingChartPoints(
            from: records,
            referenceDate: referenceDate,
            calendar: japanCalendar
        )

        XCTAssertEqual(points.map(\.valueMinor), [0, 0, 0, 0, 0, 0, 2_500])
        XCTAssertEqual(
            japanCalendar.dateComponents([.year, .month, .day], from: points.last?.date ?? .distantPast).day,
            6
        )
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

    func testCategorySpendingMonthGroupsExpenseByParentBranch() {
        let foodParent = UUID()
        let healthParent = UUID()
        let grocery = UUID()
        let dineOut = UUID()
        let medicine = UUID()

        let page = OverviewLogic.categorySpendingMonth(
            from: [
                makeOverviewExpense(
                    amountMinor: 5_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 2),
                    categoryID: grocery,
                    categoryName: "Đi chợ",
                    categoryParentID: foodParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentColorHex: "#FF8A4C"
                ),
                makeOverviewExpense(
                    amountMinor: 3_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 3),
                    categoryID: dineOut,
                    categoryName: "Ăn ngoài",
                    categoryParentID: foodParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentColorHex: "#FF8A4C"
                ),
                makeOverviewExpense(
                    amountMinor: 2_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 4),
                    categoryID: medicine,
                    categoryName: "Thuốc",
                    categoryParentID: healthParent,
                    categoryParentName: "Sức khỏe",
                    categoryParentColorHex: "#F45C7E"
                ),
                makeOverviewTransaction(
                    primaryKind: .income,
                    title: "Ignored income",
                    amountMinor: 9_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 5)
                ),
                makeOverviewExpense(
                    amountMinor: 7_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 6),
                    categoryID: UUID(),
                    categoryName: "Archived",
                    isArchived: true
                )
            ],
            selectedMonth: makeDate(year: 2026, month: 4, day: 15),
            currencyCode: "JPY",
            calendar: calendar
        )

        XCTAssertEqual(page.totalExpenseMinor, 10_000)
        XCTAssertEqual(page.slices.map(\.name), ["Sinh hoạt", "Sức khỏe"])
        XCTAssertEqual(page.slices.map(\.amountMinor), [8_000, 2_000])
        XCTAssertEqual(page.slices[0].colorHex, "#FF8A4C")
        XCTAssertEqual(page.slices[0].childSlices.map(\.name), ["Đi chợ", "Ăn ngoài"])
        XCTAssertEqual(page.slices[0].childSlices.map(\.amountMinor), [5_000, 3_000])
    }

    func testCategorySpendingExcludesNonSpendingExpenseLikePayments() {
        let grocery = UUID()

        let page = OverviewLogic.categorySpendingMonth(
            from: [
                makeOverviewExpense(
                    amountMinor: 5_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 2),
                    categoryID: grocery,
                    categoryName: "Đi chợ"
                ),
                makeOverviewExpense(
                    amountMinor: 7_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 3),
                    categoryID: MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID,
                    categoryName: "Điều chỉnh số dư"
                ),
                makeOverviewExpense(
                    amountMinor: 9_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 4),
                    categoryID: MistiaSystemCategoryIdentity.canonicalID(for: .loanRepayment),
                    categoryName: "Trả góp"
                ),
                makeOverviewTransaction(
                    primaryKind: .transfer,
                    transferSubtype: .internalTransfer,
                    title: "Chuyển tiền",
                    amountMinor: 11_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 5)
                )
            ],
            selectedMonth: makeDate(year: 2026, month: 4, day: 15),
            currencyCode: "JPY",
            calendar: calendar
        )

        XCTAssertEqual(page.totalExpenseMinor, 5_000)
        XCTAssertEqual(page.slices.map(\.name), ["Đi chợ"])
    }

    func testPaidForBorrowDebtWithCategoryCountsInOverviewSpending() {
        let grocery = UUID()
        let uncategorizedPaidFor = makeOverviewTransaction(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            title: "Được trả hộ",
            amountMinor: 9_000,
            sourceCurrencyCode: "JPY",
            occurredAt: makeDate(year: 2026, month: 4, day: 4),
            counterpartyName: "Minh"
        )
        let categorizedPaidFor = makeOverviewTransaction(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            title: "Được trả hộ",
            amountMinor: 4_000,
            sourceCurrencyCode: "JPY",
            occurredAt: makeDate(year: 2026, month: 4, day: 5),
            categoryID: grocery,
            categoryName: "Đi chợ",
            counterpartyName: "Minh"
        )

        let monthly = OverviewLogic.monthlyCashflowPages(
            from: [categorizedPaidFor, uncategorizedPaidFor],
            currencyCode: "JPY",
            referenceDate: makeDate(year: 2026, month: 4, day: 20),
            calendar: calendar
        )
        let categoryPage = OverviewLogic.categorySpendingMonth(
            from: [categorizedPaidFor, uncategorizedPaidFor],
            selectedMonth: makeDate(year: 2026, month: 4, day: 15),
            currencyCode: "JPY",
            calendar: calendar
        )

        XCTAssertEqual(monthly.map(\.expenseMinor), [4_000])
        XCTAssertEqual(categoryPage.totalExpenseMinor, 4_000)
        XCTAssertEqual(categoryPage.slices.map(\.name), ["Đi chợ"])
    }

    func testCategorySpendingDrilldownIncludesChildAndDirectParentTransactions() {
        let foodParent = UUID()
        let grocery = UUID()
        let dineOut = UUID()

        let page = OverviewLogic.categorySpendingMonth(
            from: [
                makeOverviewExpense(
                    amountMinor: 5_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 2),
                    categoryID: grocery,
                    categoryName: "Đi chợ",
                    categoryParentID: foodParent,
                    categoryParentName: "Sinh hoạt"
                ),
                makeOverviewExpense(
                    amountMinor: 3_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 3),
                    categoryID: dineOut,
                    categoryName: "Ăn ngoài",
                    categoryParentID: foodParent,
                    categoryParentName: "Sinh hoạt"
                ),
                makeOverviewExpense(
                    amountMinor: 1_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 4),
                    categoryID: foodParent,
                    categoryName: "Sinh hoạt"
                )
            ],
            selectedMonth: makeDate(year: 2026, month: 4, day: 15),
            currencyCode: "JPY",
            calendar: calendar
        )

        let drilldown = page.drilldownSlices(for: foodParent)

        XCTAssertEqual(page.slices.first?.amountMinor, 9_000)
        XCTAssertEqual(drilldown.map(\.name), ["Đi chợ", "Ăn ngoài", "Sinh hoạt"])
        XCTAssertEqual(drilldown.map(\.amountMinor), [5_000, 3_000, 1_000])
    }

    func testCategorySpendingMonthKeepsUncategorizedExpensesVisible() throws {
        let page = OverviewLogic.categorySpendingMonth(
            from: [
                makeOverviewExpense(
                    amountMinor: 4_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 9)
                )
            ],
            selectedMonth: makeDate(year: 2026, month: 4, day: 15),
            currencyCode: "JPY",
            calendar: calendar
        )

        let slice = try XCTUnwrap(page.slices.first)

        XCTAssertNil(slice.categoryID)
        XCTAssertEqual(slice.name, "Chưa phân loại")
        XCTAssertEqual(slice.amountMinor, 4_000)
        XCTAssertEqual(page.totalExpenseMinor, 4_000)
    }

    func testCategorySpendingMonthPagesRunFromEarliestExpenseThroughCurrentMonthOnly() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 18)
        let categoryID = UUID()

        let pages = OverviewLogic.categorySpendingMonthPages(
            from: [
                makeOverviewExpense(
                    amountMinor: 1_000,
                    occurredAt: makeDate(year: 2026, month: 3, day: 31),
                    categoryID: categoryID,
                    categoryName: "March"
                ),
                makeOverviewExpense(
                    amountMinor: 2_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 1),
                    categoryID: categoryID,
                    categoryName: "April"
                ),
                makeOverviewExpense(
                    amountMinor: 3_000,
                    occurredAt: makeDate(year: 2026, month: 6, day: 1),
                    categoryID: categoryID,
                    categoryName: "Future"
                )
            ],
            currencyCode: "JPY",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            pages.map(\.monthStart),
            [
                makeDate(year: 2026, month: 3, day: 1),
                makeDate(year: 2026, month: 4, day: 1),
                makeDate(year: 2026, month: 5, day: 1)
            ]
        )
        XCTAssertEqual(pages.map(\.totalExpenseMinor), [1_000, 2_000, 0])
    }

    func testCategorySpendingTopSlicesUseAmountThenNameOrdering() {
        let page = OverviewLogic.categorySpendingMonth(
            from: [
                makeOverviewExpense(amountMinor: 100, occurredAt: makeDate(year: 2026, month: 4, day: 1), categoryID: UUID(), categoryName: "Beta"),
                makeOverviewExpense(amountMinor: 100, occurredAt: makeDate(year: 2026, month: 4, day: 1), categoryID: UUID(), categoryName: "Alpha"),
                makeOverviewExpense(amountMinor: 300, occurredAt: makeDate(year: 2026, month: 4, day: 1), categoryID: UUID(), categoryName: "Gamma"),
                makeOverviewExpense(amountMinor: 200, occurredAt: makeDate(year: 2026, month: 4, day: 1), categoryID: UUID(), categoryName: "Delta")
            ],
            selectedMonth: makeDate(year: 2026, month: 4, day: 15),
            currencyCode: "JPY",
            calendar: calendar
        )

        XCTAssertEqual(page.slices.map(\.name), ["Gamma", "Delta", "Alpha", "Beta"])
        XCTAssertEqual(page.topSlices.map(\.name), ["Gamma", "Delta", "Alpha"])
    }

    func testCategorySpendingIntervalUsesSameParentChildRollup() {
        let foodParent = UUID()
        let grocery = UUID()
        let dineOut = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 7),
            end: makeDate(year: 2026, month: 4, day: 14)
        )

        let page = OverviewLogic.categorySpendingInterval(
            from: [
                makeOverviewExpense(
                    amountMinor: 6_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 7),
                    categoryID: grocery,
                    categoryName: "Đi chợ",
                    categoryParentID: foodParent,
                    categoryParentName: "Ăn uống"
                ),
                makeOverviewExpense(
                    amountMinor: 4_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 10),
                    categoryID: dineOut,
                    categoryName: "Ăn ngoài",
                    categoryParentID: foodParent,
                    categoryParentName: "Ăn uống"
                ),
                makeOverviewExpense(
                    amountMinor: 9_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 15),
                    categoryID: UUID(),
                    categoryName: "Excluded"
                )
            ],
            interval: interval,
            title: "Tuần",
            currencyCode: "JPY",
            calendar: calendar
        )

        XCTAssertEqual(page.title, "Tuần")
        XCTAssertEqual(page.totalExpenseMinor, 10_000)
        XCTAssertEqual(page.slices.map(\.name), ["Ăn uống"])
        XCTAssertEqual(page.slices.first?.childSlices.map(\.name), ["Đi chợ", "Ăn ngoài"])
    }

    func testBudgetAlertsFilterByPaceSortByHealthAndApplyTint() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 3)
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
            makeTransactionRecord(primaryKind: .expense, amountMinor: 12_000, occurredAt: makeDate(year: 2026, month: 4, day: 2), categoryID: foodCategory),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 2_500, occurredAt: makeDate(year: 2026, month: 4, day: 2), categoryID: shoppingCategory),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 1_000, occurredAt: makeDate(year: 2026, month: 4, day: 2), categoryID: travelCategory),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 400, occurredAt: makeDate(year: 2026, month: 4, day: 2), categoryID: healthCategory)
        ]

        let alerts = OverviewLogic.budgetAlerts(
            budgets: budgets,
            transactionRecords: records,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(alerts.map(\.name), ["An uong", "Mua sam"])
        XCTAssertEqual(alerts[0].tint, .red)
        XCTAssertEqual(alerts[1].tint, .orange)
        XCTAssertEqual(alerts[0].health, .exceeded)
        XCTAssertEqual(alerts[1].health, .caution)
    }

    func testBudgetAlertsCanIncludeStableRowsForNotificationStateTransitions() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 24)
        let categoryIDs = (0..<5).map { _ in UUID() }

        let budgets = categoryIDs.enumerated().map { index, categoryID in
            makeBudget(
                categoryID: categoryID,
                name: "Budget \(index)",
                limitMinor: 10_000,
                monthAnchor: selectedMonth
            )
        }
        let records = [
            makeTransactionRecord(primaryKind: .expense, amountMinor: 12_000, occurredAt: makeDate(year: 2026, month: 4, day: 4), categoryID: categoryIDs[0]),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 9_000, occurredAt: makeDate(year: 2026, month: 4, day: 5), categoryID: categoryIDs[1]),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 8_100, occurredAt: makeDate(year: 2026, month: 4, day: 6), categoryID: categoryIDs[2]),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 8_000, occurredAt: makeDate(year: 2026, month: 4, day: 7), categoryID: categoryIDs[3]),
            makeTransactionRecord(primaryKind: .expense, amountMinor: 7_999, occurredAt: makeDate(year: 2026, month: 4, day: 8), categoryID: categoryIDs[4])
        ]

        let alerts = OverviewLogic.budgetAlerts(
            budgets: budgets,
            transactionRecords: records,
            referenceDate: referenceDate,
            calendar: calendar,
            includesStable: true,
            maximumCount: nil
        )

        XCTAssertEqual(alerts.map(\.name), ["Budget 0", "Budget 1", "Budget 2", "Budget 3", "Budget 4"])
        XCTAssertEqual(alerts[0].tint, .red)
        XCTAssertEqual(alerts[1].health, .stable)
        XCTAssertEqual(alerts[4].progressPercentText, "80%")
    }

    func testBudgetAlertsDoNotWarnWhenNearEndSpendingMatchesPace() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let categoryID = UUID()

        let alerts = OverviewLogic.budgetAlerts(
            budgets: [
                makeBudget(
                    categoryID: categoryID,
                    name: "On pace",
                    limitMinor: 100_000,
                    monthAnchor: selectedMonth
                )
            ],
            transactionRecords: [
                makeTransactionRecord(
                    primaryKind: .expense,
                    amountMinor: 80_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 20),
                    categoryID: categoryID
                )
            ],
            referenceDate: makeDate(year: 2026, month: 4, day: 24),
            calendar: calendar
        )

        XCTAssertTrue(alerts.isEmpty)
    }

    func testBudgetAlertsRollUpChildBudgetsByParentBranch() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 10)
        let livingParent = UUID()
        let travelParent = UUID()
        let foodCategory = UUID()
        let housingCategory = UUID()
        let trainCategory = UUID()

        let alerts = OverviewLogic.budgetAlerts(
            budgets: [
                makeBudget(
                    categoryID: foodCategory,
                    name: "Ăn uống",
                    limitMinor: 10_000,
                    monthAnchor: selectedMonth,
                    categoryParentID: livingParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentIconSymbolName: "house.fill",
                    categoryParentColorHex: "#5A6C7D"
                ),
                makeBudget(
                    categoryID: housingCategory,
                    name: "Nhà ở",
                    limitMinor: 10_000,
                    monthAnchor: selectedMonth,
                    categoryParentID: livingParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentIconSymbolName: "house.fill",
                    categoryParentColorHex: "#5A6C7D"
                ),
                makeBudget(
                    categoryID: travelParent,
                    name: "Di chuyển & chuyến đi",
                    limitMinor: 10_000,
                    monthAnchor: selectedMonth,
                    categoryIsParent: true
                )
            ],
            transactionRecords: [
                makeTransactionRecord(
                    primaryKind: .expense,
                    amountMinor: 7_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 4),
                    categoryID: foodCategory,
                    categoryParentID: livingParent
                ),
                makeTransactionRecord(
                    primaryKind: .expense,
                    amountMinor: 6_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 6),
                    categoryID: housingCategory,
                    categoryParentID: livingParent
                ),
                makeTransactionRecord(
                    primaryKind: .expense,
                    amountMinor: 8_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 8),
                    categoryID: trainCategory,
                    categoryParentID: travelParent
                )
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts.map(\.name), ["Di chuyển & chuyến đi", "Sinh hoạt"])
        XCTAssertEqual(alerts[0].spentMinor, 8_000)
        XCTAssertEqual(alerts[0].limitMinor, 10_000)
        XCTAssertEqual(alerts[1].spentMinor, 13_000)
        XCTAssertEqual(alerts[1].limitMinor, 20_000)
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
                availableCreditMinor: 5_000,
                statementMonth: makeDate(year: 2026, month: 3, day: 1),
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
                iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
                categorySystemKey: .internet,
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
                iconSymbolName: "mistia.plan.installment",
                categorySystemKey: .loanRepayment,
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
                iconSymbolName: MistiaSystemCategoryKey.electricity.iconSymbolName,
                categorySystemKey: .electricity,
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
        XCTAssertEqual(alerts.map { $0.name }, ["Internet", "Visa", "Laptop"])
        XCTAssertEqual(alerts[0].tint, .red)
        XCTAssertEqual(alerts[1].tint, .red)
        XCTAssertEqual(alerts[1].dueMonthKey, "2026-03")
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
            availableCreditMinor: 80_000,
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

    func testCreditCardStatementKeepsRowsScopedToEachCardWhenTransactionsContainNoise() throws {
        let referenceDate = makeDate(year: 2026, month: 4, day: 2, hour: 12)
        let primaryCardID = UUID()
        let secondaryCardID = UUID()
        let cashWalletID = UUID()
        let accounts = [
            makeCreditCardStatementAccount(
                walletID: secondaryCardID,
                walletName: "B Card"
            ),
            makeCreditCardStatementAccount(
                walletID: primaryCardID,
                walletName: "A Card"
            )
        ]

        let statement = OverviewLogic.creditCardStatement(
            accounts: accounts,
            transactions: [
                makeOverviewTransaction(
                    primaryKind: .expense,
                    title: "Primary latest",
                    amountMinor: 2_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 2),
                    sourceWalletID: primaryCardID,
                    sourceWalletName: "A Card",
                    sourceWalletKind: .creditCard
                ),
                makeOverviewTransaction(
                    primaryKind: .expense,
                    title: "Cash noise",
                    amountMinor: 1_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 2),
                    sourceWalletID: cashWalletID,
                    sourceWalletName: "Cash",
                    sourceWalletKind: .cash
                ),
                makeOverviewTransaction(
                    primaryKind: .expense,
                    title: "Secondary charge",
                    amountMinor: 3_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 1),
                    sourceWalletID: secondaryCardID,
                    sourceWalletName: "B Card",
                    sourceWalletKind: .creditCard
                ),
                makeOverviewTransaction(
                    primaryKind: .transfer,
                    transferSubtype: .internalTransfer,
                    title: "Primary payment",
                    amountMinor: 2_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 3),
                    sourceWalletID: cashWalletID,
                    sourceWalletName: "Cash",
                    sourceWalletKind: .cash,
                    destinationWalletID: primaryCardID,
                    destinationWalletName: "A Card",
                    destinationWalletKind: .creditCard
                ),
                makeOverviewTransaction(
                    primaryKind: .transfer,
                    transferSubtype: .internalTransfer,
                    title: "Wrong destination noise",
                    amountMinor: 2_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 4),
                    sourceWalletID: cashWalletID,
                    sourceWalletName: "Cash",
                    sourceWalletKind: .cash,
                    destinationWalletID: cashWalletID,
                    destinationWalletName: "Cash",
                    destinationWalletKind: .cash
                )
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(statement.cards.map(\.walletName), ["A Card", "B Card"])
        XCTAssertEqual(statement.cards[0].charges.map(\.title), ["Primary latest"])
        XCTAssertEqual(statement.cards[0].payments.map(\.title), ["Primary payment"])
        XCTAssertEqual(statement.cards[1].charges.map(\.title), ["Secondary charge"])
        XCTAssertTrue(statement.cards[1].payments.isEmpty)
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
        monthAnchor: Date,
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil,
        categoryParentIconSymbolName: String? = nil,
        categoryParentColorHex: String? = nil,
        categoryIsParent: Bool = false
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
            monthAnchor: monthAnchor,
            categoryParentID: categoryParentID,
            categoryParentName: categoryParentName,
            categoryParentIconSymbolName: categoryParentIconSymbolName,
            categoryParentColorHex: categoryParentColorHex,
            categoryIsParent: categoryIsParent
        )
    }

    private func makeTransactionRecord(
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        amountMinor: Int64,
        occurredAt: Date,
        sourceCurrencyCode: String? = nil,
        sourceWalletID: UUID? = UUID(),
        sourceWalletKind: LedgerWalletKind? = .cash,
        categoryID: UUID? = nil,
        categoryParentID: UUID? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: .posted,
            title: "Test",
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            categoryParentID: categoryParentID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }

    private func makeOverviewTransaction(
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        title: String,
        amountMinor: Int64,
        sourceCurrencyCode: String? = nil,
        occurredAt: Date,
        isArchived: Bool = false,
        sourceWalletID: UUID? = nil,
        sourceWalletName: String? = nil,
        sourceWalletKind: LedgerWalletKind? = nil,
        destinationWalletID: UUID? = nil,
        destinationWalletName: String? = nil,
        destinationWalletKind: LedgerWalletKind? = nil,
        categoryID: UUID? = nil,
        categoryName: String? = nil,
        categoryIconSymbolName: String? = nil,
        categoryColorHex: String? = nil,
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil,
        categoryParentIconSymbolName: String? = nil,
        categoryParentColorHex: String? = nil,
        counterpartyName: String? = nil
    ) -> OverviewTransactionSnapshot {
        OverviewTransactionSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: .posted,
            title: title,
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletName: sourceWalletName,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletName: destinationWalletName,
            destinationWalletKind: destinationWalletKind,
            categoryID: categoryID,
            categoryName: categoryName,
            categoryIconSymbolName: categoryIconSymbolName,
            categoryColorHex: categoryColorHex,
            categoryParentID: categoryParentID,
            categoryParentName: categoryParentName,
            categoryParentIconSymbolName: categoryParentIconSymbolName,
            categoryParentColorHex: categoryParentColorHex,
            counterpartyName: counterpartyName,
            isArchived: isArchived
        )
    }

    private func makeCreditCardStatementAccount(
        walletID: UUID,
        walletName: String
    ) -> OverviewCreditCardStatementAccountSnapshot {
        OverviewCreditCardStatementAccountSnapshot(
            id: walletID,
            walletID: walletID,
            walletName: walletName,
            iconSymbolName: "creditcard.fill",
            issuerName: "Issuer",
            network: .visa,
            last4: "1234",
            creditLimitMinor: 100_000,
            currentDebtMinor: 20_000,
            availableCreditMinor: 80_000,
            statementClosingDay: 25,
            paymentDueDay: 10,
            paymentSourceWalletName: "Cash",
            currencyCode: "JPY",
            openedAt: makeDate(year: 2026, month: 1, day: 1)
        )
    }

    private func makeOverviewExpense(
        amountMinor: Int64,
        occurredAt: Date,
        categoryID: UUID? = nil,
        categoryName: String? = nil,
        categoryIconSymbolName: String? = "fork.knife",
        categoryColorHex: String? = "#FF9F1C",
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil,
        categoryParentIconSymbolName: String? = "folder.fill",
        categoryParentColorHex: String? = "#5B7BFF",
        isArchived: Bool = false
    ) -> OverviewTransactionSnapshot {
        makeOverviewTransaction(
            primaryKind: .expense,
            title: categoryName ?? "Expense",
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            isArchived: isArchived,
            categoryID: categoryID,
            categoryName: categoryName,
            categoryIconSymbolName: categoryID == nil ? nil : categoryIconSymbolName,
            categoryColorHex: categoryID == nil ? nil : categoryColorHex,
            categoryParentID: categoryParentID,
            categoryParentName: categoryParentName,
            categoryParentIconSymbolName: categoryParentID == nil ? nil : categoryParentIconSymbolName,
            categoryParentColorHex: categoryParentID == nil ? nil : categoryParentColorHex
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        (try? makeDate(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar)) ?? .distantPast
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(calendar.date(from: components))
    }

    private var jpyVndRate: MistiaExchangeRate {
        MistiaExchangeRate(
            baseCurrencyCode: "JPY",
            quoteCurrencyCode: "VND",
            rateDecimalString: "165",
            provider: "test",
            fetchedAt: Date(timeIntervalSince1970: 0),
            rateDate: "2026-05-27"
        )
    }
}
