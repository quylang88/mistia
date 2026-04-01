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

enum MistiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MistiaSchemaV1.self, MistiaSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: MistiaSchemaV1.self, toVersion: MistiaSchemaV2.self)
        ]
    }
}
