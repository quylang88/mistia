import Foundation
import XCTest
@testable import Mistia

final class OverviewAggregationPerformanceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testWeeklySpendingPagesKeepDailyTotalsAndEmptyWeeks() {
        let referenceDate = makeDate(year: 2026, month: 4, day: 22, hour: 10)
        let records = [
            transactionRecord(amountMinor: 2_000, occurredAt: makeDate(year: 2026, month: 4, day: 6, hour: 8)),
            transactionRecord(amountMinor: 3_000, occurredAt: makeDate(year: 2026, month: 4, day: 22, hour: 9))
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
        XCTAssertEqual(pages[0].points.map(\.valueMinor), [2_000, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(pages[1].points.map(\.valueMinor), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(pages[2].points.map(\.valueMinor), [0, 0, 3_000, 0, 0, 0, 0])
    }

    func testCategorySpendingMonthPagesKeepMonthBucketsAndRollups() {
        let parentID = UUID()
        let childID = UUID()
        let uncategorizedID = UUID()
        let transactions = [
            overviewExpense(
                amountMinor: 5_000,
                occurredAt: makeDate(year: 2026, month: 3, day: 12),
                categoryID: childID,
                categoryName: "Groceries",
                categoryParentID: parentID,
                categoryParentName: "Living"
            ),
            overviewExpense(
                amountMinor: 2_000,
                occurredAt: makeDate(year: 2026, month: 5, day: 2),
                categoryID: uncategorizedID,
                categoryName: "Other"
            )
        ]

        let pages = OverviewLogic.categorySpendingMonthPages(
            from: transactions,
            currencyCode: "JPY",
            referenceDate: makeDate(year: 2026, month: 5, day: 20),
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
        XCTAssertEqual(pages.map(\.totalExpenseMinor), [5_000, 0, 2_000])
        XCTAssertEqual(pages[0].slices.first?.name, "Living")
        XCTAssertEqual(pages[0].slices.first?.childSlices.map(\.name), ["Groceries"])
    }

    func testMonthlyCashflowPagesKeepIncomeAndExpenseBuckets() {
        let records = [
            transactionRecord(primaryKind: .income, amountMinor: 7_000, occurredAt: makeDate(year: 2026, month: 5, day: 4)),
            transactionRecord(primaryKind: .expense, amountMinor: 2_000, occurredAt: makeDate(year: 2026, month: 5, day: 12)),
            transactionRecord(primaryKind: .income, amountMinor: 11_000, occurredAt: makeDate(year: 2026, month: 6, day: 2)),
            transactionRecord(primaryKind: .expense, amountMinor: 3_000, occurredAt: makeDate(year: 2026, month: 6, day: 8))
        ]

        let pages = OverviewLogic.monthlyCashflowPages(
            from: records,
            currencyCode: "JPY",
            referenceDate: makeDate(year: 2026, month: 6, day: 20),
            calendar: calendar
        )

        XCTAssertEqual(pages.map(\.monthStart), [
            makeDate(year: 2026, month: 5, day: 1),
            makeDate(year: 2026, month: 6, day: 1)
        ])
        XCTAssertEqual(pages.map(\.incomeMinor), [7_000, 11_000])
        XCTAssertEqual(pages.map(\.expenseMinor), [2_000, 3_000])
    }

    func testOverviewRenderSnapshotCacheKeyInvalidatesWhenSettlementDataChanges() {
        let baselineGroups = collectionSignature(updatedAt: 100, remoteVersion: 1)
        let changedGroups = collectionSignature(updatedAt: 200, remoteVersion: 2)
        let baselineParticipants = collectionSignature(updatedAt: 300, remoteVersion: 1)
        let changedParticipants = collectionSignature(updatedAt: 400, remoteVersion: 2)

        let baseline = overviewCacheKey(
            settlementGroupSignature: baselineGroups,
            settlementParticipantSignature: baselineParticipants
        )

        XCTAssertNotEqual(
            baseline,
            overviewCacheKey(
                settlementGroupSignature: changedGroups,
                settlementParticipantSignature: baselineParticipants
            )
        )
        XCTAssertNotEqual(
            baseline,
            overviewCacheKey(
                settlementGroupSignature: baselineGroups,
                settlementParticipantSignature: changedParticipants
            )
        )
    }

    private func transactionRecord(
        primaryKind: TransactionPrimaryKind = .expense,
        amountMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Expense",
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: nil,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }

    private func overviewExpense(
        amountMinor: Int64,
        occurredAt: Date,
        categoryID: UUID,
        categoryName: String,
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil
    ) -> OverviewTransactionSnapshot {
        OverviewTransactionSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: categoryName,
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: nil,
            sourceWalletName: nil,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletName: nil,
            destinationWalletKind: nil,
            categoryID: categoryID,
            categoryName: categoryName,
            categoryIconSymbolName: "circle.fill",
            categoryColorHex: "#999999",
            categoryParentID: categoryParentID,
            categoryParentName: categoryParentName,
            categoryParentIconSymbolName: categoryParentID == nil ? nil : "square.fill",
            categoryParentColorHex: categoryParentID == nil ? nil : "#111111",
            counterpartyName: nil,
            isArchived: false
        )
    }

    private func overviewCacheKey(
        settlementGroupSignature: MistiaCollectionChangeSignature,
        settlementParticipantSignature: MistiaCollectionChangeSignature
    ) -> OverviewRenderSnapshotCacheKey {
        OverviewRenderSnapshotCacheKey(
            activeScope: .personalSelf,
            selectedSubjectUserID: nil,
            currentUserID: nil,
            activeLocalProfileUserID: nil,
            signedInUserID: nil,
            familyID: nil,
            currentMonthStart: 1_777_000_000,
            calendarIdentifier: "gregorian",
            calendarTimeZoneIdentifier: "UTC",
            localeIdentifier: "en_US",
            currencyCode: "JPY",
            currencyRateMode: MistiaCurrencyRateMode.automatic.rawValue,
            manualJPYToVNDRate: "",
            cachedRatesSignature: 0,
            familyAccessSignature: 0,
            walletSignature: .empty,
            transactionSignature: .empty,
            budgetSignature: .empty,
            categorySignature: .empty,
            billSignature: .empty,
            installmentSignature: .empty,
            occurrenceSignature: .empty,
            settlementGroupSignature: settlementGroupSignature,
            settlementParticipantSignature: settlementParticipantSignature,
            ownershipSignature: .empty
        )
    }

    private func collectionSignature(
        updatedAt: TimeInterval,
        remoteVersion: Int64
    ) -> MistiaCollectionChangeSignature {
        MistiaCollectionChangeSignature(
            count: 1,
            latestUpdatedAt: updatedAt,
            latestDeletedAt: nil,
            latestRemoteVersion: remoteVersion,
            archivedCount: 0
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? .distantPast
    }
}
