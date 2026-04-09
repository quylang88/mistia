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
            TransactionCategory.self
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

enum MistiaSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerWallet.self,
            CreditCardProfile.self,
            TransactionCategory.self,
            LedgerTransaction.self
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
            DueOccurrenceRecord.self
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
            SyncConflict.self
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
            sourceWallet: LedgerWallet? = nil,
            destinationWallet: LedgerWallet? = nil,
            category: TransactionCategory? = nil,
            counterpartyName: String? = nil,
            normalizedCounterpartyKey: String? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil
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
            self.sourceWallet = sourceWallet
            self.destinationWallet = destinationWallet
            self.category = category
            self.counterpartyName = counterpartyName
            self.normalizedCounterpartyKey = normalizedCounterpartyKey
            self.isArchived = isArchived
            self.archivedAt = archivedAt
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
            statusRawValue: String = PlanningDueOccurrenceStatus.pending.rawValue,
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
}

enum MistiaSchemaV5: VersionedSchema {
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
            SyncConflict.self
        ]
    }
}

enum MistiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MistiaSchemaV1.self, MistiaSchemaV2.self, MistiaSchemaV3.self, MistiaSchemaV4.self, MistiaSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: MistiaSchemaV1.self, toVersion: MistiaSchemaV2.self),
            .lightweight(fromVersion: MistiaSchemaV2.self, toVersion: MistiaSchemaV3.self),
            .lightweight(fromVersion: MistiaSchemaV3.self, toVersion: MistiaSchemaV4.self),
            .lightweight(fromVersion: MistiaSchemaV4.self, toVersion: MistiaSchemaV5.self)
        ]
    }
}
