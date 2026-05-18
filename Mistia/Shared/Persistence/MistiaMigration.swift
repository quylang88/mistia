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

enum MistiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MistiaSchemaV1.self,
            MistiaSchemaV2.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: MistiaSchemaV1.self, toVersion: MistiaSchemaV2.self)
        ]
    }
}
