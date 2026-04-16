import Foundation
import SwiftData

enum MistiaLegacyStoreRecovery {
    struct RecoveryError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private struct Payload {
        var sourceVersion: String
        var wallets: [LegacyWalletSnapshot] = []
        var creditCards: [LegacyCreditCardSnapshot] = []
        var categories: [LegacyCategorySnapshot] = []
        var transactions: [LegacyTransactionSnapshot] = []
        var budgetPlans: [LegacyBudgetPlanSnapshot] = []
        var savingsGoals: [LegacySavingsGoalSnapshot] = []
        var recurringBills: [LegacyRecurringBillSnapshot] = []
        var installmentPlans: [LegacyInstallmentPlanSnapshot] = []
        var dueOccurrences: [LegacyDueOccurrenceSnapshot] = []
        var syncConflicts: [LegacySyncConflictSnapshot] = []
        var userProfiles: [LegacyUserProfileSnapshot] = []
        var ownershipScopes: [LegacyOwnedRecordScopeSnapshot] = []
        var transactionAuditRecords: [LegacyTransactionAuditSnapshot] = []

        var debugSummary: String {
            "wallets=\(wallets.count), creditCards=\(creditCards.count), categories=\(categories.count), transactions=\(transactions.count), budgets=\(budgetPlans.count), goals=\(savingsGoals.count), recurringBills=\(recurringBills.count), installments=\(installmentPlans.count), dueOccurrences=\(dueOccurrences.count), syncConflicts=\(syncConflicts.count), userProfiles=\(userProfiles.count), ownershipScopes=\(ownershipScopes.count), transactionAudits=\(transactionAuditRecords.count)"
        }
    }

    static func canRecover(from error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 134504 {
            return true
        }

        return String(describing: error)
            .localizedCaseInsensitiveContains("unknown model version")
    }

    static func recoveredStoreURL(for primaryStoreURL: URL) -> URL {
        let directoryURL = primaryStoreURL.deletingLastPathComponent()
        let baseName = primaryStoreURL.deletingPathExtension().lastPathComponent
        return directoryURL
            .appendingPathComponent("\(baseName).recovered")
            .appendingPathExtension(primaryStoreURL.pathExtension)
    }

    static func recoverLegacyStoreIfNeeded(
        at legacyStoreURL: URL,
        recoveredStoreURL: URL
    ) throws -> Bool {
        guard let payload = try loadPayloadIfSupported(from: legacyStoreURL) else {
            return false
        }

        try materializeRecoveredStore(with: payload, recoveredStoreURL: recoveredStoreURL)
        return true
    }

    static func recoverStore(at legacyStoreURL: URL, recoveredStoreURL: URL) throws {
        guard let payload = try loadPayloadIfSupported(from: legacyStoreURL) else {
            throw RecoveryError(
                message: "Unable to open the legacy store with any known schema snapshot."
            )
        }

        try materializeRecoveredStore(with: payload, recoveredStoreURL: recoveredStoreURL)
    }

    private static func temporaryRecoveredStoreURL(for recoveredStoreURL: URL) -> URL {
        let directoryURL = recoveredStoreURL.deletingLastPathComponent()
        let baseName = recoveredStoreURL.deletingPathExtension().lastPathComponent
        return directoryURL
            .appendingPathComponent("\(baseName).import")
            .appendingPathExtension(recoveredStoreURL.pathExtension)
    }

    private static func materializeRecoveredStore(with payload: Payload, recoveredStoreURL: URL) throws {
        let temporaryStoreURL = temporaryRecoveredStoreURL(for: recoveredStoreURL)

        try removeStoreFamily(at: temporaryStoreURL)
        try writeRecoveredStore(with: payload, to: temporaryStoreURL)
        try removeStoreFamily(at: recoveredStoreURL)
        try moveStoreFamily(from: temporaryStoreURL, to: recoveredStoreURL)

        print(
            "MistiaLegacyStoreRecovery: recovered legacy \(payload.sourceVersion) store to \(recoveredStoreURL.path) with \(payload.debugSummary)"
        )
    }

    private static func loadPayloadIfSupported(from legacyStoreURL: URL) throws -> Payload? {
        typealias LabeledLoader = (label: String, load: (URL) throws -> Payload)

        let loaders: [LabeledLoader] = [
            ("V10", loadV10Payload),
            ("V9", loadV9Payload),
            ("V8", loadV8Payload),
            ("V7", loadV7Payload),
            ("V6", loadV6Payload),
            ("V5", loadV5Payload),
            ("V4", loadV4Payload),
            ("V3", loadV3Payload),
            ("V2-Account", loadLegacyAccountV2Payload),
            ("V2", loadV2Payload),
            ("V1-Account", loadLegacyAccountV1Payload),
            ("V1", loadV1Payload)
        ]

        for loader in loaders {
            do {
                let payload = try loader.load(legacyStoreURL)
                print(
                    "MistiaLegacyStoreRecovery: loaded \(payload.sourceVersion) payload from \(legacyStoreURL.path) with \(payload.debugSummary)"
                )
                return payload
            } catch {
                print(
                    "MistiaLegacyStoreRecovery: \(loader.label) loader failed for \(legacyStoreURL.path): \(error)"
                )
                continue
            }
        }

        return nil
    }

