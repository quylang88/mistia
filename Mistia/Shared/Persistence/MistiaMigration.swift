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

enum MistiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        // Older schema declarations in this file reuse the app's live @Model types.
        // Once those types drift, SwiftData can calculate the same checksum for
        // multiple historical versions and crash with "Duplicate version checksums
        // detected" before the store opens.
        //
        // Keep only the current persisted schema in the active plan until a future
        // release introduces properly frozen version-specific model types. Do not
        // add MistiaSchemaV5 for data-only cleanup or a version-label bump.
        [
            MistiaSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        // No staged migration is required while pause state is encoded in existing
        // recurring-bill columns.
        []
    }
}
