import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class FamilyWalletSpendingTests: XCTestCase {
    func testFamilyMoneyCanBeSpentRegardlessOfExpenseDate() throws {
        let fixture = try makeFixture()
        let balance = try InvestmentPersistenceService.currentBalance(
            wallet: fixture.wallet,
            context: fixture.context
        )
        XCTAssertEqual(balance, 9_340)

        for occurredAt in [fixture.start.addingTimeInterval(-86_400), fixture.start,
                           fixture.start.addingTimeInterval(86_400)] {
            for amount: Int64 in [1_800, 9_340, 9_341] {
                let preview = try InvestmentPersistenceService.fundUsageChangePreview(
                    ownerUserID: fixture.ownerID,
                    wallet: fixture.wallet,
                    requestedMinor: amount,
                    visibleWalletBalanceMinor: balance,
                    transactionID: nil,
                    occurredAt: occurredAt,
                    orderingCreatedAt: fixture.start.addingTimeInterval(86_400),
                    context: fixture.context
                )
                XCTAssertEqual(
                    preview.proposed.outcome,
                    amount <= balance ? .ordinaryFundsOnly : .insufficientFunds
                )
                XCTAssertEqual(preview.proposedInvestmentToUseMinor, 0)
            }
        }
    }

    func testBackdatedExpensePersistsAndEditsAgainstRemainingFamilyMoney() throws {
        let fixture = try makeFixture()
        let expense = LedgerTransaction(
            primaryKind: .expense,
            title: "Expense",
            amountMinor: 1_800,
            sourceCurrencyCode: "JPY",
            occurredAt: fixture.start.addingTimeInterval(-86_400),
            createdAt: fixture.start.addingTimeInterval(86_400),
            sourceWallet: fixture.wallet
        )
        fixture.context.insert(expense)
        try MistiaRecordOwnershipStore.upsert(
            entity: .transaction,
            recordID: expense.id,
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
        let reconciliation = try InvestmentPersistenceService.reconcileFundUsageTimeline(
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
        XCTAssertTrue(reconciliation.postingIDs.isEmpty)
        XCTAssertEqual(
            try InvestmentPersistenceService.currentBalance(wallet: fixture.wallet, context: fixture.context),
            7_540
        )

        let newExpense = try InvestmentPersistenceService.fundUsageChangePreview(
            ownerUserID: fixture.ownerID,
            wallet: fixture.wallet,
            requestedMinor: 7_541,
            visibleWalletBalanceMinor: 7_540,
            transactionID: nil,
            occurredAt: fixture.start.addingTimeInterval(86_400),
            context: fixture.context
        )
        XCTAssertEqual(newExpense.proposed.outcome, .insufficientFunds)

        let balanceBeforeEdit = try InvestmentPersistenceService.currentBalance(
            wallet: fixture.wallet,
            excludingTransactionIDs: [expense.id],
            context: fixture.context
        )
        let edit = try InvestmentPersistenceService.fundUsageChangePreview(
            ownerUserID: fixture.ownerID,
            wallet: fixture.wallet,
            requestedMinor: 9_340,
            visibleWalletBalanceMinor: balanceBeforeEdit,
            transactionID: expense.id,
            occurredAt: expense.occurredAt,
            orderingCreatedAt: expense.createdAt,
            context: fixture.context
        )
        XCTAssertEqual(edit.proposed.outcome, .ordinaryFundsOnly)
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let ownerID: UUID
        let wallet: LedgerWallet
        let start: Date
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let ownerID = UUID()
        let senderID = UUID()
        let start = Date(timeIntervalSince1970: 1_788_732_000)
        let wallet = LedgerWallet(
            name: "PayPay", kind: .payPay, iconSymbolName: "wallet.pass.fill",
            iconColorHex: "#000000", currencyCode: "JPY", openingBalanceMinor: 360
        )
        let sender = LedgerWallet(
            name: "Sender", kind: .bank, iconSymbolName: "building.columns.fill",
            iconColorHex: "#000000", currencyCode: "JPY", openingBalanceMinor: 20_000
        )
        for (model, owner) in [(wallet, ownerID), (sender, senderID)] {
            context.insert(model)
            try MistiaRecordOwnershipStore.upsert(
                entity: .wallet, recordID: model.id, ownerUserID: owner, context: context
            )
        }
        // An Investment wallet exists, while the receiving wallet holds ordinary cash.
        _ = try InvestmentPersistenceService.createChannel(
            ownerUserID: ownerID, name: "Shop", iconSymbolName: "storefront.fill",
            iconColorHex: "#000000", primaryCurrencyCode: "JPY", context: context
        )
        let previousExpense = LedgerTransaction(
            primaryKind: .expense, title: "Earlier expense", amountMinor: 840,
            occurredAt: start.addingTimeInterval(60), sourceWallet: wallet
        )
        context.insert(previousExpense)
        try MistiaRecordOwnershipStore.upsert(
            entity: .transaction, recordID: previousExpense.id, ownerUserID: ownerID, context: context
        )
        for (index, amount) in [Int64(2_000), 620, 7_200].enumerated() {
            let date = start.addingTimeInterval(Double(index + 2) * 60)
            // Match the RPC: sender and recipient have separate ledger rows.
            let outgoing = LedgerTransaction(
                primaryKind: .transfer, transferSubtype: .familyTransfer,
                title: "Sent", amountMinor: amount, occurredAt: date, createdAt: date,
                sourceWallet: sender, destinationWallet: wallet
            )
            let incoming = LedgerTransaction(
                primaryKind: .transfer, transferSubtype: .familyTransfer,
                title: "Received", amountMinor: amount, occurredAt: date, createdAt: date,
                sourceWallet: wallet
            )
            for (transaction, owner) in [(outgoing, senderID), (incoming, ownerID)] {
                context.insert(transaction)
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction, recordID: transaction.id,
                    ownerUserID: owner, context: context
                )
            }
        }
        try context.save()
        return Fixture(container: container, context: context, ownerID: ownerID, wallet: wallet, start: start)
    }
}
