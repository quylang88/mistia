import Foundation
import SwiftData

/// Frozen copies of the investment entities shipped in schema V7.
/// Keep these fields intact so SwiftData can migrate existing stores to V8.
enum MistiaSchemaV7InvestmentModels {
    @Model
    final class InvestmentAsset {
        @Attribute(.unique) var id: UUID
        var ownerUserID: UUID
        var channelID: UUID
        var name: String
        var symbol: String?
        var currencyCode: String
        var openingQuantityDecimalString: String
        var openingCostMinor: Int64
        var sortOrder: Int
        var isArchived: Bool
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            ownerUserID: UUID,
            channelID: UUID,
            name: String,
            symbol: String? = nil,
            currencyCode: String,
            openingQuantityDecimalString: String = "0",
            openingCostMinor: Int64 = 0,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.ownerUserID = ownerUserID
            self.channelID = channelID
            self.name = name
            self.symbol = symbol
            self.currencyCode = currencyCode
            self.openingQuantityDecimalString = openingQuantityDecimalString
            self.openingCostMinor = openingCostMinor
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
    final class InvestmentTrade {
        @Attribute(.unique) var id: UUID
        var ownerUserID: UUID
        var channelID: UUID
        var assetID: UUID
        var kindRawValue: String
        var quantityDecimalString: String
        var grossAmountMinor: Int64
        var feeMinor: Int64
        var currencyCode: String
        var accountingGrossAmountMinor: Int64
        var accountingFeeMinor: Int64
        var accountingCurrencyCode: String
        var exchangeRateDecimalString: String?
        var exchangeRateProvider: String?
        var exchangeRateDate: String?
        var fundingWalletID: UUID?
        var capitalReturnWalletID: UUID?
        var fundingWalletCurrencyCode: String?
        var capitalReturnWalletCurrencyCode: String?
        var fundingWalletAmountMinor: Int64?
        var capitalReturnWalletAmountMinor: Int64?
        var fundingToAccountingRateDecimalString: String?
        var accountingToCapitalReturnRateDecimalString: String?
        var fundingLedgerTransactionID: UUID?
        var capitalReturnLedgerTransactionID: UUID?
        var profitLossLedgerTransactionID: UUID?
        var releasedCostBasisMinor: Int64
        var realizedProfitLossMinor: Int64
        var positionQuantityAfterDecimalString: String
        var positionCostBasisAfterMinor: Int64
        var note: String?
        var occurredAt: Date
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var remoteVersion: Int64

        init(
            id: UUID = UUID(),
            ownerUserID: UUID,
            channelID: UUID,
            assetID: UUID,
            kindRawValue: String,
            quantityDecimalString: String,
            grossAmountMinor: Int64,
            feeMinor: Int64 = 0,
            currencyCode: String,
            accountingGrossAmountMinor: Int64,
            accountingFeeMinor: Int64 = 0,
            accountingCurrencyCode: String,
            fundingWalletID: UUID? = nil,
            capitalReturnWalletID: UUID? = nil,
            occurredAt: Date = .now,
            createdAt: Date = .now
        ) {
            self.id = id
            self.ownerUserID = ownerUserID
            self.channelID = channelID
            self.assetID = assetID
            self.kindRawValue = kindRawValue
            self.quantityDecimalString = quantityDecimalString
            self.grossAmountMinor = grossAmountMinor
            self.feeMinor = feeMinor
            self.currencyCode = currencyCode
            self.accountingGrossAmountMinor = accountingGrossAmountMinor
            self.accountingFeeMinor = accountingFeeMinor
            self.accountingCurrencyCode = accountingCurrencyCode
            self.exchangeRateDecimalString = nil
            self.exchangeRateProvider = nil
            self.exchangeRateDate = nil
            self.fundingWalletID = fundingWalletID
            self.capitalReturnWalletID = capitalReturnWalletID
            self.fundingWalletCurrencyCode = nil
            self.capitalReturnWalletCurrencyCode = nil
            self.fundingWalletAmountMinor = nil
            self.capitalReturnWalletAmountMinor = nil
            self.fundingToAccountingRateDecimalString = nil
            self.accountingToCapitalReturnRateDecimalString = nil
            self.fundingLedgerTransactionID = nil
            self.capitalReturnLedgerTransactionID = nil
            self.profitLossLedgerTransactionID = nil
            self.releasedCostBasisMinor = 0
            self.realizedProfitLossMinor = 0
            self.positionQuantityAfterDecimalString = "0"
            self.positionCostBasisAfterMinor = 0
            self.note = nil
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.deletedAt = nil
            self.remoteVersion = 0
        }
    }
}
