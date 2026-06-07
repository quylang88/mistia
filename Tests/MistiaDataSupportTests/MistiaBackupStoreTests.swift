import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaBackupStoreTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func tearDownWithError() throws {
        try removeDirectoryIfPresent(backupDirectoryURL())
        try removeDirectoryIfPresent(avatarDirectoryURL())
    }

    func testBackupExportAndReplaceRestoreRoundTripsAllSupportedEntities() throws {
        let ownerUserID = UUID()
        let secondOwnerUserID = UUID()
        let sourceContainer = try makeContainer()
        let fixture = try seedComprehensiveFixture(
            in: sourceContainer,
            ownerUserID: ownerUserID,
            secondOwnerUserID: secondOwnerUserID
        )

        let export = try MistiaBackupStore.exportBackup(
            from: sourceContainer,
            fallbackOwnerUserID: ownerUserID,
            appVersion: "1.0.0",
            appBuild: "100"
        )
        let validation = try MistiaBackupStore.validateBackup(export.data)

        XCTAssertEqual(validation.walletCount, 3)
        XCTAssertEqual(validation.creditCardProfileCount, 1)
        XCTAssertEqual(validation.categoryCount, 2)
        XCTAssertEqual(validation.transactionCount, 1)
        XCTAssertEqual(validation.budgetPlanCount, 1)
        XCTAssertEqual(validation.savingsGoalCount, 1)
        XCTAssertEqual(validation.recurringBillPlanCount, 1)
        XCTAssertEqual(validation.installmentPlanCount, 1)
        XCTAssertEqual(validation.dueOccurrenceCount, 1)
        XCTAssertEqual(validation.userProfileCount, 2)
        XCTAssertEqual(validation.ownershipScopeCount, 12)
        XCTAssertEqual(validation.transactionAuditCount, 1)
        XCTAssertEqual(validation.avatarAssetCount, 1)

        let targetContainer = try makeContainer()
        let extraContext = ModelContext(targetContainer)
        extraContext.insert(
            LedgerWallet(
                id: UUID(),
                name: "Transient wallet",
                kind: .cash,
                iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
                iconColorHex: LedgerWalletKind.cash.defaultColorHex,
                openingBalanceMinor: 999
            )
        )
        extraContext.insert(
            UserAccountProfile(
                userID: UUID(),
                email: "stale@example.com",
                displayName: "Stale profile"
            )
        )
        try extraContext.save()

        let outboxDefaults = try makeOutboxDefaults()
        let outbox = MistiaSyncOutbox(defaults: outboxDefaults, key: "replace-outbox")
        outbox.enqueue(
            MistiaSyncMutation(
                entity: .wallet,
                recordID: fixture.cashWalletID,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: makeDate(year: 2026, month: 4, day: 17)
            )
        )

        let restoreResult = try MistiaBackupStore.restoreBackup(
            export.data,
            mode: .replaceLocal,
            in: targetContainer,
            fallbackOwnerUserID: ownerUserID,
            outbox: outbox
        )

        XCTAssertEqual(outbox.allMutations.count, 0)
        XCTAssertEqual(restoreResult.summary.activeRecordCount, validation.activeRecordCount)
        XCTAssertNotNil(restoreResult.safetySnapshotURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoreResult.safetySnapshotURL!.path))

        let wallets = try fetchAll(LedgerWallet.self, in: targetContainer)
        XCTAssertEqual(Set(wallets.map(\.id)), fixture.expectedWalletIDs)
        XCTAssertEqual(wallets.first(where: { $0.id == fixture.cashWalletID })?.name, "Cash wallet")
        XCTAssertEqual(wallets.first(where: { $0.id == fixture.sharedFamilyWalletID })?.openingBalanceMinor, 48_000)

        let profiles = try fetchAll(CreditCardProfile.self, in: targetContainer)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.paymentSourceWallet?.id, fixture.cashWalletID)
        XCTAssertEqual(profiles.first?.autoPayEnabled, true)

        let categories = try fetchAll(TransactionCategory.self, in: targetContainer)
        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(
            categories.first(where: { $0.id == fixture.childCategoryID })?.parentCategory?.id,
            fixture.parentCategoryID
        )

        let transactions = try fetchAll(LedgerTransaction.self, in: targetContainer)
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.category?.id, fixture.childCategoryID)
        XCTAssertEqual(transactions.first?.sourceWallet?.id, fixture.cashWalletID)

        let budgets = try fetchAll(BudgetPlan.self, in: targetContainer)
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(budgets.first?.category?.id, fixture.childCategoryID)

        let goals = try fetchAll(SavingsGoal.self, in: targetContainer)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goals.first?.linkedWallet?.id, fixture.cashWalletID)

        let recurringBills = try fetchAll(RecurringBillPlan.self, in: targetContainer)
        XCTAssertEqual(recurringBills.count, 1)
        XCTAssertEqual(recurringBills.first?.category?.id, fixture.childCategoryID)
        XCTAssertEqual(recurringBills.first?.resolvedPaymentStartDay, 25)
        XCTAssertEqual(recurringBills.first?.dueDay, 10)
        XCTAssertEqual(recurringBills.first?.resolvedHasExplicitDueDate, true)
        XCTAssertEqual(recurringBills.first?.firstScheduledMonth, makeDate(year: 2026, month: 4, day: 1))
        XCTAssertEqual(recurringBills.first?.autoPayEnabled, true)
        XCTAssertEqual(recurringBills.first?.autoPayDay, 28)
        XCTAssertEqual(recurringBills.first?.isPaused, true)
        XCTAssertEqual(recurringBills.first?.pausedAt, makeDate(year: 2026, month: 4, day: 20))
        XCTAssertEqual(recurringBills.first?.resumeStartMonth, makeDate(year: 2026, month: 7, day: 1))

        let installments = try fetchAll(InstallmentPlan.self, in: targetContainer)
        XCTAssertEqual(installments.count, 1)
        XCTAssertEqual(installments.first?.paymentWallet?.id, fixture.cashWalletID)

        let occurrences = try fetchAll(DueOccurrenceRecord.self, in: targetContainer)
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.sourceID, fixture.recurringBillID)
        XCTAssertEqual(occurrences.first?.linkedTransactionID, fixture.transactionID)

        let accountProfiles = try fetchAll(UserAccountProfile.self, in: targetContainer)
        XCTAssertEqual(accountProfiles.count, 2)
        XCTAssertEqual(accountProfiles.first(where: { $0.userID == ownerUserID })?.displayName, "Owner One")
        XCTAssertEqual(accountProfiles.first(where: { $0.userID == ownerUserID })?.avatarFileName, fixture.avatarFileName)

        let ownershipScopes = try fetchAll(OwnedRecordScope.self, in: targetContainer)
        XCTAssertEqual(ownershipScopes.count, 12)
        XCTAssertEqual(
            ownershipScopes.first(where: { $0.recordID == fixture.sharedFamilyWalletID })?.ownerUserID,
            secondOwnerUserID
        )

        let audits = try fetchAll(TransactionAuditRecord.self, in: targetContainer)
        XCTAssertEqual(audits.count, 1)
        XCTAssertEqual(audits.first?.createdByUserID, ownerUserID)
        XCTAssertEqual(audits.first?.lastModifiedByUserID, secondOwnerUserID)

        XCTAssertEqual(try fetchAll(SyncConflict.self, in: targetContainer).count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try avatarFileURL(fileName: fixture.avatarFileName).path))
    }

    func testMergeRestoreKeepsUnrelatedLocalRecordsAndBackupWinsOnMatchingIDs() throws {
        let ownerUserID = UUID()
        let backupContainer = try makeContainer()

        let sharedWalletID = UUID()
        let backupContext = ModelContext(backupContainer)
        let backupWallet = LedgerWallet(
            id: sharedWalletID,
            name: "Backup wallet",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            openingBalanceMinor: 42_000,
            updatedAt: makeDate(year: 2026, month: 4, day: 17)
        )
        backupContext.insert(backupWallet)
        backupContext.insert(
            OwnedRecordScope(
                entity: .wallet,
                recordID: sharedWalletID,
                ownerUserID: ownerUserID,
                updatedAt: backupWallet.updatedAt
            )
        )
        try backupContext.save()

        let backupExport = try MistiaBackupStore.exportBackup(
            from: backupContainer,
            fallbackOwnerUserID: ownerUserID,
            appVersion: "1.0.0",
            appBuild: "100"
        )

        let currentContainer = try makeContainer()
        let currentContext = ModelContext(currentContainer)
        let localVersion = LedgerWallet(
            id: sharedWalletID,
            name: "Local wallet",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            openingBalanceMinor: 900,
            updatedAt: makeDate(year: 2026, month: 4, day: 1)
        )
        let unrelatedWallet = LedgerWallet(
            id: UUID(),
            name: "Unrelated wallet",
            kind: .bank,
            iconSymbolName: LedgerWalletKind.bank.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.bank.defaultColorHex,
            openingBalanceMinor: 7_000
        )
        currentContext.insert(localVersion)
        currentContext.insert(unrelatedWallet)
        currentContext.insert(
            OwnedRecordScope(
                entity: .wallet,
                recordID: sharedWalletID,
                ownerUserID: ownerUserID
            )
        )
        currentContext.insert(
            OwnedRecordScope(
                entity: .wallet,
                recordID: unrelatedWallet.id,
                ownerUserID: ownerUserID
            )
        )
        currentContext.insert(
            SyncConflict(
                entityRawValue: MistiaSyncEntity.wallet.rawValue,
                recordID: sharedWalletID,
                conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                localPayloadJSON: "{}",
                remotePayloadJSON: "{}",
                baseVersion: 0,
                remoteVersion: 0
            )
        )
        try currentContext.save()

        let outboxDefaults = try makeOutboxDefaults()
        let outbox = MistiaSyncOutbox(defaults: outboxDefaults, key: "merge-outbox")
        outbox.enqueue(
            MistiaSyncMutation(
                entity: .wallet,
                recordID: sharedWalletID,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: makeDate(year: 2026, month: 4, day: 17)
            )
        )

        _ = try MistiaBackupStore.restoreBackup(
            backupExport.data,
            mode: .merge,
            in: currentContainer,
            fallbackOwnerUserID: ownerUserID,
            outbox: outbox
        )

        let wallets = try fetchAll(LedgerWallet.self, in: currentContainer)
        XCTAssertEqual(wallets.count, 2)
        XCTAssertEqual(wallets.first(where: { $0.id == sharedWalletID })?.name, "Backup wallet")
        XCTAssertEqual(wallets.first(where: { $0.id == sharedWalletID })?.openingBalanceMinor, 42_000)
        XCTAssertEqual(wallets.first(where: { $0.id == unrelatedWallet.id })?.name, "Unrelated wallet")
        XCTAssertEqual(outbox.allMutations.count, 0)
        XCTAssertEqual(try fetchAll(SyncConflict.self, in: currentContainer).count, 0)
    }

    func testFreshInMemoryStoreBootsWithCurrentSchema() throws {
        let container = try makeContainer()
        let schema = Schema(versionedSchema: MistiaSchemaV5.self)

        XCTAssertEqual(schema.entities.count, 15)
        XCTAssertEqual(try MistiaSyncLocalStore.totalObjectCount(in: container), 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fetchAll<Model: PersistentModel>(
        _ type: Model.Type,
        in container: ModelContainer
    ) throws -> [Model] {
        try ModelContext(container).fetch(FetchDescriptor<Model>())
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeOutboxDefaults() throws -> UserDefaults {
        let suiteName = "mistia.tests.\(UUID().uuidString.lowercased())"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func seedComprehensiveFixture(
        in container: ModelContainer,
        ownerUserID: UUID,
        secondOwnerUserID: UUID
    ) throws -> BackupFixture {
        let context = ModelContext(container)
        let now = makeDate(year: 2026, month: 4, day: 17)

        let parentCategory = TransactionCategory(
            id: UUID(),
            name: "Living",
            kind: .expense,
            iconSymbolName: "house.fill",
            iconColorHex: "#FF9F1C",
            isFavorite: false,
            hierarchyRole: .parent,
            sortOrder: 0,
            updatedAt: now
        )
        let childCategory = TransactionCategory(
            id: UUID(),
            name: "Groceries",
            kind: .expense,
            iconSymbolName: "cart.fill",
            iconColorHex: "#57B7FF",
            isFavorite: true,
            parentCategory: parentCategory,
            hierarchyRole: .child,
            sortOrder: 1,
            updatedAt: now
        )

        let cashWallet = LedgerWallet(
            id: UUID(),
            name: "Cash wallet",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            openingBalanceMinor: 15_000,
            updatedAt: now
        )
        let creditWallet = LedgerWallet(
            id: UUID(),
            name: "Travel card",
            kind: .creditCard,
            iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.creditCard.defaultColorHex,
            openingBalanceMinor: 6_000,
            updatedAt: now
        )
        let sharedFamilyWallet = LedgerWallet(
            id: UUID(),
            name: "Family wallet",
            kind: .bank,
            iconSymbolName: LedgerWalletKind.bank.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.bank.defaultColorHex,
            openingBalanceMinor: 48_000,
            updatedAt: now
        )

        let cardProfile = CreditCardProfile(
            id: UUID(),
            issuerName: "Visa",
            network: .visa,
            last4: "1234",
            creditLimitMinor: 120_000,
            statementClosingDay: 25,
            paymentDueDay: 10,
            notes: "Primary card",
            autoPayEnabled: true,
            createdAt: now,
            updatedAt: now,
            wallet: creditWallet,
            paymentSourceWallet: cashWallet
        )
        creditWallet.creditCardProfile = cardProfile

        let transaction = LedgerTransaction(
            id: UUID(),
            primaryKind: .expense,
            entryStatus: .posted,
            title: "Supermarket",
            note: "Weekly run",
            amountMinor: 2_400,
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            sourceWallet: cashWallet,
            category: childCategory,
            counterpartyName: "Local mart",
            normalizedCounterpartyKey: "local-mart"
        )
        let budgetPlan = BudgetPlan(
            id: UUID(),
            category: childCategory,
            monthAnchor: makeDate(year: 2026, month: 4, day: 1),
            limitMinor: 20_000,
            rolloverEnabled: false,
            createdAt: now,
            updatedAt: now
        )
        let savingsGoal = SavingsGoal(
            id: UUID(),
            name: "Emergency fund",
            iconSymbolName: "mistia.goal.savings",
            targetMinor: 300_000,
            currentSavedMinor: 75_000,
            targetDate: makeDate(year: 2026, month: 12, day: 31),
            linkedWallet: cashWallet,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now
        )
        let recurringBill = RecurringBillPlan(
            id: UUID(),
            name: "Rent",
            iconSymbolName: "mistia.plan.bill",
            category: childCategory,
            amountMinor: 35_000,
            dueDay: 10,
            scheduleKind: .recurring,
            paymentStartDay: 25,
            firstScheduledMonth: makeDate(year: 2026, month: 4, day: 1),
            hasExplicitDueDate: true,
            autoPayEnabled: true,
            autoPayDay: 28,
            paymentWallet: cashWallet,
            isPaused: true,
            pausedAt: makeDate(year: 2026, month: 4, day: 20),
            resumeStartMonth: makeDate(year: 2026, month: 7, day: 1),
            createdAt: now,
            updatedAt: now
        )
        let installmentPlan = InstallmentPlan(
            id: UUID(),
            name: "Laptop",
            iconSymbolName: "mistia.plan.installment",
            amountPerCycleMinor: 9_000,
            dueDay: 18,
            totalCycles: 12,
            paymentWallet: cashWallet,
            createdAt: now,
            updatedAt: now
        )
        let dueOccurrence = DueOccurrenceRecord(
            id: UUID(),
            sourceKind: .recurringBill,
            sourceID: recurringBill.id,
            selectedMonthKey: "2026-04",
            scheduledDate: makeDate(year: 2026, month: 5, day: 10),
            amountMinorSnapshot: recurringBill.amountMinor,
            status: .paid,
            paidAt: now,
            linkedTransactionID: transaction.id,
            createdAt: now,
            updatedAt: now
        )

        let avatarFileName = "\(ownerUserID.uuidString.lowercased()).jpg"
        try Data([0x01, 0x02, 0x03, 0x04]).write(
            to: avatarFileURL(fileName: avatarFileName),
            options: .atomic
        )

        let ownerProfile = UserAccountProfile(
            userID: ownerUserID,
            email: "owner@example.com",
            displayName: "Owner One",
            avatarFileName: avatarFileName,
            birthday: makeDate(year: 1992, month: 8, day: 12),
            createdAt: now,
            updatedAt: now
        )
        let secondProfile = UserAccountProfile(
            userID: secondOwnerUserID,
            email: "family@example.com",
            displayName: "Family Two",
            createdAt: now,
            updatedAt: now
        )

        context.insert(parentCategory)
        context.insert(childCategory)
        context.insert(cashWallet)
        context.insert(creditWallet)
        context.insert(sharedFamilyWallet)
        context.insert(cardProfile)
        context.insert(transaction)
        context.insert(budgetPlan)
        context.insert(savingsGoal)
        context.insert(recurringBill)
        context.insert(installmentPlan)
        context.insert(dueOccurrence)
        context.insert(ownerProfile)
        context.insert(secondProfile)

        let scopes: [OwnedRecordScope] = [
            OwnedRecordScope(entity: .wallet, recordID: cashWallet.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .wallet, recordID: creditWallet.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .wallet, recordID: sharedFamilyWallet.id, ownerUserID: secondOwnerUserID, updatedAt: now),
            OwnedRecordScope(entity: .creditCardProfile, recordID: cardProfile.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .category, recordID: parentCategory.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .category, recordID: childCategory.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .transaction, recordID: transaction.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .budgetPlan, recordID: budgetPlan.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .savingsGoal, recordID: savingsGoal.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .recurringBillPlan, recordID: recurringBill.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .installmentPlan, recordID: installmentPlan.id, ownerUserID: ownerUserID, updatedAt: now),
            OwnedRecordScope(entity: .dueOccurrenceRecord, recordID: dueOccurrence.id, ownerUserID: ownerUserID, updatedAt: now)
        ]
        scopes.forEach(context.insert)

        context.insert(
            TransactionAuditRecord(
                transactionID: transaction.id,
                createdByUserID: ownerUserID,
                lastModifiedByUserID: secondOwnerUserID,
                updatedAt: now
            )
        )

        try context.save()

        return BackupFixture(
            cashWalletID: cashWallet.id,
            sharedFamilyWalletID: sharedFamilyWallet.id,
            parentCategoryID: parentCategory.id,
            childCategoryID: childCategory.id,
            transactionID: transaction.id,
            recurringBillID: recurringBill.id,
            avatarFileName: avatarFileName,
            expectedWalletIDs: Set([cashWallet.id, creditWallet.id, sharedFamilyWallet.id])
        )
    }
}

private struct BackupFixture {
    let cashWalletID: UUID
    let sharedFamilyWalletID: UUID
    let parentCategoryID: UUID
    let childCategoryID: UUID
    let transactionID: UUID
    let recurringBillID: UUID
    let avatarFileName: String
    let expectedWalletIDs: Set<UUID>
}

private func avatarDirectoryURL() throws -> URL {
    let baseURL = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directoryURL = baseURL.appendingPathComponent("ProfileAvatars", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func avatarFileURL(fileName: String) throws -> URL {
    try avatarDirectoryURL().appendingPathComponent(fileName)
}

private func backupDirectoryURL() throws -> URL {
    let baseURL = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directoryURL = baseURL.appendingPathComponent("MistiaBackups", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func removeDirectoryIfPresent(_ directoryURL: URL) throws {
    if FileManager.default.fileExists(atPath: directoryURL.path) {
        try FileManager.default.removeItem(at: directoryURL)
    }
}
