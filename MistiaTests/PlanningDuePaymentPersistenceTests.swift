import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class PlanningDuePaymentPersistenceTests: XCTestCase {
    func testSaveDuePaymentAcceptsExactAvailableCreditAfterLimitIncrease() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let card = LedgerWallet(
            name: "Credit card",
            kind: .creditCard,
            iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.creditCard.defaultColorHex
        )
        let profile = CreditCardProfile(
            creditLimitMinor: 100_000,
            wallet: card
        )
        card.creditCardProfile = profile
        let purchase = LedgerTransaction(
            primaryKind: .expense,
            title: "Existing card purchase",
            amountMinor: 20_000,
            occurredAt: makeDate(year: 2026, month: 7, day: 1),
            sourceWallet: card
        )
        context.insert(card)
        context.insert(profile)
        context.insert(purchase)
        try context.save()

        profile.creditLimitMinor = 120_000
        try context.save()

        let draft = PlanningDuePaymentDraft(
            primaryKind: .expense,
            transferSubtype: nil,
            title: "Exact available credit",
            amountMinor: 100_000,
            sourceWalletID: card.id,
            destinationWalletID: nil,
            categorySystemKey: .billing
        )

        _ = try PlanningPersistenceSupport.saveDuePayment(
            draft: draft,
            sourceKind: .recurringBill,
            sourceID: UUID(),
            selectedMonth: makeDate(year: 2026, month: 7, day: 1),
            scheduledDate: makeDate(year: 2026, month: 7, day: 25),
            wallets: [card],
            occurrences: [],
            modelContext: context,
            actorUserID: nil,
            calendar: calendar
        )

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let occurrences = try context.fetch(FetchDescriptor<DueOccurrenceRecord>())
        XCTAssertEqual(transactions.count, 2)
        XCTAssertEqual(occurrences.count, 1)
    }

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
