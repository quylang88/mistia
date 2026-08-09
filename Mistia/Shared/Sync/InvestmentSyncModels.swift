import Foundation

nonisolated struct RemoteInvestmentChannel: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .investmentChannel
    var userID: UUID
    var id: UUID
    var name: String
    var iconSymbolName: String
    var iconColorHex: String
    var sortOrder: Int
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", id, name
        case iconSymbolName = "icon_symbol_name"
        case iconColorHex = "icon_color_hex"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated struct RemoteInvestmentAsset: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .investmentAsset
    var userID: UUID
    var id: UUID
    var channelID: UUID
    var name: String
    var currencyCode: String
    var sortOrder: Int
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", id
        case channelID = "channel_id"
        case name
        case currencyCode = "currency_code"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated struct RemoteInvestmentTrade: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .investmentTrade
    var userID: UUID
    var id: UUID
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
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", id
        case channelID = "channel_id", assetID = "asset_id"
        case kindRawValue = "kind_raw_value"
        case quantityDecimalString = "quantity_decimal_string"
        case grossAmountMinor = "gross_amount_minor"
        case currencyCode = "currency_code"
        case accountingGrossAmountMinor = "accounting_gross_amount_minor"
        case accountingCurrencyCode = "accounting_currency_code"
        case exchangeRateDecimalString = "exchange_rate_decimal_string"
        case exchangeRateProvider = "exchange_rate_provider", exchangeRateDate = "exchange_rate_date"
        case fundingWalletID = "funding_wallet_id", capitalReturnWalletID = "capital_return_wallet_id"
        case fundingWalletCurrencyCode = "funding_wallet_currency_code"
        case capitalReturnWalletCurrencyCode = "capital_return_wallet_currency_code"
        case fundingWalletAmountMinor = "funding_wallet_amount_minor"
        case capitalReturnWalletAmountMinor = "capital_return_wallet_amount_minor"
        case fundingToAccountingRateDecimalString = "funding_to_accounting_rate_decimal_string"
        case accountingToCapitalReturnRateDecimalString = "accounting_to_capital_return_rate_decimal_string"
        case fundingLedgerTransactionID = "funding_ledger_transaction_id"
        case capitalReturnLedgerTransactionID = "capital_return_ledger_transaction_id"
        case profitLossLedgerTransactionID = "profit_loss_ledger_transaction_id"
        case releasedCostBasisMinor = "released_cost_basis_minor"
        case realizedProfitLossMinor = "realized_profit_loss_minor"
        case positionQuantityAfterDecimalString = "position_quantity_after_decimal_string"
        case positionCostBasisAfterMinor = "position_cost_basis_after_minor"
        case note, occurredAt = "occurred_at", createdAt = "created_at", updatedAt = "updated_at"
        case deletedAt = "deleted_at", syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated struct RemoteInvestmentValuation: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .investmentValuation
    var userID: UUID
    var id: UUID
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
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", id, channelID = "channel_id", assetID = "asset_id"
        case marketValueMinor = "market_value_minor", accountingMarketValueMinor = "accounting_market_value_minor"
        case currencyCode = "currency_code", accountingCurrencyCode = "accounting_currency_code"
        case exchangeRateDecimalString = "exchange_rate_decimal_string", valuedAt = "valued_at"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
        case syncVersion = "sync_version", lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated struct RemoteInvestmentWalletPosting: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .investmentPosting
    var userID: UUID
    var id: UUID
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
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", id, eventID = "event_id", tradeID = "trade_id", assetID = "asset_id"
        case walletID = "wallet_id", ledgerTransactionID = "ledger_transaction_id"
        case roleRawValue = "role_raw_value", amountMinor = "amount_minor", currencyCode = "currency_code"
        case accountingAmountMinor = "accounting_amount_minor", accountingCurrencyCode = "accounting_currency_code"
        case occurredAt = "occurred_at", createdAt = "created_at", updatedAt = "updated_at"
        case deletedAt = "deleted_at", syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated extension RemoteInvestmentChannel {
    init(local: InvestmentChannel) {
        self.init(
            userID: local.ownerUserID, id: local.id, name: local.name,
            iconSymbolName: local.iconSymbolName, iconColorHex: local.iconColorHex,
            sortOrder: local.sortOrder, isArchived: local.isArchived, archivedAt: local.archivedAt,
            createdAt: local.createdAt, updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            syncVersion: local.remoteVersion, lastModifiedByDeviceID: nil
        )
    }
}