    private static func writeRecoveredStore(with payload: Payload, to recoveredStoreURL: URL) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV10.self)
        let configuration = ModelConfiguration("default", schema: schema, url: recoveredStoreURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        var walletByID: [UUID: LedgerWallet] = [:]
        for snapshot in payload.wallets {
            let wallet = LedgerWallet(
                id: snapshot.id,
                name: snapshot.name,
                kind: LedgerWalletKind(rawValue: snapshot.kindRawValue) ?? .cash,
                iconSymbolName: snapshot.iconSymbolName,
                iconColorHex: snapshot.iconColorHex,
                currencyCode: snapshot.currencyCode,
                openingBalanceMinor: snapshot.openingBalanceMinor,
                institutionDisplayName: snapshot.institutionDisplayName,
                institutionPresetKey: snapshot.institutionPresetKey,
                sortOrder: snapshot.sortOrder,
                isArchived: snapshot.isArchived,
                archivedAt: snapshot.archivedAt,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(wallet)
            walletByID[wallet.id] = wallet
        }

        var categoryByID: [UUID: TransactionCategory] = [:]
        for snapshot in payload.categories {
            let category = TransactionCategory(
                id: snapshot.id,
                name: snapshot.name,
                kind: TransactionCategoryKind(rawValue: snapshot.kindRawValue) ?? .expense,
                iconSymbolName: snapshot.iconSymbolName,
                iconColorHex: snapshot.iconColorHex,
                isFavorite: snapshot.isFavorite,
                parentCategory: nil,
                hierarchyRole: snapshot.hierarchyRoleRawValue.flatMap(TransactionCategoryHierarchyRole.init(rawValue:)),
                systemKey: snapshot.systemKey,
                isSystem: snapshot.isSystem,
                cloudSyncEnabled: !snapshot.isSystem || snapshot.remoteVersion > 0,
                sortOrder: snapshot.sortOrder,
                isArchived: snapshot.isArchived,
                archivedAt: snapshot.archivedAt,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(category)
            categoryByID[category.id] = category
        }

        var creditCardByID: [UUID: CreditCardProfile] = [:]
        for snapshot in payload.creditCards {
            let creditCard = CreditCardProfile(
                id: snapshot.id,
                issuerName: snapshot.issuerName,
                network: CreditCardNetwork(rawValue: snapshot.networkRawValue) ?? .visa,
                last4: snapshot.last4,
                creditLimitMinor: snapshot.creditLimitMinor,
                statementClosingDay: snapshot.statementClosingDay,
                paymentDueDay: snapshot.paymentDueDay,
                notes: snapshot.notes,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(creditCard)
            creditCardByID[creditCard.id] = creditCard
        }

        var transactionByID: [UUID: LedgerTransaction] = [:]
        for snapshot in payload.transactions {
            let transaction = LedgerTransaction(
                id: snapshot.id,
                primaryKind: TransactionPrimaryKind(rawValue: snapshot.primaryKindRawValue) ?? .expense,
                transferSubtype: snapshot.transferSubtypeRawValue.flatMap(TransactionTransferSubtype.init(rawValue:)),
                debtIntent: snapshot.debtIntentRawValue.flatMap(TransactionDebtIntent.init(rawValue:)),
                entryStatus: TransactionEntryStatus(rawValue: snapshot.entryStatusRawValue) ?? .posted,
                title: snapshot.title,
                note: snapshot.note,
                amountMinor: snapshot.amountMinor,
                occurredAt: snapshot.occurredAt,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion,
                counterpartyName: snapshot.counterpartyName,
                normalizedCounterpartyKey: snapshot.normalizedCounterpartyKey,
                isArchived: snapshot.isArchived,
                archivedAt: snapshot.archivedAt
            )
            context.insert(transaction)
            transactionByID[transaction.id] = transaction
        }

        for snapshot in payload.budgetPlans {
            let budgetPlan = BudgetPlan(
                id: snapshot.id,
                category: snapshot.categoryID.flatMap { categoryByID[$0] },
                monthAnchor: snapshot.monthAnchor,
                limitMinor: snapshot.limitMinor,
                rolloverEnabled: snapshot.rolloverEnabled,
                currencyCode: snapshot.currencyCode,
                isArchived: snapshot.isArchived,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(budgetPlan)
        }

        for snapshot in payload.savingsGoals {
            let savingsGoal = SavingsGoal(
                id: snapshot.id,
                name: snapshot.name,
                iconSymbolName: snapshot.iconSymbolName,
                targetMinor: snapshot.targetMinor,
                currentSavedMinor: snapshot.currentSavedMinor,
                targetDate: snapshot.targetDate,
                linkedWallet: snapshot.linkedWalletID.flatMap { walletByID[$0] },
                currencyCode: snapshot.currencyCode,
                sortOrder: snapshot.sortOrder,
                isArchived: snapshot.isArchived,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(savingsGoal)
        }

        for snapshot in payload.recurringBills {
            let recurringBill = RecurringBillPlan(
                id: snapshot.id,
                name: snapshot.name,
                iconSymbolName: snapshot.iconSymbolName,
                category: snapshot.categoryID.flatMap { categoryByID[$0] },
                amountMinor: snapshot.amountMinor,
                dueDay: snapshot.dueDay,
                frequencyMonths: snapshot.frequencyMonths,
                paymentWallet: snapshot.paymentWalletID.flatMap { walletByID[$0] },
                currencyCode: snapshot.currencyCode,
                isArchived: snapshot.isArchived,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(recurringBill)
        }

        for snapshot in payload.installmentPlans {
            let installmentPlan = InstallmentPlan(
                id: snapshot.id,
                name: snapshot.name,
                iconSymbolName: snapshot.iconSymbolName,
                amountPerCycleMinor: snapshot.amountPerCycleMinor,
                dueDay: snapshot.dueDay,
                totalCycles: snapshot.totalCycles,
                frequencyMonths: snapshot.frequencyMonths,
                paymentWallet: snapshot.paymentWalletID.flatMap { walletByID[$0] },
                currencyCode: snapshot.currencyCode,
                isArchived: snapshot.isArchived,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(installmentPlan)
        }

        for snapshot in payload.dueOccurrences {
            let dueOccurrence = DueOccurrenceRecord(
                id: snapshot.id,
                sourceKind: PlanningDueSourceKind(rawValue: snapshot.sourceKindRawValue) ?? .creditCard,
                sourceID: snapshot.sourceID,
                selectedMonthKey: snapshot.selectedMonthKey,
                scheduledDate: snapshot.scheduledDate,
                amountMinorSnapshot: snapshot.amountMinorSnapshot,
                status: PlanningDueOccurrenceStatus(rawValue: snapshot.statusRawValue) ?? .pending,
                paidAt: snapshot.paidAt,
                linkedTransactionID: snapshot.linkedTransactionID,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                deletedAt: snapshot.deletedAt,
                remoteVersion: snapshot.remoteVersion
            )
            context.insert(dueOccurrence)
        }

        for snapshot in payload.syncConflicts {
            let conflict = SyncConflict(
                id: snapshot.id,
                entityRawValue: snapshot.entityRawValue,
                recordID: snapshot.recordID,
                conflictKindRawValue: snapshot.conflictKindRawValue,
                localPayloadJSON: snapshot.localPayloadJSON,
                remotePayloadJSON: snapshot.remotePayloadJSON,
                baseVersion: snapshot.baseVersion,
                remoteVersion: snapshot.remoteVersion,
                createdAt: snapshot.createdAt
            )
            context.insert(conflict)
        }

        for snapshot in payload.userProfiles {
            let profile = UserAccountProfile(
                userID: snapshot.userID,
                email: snapshot.email,
                displayName: snapshot.displayName,
                avatarFileName: snapshot.avatarFileName,
                birthday: snapshot.birthday,
                lastSyncAt: snapshot.lastSyncAt,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt
            )
            context.insert(profile)
        }

        for snapshot in payload.ownershipScopes {
            guard let entity = MistiaSyncEntity(rawValue: snapshot.entityRawValue) else { continue }
            let scope = OwnedRecordScope(
                entity: entity,
                recordID: snapshot.recordID,
                ownerUserID: snapshot.ownerUserID,
                updatedAt: snapshot.updatedAt
            )
            context.insert(scope)
        }

        for snapshot in payload.transactionAuditRecords {
            let auditRecord = TransactionAuditRecord(
                transactionID: snapshot.transactionID,
                createdByUserID: snapshot.createdByUserID,
                lastModifiedByUserID: snapshot.lastModifiedByUserID,
                updatedAt: snapshot.updatedAt
            )
            context.insert(auditRecord)
        }

        for snapshot in payload.categories {
            guard let category = categoryByID[snapshot.id] else { continue }
            category.parentCategory = snapshot.parentCategoryID.flatMap { categoryByID[$0] }
        }

        for snapshot in payload.creditCards {
            guard let creditCard = creditCardByID[snapshot.id] else { continue }
            creditCard.wallet = snapshot.walletID.flatMap { walletByID[$0] }
            creditCard.paymentSourceWallet = snapshot.paymentSourceWalletID.flatMap { walletByID[$0] }
        }

        for snapshot in payload.transactions {
            guard let transaction = transactionByID[snapshot.id] else { continue }
            transaction.sourceWallet = snapshot.sourceWalletID.flatMap { walletByID[$0] }
            transaction.destinationWallet = snapshot.destinationWalletID.flatMap { walletByID[$0] }
            transaction.category = snapshot.categoryID.flatMap { categoryByID[$0] }
        }

        try context.save()
    }

    private static func loadV1Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV1.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V1",
            wallets: try context.fetch(FetchDescriptor<MistiaSchemaV1.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaSchemaV1.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaSchemaV1.TransactionCategory>()).map(LegacyCategorySnapshot.init)
        )
    }

    private static func loadV2Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV2.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V2",
            wallets: try context.fetch(FetchDescriptor<MistiaSchemaV2.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaSchemaV2.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaSchemaV2.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaSchemaV2.LedgerTransaction>()).map(LegacyTransactionSnapshot.init)
        )
    }

    private static func loadV3Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV3.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V3",
            wallets: try context.fetch(FetchDescriptor<MistiaSchemaV3.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaSchemaV3.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaSchemaV3.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaSchemaV3.LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<MistiaSchemaV3.BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<MistiaSchemaV3.SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<MistiaSchemaV3.RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<MistiaSchemaV3.InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<MistiaSchemaV3.DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init)
        )
    }

    private static func loadLegacyAccountV2Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaLegacyAccountSchemaV2.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V2-Account",
            wallets: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV2.LedgerAccount>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV2.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV2.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV2.LedgerTransaction>()).map(LegacyTransactionSnapshot.init)
        )
    }

    private static func loadV4Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV4.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V4",
            wallets: try context.fetch(FetchDescriptor<MistiaSchemaV4.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaSchemaV4.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaSchemaV4.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaSchemaV4.LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<MistiaSchemaV4.BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<MistiaSchemaV4.SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<MistiaSchemaV4.RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<MistiaSchemaV4.InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<MistiaSchemaV4.DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<MistiaSchemaV4.SyncConflict>()).map(LegacySyncConflictSnapshot.init)
        )
    }

    private static func loadV5Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV5.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V5",
            wallets: try context.fetch(FetchDescriptor<MistiaSchemaV5.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaSchemaV5.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaSchemaV5.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaSchemaV5.LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<MistiaSchemaV5.BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<MistiaSchemaV5.SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<MistiaSchemaV5.RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<MistiaSchemaV5.InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<MistiaSchemaV5.DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<MistiaSchemaV5.SyncConflict>()).map(LegacySyncConflictSnapshot.init)
        )
    }

    private static func loadV6Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV6.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V6",
            wallets: try context.fetch(FetchDescriptor<MistiaSchemaV6.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaSchemaV6.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaSchemaV6.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaSchemaV6.LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<MistiaSchemaV6.BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<MistiaSchemaV6.SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<MistiaSchemaV6.RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<MistiaSchemaV6.InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<MistiaSchemaV6.DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<MistiaSchemaV6.SyncConflict>()).map(LegacySyncConflictSnapshot.init),
            userProfiles: try context.fetch(FetchDescriptor<MistiaSchemaV6.UserAccountProfile>()).map(LegacyUserProfileSnapshot.init)
        )
    }

    private static func loadV7Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaRecoverySchemaV7.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V7",
            wallets: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.SyncConflict>()).map(LegacySyncConflictSnapshot.init),
            userProfiles: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.UserAccountProfile>()).map(LegacyUserProfileSnapshot.init)
        )
    }

    private static func loadV8Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaRecoverySchemaV8.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V8",
            wallets: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.SyncConflict>()).map(LegacySyncConflictSnapshot.init),
            userProfiles: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.UserAccountProfile>()).map(LegacyUserProfileSnapshot.init),
            ownershipScopes: try context.fetch(FetchDescriptor<MistiaRecoverySchemaV8.OwnedRecordScope>()).map(LegacyOwnedRecordScopeSnapshot.init)
        )
    }

    private static func loadV9Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV9.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V9",
            wallets: try context.fetch(FetchDescriptor<LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<SyncConflict>()).map(LegacySyncConflictSnapshot.init),
            userProfiles: try context.fetch(FetchDescriptor<UserAccountProfile>()).map(LegacyUserProfileSnapshot.init),
            ownershipScopes: try context.fetch(FetchDescriptor<OwnedRecordScope>()).map(LegacyOwnedRecordScopeSnapshot.init)
        )
    }

    private static func loadV10Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaSchemaV10.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V10",
            wallets: try context.fetch(FetchDescriptor<LedgerWallet>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<TransactionCategory>()).map(LegacyCategorySnapshot.init),
            transactions: try context.fetch(FetchDescriptor<LedgerTransaction>()).map(LegacyTransactionSnapshot.init),
            budgetPlans: try context.fetch(FetchDescriptor<BudgetPlan>()).map(LegacyBudgetPlanSnapshot.init),
            savingsGoals: try context.fetch(FetchDescriptor<SavingsGoal>()).map(LegacySavingsGoalSnapshot.init),
            recurringBills: try context.fetch(FetchDescriptor<RecurringBillPlan>()).map(LegacyRecurringBillSnapshot.init),
            installmentPlans: try context.fetch(FetchDescriptor<InstallmentPlan>()).map(LegacyInstallmentPlanSnapshot.init),
            dueOccurrences: try context.fetch(FetchDescriptor<DueOccurrenceRecord>()).map(LegacyDueOccurrenceSnapshot.init),
            syncConflicts: try context.fetch(FetchDescriptor<SyncConflict>()).map(LegacySyncConflictSnapshot.init),
            userProfiles: try context.fetch(FetchDescriptor<UserAccountProfile>()).map(LegacyUserProfileSnapshot.init),
            ownershipScopes: try context.fetch(FetchDescriptor<OwnedRecordScope>()).map(LegacyOwnedRecordScopeSnapshot.init),
            transactionAuditRecords: try context.fetch(FetchDescriptor<TransactionAuditRecord>()).map(LegacyTransactionAuditSnapshot.init)
        )
    }

    private static func loadLegacyAccountV1Payload(from legacyStoreURL: URL) throws -> Payload {
        let container = try legacyContainer(for: MistiaLegacyAccountSchemaV1.self, at: legacyStoreURL)
        let context = ModelContext(container)

        return Payload(
            sourceVersion: "V1-Account",
            wallets: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV1.LedgerAccount>()).map(LegacyWalletSnapshot.init),
            creditCards: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV1.CreditCardProfile>()).map(LegacyCreditCardSnapshot.init),
            categories: try context.fetch(FetchDescriptor<MistiaLegacyAccountSchemaV1.TransactionCategory>()).map(LegacyCategorySnapshot.init)
        )
    }

    private static func legacyContainer(
        for versionedSchema: any VersionedSchema.Type,
        at legacyStoreURL: URL
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: versionedSchema)
        let configuration = ModelConfiguration("default", schema: schema, url: legacyStoreURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func removeStoreFamily(at storeURL: URL) throws {
        let fileManager = FileManager.default
        for url in storeFamilyURLs(for: storeURL) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func moveStoreFamily(from sourceStoreURL: URL, to destinationStoreURL: URL) throws {
        let fileManager = FileManager.default
        for (sourceURL, destinationURL) in zip(storeFamilyURLs(for: sourceStoreURL), storeFamilyURLs(for: destinationStoreURL)) {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func storeFamilyURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }
}

private struct LegacyWalletSnapshot {
    let id: UUID
    let name: String
    let kindRawValue: String
    let iconSymbolName: String
    let iconColorHex: String
    let currencyCode: String
    let openingBalanceMinor: Int64
    let institutionDisplayName: String?
    let institutionPresetKey: String?
    let sortOrder: Int
    let isArchived: Bool
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ wallet: MistiaSchemaV1.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = nil
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ wallet: MistiaSchemaV2.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = nil
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ wallet: MistiaSchemaV3.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = nil
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ wallet: MistiaSchemaV4.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = wallet.archivedAt
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = wallet.deletedAt
        remoteVersion = wallet.remoteVersion
    }

    init(_ wallet: MistiaSchemaV5.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = wallet.archivedAt
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = wallet.deletedAt
        remoteVersion = wallet.remoteVersion
    }

    init(_ wallet: MistiaSchemaV6.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = wallet.archivedAt
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = wallet.deletedAt
        remoteVersion = wallet.remoteVersion
    }

    init(_ wallet: MistiaRecoverySchemaV8.LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = wallet.archivedAt
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = wallet.deletedAt
        remoteVersion = wallet.remoteVersion
    }

    init(_ wallet: LedgerWallet) {
        id = wallet.id
        name = wallet.name
        kindRawValue = wallet.kindRawValue
        iconSymbolName = wallet.iconSymbolName
        iconColorHex = wallet.iconColorHex
        currencyCode = wallet.currencyCode
        openingBalanceMinor = wallet.openingBalanceMinor
        institutionDisplayName = wallet.institutionDisplayName
        institutionPresetKey = wallet.institutionPresetKey
        sortOrder = wallet.sortOrder
        isArchived = wallet.isArchived
        archivedAt = wallet.archivedAt
        createdAt = wallet.createdAt
        updatedAt = wallet.updatedAt
        deletedAt = wallet.deletedAt
        remoteVersion = wallet.remoteVersion
    }

    init(_ account: MistiaLegacyAccountSchemaV1.LedgerAccount) {
        id = account.id
        name = account.name
        kindRawValue = account.kindRawValue
        iconSymbolName = account.iconSymbolName
        iconColorHex = account.iconColorHex
        currencyCode = account.currencyCode
        openingBalanceMinor = account.openingBalanceMinor
        institutionDisplayName = account.institutionDisplayName
        institutionPresetKey = account.institutionPresetKey
        sortOrder = account.sortOrder
        isArchived = account.isArchived
        archivedAt = nil
        createdAt = account.createdAt
        updatedAt = account.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ account: MistiaLegacyAccountSchemaV2.LedgerAccount) {
        id = account.id
        name = account.name
        kindRawValue = account.kindRawValue
        iconSymbolName = account.iconSymbolName
        iconColorHex = account.iconColorHex
        currencyCode = account.currencyCode
        openingBalanceMinor = account.openingBalanceMinor
        institutionDisplayName = account.institutionDisplayName
        institutionPresetKey = account.institutionPresetKey
        sortOrder = account.sortOrder
        isArchived = account.isArchived
        archivedAt = nil
        createdAt = account.createdAt
        updatedAt = account.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }
}

private struct LegacyCreditCardSnapshot {
    let id: UUID
    let issuerName: String
    let networkRawValue: String
    let last4: String
    let creditLimitMinor: Int64
    let statementClosingDay: Int
    let paymentDueDay: Int
    let notes: String?
    let walletID: UUID?
    let paymentSourceWalletID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ profile: MistiaSchemaV1.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ profile: MistiaSchemaV2.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ profile: MistiaSchemaV3.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ profile: MistiaSchemaV4.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = profile.deletedAt
        remoteVersion = profile.remoteVersion
    }

    init(_ profile: MistiaSchemaV5.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = profile.deletedAt
        remoteVersion = profile.remoteVersion
    }

    init(_ profile: MistiaSchemaV6.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = profile.deletedAt
        remoteVersion = profile.remoteVersion
    }

    init(_ profile: MistiaRecoverySchemaV8.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = profile.deletedAt
        remoteVersion = profile.remoteVersion
    }

    init(_ profile: CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.wallet?.id
        paymentSourceWalletID = profile.paymentSourceWallet?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = profile.deletedAt
        remoteVersion = profile.remoteVersion
    }

    init(_ profile: MistiaLegacyAccountSchemaV1.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.account?.id
        paymentSourceWalletID = profile.paymentSourceAccount?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ profile: MistiaLegacyAccountSchemaV2.CreditCardProfile) {
        id = profile.id
        issuerName = profile.issuerName
        networkRawValue = profile.networkRawValue
        last4 = profile.last4
        creditLimitMinor = profile.creditLimitMinor
        statementClosingDay = profile.statementClosingDay
        paymentDueDay = profile.paymentDueDay
        notes = profile.notes
        walletID = profile.account?.id
        paymentSourceWalletID = profile.paymentSourceAccount?.id
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }
}

