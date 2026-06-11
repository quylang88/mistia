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
            SettlementObligation.self,
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

enum MistiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MistiaSchemaV4.self,
            MistiaSchemaV5.self,
            MistiaSchemaV6.self
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
            )
        ]
    }
}
