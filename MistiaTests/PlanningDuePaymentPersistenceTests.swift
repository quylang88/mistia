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

    func testUndoDuePaymentSoftDeletesTransactionAndOccurrence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let wallet = LedgerWallet(
            name: "Main",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            openingBalanceMinor: 500_000
        )
        context.insert(wallet)
        try context.save()

        let billID = UUID()
        let selectedMonth = makeDate(year: 2026, month: 8, day: 1)
        let scheduledDate = makeDate(year: 2026, month: 8, day: 25)

        let draft = PlanningDuePaymentDraft(
            primaryKind: .expense,
            transferSubtype: nil,
            title: "Electricity bill",
            amountMinor: 200_000,
            sourceWalletID: wallet.id,
            destinationWalletID: nil,
            categorySystemKey: .billing
        )

        let saved = try PlanningPersistenceSupport.saveDuePayment(
            draft: draft,
            sourceKind: .recurringBill,
            sourceID: billID,
            selectedMonth: selectedMonth,
            scheduledDate: scheduledDate,
            wallets: [wallet],
            occurrences: [],
            modelContext: context,
            actorUserID: nil,
            calendar: calendar
        )

        let activeTxDescriptor = FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate<LedgerTransaction> { $0.deletedAt == nil }
        )
        let activeOccDescriptor = FetchDescriptor<DueOccurrenceRecord>(
            predicate: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil }
        )

        var activeTransactions = try context.fetch(activeTxDescriptor)
        var activeOccurrences = try context.fetch(activeOccDescriptor)
        XCTAssertEqual(activeTransactions.count, 1)
        XCTAssertEqual(activeOccurrences.count, 1)
        XCTAssertEqual(activeOccurrences.first?.status, .paid)
        XCTAssertEqual(activeOccurrences.first?.linkedTransactionID, saved.transaction.id)

        // Undo payment
        let undone = try PlanningPersistenceSupport.undoDuePayment(
            sourceKind: .recurringBill,
            sourceID: billID,
            selectedMonth: selectedMonth,
            occurrences: activeOccurrences,
            modelContext: context,
            targetTransactionID: saved.transaction.id,
            calendar: calendar
        )

        XCTAssertEqual(undone.deletedTransactionID, saved.transaction.id)
        XCTAssertTrue(undone.deletedTransactionIDs.contains(saved.transaction.id))

        activeTransactions = try context.fetch(activeTxDescriptor)
        activeOccurrences = try context.fetch(activeOccDescriptor)
        XCTAssertEqual(activeTransactions.count, 0, "Active transactions must be 0 after undo")
        XCTAssertEqual(activeOccurrences.count, 0, "Active occurrences must be 0 after undo")

        // Confirm both records still exist locally but with deletedAt set (soft-deleted)
        let allTransactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let allOccurrences = try context.fetch(FetchDescriptor<DueOccurrenceRecord>())
        XCTAssertEqual(allTransactions.count, 1)
        XCTAssertNotNil(allTransactions.first?.deletedAt)
        XCTAssertEqual(allOccurrences.count, 1)
        XCTAssertNotNil(allOccurrences.first?.deletedAt)
    }

    func testCleanupOrphanedBillTransactions() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let wallet = LedgerWallet(
            name: "Bank",
            kind: .bank,
            iconSymbolName: LedgerWalletKind.bank.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.bank.defaultColorHex,
            openingBalanceMinor: 1_000_000
        )
        context.insert(wallet)

        let bill1 = RecurringBillPlan(
            name: "Bill 1",
            iconSymbolName: "doc.text",
            amountMinor: 100_000,
            dueDay: 5,
            paymentWallet: wallet
        )
        let bill2 = RecurringBillPlan(
            name: "Deleted Bill",
            iconSymbolName: "doc.text",
            amountMinor: 150_000,
            dueDay: 10,
            paymentWallet: wallet
        )
        bill2.markDeleted(at: Date())
        context.insert(bill1)
        context.insert(bill2)

        // Case 1: Occurrence is deleted, but transaction was still active
        let tx1 = LedgerTransaction(
            primaryKind: .expense,
            title: "Bill 1 Payment (Orphaned by deleted occurrence)",
            amountMinor: 100_000,
            occurredAt: makeDate(year: 2026, month: 6, day: 5),
            sourceWallet: wallet
        )
        let occ1 = DueOccurrenceRecord(
            sourceKind: .recurringBill,
            sourceID: bill1.id,
            selectedMonthKey: "2026-06",
            scheduledDate: makeDate(year: 2026, month: 6, day: 5),
            status: .paid,
            linkedTransactionID: tx1.id
        )
        occ1.markDeleted(at: Date())
        context.insert(tx1)
        context.insert(occ1)

        // Case 2: Occurrence is marked skipped, but linked transaction was still active
        let tx2 = LedgerTransaction(
            primaryKind: .expense,
            title: "Bill 1 Payment (Orphaned by skipped occurrence)",
            amountMinor: 100_000,
            occurredAt: makeDate(year: 2026, month: 7, day: 5),
            sourceWallet: wallet
        )
        let occ2 = DueOccurrenceRecord(
            sourceKind: .recurringBill,
            sourceID: bill1.id,
            selectedMonthKey: "2026-07",
            scheduledDate: makeDate(year: 2026, month: 7, day: 5),
            status: .skipped,
            linkedTransactionID: tx2.id
        )
        context.insert(tx2)
        context.insert(occ2)

        // Case 3: Parent bill is deleted, occurrence was paid with transaction
        let tx3 = LedgerTransaction(
            primaryKind: .expense,
            title: "Bill 2 Payment (Orphaned by deleted bill)",
            amountMinor: 150_000,
            occurredAt: makeDate(year: 2026, month: 8, day: 10),
            sourceWallet: wallet
        )
        let occ3 = DueOccurrenceRecord(
            sourceKind: .recurringBill,
            sourceID: bill2.id,
            selectedMonthKey: "2026-08",
            scheduledDate: makeDate(year: 2026, month: 8, day: 10),
            status: .paid,
            linkedTransactionID: tx3.id
        )
        context.insert(tx3)
        context.insert(occ3)

        // Case 4: Valid active transaction and paid occurrence
        let tx4 = LedgerTransaction(
            primaryKind: .expense,
            title: "Bill 1 Valid Payment",
            amountMinor: 100_000,
            occurredAt: makeDate(year: 2026, month: 8, day: 5),
            sourceWallet: wallet
        )
        let occ4 = DueOccurrenceRecord(
            sourceKind: .recurringBill,
            sourceID: bill1.id,
            selectedMonthKey: "2026-08",
            scheduledDate: makeDate(year: 2026, month: 8, day: 5),
            status: .paid,
            linkedTransactionID: tx4.id
        )
        context.insert(tx4)
        context.insert(occ4)

        // Case 5: Transaction from previously undone bill payment where occurrence was hard-deleted (unpaid month)
        let billingCategory = TransactionCategory(
            name: "Billing",
            kind: .expense,
            iconSymbolName: "doc.text",
            iconColorHex: "#000000",
            systemKey: MistiaSystemCategoryKey.billing.rawValue
        )
        context.insert(billingCategory)

        let tx5 = LedgerTransaction(
            primaryKind: .expense,
            title: "Bill 1",
            amountMinor: 100_000,
            occurredAt: makeDate(year: 2026, month: 5, day: 5),
            sourceWallet: wallet
        )
        tx5.category = billingCategory
        context.insert(tx5)

        // Case 6: Transaction for deleted bill where occurrence was hard-deleted
        let tx6 = LedgerTransaction(
            primaryKind: .expense,
            title: "Deleted Bill",
            amountMinor: 150_000,
            occurredAt: makeDate(year: 2026, month: 5, day: 10),
            sourceWallet: wallet
        )
        tx6.category = billingCategory
        context.insert(tx6)

        try context.save()

        // Run cleanup
        let deleteMutations = try MistiaBootstrap.cleanupOrphanedBillTransactions(modelContext: context)

        XCTAssertEqual(deleteMutations.filter { $0.entity == .transaction }.count, 5)
        XCTAssertNotNil(tx1.deletedAt)
        XCTAssertNotNil(tx2.deletedAt)
        XCTAssertNotNil(tx3.deletedAt)
        XCTAssertNotNil(tx5.deletedAt, "Hard-deleted occurrence orphan for unpaid month must be cleaned up")
        XCTAssertNotNil(tx6.deletedAt, "Hard-deleted occurrence orphan for deleted bill must be cleaned up")
        XCTAssertNil(tx4.deletedAt, "Valid transaction must NOT be deleted")

        let activeTxDescriptor = FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate<LedgerTransaction> { $0.deletedAt == nil }
        )
        let activeTransactions = try context.fetch(activeTxDescriptor)
        XCTAssertEqual(activeTransactions.count, 1)
        XCTAssertEqual(activeTransactions.first?.id, tx4.id)
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
