import XCTest
@testable import MistiaCoreLogic

final class PlanningLogicTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

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

    func testBudgetBranchRowsRollUpChildBudgetsAndKeepParentModeSeparate() {
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
        XCTAssertEqual(livingRow.mode, .child)
        XCTAssertEqual(livingRow.spentMinor, 13_000)
        XCTAssertEqual(livingRow.limitMinor, 30_000)
        XCTAssertEqual(livingRow.childRows.map(\.name), ["Ăn uống", "Nhà ở"])

        guard let travelRow = rows.first(where: { $0.parentCategoryID == travelParent }) else {
            XCTFail("Expected a travel branch row")
            return
        }
        XCTAssertEqual(travelRow.mode, .parent)
        XCTAssertEqual(travelRow.spentMinor, 3_000)
        XCTAssertEqual(travelRow.limitMinor, 15_000)
        XCTAssertEqual(travelRow.childRows.count, 0)

        let summary = PlanningLogic.budgetSummary(from: rows)
        XCTAssertEqual(summary.totalBudgetMinor, 45_000)
        XCTAssertEqual(summary.spentMinor, 16_000)
        XCTAssertEqual(summary.remainingMinor, 29_000)
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

    func testSelectedDueMonthSummaryCountsOnlyClosedCreditStatement() {
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
        XCTAssertEqual(beforeSummary.totalDueMinor, 0)

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
        primaryKind: TransactionPrimaryKind,
        amountMinor: Int64,
        occurredAt: Date,
        categoryID: UUID?,
        categoryParentID: UUID? = nil,
        sourceWalletID: UUID = UUID(),
        sourceWalletKind: LedgerWalletKind = .cash
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
            categoryParentID: categoryParentID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }

    private func makeBudget(
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
            id: UUID(),
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
        state: PlanningCreditCardStatementState
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
            dueDate: makeDate(year: 2026, month: 3, day: 26),
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
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? .distantPast
    }
}
