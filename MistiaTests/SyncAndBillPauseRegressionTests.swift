import Foundation
import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class SyncAndBillPauseRegressionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

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

    func testPausedRecurringBillDoesNotProduceDueItems() {
        let bill = makeBill(
            isPaused: true,
            resumeStartMonth: nil
        )

        let items = PlanningLogic.recurringBillDueItems(
            bills: [bill],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 7, day: 1),
            calendar: calendar
        )

        XCTAssertTrue(items.isEmpty)
    }

    func testResumedRecurringBillSkipsPausedMonthsAndRestartsInResumeMonth() {
        let bill = makeBill(
            isPaused: false,
            resumeStartMonth: makeDate(year: 2026, month: 7, day: 1)
        )

        let juneItems = PlanningLogic.recurringBillDueItems(
            bills: [bill],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 6, day: 1),
            calendar: calendar
        )
        let julyItems = PlanningLogic.recurringBillDueItems(
            bills: [bill],
            occurrences: [],
            selectedMonth: makeDate(year: 2026, month: 7, day: 1),
            calendar: calendar
        )

        XCTAssertTrue(juneItems.isEmpty)
        XCTAssertEqual(julyItems.count, 1)
        XCTAssertEqual(julyItems.first?.paymentStartDate, makeDate(year: 2026, month: 7, day: 5))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
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

    private func makeBill(
        isPaused: Bool,
        resumeStartMonth: Date?
    ) -> PlanningBillSnapshot {
        PlanningBillSnapshot(
            id: UUID(),
            name: "Gym",
            iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
            categorySystemKey: .billing,
            amountMinor: 9_000,
            dueDay: 5,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 1, day: 1),
            scheduleKind: .recurring,
            paymentStartDay: 5,
            paymentStartDate: nil,
            firstScheduledMonth: makeDate(year: 2026, month: 1, day: 1),
            hasExplicitDueDate: false,
            dueDate: nil,
            autoPayEnabled: false,
            autoPayDay: nil,
            autoPayDate: nil,
            isPaused: isPaused,
            resumeStartMonth: resumeStartMonth
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
