import XCTest
@testable import MistiaCoreLogic

final class PlanningLogicTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testMonthKeyAndScheduledDateUseJapanLocalCalendarAtUTCBoundary() throws {
        let japanCalendar = MistiaCalendar.gregorian(
            locale: Locale(identifier: "ja_JP"),
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )
        let utcCalendar = MistiaCalendar.gregorian(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt
        )
        let japanJuneInstant = try makeDate(
            year: 2026,
            month: 6,
            day: 1,
            hour: 0,
            minute: 30,
            calendar: japanCalendar
        )

        XCTAssertEqual(PlanningLogic.monthKey(for: japanJuneInstant, calendar: japanCalendar), "2026-06")
        XCTAssertEqual(PlanningLogic.monthKey(for: japanJuneInstant, calendar: utcCalendar), "2026-05")

        let dueDate = PlanningLogic.scheduledDate(
            dueDay: 10,
            selectedMonth: japanJuneInstant,
            calendar: japanCalendar
        )
        let dueComponents = japanCalendar.dateComponents([.year, .month, .day], from: dueDate)
        XCTAssertEqual(dueComponents.year, 2026)
        XCTAssertEqual(dueComponents.month, 6)
        XCTAssertEqual(dueComponents.day, 10)
    }

    func testBudgetRowsSortByHighestProgressAndSummaryUsesThresholds() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 10)
        let foodCategory = UUID()
        let travelCategory = UUID()

        let rows = PlanningLogic.budgetRows(
            plans: [
                BudgetPlanSnapshot(
                    id: UUID(),
                    categoryID: foodCategory,
                    categoryName: "Ăn uống",
                    categoryIconSymbolName: "fork.knife",
                    categoryColorHex: "#FF9F1C",
                    limitMinor: 10_000,
                    rolloverEnabled: false,
                    currencyCode: "JPY",
                    monthAnchor: selectedMonth
                ),
                BudgetPlanSnapshot(
                    id: UUID(),
                    categoryID: travelCategory,
                    categoryName: "Du lịch",
                    categoryIconSymbolName: "airplane",
                    categoryColorHex: "#5B7BFF",
                    limitMinor: 20_000,
                    rolloverEnabled: false,
                    currencyCode: "JPY",
                    monthAnchor: selectedMonth
                )
            ],
            records: [
                makeRecord(
                    primaryKind: .expense,
                    amountMinor: 9_500,
                    occurredAt: makeDate(year: 2026, month: 4, day: 5),
                    categoryID: foodCategory
                ),
                makeRecord(
                    primaryKind: .expense,
                    amountMinor: 5_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 7),
                    categoryID: travelCategory
                )
            ],
            selectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.name), ["Ăn uống", "Du lịch"])
        XCTAssertEqual(rows.first?.tone, .warning) // 0.95 is now .warning (>= 0.8)
        XCTAssertEqual(rows.last?.tone, .calm)

        let summary = PlanningLogic.budgetSummary(from: rows)
        XCTAssertEqual(summary.totalBudgetMinor, 30_000)
        XCTAssertEqual(summary.spentMinor, 14_500)
        XCTAssertEqual(summary.remainingMinor, 15_500)
        XCTAssertEqual(summary.health, .stable)
    }

    func testBudgetSummaryConvertsRowsToReportingCurrencyBeforeSumming() {
        let rows = [
            PlanningBudgetRowSnapshot(
                id: UUID(),
                categoryID: UUID(),
                name: "JPY",
                iconSymbolName: "yen",
                colorHex: "#111111",
                spentMinor: 50,
                limitMinor: 100,
                currencyCode: "JPY",
                daysRemaining: 10,
                isPastMonth: false
            ),
            PlanningBudgetRowSnapshot(
                id: UUID(),
                categoryID: UUID(),
                name: "VND",
                iconSymbolName: "dong",
                colorHex: "#222222",
                spentMinor: 8_250,
                limitMinor: 16_500,
                currencyCode: "VND",
                daysRemaining: 10,
                isPastMonth: false
            )
        ]

        let summary = PlanningLogic.budgetSummary(
            from: rows,
            reportingCurrencyCode: "JPY",
            exchangeRates: [jpyVndRate]
        )

        XCTAssertEqual(summary.totalBudgetMinor, 200)
        XCTAssertEqual(summary.spentMinor, 100)
        XCTAssertEqual(summary.remainingMinor, 100)
    }

    func testGoalRowsPickNearestGoalAndComputeMonthlyContribution() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)

        let rows = PlanningLogic.goalRows(
            goals: [
                SavingsGoalSnapshot(
                    id: UUID(),
                    name: "Quỹ khẩn cấp",
                    iconSymbolName: "shield.fill",
                    targetMinor: 20_000,
                    currentSavedMinor: 12_000,
                    targetDate: makeDate(year: 2026, month: 8, day: 20),
                    linkedWalletID: nil,
                    currencyCode: "JPY",
                    sortOrder: 0
                ),
                SavingsGoalSnapshot(
                    id: UUID(),
                    name: "Laptop mới",
                    iconSymbolName: "laptopcomputer",
                    targetMinor: 30_000,
                    currentSavedMinor: 4_000,
                    targetDate: makeDate(year: 2026, month: 12, day: 1),
                    linkedWalletID: nil,
                    currencyCode: "JPY",
                    sortOrder: 1
                )
            ],
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        XCTAssertEqual(rows.first?.name, "Quỹ khẩn cấp")
        XCTAssertEqual(rows.first?.monthlyRequiredMinor, 1_600)
        XCTAssertEqual(rows.last?.monthlyRequiredMinor, 2_889)

        let summary = PlanningLogic.goalSummary(from: rows)
        XCTAssertEqual(summary.activeCount, 2)
        XCTAssertEqual(summary.totalSavedMinor, 16_000)
        XCTAssertEqual(summary.nearestGoalName, "Quỹ khẩn cấp")
    }

    func testBudgetBranchRowsUseParentLimitWithChildAllocation() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 10)
        let livingParent = UUID()
        let travelParent = UUID()
        let foodCategory = UUID()
        let housingCategory = UUID()
        let trainCategory = UUID()

        let rows = PlanningLogic.budgetBranchRows(
            plans: [
                makeBudget(
                    categoryID: livingParent,
                    categoryName: "Sinh hoạt",
                    limitMinor: 35_000,
                    monthAnchor: selectedMonth,
                    categoryIsParent: true
                ),
                makeBudget(
                    categoryID: foodCategory,
                    categoryName: "Ăn uống",
                    limitMinor: 10_000,
                    monthAnchor: selectedMonth,
                    categoryParentID: livingParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentIconSymbolName: "house.fill",
                    categoryParentColorHex: "#5A6C7D"
                ),
                makeBudget(
                    categoryID: housingCategory,
                    categoryName: "Nhà ở",
                    limitMinor: 20_000,
                    monthAnchor: selectedMonth,
                    categoryParentID: livingParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentIconSymbolName: "house.fill",
                    categoryParentColorHex: "#5A6C7D"
                ),
                makeBudget(
                    categoryID: travelParent,
                    categoryName: "Di chuyển & chuyến đi",
                    limitMinor: 15_000,
                    monthAnchor: selectedMonth,
                    categoryIsParent: true
                )
            ],
            records: [
                makeRecord(
                    primaryKind: .expense,
                    amountMinor: 6_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 5),
                    categoryID: foodCategory,
                    categoryParentID: livingParent
                ),
                makeRecord(
                    primaryKind: .expense,
                    amountMinor: 7_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 7),
                    categoryID: housingCategory,
                    categoryParentID: livingParent
                ),
                makeRecord(
                    primaryKind: .expense,
                    amountMinor: 3_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 8),
                    categoryID: trainCategory,
                    categoryParentID: travelParent
                )
            ],
            selectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.name), ["Sinh hoạt", "Di chuyển & chuyến đi"])

        guard let livingRow = rows.first(where: { $0.parentCategoryID == livingParent }) else {
            XCTFail("Expected a living branch row")
            return
        }
        XCTAssertEqual(livingRow.mode, .parentWithChildren)
        XCTAssertEqual(livingRow.primaryBudgetID, livingRow.parentBudgetID)
        XCTAssertEqual(livingRow.spentMinor, 13_000)
        XCTAssertEqual(livingRow.limitMinor, 35_000)
        XCTAssertEqual(livingRow.allocatedChildLimitMinor, 30_000)
        XCTAssertEqual(livingRow.unallocatedLimitMinor, 5_000)
        XCTAssertEqual(livingRow.childRows.map(\.name), ["Ăn uống", "Nhà ở"])

        guard let travelRow = rows.first(where: { $0.parentCategoryID == travelParent }) else {
            XCTFail("Expected a travel branch row")
            return
        }
        XCTAssertEqual(travelRow.mode, .parentOnly)
        XCTAssertEqual(travelRow.primaryBudgetID, travelRow.parentBudgetID)
        XCTAssertEqual(travelRow.spentMinor, 3_000)
        XCTAssertEqual(travelRow.limitMinor, 15_000)
        XCTAssertEqual(travelRow.childRows.count, 0)

        let summary = PlanningLogic.budgetSummary(from: rows)
        XCTAssertEqual(summary.totalBudgetMinor, 50_000)
        XCTAssertEqual(summary.spentMinor, 16_000)
        XCTAssertEqual(summary.remainingMinor, 34_000)
    }

    func testBudgetBranchRowsShowSingleChildWithoutParentAsTopLevelBudget() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 10)
        let livingParent = UUID()
        let foodCategory = UUID()
        let foodBudgetID = UUID()

        let rows = PlanningLogic.budgetBranchRows(
            plans: [
                makeBudget(
                    id: foodBudgetID,
                    categoryID: foodCategory,
                    categoryName: "Ăn uống",
                    limitMinor: 10_000,
                    monthAnchor: selectedMonth,
                    categoryParentID: livingParent,
                    categoryParentName: "Sinh hoạt",
                    categoryParentIconSymbolName: "house.fill",
                    categoryParentColorHex: "#5A6C7D"
                )
            ],
            records: [
                makeRecord(
                    primaryKind: .expense,
                    amountMinor: 4_000,
                    occurredAt: makeDate(year: 2026, month: 4, day: 8),
                    categoryID: foodCategory,
                    categoryParentID: livingParent
                )
            ],
            selectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.mode, .childOnly)
        XCTAssertEqual(row.parentCategoryID, livingParent)
        XCTAssertEqual(row.primaryBudgetID, foodBudgetID)
        XCTAssertEqual(row.name, "Ăn uống")
        XCTAssertEqual(row.spentMinor, 4_000)
        XCTAssertEqual(row.limitMinor, 10_000)
        XCTAssertTrue(row.childRows.isEmpty)

        let summary = PlanningLogic.budgetSummary(from: rows)
        XCTAssertEqual(summary.totalBudgetMinor, 10_000)
        XCTAssertEqual(summary.spentMinor, 4_000)
    }

    func testBudgetAllocationValidationAllowsChildOnlyAndCapsExistingParent() {
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let livingParent = UUID()
        let foodCategory = UUID()
        let housingCategory = UUID()
        let transportCategory = UUID()
        let parentBudgetID = UUID()
        let foodBudgetID = UUID()

        let parentBudget = makeBudget(
            id: parentBudgetID,
            categoryID: livingParent,
            categoryName: "Sinh hoạt",
            limitMinor: 30_000,
            monthAnchor: selectedMonth,
            categoryIsParent: true
        )
        let foodBudget = makeBudget(
            id: foodBudgetID,
            categoryID: foodCategory,
            categoryName: "Ăn uống",
            limitMinor: 10_000,
            monthAnchor: selectedMonth,
            categoryParentID: livingParent,
            categoryParentName: "Sinh hoạt"
        )

        XCTAssertEqual(
            PlanningLogic.validateBudgetAllocation(
                categoryID: housingCategory,
                branchCategoryID: livingParent,
                categoryIsParent: false,
                categoryIsChild: true,
                limitMinor: 20_000,
                monthAnchor: selectedMonth,
                plans: [parentBudget, foodBudget],
                calendar: calendar
            ),
            .valid
        )
        XCTAssertEqual(
            PlanningLogic.validateBudgetAllocation(
                categoryID: housingCategory,
                branchCategoryID: livingParent,
                categoryIsParent: false,
                categoryIsChild: true,
                limitMinor: 20_001,
                monthAnchor: selectedMonth,
                plans: [parentBudget, foodBudget],
                calendar: calendar
            ),
            .childBudgetsExceedParent(childTotalMinor: 30_001, parentLimitMinor: 30_000)
        )
        XCTAssertEqual(
            PlanningLogic.validateBudgetAllocation(
                categoryID: livingParent,
                branchCategoryID: livingParent,
                categoryIsParent: true,
                categoryIsChild: false,
                limitMinor: 9_999,
                monthAnchor: selectedMonth,
                plans: [parentBudget, foodBudget],
                editingBudgetID: parentBudgetID,
                calendar: calendar
            ),
            .parentLimitBelowChildren(childTotalMinor: 10_000, parentLimitMinor: 9_999)
        )
        XCTAssertEqual(
            PlanningLogic.validateBudgetAllocation(
                categoryID: transportCategory,
                branchCategoryID: transportCategory,
                categoryIsParent: false,
                categoryIsChild: true,
                limitMinor: 5_000,
                monthAnchor: selectedMonth,
                plans: [],
                calendar: calendar
            ),
            .valid
        )
    }

    func testDueSummaryLogic() {
        let currentMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 10)

        let creditCards = [
            PlanningCreditCardDueSnapshot(
                id: UUID(),
                walletID: UUID(),
                walletName: "SMBC Card",
                network: .visa,
                last4: "1234",
                amountMinor: 12_000, // Thẻ đến hạn tháng này
                availableCreditMinor: 8_000,
                statementMonth: makeDate(year: 2026, month: 3, day: 1),
                dueDate: makeDate(year: 2026, month: 4, day: 14),
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
                name: "Điện",
                iconSymbolName: MistiaSystemCategoryKey.electricity.iconSymbolName,
                categorySystemKey: .electricity,
                amountMinor: 3_000, // Quá hạn
                dueDate: makeDate(year: 2026, month: 4, day: 8),
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
                name: "iPhone",
                iconSymbolName: "mistia.plan.installment",
                categorySystemKey: .loanRepayment,
                amountMinor: 5_000, // Xa (> 7 ngày)
                dueDate: makeDate(year: 2026, month: 4, day: 25),
                frequencyMonths: 1,
                totalCycles: 12,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        ]

        let summary = PlanningLogic.dueSummary(
            creditCards: creditCards,
            recurring: recurring,
            selectedMonth: currentMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Sắp đến hạn: chỉ SMBC (14th) vì trong 7 ngày tới (10th -> 17th)
        XCTAssertEqual(summary.upcomingCount, 1)
        // Tổng cần trả: thẻ + hóa đơn + trả góp trong tháng đang chọn.
        XCTAssertEqual(summary.totalDueMinor, 20_000)
        // Quá hạn: Điện (8th)
        XCTAssertEqual(summary.overdueCount, 1)
    }

    func testRecurringBillWindowCarriesDeadlineIntoNextMonthWhenDueDayIsBeforePaymentStart() {
        let billID = UUID()
        let paymentWalletID = UUID()
        let selectedMonth = makeDate(year: 2026, month: 5, day: 1)

        let items = PlanningLogic.recurringBillDueItems(
            bills: [
                PlanningBillSnapshot(
                    id: billID,
                    name: "Internet",
                    iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
                    categorySystemKey: .internet,
                    amountMinor: 5_000,
                    dueDay: 10,
                    frequencyMonths: 1,
                    paymentWalletID: paymentWalletID,
                    currencyCode: "JPY",
                    createdAt: makeDate(year: 2026, month: 1, day: 1),
                    scheduleKind: .recurring,
                    paymentStartDay: 25,
                    paymentStartDate: nil,
                    hasExplicitDueDate: true,
                    dueDate: nil,
                    autoPayEnabled: false,
                    autoPayDay: nil,
                    autoPayDate: nil
                )
            ],
            occurrences: [],
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.paymentStartDate, makeDate(year: 2026, month: 5, day: 25))
        XCTAssertEqual(items.first?.dueDate, makeDate(year: 2026, month: 6, day: 10))
        XCTAssertTrue(items.first?.hasExplicitDueDate == true)
    }

    func testRecurringBillWindowKeepsDeadlineInSameMonthWhenDueDayIsAfterPaymentStart() {
        let items = PlanningLogic.recurringBillDueItems(
            bills: [
                PlanningBillSnapshot(
                    id: UUID(),
                    name: "Gas",
                    iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
                    categorySystemKey: .billing,
                    amountMinor: 3_000,
                    dueDay: 25,
                    frequencyMonths: 1,
                    paymentWalletID: UUID(),
                    currencyCode: "JPY",
                    createdAt: makeDate(year: 2026, month: 1, day: 1),
                    scheduleKind: .recurring,
                    paymentStartDay: 10,
                    paymentStartDate: nil,
                    hasExplicitDueDate: true,
                    dueDate: nil,
                    autoPayEnabled: false,
                    autoPayDay: nil,
                    autoPayDate: nil
                )
            ],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 5, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(items.first?.paymentStartDate, makeDate(year: 2026, month: 5, day: 10))
        XCTAssertEqual(items.first?.dueDate, makeDate(year: 2026, month: 5, day: 25))
        XCTAssertTrue(items.first?.hasExplicitDueDate == true)
    }

    func testRecurringBillFirstScheduledMonthDefaultsToCreatedAtMonth() {
        let items = PlanningLogic.recurringBillDueItems(
            bills: [
                PlanningBillSnapshot(
                    id: UUID(),
                    name: "Internet",
                    iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
                    categorySystemKey: .internet,
                    amountMinor: 5_000,
                    dueDay: 25,
                    frequencyMonths: 1,
                    paymentWalletID: UUID(),
                    currencyCode: "JPY",
                    createdAt: makeDate(year: 2026, month: 5, day: 20),
                    scheduleKind: .recurring,
                    paymentStartDay: 25,
                    paymentStartDate: nil,
                    firstScheduledMonth: nil,
                    hasExplicitDueDate: false,
                    dueDate: nil,
                    autoPayEnabled: false,
                    autoPayDay: nil,
                    autoPayDate: nil
                )
            ],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 5, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.paymentStartDate, makeDate(year: 2026, month: 5, day: 25))
    }

    func testRecurringBillCanStartNextMonthWithoutAppearingInCurrentMonth() {
        let bill = PlanningBillSnapshot(
            id: UUID(),
            name: "Train pass",
            iconSymbolName: MistiaSystemCategoryKey.publicTransport.iconSymbolName,
            categorySystemKey: .publicTransport,
            amountMinor: 12_000,
            dueDay: 5,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 5, day: 20),
            scheduleKind: .recurring,
            paymentStartDay: 5,
            paymentStartDate: nil,
            firstScheduledMonth: makeDate(year: 2026, month: 6, day: 1),
            hasExplicitDueDate: false,
            dueDate: nil,
            autoPayEnabled: false,
            autoPayDay: nil,
            autoPayDate: nil
        )

        let currentMonthItems = PlanningLogic.recurringBillDueItems(
            bills: [bill],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 5, day: 1),
            calendar: calendar
        )
        let nextMonthItems = PlanningLogic.recurringBillDueItems(
            bills: [bill],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 6, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(currentMonthItems.count, 0)
        XCTAssertEqual(nextMonthItems.count, 1)
        XCTAssertEqual(nextMonthItems.first?.paymentStartDate, makeDate(year: 2026, month: 6, day: 5))
    }

    func testCurrentMonthOverdueRecurringBillRemainsPayable() {
        let selectedMonth = makeDate(year: 2026, month: 5, day: 1)
        let items = PlanningLogic.recurringBillDueItems(
            bills: [
                PlanningBillSnapshot(
                    id: UUID(),
                    name: "Parking",
                    iconSymbolName: MistiaSystemCategoryKey.parking.iconSymbolName,
                    categorySystemKey: .parking,
                    amountMinor: 8_000,
                    dueDay: 5,
                    frequencyMonths: 1,
                    paymentWalletID: UUID(),
                    currencyCode: "JPY",
                    createdAt: makeDate(year: 2026, month: 5, day: 20),
                    scheduleKind: .recurring,
                    paymentStartDay: 1,
                    paymentStartDate: nil,
                    firstScheduledMonth: selectedMonth,
                    hasExplicitDueDate: true,
                    dueDate: nil,
                    autoPayEnabled: false,
                    autoPayDay: nil,
                    autoPayDate: nil
                )
            ],
            occurrences: [],
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        let summary = PlanningLogic.dueSummary(
            creditStatements: [],
            recurring: items,
            selectedMonth: selectedMonth,
            referenceDate: makeDate(year: 2026, month: 5, day: 20),
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.status, .pending)
        XCTAssertEqual(items.first?.paymentStartDate, makeDate(year: 2026, month: 5, day: 1))
        XCTAssertEqual(items.first?.dueDate, makeDate(year: 2026, month: 5, day: 5))
        XCTAssertEqual(summary.totalDueMinor, 8_000)
        XCTAssertEqual(summary.overdueCount, 1)
    }

    func testRecurringBillWindowTreatsMissingOrEqualDeadlineAsPaymentDate() {
        let selectedMonth = makeDate(year: 2026, month: 5, day: 1)
        let missingDeadline = PlanningBillSnapshot(
            id: UUID(),
            name: "Water",
            iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
            categorySystemKey: .billing,
            amountMinor: 2_000,
            dueDay: 25,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 1, day: 1),
            scheduleKind: .recurring,
            paymentStartDay: 25,
            paymentStartDate: nil,
            hasExplicitDueDate: false,
            dueDate: nil,
            autoPayEnabled: false,
            autoPayDay: nil,
            autoPayDate: nil
        )
        let equalDeadline = PlanningBillSnapshot(
            id: UUID(),
            name: "Phone",
            iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
            categorySystemKey: .billing,
            amountMinor: 4_000,
            dueDay: 25,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 1, day: 1),
            scheduleKind: .recurring,
            paymentStartDay: 25,
            paymentStartDate: nil,
            hasExplicitDueDate: true,
            dueDate: nil,
            autoPayEnabled: false,
            autoPayDay: nil,
            autoPayDate: nil
        )

        let items = PlanningLogic.recurringBillDueItems(
            bills: [missingDeadline, equalDeadline],
            occurrences: [],
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.paymentStartDate), [
            makeDate(year: 2026, month: 5, day: 25),
            makeDate(year: 2026, month: 5, day: 25)
        ])
        XCTAssertEqual(items.map(\.dueDate), [
            makeDate(year: 2026, month: 5, day: 25),
            makeDate(year: 2026, month: 5, day: 25)
        ])
        XCTAssertEqual(items.map(\.hasExplicitDueDate), [false, false])
    }

    func testOneTimeBillUsesExactPaymentDateAndOptionalDeadline() {
        let paymentDate = makeDate(year: 2026, month: 5, day: 25)
        let deadline = makeDate(year: 2026, month: 6, day: 10)

        let withDeadline = PlanningBillSnapshot(
            id: UUID(),
            name: "Tax",
            iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
            categorySystemKey: .billing,
            amountMinor: 8_000,
            dueDay: 10,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 5, day: 1),
            scheduleKind: .oneTime,
            paymentStartDay: 25,
            paymentStartDate: paymentDate,
            hasExplicitDueDate: true,
            dueDate: deadline,
            autoPayEnabled: false,
            autoPayDay: nil,
            autoPayDate: nil
        )
        let withoutDeadline = PlanningBillSnapshot(
            id: UUID(),
            name: "Application fee",
            iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
            categorySystemKey: .billing,
            amountMinor: 6_000,
            dueDay: 25,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 5, day: 1),
            scheduleKind: .oneTime,
            paymentStartDay: 25,
            paymentStartDate: paymentDate,
            hasExplicitDueDate: false,
            dueDate: nil,
            autoPayEnabled: false,
            autoPayDay: nil,
            autoPayDate: nil
        )

        let items = PlanningLogic.recurringBillDueItems(
            bills: [withDeadline, withoutDeadline],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 5, day: 1),
            calendar: calendar
        )
        let itemByName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        XCTAssertEqual(itemByName["Tax"]?.paymentStartDate, paymentDate)
        XCTAssertEqual(itemByName["Tax"]?.dueDate, deadline)
        XCTAssertEqual(itemByName["Tax"]?.hasExplicitDueDate, true)
        XCTAssertEqual(itemByName["Application fee"]?.paymentStartDate, paymentDate)
        XCTAssertEqual(itemByName["Application fee"]?.dueDate, paymentDate)
        XCTAssertEqual(itemByName["Application fee"]?.hasExplicitDueDate, false)
    }

    func testDueSummaryCountsRecurringBillsInPaymentStartMonth() {
        let selectedMonth = makeDate(year: 2026, month: 5, day: 1)
        let referenceDate = makeDate(year: 2026, month: 5, day: 22)
        let recurring = [
            PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .recurringBill,
                sourceID: UUID(),
                name: "Internet",
                iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
                categorySystemKey: .internet,
                amountMinor: 5_000,
                paymentStartDate: makeDate(year: 2026, month: 5, day: 25),
                dueDate: makeDate(year: 2026, month: 6, day: 10),
                hasExplicitDueDate: true,
                scheduleKind: .recurring,
                frequencyMonths: 1,
                totalCycles: nil,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        ]

        let summary = PlanningLogic.dueSummary(
            creditStatements: [],
            recurring: recurring,
            selectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.upcomingCount, 1)
        XCTAssertEqual(summary.totalDueMinor, 5_000)
        XCTAssertEqual(summary.overdueCount, 0)
    }

    func testCreditCardStatementClosesNextMonthAndBecomesPayableOnClosingDay() {
        let cardWalletID = UUID()
        let paymentWalletID = UUID()
        let statementMonth = makeDate(year: 2026, month: 2, day: 1)
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: paymentWalletID,
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            ),
            makeRecord(
                primaryKind: .expense,
                amountMinor: 9_000,
                occurredAt: makeDate(year: 2026, month: 3, day: 2),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            )
        ]

        let beforeClosing = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [],
            statementMonths: [statementMonth],
            referenceDate: makeDate(year: 2026, month: 3, day: 9),
            calendar: calendar
        )

        XCTAssertEqual(beforeClosing.first?.amountMinor, 32_456)
        XCTAssertEqual(beforeClosing.first?.closingDate, makeDate(year: 2026, month: 3, day: 10))
        XCTAssertEqual(beforeClosing.first?.dueDate, makeDate(year: 2026, month: 3, day: 26))
        XCTAssertEqual(beforeClosing.first?.state, .unclosed)

        let afterClosing = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [],
            statementMonths: [statementMonth],
            referenceDate: makeDate(year: 2026, month: 3, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(afterClosing.first?.state, .payable)
    }

    func testCreditCardStatementKeepsDebtLendingChargeAfterCollectionToCashWallet() {
        let cardWalletID = UUID()
        let cashWalletID = UUID()
        let paymentWalletID = UUID()
        let statementMonth = makeDate(year: 2026, month: 2, day: 1)
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: paymentWalletID,
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .lend,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .collect,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 20),
                categoryID: nil,
                sourceWalletID: cashWalletID,
                sourceWalletKind: .cash
            )
        ]

        let statements = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [],
            statementMonths: [statementMonth],
            referenceDate: makeDate(year: 2026, month: 3, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(statements.first?.amountMinor, 32_456)
        XCTAssertEqual(statements.first?.status, .pending)
        XCTAssertEqual(statements.first?.state, .payable)
    }

    func testSelectedDueMonthSummaryCountsCreditStatementByDueMonthBeforeClosing() {
        let cardWalletID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: UUID(),
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            )
        ]
        let dueMonth = makeDate(year: 2026, month: 3, day: 1)

        let beforeClosingStatements = PlanningLogic.creditCardStatementsDue(
            in: dueMonth,
            accounts: [account],
            records: records,
            occurrences: [],
            referenceDate: makeDate(year: 2026, month: 3, day: 9),
            calendar: calendar
        )
        let beforeSummary = PlanningLogic.dueSummary(
            creditStatements: beforeClosingStatements,
            recurring: [],
            selectedMonth: dueMonth,
            referenceDate: makeDate(year: 2026, month: 3, day: 9),
            calendar: calendar
        )
        XCTAssertEqual(beforeSummary.totalDueMinor, 32_456)

        let afterClosingStatements = PlanningLogic.creditCardStatementsDue(
            in: dueMonth,
            accounts: [account],
            records: records,
            occurrences: [],
            referenceDate: makeDate(year: 2026, month: 3, day: 10),
            calendar: calendar
        )
        let afterSummary = PlanningLogic.dueSummary(
            creditStatements: afterClosingStatements,
            recurring: [],
            selectedMonth: dueMonth,
            referenceDate: makeDate(year: 2026, month: 3, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(afterSummary.totalDueMinor, 32_456)
        XCTAssertEqual(afterSummary.upcomingCount, 0)
    }

    func testBackdatedCreditCardExpenseCreatesStatementBeforeWalletCreatedMonth() {
        let cardWalletID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: UUID(),
            dueDay: 26,
            statementClosingDay: 10,
            openedAt: makeDate(year: 2026, month: 3, day: 5)
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            )
        ]

        let statements = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [],
            statementMonths: [makeDate(year: 2026, month: 2, day: 1)],
            referenceDate: makeDate(year: 2026, month: 3, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(statements.count, 1)
        XCTAssertEqual(statements.first?.amountMinor, 32_456)
        XCTAssertEqual(statements.first?.statementMonth, makeDate(year: 2026, month: 2, day: 1))
        XCTAssertEqual(statements.first?.state, .payable)
    }

    func testPaidCreditCardStatementForExpenseDetectsClosedPaidMonth() {
        let cardWalletID = UUID()
        let paymentTransactionID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: UUID(),
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            )
        ]
        let occurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .creditCard,
            sourceID: cardWalletID,
            selectedMonthKey: "2026-02",
            scheduledDate: makeDate(year: 2026, month: 3, day: 26),
            amountMinorSnapshot: 32_456,
            status: .paid,
            linkedTransactionID: paymentTransactionID
        )

        let paidStatement = PlanningLogic.paidCreditCardStatementForExpense(
            account: account,
            records: records,
            occurrences: [occurrence],
            occurredAt: makeDate(year: 2026, month: 2, day: 20),
            referenceDate: makeDate(year: 2026, month: 3, day: 27),
            calendar: calendar
        )

        XCTAssertEqual(paidStatement?.statementMonth, makeDate(year: 2026, month: 2, day: 1))
        XCTAssertEqual(paidStatement?.amountMinor, 32_456)
        XCTAssertEqual(paidStatement?.state, .paid)
    }

    func testPaidCreditCardStatementFallsBackToLegacyDueMonthOccurrence() {
        let cardWalletID = UUID()
        let paymentTransactionID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: UUID(),
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 23_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            )
        ]
        let legacyOccurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .creditCard,
            sourceID: cardWalletID,
            selectedMonthKey: "2026-03",
            scheduledDate: makeDate(year: 2026, month: 3, day: 26),
            amountMinorSnapshot: 23_456,
            status: .paid,
            linkedTransactionID: paymentTransactionID
        )

        let paidStatement = PlanningLogic.paidCreditCardStatementForExpense(
            account: account,
            records: records,
            occurrences: [legacyOccurrence],
            occurredAt: makeDate(year: 2026, month: 2, day: 20),
            referenceDate: makeDate(year: 2026, month: 3, day: 27),
            calendar: calendar
        )

        XCTAssertEqual(paidStatement?.statementMonth, makeDate(year: 2026, month: 2, day: 1))
        XCTAssertEqual(paidStatement?.amountMinor, 23_456)
        XCTAssertEqual(paidStatement?.state, .paid)
    }

    func testCreditCardStatementIgnoresStalePaidOccurrenceWhenSpendingChanged() {
        let cardWalletID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: UUID(),
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 6_666,
                occurredAt: makeDate(year: 2026, month: 3, day: 15),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            )
        ]
        let staleOccurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .creditCard,
            sourceID: cardWalletID,
            selectedMonthKey: "2026-03",
            scheduledDate: makeDate(year: 2026, month: 4, day: 26),
            amountMinorSnapshot: 2_000,
            status: .paid,
            linkedTransactionID: UUID()
        )

        let statement = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [staleOccurrence],
            statementMonths: [makeDate(year: 2026, month: 3, day: 1)],
            referenceDate: makeDate(year: 2026, month: 4, day: 27),
            calendar: calendar
        ).first

        XCTAssertEqual(statement?.amountMinor, 6_666)
        XCTAssertEqual(statement?.status, .pending)
        XCTAssertEqual(statement?.state, .overdue)
        XCTAssertNil(statement?.linkedTransactionID)
    }

    func testCreditCardStatementIsPaidByPostedTransferAfterClosingEvenWhenLate() {
        let cardWalletID = UUID()
        let paymentWalletID = UUID()
        let paymentTransactionID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: paymentWalletID,
            dueDay: 26,
            statementClosingDay: 10
        )
        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 2, day: 12),
                categoryID: nil,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard
            ),
            makeRecord(
                id: paymentTransactionID,
                primaryKind: .transfer,
                transferSubtype: .internalTransfer,
                amountMinor: 32_456,
                occurredAt: makeDate(year: 2026, month: 4, day: 3),
                categoryID: nil,
                sourceWalletID: paymentWalletID,
                sourceWalletKind: .bank,
                destinationWalletID: cardWalletID,
                destinationWalletKind: .creditCard
            )
        ]

        let statement = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [],
            statementMonths: [makeDate(year: 2026, month: 2, day: 1)],
            referenceDate: makeDate(year: 2026, month: 4, day: 4),
            calendar: calendar
        ).first

        XCTAssertEqual(statement?.status, .paid)
        XCTAssertEqual(statement?.state, .paid)
        XCTAssertEqual(statement?.linkedTransactionID, paymentTransactionID)
    }

    func testCreditCardStatementIgnoresStaleOccurrenceForEmptyStatementMonth() {
        let cardWalletID = UUID()
        let account = makeCreditCardAccount(
            walletID: cardWalletID,
            paymentWalletID: UUID(),
            dueDay: 26,
            statementClosingDay: 10
        )
        let staleOccurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .creditCard,
            sourceID: cardWalletID,
            selectedMonthKey: "2026-02",
            scheduledDate: makeDate(year: 2026, month: 3, day: 26),
            amountMinorSnapshot: 6_000,
            status: .paid,
            linkedTransactionID: UUID()
        )

        let statement = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: [],
            occurrences: [staleOccurrence],
            statementMonths: [makeDate(year: 2026, month: 2, day: 1)],
            referenceDate: makeDate(year: 2026, month: 3, day: 27),
            calendar: calendar
        ).first

        XCTAssertEqual(statement?.amountMinor, 0)
        XCTAssertEqual(statement?.status, .pending)
        XCTAssertEqual(statement?.state, .paid)
        XCTAssertNil(statement?.linkedTransactionID)
    }

    func testBillAmountTotalsByCurrencyIgnoreUnknownAmountsAndNonBillRows() {
        let month = makeDate(year: 2026, month: 5, day: 1)
        let totals = PlanningLogic.recurringBillAmountTotalsByCurrency(
            [
                makeRecurringDueItem(
                    sourceKind: .recurringBill,
                    amountMinor: 1_000,
                    currencyCode: "JPY",
                    dueDate: month
                ),
                makeRecurringDueItem(
                    sourceKind: .recurringBill,
                    amountMinor: nil,
                    currencyCode: "JPY",
                    dueDate: month
                ),
                makeRecurringDueItem(
                    sourceKind: .recurringBill,
                    amountMinor: 0,
                    currencyCode: "JPY",
                    dueDate: month
                ),
                makeRecurringDueItem(
                    sourceKind: .installment,
                    amountMinor: 2_000,
                    currencyCode: "JPY",
                    dueDate: month
                ),
                makeRecurringDueItem(
                    sourceKind: .recurringBill,
                    amountMinor: 500,
                    currencyCode: "VND",
                    dueDate: month
                )
            ]
        )

        XCTAssertEqual(totals, [
            PlanningCurrencyAmountTotalSnapshot(currencyCode: "JPY", amountMinor: 1_000),
            PlanningCurrencyAmountTotalSnapshot(currencyCode: "VND", amountMinor: 500)
        ])
    }

    func testCreditCardAutoPaymentDecisionWaitsForDueDateAndRequiresFunds() {
        let paymentWalletID = UUID()
        let statement = makeCreditCardStatement(
            paymentWalletID: paymentWalletID,
            status: .pending,
            state: .payable
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: statement,
                sourceWalletBalanceMinor: 40_000,
                referenceDate: makeDate(year: 2026, month: 3, day: 25),
                calendar: calendar
            ),
            .notDue
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: statement,
                sourceWalletBalanceMinor: 40_000,
                referenceDate: makeDate(year: 2026, month: 4, day: 2),
                calendar: calendar
            ),
            .notDue
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: makeCreditCardStatement(paymentWalletID: nil, status: .pending, state: .overdue),
                sourceWalletBalanceMinor: nil,
                referenceDate: makeDate(year: 2026, month: 3, day: 26),
                calendar: calendar
            ),
            .missingLinkedWallet
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: statement,
                sourceWalletBalanceMinor: 20_000,
                referenceDate: makeDate(year: 2026, month: 3, day: 26),
                calendar: calendar
            ),
            .insufficientFunds(availableMinor: 20_000, requiredMinor: 32_456)
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: statement,
                sourceWalletBalanceMinor: 32_456,
                referenceDate: makeDate(year: 2026, month: 3, day: 26),
                calendar: calendar
            ),
            .payable
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: makeCreditCardStatement(paymentWalletID: paymentWalletID, status: .paid, state: .paid),
                sourceWalletBalanceMinor: 40_000,
                referenceDate: makeDate(year: 2026, month: 3, day: 26),
                calendar: calendar
            ),
            .alreadyPaid
        )
    }

    func testCreditCardAutoPaymentDecisionRetriesAcrossMonthForFiveDaysAfterDueDate() {
        let paymentWalletID = UUID()
        let statement = makeCreditCardStatement(
            paymentWalletID: paymentWalletID,
            status: .pending,
            state: .overdue,
            dueDate: makeDate(year: 2026, month: 3, day: 30)
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: statement,
                sourceWalletBalanceMinor: 40_000,
                referenceDate: makeDate(year: 2026, month: 4, day: 2),
                calendar: calendar
            ),
            .payable
        )

        XCTAssertEqual(
            PlanningLogic.creditCardAutoPaymentDecision(
                statement: statement,
                sourceWalletBalanceMinor: 40_000,
                referenceDate: makeDate(year: 2026, month: 4, day: 5),
                calendar: calendar
            ),
            .notDue
        )
    }

    func testInstallmentOccurrenceGenerationHonorsFrequencyAndCycleLimit() {
        let selectedMonth = makeDate(year: 2026, month: 5, day: 1)
        let plans = [
            PlanningInstallmentSnapshot(
                id: UUID(),
                name: "MacBook",
                iconSymbolName: "laptopcomputer",
                amountPerCycleMinor: 4_000,
                dueDay: 15,
                totalCycles: 3,
                frequencyMonths: 2,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                createdAt: makeDate(year: 2026, month: 1, day: 20)
            )
        ]

        let july = PlanningLogic.installmentDueItems(
            plans: plans,
            occurrences: [],
            selectedMonth: selectedMonth,
            calendar: calendar
        )
        XCTAssertEqual(july.count, 1)

        let afterCycleLimit = PlanningLogic.installmentDueItems(
            plans: plans,
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 7, day: 1),
            calendar: calendar
        )
        XCTAssertEqual(afterCycleLimit.count, 0)
    }

    func testPayEarlyDraftsMapToTransactions() throws {
        let paymentWallet = UUID()
        let cardWallet = UUID()

        let cardDraft = try PlanningLogic.makePaymentDraft(
            for: PlanningCreditCardDueSnapshot(
                id: UUID(),
                walletID: cardWallet,
                walletName: "SMBC Card",
                network: .visa,
                last4: "1234",
                amountMinor: 8_000,
                availableCreditMinor: 12_000,
                statementMonth: makeDate(year: 2026, month: 3, day: 1),
                dueDate: makeDate(year: 2026, month: 4, day: 20),
                paymentSourceWalletID: paymentWallet,
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        )
        XCTAssertEqual(cardDraft.primaryKind, .transfer)
        XCTAssertEqual(cardDraft.transferSubtype, .internalTransfer)
        XCTAssertEqual(cardDraft.sourceWalletID, paymentWallet)
        XCTAssertEqual(cardDraft.destinationWalletID, cardWallet)

        let statementDraft = try PlanningLogic.makePaymentDraft(
            for: makeCreditCardStatement(
                walletID: cardWallet,
                paymentWalletID: paymentWallet,
                status: .pending,
                state: .payable
            )
        )
        XCTAssertEqual(statementDraft.primaryKind, .transfer)
        XCTAssertEqual(statementDraft.transferSubtype, .internalTransfer)
        XCTAssertEqual(statementDraft.amountMinor, 32_456)
        XCTAssertEqual(statementDraft.sourceWalletID, paymentWallet)
        XCTAssertEqual(statementDraft.destinationWalletID, cardWallet)

        let billDraft = try PlanningLogic.makePaymentDraft(
            for: PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .recurringBill,
                sourceID: UUID(),
                name: "Internet",
                iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
                categorySystemKey: .internet,
                amountMinor: 2_000,
                dueDate: makeDate(year: 2026, month: 4, day: 18),
                frequencyMonths: 1,
                totalCycles: nil,
                paymentWalletID: paymentWallet,
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        )
        XCTAssertEqual(billDraft.primaryKind, .expense)
        XCTAssertEqual(billDraft.categorySystemKey, .internet)

        let installmentDraft = try PlanningLogic.makePaymentDraft(
            for: PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .installment,
                sourceID: UUID(),
                name: "Laptop",
                iconSymbolName: "mistia.plan.installment",
                categorySystemKey: .loanRepayment,
                amountMinor: 6_000,
                dueDate: makeDate(year: 2026, month: 4, day: 22),
                frequencyMonths: 1,
                totalCycles: 6,
                paymentWalletID: paymentWallet,
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        )
        XCTAssertEqual(installmentDraft.categorySystemKey, .loanRepayment)
    }

    private func makeRecord(
        id: UUID = UUID(),
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        amountMinor: Int64,
        occurredAt: Date,
        categoryID: UUID?,
        categoryParentID: UUID? = nil,
        sourceWalletID: UUID = UUID(),
        sourceWalletKind: LedgerWalletKind = .cash,
        destinationWalletID: UUID? = nil,
        destinationWalletKind: LedgerWalletKind? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: .posted,
            title: "Test",
            note: nil,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletKind: destinationWalletKind,
            categoryID: categoryID,
            categoryParentID: categoryParentID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }

    private func makeRecurringDueItem(
        sourceKind: PlanningDueSourceKind,
        amountMinor: Int64?,
        currencyCode: String,
        dueDate: Date
    ) -> PlanningRecurringDueSnapshot {
        PlanningRecurringDueSnapshot(
            id: UUID(),
            sourceKind: sourceKind,
            sourceID: UUID(),
            name: "Due",
            iconSymbolName: "doc.text.fill",
            categorySystemKey: sourceKind == .recurringBill ? .billing : .loanRepayment,
            amountMinor: amountMinor,
            dueDate: dueDate,
            frequencyMonths: 1,
            totalCycles: sourceKind == .installment ? 6 : nil,
            paymentWalletID: nil,
            currencyCode: currencyCode,
            status: .pending,
            linkedTransactionID: nil
        )
    }

    private func makeBudget(
        id: UUID = UUID(),
        categoryID: UUID,
        categoryName: String,
        limitMinor: Int64,
        monthAnchor: Date,
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil,
        categoryParentIconSymbolName: String? = nil,
        categoryParentColorHex: String? = nil,
        categoryIsParent: Bool = false
    ) -> BudgetPlanSnapshot {
        BudgetPlanSnapshot(
            id: id,
            categoryID: categoryID,
            categoryName: categoryName,
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

    private func makeCreditCardAccount(
        walletID: UUID,
        paymentWalletID: UUID,
        dueDay: Int,
        statementClosingDay: Int,
        openedAt: Date? = nil
    ) -> PlanningCreditCardAccountSnapshot {
        PlanningCreditCardAccountSnapshot(
            id: walletID,
            walletID: walletID,
            walletName: "SMBC Card",
            issuerName: "SMBC",
            network: .visa,
            last4: "1234",
            dueDay: dueDay,
            statementClosingDay: statementClosingDay,
            paymentSourceWalletID: paymentWalletID,
            paymentSourceWalletName: "Main",
            currencyCode: "JPY",
            currentDebtMinor: 0,
            availableCreditMinor: 100_000,
            openedAt: openedAt ?? makeDate(year: 2026, month: 1, day: 1)
        )
    }

    private func makeCreditCardStatement(
        walletID: UUID = UUID(),
        paymentWalletID: UUID?,
        status: PlanningDueOccurrenceStatus,
        state: PlanningCreditCardStatementState,
        dueDate: Date? = nil
    ) -> PlanningCreditCardStatementSnapshot {
        PlanningCreditCardStatementSnapshot(
            id: "\(walletID.uuidString.lowercased())-2026-02",
            walletID: walletID,
            walletName: "SMBC Card",
            issuerName: "SMBC",
            network: .visa,
            last4: "1234",
            statementMonth: makeDate(year: 2026, month: 2, day: 1),
            closingDate: makeDate(year: 2026, month: 3, day: 10),
            dueDate: dueDate ?? makeDate(year: 2026, month: 3, day: 26),
            amountMinor: 32_456,
            availableCreditMinor: 100_000,
            paymentSourceWalletID: paymentWalletID,
            paymentSourceWalletName: paymentWalletID == nil ? nil : "Main",
            currencyCode: "JPY",
            status: status,
            linkedTransactionID: nil,
            state: state
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        (try? makeDate(year: year, month: month, day: day, calendar: calendar)) ?? .distantPast
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
