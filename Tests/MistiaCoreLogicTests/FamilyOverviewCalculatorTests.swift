import XCTest
@testable import MistiaCoreLogic

final class FamilyOverviewCalculatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testComputeAggregatesFamilyOverviewFromValueSnapshots() {
        let ownerID = UUID()
        let memberID = UUID()
        let walletID = UUID()
        let categoryID = UUID()
        let month = makeDate(year: 2026, month: 5, day: 1)
        let transactionDate = makeDate(year: 2026, month: 5, day: 12)
        let wallet = FamilyOverviewWalletInputSnapshot(
            id: walletID,
            ownerUserID: ownerID,
            name: "Cash",
            kind: .cash,
            openingBalanceMinor: 100_000,
            creditCardProfile: nil,
            currencyCode: "JPY",
            sortOrder: 0,
            createdAt: makeDate(year: 2026, month: 1, day: 1)
        )
        let expenseRecord = TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Lunch",
            note: nil,
            amountMinor: 12_000,
            sourceCurrencyCode: "JPY",
            isArchived: false,
            occurredAt: transactionDate,
            createdAt: transactionDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
        let expenseOverview = OverviewTransactionSnapshot(
            id: expenseRecord.id,
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Lunch",
            note: nil,
            amountMinor: 12_000,
            sourceCurrencyCode: "JPY",
            occurredAt: transactionDate,
            createdAt: transactionDate,
            sourceWalletID: walletID,
            sourceWalletName: "Cash",
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletName: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            categoryName: "Food",
            categoryIconSymbolName: "fork.knife",
            categoryColorHex: "#FFAA00",
            categoryParentID: nil,
            categoryParentName: nil,
            categoryParentIconSymbolName: nil,
            categoryParentColorHex: nil,
            counterpartyName: nil,
            isArchived: false
        )
        let transaction = FamilyOverviewTransactionInputSnapshot(
            record: expenseRecord,
            overview: expenseOverview,
            aggregate: FamilyAggregateTransactionSnapshot(
                ownerUserID: ownerID,
                createdByUserID: memberID,
                categoryName: "Food",
                occurredAt: transactionDate,
                kind: .expense,
                amountMinor: 12_000,
                currencyCode: "JPY"
            )
        )
        let budget = FamilyBudgetPlanSnapshot(
            id: UUID(),
            ownerUserID: ownerID,
            categoryName: "Food",
            iconSymbolName: "fork.knife",
            colorHex: "#FFAA00",
            limitMinor: 20_000,
            currencyCode: "JPY",
            monthAnchor: month
        )

        let result = FamilyOverviewCalculator.compute(
            input: FamilyOverviewCalculationInput(
                now: makeDate(year: 2026, month: 5, day: 15),
                currentMonth: month,
                selectedBillMonth: month,
                selectedInterval: DateInterval(
                    start: month,
                    end: makeDate(year: 2026, month: 6, day: 1)
                ),
                timeframeTitle: "Tháng",
                familyMemberUserIDs: [ownerID, memberID],
                memberNames: [
                    ownerID: "Owner",
                    memberID: "Member"
                ],
                memberOrder: [ownerID, memberID],
                familyOwnerUserID: ownerID,
                budgetManagerUserID: nil,
                goalManagerUserID: nil,
                reportingCurrencyCode: "JPY",
                exchangeRates: [],
                calendar: calendar,
                wallets: [wallet],
                transactions: [transaction],
                budgets: [budget],
                goals: [],
                bills: [],
                installments: [],
                occurrences: []
            )
        )

