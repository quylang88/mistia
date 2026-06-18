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

    func testOlderRemoteArchivedSettlementGroupDoesNotOverrideNewerLocalRestore() throws {
        let userID = UUID()
        let groupID = UUID()
        let container = try makeContainer()
        let context = ModelContext(container)
        let remoteUpdatedAt = makeDate(year: 2026, month: 7, day: 10)
        let localUpdatedAt = remoteUpdatedAt.addingTimeInterval(3_600)
        let archivedAt = remoteUpdatedAt.addingTimeInterval(120)
        let group = SettlementGroup(
            id: groupID,
            kind: .sharedExpense,
            status: .preparing,
            title: "Trip",
            currencyCode: "JPY",
            occurredAt: remoteUpdatedAt,
            totalMinor: 12_000,
            expectedMinor: 0,
            settledMinor: 0,
            organizerUserID: userID,
            createdAt: remoteUpdatedAt,
            updatedAt: localUpdatedAt,
            remoteVersion: 1,
            isArchived: false,
            archivedAt: nil
        )
        context.insert(group)
        try context.save()

        let staleRemoteSnapshot = MistiaRemoteSnapshot(
            wallets: [],
            creditCardProfiles: [],
            categories: [],
            settlementGroups: [
                RemoteSettlementGroup(
                    userID: userID,
                    id: groupID,
                    kindRawValue: SettlementKind.sharedExpense.rawValue,
                    statusRawValue: SettlementStatus.preparing.rawValue,
                    title: "Trip",
                    currencyCode: "JPY",
                    occurredAt: remoteUpdatedAt,
                    totalMinor: 12_000,
                    expectedMinor: 0,
                    settledMinor: 0,
                    organizerUserID: userID,
                    note: nil,
                    createdAt: remoteUpdatedAt,
                    updatedAt: remoteUpdatedAt,
                    deletedAt: nil,
                    isArchived: true,
                    archivedAt: archivedAt,
                    syncVersion: 2,
                    lastModifiedByDeviceID: nil
                )
            ],
            transactions: [],
            budgetPlans: [],
            savingsGoals: [],
            recurringBillPlans: [],
            installmentPlans: [],
            dueOccurrences: []
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            staleRemoteSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            preserveLocalNewerRows: true,
            in: container
        )

        let restoredGroup = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<SettlementGroup>()).first)
        XCTAssertFalse(restoredGroup.isArchived)
        XCTAssertNil(restoredGroup.archivedAt)
        XCTAssertEqual(restoredGroup.updatedAt, localUpdatedAt)
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
        let participantID = UUID()
        let transactionID = UUID()
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let occurredAt = makeDate(year: 2026, month: 7, day: 10)

        let group = SettlementGroup(
            id: groupID,
            kind: .sharedExpense,
            status: .open,
            title: "Dinner split",
            currencyCode: "JPY",
            occurredAt: occurredAt,
            totalMinor: 3_000,
            expectedMinor: 1_500,
            settledMinor: 0,
            organizerUserID: userID,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
        let participant = SettlementParticipant(
            id: participantID,
            groupID: groupID,
            displayName: "Friend",
            normalizedKey: "friend",
            memberUserID: nil,
            isSelf: false,
            sortOrder: 1,
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
        let transaction = LedgerTransaction(
            id: transactionID,
            primaryKind: .income,
            title: "Shared expense receipt",
            amountMinor: 1_500,
            settlementGroupID: groupID,
            settlementRole: .sharedExpenseReceipt,
            reportingExpenseMinor: -1_500,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            updatedAt: occurredAt,
            sourceWallet: wallet
        )

        sourceContext.insert(wallet)
        sourceContext.insert(group)
        sourceContext.insert(participant)
        sourceContext.insert(transaction)
        try sourceContext.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshot(for: userID, from: sourceContainer)
        XCTAssertEqual(snapshot.settlementGroups.first?.id, groupID)
        XCTAssertEqual(snapshot.settlementParticipants.first?.id, participantID)
        XCTAssertEqual(snapshot.transactions.first?.settlementRoleRawValue, SettlementTransactionRole.sharedExpenseReceipt.rawValue)
        XCTAssertEqual(snapshot.transactions.first?.reportingExpenseMinor, -1_500)
        XCTAssertEqual(snapshot.transactions.first?.reportingIncomeMinor, 0)

        let targetContainer = try makeContainer()
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: targetContainer
        )

        let targetContext = ModelContext(targetContainer)
        let restoredGroup = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<SettlementGroup>()).first)
        let restoredParticipant = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<SettlementParticipant>()).first)
        let restoredTransaction = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<LedgerTransaction>()).first)

        XCTAssertEqual(restoredGroup.id, groupID)
        XCTAssertEqual(restoredGroup.kind, .sharedExpense)
        XCTAssertEqual(restoredParticipant.groupID, groupID)
        XCTAssertEqual(restoredParticipant.displayName, "Friend")
        XCTAssertFalse(restoredParticipant.isSelf)
        XCTAssertEqual(restoredTransaction.settlementGroupID, groupID)
        XCTAssertNil(restoredTransaction.settlementObligationID)
        XCTAssertEqual(restoredTransaction.settlementRole, .sharedExpenseReceipt)
        XCTAssertEqual(restoredTransaction.reportingExpenseMinor, -1_500)
        XCTAssertEqual(restoredTransaction.reportingIncomeMinor, 0)
    }

    func testArchivedEventSyncHidesGeneratedRowsWithoutArchivingTransactions() throws {
        let userID = UUID()
        let groupID = UUID()
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let wallet = makeWallet()
        let occurredAt = makeDate(year: 2026, month: 7, day: 10)
        let archivedAt = occurredAt.addingTimeInterval(600)
        let group = SettlementGroup(
            id: groupID,
            kind: .sharedExpense,
            status: .settled,
            title: "Dinner split",
            currencyCode: "JPY",
            occurredAt: occurredAt,
            totalMinor: 10_000,
            expectedMinor: 4_000,
            settledMinor: 0,
            organizerUserID: userID,
            createdAt: occurredAt,
            updatedAt: archivedAt,
            isArchived: true,
            archivedAt: archivedAt
        )
        let linkedBill = makeTransaction(
            title: "Dinner",
            amountMinor: 10_000,
            occurredAt: occurredAt,
            updatedAt: occurredAt,
            wallet: wallet
        )
        linkedBill.settlementGroupID = groupID
        linkedBill.settlementRole = .sharedExpensePaid
        let generatedDebt = makeTransaction(
            title: "Split payable",
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            amountMinor: 4_000,
            occurredAt: occurredAt.addingTimeInterval(60),
            updatedAt: occurredAt.addingTimeInterval(60),
            wallet: wallet
        )
        generatedDebt.settlementGroupID = groupID
        generatedDebt.settlementRole = .sharedExpensePayable

        sourceContext.insert(wallet)
        sourceContext.insert(group)
        sourceContext.insert(linkedBill)
        sourceContext.insert(generatedDebt)
        try sourceContext.save()

        let snapshot = try MistiaSyncLocalStore.exportSnapshot(for: userID, from: sourceContainer)
        XCTAssertEqual(snapshot.settlementGroups.first?.isArchived, true)
        XCTAssertEqual(snapshot.transactions.count, 2)
        XCTAssertTrue(snapshot.transactions.allSatisfy { !$0.isArchived })

        let targetContainer = try makeContainer()
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: [],
            in: targetContainer
        )

        let targetContext = ModelContext(targetContainer)
        let restoredGroup = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<SettlementGroup>()).first)
        let restoredTransactions = try targetContext.fetch(FetchDescriptor<LedgerTransaction>())
        let archivedEventIDs = SettlementLogic.archivedSharedExpenseEventIDs(from: [restoredGroup.recordSnapshot])
        let visibleRecords = SettlementLogic.visibleRecordsAfterEventArchiveFiltering(
            restoredTransactions.map(\.snapshot),
            archivedEventIDs: archivedEventIDs
        )

        XCTAssertTrue(restoredGroup.isArchived)
        XCTAssertEqual(restoredTransactions.count, 2)
        XCTAssertTrue(restoredTransactions.allSatisfy { !$0.isArchived })
        XCTAssertEqual(visibleRecords.map(\.id), [linkedBill.id])
    }

    func testDiagnosticSettlementRoles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let wallet = makeWallet()
        context.insert(wallet)

        let tx = LedgerTransaction(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            title: "Test Payable",
            amountMinor: 2000,
            settlementGroupID: UUID(),
            settlementRole: .sharedExpensePayable,
            occurredAt: Date(),
            sourceWallet: nil
        )
        context.insert(tx)
        try context.save()

        // Fetch it back
        let fetched = try context.fetch(FetchDescriptor<LedgerTransaction>()).first!
        XCTAssertEqual(fetched.settlementRole, .sharedExpensePayable)

        // Simulate importing back via JSON
        let userID = UUID()
        let transactionID = UUID()
        let groupID = UUID()
        let occurredAtString = MistiaISO8601DateCoding.stringWithFractionalSeconds(from: Date())
        let jsonPayload = """
        {
          "user_id": "\(userID.uuidString)",
          "id": "\(transactionID.uuidString)",
          "primary_kind_raw_value": "transfer",
          "transfer_subtype_raw_value": "debt",
          "debt_intent_raw_value": "borrow",
          "entry_status_raw_value": "posted",
          "title": "Test suggestion",
          "amount_minor": 2000,
          "occurred_at": "\(occurredAtString)",
          "created_at": "\(occurredAtString)",
          "updated_at": "\(occurredAtString)",
          "created_by_user_id": "\(userID.uuidString)",
          "last_modified_by_user_id": "\(userID.uuidString)",
          "settlement_group_id": "\(groupID.uuidString)",
          "settlement_role_raw_value": "sharedExpensePayable",
          "is_archived": false,
          "sync_version": 1
        }
        """

        let decodedRow = try JSONDecoder.mistiaRemoteAPIDecoder.decode(RemoteLedgerTransaction.self, from: Data(jsonPayload.utf8))
        XCTAssertEqual(decodedRow.settlementRoleRawValue, "sharedExpensePayable")

        let targetContainer = try makeContainer()
        let targetContext = ModelContext(targetContainer)

        try MistiaSyncLocalStore.mergeAccessibleTransactions(
            [decodedRow],
            protectedRecordIDs: [],
            in: targetContainer
        )

        let targetFetched = try targetContext.fetch(FetchDescriptor<LedgerTransaction>()).first!
        XCTAssertEqual(targetFetched.settlementRole, .sharedExpensePayable)
    }

    func testDiagnosticSettlementFinalizationReload() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let userID = UUID()
        let groupID = UUID()
        let group = SettlementGroup(
            kind: .sharedExpense,
            status: .preparing,
            title: "Trip",
            currencyCode: "VND",
            occurredAt: Date(),
            totalMinor: 100_000,
            expectedMinor: 0,
            organizerUserID: userID
        )
        context.insert(group)

        // Link a bill
        let wallet = makeWallet()
        context.insert(wallet)
        let bill = LedgerTransaction(
            id: UUID(),
            primaryKind: .expense,
            title: "Dinner",
            amountMinor: 100_000,
            settlementGroupID: groupID,
            settlementRole: .sharedExpensePaid,
            occurredAt: Date(),
            sourceWallet: wallet
        )
        context.insert(bill)

        // Finalize split would create a suggestion
        // Let's create a payable suggestion manually to simulate finalization
        let payableSuggestion = LedgerTransaction(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            title: "Vay",
            amountMinor: 50_000,
            settlementGroupID: groupID,
            settlementRole: .sharedExpensePayable,
            occurredAt: Date(),
            sourceWallet: nil
        )
        context.insert(payableSuggestion)

        try context.save()

        // Now, let's create a new model context from the same container (simulating reload/reopen)
        let newContext = ModelContext(container)
        let allTransactions = try newContext.fetch(FetchDescriptor<LedgerTransaction>())

        // Filter like linkedBills does:
        let linkedBills = allTransactions.filter {
            $0.settlementGroupID == groupID
                && $0.settlementRole == .sharedExpensePaid
                && $0.entryStatus == .posted
        }

        // Total paid should be 100_000, not 150_000!
        XCTAssertEqual(linkedBills.count, 1)
        XCTAssertEqual(linkedBills.first?.id, bill.id)

        let totalPaid = linkedBills.reduce(Int64.zero) { $0 + max($1.amountMinor, 0) }
        XCTAssertEqual(totalPaid, 100_000)
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
