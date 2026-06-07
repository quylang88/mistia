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
                selectedMonth: month,
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
                selectedMonth: month,
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

    func testComputeUsesSelectedMonthInsteadOfCurrentMonthForMonthlyFamilyData() {
        let ownerID = UUID()
        let walletID = UUID()
        let categoryID = UUID()
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)
        let nextMonth = makeDate(year: 2026, month: 5, day: 1)
        let selectedMonthTransactionDate = makeDate(year: 2026, month: 4, day: 12)
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
            title: "Groceries",
            note: nil,
            amountMinor: 10_000,
            sourceCurrencyCode: "JPY",
            isArchived: false,
            occurredAt: selectedMonthTransactionDate,
            createdAt: selectedMonthTransactionDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
        let transaction = FamilyOverviewTransactionInputSnapshot(
            record: expenseRecord,
            overview: OverviewTransactionSnapshot(
                id: expenseRecord.id,
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                entryStatus: .posted,
                title: "Groceries",
                note: nil,
                amountMinor: 10_000,
                sourceCurrencyCode: "JPY",
                occurredAt: selectedMonthTransactionDate,
                createdAt: selectedMonthTransactionDate,
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
            ),
            aggregate: FamilyAggregateTransactionSnapshot(
                ownerUserID: ownerID,
                createdByUserID: ownerID,
                categoryName: "Food",
                occurredAt: selectedMonthTransactionDate,
                kind: .expense,
                amountMinor: 10_000,
                currencyCode: "JPY"
            )
        )
        let budget = FamilyBudgetPlanSnapshot(
            id: UUID(),
            ownerUserID: ownerID,
            categoryName: "Food",
            iconSymbolName: "fork.knife",
            colorHex: "#FFAA00",
            limitMinor: 15_000,
            currencyCode: "JPY",
            monthAnchor: selectedMonth
        )
        let bill = makeBill(
            name: "Selected month utility",
            categorySystemKey: .electricity,
            categoryName: "Electricity",
            amountMinor: 20_000,
            currencyCode: "JPY",
            month: selectedMonth,
            scheduleKind: .oneTime,
            paymentStartDate: selectedMonthTransactionDate
        )

        let result = FamilyOverviewCalculator.compute(
            input: FamilyOverviewCalculationInput(
                now: makeDate(year: 2026, month: 5, day: 15),
                selectedMonth: selectedMonth,
                selectedInterval: DateInterval(
                    start: selectedMonth,
                    end: nextMonth
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
                wallets: [wallet],
                transactions: [transaction],
                budgets: [budget],
                goals: [],
                bills: [bill],
                installments: [],
                occurrences: []
            )
        )

        XCTAssertEqual(result.categorySpendingSnapshot.totalExpenseMinor, 10_000)
        XCTAssertEqual(result.budgetRows.map(\.name), ["Food"])
        XCTAssertEqual(result.monthlyBillRows.first?.amountMinor, 20_000)
        XCTAssertEqual(result.monthlySpendable.displayMinor, 70_000)
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
        month: Date,
        scheduleKind: PlanningBillScheduleKind = .recurring,
        paymentStartDate: Date? = nil
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
            scheduleKind: scheduleKind,
            paymentStartDate: paymentStartDate,
            firstScheduledMonth: month
        )
    }

    func testComputeIncludesPaidLabelForBillsAndLimitsCreditCardUpcomingWindow() {
        let ownerID = UUID()
        let month = makeDate(year: 2026, month: 4, day: 1) // Selected month is April
        let monthInterval = calendar.dateInterval(of: .month, for: month)!
        let now = makeDate(year: 2026, month: 5, day: 10) // Now is May 10th
        let transactionDate = makeDate(year: 2026, month: 4, day: 10)
        
        // 1. Paid Bill
        let billID = UUID()
        let bill = PlanningBillSnapshot(
            id: billID,
            name: "Paid Utility",
            iconSymbolName: "bolt",
            categorySystemKey: .billing,
            categoryName: "Utilities",
            categoryIconSymbolName: "bolt",
            categoryColorHex: "#0000FF",
            amountMinor: 5000,
            dueDay: 15,
            frequencyMonths: 1,
            paymentWalletID: nil,
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 1, day: 1),
            scheduleKind: .recurring,
            paymentStartDate: makeDate(year: 2026, month: 4, day: 1),
            firstScheduledMonth: month
        )
        let paidOccurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .recurringBill,
            sourceID: billID,
            selectedMonthKey: PlanningLogic.monthKey(for: month, calendar: calendar),
            scheduledDate: makeDate(year: 2026, month: 4, day: 15),
            amountMinorSnapshot: 5000,
            status: .paid,
            linkedTransactionID: UUID()
        )
        
        // 2. Credit Card - Near Due (5 days away) -> should be upcoming
        let nearCardID = UUID()
        let nearCard = FamilyOverviewWalletInputSnapshot(
            id: nearCardID,
            ownerUserID: ownerID,
            name: "Near Card",
            kind: .creditCard,
            openingBalanceMinor: 0,
            creditCardProfile: FamilyOverviewCreditCardProfileSnapshot(
                issuerName: "Bank A",
                network: .visa,
                last4: "1234",
                creditLimitMinor: 100_000,
                statementClosingDay: 5,
                paymentDueDay: 15,
                paymentSourceWalletID: nil,
                paymentSourceWalletName: nil,
                autoPayEnabled: false
            ),
            currencyCode: "JPY",
            sortOrder: 0,
            createdAt: makeDate(year: 2026, month: 1, day: 1)
        )
        let nearTransaction = FamilyOverviewTransactionInputSnapshot(
            record: TransactionRecordSnapshot(
                id: UUID(),
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                entryStatus: .posted,
                title: "Spend",
                note: nil,
                amountMinor: 10_000,
                sourceCurrencyCode: "JPY",
                isArchived: false,
                occurredAt: transactionDate,
                createdAt: transactionDate,
                sourceWalletID: nearCardID,
                sourceWalletKind: .creditCard,
                destinationWalletID: nil,
                destinationWalletKind: nil,
                categoryID: UUID(),
                counterpartyName: nil,
                normalizedCounterpartyKey: nil
            ),
            overview: OverviewTransactionSnapshot(
                id: UUID(),
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                entryStatus: .posted,
                title: "Spend",
                note: nil,
                amountMinor: 10_000,
                sourceCurrencyCode: "JPY",
                occurredAt: transactionDate,
                createdAt: transactionDate,
                sourceWalletID: nearCardID,
                sourceWalletName: "Near Card",
                sourceWalletKind: .creditCard,
                destinationWalletID: nil,
                destinationWalletName: nil,
                destinationWalletKind: nil,
                categoryID: UUID(),
                categoryName: "Shopping",
                categoryIconSymbolName: "cart",
                categoryColorHex: "#FF00FF",
                categoryParentID: nil,
                categoryParentName: nil,
                categoryParentIconSymbolName: nil,
                categoryParentColorHex: nil,
                counterpartyName: nil,
                isArchived: false
            ),
            aggregate: FamilyAggregateTransactionSnapshot(
                ownerUserID: ownerID,
                createdByUserID: ownerID,
                categoryName: "Shopping",
                occurredAt: transactionDate,
                kind: .expense,
                amountMinor: 10_000,
                currencyCode: "JPY"
            )
        )
        
        // 3. Credit Card - Far Due (15 days away) -> should NOT be upcoming
        let farCardID = UUID()
        let farCard = FamilyOverviewWalletInputSnapshot(
            id: farCardID,
            ownerUserID: ownerID,
            name: "Far Card",
            kind: .creditCard,
            openingBalanceMinor: 0,
            creditCardProfile: FamilyOverviewCreditCardProfileSnapshot(
                issuerName: "Bank B",
                network: .mastercard,
                last4: "5678",
                creditLimitMinor: 100_000,
                statementClosingDay: 5,
                paymentDueDay: 25,
                paymentSourceWalletID: nil,
                paymentSourceWalletName: nil,
                autoPayEnabled: false
            ),
            currencyCode: "JPY",
            sortOrder: 1,
            createdAt: makeDate(year: 2026, month: 1, day: 1)
        )
        let farTransaction = FamilyOverviewTransactionInputSnapshot(
            record: TransactionRecordSnapshot(
                id: UUID(),
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                entryStatus: .posted,
                title: "Spend",
                note: nil,
                amountMinor: 10_000,
                sourceCurrencyCode: "JPY",
                isArchived: false,
                occurredAt: transactionDate,
                createdAt: transactionDate,
                sourceWalletID: farCardID,
                sourceWalletKind: .creditCard,
                destinationWalletID: nil,
                destinationWalletKind: nil,
                categoryID: UUID(),
                counterpartyName: nil,
                normalizedCounterpartyKey: nil
            ),
            overview: OverviewTransactionSnapshot(
                id: UUID(),
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                entryStatus: .posted,
                title: "Spend",
                note: nil,
                amountMinor: 10_000,
                sourceCurrencyCode: "JPY",
                occurredAt: transactionDate,
                createdAt: transactionDate,
                sourceWalletID: farCardID,
                sourceWalletName: "Far Card",
                sourceWalletKind: .creditCard,
                destinationWalletID: nil,
                destinationWalletName: nil,
                destinationWalletKind: nil,
                categoryID: UUID(),
                categoryName: "Shopping",
                categoryIconSymbolName: "cart",
                categoryColorHex: "#FF00FF",
                categoryParentID: nil,
                categoryParentName: nil,
                categoryParentIconSymbolName: nil,
                categoryParentColorHex: nil,
                counterpartyName: nil,
                isArchived: false
            ),
            aggregate: FamilyAggregateTransactionSnapshot(
                ownerUserID: ownerID,
                createdByUserID: ownerID,
                categoryName: "Shopping",
                occurredAt: transactionDate,
                kind: .expense,
                amountMinor: 10_000,
                currencyCode: "JPY"
            )
        )

        let input = FamilyOverviewCalculationInput(
            now: now,
            selectedMonth: month,
            selectedInterval: monthInterval,
            timeframeTitle: "April 2026",
            familyMemberUserIDs: [ownerID],
            memberNames: [ownerID: "Owner"],
            memberOrder: [ownerID],
            familyOwnerUserID: ownerID,
            budgetManagerUserID: ownerID,
            goalManagerUserID: ownerID,
            reportingCurrencyCode: "JPY",
            exchangeRates: [],
            calendar: calendar,
            wallets: [nearCard, farCard],
            transactions: [nearTransaction, farTransaction],
            budgets: [],
            goals: [],
            bills: [bill],
            installments: [],
            occurrences: [paidOccurrence]
        )
        
        let result = FamilyOverviewCalculator.compute(input: input)
        
        // Verify Bill is Paid
        let billRow = result.monthlyBillRows.first { $0.title == "Utilities" }
        XCTAssertNotNil(billRow)
        XCTAssertTrue(billRow?.isPaid ?? false)
        
        // Verify Credit Card statuses
        let nearCardRow = result.walletRows.first { $0.name == "Near Card" }
        XCTAssertEqual(nearCardRow?.creditCardStatementStatus, .upcoming)
        
        let farCardRow = result.walletRows.first { $0.name == "Far Card" }
        XCTAssertNil(farCardRow?.creditCardStatementStatus)
    }
}
