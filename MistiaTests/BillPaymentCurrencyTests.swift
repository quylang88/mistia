import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class BillPaymentCurrencyTests: XCTestCase {
    func testAutoPayDifferentCurrencyCreatesNoLedgerOrPaidOccurrence() async throws {
        let notificationKeys = [MistiaAppStorageKey.notificationsEnabled, MistiaAppStorageKey.notificationsGroupRemindersEnabled, MistiaNotificationReminderKind.bills.storageKey]
        let previous = notificationKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        notificationKeys.forEach { UserDefaults.standard.set(true, forKey: $0) }
        defer { previous.forEach { key, value in
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        } }
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let owner = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let wallet = LedgerWallet(name: "JPY cash", kind: .cash, iconSymbolName: "wallet.pass.fill", iconColorHex: "#A673FA", currencyCode: "JPY", openingBalanceMinor: 100_000)
        let bill = RecurringBillPlan(name: "VND bill", iconSymbolName: "mistia.plan.bill", amountMinor: 500, dueDay: 13,
                                     paymentStartDay: 13, autoPayEnabled: true, autoPayDay: 13, paymentWallet: wallet, currencyCode: "VND", createdAt: now, updatedAt: now)
        context.insert(wallet); context.insert(bill)
        try context.save()
        let suite = "BillPaymentCurrencyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionStore(modelContainer: container, userDefaults: defaults,
                                   connectivityMonitor: SessionConnectivityMonitor(initialStatus: .disconnected), registerBackgroundRefresh: false)
        let snapshot = MistiaDueMaintenanceSnapshot(
            activeUserID: owner, storedWallets: [wallet], storedTransactions: [], storedOccurrences: [], storedBudgets: [], storedCategories: [], storedBills: [bill], ownershipScopes: [],
            walletOwnerMap: [wallet.id: owner], transactionOwnerMap: [:], occurrenceOwnerMap: [:], billOwnerMap: [bill.id: owner], budgetOwnerMap: [:],
            activeWallets: [wallet], activeTransactions: [], activeOccurrences: [], activeBudgets: [], activeBills: [bill], activeTransactionRecords: [],
            familyBudgetTransactions: [], familyBudgetSpendingAvailable: false, activeOccurrenceSnapshots: [], walletByID: [wallet.id: wallet],
            balanceIndex: TransactionWalletBalanceIndex(balancesByWalletID: [wallet.id: 100_000])
        )
        await MistiaRecurringBillMaintenance.run(snapshot: snapshot, modelContext: context, sessionStore: session, referenceDate: now, calendar: calendar)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DueOccurrenceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AppNotificationRecord>()).contains { $0.kindRawValue == "billAutoPaymentFailed" })
    }
    func testManualPaymentDifferentCurrencyFailsBeforeAnyMoneyOrOwnershipWrite() throws {
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let now = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!
        let wallet = LedgerWallet(name: "JPY cash", kind: .cash, iconSymbolName: "wallet.pass.fill", iconColorHex: "#A673FA", currencyCode: "JPY", openingBalanceMinor: 100_000)
        let bill = RecurringBillPlan(name: "VND bill", iconSymbolName: "mistia.plan.bill", amountMinor: 500, dueDay: 13, paymentWallet: wallet, currencyCode: "VND")
        context.insert(wallet); context.insert(bill); try context.save()
        let draft = PlanningDuePaymentDraft(primaryKind: .expense, transferSubtype: nil, title: bill.name, amountMinor: 500, sourceWalletID: wallet.id, destinationWalletID: nil, categorySystemKey: .billing)
        XCTAssertThrowsError(try PlanningPersistenceSupport.saveDuePayment(draft: draft, sourceKind: .recurringBill, sourceID: bill.id, selectedMonth: now, scheduledDate: now,
            wallets: [wallet], occurrences: [], modelContext: context, actorUserID: UUID())) { error in
            XCTAssertEqual(error as? PlanningDuePaymentError, .billCurrencyMismatch)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DueOccurrenceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OwnedRecordScope>()).isEmpty)
    }

}