private struct LegacyCategorySnapshot {
    let id: UUID
    let name: String
    let kindRawValue: String
    let iconSymbolName: String
    let iconColorHex: String
    let isFavorite: Bool
    let parentCategoryID: UUID?
    let hierarchyRoleRawValue: String?
    let systemKey: String?
    let isSystem: Bool
    let sortOrder: Int
    let isArchived: Bool
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ category: MistiaSchemaV1.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = nil
        hierarchyRoleRawValue = nil
        systemKey = nil
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = nil
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ category: MistiaSchemaV2.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = nil
        hierarchyRoleRawValue = nil
        systemKey = nil
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = nil
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ category: MistiaSchemaV3.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = nil
        hierarchyRoleRawValue = nil
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = nil
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ category: MistiaSchemaV4.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = nil
        hierarchyRoleRawValue = nil
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = category.archivedAt
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        remoteVersion = category.remoteVersion
    }

    init(_ category: MistiaSchemaV5.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = category.parentCategory?.id
        hierarchyRoleRawValue = category.hierarchyRoleRawValue
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = category.archivedAt
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        remoteVersion = category.remoteVersion
    }

    init(_ category: MistiaSchemaV6.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = category.parentCategory?.id
        hierarchyRoleRawValue = category.hierarchyRoleRawValue
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = category.archivedAt
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        remoteVersion = category.remoteVersion
    }

    init(_ category: MistiaRecoverySchemaV8.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = category.favoriteRawValue ?? false
        parentCategoryID = category.parentCategory?.id
        hierarchyRoleRawValue = category.hierarchyRoleRawValue
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = category.archivedAt
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        remoteVersion = category.remoteVersion
    }

    init(_ category: MistiaRecoverySchemaV10.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = category.favoriteRawValue ?? false
        parentCategoryID = category.parentCategory?.id
        hierarchyRoleRawValue = category.hierarchyRoleRawValue
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = category.archivedAt
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        remoteVersion = category.remoteVersion
    }

    init(_ category: TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = category.favoriteRawValue ?? false
        parentCategoryID = category.parentCategory?.id
        hierarchyRoleRawValue = category.hierarchyRoleRawValue
        systemKey = category.systemKey
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = category.archivedAt
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        remoteVersion = category.remoteVersion
    }

    init(_ category: MistiaLegacyAccountSchemaV1.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = nil
        hierarchyRoleRawValue = nil
        systemKey = nil
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = nil
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ category: MistiaLegacyAccountSchemaV2.TransactionCategory) {
        id = category.id
        name = category.name
        kindRawValue = category.kindRawValue
        iconSymbolName = category.iconSymbolName
        iconColorHex = category.iconColorHex
        isFavorite = false
        parentCategoryID = nil
        hierarchyRoleRawValue = nil
        systemKey = nil
        isSystem = category.isSystem
        sortOrder = category.sortOrder
        isArchived = category.isArchived
        archivedAt = nil
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }
}

