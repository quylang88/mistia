import Foundation
import SwiftData

nonisolated struct InvestmentTradeDraft: Equatable {
    let id: UUID
    var channelID: UUID
    var assetID: UUID
    var kind: InvestmentTradeKind
    var quantity: Decimal
    var grossAmountMinor: Int64
    var currencyCode: String
    var accountingGrossAmountMinor: Int64
    var accountingCurrencyCode: String
    var exchangeRateDecimalString: String?
    var exchangeRateProvider: String?
    var exchangeRateDate: String?
    var fundingWalletID: UUID?
    var capitalReturnWalletID: UUID?
    var note: String?
    var occurredAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
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
        note: String? = nil,
        occurredAt: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.channelID = channelID
        self.assetID = assetID
        self.kind = kind
        self.quantity = quantity
        self.grossAmountMinor = grossAmountMinor
        self.currencyCode = currencyCode
        self.accountingGrossAmountMinor = accountingGrossAmountMinor
        self.accountingCurrencyCode = accountingCurrencyCode
        self.exchangeRateDecimalString = exchangeRateDecimalString
        self.exchangeRateProvider = exchangeRateProvider
        self.exchangeRateDate = exchangeRateDate
        self.fundingWalletID = fundingWalletID
        self.capitalReturnWalletID = capitalReturnWalletID
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}

nonisolated struct InvestmentPersistenceResult: Equatable {
    var walletIDs: Set<UUID> = []
    var tradeIDs: Set<UUID> = []
    var postingIDs: Set<UUID> = []
    var ledgerTransactionIDs: Set<UUID> = []
    var deletedTradeIDs: Set<UUID> = []
    var deletedPostingIDs: Set<UUID> = []
    var deletedLedgerTransactionIDs: Set<UUID> = []
}

nonisolated enum InvestmentPersistenceError: LocalizedError, Equatable {
    case missingAsset
    case missingWallet
    case invalidWallet
    case insufficientFunds
    case missingExchangeRate
    case invalidTradeInput
    case investmentWalletCannotReceiveTransfer
    case transferExceedsPositiveBalance

    var errorDescription: String? {
        switch self {
        case .missingAsset:
            return L10n.investment.error.missingAsset
        case .missingWallet:
            return L10n.investment.error.missingWallet
        case .invalidWallet:
            return L10n.investment.error.invalidWallet
        case .insufficientFunds:
            return L10n.investment.error.insufficientFunds
        case .missingExchangeRate:
            return L10n.investment.error.missingExchangeRate
        case .invalidTradeInput:
            return L10n.investment.error.invalidTradeInput
        case .investmentWalletCannotReceiveTransfer:
            return L10n.investment.error.cannotTransferIn
        case .transferExceedsPositiveBalance:
            return L10n.investment.error.transferExceedsBalance
        }
    }
}

