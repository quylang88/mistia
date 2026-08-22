import Foundation
import SwiftData

/// Frozen copy of the Investment trade model used by SwiftData schemas V8 and V9.
/// Keep this model unchanged so existing store checksums remain stable.
enum MistiaSchemaV9InvestmentTradeModels {
    @Model
    nonisolated final class InvestmentTrade: Identifiable, Hashable {
        static func == (lhs: InvestmentTrade, rhs: InvestmentTrade) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        @Attribute(.unique) var id: UUID
        var ownerUserID: UUID
        var channelID: UUID
        var assetID: UUID
        var kindRawValue: String
        var quantityDecimalString: String
        var grossAmountMinor: Int64
        var currencyCode: String
        var accountingGrossAmountMinor: Int64
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
            kind: InvestmentTradeKind,
            quantity: Decimal,
            grossAmountMinor: Int64,
            currencyCode: String,
            accountingGrossAmountMinor: Int64,
            accountingCurrencyCode: String,
            exchangeRateDecimalString: String? = nil,
            exchangeRateProvider: String? = nil,
            exchangeRateDate: String? = nil,
            fundingWalletID: UUID? = nil,
            capitalReturnWalletID: UUID? = nil,
            fundingWalletCurrencyCode: String? = nil,
            capitalReturnWalletCurrencyCode: String? = nil,
            fundingWalletAmountMinor: Int64? = nil,
            capitalReturnWalletAmountMinor: Int64? = nil,
            fundingToAccountingRateDecimalString: String? = nil,
            accountingToCapitalReturnRateDecimalString: String? = nil,
            fundingLedgerTransactionID: UUID? = nil,
            capitalReturnLedgerTransactionID: UUID? = nil,
            profitLossLedgerTransactionID: UUID? = nil,
            releasedCostBasisMinor: Int64 = 0,
            realizedProfitLossMinor: Int64 = 0,
            positionQuantityAfter: Decimal = 0,
            positionCostBasisAfterMinor: Int64 = 0,
            note: String? = nil,
            occurredAt: Date = .now,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil,
            remoteVersion: Int64 = 0
        ) {
            self.id = id
            self.ownerUserID = ownerUserID
            self.channelID = channelID
            self.assetID = assetID
            self.kindRawValue = kind.rawValue
            self.quantityDecimalString = InvestmentDecimalCoding.string(from: quantity)
            self.grossAmountMinor = max(grossAmountMinor, 0)
            self.currencyCode = currencyCode
            self.accountingGrossAmountMinor = max(accountingGrossAmountMinor, 0)
            self.accountingCurrencyCode = accountingCurrencyCode
            self.exchangeRateDecimalString = exchangeRateDecimalString
            self.exchangeRateProvider = exchangeRateProvider
            self.exchangeRateDate = exchangeRateDate
            self.fundingWalletID = fundingWalletID
            self.capitalReturnWalletID = capitalReturnWalletID
            self.fundingWalletCurrencyCode = fundingWalletCurrencyCode
            self.capitalReturnWalletCurrencyCode = capitalReturnWalletCurrencyCode
            self.fundingWalletAmountMinor = fundingWalletAmountMinor
            self.capitalReturnWalletAmountMinor = capitalReturnWalletAmountMinor
            self.fundingToAccountingRateDecimalString = fundingToAccountingRateDecimalString
            self.accountingToCapitalReturnRateDecimalString = accountingToCapitalReturnRateDecimalString
            self.fundingLedgerTransactionID = fundingLedgerTransactionID
            self.capitalReturnLedgerTransactionID = capitalReturnLedgerTransactionID
            self.profitLossLedgerTransactionID = profitLossLedgerTransactionID
            self.releasedCostBasisMinor = releasedCostBasisMinor
            self.realizedProfitLossMinor = realizedProfitLossMinor
            self.positionQuantityAfterDecimalString = InvestmentDecimalCoding.string(from: positionQuantityAfter)
            self.positionCostBasisAfterMinor = max(positionCostBasisAfterMinor, 0)
            self.note = note
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.remoteVersion = remoteVersion
        }
    }
}
