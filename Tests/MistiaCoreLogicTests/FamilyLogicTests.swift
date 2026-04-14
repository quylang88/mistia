import XCTest
@testable import MistiaCoreLogic

final class FamilyLogicTests: XCTestCase {
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

    func testAggregateSummaryUsesVisibleMembersAndSeparatesCreditCardDebt() {
        let memberA = UUID()
        let memberB = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 1),
            end: makeDate(year: 2026, month: 5, day: 1)
        )

        let summary = FamilyLogic.aggregateSummary(
            wallets: [
                FamilyAggregateWalletSnapshot(ownerUserID: memberA, kind: .bank, balanceMinor: 120_000, debtMinor: 0),
                FamilyAggregateWalletSnapshot(ownerUserID: memberB, kind: .cash, balanceMinor: 40_000, debtMinor: 0),
                FamilyAggregateWalletSnapshot(ownerUserID: memberB, kind: .creditCard, balanceMinor: 0, debtMinor: 30_000)
            ],
            transactions: [],
            selectedInterval: interval,
            visibleMemberIDs: [memberA, memberB],
            memberNames: [memberA: "A", memberB: "B"],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.totalAssetsMinor, 160_000)
        XCTAssertEqual(summary.totalDebtMinor, 30_000)
        XCTAssertEqual(summary.spendableMinor, 130_000)
    }

    func testAggregateSummaryCanScopeToSingleMember() {
        let memberA = UUID()
        let memberB = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 1),
            end: makeDate(year: 2026, month: 5, day: 1)
        )

        let summary = FamilyLogic.aggregateSummary(
            wallets: [
                FamilyAggregateWalletSnapshot(ownerUserID: memberA, kind: .bank, balanceMinor: 120_000, debtMinor: 0),
                FamilyAggregateWalletSnapshot(ownerUserID: memberB, kind: .cash, balanceMinor: 40_000, debtMinor: 0),
                FamilyAggregateWalletSnapshot(ownerUserID: memberB, kind: .creditCard, balanceMinor: 0, debtMinor: 30_000)
            ],
            transactions: [],
            selectedInterval: interval,
            visibleMemberIDs: [memberA],
            memberNames: [memberA: "A", memberB: "B"],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.totalAssetsMinor, 120_000)
        XCTAssertEqual(summary.totalDebtMinor, 0)
        XCTAssertEqual(summary.spendableMinor, 120_000)
    }

    func testAggregateSummaryBuildsMemberComparisonFromVisibleTransactions() {
        let memberA = UUID()
        let memberB = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 1),
            end: makeDate(year: 2026, month: 5, day: 1)
        )

        let summary = FamilyLogic.aggregateSummary(
            wallets: [],
            transactions: [
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberA,
                    categoryName: "Food",
                    occurredAt: makeDate(year: 2026, month: 4, day: 3),
                    kind: .expense,
                    amountMinor: 20_000
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberB,
                    categoryName: "Salary",
                    occurredAt: makeDate(year: 2026, month: 4, day: 5),
                    kind: .income,
                    amountMinor: 50_000
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberB,
                    categoryName: "Shopping",
                    occurredAt: makeDate(year: 2026, month: 4, day: 8),
                    kind: .expense,
                    amountMinor: 35_000
                )
            ],
            selectedInterval: interval,
            visibleMemberIDs: [memberA, memberB],
            memberNames: [memberA: "An", memberB: "Binh"],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.spendingByMember.map(\.name), ["Binh", "An"])
        XCTAssertEqual(summary.spendingByMember.map(\.amountMinor), [35_000, 20_000])
        XCTAssertEqual(summary.incomeByMember.map(\.name), ["Binh"])
        XCTAssertEqual(summary.incomeByMember.map(\.amountMinor), [50_000])
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? .distantPast
    }
}
