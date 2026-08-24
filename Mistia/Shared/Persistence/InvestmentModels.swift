import Foundation
import SwiftData

nonisolated enum TransactionFinancialDomain: String, Codable, CaseIterable {
    case ordinary
    case investment
}

nonisolated enum LedgerWalletSystemPurpose: String, Codable, CaseIterable {
    case investmentProfit
}

nonisolated enum InvestmentTradeKind: String, Codable, CaseIterable, Identifiable {
    case buy
    case sell

    var id: String { rawValue }
}

nonisolated enum InvestmentPostingRole: String, Codable, CaseIterable {
    case funding
    case capitalReturn
    case realizedProfit
    case transferOut
    case transferIn
    case cashAccrual
    case cashReconciliation
    case cashConsumption
    case cashTransfer
    case cashCorrection
}

nonisolated enum InvestmentCashBucket: String, Codable, CaseIterable {
    case booked
    case unreconciled
}

nonisolated enum InvestmentCashPostingOrigin: String, Codable, CaseIterable {
    case derived
    case inferred
    case manual
}

nonisolated enum InvestmentLedgerLegRole: String, Codable, CaseIterable {
    case investmentFunding
    case investmentCapitalReturn
    case investmentRealizedProfit
    case investmentTransfer
    case investmentReconciliation
    case investmentReserveUse

    static func isInvestmentRawValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.hasPrefix("investment")
    }

    static func isServerDerivedRawValue(_ value: String?) -> Bool {
        guard let value,
              let role = InvestmentLedgerLegRole(rawValue: value) else {
            return false
        }
        switch role {
        case .investmentFunding, .investmentCapitalReturn, .investmentRealizedProfit:
            return true
        case .investmentTransfer, .investmentReconciliation, .investmentReserveUse:
            return false
        }
    }
}

nonisolated extension LedgerTransaction {
    var financialDomain: TransactionFinancialDomain {
        InvestmentLedgerLegRole.isInvestmentRawValue(settlementRoleRawValue)
            ? .investment
            : .ordinary
    }
}

@Model
nonisolated final class InvestmentChannel: Identifiable, Hashable {
    static func == (lhs: InvestmentChannel, rhs: InvestmentChannel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var name: String
    var iconSymbolName: String
    var iconColorHex: String
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
        name: String,
        iconSymbolName: String = "chart.line.uptrend.xyaxis",
        iconColorHex: String = "#9A67FF",
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
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.iconColorHex = iconColorHex
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }
}

enum MistiaSchemaV9InvestmentModels {
@Model
nonisolated final class InvestmentAsset: Identifiable, Hashable {
    static func == (lhs: InvestmentAsset, rhs: InvestmentAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var channelID: UUID
    var name: String
    var currencyCode: String
    var imagePath: String?
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
        currencyCode: String,
        imagePath: String? = nil,
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
        self.currencyCode = currencyCode
        self.imagePath = imagePath
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

}

}

enum MistiaSchemaV10InvestmentModels {
@Model
nonisolated final class InvestmentAsset: Identifiable, Hashable {
    static func == (lhs: InvestmentAsset, rhs: InvestmentAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var channelID: UUID
    var name: String
    var currencyCode: String
    var imagePath: String?
    var defaultUnitLabel: String?
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
        currencyCode: String,
        imagePath: String? = nil,
        defaultUnitLabel: String? = nil,
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
        self.currencyCode = currencyCode
        self.imagePath = imagePath
        self.defaultUnitLabel = defaultUnitLabel
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

}
}

typealias InvestmentAsset = MistiaSchemaV10InvestmentModels.InvestmentAsset

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
    var unitLabel: String?
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
        unitLabel: String? = nil,
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
        self.unitLabel = unitLabel
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

    var kind: InvestmentTradeKind {
        get { InvestmentTradeKind(rawValue: kindRawValue) ?? .buy }
        set { kindRawValue = newValue.rawValue }
    }

    var quantity: Decimal {
        get { InvestmentDecimalCoding.decimal(from: quantityDecimalString) ?? 0 }
        set { quantityDecimalString = InvestmentDecimalCoding.string(from: newValue) }
    }

    var positionQuantityAfter: Decimal {
        get { InvestmentDecimalCoding.decimal(from: positionQuantityAfterDecimalString) ?? 0 }
        set { positionQuantityAfterDecimalString = InvestmentDecimalCoding.string(from: newValue) }
    }

