import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class PlanningDuePaymentPersistenceTests: XCTestCase {
    func testSaveDuePaymentRejectsRecurringBillWhenLinkedWalletBalanceIsInsufficient() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let wallet = LedgerWallet(
            name: "Main",
            kind: .bank,
            iconSymbolName: LedgerWalletKind.bank.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.bank.defaultColorHex,
            openingBalanceMinor: 1_000
        )
        context.insert(wallet)
        try context.save()

        let draft = PlanningDuePaymentDraft(
            primaryKind: .expense,
            transferSubtype: nil,
            title: "Internet",
            amountMinor: 2_000,
            sourceWalletID: wallet.id,
            destinationWalletID: nil,
            categorySystemKey: .billing
        )

        XCTAssertThrowsError(
            try PlanningPersistenceSupport.saveDuePayment(
                draft: draft,
                sourceKind: .recurringBill,
                sourceID: UUID(),
                selectedMonth: makeDate(year: 2026, month: 7, day: 1),
                scheduledDate: makeDate(year: 2026, month: 7, day: 25),
                wallets: [wallet],
                occurrences: [],
                modelContext: context,
                actorUserID: nil,
                calendar: calendar
            )
        ) { error in
            guard case PlanningPersistenceError.insufficientWalletBalance = error else {
                XCTFail("Expected insufficient wallet balance, got \(error)")
                return
            }
        }

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let occurrences = try context.fetch(FetchDescriptor<DueOccurrenceRecord>())
        XCTAssertTrue(transactions.isEmpty)
        XCTAssertTrue(occurrences.isEmpty)
    }

    private var calendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
