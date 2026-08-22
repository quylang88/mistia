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
    var imagePath: String?
    var defaultUnitLabel: String?
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
        case imagePath = "image_path"
        case defaultUnitLabel = "default_unit_label"
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
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", id
        case channelID = "channel_id", assetID = "asset_id"
        case kindRawValue = "kind_raw_value"
        case quantityDecimalString = "quantity_decimal_string"
        case unitLabel = "unit_label"
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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconSymbolName = try container.decode(String.self, forKey: .iconSymbolName)
        iconColorHex = try container.decode(String.self, forKey: .iconColorHex)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconSymbolName, forKey: .iconSymbolName)
        try container.encode(iconColorHex, forKey: .iconColorHex)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(archivedAt, forKey: .archivedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(syncVersion, forKey: .syncVersion)
        try container.encode(lastModifiedByDeviceID, forKey: .lastModifiedByDeviceID)
    }

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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        channelID = try container.decode(UUID.self, forKey: .channelID)
        name = try container.decode(String.self, forKey: .name)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        defaultUnitLabel = try container.decodeIfPresent(String.self, forKey: .defaultUnitLabel)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(channelID, forKey: .channelID)
        try container.encode(name, forKey: .name)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(defaultUnitLabel, forKey: .defaultUnitLabel)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(archivedAt, forKey: .archivedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(syncVersion, forKey: .syncVersion)
        try container.encode(lastModifiedByDeviceID, forKey: .lastModifiedByDeviceID)
    }

    init(local: InvestmentAsset) {
        self.init(
            userID: local.ownerUserID, id: local.id, channelID: local.channelID,
            name: local.name, currencyCode: local.currencyCode, imagePath: local.imagePath,
            defaultUnitLabel: local.defaultUnitLabel,
            sortOrder: local.sortOrder,
            isArchived: local.isArchived, archivedAt: local.archivedAt,
            createdAt: local.createdAt, updatedAt: local.updatedAt, deletedAt: local.deletedAt,
            syncVersion: local.remoteVersion, lastModifiedByDeviceID: nil
        )
    }
}

