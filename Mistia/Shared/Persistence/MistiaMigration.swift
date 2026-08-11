import Foundation
import SwiftData

enum MistiaSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
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
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self
        ]
    }
}

enum MistiaSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
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
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self
        ]
    }
}

enum MistiaSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
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
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self
        ]
    }
}

enum MistiaSchemaV4: VersionedSchema {
    typealias LedgerWallet = MistiaSchemaV4Models.LedgerWallet
    typealias CreditCardProfile = MistiaSchemaV4Models.CreditCardProfile
    typealias TransactionCategory = MistiaSchemaV4Models.TransactionCategory
    typealias LedgerTransaction = MistiaSchemaV4Models.LedgerTransaction
    typealias TransactionReceiptImage = MistiaSchemaV4Models.TransactionReceiptImage
    typealias BudgetPlan = MistiaSchemaV4Models.BudgetPlan
    typealias SavingsGoal = MistiaSchemaV4Models.SavingsGoal
    typealias RecurringBillPlan = MistiaSchemaV4Models.RecurringBillPlan
    typealias InstallmentPlan = MistiaSchemaV4Models.InstallmentPlan
    typealias DueOccurrenceRecord = MistiaSchemaV4Models.DueOccurrenceRecord
    typealias AppNotificationRecord = MistiaSchemaV4Models.AppNotificationRecord
    typealias SyncConflict = MistiaSchemaV4Models.SyncConflict
    typealias UserAccountProfile = MistiaSchemaV4Models.UserAccountProfile
    typealias OwnedRecordScope = MistiaSchemaV4Models.OwnedRecordScope
    typealias TransactionAuditRecord = MistiaSchemaV4Models.TransactionAuditRecord

    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
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
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self
        ]
    }
}

enum MistiaSchemaV5: VersionedSchema {
    typealias LedgerTransaction = MistiaSchemaV5Models.LedgerTransaction

    static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
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
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self
        ]
    }
}

enum MistiaSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerWallet.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self,
            SettlementGroup.self,
            SettlementParticipant.self,
            BudgetPlan.self,
            SavingsGoal.self,
            RecurringBillPlan.self,
            InstallmentPlan.self,
            DueOccurrenceRecord.self,
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self
        ]
    }
}

enum MistiaSchemaV7: VersionedSchema {
    typealias InvestmentAsset = MistiaSchemaV7InvestmentModels.InvestmentAsset
    typealias InvestmentTrade = MistiaSchemaV7InvestmentModels.InvestmentTrade

    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerWallet.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self,
            SettlementGroup.self,
            SettlementParticipant.self,
            BudgetPlan.self,
            SavingsGoal.self,
            RecurringBillPlan.self,
            InstallmentPlan.self,
            DueOccurrenceRecord.self,
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self,
            InvestmentChannel.self,
            InvestmentAsset.self,
            InvestmentTrade.self,
            InvestmentValuation.self,
            InvestmentWalletPosting.self
        ]
    }
}

enum MistiaSchemaV8: VersionedSchema {
    typealias InvestmentAsset = MistiaSchemaV8InvestmentModels.InvestmentAsset

    static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerWallet.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self,
            SettlementGroup.self,
            SettlementParticipant.self,
            BudgetPlan.self,
            SavingsGoal.self,
            RecurringBillPlan.self,
            InstallmentPlan.self,
            DueOccurrenceRecord.self,
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self,
            InvestmentChannel.self,
            InvestmentAsset.self,
            InvestmentTrade.self,
            InvestmentValuation.self,
            InvestmentWalletPosting.self
        ]
    }
}

enum MistiaSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(9, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerWallet.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self,
            SettlementGroup.self,
            SettlementParticipant.self,
            BudgetPlan.self,
            SavingsGoal.self,
            RecurringBillPlan.self,
            InstallmentPlan.self,
            DueOccurrenceRecord.self,
            AppNotificationRecord.self,
            SyncConflict.self,
            UserAccountProfile.self,
            OwnedRecordScope.self,
            TransactionAuditRecord.self,
            TransactionReceiptImage.self,
            InvestmentChannel.self,
            InvestmentAsset.self,
            InvestmentTrade.self,
            InvestmentWalletPosting.self
        ]
    }
}

enum MistiaLegacyV4ToV5MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MistiaSchemaV4.self, MistiaSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.custom(
                fromVersion: MistiaSchemaV4.self,
                toVersion: MistiaSchemaV5.self,
                willMigrate: nil,
                didMigrate: { context in
                    let descriptor = FetchDescriptor<RecurringBillPlan>()
                    let bills = try context.fetch(descriptor)
                    var didUpdate = false

                    for bill in bills where bill.scheduleKindRawValue == recurringBillPausedScheduleKindRawValue {
                        bill.isPaused = true
                        bill.pausedAt = bill.paymentStartDate
                        bill.resumeStartMonth = bill.autoPayDate
                        bill.scheduleKindRawValue = PlanningBillScheduleKind.recurring.rawValue
                        bill.paymentStartDate = nil
                        bill.autoPayDate = nil
                        didUpdate = true
                    }

                    if didUpdate {
                        try context.save()
                    }
                }
            )
        ]
    }
}