private struct LegacyTransactionSnapshot {
    let id: UUID
    let primaryKindRawValue: String
    let transferSubtypeRawValue: String?
    let debtIntentRawValue: String?
    let entryStatusRawValue: String
    let title: String
    let note: String?
    let amountMinor: Int64
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64
    let counterpartyName: String?
    let normalizedCounterpartyKey: String?
    let sourceWalletID: UUID?
    let destinationWalletID: UUID?
    let categoryID: UUID?
    let isArchived: Bool
    let archivedAt: Date?

    init(_ transaction: MistiaSchemaV2.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = nil
        remoteVersion = 0
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = false
        archivedAt = nil
    }

    init(_ transaction: MistiaSchemaV3.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = nil
        remoteVersion = 0
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = false
        archivedAt = nil
    }

    init(_ transaction: MistiaSchemaV4.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
        remoteVersion = transaction.remoteVersion
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = transaction.isArchived
        archivedAt = transaction.archivedAt
    }

    init(_ transaction: MistiaSchemaV5.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
        remoteVersion = transaction.remoteVersion
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = transaction.isArchived
        archivedAt = transaction.archivedAt
    }

    init(_ transaction: MistiaSchemaV6.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
        remoteVersion = transaction.remoteVersion
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = transaction.isArchived
        archivedAt = transaction.archivedAt
    }

    init(_ transaction: MistiaRecoverySchemaV8.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
        remoteVersion = transaction.remoteVersion
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = transaction.isArchived
        archivedAt = transaction.archivedAt
    }

    init(_ transaction: MistiaRecoverySchemaV10.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
        remoteVersion = transaction.remoteVersion
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = transaction.isArchived
        archivedAt = transaction.archivedAt
    }

    init(_ transaction: LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = transaction.deletedAt
        remoteVersion = transaction.remoteVersion
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceWallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        categoryID = transaction.category?.id
        isArchived = transaction.isArchived
        archivedAt = transaction.archivedAt
    }

    init(_ transaction: MistiaLegacyAccountSchemaV2.LedgerTransaction) {
        id = transaction.id
        primaryKindRawValue = transaction.primaryKindRawValue
        transferSubtypeRawValue = transaction.transferSubtypeRawValue
        debtIntentRawValue = transaction.debtIntentRawValue
        entryStatusRawValue = transaction.entryStatusRawValue
        title = transaction.title
        note = transaction.note
        amountMinor = transaction.amountMinor
        occurredAt = transaction.occurredAt
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
        deletedAt = nil
        remoteVersion = 0
        counterpartyName = transaction.counterpartyName
        normalizedCounterpartyKey = transaction.normalizedCounterpartyKey
        sourceWalletID = transaction.sourceAccount?.id
        destinationWalletID = transaction.destinationAccount?.id
        categoryID = transaction.category?.id
        isArchived = false
        archivedAt = nil
    }
}

private struct LegacyBudgetPlanSnapshot {
    let id: UUID
    let categoryID: UUID?
    let monthAnchor: Date
    let limitMinor: Int64
    let rolloverEnabled: Bool
    let currencyCode: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ budgetPlan: MistiaSchemaV3.BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ budgetPlan: MistiaSchemaV4.BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = budgetPlan.deletedAt
        remoteVersion = budgetPlan.remoteVersion
    }

    init(_ budgetPlan: MistiaSchemaV5.BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = budgetPlan.deletedAt
        remoteVersion = budgetPlan.remoteVersion
    }

    init(_ budgetPlan: MistiaSchemaV6.BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = budgetPlan.deletedAt
        remoteVersion = budgetPlan.remoteVersion
    }

    init(_ budgetPlan: MistiaRecoverySchemaV8.BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = budgetPlan.deletedAt
        remoteVersion = budgetPlan.remoteVersion
    }

    init(_ budgetPlan: MistiaRecoverySchemaV10.BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = budgetPlan.deletedAt
        remoteVersion = budgetPlan.remoteVersion
    }

    init(_ budgetPlan: BudgetPlan) {
        id = budgetPlan.id
        categoryID = budgetPlan.category?.id
        monthAnchor = budgetPlan.monthAnchor
        limitMinor = budgetPlan.limitMinor
        rolloverEnabled = budgetPlan.rolloverEnabled
        currencyCode = budgetPlan.currencyCode
        isArchived = budgetPlan.isArchived
        createdAt = budgetPlan.createdAt
        updatedAt = budgetPlan.updatedAt
        deletedAt = budgetPlan.deletedAt
        remoteVersion = budgetPlan.remoteVersion
    }
}

private struct LegacySavingsGoalSnapshot {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let targetMinor: Int64
    let currentSavedMinor: Int64
    let targetDate: Date
    let linkedWalletID: UUID?
    let currencyCode: String
    let sortOrder: Int
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ savingsGoal: MistiaSchemaV3.SavingsGoal) {
        id = savingsGoal.id
        name = savingsGoal.name
        iconSymbolName = savingsGoal.iconSymbolName
        targetMinor = savingsGoal.targetMinor
        currentSavedMinor = savingsGoal.currentSavedMinor
        targetDate = savingsGoal.targetDate
        linkedWalletID = savingsGoal.linkedWallet?.id
        currencyCode = savingsGoal.currencyCode
        sortOrder = savingsGoal.sortOrder
        isArchived = savingsGoal.isArchived
        createdAt = savingsGoal.createdAt
        updatedAt = savingsGoal.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ savingsGoal: MistiaSchemaV4.SavingsGoal) {
        id = savingsGoal.id
        name = savingsGoal.name
        iconSymbolName = savingsGoal.iconSymbolName
        targetMinor = savingsGoal.targetMinor
        currentSavedMinor = savingsGoal.currentSavedMinor
        targetDate = savingsGoal.targetDate
        linkedWalletID = savingsGoal.linkedWallet?.id
        currencyCode = savingsGoal.currencyCode
        sortOrder = savingsGoal.sortOrder
        isArchived = savingsGoal.isArchived
        createdAt = savingsGoal.createdAt
        updatedAt = savingsGoal.updatedAt
        deletedAt = savingsGoal.deletedAt
        remoteVersion = savingsGoal.remoteVersion
    }

    init(_ savingsGoal: MistiaSchemaV5.SavingsGoal) {
        id = savingsGoal.id
        name = savingsGoal.name
        iconSymbolName = savingsGoal.iconSymbolName
        targetMinor = savingsGoal.targetMinor
        currentSavedMinor = savingsGoal.currentSavedMinor
        targetDate = savingsGoal.targetDate
        linkedWalletID = savingsGoal.linkedWallet?.id
        currencyCode = savingsGoal.currencyCode
        sortOrder = savingsGoal.sortOrder
        isArchived = savingsGoal.isArchived
        createdAt = savingsGoal.createdAt
        updatedAt = savingsGoal.updatedAt
        deletedAt = savingsGoal.deletedAt
        remoteVersion = savingsGoal.remoteVersion
    }

    init(_ savingsGoal: MistiaSchemaV6.SavingsGoal) {
        id = savingsGoal.id
        name = savingsGoal.name
        iconSymbolName = savingsGoal.iconSymbolName
        targetMinor = savingsGoal.targetMinor
        currentSavedMinor = savingsGoal.currentSavedMinor
        targetDate = savingsGoal.targetDate
        linkedWalletID = savingsGoal.linkedWallet?.id
        currencyCode = savingsGoal.currencyCode
        sortOrder = savingsGoal.sortOrder
        isArchived = savingsGoal.isArchived
        createdAt = savingsGoal.createdAt
        updatedAt = savingsGoal.updatedAt
        deletedAt = savingsGoal.deletedAt
        remoteVersion = savingsGoal.remoteVersion
    }

    init(_ savingsGoal: MistiaRecoverySchemaV8.SavingsGoal) {
        id = savingsGoal.id
        name = savingsGoal.name
        iconSymbolName = savingsGoal.iconSymbolName
        targetMinor = savingsGoal.targetMinor
        currentSavedMinor = savingsGoal.currentSavedMinor
        targetDate = savingsGoal.targetDate
        linkedWalletID = savingsGoal.linkedWallet?.id
        currencyCode = savingsGoal.currencyCode
        sortOrder = savingsGoal.sortOrder
        isArchived = savingsGoal.isArchived
        createdAt = savingsGoal.createdAt
        updatedAt = savingsGoal.updatedAt
        deletedAt = savingsGoal.deletedAt
        remoteVersion = savingsGoal.remoteVersion
    }

    init(_ savingsGoal: SavingsGoal) {
        id = savingsGoal.id
        name = savingsGoal.name
        iconSymbolName = savingsGoal.iconSymbolName
        targetMinor = savingsGoal.targetMinor
        currentSavedMinor = savingsGoal.currentSavedMinor
        targetDate = savingsGoal.targetDate
        linkedWalletID = savingsGoal.linkedWallet?.id
        currencyCode = savingsGoal.currencyCode
        sortOrder = savingsGoal.sortOrder
        isArchived = savingsGoal.isArchived
        createdAt = savingsGoal.createdAt
        updatedAt = savingsGoal.updatedAt
        deletedAt = savingsGoal.deletedAt
        remoteVersion = savingsGoal.remoteVersion
    }
}

private struct LegacyRecurringBillSnapshot {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let categoryID: UUID?
    let amountMinor: Int64?
    let dueDay: Int
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ recurringBill: MistiaSchemaV3.RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = nil
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ recurringBill: MistiaSchemaV4.RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = nil
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = recurringBill.deletedAt
        remoteVersion = recurringBill.remoteVersion
    }

    init(_ recurringBill: MistiaSchemaV5.RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = nil
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = recurringBill.deletedAt
        remoteVersion = recurringBill.remoteVersion
    }

    init(_ recurringBill: MistiaSchemaV6.RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = nil
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = recurringBill.deletedAt
        remoteVersion = recurringBill.remoteVersion
    }

    init(_ recurringBill: MistiaRecoverySchemaV8.RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = recurringBill.category?.id
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = recurringBill.deletedAt
        remoteVersion = recurringBill.remoteVersion
    }

    init(_ recurringBill: MistiaRecoverySchemaV10.RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = recurringBill.category?.id
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = recurringBill.deletedAt
        remoteVersion = recurringBill.remoteVersion
    }

    init(_ recurringBill: RecurringBillPlan) {
        id = recurringBill.id
        name = recurringBill.name
        iconSymbolName = recurringBill.iconSymbolName
        categoryID = recurringBill.category?.id
        amountMinor = recurringBill.amountMinor
        dueDay = recurringBill.dueDay
        frequencyMonths = recurringBill.frequencyMonths
        paymentWalletID = recurringBill.paymentWallet?.id
        currencyCode = recurringBill.currencyCode
        isArchived = recurringBill.isArchived
        createdAt = recurringBill.createdAt
        updatedAt = recurringBill.updatedAt
        deletedAt = recurringBill.deletedAt
        remoteVersion = recurringBill.remoteVersion
    }
}

