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
        XCTAssertEqual(rows.first?.tone, .critical)
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

    func testDueSummaryUsesSevenDayWindowForCurrentMonthAndAllPendingForOtherMonths() {
        let currentMonth = makeDate(year: 2026, month: 4, day: 1)
        let referenceDate = makeDate(year: 2026, month: 4, day: 10)

        let creditCards = [
            PlanningCreditCardDueSnapshot(
                id: UUID(),
                walletID: UUID(),
                walletName: "SMBC Card",
                network: .visa,
                last4: "1234",
                amountMinor: 12_000,
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
                iconSymbolName: "bolt.fill",
                amountMinor: 3_000,
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
                iconSymbolName: "iphone",
                amountMinor: 5_000,
                dueDate: makeDate(year: 2026, month: 4, day: 25),
                frequencyMonths: 1,
                totalCycles: 12,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                status: .pending,
                linkedTransactionID: nil
            )
        ]

        let currentSummary = PlanningLogic.dueSummary(
            creditCards: creditCards,
            recurring: recurring,
            selectedMonth: currentMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(currentSummary.upcomingCount, 1)
        XCTAssertEqual(currentSummary.totalDueMinor, 12_000)
        XCTAssertEqual(currentSummary.overdueCount, 1)

        let futureSummary = PlanningLogic.dueSummary(
            creditCards: creditCards,
            recurring: recurring,
            selectedMonth: makeDate(year: 2026, month: 5, day: 1),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(futureSummary.upcomingCount, 3)
        XCTAssertEqual(futureSummary.totalDueMinor, 20_000)
        XCTAssertEqual(futureSummary.overdueCount, 0)
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

        let billDraft = try PlanningLogic.makePaymentDraft(
            for: PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .recurringBill,
                sourceID: UUID(),
                name: "Internet",
                iconSymbolName: "wifi",
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
        XCTAssertEqual(billDraft.categorySystemKey, .billing)

        let installmentDraft = try PlanningLogic.makePaymentDraft(
            for: PlanningRecurringDueSnapshot(
                id: UUID(),
                sourceKind: .installment,
                sourceID: UUID(),
                name: "Laptop",
                iconSymbolName: "laptopcomputer",
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
        categoryID: UUID?
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
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
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
