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

        try MistiaSyncLocalStore.applyAccessibleFinanceSnapshot(
            MistiaRemoteSnapshot(
                wallets: [],
                creditCardProfiles: [],
                categories: [],
                settlementGroups: [],
                transactions: [remote],
                budgetPlans: [],
                savingsGoals: [],
                recurringBillPlans: [],
                installmentPlans: [],
                dueOccurrences: []
            ),
            protectedRecordIDs: [],
            familyCategoryScopedTo: userID,
            familyCategoryPruneOwnerIDs: [userID],
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

    func testPausedRecurringBillsSnapshotContainsOnlyPausedRecurringBills() {
        let activeBill = makeBill(name: "Active", isPaused: false, resumeStartMonth: nil)
        let pausedBill = makeBill(name: "Paused", isPaused: true, resumeStartMonth: nil)
        let oneTimeBill = makeBill(
            name: "One time",
            scheduleKind: .oneTime,
            isPaused: true,
            resumeStartMonth: nil
        )

        let pausedBills = PlanningLogic.pausedRecurringBills(
            from: [activeBill, pausedBill, oneTimeBill]
        )

        XCTAssertEqual(pausedBills.map(\.id), [pausedBill.id])
    }

    func testBillPauseResumeDialogCopyUsesCompactActionsAndDetailedMessages() {
        XCTAssertEqual(L10n.planning.planning.pauseBill, "Tạm dừng hóa đơn")
        XCTAssertEqual(L10n.planning.planning.pauseBillAction, "Tạm dừng")
        XCTAssertEqual(
            L10n.planning.planning.pauseBillMessage,
            "Hóa đơn này sẽ tạm dừng. Hóa đơn tạm dừng sẽ không xuất hiện trong khoản cần thanh toán, thông báo hoặc tự động thanh toán cho đến khi bắt đầu lại."
        )
        XCTAssertEqual(
            L10n.planning.planning.resumeBillMessage,
            "Hóa đơn này sẽ được tính trở lại từ tháng hiện tại."
        )
    }

    func testLegacyV4RecurringBillStoreOpensWithPauseDefaults() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let billID = UUID()
        try createLegacyV4BillStore(at: storeURL, billID: billID)

        let container = try openCurrentStore(at: storeURL)
        let bills = try ModelContext(container).fetch(FetchDescriptor<RecurringBillPlan>())

        XCTAssertEqual(bills.map(\.id), [billID])
        XCTAssertEqual(bills.first?.name, "Internet")
        XCTAssertFalse(bills.first?.isPaused ?? true)
        XCTAssertNil(bills.first?.pausedAt)
        XCTAssertNil(bills.first?.resumeStartMonth)
    }

    func testMigrationPlanIncludesFrozenLegacySchemasAndCurrentV6() {
        let schemaNames = MistiaMigrationPlan.schemas.map { String(reflecting: $0) }
        let v4ModelNames = MistiaSchemaV4.models.map { String(reflecting: $0) }
        let v5ModelNames = MistiaSchemaV5.models.map { String(reflecting: $0) }
        let v6ModelNames = MistiaSchemaV6.models.map { String(reflecting: $0) }

        XCTAssertEqual(schemaNames, [
            "Mistia.MistiaSchemaV4",
            "Mistia.MistiaSchemaV5",
            "Mistia.MistiaSchemaV6"
        ])
        XCTAssertEqual(MistiaMigrationPlan.stages.count, 1)
        XCTAssertTrue(v4ModelNames.contains("Mistia.MistiaSchemaV4Models.RecurringBillPlan"))
        XCTAssertFalse(v4ModelNames.contains("Mistia.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("Mistia.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("Mistia.MistiaSchemaV5Models.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("Mistia.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("Mistia.SettlementGroup"))
        XCTAssertTrue(v6ModelNames.contains("Mistia.SettlementObligation"))
    }

    func testLegacyV4EncodedPausedBillMigratesToPhysicalPauseColumns() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let billID = UUID()
        let pausedAt = makeDate(year: 2026, month: 2, day: 12)
        let resumeStartMonth = makeDate(year: 2026, month: 7, day: 1)
        try createLegacyV4EncodedPausedBillStore(
            at: storeURL,
            billID: billID,
            pausedAt: pausedAt,
            resumeStartMonth: resumeStartMonth
        )

        let container = try openCurrentStore(at: storeURL)
        let bills = try ModelContext(container).fetch(FetchDescriptor<RecurringBillPlan>())

        XCTAssertEqual(bills.map(\.id), [billID])
        XCTAssertEqual(bills.first?.scheduleKind, .recurring)
        XCTAssertTrue(bills.first?.isPaused ?? false)
        XCTAssertEqual(bills.first?.pausedAt, pausedAt)
        XCTAssertEqual(bills.first?.resumeStartMonth, resumeStartMonth)
        XCTAssertNil(bills.first?.paymentStartDate)
        XCTAssertNil(bills.first?.autoPayDate)
        XCTAssertTrue(try storeFileContains("ZISPAUSED", at: storeURL))
        XCTAssertTrue(try storeFileContains("ZPAUSEDAT", at: storeURL))
        XCTAssertTrue(try storeFileContains("ZRESUMESTARTMONTH", at: storeURL))

        let reopenedContainer = try openCurrentStore(at: storeURL)
        let reopenedBills = try ModelContext(reopenedContainer).fetch(FetchDescriptor<RecurringBillPlan>())
        XCTAssertEqual(reopenedBills.map(\.id), [billID])
        XCTAssertTrue(reopenedBills.first?.isPaused ?? false)
    }

    func testLegacyV4OneTimeBillPreservesPaymentAndAutoPayDates() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let billID = UUID()
        let paymentStartDate = makeDate(year: 2026, month: 7, day: 7)
        let autoPayDate = makeDate(year: 2026, month: 7, day: 8)
        try createLegacyV4OneTimeBillStore(
            at: storeURL,
            billID: billID,
            paymentStartDate: paymentStartDate,
            autoPayDate: autoPayDate
        )

        let container = try openCurrentStore(at: storeURL)
        let bills = try ModelContext(container).fetch(FetchDescriptor<RecurringBillPlan>())

        XCTAssertEqual(bills.map(\.id), [billID])
        XCTAssertEqual(bills.first?.scheduleKind, .oneTime)
        XCTAssertFalse(bills.first?.isPaused ?? true)
        XCTAssertNil(bills.first?.pausedAt)
        XCTAssertNil(bills.first?.resumeStartMonth)
        XCTAssertEqual(bills.first?.paymentStartDate, paymentStartDate)
        XCTAssertEqual(bills.first?.autoPayDate, autoPayDate)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func createLegacyV4BillStore(at storeURL: URL, billID: UUID) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            MistiaSchemaV4.RecurringBillPlan(
                id: billID,
                name: "Internet",
                iconSymbolName: "wifi",
                amountMinor: 4_200,
                dueDay: 12,
                frequencyMonths: 1
            )
        )
        try context.save()
    }

    private func createLegacyV4EncodedPausedBillStore(
        at storeURL: URL,
        billID: UUID,
        pausedAt: Date,
        resumeStartMonth: Date
    ) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            MistiaSchemaV4.RecurringBillPlan(
                id: billID,
                name: "Internet",
                iconSymbolName: "wifi",
                amountMinor: 4_200,
                dueDay: 12,
                scheduleKindRawValue: recurringBillPausedScheduleKindRawValue,
                paymentStartDate: pausedAt,
                autoPayDate: resumeStartMonth,
                frequencyMonths: 1
            )
        )
        try context.save()
    }

    private func createLegacyV4OneTimeBillStore(
        at storeURL: URL,
        billID: UUID,
        paymentStartDate: Date,
        autoPayDate: Date
    ) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            MistiaSchemaV4.RecurringBillPlan(
                id: billID,
                name: "Doctor",
                iconSymbolName: "cross.case.fill",
                amountMinor: 8_000,
                dueDay: 8,
                scheduleKindRawValue: PlanningBillScheduleKind.oneTime.rawValue,
                paymentStartDate: paymentStartDate,
                hasExplicitDueDate: false,
                autoPayEnabled: true,
                autoPayDate: autoPayDate,
                frequencyMonths: 1
            )
        )
        try context.save()
    }

    private func openCurrentStore(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        return try MistiaDataStack.LaunchState.openContainer(
            schema: schema,
            configuration: configuration,
            storeURL: storeURL,
            fileManager: .default
        )
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
        id: UUID = UUID(),
        name: String = "Gym",
        scheduleKind: PlanningBillScheduleKind = .recurring,
        isPaused: Bool,
        resumeStartMonth: Date?
    ) -> PlanningBillSnapshot {
        PlanningBillSnapshot(
            id: id,
            name: name,
            iconSymbolName: MistiaSystemCategoryKey.billing.iconSymbolName,
            categorySystemKey: .billing,
            amountMinor: 9_000,
            dueDay: 5,
            frequencyMonths: 1,
            paymentWalletID: UUID(),
            currencyCode: "JPY",
            createdAt: makeDate(year: 2026, month: 1, day: 1),
            scheduleKind: scheduleKind,
            paymentStartDay: 5,
            paymentStartDate: scheduleKind == .oneTime ? makeDate(year: 2026, month: 7, day: 5) : nil,
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

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "mistia-bill-pause-migration-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("store")
    }

    private func removeStoreArtifacts(at storeURL: URL) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func storeFileContains(_ text: String, at storeURL: URL) throws -> Bool {
        let data = try Data(contentsOf: storeURL)
        return String(decoding: data, as: UTF8.self).contains(text)
    }
}