enum MistiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MistiaSchemaV4.self,
            MistiaSchemaV5.self,
            MistiaSchemaV6.self,
            MistiaSchemaV7.self,
            MistiaSchemaV8.self,
            MistiaSchemaV9.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.custom(
                fromVersion: MistiaSchemaV4.self,
                toVersion: MistiaSchemaV5.self,
                willMigrate: nil,
                didMigrate: { context in
                    let descriptor = FetchDescriptor<RecurringBillPlan>()
                    let bills = try context.fetch(descriptor)
                    var didUpdate = false

                    for bill in bills where bill.scheduleKindRawValue == recurringBillPausedScheduleKindRawValue {
                        bill.isPaused = true
                        bill.pausedAt = bill.paymentStartDate
                        bill.resumeStartMonth = bill.autoPayDate
                        bill.scheduleKindRawValue = PlanningBillScheduleKind.recurring.rawValue
                        bill.paymentStartDate = nil
                        bill.autoPayDate = nil
                        didUpdate = true
                    }

                    if didUpdate {
                        try context.save()
                    }
                }
            ),
            MigrationStage.lightweight(
                fromVersion: MistiaSchemaV6.self,
                toVersion: MistiaSchemaV7.self
            ),
            MigrationStage.custom(
                fromVersion: MistiaSchemaV7.self,
                toVersion: MistiaSchemaV8.self,
                willMigrate: { context in
                    try InvestmentV8Migration.validateLegacyStoreBeforeFieldRemoval(
                        context: context
                    )
                },
                didMigrate: { context in
                    try InvestmentPersistenceService.rebuildDerivedAccountingForV8(context: context)
                }
            ),
            MigrationStage.custom(
                fromVersion: MistiaSchemaV8.self,
                toVersion: MistiaSchemaV9.self,
                willMigrate: nil,
                didMigrate: { context in
                    try InvestmentPersistenceService.rebuildDerivedAccountingForFIFO(
                        context: context
                    )
                }
            )
        ]
    }
}

private enum InvestmentV8Migration {
    static func validateLegacyStoreBeforeFieldRemoval(
        context: ModelContext
    ) throws {
        let assets = try context.fetch(
            FetchDescriptor<MistiaSchemaV7.InvestmentAsset>()
        ).filter { $0.deletedAt == nil }
        let trades = try context.fetch(
            FetchDescriptor<MistiaSchemaV7.InvestmentTrade>()
        ).filter { $0.deletedAt == nil }
        let tradesByAssetID = Dictionary(grouping: trades, by: \.assetID)
        let wallets = try context.fetch(FetchDescriptor<LedgerWallet>())
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })

        for asset in assets {
            let assetTrades = tradesByAssetID[asset.id] ?? []
            guard !assetTrades.isEmpty else { continue }
            guard walletsByID[
                InvestmentSystemWalletIdentity.walletID(ownerUserID: asset.ownerUserID)
            ] != nil else {
                throw InvestmentPersistenceError.missingWallet
            }

            let inputs = try assetTrades.map { trade in
                guard let kind = InvestmentTradeKind(rawValue: trade.kindRawValue),
                      let quantity = InvestmentDecimalCoding.decimal(
                          from: trade.quantityDecimalString
                      ) else {
                    throw InvestmentPersistenceError.invalidTradeInput
                }
                return InvestmentTradeInput(
                    id: trade.id,
                    kind: kind,
                    quantity: quantity,
                    accountingGrossAmountMinor: trade.accountingGrossAmountMinor,
                    occurredAt: trade.occurredAt,
                    createdAt: trade.createdAt
                )
            }
            _ = try InvestmentAccountingEngine.recalculate(trades: inputs)

            for trade in assetTrades {
                let walletID = trade.kindRawValue == InvestmentTradeKind.buy.rawValue
                    ? trade.fundingWalletID
                    : trade.capitalReturnWalletID
                guard let walletID, let wallet = walletsByID[walletID] else {
                    throw InvestmentPersistenceError.missingWallet
                }

                let sourceCurrency: String
                let destinationCurrency: String
                let rateString: String?
                if trade.kindRawValue == InvestmentTradeKind.buy.rawValue {
                    sourceCurrency = wallet.currencyCode
                    destinationCurrency = trade.accountingCurrencyCode
                    rateString = trade.fundingToAccountingRateDecimalString
                } else {
                    sourceCurrency = trade.accountingCurrencyCode
                    destinationCurrency = wallet.currencyCode
                    rateString = trade.accountingToCapitalReturnRateDecimalString
                }
                if MistiaCurrencyLogic.normalizedCode(sourceCurrency)
                    != MistiaCurrencyLogic.normalizedCode(destinationCurrency),
                   !isValidPositiveRate(rateString) {
                    throw InvestmentPersistenceError.missingExchangeRate
                }
            }
        }
    }

    private static func isValidPositiveRate(_ value: String?) -> Bool {
        guard let value,
              let rate = InvestmentDecimalCoding.decimal(from: value) else {
            return false
        }
        return rate > 0
    }
}
