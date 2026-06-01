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

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? .distantPast
    }
}
