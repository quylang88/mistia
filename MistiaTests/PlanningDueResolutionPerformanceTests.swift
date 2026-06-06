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

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
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
