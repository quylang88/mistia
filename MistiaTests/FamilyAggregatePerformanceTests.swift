import Foundation
import XCTest
@testable import Mistia

final class FamilyAggregatePerformanceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testAggregateSummaryKeepsVisibleTotalsAndCreatorSpending() {
        let memberA = UUID()
        let memberB = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 1),
            end: makeDate(year: 2026, month: 5, day: 1)
        )

        let summary = FamilyLogic.aggregateSummary(
            wallets: [
                FamilyAggregateWalletSnapshot(
                    ownerUserID: memberA,
                    kind: .bank,
                    balanceMinor: 120_000,
                    debtMinor: 0,
                    name: "Main"
                ),
                FamilyAggregateWalletSnapshot(
                    ownerUserID: memberB,
                    kind: .creditCard,
                    balanceMinor: 0,
                    debtMinor: 30_000,
                    name: "Card"
                )
            ],
            transactions: [
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberA,
                    createdByUserID: memberA,
                    categoryName: "Food",
                    occurredAt: makeDate(year: 2026, month: 4, day: 13),
                    kind: .expense,
                    amountMinor: 20_000
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberA,
                    createdByUserID: memberB,
                    categoryName: "Shopping",
                    occurredAt: makeDate(year: 2026, month: 4, day: 14),
                    kind: .expense,
                    amountMinor: 15_000
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberB,
                    categoryName: "Salary",
                    occurredAt: makeDate(year: 2026, month: 4, day: 15),
                    kind: .income,
                    amountMinor: 50_000
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberA,
                    categoryName: "Card payment",
                    occurredAt: makeDate(year: 2026, month: 4, day: 16),
                    kind: .expense,
                    amountMinor: 99_000,
                    isCreditCardPayment: true
                )
            ],
            selectedInterval: interval,
            visibleMemberIDs: [memberA, memberB],
            memberNames: [memberA: "A", memberB: "B"],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.totalAssetsMinor, 120_000)
        XCTAssertEqual(summary.totalDebtMinor, 30_000)
        XCTAssertEqual(summary.spendableMinor, 90_000)
        XCTAssertEqual(summary.expenseByCategory.map(\.valueMinor).sorted(), [15_000, 20_000])
        XCTAssertEqual(summary.spendingByMember.map(\.amountMinor), [20_000, 15_000])
        XCTAssertEqual(summary.incomeByMember.map(\.amountMinor), [50_000])
        XCTAssertEqual(summary.assetTrend.last?.valueMinor, 40_000)
    }

    func testNotificationResourceIndexReturnsResourcesByID() {
        let walletID = UUID()
        let categoryID = UUID()
        let billID = UUID()
        let wallet = LedgerWallet(
            id: walletID,
            name: "Main Wallet",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#3366FF"
        )
        let category = TransactionCategory(
            id: categoryID,
            name: "Utilities",
            kind: .expense,
            iconSymbolName: "bolt.fill",
            iconColorHex: "#FFAA00"
        )
        let bill = RecurringBillPlan(
            id: billID,
            name: "Internet",
            iconSymbolName: "wifi",
            category: category,
            dueDay: 15
        )
        let index = NotificationCenterResourceIndex(
            wallets: [wallet],
            categories: [category],
            bills: [bill]
        )

        XCTAssertEqual(index.wallet(id: walletID, resourceType: .wallet)?.name, "Main Wallet")
        XCTAssertEqual(index.wallet(id: walletID, resourceType: .card)?.name, "Main Wallet")
        XCTAssertNil(index.wallet(id: walletID, resourceType: .category))
        XCTAssertEqual(index.category(id: categoryID, resourceType: .category)?.name, "Utilities")
        XCTAssertNil(index.category(id: categoryID, resourceType: .wallet))
        XCTAssertEqual(index.bill(id: billID, resourceType: .bill)?.name, "Internet")
        XCTAssertNil(index.bill(id: billID, resourceType: .card))
    }

    func testNotificationMetadataIndexDecodesMetadataOncePerRow() {
        let stringRow = AppNotificationRecord(
            key: "string-metadata",
            title: "Family",
            body: "Family activity",
            kind: .familyActivity,
            source: .family,
            metadataJSON: #"{"action":"created","wallet_name":"Cash"}"#
        )
        let mixedRow = AppNotificationRecord(
            key: "mixed-metadata",
            title: "Family",
            body: "Family activity",
            kind: .familyActivity,
            source: .family,
            metadataJSON: #"{"wallet_name":"Savings","amount_minor":1200}"#
        )
        let invalidRow = AppNotificationRecord(
            key: "invalid-metadata",
            title: "Family",
            body: "Family activity",
            kind: .familyActivity,
            source: .family,
            metadataJSON: #"{"wallet_name":"Broken""#
        )

        let index = NotificationCenterMetadataIndex(rows: [stringRow, mixedRow, invalidRow])

        XCTAssertEqual(index.stringMetadata(for: stringRow)?["action"], "created")
        XCTAssertEqual(index.objectMetadata(for: stringRow)?["wallet_name"] as? String, "Cash")
        XCTAssertNil(index.stringMetadata(for: mixedRow))
        XCTAssertEqual(index.objectMetadata(for: mixedRow)?["wallet_name"] as? String, "Savings")
        XCTAssertNil(index.stringMetadata(for: invalidRow))
        XCTAssertNil(index.objectMetadata(for: invalidRow))
    }

    func testBudgetBranchRowsUseFamilySpendingPerBudgetPlan() {
        let month = makeDate(year: 2026, month: 6, day: 1)
        let referenceDate = makeDate(year: 2026, month: 6, day: 15)
        let foodCategoryID = UUID()
        let commuteCategoryID = UUID()
        let livingBranchID = UUID()

        let rows = PlanningLogic.budgetBranchRows(
            plans: [
                makeBudgetPlan(
                    categoryID: foodCategoryID,
                    categoryName: "Food",
                    parentID: livingBranchID,
                    parentName: "Living",
                    limitMinor: 100_000,
                    monthAnchor: month,
                    includesFamilySpending: false
                ),
                makeBudgetPlan(
                    categoryID: commuteCategoryID,
                    categoryName: "Commute",
                    parentID: livingBranchID,
                    parentName: "Living",
                    limitMinor: 80_000,
                    monthAnchor: month,
                    includesFamilySpending: true
                )
            ],
            records: [
                makeExpenseRecord(
                    amountMinor: 42_000,
                    occurredAt: makeDate(year: 2026, month: 6, day: 4),
                    categoryID: foodCategoryID,
                    parentID: livingBranchID
                )
            ],
            selectedMonth: month,
            referenceDate: referenceDate,
            calendar: calendar,
            familyTransactions: [
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: UUID(),
                    categoryName: "Commute",
                    categoryParentName: "Living",
                    occurredAt: makeDate(year: 2026, month: 6, day: 6),
                    kind: .expense,
                    amountMinor: 31_000,
                    currencyCode: "JPY"
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: UUID(),
                    categoryName: "Commute",
                    categoryParentName: "Living",
                    occurredAt: makeDate(year: 2026, month: 6, day: 7),
                    kind: .expense,
                    amountMinor: 29_000,
                    currencyCode: "JPY"
                )
            ],
            familySpendingAvailable: true
        )

        guard let branchRow = rows.first else {
            XCTFail("Expected a budget branch row")
            return
        }
        guard let foodRow = branchRow.childRows.first(where: { $0.categoryID == foodCategoryID }) else {
            XCTFail("Expected Food child row")
            return
        }
        guard let commuteRow = branchRow.childRows.first(where: { $0.categoryID == commuteCategoryID }) else {
            XCTFail("Expected Commute child row")
            return
        }

        XCTAssertEqual(foodRow.spentMinor, 42_000)
        XCTAssertEqual(commuteRow.spentMinor, 60_000)
        XCTAssertEqual(branchRow.spentMinor, 102_000)
    }

    func testBudgetBranchRowsMatchPersonalSpendingByCategoryNameWhenIDsDiffer() {
        let month = makeDate(year: 2026, month: 6, day: 1)
        let referenceDate = makeDate(year: 2026, month: 6, day: 15)
        let budgetCategoryID = UUID()
        let transactionCategoryID = UUID()
        let parentID = UUID()

        let rows = PlanningLogic.budgetBranchRows(
            plans: [
                makeBudgetPlan(
                    categoryID: budgetCategoryID,
                    categoryName: "Food",
                    parentID: parentID,
                    parentName: "Living",
                    limitMinor: 100_000,
                    monthAnchor: month,
                    includesFamilySpending: false
                )
            ],
            records: [
                makeExpenseRecord(
                    amountMinor: 42_000,
                    occurredAt: makeDate(year: 2026, month: 6, day: 4),
                    categoryID: transactionCategoryID,
                    categoryName: " food ",
                    parentID: parentID,
                    parentName: "Living"
                )
            ],
            selectedMonth: month,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(rows.first?.spentMinor, 42_000)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? .distantPast
    }

    private func makeBudgetPlan(
        categoryID: UUID,
        categoryName: String,
        parentID: UUID,
        parentName: String,
        limitMinor: Int64,
        monthAnchor: Date,
        includesFamilySpending: Bool
    ) -> BudgetPlanSnapshot {
        BudgetPlanSnapshot(
            id: UUID(),
            categoryID: categoryID,
            categoryName: categoryName,
            categoryIconSymbolName: "circle.fill",
            categoryColorHex: "#3366FF",
            limitMinor: limitMinor,
            rolloverEnabled: false,
            currencyCode: "JPY",
            monthAnchor: monthAnchor,
            categoryParentID: parentID,
            categoryParentName: parentName,
            categoryParentIconSymbolName: "square.fill",
            categoryParentColorHex: "#111111",
            includesFamilySpending: includesFamilySpending
        )
    }

    private func makeExpenseRecord(
        amountMinor: Int64,
        occurredAt: Date,
        categoryID: UUID,
        categoryName: String? = nil,
        parentID: UUID,
        parentName: String? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Expense",
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            categoryName: categoryName,
            categoryParentID: parentID,
            categoryParentName: parentName,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }
}