nonisolated extension RemoteInvestmentAsset {
    init(local: InvestmentAsset) {
        self.init(
            userID: local.ownerUserID, id: local.id, channelID: local.channelID,
            name: local.name, currencyCode: local.currencyCode, sortOrder: local.sortOrder,
            isArchived: local.isArchived, archivedAt: local.archivedAt,
            createdAt: local.createdAt, updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            syncVersion: local.remoteVersion, lastModifiedByDeviceID: nil
        )
    }
}

nonisolated extension RemoteInvestmentTrade {
    init(local: InvestmentTrade) {
        self.init(
            userID: local.ownerUserID, id: local.id, channelID: local.channelID, assetID: local.assetID,
            kindRawValue: local.kindRawValue, quantityDecimalString: local.quantityDecimalString,
            grossAmountMinor: local.grossAmountMinor, currencyCode: local.currencyCode,
            accountingGrossAmountMinor: local.accountingGrossAmountMinor,
            accountingCurrencyCode: local.accountingCurrencyCode,
            exchangeRateDecimalString: local.exchangeRateDecimalString,
            exchangeRateProvider: local.exchangeRateProvider, exchangeRateDate: local.exchangeRateDate,
            fundingWalletID: local.fundingWalletID, capitalReturnWalletID: local.capitalReturnWalletID,
            fundingWalletCurrencyCode: local.fundingWalletCurrencyCode,
            capitalReturnWalletCurrencyCode: local.capitalReturnWalletCurrencyCode,
            fundingWalletAmountMinor: local.fundingWalletAmountMinor,
            capitalReturnWalletAmountMinor: local.capitalReturnWalletAmountMinor,
            fundingToAccountingRateDecimalString: local.fundingToAccountingRateDecimalString,
            accountingToCapitalReturnRateDecimalString: local.accountingToCapitalReturnRateDecimalString,
            fundingLedgerTransactionID: local.fundingLedgerTransactionID,
            capitalReturnLedgerTransactionID: local.capitalReturnLedgerTransactionID,
            profitLossLedgerTransactionID: local.profitLossLedgerTransactionID,
            releasedCostBasisMinor: local.releasedCostBasisMinor,
            realizedProfitLossMinor: local.realizedProfitLossMinor,
            positionQuantityAfterDecimalString: local.positionQuantityAfterDecimalString,
            positionCostBasisAfterMinor: local.positionCostBasisAfterMinor,
            note: local.note, occurredAt: local.occurredAt, createdAt: local.createdAt,
            updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            syncVersion: local.remoteVersion, lastModifiedByDeviceID: nil
        )
    }
}

nonisolated extension RemoteInvestmentValuation {
    init(local: InvestmentValuation) {
        self.init(
            userID: local.ownerUserID, id: local.id, channelID: local.channelID, assetID: local.assetID,
            marketValueMinor: local.marketValueMinor, accountingMarketValueMinor: local.accountingMarketValueMinor,
            currencyCode: local.currencyCode, accountingCurrencyCode: local.accountingCurrencyCode,
            exchangeRateDecimalString: local.exchangeRateDecimalString, valuedAt: local.valuedAt,
            createdAt: local.createdAt, updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            syncVersion: local.remoteVersion, lastModifiedByDeviceID: nil
        )
    }
}

nonisolated extension RemoteInvestmentWalletPosting {
    init(local: InvestmentWalletPosting) {
        self.init(
            userID: local.ownerUserID, id: local.id, eventID: local.eventID,
            tradeID: local.tradeID, assetID: local.assetID, walletID: local.walletID,
            ledgerTransactionID: local.ledgerTransactionID, roleRawValue: local.roleRawValue,
            amountMinor: local.amountMinor, currencyCode: local.currencyCode,
            accountingAmountMinor: local.accountingAmountMinor,
            accountingCurrencyCode: local.accountingCurrencyCode, occurredAt: local.occurredAt,
            createdAt: local.createdAt, updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            syncVersion: local.remoteVersion, lastModifiedByDeviceID: nil
        )
    }
}