private struct LegacyInstallmentPlanSnapshot {
    let id: UUID
    let name: String
    let iconSymbolName: String
    let amountPerCycleMinor: Int64
    let dueDay: Int
    let totalCycles: Int?
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ installmentPlan: MistiaSchemaV3.InstallmentPlan) {
        id = installmentPlan.id
        name = installmentPlan.name
        iconSymbolName = installmentPlan.iconSymbolName
        amountPerCycleMinor = installmentPlan.amountPerCycleMinor
        dueDay = installmentPlan.dueDay
        totalCycles = installmentPlan.totalCycles
        frequencyMonths = installmentPlan.frequencyMonths
        paymentWalletID = installmentPlan.paymentWallet?.id
        currencyCode = installmentPlan.currencyCode
        isArchived = installmentPlan.isArchived
        createdAt = installmentPlan.createdAt
        updatedAt = installmentPlan.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ installmentPlan: MistiaSchemaV4.InstallmentPlan) {
        id = installmentPlan.id
        name = installmentPlan.name
        iconSymbolName = installmentPlan.iconSymbolName
        amountPerCycleMinor = installmentPlan.amountPerCycleMinor
        dueDay = installmentPlan.dueDay
        totalCycles = installmentPlan.totalCycles
        frequencyMonths = installmentPlan.frequencyMonths
        paymentWalletID = installmentPlan.paymentWallet?.id
        currencyCode = installmentPlan.currencyCode
        isArchived = installmentPlan.isArchived
        createdAt = installmentPlan.createdAt
        updatedAt = installmentPlan.updatedAt
        deletedAt = installmentPlan.deletedAt
        remoteVersion = installmentPlan.remoteVersion
    }

    init(_ installmentPlan: MistiaSchemaV5.InstallmentPlan) {
        id = installmentPlan.id
        name = installmentPlan.name
        iconSymbolName = installmentPlan.iconSymbolName
        amountPerCycleMinor = installmentPlan.amountPerCycleMinor
        dueDay = installmentPlan.dueDay
        totalCycles = installmentPlan.totalCycles
        frequencyMonths = installmentPlan.frequencyMonths
        paymentWalletID = installmentPlan.paymentWallet?.id
        currencyCode = installmentPlan.currencyCode
        isArchived = installmentPlan.isArchived
        createdAt = installmentPlan.createdAt
        updatedAt = installmentPlan.updatedAt
        deletedAt = installmentPlan.deletedAt
        remoteVersion = installmentPlan.remoteVersion
    }

    init(_ installmentPlan: MistiaSchemaV6.InstallmentPlan) {
        id = installmentPlan.id
        name = installmentPlan.name
        iconSymbolName = installmentPlan.iconSymbolName
        amountPerCycleMinor = installmentPlan.amountPerCycleMinor
        dueDay = installmentPlan.dueDay
        totalCycles = installmentPlan.totalCycles
        frequencyMonths = installmentPlan.frequencyMonths
        paymentWalletID = installmentPlan.paymentWallet?.id
        currencyCode = installmentPlan.currencyCode
        isArchived = installmentPlan.isArchived
        createdAt = installmentPlan.createdAt
        updatedAt = installmentPlan.updatedAt
        deletedAt = installmentPlan.deletedAt
        remoteVersion = installmentPlan.remoteVersion
    }

    init(_ installmentPlan: MistiaRecoverySchemaV8.InstallmentPlan) {
        id = installmentPlan.id
        name = installmentPlan.name
        iconSymbolName = installmentPlan.iconSymbolName
        amountPerCycleMinor = installmentPlan.amountPerCycleMinor
        dueDay = installmentPlan.dueDay
        totalCycles = installmentPlan.totalCycles
        frequencyMonths = installmentPlan.frequencyMonths
        paymentWalletID = installmentPlan.paymentWallet?.id
        currencyCode = installmentPlan.currencyCode
        isArchived = installmentPlan.isArchived
        createdAt = installmentPlan.createdAt
        updatedAt = installmentPlan.updatedAt
        deletedAt = installmentPlan.deletedAt
        remoteVersion = installmentPlan.remoteVersion
    }

    init(_ installmentPlan: InstallmentPlan) {
        id = installmentPlan.id
        name = installmentPlan.name
        iconSymbolName = installmentPlan.iconSymbolName
        amountPerCycleMinor = installmentPlan.amountPerCycleMinor
        dueDay = installmentPlan.dueDay
        totalCycles = installmentPlan.totalCycles
        frequencyMonths = installmentPlan.frequencyMonths
        paymentWalletID = installmentPlan.paymentWallet?.id
        currencyCode = installmentPlan.currencyCode
        isArchived = installmentPlan.isArchived
        createdAt = installmentPlan.createdAt
        updatedAt = installmentPlan.updatedAt
        deletedAt = installmentPlan.deletedAt
        remoteVersion = installmentPlan.remoteVersion
    }
}

private struct LegacyDueOccurrenceSnapshot {
    let id: UUID
    let sourceKindRawValue: String
    let sourceID: UUID
    let selectedMonthKey: String
    let scheduledDate: Date
    let amountMinorSnapshot: Int64?
    let statusRawValue: String
    let paidAt: Date?
    let linkedTransactionID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let remoteVersion: Int64

    init(_ occurrence: MistiaSchemaV3.DueOccurrenceRecord) {
        id = occurrence.id
        sourceKindRawValue = occurrence.sourceKindRawValue
        sourceID = occurrence.sourceID
        selectedMonthKey = occurrence.selectedMonthKey
        scheduledDate = occurrence.scheduledDate
        amountMinorSnapshot = occurrence.amountMinorSnapshot
        statusRawValue = occurrence.statusRawValue
        paidAt = occurrence.paidAt
        linkedTransactionID = occurrence.linkedTransactionID
        createdAt = occurrence.createdAt
        updatedAt = occurrence.updatedAt
        deletedAt = nil
        remoteVersion = 0
    }

    init(_ occurrence: MistiaSchemaV4.DueOccurrenceRecord) {
        id = occurrence.id
        sourceKindRawValue = occurrence.sourceKindRawValue
        sourceID = occurrence.sourceID
        selectedMonthKey = occurrence.selectedMonthKey
        scheduledDate = occurrence.scheduledDate
        amountMinorSnapshot = occurrence.amountMinorSnapshot
        statusRawValue = occurrence.statusRawValue
        paidAt = occurrence.paidAt
        linkedTransactionID = occurrence.linkedTransactionID
        createdAt = occurrence.createdAt
        updatedAt = occurrence.updatedAt
        deletedAt = occurrence.deletedAt
        remoteVersion = occurrence.remoteVersion
    }

    init(_ occurrence: MistiaSchemaV5.DueOccurrenceRecord) {
        id = occurrence.id
        sourceKindRawValue = occurrence.sourceKindRawValue
        sourceID = occurrence.sourceID
        selectedMonthKey = occurrence.selectedMonthKey
        scheduledDate = occurrence.scheduledDate
        amountMinorSnapshot = occurrence.amountMinorSnapshot
        statusRawValue = occurrence.statusRawValue
        paidAt = occurrence.paidAt
        linkedTransactionID = occurrence.linkedTransactionID
        createdAt = occurrence.createdAt
        updatedAt = occurrence.updatedAt
        deletedAt = occurrence.deletedAt
        remoteVersion = occurrence.remoteVersion
    }

    init(_ occurrence: MistiaSchemaV6.DueOccurrenceRecord) {
        id = occurrence.id
        sourceKindRawValue = occurrence.sourceKindRawValue
        sourceID = occurrence.sourceID
        selectedMonthKey = occurrence.selectedMonthKey
        scheduledDate = occurrence.scheduledDate
        amountMinorSnapshot = occurrence.amountMinorSnapshot
        statusRawValue = occurrence.statusRawValue
        paidAt = occurrence.paidAt
        linkedTransactionID = occurrence.linkedTransactionID
        createdAt = occurrence.createdAt
        updatedAt = occurrence.updatedAt
        deletedAt = occurrence.deletedAt
        remoteVersion = occurrence.remoteVersion
    }

    init(_ occurrence: MistiaRecoverySchemaV8.DueOccurrenceRecord) {
        id = occurrence.id
        sourceKindRawValue = occurrence.sourceKindRawValue
        sourceID = occurrence.sourceID
        selectedMonthKey = occurrence.selectedMonthKey
        scheduledDate = occurrence.scheduledDate
        amountMinorSnapshot = occurrence.amountMinorSnapshot
        statusRawValue = occurrence.statusRawValue
        paidAt = occurrence.paidAt
        linkedTransactionID = occurrence.linkedTransactionID
        createdAt = occurrence.createdAt
        updatedAt = occurrence.updatedAt
        deletedAt = occurrence.deletedAt
        remoteVersion = occurrence.remoteVersion
    }