        XCTAssertEqual(result.walletRows.first?.currentBalanceMinor, 88_000)
        XCTAssertEqual(result.summary.totalAssetsMinor, 88_000)
        XCTAssertEqual(result.summary.spendingByMember.first?.amountMinor, 12_000)
        XCTAssertEqual(result.categorySpendingSnapshot.totalExpenseMinor, 12_000)
        XCTAssertEqual(result.budgetRows.first?.spentMinor, 12_000)
        XCTAssertEqual(result.monthlySpendable.displayMinor, 88_000)
    }

    func testComputeGroupsMonthlyBillsByCategoryWithinCurrencyAndOmitsUnknownAmounts() {
        let ownerID = UUID()
        let month = makeDate(year: 2026, month: 5, day: 1)
        let jpyInternetBillID = UUID()
        let jpyInternetSecondBillID = UUID()
        let vndInternetBillID = UUID()

        let result = FamilyOverviewCalculator.compute(
            input: FamilyOverviewCalculationInput(
                now: makeDate(year: 2026, month: 5, day: 15),
                currentMonth: month,
                selectedBillMonth: month,
                selectedInterval: DateInterval(
                    start: month,
                    end: makeDate(year: 2026, month: 6, day: 1)
                ),
                timeframeTitle: "Tháng",
                familyMemberUserIDs: [ownerID],
                memberNames: [ownerID: "Owner"],
                memberOrder: [ownerID],
                familyOwnerUserID: ownerID,
                budgetManagerUserID: nil,
                goalManagerUserID: nil,
                reportingCurrencyCode: "JPY",
                exchangeRates: [],
                calendar: calendar,
                wallets: [],
                transactions: [],
                budgets: [],
                goals: [],
                bills: [
                    makeBill(
                        id: jpyInternetBillID,
                        name: "Home internet",
                        categorySystemKey: .internet,
                        categoryName: "Internet",
                        amountMinor: 3_000,
                        currencyCode: "JPY",
                        month: month
                    ),
                    makeBill(
                        id: jpyInternetSecondBillID,
                        name: "Mobile internet",
                        categorySystemKey: .internet,
                        categoryName: "Internet",
                        amountMinor: 4_000,
                        currencyCode: "JPY",
                        month: month
                    ),
                    makeBill(
                        id: vndInternetBillID,
                        name: "Cloud internet",
                        categorySystemKey: .internet,
                        categoryName: "Internet",
                        amountMinor: 25,
                        currencyCode: "VND",
                        month: month
                    ),
                    makeBill(
                        name: "Unknown amount",
                        categorySystemKey: .internet,
                        categoryName: "Internet",
                        amountMinor: nil,
                        currencyCode: "JPY",
                        month: month
                    ),
                    makeBill(
                        name: "Free trial",
                        categorySystemKey: .internet,
                        categoryName: "Internet",
                        amountMinor: 0,
                        currencyCode: "JPY",
                        month: month
                    )
                ],
                installments: [],
                occurrences: []
            )
        )

        XCTAssertEqual(result.monthlyBillRows.count, 2)
        XCTAssertEqual(result.monthlyBillRows.first(where: { $0.currencyCode == "JPY" })?.amountMinor, 7_000)
        XCTAssertEqual(result.monthlyBillRows.first(where: { $0.currencyCode == "JPY" })?.sourceCount, 2)
        XCTAssertEqual(result.monthlyBillRows.first(where: { $0.currencyCode == "VND" })?.amountMinor, 25)
        XCTAssertEqual(result.monthlyBillTotalsByCurrency, [
            FamilyMonthlyBillTotalSnapshot(currencyCode: "JPY", amountMinor: 7_000),
            FamilyMonthlyBillTotalSnapshot(currencyCode: "VND", amountMinor: 25)
        ])
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        )
        return components.date!
    }

    private func makeBill(
        id: UUID = UUID(),
        name: String,
        categorySystemKey: MistiaSystemCategoryKey?,
        categoryName: String?,
        amountMinor: Int64?,
        currencyCode: String,
        month: Date
    ) -> PlanningBillSnapshot {
        PlanningBillSnapshot(
            id: id,
            name: name,
            iconSymbolName: categorySystemKey?.iconSymbolName ?? "doc.text.fill",
            categorySystemKey: categorySystemKey,
            categoryName: categoryName,
            categoryIconSymbolName: categorySystemKey?.iconSymbolName,
            categoryColorHex: categorySystemKey?.iconColorHex,
            amountMinor: amountMinor,
            dueDay: 12,
            frequencyMonths: 1,
            paymentWalletID: nil,
            currencyCode: currencyCode,
            createdAt: month,
            firstScheduledMonth: month
        )
    }
}
