import Foundation
import SwiftData

enum MistiaSchemaV5Models {
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
        var sourceCurrencyCode: String?
        var destinationCurrencyCode: String?
        var destinationAmountMinor: Int64?
        var reportingCurrencyCode: String?
        var reportingAmountMinor: Int64?
        var conversionModeRawValue: String?
        var exchangeRateDecimalString: String?
        var exchangeRateProvider: String?
        var exchangeRateDate: String?
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
            primaryKindRawValue: String = TransactionPrimaryKind.expense.rawValue,
            transferSubtypeRawValue: String? = nil,
            debtIntentRawValue: String? = nil,
            entryStatusRawValue: String = TransactionEntryStatus.posted.rawValue,
            title: String = "",
            note: String? = nil,
            amountMinor: Int64 = 0,
            sourceCurrencyCode: String? = nil,
            destinationCurrencyCode: String? = nil,
            destinationAmountMinor: Int64? = nil,
            reportingCurrencyCode: String? = nil,
            reportingAmountMinor: Int64? = nil,
            conversionModeRawValue: String? = nil,
            exchangeRateDecimalString: String? = nil,
            exchangeRateProvider: String? = nil,
            exchangeRateDate: String? = nil,
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
            self.sourceCurrencyCode = sourceCurrencyCode
            self.destinationCurrencyCode = destinationCurrencyCode
            self.destinationAmountMinor = destinationAmountMinor
            self.reportingCurrencyCode = reportingCurrencyCode
            self.reportingAmountMinor = reportingAmountMinor
            self.conversionModeRawValue = conversionModeRawValue
            self.exchangeRateDecimalString = exchangeRateDecimalString
            self.exchangeRateProvider = exchangeRateProvider
            self.exchangeRateDate = exchangeRateDate
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
}