    init(_ occurrence: DueOccurrenceRecord) {
        id = occurrence.id
        sourceKindRawValue = occurrence.sourceKindRawValue
        sourceID = occurrence.sourceID
        selectedMonthKey = occurrence.selectedMonthKey
        scheduledDate = occurrence.scheduledDate
        amountMinorSnapshot = occurrence.amountMinorSnapshot
        statusRawValue = occurrence.statusRawValue
        paidAt = occurrence.paidAt
        linkedTransactionID = occurrence.linkedTransactionID
        createdAt = occurrence.createdAt
        updatedAt = occurrence.updatedAt
        deletedAt = occurrence.deletedAt
        remoteVersion = occurrence.remoteVersion
    }
}

private struct LegacySyncConflictSnapshot {
    let id: UUID
    let entityRawValue: String
    let recordID: UUID
    let conflictKindRawValue: String
    let localPayloadJSON: String
    let remotePayloadJSON: String
    let baseVersion: Int64
    let remoteVersion: Int64
    let createdAt: Date

    init(_ conflict: MistiaSchemaV4.SyncConflict) {
        id = conflict.id
        entityRawValue = conflict.entityRawValue
        recordID = conflict.recordID
        conflictKindRawValue = conflict.conflictKindRawValue
        localPayloadJSON = conflict.localPayloadJSON
        remotePayloadJSON = conflict.remotePayloadJSON
        baseVersion = conflict.baseVersion
        remoteVersion = conflict.remoteVersion
        createdAt = conflict.createdAt
    }

    init(_ conflict: MistiaSchemaV5.SyncConflict) {
        id = conflict.id
        entityRawValue = conflict.entityRawValue
        recordID = conflict.recordID
        conflictKindRawValue = conflict.conflictKindRawValue
        localPayloadJSON = conflict.localPayloadJSON
        remotePayloadJSON = conflict.remotePayloadJSON
        baseVersion = conflict.baseVersion
        remoteVersion = conflict.remoteVersion
        createdAt = conflict.createdAt
    }

    init(_ conflict: MistiaSchemaV6.SyncConflict) {
        id = conflict.id
        entityRawValue = conflict.entityRawValue
        recordID = conflict.recordID
        conflictKindRawValue = conflict.conflictKindRawValue
        localPayloadJSON = conflict.localPayloadJSON
        remotePayloadJSON = conflict.remotePayloadJSON
        baseVersion = conflict.baseVersion
        remoteVersion = conflict.remoteVersion
        createdAt = conflict.createdAt
    }

    init(_ conflict: MistiaRecoverySchemaV8.SyncConflict) {
        id = conflict.id
        entityRawValue = conflict.entityRawValue
        recordID = conflict.recordID
        conflictKindRawValue = conflict.conflictKindRawValue
        localPayloadJSON = conflict.localPayloadJSON
        remotePayloadJSON = conflict.remotePayloadJSON
        baseVersion = conflict.baseVersion
        remoteVersion = conflict.remoteVersion
        createdAt = conflict.createdAt
    }

    init(_ conflict: SyncConflict) {
        id = conflict.id
        entityRawValue = conflict.entityRawValue
        recordID = conflict.recordID
        conflictKindRawValue = conflict.conflictKindRawValue
        localPayloadJSON = conflict.localPayloadJSON
        remotePayloadJSON = conflict.remotePayloadJSON
        baseVersion = conflict.baseVersion
        remoteVersion = conflict.remoteVersion
        createdAt = conflict.createdAt
    }
}

private struct LegacyUserProfileSnapshot {
    let userID: UUID
    let email: String
    let displayName: String
    let avatarFileName: String?
    let birthday: Date?
    let lastSyncAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(_ profile: MistiaSchemaV6.UserAccountProfile) {
        userID = profile.userID
        email = profile.email
        displayName = profile.displayName
        avatarFileName = profile.avatarFileName
        birthday = profile.birthday
        lastSyncAt = nil
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }

    init(_ profile: MistiaRecoverySchemaV8.UserAccountProfile) {
        userID = profile.userID
        email = profile.email
        displayName = profile.displayName
        avatarFileName = profile.avatarFileName
        birthday = profile.birthday
        lastSyncAt = nil
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }

    init(_ profile: MistiaRecoverySchemaV10.UserAccountProfile) {
        userID = profile.userID
        email = profile.email
        displayName = profile.displayName
        avatarFileName = profile.avatarFileName
        birthday = profile.birthday
        lastSyncAt = profile.lastSyncAt
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }

    init(_ profile: UserAccountProfile) {
        userID = profile.userID
        email = profile.email
        displayName = profile.displayName
        avatarFileName = profile.avatarFileName
        birthday = profile.birthday
        lastSyncAt = profile.lastSyncAt
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }
}

private struct LegacyOwnedRecordScopeSnapshot {
    let entityRawValue: String
    let recordID: UUID
    let ownerUserID: UUID
    let updatedAt: Date

    init(_ scope: MistiaRecoverySchemaV8.OwnedRecordScope) {
        entityRawValue = scope.entityRawValue
        recordID = scope.recordID
        ownerUserID = scope.ownerUserID
        updatedAt = scope.updatedAt
    }

    init(_ scope: OwnedRecordScope) {
        entityRawValue = scope.entityRawValue
        recordID = scope.recordID
        ownerUserID = scope.ownerUserID
        updatedAt = scope.updatedAt
    }

    init(_ scope: MistiaRecoverySchemaV10.OwnedRecordScope) {
        entityRawValue = scope.entityRawValue
        recordID = scope.recordID
        ownerUserID = scope.ownerUserID
        updatedAt = scope.updatedAt
    }
}

private struct LegacyTransactionAuditSnapshot {
    let transactionID: UUID
    let createdByUserID: UUID
    let lastModifiedByUserID: UUID
    let updatedAt: Date

    init(_ record: TransactionAuditRecord) {
        transactionID = record.transactionID
        createdByUserID = record.createdByUserID
        lastModifiedByUserID = record.lastModifiedByUserID
        updatedAt = record.updatedAt
    }

    init(_ record: MistiaRecoverySchemaV10.TransactionAuditRecord) {
        transactionID = record.transactionID
        createdByUserID = record.createdByUserID
        lastModifiedByUserID = record.lastModifiedByUserID
        updatedAt = record.updatedAt
    }
}

private enum MistiaRecoverySchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(10, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            MistiaRecoverySchemaV8.LedgerWallet.self,
            MistiaRecoverySchemaV8.CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self,
            BudgetPlan.self,
            MistiaRecoverySchemaV8.SavingsGoal.self,
            RecurringBillPlan.self,
            MistiaRecoverySchemaV8.InstallmentPlan.self,
            MistiaRecoverySchemaV8.DueOccurrenceRecord.self,
            MistiaRecoverySchemaV8.SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self
        ]
    }

    @Model
    final class TransactionCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var favoriteRawValue: Bool?
        var parentCategory: TransactionCategory?
        @Relationship(deleteRule: .nullify, inverse: \TransactionCategory.parentCategory) var childCategories: [TransactionCategory] = []
        var hierarchyRoleRawValue: String?
        var systemKey: String?
        var isSystem: Bool
        var cloudSyncEnabled: Bool
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            favoriteRawValue: Bool? = false,
            parentCategory: TransactionCategory? = nil,
            hierarchyRoleRawValue: String? = nil,
            systemKey: String? = nil,
            isSystem: Bool = false,
            cloudSyncEnabled: Bool = false,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.favoriteRawValue = favoriteRawValue
            self.parentCategory = parentCategory
            self.hierarchyRoleRawValue = hierarchyRoleRawValue
            self.systemKey = systemKey
            self.isSystem = isSystem
            self.cloudSyncEnabled = cloudSyncEnabled
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class UserAccountProfile {
        @Attribute(.unique) var userID: UUID
        var email: String
        var displayName: String
        var avatarFileName: String?
        var birthday: Date?
        var lastSyncAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            userID: UUID,
            email: String,
            displayName: String,
            avatarFileName: String? = nil,
            birthday: Date? = nil,
            lastSyncAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.userID = userID
            self.email = email
            self.displayName = displayName
            self.avatarFileName = avatarFileName
            self.birthday = birthday
            self.lastSyncAt = lastSyncAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class LedgerTransaction {
        @Attribute(.unique) var id: UUID
        var primaryKindRawValue: String
        var transferSubtypeRawValue: String?
        var debtIntentRawValue: String?
        var entryStatusRawValue: String
        var title: String
        var note: String?
        var amountMinor: Int64
        var occurredAt: Date
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var counterpartyName: String?
        var normalizedCounterpartyKey: String?
        var isArchived: Bool
        var archivedAt: Date?
        @Relationship(deleteRule: .nullify) var sourceWallet: MistiaRecoverySchemaV8.LedgerWallet?
        @Relationship(deleteRule: .nullify) var destinationWallet: MistiaRecoverySchemaV8.LedgerWallet?
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?

        init(
            id: UUID = UUID(),
            primaryKindRawValue: String,
            transferSubtypeRawValue: String? = nil,
            debtIntentRawValue: String? = nil,
            entryStatusRawValue: String,
            title: String = "",
            note: String? = nil,
            amountMinor: Int64,
            occurredAt: Date = .now,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0,
            counterpartyName: String? = nil,
            normalizedCounterpartyKey: String? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            sourceWallet: MistiaRecoverySchemaV8.LedgerWallet? = nil,
            destinationWallet: MistiaRecoverySchemaV8.LedgerWallet? = nil,
            category: TransactionCategory? = nil
        ) {
            self.id = id
            self.primaryKindRawValue = primaryKindRawValue
            self.transferSubtypeRawValue = transferSubtypeRawValue
            self.debtIntentRawValue = debtIntentRawValue
            self.entryStatusRawValue = entryStatusRawValue
            self.title = title
            self.note = note
            self.amountMinor = amountMinor
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
            self.counterpartyName = counterpartyName
            self.normalizedCounterpartyKey = normalizedCounterpartyKey
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.sourceWallet = sourceWallet
            self.destinationWallet = destinationWallet
            self.category = category
        }
    }

    @Model
    final class BudgetPlan {
        @Attribute(.unique) var id: UUID
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?
        var monthAnchor: Date
        var limitMinor: Int64
        var rolloverEnabled: Bool
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            category: TransactionCategory? = nil,
            monthAnchor: Date,
            limitMinor: Int64,
            rolloverEnabled: Bool = false,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.category = category
            self.monthAnchor = monthAnchor
            self.limitMinor = limitMinor
            self.rolloverEnabled = rolloverEnabled
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class RecurringBillPlan {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?
        var amountMinor: Int64?
        var dueDay: Int
        var frequencyMonths: Int
        @Relationship(deleteRule: .nullify) var paymentWallet: MistiaRecoverySchemaV8.LedgerWallet?
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String,
            iconSymbolName: String,
            category: TransactionCategory? = nil,
            amountMinor: Int64? = nil,
            dueDay: Int,
            frequencyMonths: Int = 1,
            paymentWallet: MistiaRecoverySchemaV8.LedgerWallet? = nil,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.category = category
            self.amountMinor = amountMinor
            self.dueDay = dueDay
            self.frequencyMonths = frequencyMonths
            self.paymentWallet = paymentWallet
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class OwnedRecordScope {
        @Attribute(.unique) var id: String
        var entityRawValue: String
        var recordID: UUID
        var ownerUserID: UUID
        var updatedAt: Date

        init(
            id: String,
            entityRawValue: String,
            recordID: UUID,
            ownerUserID: UUID,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.entityRawValue = entityRawValue
            self.recordID = recordID
            self.ownerUserID = ownerUserID
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class TransactionAuditRecord {
        @Attribute(.unique) var transactionID: UUID
        var createdByUserID: UUID
        var lastModifiedByUserID: UUID
        var updatedAt: Date

        init(
            transactionID: UUID,
            createdByUserID: UUID,
            lastModifiedByUserID: UUID,
            updatedAt: Date = .now
        ) {
            self.transactionID = transactionID
            self.createdByUserID = createdByUserID
            self.lastModifiedByUserID = lastModifiedByUserID
            self.updatedAt = updatedAt
        }
    }
}

private enum MistiaRecoverySchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(9, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            MistiaRecoverySchemaV8.LedgerWallet.self,
            MistiaRecoverySchemaV8.CreditCardProfile.self,
            MistiaRecoverySchemaV10.TransactionCategory.self,
            MistiaRecoverySchemaV10.LedgerTransaction.self,
            MistiaRecoverySchemaV10.BudgetPlan.self,
            MistiaRecoverySchemaV8.SavingsGoal.self,
            MistiaRecoverySchemaV10.RecurringBillPlan.self,
            MistiaRecoverySchemaV8.InstallmentPlan.self,
            MistiaRecoverySchemaV8.DueOccurrenceRecord.self,
            MistiaRecoverySchemaV8.SyncConflict.self,
            MistiaRecoverySchemaV10.UserAccountProfile.self,
            MistiaRecoverySchemaV10.OwnedRecordScope.self
        ]
    }
}

private enum MistiaRecoverySchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            MistiaRecoverySchemaV8.LedgerWallet.self,
            MistiaRecoverySchemaV8.CreditCardProfile.self,
            MistiaRecoverySchemaV8.TransactionCategory.self,
            MistiaRecoverySchemaV8.LedgerTransaction.self,
            MistiaRecoverySchemaV8.BudgetPlan.self,
            MistiaRecoverySchemaV8.SavingsGoal.self,
            MistiaRecoverySchemaV8.RecurringBillPlan.self,
            MistiaRecoverySchemaV8.InstallmentPlan.self,
            MistiaRecoverySchemaV8.DueOccurrenceRecord.self,
            MistiaRecoverySchemaV8.SyncConflict.self,
            MistiaRecoverySchemaV8.UserAccountProfile.self
        ]
    }
}

