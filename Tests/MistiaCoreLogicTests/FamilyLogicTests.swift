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

    func testAggregateSummaryConvertsWalletsAndTransactionsBeforeSumming() {
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
                    balanceMinor: 100,
                    debtMinor: 0,
                    currencyCode: "JPY"
                ),
                FamilyAggregateWalletSnapshot(
                    ownerUserID: memberB,
                    kind: .cash,
                    balanceMinor: 16_500,
                    debtMinor: 0,
                    currencyCode: "VND"
                )
            ],
            transactions: [
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberB,
                    categoryName: "Ăn uống",
                    occurredAt: makeDate(year: 2026, month: 4, day: 10),
                    kind: .expense,
                    amountMinor: 16_500,
                    currencyCode: "VND"
                )
            ],
            selectedInterval: interval,
            visibleMemberIDs: [memberA, memberB],
            memberNames: [memberA: "A", memberB: "B"],
            reportingCurrencyCode: "JPY",
            exchangeRates: [jpyVndRate],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.totalAssetsMinor, 200)
        XCTAssertEqual(summary.expenseByCategory.first?.valueMinor, 100)
        XCTAssertEqual(summary.spendingByMember.first?.amountMinor, 100)
    }

    func testMonthlySpendableUsesAssetsMinusMonthlyDue() {
        let snapshot = FamilyLogic.monthlySpendable(
            totalAssetsMinor: 250_000,
            monthlyDueMinor: 80_000
        )

        XCTAssertEqual(snapshot.rawMinor, 170_000)
        XCTAssertEqual(snapshot.displayMinor, 170_000)
        XCTAssertEqual(snapshot.shortfallMinor, 0)
        XCTAssertFalse(snapshot.isShortfall)
    }

    func testMonthlySpendableClampsNegativeResultToZero() {
        let snapshot = FamilyLogic.monthlySpendable(
            totalAssetsMinor: 60_000,
            monthlyDueMinor: 95_000
        )

        XCTAssertEqual(snapshot.rawMinor, -35_000)
        XCTAssertEqual(snapshot.displayMinor, 0)
        XCTAssertEqual(snapshot.shortfallMinor, 35_000)
        XCTAssertTrue(snapshot.isShortfall)
    }

    func testMonthlySpendableDoesNotUseAggregateTotalDebt() {
        let memberA = UUID()
        let memberB = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 1),
            end: makeDate(year: 2026, month: 5, day: 1)
        )

        let summary = FamilyLogic.aggregateSummary(
            wallets: [
                FamilyAggregateWalletSnapshot(ownerUserID: memberA, kind: .bank, balanceMinor: 120_000, debtMinor: 0),
                FamilyAggregateWalletSnapshot(ownerUserID: memberB, kind: .creditCard, balanceMinor: 0, debtMinor: 90_000)
            ],
            transactions: [],
            selectedInterval: interval,
            visibleMemberIDs: [memberA, memberB],
            memberNames: [memberA: "A", memberB: "B"],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        let snapshot = FamilyLogic.monthlySpendable(
            totalAssetsMinor: summary.totalAssetsMinor,
            monthlyDueMinor: 25_000
        )

        XCTAssertEqual(summary.totalDebtMinor, 90_000)
        XCTAssertEqual(snapshot.displayMinor, 95_000)
    }

    func testOwnerAndMemberCanViewOthersButCannotEditWithoutPermission() {
        let ownerAccess = FamilyLogic.access(
            viewerRole: .owner,
            viewerPolicy: .preset(for: .owner),
            targetRole: .member,
            isSameUser: false
        )

        XCTAssertTrue(ownerAccess.canOpenFamilyHome)
        XCTAssertTrue(ownerAccess.canInviteMembers)
        XCTAssertTrue(ownerAccess.canManageMembers)
        XCTAssertTrue(ownerAccess.canViewTarget)
        XCTAssertTrue(ownerAccess.canViewTargetWallets)
        XCTAssertFalse(ownerAccess.canEditTarget)

        let memberAccess = FamilyLogic.access(
            viewerRole: .member,
            viewerPolicy: .preset(for: .member),
            targetRole: .owner,
            isSameUser: false
        )

        XCTAssertTrue(memberAccess.canOpenFamilyHome)
        XCTAssertFalse(memberAccess.canInviteMembers)
        XCTAssertFalse(memberAccess.canManageMembers)
        XCTAssertTrue(memberAccess.canViewTarget)
        XCTAssertTrue(memberAccess.canViewTargetWallets)
        XCTAssertFalse(memberAccess.canEditTarget)
    }

    func testKidCannotViewOthersByDefault() {
        let access = FamilyLogic.access(
            viewerRole: .kid,
            viewerPolicy: .preset(for: .kid),
            targetRole: .member,
            isSameUser: false
        )

        XCTAssertFalse(access.canOpenFamilyHome)
        XCTAssertFalse(access.canViewTarget)
        XCTAssertFalse(access.canViewTargetWallets)
        XCTAssertFalse(access.canEditTarget)
    }

    func testKidViewGrantDoesNotGrantEdit() {
        var policy = FamilyPermissionPolicy.preset(for: .kid)
        policy.canViewFamilyDashboard = true
        policy.canViewOthers = true
        policy.canViewWallets = true

        let access = FamilyLogic.access(
            viewerRole: .kid,
            viewerPolicy: policy,
            targetRole: .member,
            isSameUser: false
        )

        XCTAssertTrue(access.canOpenFamilyHome)
        XCTAssertTrue(access.canViewTarget)
        XCTAssertTrue(access.canViewTargetWallets)
        XCTAssertFalse(access.canEditTarget)
    }

    func testSameUserCanViewAndEditOwnData() {
        let access = FamilyLogic.access(
            viewerRole: .kid,
            viewerPolicy: .preset(for: .kid),
            targetRole: .kid,
            isSameUser: true
        )

        XCTAssertTrue(access.canViewTarget)
        XCTAssertTrue(access.canEditTarget)
        XCTAssertTrue(access.canViewTargetWallets)
    }

    func testLegacyViewerAndEditorRolesDecodeAsMember() {
        XCTAssertEqual(FamilyRole(rawValue: "viewer"), .member)
        XCTAssertEqual(FamilyRole(rawValue: "editor"), .member)
        XCTAssertEqual(FamilyRole.member.rawValue, "member")
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

    func testAggregateSummaryBuildsMemberComparisonFromCreatorsAndVisibleTransactions() {
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
                    createdByUserID: memberA,
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
                    ownerUserID: memberA,
                    createdByUserID: memberB,
                    categoryName: "Shopping",
                    occurredAt: makeDate(year: 2026, month: 4, day: 8),
                    kind: .expense,
                    amountMinor: 35_000
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberA,
                    categoryName: "Thanh toán thẻ",
                    occurredAt: makeDate(year: 2026, month: 4, day: 12),
                    kind: .expense,
                    amountMinor: 100_000,
                    isCreditCardPayment: true
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberA,
                    createdByUserID: memberB,
                    categoryName: "Adjustment",
                    occurredAt: makeDate(year: 2026, month: 4, day: 13),
                    kind: .expense,
                    amountMinor: 70_000,
                    isAdjustment: true
                ),
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: memberB,
                    createdByUserID: memberB,
                    categoryName: "Installment",
                    occurredAt: makeDate(year: 2026, month: 4, day: 14),
                    kind: .expense,
                    amountMinor: 90_000,
                    isInstallmentPayment: true
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
        XCTAssertEqual(summary.expenseByCategory.map(\.label), ["Shopping", "Food"])
        XCTAssertEqual(summary.expenseByCategory.map(\.valueMinor), [35_000, 20_000])
        XCTAssertEqual(summary.incomeByMember.map(\.name), ["Binh"])
        XCTAssertEqual(summary.incomeByMember.map(\.amountMinor), [50_000])
    }

    func testAggregateSummarySumsSameNamedCategorySpendingAcrossMembers() {
        let memberA = UUID()
        let memberB = UUID()
        let interval = DateInterval(
            start: makeDate(year: 2026, month: 4, day: 1),
            end: makeDate(year: 2026, month: 5, day: 1)
        )

        let summary = FamilyLogic.aggregateSummary(
            wallets: [],
            transactions: [
                makeFamilyTransaction(ownerUserID: memberA, categoryName: "Ăn uống", amountMinor: 40_000),
                makeFamilyTransaction(ownerUserID: memberB, categoryName: " ăn   UỐNG ", amountMinor: 35_000)
            ],
            selectedInterval: interval,
            visibleMemberIDs: [memberA, memberB],
            memberNames: [memberA: "An", memberB: "Binh"],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.expenseByCategory.map(\.label), ["Ăn uống"])
        XCTAssertEqual(summary.expenseByCategory.map(\.valueMinor), [75_000])
    }

    func testAggregateWalletsByNameSumsMatchingVisibleNames() {
        let memberA = UUID()
        let memberB = UUID()
        let createdAt = makeDate(year: 2026, month: 4, day: 1)
        let rows = FamilyLogic.aggregateWalletsByName([
            FamilyWalletAggregateSnapshot(
                id: "a",
                ownerUserID: memberA,
                name: "Main Cash",
                kind: .cash,
                currentBalanceMinor: 120_000,
                debtMinor: 0,
                currencyCode: "JPY",
                sortOrder: 1,
                createdAt: createdAt
            ),
            FamilyWalletAggregateSnapshot(
                id: "b",
                ownerUserID: memberB,
                name: " main   cash ",
                kind: .bank,
                currentBalanceMinor: 80_000,
                debtMinor: 0,
                currencyCode: "JPY",
                sortOrder: 2,
                createdAt: createdAt
            )
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Main Cash")
        XCTAssertEqual(rows.first?.currentBalanceMinor, 200_000)

        let summary = FamilyLogic.aggregateSummary(
            wallets: rows.map {
                FamilyAggregateWalletSnapshot(
                    ownerUserID: $0.ownerUserID,
                    kind: .cash,
                    balanceMinor: $0.currentBalanceMinor,
                    debtMinor: $0.debtMinor,
                    name: $0.name
                )
            },
            transactions: [],
            selectedInterval: DateInterval(
                start: makeDate(year: 2026, month: 4, day: 1),
                end: makeDate(year: 2026, month: 5, day: 1)
            ),
            visibleMemberIDs: [memberA, memberB],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar
        )

        XCTAssertEqual(summary.balanceByWalletName.map(\.label), ["Main Cash"])
        XCTAssertEqual(summary.balanceByWalletName.map(\.valueMinor), [200_000])
    }

    func testFamilyBudgetRowsSumSameNamedCategorySpendingAcrossMembers() {
        let memberA = UUID()
        let memberB = UUID()
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)

        let rows = FamilyLogic.familyBudgetRows(
            plans: [
                makeBudget(ownerUserID: memberA, categoryName: "Ăn ngoài", limitMinor: 100_000, monthAnchor: selectedMonth)
            ],
            transactions: [
                makeFamilyTransaction(ownerUserID: memberA, categoryName: "Ăn ngoài", amountMinor: 40_000),
                makeFamilyTransaction(ownerUserID: memberB, categoryName: " ăn   ngoài ", amountMinor: 35_000),
                makeFamilyTransaction(
                    ownerUserID: memberB,
                    categoryName: "Ăn ngoài",
                    amountMinor: 200_000,
                    isCreditCardPayment: true
                )
            ],
            selectedMonth: selectedMonth,
            ownerUserID: memberA,
            budgetManagerUserID: nil,
            memberOrder: [memberA, memberB],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar,
            minimumProgress: 0,
            includesMinimumProgress: true,
            maximumCount: nil
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.spentMinor, 75_000)
        XCTAssertEqual(rows.first?.limitMinor, 100_000)
    }

    func testFamilyBudgetRowsPrioritizeOwnerBudgetThenManager() {
        let owner = UUID()
        let memberA = UUID()
        let memberB = UUID()
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)

        let ownerRows = FamilyLogic.familyBudgetRows(
            plans: [
                makeBudget(ownerUserID: memberA, categoryName: "Ăn ngoài", limitMinor: 100_000, monthAnchor: selectedMonth),
                makeBudget(ownerUserID: owner, categoryName: "Ăn ngoài", limitMinor: 250_000, monthAnchor: selectedMonth)
            ],
            transactions: [makeFamilyTransaction(ownerUserID: memberA, categoryName: "Ăn ngoài", amountMinor: 50_000)],
            selectedMonth: selectedMonth,
            ownerUserID: owner,
            budgetManagerUserID: memberA,
            memberOrder: [owner, memberA, memberB],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar,
            minimumProgress: 0,
            includesMinimumProgress: true,
            maximumCount: nil
        )

        XCTAssertEqual(ownerRows.first?.sourceOwnerUserID, owner)
        XCTAssertEqual(ownerRows.first?.limitMinor, 250_000)

        let managerRows = FamilyLogic.familyBudgetRows(
            plans: [
                makeBudget(ownerUserID: memberA, categoryName: "Ăn ngoài", limitMinor: 100_000, monthAnchor: selectedMonth),
                makeBudget(ownerUserID: memberB, categoryName: "Ăn ngoài", limitMinor: 300_000, monthAnchor: selectedMonth)
            ],
            transactions: [makeFamilyTransaction(ownerUserID: memberA, categoryName: "Ăn ngoài", amountMinor: 50_000)],
            selectedMonth: selectedMonth,
            ownerUserID: owner,
            budgetManagerUserID: memberB,
            memberOrder: [owner, memberA, memberB],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar,
            minimumProgress: 0,
            includesMinimumProgress: true,
            maximumCount: nil
        )

        XCTAssertEqual(managerRows.first?.sourceOwnerUserID, memberB)
        XCTAssertEqual(managerRows.first?.limitMinor, 300_000)
    }

    func testFamilyBudgetRowsUseMemberOrderWhenOwnerAndManagerHaveNoPlan() {
        let owner = UUID()
        let memberA = UUID()
        let memberB = UUID()
        let selectedMonth = makeDate(year: 2026, month: 4, day: 1)

        let rows = FamilyLogic.familyBudgetRows(
            plans: [
                makeBudget(ownerUserID: memberB, categoryName: "Ăn ngoài", limitMinor: 300_000, monthAnchor: selectedMonth),
                makeBudget(ownerUserID: memberA, categoryName: "Ăn ngoài", limitMinor: 100_000, monthAnchor: selectedMonth)
            ],
            transactions: [makeFamilyTransaction(ownerUserID: memberA, categoryName: "Ăn ngoài", amountMinor: 50_000)],
            selectedMonth: selectedMonth,
            ownerUserID: owner,
            budgetManagerUserID: nil,
            memberOrder: [owner, memberA, memberB],
            referenceDate: makeDate(year: 2026, month: 4, day: 15),
            calendar: calendar,
            minimumProgress: 0,
            includesMinimumProgress: true,
            maximumCount: nil
        )

        XCTAssertEqual(rows.first?.sourceOwnerUserID, memberA)
        XCTAssertEqual(rows.first?.limitMinor, 100_000)
    }

    func testFamilyGoalRowsAggregateByNameAndPrioritizeOwnerThenManagerTarget() {
        let owner = UUID()
        let memberA = UUID()
        let memberB = UUID()
        let targetDate = makeDate(year: 2026, month: 12, day: 31)

        let ownerRows = FamilyLogic.familyGoalRows(
            goals: [
                makeGoal(ownerUserID: owner, name: "Du lịch", targetMinor: 500_000, savedMinor: 120_000, targetDate: targetDate),
                makeGoal(ownerUserID: memberA, name: " du   lịch ", targetMinor: 900_000, savedMinor: 80_000, targetDate: targetDate)
            ],
            ownerUserID: owner,
            goalManagerUserID: memberA,
            memberOrder: [owner, memberA, memberB]
        )

        XCTAssertEqual(ownerRows.count, 1)
        XCTAssertEqual(ownerRows.first?.sourceOwnerUserID, owner)
        XCTAssertEqual(ownerRows.first?.targetMinor, 500_000)
        XCTAssertEqual(ownerRows.first?.currentSavedMinor, 200_000)

        let managerRows = FamilyLogic.familyGoalRows(
            goals: [
                makeGoal(ownerUserID: memberA, name: "Du lịch", targetMinor: 500_000, savedMinor: 120_000, targetDate: targetDate),
                makeGoal(ownerUserID: memberB, name: "Du lịch", targetMinor: 900_000, savedMinor: 80_000, targetDate: targetDate)
            ],
            ownerUserID: owner,
            goalManagerUserID: memberB,
            memberOrder: [owner, memberA, memberB]
        )

        XCTAssertEqual(managerRows.first?.sourceOwnerUserID, memberB)
        XCTAssertEqual(managerRows.first?.targetMinor, 900_000)
        XCTAssertEqual(managerRows.first?.currentSavedMinor, 200_000)
    }

    func testFamilyGoalRowsUseMemberOrderWhenOwnerAndManagerHaveNoGoal() {
        let owner = UUID()
        let memberA = UUID()
        let memberB = UUID()
        let targetDate = makeDate(year: 2026, month: 12, day: 31)

        let rows = FamilyLogic.familyGoalRows(
            goals: [
                makeGoal(ownerUserID: memberB, name: "Du lịch", targetMinor: 900_000, savedMinor: 80_000, targetDate: targetDate),
                makeGoal(ownerUserID: memberA, name: " du   lịch ", targetMinor: 500_000, savedMinor: 120_000, targetDate: targetDate)
            ],
            ownerUserID: owner,
            goalManagerUserID: nil,
            memberOrder: [owner, memberA, memberB]
        )

        XCTAssertEqual(rows.first?.sourceOwnerUserID, memberA)
        XCTAssertEqual(rows.first?.targetMinor, 500_000)
        XCTAssertEqual(rows.first?.currentSavedMinor, 200_000)
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

    private func makeBudget(
        ownerUserID: UUID,
        categoryName: String,
        limitMinor: Int64,
        monthAnchor: Date
    ) -> FamilyBudgetPlanSnapshot {
        FamilyBudgetPlanSnapshot(
            id: UUID(),
            ownerUserID: ownerUserID,
            categoryName: categoryName,
            iconSymbolName: "fork.knife",
            colorHex: "#9B5CF6",
            limitMinor: limitMinor,
            currencyCode: "JPY",
            monthAnchor: monthAnchor
        )
    }

    private func makeGoal(
        ownerUserID: UUID,
        name: String,
        targetMinor: Int64,
        savedMinor: Int64,
        targetDate: Date
    ) -> FamilyGoalSnapshot {
        FamilyGoalSnapshot(
            id: UUID(),
            ownerUserID: ownerUserID,
            name: name,
            iconSymbolName: "target",
            targetMinor: targetMinor,
            currentSavedMinor: savedMinor,
            targetDate: targetDate,
            currencyCode: "JPY",
            sortOrder: 0
        )
    }

    private func makeFamilyTransaction(
        ownerUserID: UUID,
        categoryName: String,
        amountMinor: Int64,
        isCreditCardPayment: Bool = false
    ) -> FamilyAggregateTransactionSnapshot {
        FamilyAggregateTransactionSnapshot(
            ownerUserID: ownerUserID,
            categoryName: categoryName,
            occurredAt: makeDate(year: 2026, month: 4, day: 10),
            kind: .expense,
            amountMinor: amountMinor,
            isCreditCardPayment: isCreditCardPayment
        )
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