    var calculation: InvestmentTradeCalculation {
        InvestmentTradeCalculation(
            id: id,
            releasedCostBasisMinor: releasedCostBasisMinor,
            realizedProfitLossMinor: realizedProfitLossMinor,
            positionQuantityAfter: positionQuantityAfter,
            positionCostBasisAfterMinor: positionCostBasisAfterMinor,
            openLotCountAfter: 0
        )
    }
}

// Kept only so V7/V8 stores can migrate into V9. It is not part of the current schema.
@Model
nonisolated final class InvestmentValuation: Identifiable, Hashable {
    static func == (lhs: InvestmentValuation, rhs: InvestmentValuation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var channelID: UUID
    var assetID: UUID
    var marketValueMinor: Int64
    var accountingMarketValueMinor: Int64
    var currencyCode: String
    var accountingCurrencyCode: String
    var exchangeRateDecimalString: String?
    var valuedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        channelID: UUID,
        assetID: UUID,
        marketValueMinor: Int64,
        accountingMarketValueMinor: Int64,
        currencyCode: String,
        accountingCurrencyCode: String,
        exchangeRateDecimalString: String? = nil,
        valuedAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.channelID = channelID
        self.assetID = assetID
        self.marketValueMinor = max(marketValueMinor, 0)
        self.accountingMarketValueMinor = max(accountingMarketValueMinor, 0)
        self.currencyCode = currencyCode
        self.accountingCurrencyCode = accountingCurrencyCode
        self.exchangeRateDecimalString = exchangeRateDecimalString
        self.valuedAt = valuedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }
}

enum MistiaSchemaV10InvestmentPostingModels {
@Model
nonisolated final class InvestmentWalletPosting: Identifiable, Hashable {
    static func == (lhs: InvestmentWalletPosting, rhs: InvestmentWalletPosting) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var eventID: UUID
    var tradeID: UUID?
    var assetID: UUID?
    var walletID: UUID
    var ledgerTransactionID: UUID
    var roleRawValue: String
    var amountMinor: Int64
    var currencyCode: String
    var accountingAmountMinor: Int64
    var accountingCurrencyCode: String
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        eventID: UUID,
        tradeID: UUID? = nil,
        assetID: UUID? = nil,
        walletID: UUID,
        ledgerTransactionID: UUID,
        role: InvestmentPostingRole,
        amountMinor: Int64,
        currencyCode: String,
        accountingAmountMinor: Int64,
        accountingCurrencyCode: String,
        occurredAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.eventID = eventID
        self.tradeID = tradeID
        self.assetID = assetID
        self.walletID = walletID
        self.ledgerTransactionID = ledgerTransactionID
        self.roleRawValue = role.rawValue
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.accountingAmountMinor = accountingAmountMinor
        self.accountingCurrencyCode = accountingCurrencyCode
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

    var role: InvestmentPostingRole {
        get { InvestmentPostingRole(rawValue: roleRawValue) ?? .funding }
        set { roleRawValue = newValue.rawValue }
    }
}
}

typealias InvestmentWalletPosting = MistiaSchemaV10InvestmentPostingModels.InvestmentWalletPosting

@Model
nonisolated final class InvestmentCashPostingMetadata: Identifiable, Hashable {
    static func == (lhs: InvestmentCashPostingMetadata, rhs: InvestmentCashPostingMetadata) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Matches the corresponding `InvestmentWalletPosting.id`.
    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var cashBucketRawValue: String
    var cashOriginRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        ownerUserID: UUID,
        cashBucket: InvestmentCashBucket,
        cashOrigin: InvestmentCashPostingOrigin,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.cashBucketRawValue = cashBucket.rawValue
        self.cashOriginRawValue = cashOrigin.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var cashBucket: InvestmentCashBucket {
        get { InvestmentCashBucket(rawValue: cashBucketRawValue) ?? .booked }
        set { cashBucketRawValue = newValue.rawValue }
    }

    var cashOrigin: InvestmentCashPostingOrigin {
        get { InvestmentCashPostingOrigin(rawValue: cashOriginRawValue) ?? .derived }
        set { cashOriginRawValue = newValue.rawValue }
    }
}

@Model
nonisolated final class InvestmentWalletConfiguration: Identifiable, Hashable {
    static func == (lhs: InvestmentWalletConfiguration, rhs: InvestmentWalletConfiguration) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    var systemWalletID: UUID
    var linkedWalletID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        ownerUserID: UUID,
        systemWalletID: UUID,
        linkedWalletID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.systemWalletID = systemWalletID
        self.linkedWalletID = linkedWalletID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct InvestmentWalletCashLocation: Identifiable, Equatable, Sendable {
    let walletID: UUID
    let currencyCode: String
    let bookedMinor: Int64
    let unreconciledMinor: Int64
    let originalBookedMinor: Int64
    let originalUnreconciledMinor: Int64

    var id: UUID { walletID }
    var totalMinor: Int64 { bookedMinor + unreconciledMinor }
    var originalTotalMinor: Int64 { originalBookedMinor + originalUnreconciledMinor }
}

nonisolated struct InvestmentCashAllocationSnapshot: Equatable, Sendable {
    let accountingCurrencyCode: String
    let locations: [InvestmentWalletCashLocation]
    let unidentifiedMinor: Int64

    var bookedMinor: Int64 { locations.reduce(0) { $0 + $1.bookedMinor } }
    var unreconciledMinor: Int64 { locations.reduce(0) { $0 + $1.unreconciledMinor } }
    var totalMinor: Int64 { bookedMinor + unreconciledMinor + unidentifiedMinor }
}

nonisolated enum InvestmentFundUsageOutcome: Equatable, Sendable {
    case ordinaryFundsOnly
    case requiresConfirmation
    case insufficientFunds
}

nonisolated struct InvestmentFundUsagePreview: Equatable, Sendable {
    let requestedMinor: Int64
    let ordinaryAvailableMinor: Int64
    let bookedToUseMinor: Int64
    let unreconciledToUseMinor: Int64
    let remainingInvestmentMinor: Int64
    let outcome: InvestmentFundUsageOutcome

    var investmentToUseMinor: Int64 { bookedToUseMinor + unreconciledToUseMinor }
}

nonisolated struct InvestmentReconciliationRequest: Equatable, Sendable {
    let walletID: UUID
    let accountingAmountMinor: Int64
}

nonisolated struct InvestmentReconciliationInstruction: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceWalletID: UUID
    let destinationWalletID: UUID
    let accountingAmountMinor: Int64
}

nonisolated struct InvestmentReconciliationResult: Equatable, Sendable {
    let instructions: [InvestmentReconciliationInstruction]
    let persistence: InvestmentPersistenceResult
}

nonisolated enum InvestmentDecimalCoding {
    static func decimal(from value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func string(from value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 8, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