private enum MistiaRecoverySchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerWallet.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self,
            BudgetPlan.self,
            SavingsGoal.self,
            RecurringBillPlan.self,
            InstallmentPlan.self,
            DueOccurrenceRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self
        ]
    }

    @Model
    final class LedgerWallet {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var currencyCode: String
        var openingBalanceMinor: Int64
        var institutionDisplayName: String?
        var institutionPresetKey: String?
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var creditCardProfile: CreditCardProfile?

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            currencyCode: String = "JPY",
            openingBalanceMinor: Int64 = 0,
            institutionDisplayName: String? = nil,
            institutionPresetKey: String? = nil,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.currencyCode = currencyCode
            self.openingBalanceMinor = openingBalanceMinor
            self.institutionDisplayName = institutionDisplayName
            self.institutionPresetKey = institutionPresetKey
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class CreditCardProfile {
        @Attribute(.unique) var id: UUID
        var issuerName: String
        var networkRawValue: String
        var last4: String
        var creditLimitMinor: Int64
        var statementClosingDay: Int
        var paymentDueDay: Int
        var notes: String?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var wallet: LedgerWallet?
        var paymentSourceWallet: LedgerWallet?

        init(
            id: UUID = UUID(),
            issuerName: String = "",
            networkRawValue: String = CreditCardNetwork.visa.rawValue,
            last4: String = "",
            creditLimitMinor: Int64 = 0,
            statementClosingDay: Int = 25,
            paymentDueDay: Int = 10,
            notes: String? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0,
            wallet: LedgerWallet? = nil,
            paymentSourceWallet: LedgerWallet? = nil
        ) {
            self.id = id
            self.issuerName = issuerName
            self.networkRawValue = networkRawValue
            self.last4 = last4
            self.creditLimitMinor = creditLimitMinor
            self.statementClosingDay = statementClosingDay
            self.paymentDueDay = paymentDueDay
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
            self.wallet = wallet
            self.paymentSourceWallet = paymentSourceWallet
        }
    }

    @Model
    final class TransactionCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var favoriteRawValue: Bool?
        var parentCategory: TransactionCategory?
        @Relationship(deleteRule: .nullify, inverse: \TransactionCategory.parentCategory) var childCategories: [TransactionCategory] = []
        var hierarchyRoleRawValue: String?
        var systemKey: String?
        var isSystem: Bool
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            favoriteRawValue: Bool? = false,
            parentCategory: TransactionCategory? = nil,
            hierarchyRoleRawValue: String? = nil,
            systemKey: String? = nil,
            isSystem: Bool = false,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.favoriteRawValue = favoriteRawValue
            self.parentCategory = parentCategory
            self.hierarchyRoleRawValue = hierarchyRoleRawValue
            self.systemKey = systemKey
            self.isSystem = isSystem
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class LedgerTransaction {
        @Attribute(.unique) var id: UUID
        var primaryKindRawValue: String
        var transferSubtypeRawValue: String?
        var debtIntentRawValue: String?
        var entryStatusRawValue: String
        var title: String
        var note: String?
        var amountMinor: Int64
        var occurredAt: Date
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64
        var counterpartyName: String?
        var normalizedCounterpartyKey: String?
        var isArchived: Bool
        var archivedAt: Date?
        @Relationship(deleteRule: .nullify) var sourceWallet: LedgerWallet?
        @Relationship(deleteRule: .nullify) var destinationWallet: LedgerWallet?
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?

        init(
            id: UUID = UUID(),
            primaryKindRawValue: String,
            transferSubtypeRawValue: String? = nil,
            debtIntentRawValue: String? = nil,
            entryStatusRawValue: String,
            title: String = "",
            note: String? = nil,
            amountMinor: Int64,
            occurredAt: Date = .now,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0,
            counterpartyName: String? = nil,
            normalizedCounterpartyKey: String? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            sourceWallet: LedgerWallet? = nil,
            destinationWallet: LedgerWallet? = nil,
            category: TransactionCategory? = nil
        ) {
            self.id = id
            self.primaryKindRawValue = primaryKindRawValue
            self.transferSubtypeRawValue = transferSubtypeRawValue
            self.debtIntentRawValue = debtIntentRawValue
            self.entryStatusRawValue = entryStatusRawValue
            self.title = title
            self.note = note
            self.amountMinor = amountMinor
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
            self.counterpartyName = counterpartyName
            self.normalizedCounterpartyKey = normalizedCounterpartyKey
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.sourceWallet = sourceWallet
            self.destinationWallet = destinationWallet
            self.category = category
        }
    }

    @Model
    final class BudgetPlan {
        @Attribute(.unique) var id: UUID
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?
        var monthAnchor: Date
        var limitMinor: Int64
        var rolloverEnabled: Bool
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            category: TransactionCategory? = nil,
            monthAnchor: Date,
            limitMinor: Int64,
            rolloverEnabled: Bool = false,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.category = category
            self.monthAnchor = monthAnchor
            self.limitMinor = limitMinor
            self.rolloverEnabled = rolloverEnabled
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class SavingsGoal {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        var targetMinor: Int64
        var currentSavedMinor: Int64
        var targetDate: Date
        @Relationship(deleteRule: .nullify) var linkedWallet: LedgerWallet?
        var currencyCode: String
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String,
            iconSymbolName: String,
            targetMinor: Int64,
            currentSavedMinor: Int64 = 0,
            targetDate: Date,
            linkedWallet: LedgerWallet? = nil,
            currencyCode: String = "JPY",
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.targetMinor = targetMinor
            self.currentSavedMinor = currentSavedMinor
            self.targetDate = targetDate
            self.linkedWallet = linkedWallet
            self.currencyCode = currencyCode
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class RecurringBillPlan {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?
        var amountMinor: Int64?
        var dueDay: Int
        var frequencyMonths: Int
        @Relationship(deleteRule: .nullify) var paymentWallet: LedgerWallet?
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String,
            iconSymbolName: String,
            category: TransactionCategory? = nil,
            amountMinor: Int64? = nil,
            dueDay: Int,
            frequencyMonths: Int = 1,
            paymentWallet: LedgerWallet? = nil,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.category = category
            self.amountMinor = amountMinor
            self.dueDay = dueDay
            self.frequencyMonths = frequencyMonths
            self.paymentWallet = paymentWallet
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class InstallmentPlan {
        @Attribute(.unique) var id: UUID
        var name: String
        var iconSymbolName: String
        var amountPerCycleMinor: Int64
        var dueDay: Int
        var totalCycles: Int?
        var frequencyMonths: Int
        @Relationship(deleteRule: .nullify) var paymentWallet: LedgerWallet?
        var currencyCode: String
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            name: String,
            iconSymbolName: String,
            amountPerCycleMinor: Int64,
            dueDay: Int,
            totalCycles: Int? = nil,
            frequencyMonths: Int = 1,
            paymentWallet: LedgerWallet? = nil,
            currencyCode: String = "JPY",
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.name = name
            self.iconSymbolName = iconSymbolName
            self.amountPerCycleMinor = amountPerCycleMinor
            self.dueDay = dueDay
            self.totalCycles = totalCycles
            self.frequencyMonths = frequencyMonths
            self.paymentWallet = paymentWallet
            self.currencyCode = currencyCode
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class DueOccurrenceRecord {
        @Attribute(.unique) var id: UUID
        var sourceKindRawValue: String
        var sourceID: UUID
        var selectedMonthKey: String
        var scheduledDate: Date
        var amountMinorSnapshot: Int64?
        var statusRawValue: String
        var paidAt: Date?
        var linkedTransactionID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            sourceKindRawValue: String,
            sourceID: UUID,
            selectedMonthKey: String,
            scheduledDate: Date,
            amountMinorSnapshot: Int64? = nil,
            statusRawValue: String,
            paidAt: Date? = nil,
            linkedTransactionID: UUID? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.sourceKindRawValue = sourceKindRawValue
            self.sourceID = sourceID
            self.selectedMonthKey = selectedMonthKey
            self.scheduledDate = scheduledDate
            self.amountMinorSnapshot = amountMinorSnapshot
            self.statusRawValue = statusRawValue
            self.paidAt = paidAt
            self.linkedTransactionID = linkedTransactionID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }

    @Model
    final class SyncConflict {
        @Attribute(.unique) var id: UUID
        var entityRawValue: String
        var recordID: UUID
        var conflictKindRawValue: String
        var localPayloadJSON: String
        var remotePayloadJSON: String
        var baseVersion: Int64
        var remoteVersion: Int64
        var createdAt: Date

        init(
            id: UUID = UUID(),
            entityRawValue: String,
            recordID: UUID,
            conflictKindRawValue: String,
            localPayloadJSON: String,
            remotePayloadJSON: String,
            baseVersion: Int64,
            remoteVersion: Int64,
            createdAt: Date = .now
        ) {
            self.id = id
            self.entityRawValue = entityRawValue
            self.recordID = recordID
            self.conflictKindRawValue = conflictKindRawValue
            self.localPayloadJSON = localPayloadJSON
            self.remotePayloadJSON = remotePayloadJSON
            self.baseVersion = baseVersion
            self.remoteVersion = remoteVersion
            self.createdAt = createdAt
        }
    }

    @Model
    final class UserAccountProfile {
        @Attribute(.unique) var userID: UUID
        var email: String
        var displayName: String
        var avatarFileName: String?
        var birthday: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            userID: UUID,
            email: String,
            displayName: String,
            avatarFileName: String? = nil,
            birthday: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.userID = userID
            self.email = email
            self.displayName = displayName
            self.avatarFileName = avatarFileName
            self.birthday = birthday
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class OwnedRecordScope {
        @Attribute(.unique) var id: String
        var entityRawValue: String
        var recordID: UUID
        var ownerUserID: UUID
        var updatedAt: Date

        init(
            id: String,
            entityRawValue: String,
            recordID: UUID,
            ownerUserID: UUID,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.entityRawValue = entityRawValue
            self.recordID = recordID
            self.ownerUserID = ownerUserID
            self.updatedAt = updatedAt
        }
    }
}

private enum MistiaLegacyAccountSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerAccount.self,
            CreditCardProfile.self,
            TransactionCategory.self
        ]
    }

    @Model
    final class LedgerAccount {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var currencyCode: String
        var openingBalanceMinor: Int64
        var institutionDisplayName: String?
        var institutionPresetKey: String?
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var creditCardProfile: CreditCardProfile?

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            currencyCode: String = "JPY",
            openingBalanceMinor: Int64 = 0,
            institutionDisplayName: String? = nil,
            institutionPresetKey: String? = nil,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.currencyCode = currencyCode
            self.openingBalanceMinor = openingBalanceMinor
            self.institutionDisplayName = institutionDisplayName
            self.institutionPresetKey = institutionPresetKey
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class CreditCardProfile {
        @Attribute(.unique) var id: UUID
        var issuerName: String
        var networkRawValue: String
        var last4: String
        var creditLimitMinor: Int64
        var statementClosingDay: Int
        var paymentDueDay: Int
        var notes: String?
        var createdAt: Date
        var updatedAt: Date
        var account: LedgerAccount?
        var paymentSourceAccount: LedgerAccount?

        init(
            id: UUID = UUID(),
            issuerName: String = "",
            networkRawValue: String = CreditCardNetwork.visa.rawValue,
            last4: String = "",
            creditLimitMinor: Int64 = 0,
            statementClosingDay: Int = 25,
            paymentDueDay: Int = 10,
            notes: String? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            account: LedgerAccount? = nil,
            paymentSourceAccount: LedgerAccount? = nil
        ) {
            self.id = id
            self.issuerName = issuerName
            self.networkRawValue = networkRawValue
            self.last4 = last4
            self.creditLimitMinor = creditLimitMinor
            self.statementClosingDay = statementClosingDay
            self.paymentDueDay = paymentDueDay
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.account = account
            self.paymentSourceAccount = paymentSourceAccount
        }
    }

    @Model
    final class TransactionCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var isSystem: Bool
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            isSystem: Bool = false,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.isSystem = isSystem
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

private enum MistiaLegacyAccountSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerAccount.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self
        ]
    }

    @Model
    final class LedgerAccount {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var currencyCode: String
        var openingBalanceMinor: Int64
        var institutionDisplayName: String?
        var institutionPresetKey: String?
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date
        var creditCardProfile: CreditCardProfile?

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            currencyCode: String = "JPY",
            openingBalanceMinor: Int64 = 0,
            institutionDisplayName: String? = nil,
            institutionPresetKey: String? = nil,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.currencyCode = currencyCode
            self.openingBalanceMinor = openingBalanceMinor
            self.institutionDisplayName = institutionDisplayName
            self.institutionPresetKey = institutionPresetKey
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class CreditCardProfile {
        @Attribute(.unique) var id: UUID
        var issuerName: String
        var networkRawValue: String
        var last4: String
        var creditLimitMinor: Int64
        var statementClosingDay: Int
        var paymentDueDay: Int
        var notes: String?
        var createdAt: Date
        var updatedAt: Date
        var account: LedgerAccount?
        var paymentSourceAccount: LedgerAccount?

        init(
            id: UUID = UUID(),
            issuerName: String = "",
            networkRawValue: String = CreditCardNetwork.visa.rawValue,
            last4: String = "",
            creditLimitMinor: Int64 = 0,
            statementClosingDay: Int = 25,
            paymentDueDay: Int = 10,
            notes: String? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            account: LedgerAccount? = nil,
            paymentSourceAccount: LedgerAccount? = nil
        ) {
            self.id = id
            self.issuerName = issuerName
            self.networkRawValue = networkRawValue
            self.last4 = last4
            self.creditLimitMinor = creditLimitMinor
            self.statementClosingDay = statementClosingDay
            self.paymentDueDay = paymentDueDay
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.account = account
            self.paymentSourceAccount = paymentSourceAccount
        }
    }

    @Model
    final class TransactionCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var iconSymbolName: String
        var iconColorHex: String
        var isSystem: Bool
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            name: String,
            kindRawValue: String,
            iconSymbolName: String,
            iconColorHex: String,
            isSystem: Bool = false,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.iconSymbolName = iconSymbolName
            self.iconColorHex = iconColorHex
            self.isSystem = isSystem
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class LedgerTransaction {
        @Attribute(.unique) var id: UUID
        var primaryKindRawValue: String
        var transferSubtypeRawValue: String?
        var debtIntentRawValue: String?
        var entryStatusRawValue: String
        var title: String
        var note: String?
        var amountMinor: Int64
        var occurredAt: Date
        var createdAt: Date
        var updatedAt: Date
        var counterpartyName: String?
        var normalizedCounterpartyKey: String?

        @Relationship(deleteRule: .nullify) var sourceAccount: LedgerAccount?
        @Relationship(deleteRule: .nullify) var destinationAccount: LedgerAccount?
        @Relationship(deleteRule: .nullify) var category: TransactionCategory?

        init(
            id: UUID = UUID(),
            primaryKindRawValue: String,
            transferSubtypeRawValue: String? = nil,
            debtIntentRawValue: String? = nil,
            entryStatusRawValue: String = TransactionEntryStatus.posted.rawValue,
            title: String = "",
            note: String? = nil,
            amountMinor: Int64,
            occurredAt: Date = .now,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            sourceAccount: LedgerAccount? = nil,
            destinationAccount: LedgerAccount? = nil,
            category: TransactionCategory? = nil,
            counterpartyName: String? = nil,
            normalizedCounterpartyKey: String? = nil
        ) {
            self.id = id
            self.primaryKindRawValue = primaryKindRawValue
            self.transferSubtypeRawValue = transferSubtypeRawValue
            self.debtIntentRawValue = debtIntentRawValue
            self.entryStatusRawValue = entryStatusRawValue
            self.title = title
            self.note = note
            self.amountMinor = amountMinor
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.sourceAccount = sourceAccount
            self.destinationAccount = destinationAccount
            self.category = category
            self.counterpartyName = counterpartyName
            self.normalizedCounterpartyKey = normalizedCounterpartyKey
        }
    }
}
