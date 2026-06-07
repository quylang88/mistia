import Foundation
import XCTest
@testable import Mistia

final class PlanningDueResolutionPerformanceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testRecurringBillDueItemShortCircuitsOccurrenceSequence() {
        let billID = UUID()
        let selectedMonth = makeDate(year: 2026, month: 6, day: 1)
        let occurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .recurringBill,
            sourceID: billID,
            selectedMonthKey: "2026-06",
            scheduledDate: makeDate(year: 2026, month: 6, day: 15),
            amountMinorSnapshot: 9_900,
            status: .paid,
            linkedTransactionID: UUID()
        )
        let sequence = CountingOccurrenceSequence([
            occurrence,
            PlanningDueOccurrenceSnapshot(
                id: UUID(),
                sourceKind: .recurringBill,
                sourceID: UUID(),
                selectedMonthKey: "2026-06",
                scheduledDate: makeDate(year: 2026, month: 6, day: 16),
                amountMinorSnapshot: 1,
                status: .pending,
                linkedTransactionID: nil
            )
        ])

        let item = PlanningLogic.recurringBillDueItem(
            bill: PlanningBillSnapshot(
                id: billID,
                name: "Internet",
                iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
                categorySystemKey: .internet,
                amountMinor: 5_000,
                dueDay: 15,
                frequencyMonths: 1,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                createdAt: makeDate(year: 2026, month: 1, day: 1)
            ),
            occurrences: sequence,
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        XCTAssertEqual(item?.amountMinor, 9_900)
        XCTAssertEqual(item?.status, .paid)
        XCTAssertEqual(sequence.nextCallCount, 1)
    }

    func testInstallmentDueItemShortCircuitsOccurrenceSequence() {
        let planID = UUID()
        let selectedMonth = makeDate(year: 2026, month: 6, day: 1)
        let occurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .installment,
            sourceID: planID,
            selectedMonthKey: "2026-06",
            scheduledDate: makeDate(year: 2026, month: 6, day: 20),
            amountMinorSnapshot: 7_700,
            status: .paid,
            linkedTransactionID: UUID()
        )
        let sequence = CountingOccurrenceSequence([
            occurrence,
            PlanningDueOccurrenceSnapshot(
                id: UUID(),
                sourceKind: .installment,
                sourceID: UUID(),
                selectedMonthKey: "2026-06",
                scheduledDate: makeDate(year: 2026, month: 6, day: 21),
                amountMinorSnapshot: 1,
                status: .pending,
                linkedTransactionID: nil
            )
        ])

        let item = PlanningLogic.installmentDueItem(
            plan: PlanningInstallmentSnapshot(
                id: planID,
                name: "Laptop",
                iconSymbolName: "laptopcomputer",
                amountPerCycleMinor: 8_000,
                dueDay: 20,
                totalCycles: 12,
                frequencyMonths: 1,
                paymentWalletID: UUID(),
                currencyCode: "JPY",
                createdAt: makeDate(year: 2026, month: 1, day: 1)
            ),
            occurrences: sequence,
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        XCTAssertEqual(item?.amountMinor, 7_700)
        XCTAssertEqual(item?.status, .paid)
        XCTAssertEqual(sequence.nextCallCount, 1)
    }

    func testPaidCreditCardStatementForExpenseAcceptsLazySequencesAndShortCircuitsOccurrences() {
        let cardWalletID = UUID()
        let paymentWalletID = UUID()
        let statementMonth = makeDate(year: 2026, month: 5, day: 12)
        let account = PlanningCreditCardAccountSnapshot(
            id: cardWalletID,
            walletID: cardWalletID,
            walletName: "SMBC Card",
            issuerName: "SMBC",
            network: .visa,
            last4: "1234",
            dueDay: 26,
            statementClosingDay: 10,
            paymentSourceWalletID: paymentWalletID,
            paymentSourceWalletName: "Main",
            currencyCode: "JPY",
            currentDebtMinor: 12_000,
            availableCreditMinor: 88_000,
            openedAt: makeDate(year: 2026, month: 1, day: 1)
        )
        let matchingOccurrence = PlanningDueOccurrenceSnapshot(
            id: UUID(),
            sourceKind: .creditCard,
            sourceID: cardWalletID,
            selectedMonthKey: "2026-05",
            scheduledDate: makeDate(year: 2026, month: 6, day: 26),
            amountMinorSnapshot: 12_000,
            status: .paid,
            linkedTransactionID: UUID()
        )
        let records = CountingTransactionRecordSequence([
            transactionRecord(
                primaryKind: .expense,
                amountMinor: 12_000,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard,
                occurredAt: statementMonth
            )
        ])
        let occurrences = CountingOccurrenceSequence([
            matchingOccurrence,
            PlanningDueOccurrenceSnapshot(
                id: UUID(),
                sourceKind: .creditCard,
                sourceID: cardWalletID,
                selectedMonthKey: "2026-06",
                scheduledDate: makeDate(year: 2026, month: 7, day: 26),
                amountMinorSnapshot: 1,
                status: .pending,
                linkedTransactionID: nil
            )
        ])

        let statement = PlanningLogic.paidCreditCardStatementForExpense(
            account: account,
            records: records,
            occurrences: occurrences,
            occurredAt: statementMonth,
            referenceDate: makeDate(year: 2026, month: 6, day: 30),
            calendar: calendar
        )

        XCTAssertEqual(statement?.amountMinor, 12_000)
        XCTAssertEqual(statement?.status, .paid)
        XCTAssertEqual(statement?.state, .paid)
        XCTAssertEqual(occurrences.nextCallCount, 1)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }

    private func transactionRecord(
        primaryKind: TransactionPrimaryKind,
        amountMinor: Int64,
        transferSubtype: TransactionTransferSubtype? = nil,
        sourceWalletID: UUID,
        sourceWalletKind: LedgerWalletKind,
        destinationWalletID: UUID? = nil,
        destinationWalletKind: LedgerWalletKind? = nil,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Record",
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: "JPY",
            isArchived: false,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletKind: destinationWalletKind,
            categoryID: primaryKind == .expense ? UUID() : nil,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }
}

private final class CountingTransactionRecordSequence: Sequence {
    private let elements: [TransactionRecordSnapshot]

    init(_ elements: [TransactionRecordSnapshot]) {
        self.elements = elements
    }

    func makeIterator() -> AnyIterator<TransactionRecordSnapshot> {
        var iterator = elements.makeIterator()
        return AnyIterator {
            iterator.next()
        }
    }
}

private final class CountingOccurrenceSequence: Sequence {
    private let elements: [PlanningDueOccurrenceSnapshot]
    private(set) var nextCallCount = 0

    init(_ elements: [PlanningDueOccurrenceSnapshot]) {
        self.elements = elements
    }

    func makeIterator() -> Iterator {
        Iterator(owner: self)
    }

    final class Iterator: IteratorProtocol {
        private let owner: CountingOccurrenceSequence
        private var index = 0

        init(owner: CountingOccurrenceSequence) {
            self.owner = owner
        }

        func next() -> PlanningDueOccurrenceSnapshot? {
            guard index < owner.elements.count else { return nil }
            defer { index += 1 }
            owner.nextCallCount += 1
            return owner.elements[index]
        }
    }
}