enum InvestmentPersistenceService {
    static func rebuildDerivedAccountingAfterLegacyFieldRemoval(
        now: Date = .now,
        context: ModelContext
    ) throws {
        try scrubLegacyInvestmentFieldsFromSyncConflicts(context: context)

        let assets = try context.fetch(FetchDescriptor<InvestmentAsset>())
            .filter { $0.deletedAt == nil }
        let activeTrades = try context.fetch(FetchDescriptor<InvestmentTrade>())
            .filter { $0.deletedAt == nil }
        let tradesByAssetID = Dictionary(grouping: activeTrades, by: \InvestmentTrade.assetID)
        let wallets = try context.fetch(FetchDescriptor<LedgerWallet>())
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })

        for asset in assets {
            let trades = tradesByAssetID[asset.id] ?? []
            guard !trades.isEmpty else { continue }
            guard let systemWallet = walletsByID[
                InvestmentSystemWalletIdentity.walletID(ownerUserID: asset.ownerUserID)
            ] else {
                throw InvestmentPersistenceError.missingWallet
            }
            let calculations = try InvestmentAccountingEngine.calculationMap(
                trades: trades.map(InvestmentTradeInput.init)
            )
            var result = InvestmentPersistenceResult(walletIDs: [systemWallet.id])

            for trade in trades {
                guard let calculation = calculations[trade.id] else { continue }
                trade.releasedCostBasisMinor = calculation.releasedCostBasisMinor
                trade.realizedProfitLossMinor = calculation.realizedProfitLossMinor
                trade.positionQuantityAfter = calculation.positionQuantityAfter
                trade.positionCostBasisAfterMinor = calculation.positionCostBasisAfterMinor

                if trade.kind == .buy {
                    guard let walletID = trade.fundingWalletID,
                          let fundingWallet = walletsByID[walletID] else {
                        throw InvestmentPersistenceError.missingWallet
                    }
                    trade.fundingWalletAmountMinor = try accountingAmountToFundingWallet(
                        trade.accountingGrossAmountMinor,
                        accountingCurrencyCode: trade.accountingCurrencyCode,
                        fundingWalletCurrencyCode: fundingWallet.currencyCode,
                        fundingToAccountingRateDecimalString: trade.fundingToAccountingRateDecimalString
                    )
                }

                try reconcileLedgerLegs(
                    ownerUserID: asset.ownerUserID,
                    trade: trade,
                    assetName: asset.name,
                    systemWallet: systemWallet,
                    walletsByID: walletsByID,
                    now: now,
                    context: context,
                    result: &result
                )
            }
        }

        try context.save()
    }

    private static func scrubLegacyInvestmentFieldsFromSyncConflicts(
        context: ModelContext
    ) throws {
        let conflicts = try context.fetch(FetchDescriptor<SyncConflict>())
        for conflict in conflicts {
            let removedKeys: Set<String>
            switch conflict.entityRawValue {
            case MistiaSyncEntity.investmentAsset.rawValue:
                removedKeys = [
                    "symbol",
                    "opening_quantity_decimal_string",
                    "opening_cost_minor"
                ]
            case MistiaSyncEntity.investmentTrade.rawValue:
                removedKeys = ["fee_minor", "accounting_fee_minor"]
            default:
                continue
            }

            conflict.localPayloadJSON = scrubbedJSONPayload(
                conflict.localPayloadJSON,
                removing: removedKeys
            )
            conflict.remotePayloadJSON = scrubbedJSONPayload(
                conflict.remotePayloadJSON,
                removing: removedKeys
            )
        }
    }

    private static func scrubbedJSONPayload(
        _ payload: String,
        removing keys: Set<String>
    ) -> String {
        guard let data = payload.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return keys.contains(where: payload.contains) ? "{}" : payload
        }

        var didRemoveValue = false
        for key in keys {
            didRemoveValue = object.removeValue(forKey: key) != nil || didRemoveValue
        }
        guard didRemoveValue,
              let scrubbedData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ),
              let scrubbedPayload = String(data: scrubbedData, encoding: .utf8) else {
            return payload
        }
        return scrubbedPayload
    }

    static func ensureSystemWallet(
        ownerUserID: UUID,
        currencyCode: String,
        now: Date = .now,
        context: ModelContext
    ) throws -> LedgerWallet {
        let walletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        let descriptor = FetchDescriptor<LedgerWallet>(
            predicate: #Predicate<LedgerWallet> { wallet in
                wallet.id == walletID
            }
        )
        if let wallet = try context.fetch(descriptor).first {
            let needsCanonicalization = wallet.name != L10n.investment.wallet.name
                || wallet.kind != .investment
                || wallet.iconSymbolName != LedgerWalletKind.investment.defaultIconSymbolName
                || wallet.iconColorHex != LedgerWalletKind.investment.defaultColorHex
                || wallet.openingBalanceMinor != 0
                || wallet.institutionDisplayName != nil
                || wallet.institutionPresetKey != nil
                || wallet.sortOrder != InvestmentSystemWalletIdentity.canonicalSortOrder
                || wallet.isArchived
                || wallet.deletedAt != nil
            if needsCanonicalization {
                wallet.name = L10n.investment.wallet.name
                wallet.kind = .investment
                wallet.iconSymbolName = LedgerWalletKind.investment.defaultIconSymbolName
                wallet.iconColorHex = LedgerWalletKind.investment.defaultColorHex
                wallet.openingBalanceMinor = 0
                wallet.institutionDisplayName = nil
                wallet.institutionPresetKey = nil
                wallet.sortOrder = InvestmentSystemWalletIdentity.canonicalSortOrder
                wallet.isArchived = false
                wallet.archivedAt = nil
                wallet.deletedAt = nil
                wallet.updatedAt = now
                try context.save()
            }
            return wallet
        }

        let wallet = LedgerWallet(
            id: walletID,
            name: L10n.investment.wallet.name,
            kind: .investment,
            iconSymbolName: LedgerWalletKind.investment.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.investment.defaultColorHex,
            currencyCode: MistiaCurrencyLogic.normalizedCode(currencyCode),
            openingBalanceMinor: 0,
            sortOrder: InvestmentSystemWalletIdentity.canonicalSortOrder,
            createdAt: now,
            updatedAt: now
        )
        context.insert(wallet)
        try MistiaRecordOwnershipStore.upsert(
            entity: .wallet,
            recordID: wallet.id,
            ownerUserID: ownerUserID,
            updatedAt: now,
            context: context
        )
        return wallet
    }

    static func createChannel(
        ownerUserID: UUID,
        name: String,
        iconSymbolName: String,
        iconColorHex: String,
        primaryCurrencyCode: String,
        now: Date = .now,
        context: ModelContext
    ) throws -> (channel: InvestmentChannel, wallet: LedgerWallet) {
        let wallet = try ensureSystemWallet(
            ownerUserID: ownerUserID,
            currencyCode: primaryCurrencyCode,
            now: now,
            context: context
        )
        let activeChannels = try context.fetch(
            FetchDescriptor<InvestmentChannel>(
                predicate: #Predicate<InvestmentChannel> { channel in
                    channel.ownerUserID == ownerUserID && channel.deletedAt == nil
                }
            )
        )
        let channel = InvestmentChannel(
            ownerUserID: ownerUserID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            iconSymbolName: iconSymbolName,
            iconColorHex: iconColorHex,
            sortOrder: activeChannels.count,
            createdAt: now,
            updatedAt: now
        )
        context.insert(channel)
        try context.save()
        return (channel, wallet)
    }

    static func createAsset(
        ownerUserID: UUID,
        channelID: UUID,
        name: String,
        currencyCode: String,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentAsset {
        let channelExists = try context.fetch(
            FetchDescriptor<InvestmentChannel>(
                predicate: #Predicate<InvestmentChannel> { channel in
                    channel.id == channelID
                        && channel.ownerUserID == ownerUserID
                        && channel.deletedAt == nil
                        && !channel.isArchived
                }
            )
        ).isEmpty == false
        guard channelExists else { throw InvestmentPersistenceError.missingAsset }
        let assets = try context.fetch(
            FetchDescriptor<InvestmentAsset>(
                predicate: #Predicate<InvestmentAsset> { asset in
                    asset.ownerUserID == ownerUserID
                        && asset.channelID == channelID
                        && asset.deletedAt == nil
                }
            )
        )
        let asset = InvestmentAsset(
            ownerUserID: ownerUserID,
            channelID: channelID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            currencyCode: MistiaCurrencyLogic.normalizedCode(currencyCode),
            sortOrder: assets.count,
            createdAt: now,
            updatedAt: now
        )
        context.insert(asset)
        try context.save()
        return asset
    }

    static func saveTrade(
        ownerUserID: UUID,
        draft: InvestmentTradeDraft,
        rates: [MistiaExchangeRate],
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let draftID = draft.id
        let storedTrade = try context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in
                    trade.id == draftID && trade.ownerUserID == ownerUserID
                }
            )
        ).first
        if let storedTrade, storedTrade.kind != draft.kind {
            throw InvestmentPersistenceError.invalidTradeInput
        }
        let originalWalletIDs = Set([
            storedTrade?.fundingWalletID,
            storedTrade?.capitalReturnWalletID
        ].compactMap { $0 })

        let targetAsset = try fetchAsset(
            id: draft.assetID,
            ownerUserID: ownerUserID,
            context: context
        )
        guard let targetAsset,
              targetAsset.deletedAt == nil,
              !targetAsset.isArchived,
              targetAsset.channelID == draft.channelID else {
            throw InvestmentPersistenceError.missingAsset
        }

        var originalAsset: InvestmentAsset?
        if let storedTrade, storedTrade.assetID != targetAsset.id {
            guard let fetchedOriginalAsset = try fetchAsset(
                id: storedTrade.assetID,
                ownerUserID: ownerUserID,
                context: context
            ) else {
                throw InvestmentPersistenceError.missingAsset
            }
            originalAsset = fetchedOriginalAsset
        }
        try validateTradeSource(draft: draft, asset: targetAsset)

        let wallets = try context.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in
                    wallet.deletedAt == nil && !wallet.isArchived
                }
            )
        )
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        try validateWalletOwnership(
            ownerUserID: ownerUserID,
            walletIDs: [draft.fundingWalletID, draft.capitalReturnWalletID].compactMap { $0 },
            context: context
        )
        let systemWallet = try ensureSystemWallet(
            ownerUserID: ownerUserID,
            currencyCode: draft.accountingCurrencyCode,
            now: now,
            context: context
        )
        guard MistiaCurrencyLogic.normalizedCode(draft.accountingCurrencyCode)
            == MistiaCurrencyLogic.normalizedCode(systemWallet.currencyCode) else {
            throw InvestmentPersistenceError.missingExchangeRate
        }

        let targetTrades = try activeTrades(
            assetID: targetAsset.id,
            ownerUserID: ownerUserID,
            context: context
        )
        try validateWalletSelection(
            draft: draft,
            systemWallet: systemWallet,
            walletsByID: walletsByID
        )

        let fundingWallet = draft.fundingWalletID.flatMap { walletsByID[$0] }
        let capitalWallet = draft.capitalReturnWalletID.flatMap { walletsByID[$0] }
        let fundingAmountMinor = try fundingWallet.map {
            try convertedAmount(
                amountMinor: draft.accountingGrossAmountMinor,
                from: draft.accountingCurrencyCode,
                to: $0.currencyCode,
                rates: rates
            )
        }

        try validateFundingCapacity(
            draft: draft,
            fundingWallet: fundingWallet,
            fundingAmountMinor: fundingAmountMinor,
            excludingTrade: storedTrade,
            allWallets: wallets,
            context: context
        )

        let targetTradesWithoutEditedTrade = targetTrades.filter { $0.id != draft.id }
        let targetCalculations = try InvestmentAccountingEngine.calculationMap(
            trades: targetTradesWithoutEditedTrade.map(InvestmentTradeInput.init) + [draft.accountingInput]
        )

        let originalRemainingTrades: [InvestmentTrade]
        let originalCalculations: [UUID: InvestmentTradeCalculation]
        if let originalAsset {
            originalRemainingTrades = try activeTrades(
                assetID: originalAsset.id,
                ownerUserID: ownerUserID,
                context: context
            ).filter { $0.id != draft.id }
            originalCalculations = try InvestmentAccountingEngine.calculationMap(
                trades: originalRemainingTrades.map(InvestmentTradeInput.init)
            )
        } else {
            originalRemainingTrades = []
            originalCalculations = [:]
        }

        let trade = storedTrade ?? InvestmentTrade(
            id: draft.id,
            ownerUserID: ownerUserID,
            channelID: draft.channelID,
            assetID: draft.assetID,
            kind: draft.kind,
            quantity: draft.quantity,
            grossAmountMinor: draft.grossAmountMinor,
            currencyCode: draft.currencyCode,
            accountingGrossAmountMinor: draft.accountingGrossAmountMinor,
            accountingCurrencyCode: draft.accountingCurrencyCode,
            occurredAt: draft.occurredAt,
            createdAt: draft.createdAt,
            updatedAt: now
        )
        if storedTrade == nil {
            context.insert(trade)
        }

        apply(draft: draft, to: trade, fundingWallet: fundingWallet, capitalWallet: capitalWallet)
        trade.fundingWalletAmountMinor = fundingAmountMinor
        trade.fundingToAccountingRateDecimalString = fundingWallet.flatMap {
            rateString(from: $0.currencyCode, to: draft.accountingCurrencyCode, rates: rates)
        }
        trade.accountingToCapitalReturnRateDecimalString = capitalWallet.flatMap {
            rateString(from: draft.accountingCurrencyCode, to: $0.currencyCode, rates: rates)
        }
        trade.updatedAt = now

        var touchedWalletIDs = originalWalletIDs
        touchedWalletIDs.insert(systemWallet.id)
        var result = InvestmentPersistenceResult(
            walletIDs: touchedWalletIDs,
            tradeIDs: [trade.id]
        )
        var rebuilds: [(
            asset: InvestmentAsset,
            trades: [InvestmentTrade],
            calculations: [UUID: InvestmentTradeCalculation]
        )] = []
        if let originalAsset {
            rebuilds.append((originalAsset, originalRemainingTrades, originalCalculations))
        }
        rebuilds.append((
            targetAsset,
            targetTradesWithoutEditedTrade + [trade],
            targetCalculations
        ))

        let reconciledWallets = walletsByID.merging([systemWallet.id: systemWallet]) { current, _ in current }
        for rebuild in rebuilds {
            for rebuiltTrade in rebuild.trades where rebuiltTrade.deletedAt == nil {
                guard let calculation = rebuild.calculations[rebuiltTrade.id] else { continue }
                rebuiltTrade.releasedCostBasisMinor = calculation.releasedCostBasisMinor
                rebuiltTrade.realizedProfitLossMinor = calculation.realizedProfitLossMinor
                rebuiltTrade.positionQuantityAfter = calculation.positionQuantityAfter
                rebuiltTrade.positionCostBasisAfterMinor = calculation.positionCostBasisAfterMinor
                if rebuiltTrade.id != trade.id {
                    rebuiltTrade.updatedAt = now
                }

                try reconcileLedgerLegs(
                    ownerUserID: ownerUserID,
                    trade: rebuiltTrade,
                    assetName: rebuild.asset.name,
                    systemWallet: systemWallet,
                    walletsByID: reconciledWallets,
                    now: now,
                    context: context,
                    result: &result
                )
                result.tradeIDs.insert(rebuiltTrade.id)
            }
        }

        try context.save()
        return result
    }

    static func deleteTrade(
        ownerUserID: UUID,
        tradeID: UUID,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let descriptor = FetchDescriptor<InvestmentTrade>(
            predicate: #Predicate<InvestmentTrade> { trade in
                trade.id == tradeID && trade.ownerUserID == ownerUserID
            }
        )
        guard let trade = try context.fetch(descriptor).first,
              let asset = try fetchAsset(id: trade.assetID, ownerUserID: ownerUserID, context: context) else {
            throw InvestmentPersistenceError.missingAsset
        }

        let remainingTrades = try activeTrades(
            assetID: asset.id,
            ownerUserID: ownerUserID,
            context: context
        ).filter { $0.id != tradeID }
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: remainingTrades.map(InvestmentTradeInput.init)
        )

        let wallets = try context.fetch(FetchDescriptor<LedgerWallet>())
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        guard let systemWallet = walletsByID[InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)] else {
            throw InvestmentPersistenceError.missingWallet
        }

        var result = InvestmentPersistenceResult(deletedTradeIDs: [tradeID])
        trade.deletedAt = now
        trade.updatedAt = now
        try deleteLedgerLegs(for: trade, now: now, context: context, result: &result)

        for remainingTrade in remainingTrades {
            guard let calculation = calculations[remainingTrade.id] else { continue }
            remainingTrade.releasedCostBasisMinor = calculation.releasedCostBasisMinor
            remainingTrade.realizedProfitLossMinor = calculation.realizedProfitLossMinor
            remainingTrade.positionQuantityAfter = calculation.positionQuantityAfter
            remainingTrade.positionCostBasisAfterMinor = calculation.positionCostBasisAfterMinor
            remainingTrade.updatedAt = now
            try reconcileLedgerLegs(
                ownerUserID: ownerUserID,
                trade: remainingTrade,
                assetName: asset.name,
                systemWallet: systemWallet,
                walletsByID: walletsByID,
                now: now,
                context: context,
                result: &result
            )
            result.tradeIDs.insert(remainingTrade.id)
        }

        try context.save()
        return result
    }

    static func createOutboundTransfer(
        ownerUserID: UUID,
        destinationWalletID: UUID,
        sourceAmountMinor: Int64,
        destinationAmountMinor: Int64,
        rates: [MistiaExchangeRate],
        occurredAt: Date = .now,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let wallets = try context.fetch(FetchDescriptor<LedgerWallet>())
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        let systemWalletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        guard let systemWallet = walletsByID[systemWalletID],
              let destinationWallet = walletsByID[destinationWalletID] else {
            throw InvestmentPersistenceError.missingWallet
        }
        guard destinationWallet.id != systemWalletID,
              destinationWallet.kind != .creditCard,
              !destinationWallet.isArchived,
              destinationWallet.deletedAt == nil else {
            throw InvestmentPersistenceError.investmentWalletCannotReceiveTransfer
        }
        try validateWalletOwnership(
            ownerUserID: ownerUserID,
            walletIDs: [destinationWallet.id],
            context: context
        )
        guard sourceAmountMinor > 0, destinationAmountMinor > 0 else {
            throw InvestmentPersistenceError.invalidWallet
        }
        let expectedDestinationAmount = try convertedAmount(
            amountMinor: sourceAmountMinor,
            from: systemWallet.currencyCode,
            to: destinationWallet.currencyCode,
            rates: rates
        )
        guard expectedDestinationAmount == destinationAmountMinor else {
            throw InvestmentPersistenceError.invalidTradeInput
        }

        let balance = try currentBalance(wallet: systemWallet, excludingTransactionIDs: [], context: context)
        guard balance > 0, sourceAmountMinor <= balance else {
            throw InvestmentPersistenceError.transferExceedsPositiveBalance
        }

        let eventID = UUID()
        let ledgerID = InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "transfer")
        let transaction = LedgerTransaction(
            id: ledgerID,
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: L10n.investment.wallet.transferTitle,
            amountMinor: sourceAmountMinor,
            reportingExpenseMinor: 0,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: systemWallet.currencyCode,
            destinationCurrencyCode: destinationWallet.currencyCode,
            destinationAmountMinor: destinationAmountMinor,
            reportingCurrencyCode: systemWallet.currencyCode,
            reportingAmountMinor: sourceAmountMinor,
            conversionModeRawValue: systemWallet.currencyCode == destinationWallet.currencyCode
                ? nil
                : MistiaCurrencyConversionMode.appRate.rawValue,
            exchangeRateDecimalString: rateString(
                from: systemWallet.currencyCode,
                to: destinationWallet.currencyCode,
                rates: rates
            ),
            occurredAt: occurredAt,
            createdAt: now,
            updatedAt: now,
            sourceWallet: systemWallet,
            destinationWallet: destinationWallet
        )
        transaction.settlementRoleRawValue = InvestmentLedgerLegRole.investmentTransfer.rawValue
        context.insert(transaction)
        try recordTransactionOwnership(transaction, ownerUserID: ownerUserID, now: now, context: context)

        let sourcePosting = InvestmentWalletPosting(
            id: InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "transfer-source-posting"),
            ownerUserID: ownerUserID,
            eventID: eventID,
            walletID: systemWallet.id,
            ledgerTransactionID: ledgerID,
            role: .transferOut,
            amountMinor: -sourceAmountMinor,
            currencyCode: systemWallet.currencyCode,
            accountingAmountMinor: -sourceAmountMinor,
            accountingCurrencyCode: systemWallet.currencyCode,
            occurredAt: occurredAt,
            createdAt: now,
            updatedAt: now
        )
        let destinationPosting = InvestmentWalletPosting(
            id: InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "transfer-destination-posting"),
            ownerUserID: ownerUserID,
            eventID: eventID,
            walletID: destinationWallet.id,
            ledgerTransactionID: ledgerID,
            role: .transferIn,
            amountMinor: destinationAmountMinor,
            currencyCode: destinationWallet.currencyCode,
            accountingAmountMinor: sourceAmountMinor,
            accountingCurrencyCode: systemWallet.currencyCode,
            occurredAt: occurredAt,
            createdAt: now,
            updatedAt: now
        )
        context.insert(sourcePosting)
        context.insert(destinationPosting)
        try context.save()

        return InvestmentPersistenceResult(
            walletIDs: [systemWallet.id, destinationWallet.id],
            postingIDs: [sourcePosting.id, destinationPosting.id],
            ledgerTransactionIDs: [ledgerID]
        )
    }

    static func currentBalance(
        wallet: LedgerWallet,
        excludingTransactionIDs: Set<UUID> = [],
        context: ModelContext
    ) throws -> Int64 {
        let transactions = try context.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in
                    transaction.deletedAt == nil && !transaction.isArchived
                }
            )
        )
        let records = transactions
            .filter { !excludingTransactionIDs.contains($0.id) }
            .map(\.snapshot)
        let snapshot = TransactionWalletSnapshot(
            id: wallet.id,
            kind: wallet.kind,
            openingBalanceMinor: wallet.openingBalanceMinor
        )
        return TransactionLogic.walletBalanceIndex(wallets: [snapshot], records: records)
            .balance(for: snapshot)
    }

    private static func validateWalletSelection(
        draft: InvestmentTradeDraft,
        systemWallet: LedgerWallet,
        walletsByID: [UUID: LedgerWallet]
    ) throws {
        switch draft.kind {
        case .buy:
            guard let walletID = draft.fundingWalletID,
                  let wallet = walletsByID[walletID],
                  !wallet.isArchived,
                  wallet.deletedAt == nil else {
                throw InvestmentPersistenceError.missingWallet
            }
        case .sell:
            guard let walletID = draft.capitalReturnWalletID,
                  let wallet = walletsByID[walletID],
                  wallet.id != systemWallet.id,
                  wallet.kind != .creditCard,
                  !wallet.isArchived,
                  wallet.deletedAt == nil else {
                throw InvestmentPersistenceError.invalidWallet
            }
        }
    }

    private static func validateTradeSource(
        draft: InvestmentTradeDraft,
        asset: InvestmentAsset
    ) throws {
        let sourceCurrency = MistiaCurrencyLogic.normalizedCode(draft.currencyCode)
        let accountingCurrency = MistiaCurrencyLogic.normalizedCode(draft.accountingCurrencyCode)
        guard draft.quantity > 0,
              draft.grossAmountMinor > 0,
              draft.accountingGrossAmountMinor > 0,
              sourceCurrency == MistiaCurrencyLogic.normalizedCode(asset.currencyCode) else {
            throw InvestmentPersistenceError.invalidTradeInput
        }

        if sourceCurrency == accountingCurrency {
            guard draft.grossAmountMinor == draft.accountingGrossAmountMinor else {
                throw InvestmentPersistenceError.invalidTradeInput
            }
            return
        }

        guard let rateString = draft.exchangeRateDecimalString,
              let rate = InvestmentDecimalCoding.decimal(from: rateString),
              rate > 0,
              let convertedGross = try? InvestmentCurrencyConversion.convertedMinor(
                  draft.grossAmountMinor,
                  rate: rate
              ),
              convertedGross == draft.accountingGrossAmountMinor else {
            throw InvestmentPersistenceError.invalidTradeInput
        }
    }

    private static func validateWalletOwnership(
        ownerUserID: UUID,
        walletIDs: [UUID],
        context: ModelContext
    ) throws {
        guard !walletIDs.isEmpty else { return }
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(
            from: try context.fetch(FetchDescriptor<OwnedRecordScope>()),
            entity: .wallet
        )
        guard walletIDs.allSatisfy({ ownerMap[$0] == nil || ownerMap[$0] == ownerUserID }) else {
            throw InvestmentPersistenceError.invalidWallet
        }
    }

    private static func validateFundingCapacity(
        draft: InvestmentTradeDraft,
        fundingWallet: LedgerWallet?,
        fundingAmountMinor: Int64?,
        excludingTrade: InvestmentTrade?,
        allWallets: [LedgerWallet],
        context: ModelContext
    ) throws {
        guard draft.kind == .buy else { return }
        guard let fundingWallet, let fundingAmountMinor else {
            throw InvestmentPersistenceError.missingWallet
        }
        let excludedIDs = Set([
            excludingTrade?.fundingLedgerTransactionID,
            excludingTrade?.capitalReturnLedgerTransactionID,
            excludingTrade?.profitLossLedgerTransactionID
        ].compactMap { $0 })
        let balance = try currentBalance(
            wallet: fundingWallet,
            excludingTransactionIDs: excludedIDs,
            context: context
        )
        if fundingWallet.kind == .creditCard {
            guard let profile = fundingWallet.creditCardProfile else {
                throw InvestmentPersistenceError.invalidWallet
            }
            let snapshot = TransactionWalletSnapshot(
                id: fundingWallet.id,
                kind: fundingWallet.kind,
                openingBalanceMinor: fundingWallet.openingBalanceMinor
            )
            let credit = TransactionLogic.creditCardBalance(
                creditLimitMinor: profile.creditLimitMinor,
                wallet: snapshot,
                balanceIndex: TransactionWalletBalanceIndex(
                    balancesByWalletID: [fundingWallet.id: balance]
                )
            )
            guard credit.canCover(amountMinor: fundingAmountMinor) else {
                throw InvestmentPersistenceError.insufficientFunds
            }
        } else {
            guard balance >= fundingAmountMinor else {
                throw InvestmentPersistenceError.insufficientFunds
            }
        }
        _ = allWallets
    }

    private static func apply(
        draft: InvestmentTradeDraft,
        to trade: InvestmentTrade,
        fundingWallet: LedgerWallet?,
        capitalWallet: LedgerWallet?
    ) {
        trade.channelID = draft.channelID
        trade.assetID = draft.assetID
        trade.kind = draft.kind
        trade.quantity = draft.quantity
        trade.grossAmountMinor = draft.grossAmountMinor
        trade.currencyCode = MistiaCurrencyLogic.normalizedCode(draft.currencyCode)
        trade.accountingGrossAmountMinor = draft.accountingGrossAmountMinor
        trade.accountingCurrencyCode = MistiaCurrencyLogic.normalizedCode(draft.accountingCurrencyCode)
        trade.exchangeRateDecimalString = draft.exchangeRateDecimalString
        trade.exchangeRateProvider = draft.exchangeRateProvider
        trade.exchangeRateDate = draft.exchangeRateDate
        trade.fundingWalletID = draft.kind == .buy ? draft.fundingWalletID : nil
        trade.capitalReturnWalletID = draft.kind == .sell ? draft.capitalReturnWalletID : nil
        trade.fundingWalletCurrencyCode = fundingWallet?.currencyCode
        trade.capitalReturnWalletCurrencyCode = capitalWallet?.currencyCode
        trade.note = normalizedOptionalText(draft.note)
        trade.occurredAt = draft.occurredAt
        trade.deletedAt = nil
    }

    private static func reconcileLedgerLegs(
        ownerUserID: UUID,
        trade: InvestmentTrade,
        assetName: String,
        systemWallet: LedgerWallet,
        walletsByID: [UUID: LedgerWallet],
        now: Date,
        context: ModelContext,
        result: inout InvestmentPersistenceResult
    ) throws {
        switch trade.kind {
        case .buy:
            guard let walletID = trade.fundingWalletID,
                  let wallet = walletsByID[walletID],
                  let walletAmount = trade.fundingWalletAmountMinor else {
                throw InvestmentPersistenceError.missingWallet
            }
            let ledgerID = InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "funding")
            let transaction = try upsertLedgerTransaction(
                id: ledgerID,
                primaryKind: .expense,
                role: .investmentFunding,
                title: assetName,
                amountMinor: walletAmount,
                sourceWallet: wallet,
                destinationWallet: nil,
                destinationAmountMinor: nil,
                reportingAmountMinor: trade.accountingGrossAmountMinor,
                reportingCurrencyCode: trade.accountingCurrencyCode,
                occurredAt: trade.occurredAt,
                now: now,
                context: context
            )
            trade.fundingLedgerTransactionID = transaction.id
            trade.capitalReturnLedgerTransactionID = nil
            trade.profitLossLedgerTransactionID = nil
            try deleteUnexpectedLedgerLegs(for: trade, keeping: [transaction.id], now: now, context: context, result: &result)
            let posting = try upsertPosting(
                id: InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "funding-posting"),
                ownerUserID: ownerUserID,
                trade: trade,
                walletID: wallet.id,
                ledgerTransactionID: transaction.id,
                role: .funding,
                amountMinor: -walletAmount,
                currencyCode: wallet.currencyCode,
                accountingAmountMinor: -trade.accountingGrossAmountMinor,
                now: now,
                context: context
            )
            try deleteUnexpectedPostings(for: trade, keeping: [posting.id], now: now, context: context, result: &result)
            try recordTransactionOwnership(transaction, ownerUserID: ownerUserID, now: now, context: context)
            result.ledgerTransactionIDs.insert(transaction.id)
            result.postingIDs.insert(posting.id)
            result.walletIDs.insert(wallet.id)

        case .sell:
            guard let capitalWalletID = trade.capitalReturnWalletID,
                  let capitalWallet = walletsByID[capitalWalletID] else {
                throw InvestmentPersistenceError.missingWallet
            }
            let capitalAmount = try convertedWithStoredRate(
                trade.releasedCostBasisMinor,
                sourceCurrencyCode: trade.accountingCurrencyCode,
                destinationCurrencyCode: capitalWallet.currencyCode,
                rateDecimalString: trade.accountingToCapitalReturnRateDecimalString
            )
            trade.capitalReturnWalletAmountMinor = capitalAmount

            let capitalLedgerID = InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "capital-return")
            let capitalTransaction = try upsertLedgerTransaction(
                id: capitalLedgerID,
                primaryKind: .income,
                role: .investmentCapitalReturn,
                title: assetName,
                amountMinor: capitalAmount,
                sourceWallet: capitalWallet,
                destinationWallet: nil,
                destinationAmountMinor: nil,
                reportingAmountMinor: trade.releasedCostBasisMinor,
                reportingCurrencyCode: trade.accountingCurrencyCode,
                occurredAt: trade.occurredAt,
                now: now,
                context: context
            )
            trade.capitalReturnLedgerTransactionID = capitalTransaction.id
            trade.fundingLedgerTransactionID = nil

            var keepingLedgerIDs: Set<UUID> = [capitalTransaction.id]
            var keepingPostingIDs: Set<UUID> = []
            let capitalPosting = try upsertPosting(
                id: InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "capital-return-posting"),
                ownerUserID: ownerUserID,
                trade: trade,
                walletID: capitalWallet.id,
                ledgerTransactionID: capitalTransaction.id,
                role: .capitalReturn,
                amountMinor: capitalAmount,
                currencyCode: capitalWallet.currencyCode,
                accountingAmountMinor: trade.releasedCostBasisMinor,
                now: now,
                context: context
            )
            keepingPostingIDs.insert(capitalPosting.id)
            result.ledgerTransactionIDs.insert(capitalTransaction.id)
            result.postingIDs.insert(capitalPosting.id)
            result.walletIDs.insert(capitalWallet.id)
            try recordTransactionOwnership(capitalTransaction, ownerUserID: ownerUserID, now: now, context: context)

            if trade.realizedProfitLossMinor != 0 {
                let profitLedgerID = InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "profit-loss")
                let profitTransaction = try upsertLedgerTransaction(
                    id: profitLedgerID,
                    primaryKind: trade.realizedProfitLossMinor > 0 ? .income : .expense,
                    role: .investmentRealizedProfit,
                    title: assetName,
                    amountMinor: absWithoutOverflow(trade.realizedProfitLossMinor),
                    sourceWallet: systemWallet,
                    destinationWallet: nil,
                    destinationAmountMinor: nil,
                    reportingAmountMinor: absWithoutOverflow(trade.realizedProfitLossMinor),
                    reportingCurrencyCode: systemWallet.currencyCode,
                    occurredAt: trade.occurredAt,
                    now: now,
                    context: context
                )
                trade.profitLossLedgerTransactionID = profitTransaction.id
                keepingLedgerIDs.insert(profitTransaction.id)
                let profitPosting = try upsertPosting(
                    id: InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "profit-loss-posting"),
                    ownerUserID: ownerUserID,
                    trade: trade,
                    walletID: systemWallet.id,
                    ledgerTransactionID: profitTransaction.id,
                    role: .realizedProfit,
                    amountMinor: trade.realizedProfitLossMinor,
                    currencyCode: systemWallet.currencyCode,
                    accountingAmountMinor: trade.realizedProfitLossMinor,
                    now: now,
                    context: context
                )
                keepingPostingIDs.insert(profitPosting.id)
                result.ledgerTransactionIDs.insert(profitTransaction.id)
                result.postingIDs.insert(profitPosting.id)
                result.walletIDs.insert(systemWallet.id)
                try recordTransactionOwnership(profitTransaction, ownerUserID: ownerUserID, now: now, context: context)
            } else {
                trade.profitLossLedgerTransactionID = nil
            }

            try deleteUnexpectedLedgerLegs(for: trade, keeping: keepingLedgerIDs, now: now, context: context, result: &result)
            try deleteUnexpectedPostings(for: trade, keeping: keepingPostingIDs, now: now, context: context, result: &result)
        }
    }

    private static func upsertLedgerTransaction(
        id: UUID,
        primaryKind: TransactionPrimaryKind,
        role: InvestmentLedgerLegRole,
        title: String,
        amountMinor: Int64,
        sourceWallet: LedgerWallet,
        destinationWallet: LedgerWallet?,
        destinationAmountMinor: Int64?,
        reportingAmountMinor: Int64,
        reportingCurrencyCode: String,
        occurredAt: Date,
        now: Date,
        context: ModelContext
    ) throws -> LedgerTransaction {
        let descriptor = FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate<LedgerTransaction> { transaction in
                transaction.id == id
            }
        )
        let transaction = try context.fetch(descriptor).first ?? LedgerTransaction(
            id: id,
            primaryKind: primaryKind,
            entryStatus: .posted,
            title: title,
            amountMinor: amountMinor,
            reportingExpenseMinor: 0,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: sourceWallet.currencyCode,
            destinationCurrencyCode: destinationWallet?.currencyCode,
            destinationAmountMinor: destinationAmountMinor,
            reportingCurrencyCode: reportingCurrencyCode,
            reportingAmountMinor: reportingAmountMinor,
            occurredAt: occurredAt,
            createdAt: now,
            updatedAt: now,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet
        )
        if transaction.modelContext == nil {
            context.insert(transaction)
        }
        transaction.primaryKind = primaryKind
        transaction.transferSubtype = primaryKind == .transfer ? .internalTransfer : nil
        transaction.debtIntent = nil
        transaction.entryStatus = .posted
        transaction.title = title
        transaction.note = nil
        transaction.amountMinor = max(amountMinor, 0)
        transaction.reportingExpenseMinor = 0
        transaction.reportingIncomeMinor = 0
        transaction.sourceCurrencyCode = sourceWallet.currencyCode
        transaction.destinationCurrencyCode = destinationWallet?.currencyCode
        transaction.destinationAmountMinor = destinationAmountMinor
        transaction.reportingCurrencyCode = reportingCurrencyCode
        transaction.reportingAmountMinor = reportingAmountMinor
        transaction.category = nil
        transaction.sourceWallet = sourceWallet
        transaction.destinationWallet = destinationWallet
        transaction.settlementGroupID = nil
        transaction.settlementObligationID = nil
        transaction.settlementRoleRawValue = role.rawValue
        transaction.occurredAt = occurredAt
        transaction.updatedAt = now
        transaction.deletedAt = nil
        transaction.isArchived = false
        transaction.archivedAt = nil
        return transaction
    }

    private static func upsertPosting(
        id: UUID,
        ownerUserID: UUID,
        trade: InvestmentTrade,
        walletID: UUID,
        ledgerTransactionID: UUID,
        role: InvestmentPostingRole,
        amountMinor: Int64,
        currencyCode: String,
        accountingAmountMinor: Int64,
        now: Date,
        context: ModelContext
    ) throws -> InvestmentWalletPosting {
        let descriptor = FetchDescriptor<InvestmentWalletPosting>(
            predicate: #Predicate<InvestmentWalletPosting> { posting in
                posting.id == id
            }
        )
        let posting = try context.fetch(descriptor).first ?? InvestmentWalletPosting(
            id: id,
            ownerUserID: ownerUserID,
            eventID: trade.id,
            tradeID: trade.id,
            assetID: trade.assetID,
            walletID: walletID,
            ledgerTransactionID: ledgerTransactionID,
            role: role,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            accountingAmountMinor: accountingAmountMinor,
            accountingCurrencyCode: trade.accountingCurrencyCode,
            occurredAt: trade.occurredAt,
            createdAt: now,
            updatedAt: now
        )
        if posting.modelContext == nil {
            context.insert(posting)
        }
        posting.ownerUserID = ownerUserID
        posting.eventID = trade.id
        posting.tradeID = trade.id
        posting.assetID = trade.assetID
        posting.walletID = walletID
        posting.ledgerTransactionID = ledgerTransactionID
        posting.role = role
        posting.amountMinor = amountMinor
        posting.currencyCode = currencyCode
        posting.accountingAmountMinor = accountingAmountMinor
        posting.accountingCurrencyCode = trade.accountingCurrencyCode
        posting.occurredAt = trade.occurredAt
        posting.updatedAt = now
        posting.deletedAt = nil
        return posting
    }

    private static func deleteUnexpectedLedgerLegs(
        for trade: InvestmentTrade,
        keeping: Set<UUID>,
        now: Date,
        context: ModelContext,
        result: inout InvestmentPersistenceResult
    ) throws {
        let candidateIDs = [
            InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "funding"),
            InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "capital-return"),
            InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "profit-loss")
        ]
        for id in candidateIDs where !keeping.contains(id) {
            let descriptor = FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in
                    transaction.id == id
                }
            )
            if let transaction = try context.fetch(descriptor).first,
               transaction.deletedAt == nil {
                transaction.deletedAt = now
                transaction.updatedAt = now
                result.deletedLedgerTransactionIDs.insert(id)
            }
        }
    }

    private static func deleteUnexpectedPostings(
        for trade: InvestmentTrade,
        keeping: Set<UUID>,
        now: Date,
        context: ModelContext,
        result: inout InvestmentPersistenceResult
    ) throws {
        let tradeID: UUID? = trade.id
        let descriptor = FetchDescriptor<InvestmentWalletPosting>(
            predicate: #Predicate<InvestmentWalletPosting> { posting in
                posting.tradeID == tradeID
            }
        )
        for posting in try context.fetch(descriptor) where !keeping.contains(posting.id) && posting.deletedAt == nil {
            posting.deletedAt = now
            posting.updatedAt = now
            result.deletedPostingIDs.insert(posting.id)
        }
    }

    private static func deleteLedgerLegs(
        for trade: InvestmentTrade,
        now: Date,
        context: ModelContext,
        result: inout InvestmentPersistenceResult
    ) throws {
        try deleteUnexpectedLedgerLegs(for: trade, keeping: [], now: now, context: context, result: &result)
        try deleteUnexpectedPostings(for: trade, keeping: [], now: now, context: context, result: &result)
    }

    private static func recordTransactionOwnership(
        _ transaction: LedgerTransaction,
        ownerUserID: UUID,
        now: Date,
        context: ModelContext
    ) throws {
        try MistiaRecordOwnershipStore.upsert(
            entity: .transaction,
            recordID: transaction.id,
            ownerUserID: ownerUserID,
            updatedAt: now,
            context: context
        )
        try TransactionAuditStore.upsert(
            transactionID: transaction.id,
            createdByUserID: ownerUserID,
            lastModifiedByUserID: ownerUserID,
            updatedAt: now,
            context: context
        )
    }

    private static func activeTrades(
        assetID: UUID,
        ownerUserID: UUID,
        context: ModelContext
    ) throws -> [InvestmentTrade] {
        try context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in
                    trade.assetID == assetID
                        && trade.ownerUserID == ownerUserID
                        && trade.deletedAt == nil
                }
            )
        )
    }

    private static func fetchAsset(
        id: UUID,
        ownerUserID: UUID,
        context: ModelContext
    ) throws -> InvestmentAsset? {
        try context.fetch(
            FetchDescriptor<InvestmentAsset>(
                predicate: #Predicate<InvestmentAsset> { asset in
                    asset.id == id && asset.ownerUserID == ownerUserID
                }
            )
        ).first
    }

    private static func convertedAmount(
        amountMinor: Int64,
        from sourceCurrencyCode: String,
        to destinationCurrencyCode: String,
        rates: [MistiaExchangeRate]
    ) throws -> Int64 {
        let source = MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode)
        let destination = MistiaCurrencyLogic.normalizedCode(destinationCurrencyCode)
        if source == destination { return amountMinor }
        guard let converted = MistiaCurrencyLogic.convertedMinorAmount(
            amountMinor,
            from: source,
            to: destination,
            rates: rates
        ) else {
            throw InvestmentPersistenceError.missingExchangeRate
        }
        return converted
    }

    private static func rateString(
        from sourceCurrencyCode: String,
        to destinationCurrencyCode: String,
        rates: [MistiaExchangeRate]
    ) -> String? {
        let source = MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode)
        let destination = MistiaCurrencyLogic.normalizedCode(destinationCurrencyCode)
        guard source != destination else { return nil }
        if let direct = rates.first(where: {
            MistiaCurrencyLogic.normalizedCode($0.baseCurrencyCode) == source
                && MistiaCurrencyLogic.normalizedCode($0.quoteCurrencyCode) == destination
        })?.rateDecimal {
            return InvestmentDecimalCoding.string(from: direct)
        }
        if let inverse = rates.first(where: {
            MistiaCurrencyLogic.normalizedCode($0.baseCurrencyCode) == destination
                && MistiaCurrencyLogic.normalizedCode($0.quoteCurrencyCode) == source
        })?.rateDecimal,
           inverse != 0 {
            return InvestmentDecimalCoding.string(from: 1 / inverse)
        }
        return nil
    }

    private static func convertedWithStoredRate(
        _ amountMinor: Int64,
        sourceCurrencyCode: String,
        destinationCurrencyCode: String,
        rateDecimalString: String?
    ) throws -> Int64 {
        let source = MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode)
        let destination = MistiaCurrencyLogic.normalizedCode(destinationCurrencyCode)
        if source == destination { return amountMinor }
        guard let rateDecimalString,
              let rate = InvestmentDecimalCoding.decimal(from: rateDecimalString) else {
            throw InvestmentPersistenceError.missingExchangeRate
        }
        return try InvestmentCurrencyConversion.convertedMinor(amountMinor, rate: rate)
    }

    private static func accountingAmountToFundingWallet(
        _ amountMinor: Int64,
        accountingCurrencyCode: String,
        fundingWalletCurrencyCode: String,
        fundingToAccountingRateDecimalString: String?
    ) throws -> Int64 {
        let accounting = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        let funding = MistiaCurrencyLogic.normalizedCode(fundingWalletCurrencyCode)
        if accounting == funding { return amountMinor }
        guard let rateString = fundingToAccountingRateDecimalString,
              let rate = InvestmentDecimalCoding.decimal(from: rateString),
              rate > 0 else {
            throw InvestmentPersistenceError.missingExchangeRate
        }
        var value = Decimal(amountMinor) / rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending,
              number.compare(NSDecimalNumber(value: Int64.min)) != .orderedAscending else {
            throw InvestmentPersistenceError.invalidTradeInput
        }
        return number.int64Value
    }

    private static func absWithoutOverflow(_ value: Int64) -> Int64 {
        value == .min ? .max : abs(value)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private nonisolated extension InvestmentTradeInput {
    init(_ trade: InvestmentTrade) {
        self.init(
            id: trade.id,
            kind: trade.kind,
            quantity: trade.quantity,
            accountingGrossAmountMinor: trade.accountingGrossAmountMinor,
            occurredAt: trade.occurredAt,
            createdAt: trade.createdAt
        )
    }
}

private nonisolated extension InvestmentTradeDraft {
    var accountingInput: InvestmentTradeInput {
        InvestmentTradeInput(
            id: id,
            kind: kind,
            quantity: quantity,
            accountingGrossAmountMinor: accountingGrossAmountMinor,
            occurredAt: occurredAt,
            createdAt: createdAt
        )
    }
}

@MainActor
enum InvestmentPrivacyCacheService {
    static func purge(
        ownerUserID: UUID,
        context: ModelContext
    ) throws {
        let postings = try context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .filter { $0.ownerUserID == ownerUserID }
        let allLedgerTransactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let ownedInvestmentLedgerTransactionIDs = Set(
            ownershipScopes.lazy
                .filter { $0.entity == .transaction && $0.ownerUserID == ownerUserID }
                .map(\.recordID)
        )
        let ledgerTransactionIDs = Set(postings.map(\.ledgerTransactionID)).union(
            allLedgerTransactions.lazy
                .filter {
                    ownedInvestmentLedgerTransactionIDs.contains($0.id)
                        && InvestmentLedgerLegRole.isInvestmentRawValue($0.settlementRoleRawValue)
                }
                .map(\.id)
        )
        let investmentWalletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)

        try context.fetch(FetchDescriptor<InvestmentValuation>())
            .filter { $0.ownerUserID == ownerUserID }
            .forEach(context.delete)
        postings.forEach(context.delete)
        try context.fetch(FetchDescriptor<InvestmentTrade>())
            .filter { $0.ownerUserID == ownerUserID }
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<InvestmentAsset>())
            .filter { $0.ownerUserID == ownerUserID }
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<InvestmentChannel>())
            .filter { $0.ownerUserID == ownerUserID }
            .forEach(context.delete)
        allLedgerTransactions
            .filter { ledgerTransactionIDs.contains($0.id) }
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<LedgerWallet>())
            .filter { $0.id == investmentWalletID }
            .forEach(context.delete)
        ownershipScopes
            .filter {
                ($0.entity == .transaction && ledgerTransactionIDs.contains($0.recordID))
                    || ($0.entity == .wallet && $0.recordID == investmentWalletID)
            }
            .forEach(context.delete)
        try context.save()
    }
}
