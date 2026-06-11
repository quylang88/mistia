import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaSyncTransactionConflictTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testSameDaySameAmountTransactionsWithDifferentIDsAreNotSyncIssues() throws {
        let wallet = makeWallet()
        let first = makeTransaction(
            title: "Lunch",
            amountMinor: 1_200,
            occurredAt: makeDate(year: 2026, month: 7, day: 10),
            wallet: wallet
        )
        let second = makeTransaction(
            title: "Lunch",
            amountMinor: 1_200,
            occurredAt: makeDate(year: 2026, month: 7, day: 10),
            wallet: wallet
        )

        let duplicates = MistiaSyncLocalStore.possibleDuplicateTransactions(from: [first, second])

        XCTAssertTrue(duplicates.isEmpty)
    }

    func testDebtTransactionsWithDifferentCounterpartiesAreNotSyncIssues() throws {
        let wallet = makeWallet()
        let first = makeTransaction(
            title: TransactionDebtIntent.lend.title,
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            amountMinor: 5_000,
            occurredAt: makeDate(year: 2026, month: 7, day: 10),
            wallet: wallet,
            counterpartyName: "Mai",
            normalizedCounterpartyKey: "mai"
        )
        let second = makeTransaction(
            title: TransactionDebtIntent.lend.title,
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            amountMinor: 5_000,
            occurredAt: makeDate(year: 2026, month: 7, day: 10),
            wallet: wallet,
            counterpartyName: "An",
            normalizedCounterpartyKey: "an"
        )

        let duplicates = MistiaSyncLocalStore.possibleDuplicateTransactions(from: [first, second])

        XCTAssertTrue(duplicates.isEmpty)
    }

    func testSameIDRemoteTransactionDifferenceCreatesSyncConflict() throws {
        let userID = UUID()
        let transactionID = UUID()
        let wallet = makeWallet()
        let container = try makeContainer()
        let context = ModelContext(container)
        let localUpdatedAt = makeDate(year: 2026, month: 7, day: 10).addingTimeInterval(3_600)
        let remoteUpdatedAt = makeDate(year: 2026, month: 7, day: 10)
        let local = makeTransaction(
            id: transactionID,
            title: "Local title",
            amountMinor: 1_200,
            occurredAt: remoteUpdatedAt,
            updatedAt: localUpdatedAt,
            remoteVersion: 1,
            wallet: wallet
        )
        context.insert(wallet)
        context.insert(local)
        try context.save()

        let remote = try makeRemoteTransaction(
            userID: userID,
            id: transactionID,
            title: "Cloud title",
            amountMinor: 1_200,
            walletID: wallet.id,
            occurredAt: remoteUpdatedAt,
            updatedAt: remoteUpdatedAt,
            syncVersion: 2
        )

        try MistiaSyncLocalStore.mergeAccessibleTransactions(
            [remote],
            protectedRecordIDs: [],
            preserveLocalNewerRows: true,
            in: container
        )

        let conflicts = try ModelContext(container).fetch(FetchDescriptor<SyncConflict>())
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.entity, .transaction)
        XCTAssertEqual(conflicts.first?.recordID, transactionID)
    }

    func testRecurringBillPauseFieldsRoundTripThroughSyncSnapshot() throws {
        let userID = UUID()
        let billID = UUID()
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.insert(
            RecurringBillPlan(
                id: billID,
                name: "Gym",
                iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
                amountMinor: 9_000,
                dueDay: 5,
                scheduleKind: .recurring,
                paymentStartDay: 5,
                firstScheduledMonth: makeDate(year: 2026, month: 1, day: 1),
                isPaused: true,
                pausedAt: makeDate(year: 2026, month: 2, day: 12),
                resumeStartMonth: makeDate(year: 2026, month: 7, day: 1),
                createdAt: makeDate(year: 2026, month: 1, day: 1),
                updatedAt: makeDate(year: 2026, month: 2, day: 12)
            )
        )
        try sourceContext.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshot(for: userID, from: sourceContainer)
        let remoteBill = try XCTUnwrap(snapshot.recurringBillPlans.first)
        XCTAssertTrue(remoteBill.isPaused)
        XCTAssertEqual(remoteBill.pausedAt, makeDate(year: 2026, month: 2, day: 12))
        XCTAssertEqual(remoteBill.resumeStartMonth, makeDate(year: 2026, month: 7, day: 1))

        let targetContainer = try makeContainer()
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: targetContainer
        )

        let restoredBills = try ModelContext(targetContainer).fetch(FetchDescriptor<RecurringBillPlan>())
        let restoredBill = try XCTUnwrap(restoredBills.first)
        XCTAssertTrue(restoredBill.isPaused)
        XCTAssertEqual(restoredBill.pausedAt, makeDate(year: 2026, month: 2, day: 12))
        XCTAssertEqual(restoredBill.resumeStartMonth, makeDate(year: 2026, month: 7, day: 1))
    }

    func testSettlementModelsAndTransactionReportingFieldsRoundTripThroughSyncSnapshot() throws {
        let userID = UUID()
        let wallet = makeWallet()
        let groupID = UUID()
        let obligationID = UUID()
        let transactionID = UUID()
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let occurredAt = makeDate(year: 2026, month: 7, day: 10)

        let group = SettlementGroup(
            id: groupID,
            kind: .resale,
            status: .open,
            title: "Camera resale",
            currencyCode: "JPY",
            occurredAt: occurredAt,
            totalMinor: 1_000,
            expectedMinor: 1_500,
            settledMinor: 0,
            organizerUserID: userID,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
        let obligation = SettlementObligation(
            id: obligationID,
            groupID: groupID,
            counterpartyName: "Buyer",
            normalizedCounterpartyKey: "buyer",
            direction: .receivable,
            expectedMinor: 1_500,
            preferredWalletID: wallet.id,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
        let transaction = LedgerTransaction(
            id: transactionID,
            primaryKind: .income,
            title: "Payment",
            amountMinor: 1_500,
            settlementGroupID: groupID,
            settlementObligationID: obligationID,
            settlementRole: .resaleReceipt,
            reportingExpenseMinor: -1_000,
            reportingIncomeMinor: 500,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            updatedAt: occurredAt,
            sourceWallet: wallet
        )

        sourceContext.insert(wallet)
        sourceContext.insert(group)
        sourceContext.insert(obligation)
        sourceContext.insert(transaction)
        try sourceContext.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshot(for: userID, from: sourceContainer)
        XCTAssertEqual(snapshot.settlementGroups.first?.id, groupID)
        XCTAssertEqual(snapshot.settlementObligations.first?.id, obligationID)
        XCTAssertEqual(snapshot.transactions.first?.settlementRoleRawValue, SettlementTransactionRole.resaleReceipt.rawValue)
        XCTAssertEqual(snapshot.transactions.first?.reportingExpenseMinor, -1_000)
        XCTAssertEqual(snapshot.transactions.first?.reportingIncomeMinor, 500)

        let targetContainer = try makeContainer()
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: targetContainer
        )

        let targetContext = ModelContext(targetContainer)
        let restoredGroup = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<SettlementGroup>()).first)
        let restoredObligation = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<SettlementObligation>()).first)
        let restoredTransaction = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<LedgerTransaction>()).first)

        XCTAssertEqual(restoredGroup.id, groupID)
        XCTAssertEqual(restoredGroup.kind, .resale)
        XCTAssertEqual(restoredObligation.groupID, groupID)
        XCTAssertEqual(restoredObligation.direction, .receivable)
        XCTAssertEqual(restoredTransaction.settlementGroupID, groupID)
        XCTAssertEqual(restoredTransaction.settlementObligationID, obligationID)
        XCTAssertEqual(restoredTransaction.settlementRole, .resaleReceipt)
        XCTAssertEqual(restoredTransaction.reportingExpenseMinor, -1_000)
        XCTAssertEqual(restoredTransaction.reportingIncomeMinor, 500)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeWallet() -> LedgerWallet {
        LedgerWallet(
            name: "Cash",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            currencyCode: "JPY"
        )
    }

    private func makeTransaction(
        id: UUID = UUID(),
        title: String,
        primaryKind: TransactionPrimaryKind = .expense,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        amountMinor: Int64,
        occurredAt: Date,
        updatedAt: Date? = nil,
        remoteVersion: Int64 = 0,
        wallet: LedgerWallet,
        counterpartyName: String? = nil,
        normalizedCounterpartyKey: String? = nil
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            title: title,
            amountMinor: amountMinor,
            sourceCurrencyCode: wallet.currencyCode,
            occurredAt: occurredAt,
            updatedAt: updatedAt ?? occurredAt,
            remoteVersion: remoteVersion,
            sourceWallet: wallet,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
    }

    private func makeRemoteTransaction(
        userID: UUID,
        id: UUID,
        title: String,
        amountMinor: Int64,
        walletID: UUID,
        occurredAt: Date,
        updatedAt: Date,
        syncVersion: Int64
    ) throws -> RemoteLedgerTransaction {
        let createdAt = MistiaISO8601DateCoding.stringWithFractionalSeconds(from: occurredAt)
        let updatedAt = MistiaISO8601DateCoding.stringWithFractionalSeconds(from: updatedAt)
        let payload = """
        {
          "user_id": "\(userID.uuidString)",
          "id": "\(id.uuidString)",
          "primary_kind_raw_value": "\(TransactionPrimaryKind.expense.rawValue)",
          "entry_status_raw_value": "\(TransactionEntryStatus.posted.rawValue)",
          "title": "\(title)",
          "amount_minor": \(amountMinor),
          "source_currency_code": "JPY",
          "occurred_at": "\(createdAt)",
          "created_at": "\(createdAt)",
          "updated_at": "\(updatedAt)",
          "created_by_user_id": "\(userID.uuidString)",
          "last_modified_by_user_id": "\(userID.uuidString)",
          "source_wallet_id": "\(walletID.uuidString)",
          "is_archived": false,
          "sync_version": \(syncVersion)
        }
        """
        return try JSONDecoder.mistiaRemoteAPIDecoder.decode(
            RemoteLedgerTransaction.self,
            from: Data(payload.utf8)
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