nonisolated extension RemoteInvestmentTrade {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        channelID = try container.decode(UUID.self, forKey: .channelID)
        assetID = try container.decode(UUID.self, forKey: .assetID)
        kindRawValue = try container.decode(String.self, forKey: .kindRawValue)
        quantityDecimalString = try container.decode(String.self, forKey: .quantityDecimalString)
        unitLabel = try container.decodeIfPresent(String.self, forKey: .unitLabel)
        grossAmountMinor = try container.decode(Int64.self, forKey: .grossAmountMinor)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        accountingGrossAmountMinor = try container.decode(Int64.self, forKey: .accountingGrossAmountMinor)
        accountingCurrencyCode = try container.decode(String.self, forKey: .accountingCurrencyCode)
        exchangeRateDecimalString = try container.decodeIfPresent(String.self, forKey: .exchangeRateDecimalString)
        exchangeRateProvider = try container.decodeIfPresent(String.self, forKey: .exchangeRateProvider)
        exchangeRateDate = try container.decodeIfPresent(String.self, forKey: .exchangeRateDate)
        fundingWalletID = try container.decodeIfPresent(UUID.self, forKey: .fundingWalletID)
        capitalReturnWalletID = try container.decodeIfPresent(UUID.self, forKey: .capitalReturnWalletID)
        fundingWalletCurrencyCode = try container.decodeIfPresent(String.self, forKey: .fundingWalletCurrencyCode)
        capitalReturnWalletCurrencyCode = try container.decodeIfPresent(String.self, forKey: .capitalReturnWalletCurrencyCode)
        fundingWalletAmountMinor = try container.decodeIfPresent(Int64.self, forKey: .fundingWalletAmountMinor)
        capitalReturnWalletAmountMinor = try container.decodeIfPresent(Int64.self, forKey: .capitalReturnWalletAmountMinor)
        fundingToAccountingRateDecimalString = try container.decodeIfPresent(String.self, forKey: .fundingToAccountingRateDecimalString)
        accountingToCapitalReturnRateDecimalString = try container.decodeIfPresent(String.self, forKey: .accountingToCapitalReturnRateDecimalString)
        fundingLedgerTransactionID = try container.decodeIfPresent(UUID.self, forKey: .fundingLedgerTransactionID)
        capitalReturnLedgerTransactionID = try container.decodeIfPresent(UUID.self, forKey: .capitalReturnLedgerTransactionID)
        profitLossLedgerTransactionID = try container.decodeIfPresent(UUID.self, forKey: .profitLossLedgerTransactionID)
        releasedCostBasisMinor = try container.decode(Int64.self, forKey: .releasedCostBasisMinor)
        realizedProfitLossMinor = try container.decode(Int64.self, forKey: .realizedProfitLossMinor)
        positionQuantityAfterDecimalString = try container.decode(String.self, forKey: .positionQuantityAfterDecimalString)
        positionCostBasisAfterMinor = try container.decode(Int64.self, forKey: .positionCostBasisAfterMinor)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(channelID, forKey: .channelID)
        try container.encode(assetID, forKey: .assetID)
        try container.encode(kindRawValue, forKey: .kindRawValue)
        try container.encode(quantityDecimalString, forKey: .quantityDecimalString)
        try container.encode(unitLabel, forKey: .unitLabel)
        try container.encode(grossAmountMinor, forKey: .grossAmountMinor)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(accountingGrossAmountMinor, forKey: .accountingGrossAmountMinor)
        try container.encode(accountingCurrencyCode, forKey: .accountingCurrencyCode)
        try container.encode(exchangeRateDecimalString, forKey: .exchangeRateDecimalString)
        try container.encode(exchangeRateProvider, forKey: .exchangeRateProvider)
        try container.encode(exchangeRateDate, forKey: .exchangeRateDate)
        try container.encode(fundingWalletID, forKey: .fundingWalletID)
        try container.encode(capitalReturnWalletID, forKey: .capitalReturnWalletID)
        try container.encode(fundingWalletCurrencyCode, forKey: .fundingWalletCurrencyCode)
        try container.encode(capitalReturnWalletCurrencyCode, forKey: .capitalReturnWalletCurrencyCode)
        try container.encode(fundingWalletAmountMinor, forKey: .fundingWalletAmountMinor)
        try container.encode(capitalReturnWalletAmountMinor, forKey: .capitalReturnWalletAmountMinor)
        try container.encode(fundingToAccountingRateDecimalString, forKey: .fundingToAccountingRateDecimalString)
        try container.encode(accountingToCapitalReturnRateDecimalString, forKey: .accountingToCapitalReturnRateDecimalString)
        try container.encode(fundingLedgerTransactionID, forKey: .fundingLedgerTransactionID)
        try container.encode(capitalReturnLedgerTransactionID, forKey: .capitalReturnLedgerTransactionID)
        try container.encode(profitLossLedgerTransactionID, forKey: .profitLossLedgerTransactionID)
        try container.encode(releasedCostBasisMinor, forKey: .releasedCostBasisMinor)
        try container.encode(realizedProfitLossMinor, forKey: .realizedProfitLossMinor)
        try container.encode(positionQuantityAfterDecimalString, forKey: .positionQuantityAfterDecimalString)
        try container.encode(positionCostBasisAfterMinor, forKey: .positionCostBasisAfterMinor)
        try container.encode(note, forKey: .note)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(syncVersion, forKey: .syncVersion)
        try container.encode(lastModifiedByDeviceID, forKey: .lastModifiedByDeviceID)
    }

    init(local: InvestmentTrade) {
        self.init(
            userID: local.ownerUserID, id: local.id, channelID: local.channelID, assetID: local.assetID,
            kindRawValue: local.kindRawValue, quantityDecimalString: local.quantityDecimalString,
            unitLabel: local.unitLabel,
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

nonisolated extension RemoteInvestmentWalletPosting {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        eventID = try container.decode(UUID.self, forKey: .eventID)
        tradeID = try container.decodeIfPresent(UUID.self, forKey: .tradeID)
        assetID = try container.decodeIfPresent(UUID.self, forKey: .assetID)
        walletID = try container.decode(UUID.self, forKey: .walletID)
        ledgerTransactionID = try container.decode(UUID.self, forKey: .ledgerTransactionID)
        roleRawValue = try container.decode(String.self, forKey: .roleRawValue)
        amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        accountingAmountMinor = try container.decode(Int64.self, forKey: .accountingAmountMinor)
        accountingCurrencyCode = try container.decode(String.self, forKey: .accountingCurrencyCode)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(tradeID, forKey: .tradeID)
        try container.encode(assetID, forKey: .assetID)
        try container.encode(walletID, forKey: .walletID)
        try container.encode(ledgerTransactionID, forKey: .ledgerTransactionID)
        try container.encode(roleRawValue, forKey: .roleRawValue)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(accountingAmountMinor, forKey: .accountingAmountMinor)
        try container.encode(accountingCurrencyCode, forKey: .accountingCurrencyCode)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(syncVersion, forKey: .syncVersion)
        try container.encode(lastModifiedByDeviceID, forKey: .lastModifiedByDeviceID)
    }

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
