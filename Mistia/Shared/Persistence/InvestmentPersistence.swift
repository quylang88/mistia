import Foundation
import os
import SwiftData

nonisolated struct InvestmentAssetDraft: Equatable {
    let id: UUID
    var channelID: UUID
    var name: String
    var currencyCode: String
    var imagePath: String?
    var defaultUnitLabel: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        channelID: UUID,
        name: String,
        currencyCode: String,
        imagePath: String? = nil,
        defaultUnitLabel: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.channelID = channelID
        self.name = name
        self.currencyCode = currencyCode
        self.imagePath = imagePath
        self.defaultUnitLabel = InvestmentUnitLabel.normalizedDisplay(defaultUnitLabel)
        self.createdAt = createdAt
    }
}

nonisolated struct InvestmentTradeDraft: Equatable {
    let id: UUID
    var channelID: UUID
    var assetID: UUID
    var kind: InvestmentTradeKind
    var quantity: Decimal
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
    var note: String?
    var occurredAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
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
        note: String? = nil,
        occurredAt: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.channelID = channelID
        self.assetID = assetID
        self.kind = kind
        self.quantity = quantity
        self.unitLabel = InvestmentUnitLabel.normalizedDisplay(unitLabel)
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

nonisolated struct InvestmentPersistenceResult: Equatable, Sendable {
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
    case invalidAssetInput
    case assetHistoryLocksAccounting
    case assetHasRemainingInventory

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
        case .invalidAssetInput:
            return L10n.investment.error.invalidAssetInput
        case .assetHistoryLocksAccounting:
            return L10n.investment.error.assetHistoryLocksAccounting
        case .assetHasRemainingInventory:
            return L10n.investment.error.closePositionsBeforeDelete
        }
    }
}

nonisolated extension InvestmentCashAllocationLogic {
    static func linkedWalletAllocation(
        configurations: [InvestmentWalletConfiguration],
        postings: [InvestmentWalletPosting],
        cashPostingMetadata: [InvestmentCashPostingMetadata],
        ownerUserID: UUID,
        accountingCurrencyCode: String
    ) -> InvestmentLinkedWalletAllocationSnapshot {
        guard let linkedWalletID = configurations.first(where: {
            $0.ownerUserID == ownerUserID
        })?.linkedWalletID else {
            return InvestmentLinkedWalletAllocationSnapshot(
                linkedWalletID: nil,
                profitMinor: 0
            )
        }
        let allocation = snapshot(
            postings: postings,
            cashPostingMetadata: cashPostingMetadata,
            ownerUserID: ownerUserID,
            accountingCurrencyCode: accountingCurrencyCode
        )
        let profitMinor = allocation.locations.first {
            $0.walletID == linkedWalletID
        }?.totalMinor ?? 0
        return InvestmentLinkedWalletAllocationSnapshot(
            linkedWalletID: linkedWalletID,
            profitMinor: max(profitMinor, 0)
        )
    }

    static func snapshot(
        postings: [InvestmentWalletPosting],
        cashPostingMetadata: [InvestmentCashPostingMetadata],
        ownerUserID: UUID,
        accountingCurrencyCode: String
    ) -> InvestmentCashAllocationSnapshot {
        let cashBucketByPostingID = Dictionary(
            uniqueKeysWithValues: cashPostingMetadata.lazy
                .filter { $0.ownerUserID == ownerUserID }
                .map { ($0.id, $0.cashBucket) }
        )
        return snapshot(
            postings: postings.compactMap { posting in
                guard posting.ownerUserID == ownerUserID,
                      posting.deletedAt == nil,
                      let bucket = cashBucketByPostingID[posting.id] else {
                    return nil
                }
                return InvestmentCashPostingSnapshot(
                    walletID: posting.walletID,
                    currencyCode: posting.currencyCode,
                    amountMinor: posting.amountMinor,
                    accountingAmountMinor: posting.accountingAmountMinor,
                    accountingCurrencyCode: posting.accountingCurrencyCode,
                    bucket: bucket
                )
            },
            accountingCurrencyCode: accountingCurrencyCode
        )
    }
}

private enum InvestmentReconciliationSignpost {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "Mistia",
        category: "InvestmentPerformance"
    )

    static func begin(_ name: StaticString, assetCount: Int, tradeCount: Int) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: name,
            signpostID: id,
            "assets=%{public}d trades=%{public}d",
            assetCount,
            tradeCount
        )
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}

enum InvestmentPersistenceService {
    private struct RebuildAsset {
        let id: UUID
        let ownerUserID: UUID
        let name: String
    }

    private enum InvestmentDerivedWritePolicy {
        case always
        case ifChanged
    }

    private struct InvestmentUpsertOutcome<Model> {
        let model: Model
        let didMutate: Bool
    }

    @discardableResult
    private static func assignIfChanged<Root: AnyObject, Value: Equatable>(
        _ value: Value,
        to keyPath: ReferenceWritableKeyPath<Root, Value>,
        on root: Root
    ) -> Bool {
        guard root[keyPath: keyPath] != value else { return false }
        root[keyPath: keyPath] = value
        return true
    }

    @discardableResult
    private static func assignDerivedValue<Root: AnyObject, Value: Equatable>(
        _ value: Value,
        to keyPath: ReferenceWritableKeyPath<Root, Value>,
        on root: Root,
        writePolicy: InvestmentDerivedWritePolicy
    ) -> Bool {
        switch writePolicy {
        case .always:
            root[keyPath: keyPath] = value
            return true
        case .ifChanged:
            return assignIfChanged(value, to: keyPath, on: root)
        }
    }

    private static func applyCalculationIfNeeded(
        _ calculation: InvestmentTradeCalculation,
        to trade: InvestmentTrade
    ) -> Bool {
        var didMutate = false
        didMutate = assignIfChanged(
            calculation.releasedCostBasisMinor,
            to: \.releasedCostBasisMinor,
            on: trade
        ) || didMutate
        didMutate = assignIfChanged(
            calculation.realizedProfitLossMinor,
            to: \.realizedProfitLossMinor,
            on: trade
        ) || didMutate
        didMutate = assignIfChanged(
            InvestmentDecimalCoding.string(from: calculation.positionQuantityAfter),
            to: \.positionQuantityAfterDecimalString,
            on: trade
        ) || didMutate
        didMutate = assignIfChanged(
            calculation.positionCostBasisAfterMinor,
            to: \.positionCostBasisAfterMinor,
            on: trade
        ) || didMutate
        return didMutate
    }

    static func rebuildDerivedAccountingForV8(
        now: Date = .now,
        context: ModelContext
    ) throws {
        let assets = try context.fetch(FetchDescriptor<MistiaSchemaV8.InvestmentAsset>())
            .filter { $0.deletedAt == nil }
            .map { RebuildAsset(id: $0.id, ownerUserID: $0.ownerUserID, name: $0.name) }
        try rebuildDerivedAccounting(
            assets: assets,
            now: now,
            scrubLegacyConflicts: true,
            context: context
        )
    }

    static func rebuildDerivedAccountingForFIFO(
        now: Date = .now,
        context: ModelContext
    ) throws {
        try rebuildDerivedAccounting(now: now, scrubLegacyConflicts: true, context: context)
    }

    static func rebuildDerivedAccountingAfterLegacyFieldRemoval(
        now: Date = .now,
        context: ModelContext
    ) throws {
        try rebuildDerivedAccounting(now: now, scrubLegacyConflicts: true, context: context)
    }

    static func cashAllocationSnapshot(
        ownerUserID: UUID,
        accountingCurrencyCode: String,
        context: ModelContext
    ) throws -> InvestmentCashAllocationSnapshot {
        let postings = try context.fetch(
            FetchDescriptor<InvestmentWalletPosting>(
                predicate: #Predicate<InvestmentWalletPosting> { posting in
                    posting.ownerUserID == ownerUserID && posting.deletedAt == nil
                }
            )
        )
        let cashPostingMetadata = try context.fetch(
            FetchDescriptor<InvestmentCashPostingMetadata>(
                predicate: #Predicate<InvestmentCashPostingMetadata> { metadata in
                    metadata.ownerUserID == ownerUserID
                }
            )
        )
        return InvestmentCashAllocationLogic.snapshot(
            postings: postings,
            cashPostingMetadata: cashPostingMetadata,
            ownerUserID: ownerUserID,
            accountingCurrencyCode: accountingCurrencyCode
        )
    }

    static func configuration(
        ownerUserID: UUID,
        createIfMissing: Bool = true,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentWalletConfiguration? {
        let configurationID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        let descriptor = FetchDescriptor<InvestmentWalletConfiguration>(
            predicate: #Predicate<InvestmentWalletConfiguration> { configuration in
                configuration.id == configurationID
            }
        )
        if let configuration = try context.fetch(descriptor).first {
            return configuration
        }
        guard createIfMissing else { return nil }
        let configuration = InvestmentWalletConfiguration(
            id: configurationID,
            ownerUserID: ownerUserID,
            systemWalletID: configurationID,
            createdAt: now,
            updatedAt: now
        )
        context.insert(configuration)
        return configuration
    }

    @discardableResult
    static func setLinkedWallet(
        ownerUserID: UUID,
        linkedWalletID: UUID?,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentWalletConfiguration {
        let systemWalletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        guard let systemWallet = try context.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in wallet.id == systemWalletID }
            )
        ).first else {
            throw InvestmentPersistenceError.missingWallet
        }
        if let linkedWalletID {
            guard let wallet = try context.fetch(
                FetchDescriptor<LedgerWallet>(
                    predicate: #Predicate<LedgerWallet> { wallet in wallet.id == linkedWalletID }
                )
            ).first,
            wallet.id != systemWalletID,
            wallet.kind != .creditCard,
            wallet.kind != .investment,
            !wallet.isArchived,
            wallet.deletedAt == nil,
            MistiaCurrencyLogic.normalizedCode(wallet.currencyCode)
                == MistiaCurrencyLogic.normalizedCode(systemWallet.currencyCode) else {
                throw InvestmentPersistenceError.invalidWallet
            }
            try validateWalletOwnership(
                ownerUserID: ownerUserID,
                walletIDs: [wallet.id],
                context: context
            )
        }
        let configuration = try configuration(
            ownerUserID: ownerUserID,
            now: now,
            context: context
        )!
        configuration.linkedWalletID = linkedWalletID
        configuration.updatedAt = now
        // The cloud stores this preference on the system wallet row. Bump the
        // wallet timestamp so conditional sync cannot discard a link change as stale.
        systemWallet.updatedAt = now
        try context.save()
        return configuration
    }

    @discardableResult
    static func changeLinkedWallet(
        ownerUserID: UUID,
        linkedWalletID: UUID,
        moveAllBookedCash: Bool,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let previousConfiguration = try configuration(
            ownerUserID: ownerUserID,
            createIfMissing: true,
            context: context
        )
        let previousLinkedWalletID = previousConfiguration?.linkedWalletID
        let configuration = try setLinkedWallet(
            ownerUserID: ownerUserID,
            linkedWalletID: linkedWalletID,
            now: now,
            context: context
        )
        var result = InvestmentPersistenceResult(walletIDs: [configuration.systemWalletID, linkedWalletID])
        guard moveAllBookedCash,
              let previousLinkedWalletID,
              previousLinkedWalletID != linkedWalletID else {
            return result
        }
        let wallets = try context.fetch(FetchDescriptor<LedgerWallet>())
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        guard let systemWallet = walletsByID[configuration.systemWalletID],
              let sourceWallet = walletsByID[previousLinkedWalletID],
              let destinationWallet = walletsByID[linkedWalletID] else {
            throw InvestmentPersistenceError.missingWallet
        }
        let snapshot = try cashAllocationSnapshot(
            ownerUserID: ownerUserID,
            accountingCurrencyCode: systemWallet.currencyCode,
            context: context
        )
        let amount = max(
            snapshot.locations.first { $0.walletID == previousLinkedWalletID }?.bookedMinor ?? 0,
            0
        )
        guard amount > 0 else { return result }
        let eventID = UUID()
        let ledgerID = InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "linked-wallet-move")
        let transaction = try upsertLedgerTransaction(
            id: ledgerID,
            primaryKind: .transfer,
            role: .investmentReconciliation,
            title: L10n.investment.wallet.changeAndTransferAll,
            amountMinor: amount,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            destinationAmountMinor: amount,
            reportingAmountMinor: amount,
            reportingCurrencyCode: systemWallet.currencyCode,
            occurredAt: now,
            now: now,
            context: context
        )
        try recordTransactionOwnership(transaction, ownerUserID: ownerUserID, now: now, context: context)
        let sourcePosting = try upsertCashPosting(
            id: InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "old-linked-cash-posting"),
            ownerUserID: ownerUserID,
            eventID: eventID,
            walletID: sourceWallet.id,
            ledgerTransactionID: ledgerID,
            role: .cashTransfer,
            bucket: .booked,
            origin: .manual,
            amountMinor: -amount,
            currencyCode: sourceWallet.currencyCode,
            accountingAmountMinor: -amount,
            accountingCurrencyCode: systemWallet.currencyCode,
            occurredAt: now,
            now: now,
            context: context
        )
        let destinationPosting = try upsertCashPosting(
            id: InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "new-linked-cash-posting"),
            ownerUserID: ownerUserID,
            eventID: eventID,
            walletID: destinationWallet.id,
            ledgerTransactionID: ledgerID,
            role: .cashTransfer,
            bucket: .booked,
            origin: .manual,
            amountMinor: amount,
            currencyCode: destinationWallet.currencyCode,
            accountingAmountMinor: amount,
            accountingCurrencyCode: systemWallet.currencyCode,
            occurredAt: now,
            now: now,
            context: context
        )
        result.walletIDs.insert(previousLinkedWalletID)
        result.postingIDs.formUnion([sourcePosting.id, destinationPosting.id])
        result.ledgerTransactionIDs.insert(transaction.id)
        try context.save()
        return result
    }

    static func rebuildCashAllocations(
        origin: InvestmentCashPostingOrigin = .derived,
        now: Date = .now,
        context: ModelContext
    ) throws {
        let trades = try context.fetch(FetchDescriptor<InvestmentTrade>())
            .filter { $0.deletedAt == nil && $0.kind == .sell && $0.realizedProfitLossMinor != 0 }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return MistiaStableUUIDOrdering.precedes($0.id, $1.id)
            }
        for trade in trades {
            guard let walletID = trade.capitalReturnWalletID,
                  let ledgerID = trade.profitLossLedgerTransactionID else { continue }
            let cashCurrencyCode = trade.capitalReturnWalletCurrencyCode ?? trade.accountingCurrencyCode
            let localGrossAmount = try convertedWithStoredRate(
                trade.accountingGrossAmountMinor,
                sourceCurrencyCode: trade.accountingCurrencyCode,
                destinationCurrencyCode: cashCurrencyCode,
                rateDecimalString: trade.accountingToCapitalReturnRateDecimalString
            )
            let localCashAmount = localGrossAmount - (trade.capitalReturnWalletAmountMinor ?? 0)
            _ = try upsertCashPosting(
                id: InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "cash-accrual-posting"),
                ownerUserID: trade.ownerUserID,
                eventID: trade.id,
                tradeID: trade.id,
                assetID: trade.assetID,
                walletID: walletID,
                ledgerTransactionID: ledgerID,
                role: .cashAccrual,
                bucket: .booked,
                origin: origin,
                amountMinor: localCashAmount,
                currencyCode: cashCurrencyCode,
                accountingAmountMinor: trade.realizedProfitLossMinor,
                accountingCurrencyCode: trade.accountingCurrencyCode,
                occurredAt: trade.occurredAt,
                now: now,
                context: context
            )
        }
        try context.save()
    }

    private static func rebuildDerivedAccounting(
        now: Date,
        scrubLegacyConflicts: Bool,
        context: ModelContext
    ) throws {
        let assets = try context.fetch(FetchDescriptor<InvestmentAsset>())
            .filter { $0.deletedAt == nil }
            .map { RebuildAsset(id: $0.id, ownerUserID: $0.ownerUserID, name: $0.name) }
        try rebuildDerivedAccounting(
            assets: assets,
            now: now,
            scrubLegacyConflicts: scrubLegacyConflicts,
            context: context
        )
    }

    private static func rebuildDerivedAccounting(
        assets: [RebuildAsset],
        now: Date,
        scrubLegacyConflicts: Bool,
        context: ModelContext
    ) throws {
        if scrubLegacyConflicts {
            try scrubLegacyInvestmentFieldsFromSyncConflicts(context: context)
        }

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
            if conflict.entityRawValue == "investment_valuations" {
                context.delete(conflict)
                continue
            }
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
        id: UUID = UUID(),
        ownerUserID: UUID,
        channelID: UUID,
        name: String,
        currencyCode: String,
        imagePath: String? = nil,
        defaultUnitLabel: String? = nil,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentAsset {
        try saveAsset(
            ownerUserID: ownerUserID,
            draft: InvestmentAssetDraft(
                id: id,
                channelID: channelID,
                name: name,
                currencyCode: currencyCode,
                imagePath: imagePath,
                defaultUnitLabel: defaultUnitLabel,
                createdAt: now
            ),
            now: now,
            context: context
        )
    }

    static func saveAsset(
        ownerUserID: UUID,
        draft: InvestmentAssetDraft,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentAsset {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = MistiaCurrencyLogic.normalizedCode(draft.currencyCode)
        let normalizedDefaultUnit = InvestmentUnitLabel.normalizedDisplay(draft.defaultUnitLabel)
        let channelID = draft.channelID
        guard !trimmedName.isEmpty, normalizedCurrency.count == 3 else {
            throw InvestmentPersistenceError.invalidAssetInput
        }

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

        let draftID = draft.id
        let existingAsset = try context.fetch(
            FetchDescriptor<InvestmentAsset>(
                predicate: #Predicate<InvestmentAsset> { asset in asset.id == draftID }
            )
        ).first
        if let existingAsset {
            guard existingAsset.ownerUserID == ownerUserID,
                  existingAsset.deletedAt == nil else {
                throw InvestmentPersistenceError.invalidAssetInput
            }
            let hasHistory = try context.fetch(FetchDescriptor<InvestmentTrade>())
                .contains { $0.assetID == draftID }
            if hasHistory,
               (existingAsset.channelID != draft.channelID
                    || MistiaCurrencyLogic.normalizedCode(existingAsset.currencyCode) != normalizedCurrency) {
                throw InvestmentPersistenceError.assetHistoryLocksAccounting
            }

            existingAsset.channelID = draft.channelID
            existingAsset.name = trimmedName
            existingAsset.currencyCode = normalizedCurrency
            existingAsset.imagePath = draft.imagePath
            let resolvesLegacyUnits = existingAsset.defaultUnitLabel == nil
                && normalizedDefaultUnit != nil
            existingAsset.defaultUnitLabel = normalizedDefaultUnit
            existingAsset.updatedAt = now
            if resolvesLegacyUnits, let normalizedDefaultUnit {
                let assetTrades = try context.fetch(FetchDescriptor<InvestmentTrade>())
                    .filter { $0.assetID == existingAsset.id && $0.unitLabel == nil }
                for trade in assetTrades {
                    trade.unitLabel = normalizedDefaultUnit
                }
                if !assetTrades.isEmpty {
                    try rebuildDerivedAccounting(
                        assets: [
                            RebuildAsset(
                                id: existingAsset.id,
                                ownerUserID: existingAsset.ownerUserID,
                                name: existingAsset.name
                            )
                        ],
                        now: now,
                        scrubLegacyConflicts: false,
                        context: context
                    )
                    return existingAsset
                }
            }
            try context.save()
            return existingAsset
        }

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
            id: draft.id,
            ownerUserID: ownerUserID,
            channelID: draft.channelID,
            name: trimmedName,
            currencyCode: normalizedCurrency,
            imagePath: draft.imagePath,
            defaultUnitLabel: normalizedDefaultUnit,
            sortOrder: assets.count,
            createdAt: draft.createdAt,
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
            ownerUserID: ownerUserID,
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
            unitLabel: draft.unitLabel,
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

    static func deleteAsset(
        ownerUserID: UUID,
        assetID: UUID,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentAsset {
        guard let asset = try fetchAsset(
            id: assetID,
            ownerUserID: ownerUserID,
            context: context
        ), asset.deletedAt == nil else {
            throw InvestmentPersistenceError.missingAsset
        }

        let assetTrades = try activeTrades(
            assetID: assetID,
            ownerUserID: ownerUserID,
            context: context
        )
        let unitPositions = try InvestmentAccountingEngine.unitPositions(
            trades: assetTrades.map(InvestmentTradeInput.init)
        )
        guard unitPositions.allSatisfy({ $0.quantity <= 0 }) else {
            throw InvestmentPersistenceError.assetHasRemainingInventory
        }

        asset.deletedAt = now
        asset.updatedAt = now
        try context.save()
        return asset
    }

    @discardableResult
    static func reconcileTrades(
        assetIDs: Set<UUID>,
        ownerUserID: UUID? = nil,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        guard !assetIDs.isEmpty else {
            return InvestmentPersistenceResult()
        }

        let trades = try context.fetch(FetchDescriptor<InvestmentTrade>())
            .filter { trade in
                trade.deletedAt == nil
                    && assetIDs.contains(trade.assetID)
                    && (ownerUserID == nil || trade.ownerUserID == ownerUserID)
            }
        return try reconcile(
            trades: trades,
            signpostName: "Investment Targeted Reconciliation",
            now: now,
            context: context
        )
    }

    @discardableResult
    static func reconcileAllTrades(
        ownerUserID: UUID? = nil,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let trades = try context.fetch(FetchDescriptor<InvestmentTrade>())
            .filter { trade in
                trade.deletedAt == nil && (ownerUserID == nil || trade.ownerUserID == ownerUserID)
            }
        return try reconcile(
            trades: trades,
            signpostName: "Investment Full Reconciliation",
            now: now,
            context: context
        )
    }

    private static func reconcile(
        trades: [InvestmentTrade],
        signpostName: StaticString,
        now: Date,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let requestedAssetIDs = Set(trades.map(\.assetID))
        let signpostID = InvestmentReconciliationSignpost.begin(
            signpostName,
            assetCount: requestedAssetIDs.count,
            tradeCount: trades.count
        )
        defer {
            InvestmentReconciliationSignpost.end(signpostName, id: signpostID)
        }
        guard !trades.isEmpty else {
            return InvestmentPersistenceResult()
        }

        let assets = try context.fetch(FetchDescriptor<InvestmentAsset>())
            .filter { $0.deletedAt == nil && requestedAssetIDs.contains($0.id) }
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let allWallets = try context.fetch(FetchDescriptor<LedgerWallet>())
            .filter { $0.deletedAt == nil }
        var walletsByID = Dictionary(uniqueKeysWithValues: allWallets.map { ($0.id, $0) })
        var systemWalletByOwnerID: [UUID: LedgerWallet] = [:]

        let tradesByAsset = Dictionary(grouping: trades, by: \.assetID)
        var result = InvestmentPersistenceResult()

        for (assetID, trades) in tradesByAsset {
            guard let asset = assetsByID[assetID] else { continue }
            let ownerID = asset.ownerUserID
            let systemWallet: LedgerWallet
            if let cached = systemWalletByOwnerID[ownerID] {
                systemWallet = cached
            } else {
                systemWallet = try ensureSystemWallet(
                    ownerUserID: ownerID,
                    currencyCode: asset.currencyCode,
                    now: now,
                    context: context
                )
                systemWalletByOwnerID[ownerID] = systemWallet
                walletsByID[systemWallet.id] = systemWallet
            }
            let sortedTrades = trades.sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return $0.createdAt < $1.createdAt
            }
            let calculations = try InvestmentAccountingEngine.calculationMap(
                trades: sortedTrades.map(InvestmentTradeInput.init)
            )

            for trade in sortedTrades {
                if let calculation = calculations[trade.id],
                   applyCalculationIfNeeded(calculation, to: trade) {
                    result.tradeIDs.insert(trade.id)
                }

                try reconcileLedgerLegs(
                    ownerUserID: trade.ownerUserID,
                    trade: trade,
                    assetName: asset.name,
                    systemWallet: systemWallet,
                    walletsByID: walletsByID,
                    now: now,
                    context: context,
                    result: &result,
                    writePolicy: .ifChanged
                )
            }
        }

        if context.hasChanges {
            try context.save()
        }
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
        for transactionID in [
            trade.fundingLedgerTransactionID,
            trade.capitalReturnLedgerTransactionID,
            trade.profitLossLedgerTransactionID
        ].compactMap({ $0 }) {
            let cleared = try clearFundUsage(
                ownerUserID: ownerUserID,
                transactionID: transactionID,
                now: now,
                context: context
            )
            result.walletIDs.formUnion(cleared.walletIDs)
            result.postingIDs.formUnion(cleared.postingIDs)
            result.ledgerTransactionIDs.formUnion(cleared.ledgerTransactionIDs)
        }
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

    static func reconcileCash(
        ownerUserID: UUID,
        requests: [InvestmentReconciliationRequest],
        occurredAt: Date = .now,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentReconciliationResult {
        guard let configuration = try configuration(
            ownerUserID: ownerUserID,
            createIfMissing: false,
            context: context
        ), let linkedWalletID = configuration.linkedWalletID else {
            throw InvestmentPersistenceError.missingWallet
        }
        let systemWalletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        let wallets = try context.fetch(FetchDescriptor<LedgerWallet>())
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        guard let systemWallet = walletsByID[systemWalletID],
              let linkedWallet = walletsByID[linkedWalletID] else {
            throw InvestmentPersistenceError.missingWallet
        }
        try validateWalletOwnership(
            ownerUserID: ownerUserID,
            walletIDs: Set(requests.map(\.walletID) + [linkedWalletID]).map { $0 },
            context: context
        )

        var snapshot = try cashAllocationSnapshot(
            ownerUserID: ownerUserID,
            accountingCurrencyCode: systemWallet.currencyCode,
            context: context
        )
        var result = InvestmentPersistenceResult(walletIDs: [systemWalletID, linkedWalletID])
        var instructions: [InvestmentReconciliationInstruction] = []

        for request in requests where request.accountingAmountMinor > 0 {
            guard request.walletID != linkedWalletID,
                  let holderWallet = walletsByID[request.walletID],
                  let location = snapshot.locations.first(where: { $0.walletID == request.walletID }),
                  location.bookedMinor > 0 else {
                throw InvestmentPersistenceError.invalidTradeInput
            }
            let holderBalance = try currentBalance(wallet: holderWallet, context: context)
            guard holderBalance >= request.accountingAmountMinor else {
                throw InvestmentPersistenceError.insufficientFunds
            }
            let profitAmountMinor = min(request.accountingAmountMinor, location.bookedMinor)
            let eventID = UUID()
            let ledgerID = InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "cash-reconciliation")
            let transaction = try upsertLedgerTransaction(
                id: ledgerID,
                primaryKind: .transfer,
                role: .investmentReconciliation,
                title: L10n.investment.cash.reconciliationTitle,
                amountMinor: request.accountingAmountMinor,
                sourceWallet: holderWallet,
                destinationWallet: linkedWallet,
                destinationAmountMinor: request.accountingAmountMinor,
                reportingAmountMinor: request.accountingAmountMinor,
                reportingCurrencyCode: systemWallet.currencyCode,
                occurredAt: occurredAt,
                now: now,
                context: context
            )
            try recordTransactionOwnership(transaction, ownerUserID: ownerUserID, now: now, context: context)

            let holderAccountingDelta = -profitAmountMinor
            let holderLocalDelta = try proportionalLocalCashDelta(
                accountingDeltaMinor: holderAccountingDelta,
                location: location,
                bucket: .booked,
                ownerUserID: ownerUserID,
                context: context
            )
            let holderPosting = try upsertCashPosting(
                id: InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "holder-cash-posting"),
                ownerUserID: ownerUserID,
                eventID: eventID,
                walletID: holderWallet.id,
                ledgerTransactionID: ledgerID,
                role: .cashReconciliation,
                bucket: .booked,
                origin: .manual,
                amountMinor: holderLocalDelta,
                currencyCode: holderWallet.currencyCode,
                accountingAmountMinor: holderAccountingDelta,
                accountingCurrencyCode: systemWallet.currencyCode,
                occurredAt: occurredAt,
                now: now,
                context: context
            )
            let linkedAccountingDelta = profitAmountMinor
            let linkedPosting = try upsertCashPosting(
                id: InvestmentLedgerIdentity.derivedID(eventID: eventID, component: "linked-cash-posting"),
                ownerUserID: ownerUserID,
                eventID: eventID,
                walletID: linkedWallet.id,
                ledgerTransactionID: ledgerID,
                role: .cashReconciliation,
                bucket: .booked,
                origin: .manual,
                amountMinor: linkedAccountingDelta,
                currencyCode: linkedWallet.currencyCode,
                accountingAmountMinor: linkedAccountingDelta,
                accountingCurrencyCode: systemWallet.currencyCode,
                occurredAt: occurredAt,
                now: now,
                context: context
            )
            result.walletIDs.insert(holderWallet.id)
            result.postingIDs.formUnion([holderPosting.id, linkedPosting.id])
            result.ledgerTransactionIDs.insert(transaction.id)
            instructions.append(
                InvestmentReconciliationInstruction(
                    id: eventID,
                    sourceWalletID: holderWallet.id,
                    destinationWalletID: linkedWallet.id,
                    accountingAmountMinor: request.accountingAmountMinor
                )
            )

            snapshot = try cashAllocationSnapshot(
                ownerUserID: ownerUserID,
                accountingCurrencyCode: systemWallet.currencyCode,
                context: context
            )
        }
        try context.save()
        return InvestmentReconciliationResult(instructions: instructions, persistence: result)
    }

    static func fundUsagePreview(
        ownerUserID: UUID,
        wallet: LedgerWallet,
        requestedMinor: Int64,
        visibleWalletBalanceMinor: Int64,
        context: ModelContext
    ) throws -> InvestmentFundUsagePreview {
        let systemWalletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        guard let systemWallet = try context.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in wallet.id == systemWalletID }
            )
        ).first else {
            return InvestmentCashAllocationLogic.usagePreview(
                requestedMinor: requestedMinor,
                visibleWalletBalanceMinor: visibleWalletBalanceMinor,
                bookedInvestmentMinor: 0,
                unreconciledInvestmentMinor: 0,
                totalInvestmentMinor: 0
            )
        }
        let snapshot = try cashAllocationSnapshot(
            ownerUserID: ownerUserID,
            accountingCurrencyCode: systemWallet.currencyCode,
            context: context
        )
        let location = snapshot.locations.first { $0.walletID == wallet.id }
        return InvestmentCashAllocationLogic.usagePreview(
            requestedMinor: requestedMinor,
            visibleWalletBalanceMinor: visibleWalletBalanceMinor,
            bookedInvestmentMinor: location?.bookedMinor ?? 0,
            unreconciledInvestmentMinor: location?.unreconciledMinor ?? 0,
            totalInvestmentMinor: snapshot.totalMinor
        )
    }

    static func recordFundUsage(
        ownerUserID: UUID,
        transaction: LedgerTransaction,
        preview: InvestmentFundUsagePreview,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        guard preview.investmentToUseMinor > 0,
              let sourceWallet = transaction.sourceWallet else {
            return InvestmentPersistenceResult()
        }
        let systemWalletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        guard let systemWallet = try context.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in wallet.id == systemWalletID }
            )
        ).first else {
            throw InvestmentPersistenceError.missingWallet
        }
        var result = InvestmentPersistenceResult(walletIDs: [sourceWallet.id])
        let candidateDestinationWallet = transaction.primaryKind == .transfer
            && transaction.transferSubtype == .internalTransfer
            && transaction.destinationWallet?.kind != .creditCard
            ? transaction.destinationWallet
            : nil
        let ownershipScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let destinationWallet = candidateDestinationWallet.flatMap { wallet in
            TransactionAuditStore.resolveOwnerUserID(
                forWalletID: wallet.id,
                ownershipScopes: ownershipScopes
            ) == ownerUserID ? wallet : nil
        }

        for (bucket, amount, component) in [
            (InvestmentCashBucket.booked, preview.bookedToUseMinor, "booked"),
            (InvestmentCashBucket.unreconciled, preview.unreconciledToUseMinor, "unreconciled")
        ] where amount > 0 {
            let posting = try upsertCashPosting(
                id: InvestmentLedgerIdentity.derivedID(eventID: transaction.id, component: "cash-consumption-\(component)"),
                ownerUserID: ownerUserID,
                eventID: transaction.id,
                walletID: sourceWallet.id,
                ledgerTransactionID: transaction.id,
                role: destinationWallet == nil ? .cashConsumption : .cashTransfer,
                bucket: bucket,
                origin: .derived,
                amountMinor: -amount,
                currencyCode: sourceWallet.currencyCode,
                accountingAmountMinor: -amount,
                accountingCurrencyCode: systemWallet.currencyCode,
                occurredAt: transaction.occurredAt,
                now: now,
                context: context
            )
            result.postingIDs.insert(posting.id)

            if let destinationWallet {
                let destinationPosting = try upsertCashPosting(
                    id: InvestmentLedgerIdentity.derivedID(eventID: transaction.id, component: "cash-destination-\(component)"),
                    ownerUserID: ownerUserID,
                    eventID: transaction.id,
                    walletID: destinationWallet.id,
                    ledgerTransactionID: transaction.id,
                    role: .cashTransfer,
                    bucket: .booked,
                    origin: .derived,
                    amountMinor: amount,
                    currencyCode: destinationWallet.currencyCode,
                    accountingAmountMinor: amount,
                    accountingCurrencyCode: systemWallet.currencyCode,
                    occurredAt: transaction.occurredAt,
                    now: now,
                    context: context
                )
                result.walletIDs.insert(destinationWallet.id)
                result.postingIDs.insert(destinationPosting.id)
            }

            if bucket == .unreconciled {
                let adjustmentID = InvestmentLedgerIdentity.derivedID(eventID: transaction.id, component: "cash-unreconciled-adjustment")
                let adjustment = try upsertLedgerTransaction(
                    id: adjustmentID,
                    primaryKind: .transfer,
                    role: .investmentReserveUse,
                    title: L10n.investment.cash.automaticReconciliationTitle,
                    amountMinor: amount,
                    sourceWallet: systemWallet,
                    destinationWallet: sourceWallet,
                    destinationAmountMinor: amount,
                    reportingAmountMinor: amount,
                    reportingCurrencyCode: systemWallet.currencyCode,
                    occurredAt: transaction.occurredAt,
                    now: now,
                    context: context
                )
                try recordTransactionOwnership(adjustment, ownerUserID: ownerUserID, now: now, context: context)
                result.walletIDs.insert(systemWallet.id)
                result.ledgerTransactionIDs.insert(adjustment.id)
            }
        }
        return result
    }

    static func clearFundUsage(
        ownerUserID: UUID,
        transactionID: UUID,
        now: Date = .now,
        context: ModelContext
    ) throws -> InvestmentPersistenceResult {
        let postings = try context.fetch(
            FetchDescriptor<InvestmentWalletPosting>(
                predicate: #Predicate<InvestmentWalletPosting> { posting in
                    posting.ownerUserID == ownerUserID
                        && posting.eventID == transactionID
                        && posting.deletedAt == nil
                }
            )
        )
        var result = InvestmentPersistenceResult()
        for posting in postings where posting.role == .cashConsumption || posting.role == .cashTransfer {
            posting.deletedAt = now
            posting.updatedAt = now
            result.postingIDs.insert(posting.id)
            result.walletIDs.insert(posting.walletID)
        }
        let adjustmentID = InvestmentLedgerIdentity.derivedID(
            eventID: transactionID,
            component: "cash-unreconciled-adjustment"
        )
        if let adjustment = try context.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate<LedgerTransaction> { transaction in transaction.id == adjustmentID }
            )
        ).first, adjustment.deletedAt == nil {
            adjustment.markDeleted(at: now)
            result.ledgerTransactionIDs.insert(adjustment.id)
        }
        return result
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
            if draft.grossAmountMinor == 0 {
                guard draft.accountingGrossAmountMinor == 0,
                      draft.fundingWalletID == nil,
                      draft.capitalReturnWalletID == nil else {
                    throw InvestmentPersistenceError.invalidWallet
                }
                return
            }
            guard let walletID = draft.fundingWalletID,
                  let wallet = walletsByID[walletID],
                  !wallet.isArchived,
                  wallet.deletedAt == nil else {
                throw InvestmentPersistenceError.missingWallet
            }
        case .sell:
            if draft.grossAmountMinor == 0 {
                guard draft.accountingGrossAmountMinor == 0,
                      draft.fundingWalletID == nil,
                      draft.capitalReturnWalletID == nil else {
                    throw InvestmentPersistenceError.invalidWallet
                }
                return
            }
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
        let hasValidGross = (draft.grossAmountMinor == 0 && draft.accountingGrossAmountMinor == 0)
            || (draft.grossAmountMinor > 0 && draft.accountingGrossAmountMinor > 0)
        guard draft.quantity > 0,
              hasValidGross,
              sourceCurrency == MistiaCurrencyLogic.normalizedCode(asset.currencyCode) else {
            throw InvestmentPersistenceError.invalidTradeInput
        }

        if draft.grossAmountMinor == 0 {
            guard draft.accountingGrossAmountMinor == 0 else {
                throw InvestmentPersistenceError.invalidTradeInput
            }
            return
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
        ownerUserID: UUID,
        draft: InvestmentTradeDraft,
        fundingWallet: LedgerWallet?,
        fundingAmountMinor: Int64?,
        excludingTrade: InvestmentTrade?,
        allWallets: [LedgerWallet],
        context: ModelContext
    ) throws {
        guard draft.kind == .buy else { return }
        if draft.grossAmountMinor == 0 && draft.accountingGrossAmountMinor == 0 {
            return
        }
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
            let preview = try fundUsagePreview(
                ownerUserID: ownerUserID,
                wallet: fundingWallet,
                requestedMinor: fundingAmountMinor,
                visibleWalletBalanceMinor: balance,
                context: context
            )
            guard preview.outcome != .insufficientFunds else {
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
        trade.unitLabel = InvestmentUnitLabel.normalizedDisplay(draft.unitLabel)
        trade.grossAmountMinor = draft.grossAmountMinor
        trade.currencyCode = MistiaCurrencyLogic.normalizedCode(draft.currencyCode)
        trade.accountingGrossAmountMinor = draft.accountingGrossAmountMinor
        trade.accountingCurrencyCode = MistiaCurrencyLogic.normalizedCode(draft.accountingCurrencyCode)
        trade.exchangeRateDecimalString = draft.exchangeRateDecimalString
        trade.exchangeRateProvider = draft.exchangeRateProvider
        trade.exchangeRateDate = draft.exchangeRateDate
        trade.fundingWalletID = (draft.kind == .buy && draft.grossAmountMinor > 0) ? draft.fundingWalletID : nil
        trade.capitalReturnWalletID = (draft.kind == .sell && draft.grossAmountMinor > 0) ? draft.capitalReturnWalletID : nil
        trade.fundingWalletCurrencyCode = (draft.kind == .buy && draft.grossAmountMinor > 0) ? fundingWallet?.currencyCode : nil
        trade.capitalReturnWalletCurrencyCode = (draft.kind == .sell && draft.grossAmountMinor > 0) ? capitalWallet?.currencyCode : nil
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
        result: inout InvestmentPersistenceResult,
        writePolicy: InvestmentDerivedWritePolicy = .always
    ) throws {
        switch trade.kind {
        case .buy:
            if trade.grossAmountMinor == 0 {
                var tradeDidMutate = false
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.fundingWalletID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<String>.none,
                    to: \.fundingWalletCurrencyCode,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<Int64>.none,
                    to: \.fundingWalletAmountMinor,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.fundingLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.capitalReturnLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.profitLossLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                if tradeDidMutate {
                    result.tradeIDs.insert(trade.id)
                }
                try deleteUnexpectedLedgerLegs(
                    for: trade,
                    keeping: [],
                    now: now,
                    context: context,
                    result: &result
                )
                try deleteUnexpectedPostings(
                    for: trade,
                    keeping: [],
                    now: now,
                    context: context,
                    result: &result
                )
                break
            }
            guard let walletID = trade.fundingWalletID,
                  let wallet = walletsByID[walletID],
                  let walletAmount = trade.fundingWalletAmountMinor else {
                throw InvestmentPersistenceError.missingWallet
            }
            let ledgerID = InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "funding")
            let transactionOutcome = try upsertLedgerTransactionOutcome(
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
                context: context,
                writePolicy: writePolicy
            )
            let transaction = transactionOutcome.model
            var tradeDidMutate = false
            tradeDidMutate = assignDerivedValue(
                Optional(transaction.id),
                to: \.fundingLedgerTransactionID,
                on: trade,
                writePolicy: writePolicy
            ) || tradeDidMutate
            tradeDidMutate = assignDerivedValue(
                Optional<UUID>.none,
                to: \.capitalReturnLedgerTransactionID,
                on: trade,
                writePolicy: writePolicy
            ) || tradeDidMutate
            tradeDidMutate = assignDerivedValue(
                Optional<UUID>.none,
                to: \.profitLossLedgerTransactionID,
                on: trade,
                writePolicy: writePolicy
            ) || tradeDidMutate
            if tradeDidMutate {
                result.tradeIDs.insert(trade.id)
            }
            try deleteUnexpectedLedgerLegs(for: trade, keeping: [transaction.id], now: now, context: context, result: &result)
            let postingOutcome = try upsertPostingOutcome(
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
                context: context,
                writePolicy: writePolicy
            )
            let posting = postingOutcome.model
            try deleteUnexpectedPostings(for: trade, keeping: [posting.id], now: now, context: context, result: &result)
            let metadataDidMutate = try recordTransactionOwnershipIfNeeded(
                transaction,
                ownerUserID: ownerUserID,
                transactionDidMutate: transactionOutcome.didMutate,
                now: now,
                context: context,
                writePolicy: writePolicy
            )
            if transactionOutcome.didMutate || metadataDidMutate {
                result.ledgerTransactionIDs.insert(transaction.id)
                result.walletIDs.insert(wallet.id)
            }
            if postingOutcome.didMutate {
                result.postingIDs.insert(posting.id)
                result.walletIDs.insert(wallet.id)
            }

        case .sell:
            var keepingLedgerIDs: Set<UUID> = []
            var keepingPostingIDs: Set<UUID> = []
            if trade.grossAmountMinor > 0 {
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
                if assignDerivedValue(
                    Optional(capitalAmount),
                    to: \.capitalReturnWalletAmountMinor,
                    on: trade,
                    writePolicy: writePolicy
                ) {
                    result.tradeIDs.insert(trade.id)
                }

                let capitalLedgerID = InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "capital-return")
                let capitalTransactionOutcome = try upsertLedgerTransactionOutcome(
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
                    context: context,
                    writePolicy: writePolicy
                )
                let capitalTransaction = capitalTransactionOutcome.model
                var tradeDidMutate = false
                tradeDidMutate = assignDerivedValue(
                    Optional(capitalTransaction.id),
                    to: \.capitalReturnLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.fundingLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                if tradeDidMutate {
                    result.tradeIDs.insert(trade.id)
                }

                keepingLedgerIDs.insert(capitalTransaction.id)
                let capitalPostingOutcome = try upsertPostingOutcome(
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
                    context: context,
                    writePolicy: writePolicy
                )
                let capitalPosting = capitalPostingOutcome.model
                keepingPostingIDs.insert(capitalPosting.id)
                let metadataDidMutate = try recordTransactionOwnershipIfNeeded(
                    capitalTransaction,
                    ownerUserID: ownerUserID,
                    transactionDidMutate: capitalTransactionOutcome.didMutate,
                    now: now,
                    context: context,
                    writePolicy: writePolicy
                )
                if capitalTransactionOutcome.didMutate || metadataDidMutate {
                    result.ledgerTransactionIDs.insert(capitalTransaction.id)
                    result.walletIDs.insert(capitalWallet.id)
                }
                if capitalPostingOutcome.didMutate {
                    result.postingIDs.insert(capitalPosting.id)
                    result.walletIDs.insert(capitalWallet.id)
                }
            } else {
                var tradeDidMutate = false
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.capitalReturnWalletID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<String>.none,
                    to: \.capitalReturnWalletCurrencyCode,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.capitalReturnLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<Int64>.none,
                    to: \.capitalReturnWalletAmountMinor,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                tradeDidMutate = assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.fundingLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) || tradeDidMutate
                if tradeDidMutate {
                    result.tradeIDs.insert(trade.id)
                }
            }

            if trade.realizedProfitLossMinor != 0 {
                let cashWallet = trade.capitalReturnWalletID.flatMap { walletsByID[$0] }
                let profitWallet = cashWallet ?? systemWallet
                let cashAmount: Int64
                if let cashWallet, trade.grossAmountMinor > 0 {
                    let localGrossAmount = try convertedWithStoredRate(
                        trade.accountingGrossAmountMinor,
                        sourceCurrencyCode: trade.accountingCurrencyCode,
                        destinationCurrencyCode: cashWallet.currencyCode,
                        rateDecimalString: trade.accountingToCapitalReturnRateDecimalString
                    )
                    cashAmount = localGrossAmount - (trade.capitalReturnWalletAmountMinor ?? 0)
                } else {
                    cashAmount = trade.realizedProfitLossMinor
                }
                let profitLedgerID = InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "profit-loss")
                let profitTransactionOutcome = try upsertLedgerTransactionOutcome(
                    id: profitLedgerID,
                    primaryKind: trade.realizedProfitLossMinor > 0 ? .income : .expense,
                    role: .investmentRealizedProfit,
                    title: assetName,
                    amountMinor: absWithoutOverflow(cashAmount),
                    sourceWallet: profitWallet,
                    destinationWallet: nil,
                    destinationAmountMinor: nil,
                    reportingAmountMinor: absWithoutOverflow(trade.realizedProfitLossMinor),
                    reportingCurrencyCode: systemWallet.currencyCode,
                    occurredAt: trade.occurredAt,
                    now: now,
                    context: context,
                    writePolicy: writePolicy
                )
                let profitTransaction = profitTransactionOutcome.model
                if assignDerivedValue(
                    Optional(profitTransaction.id),
                    to: \.profitLossLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) {
                    result.tradeIDs.insert(trade.id)
                }
                keepingLedgerIDs.insert(profitTransaction.id)
                let profitPostingOutcome = try upsertPostingOutcome(
                    id: InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "profit-loss-posting"),
                    ownerUserID: ownerUserID,
                    trade: trade,
                    walletID: profitWallet.id,
                    ledgerTransactionID: profitTransaction.id,
                    role: .realizedProfit,
                    amountMinor: cashAmount,
                    currencyCode: profitWallet.currencyCode,
                    accountingAmountMinor: trade.realizedProfitLossMinor,
                    now: now,
                    context: context,
                    writePolicy: writePolicy
                )
                let profitPosting = profitPostingOutcome.model
                keepingPostingIDs.insert(profitPosting.id)
                let metadataDidMutate = try recordTransactionOwnershipIfNeeded(
                    profitTransaction,
                    ownerUserID: ownerUserID,
                    transactionDidMutate: profitTransactionOutcome.didMutate,
                    now: now,
                    context: context,
                    writePolicy: writePolicy
                )
                if profitTransactionOutcome.didMutate || metadataDidMutate {
                    result.ledgerTransactionIDs.insert(profitTransaction.id)
                    result.walletIDs.insert(profitWallet.id)
                }
                if profitPostingOutcome.didMutate {
                    result.postingIDs.insert(profitPosting.id)
                    result.walletIDs.insert(profitWallet.id)
                }

                if let cashWallet {
                    let cashPostingOutcome = try upsertCashPostingOutcome(
                        id: InvestmentLedgerIdentity.derivedID(eventID: trade.id, component: "cash-accrual-posting"),
                        ownerUserID: ownerUserID,
                        eventID: trade.id,
                        tradeID: trade.id,
                        assetID: trade.assetID,
                        walletID: cashWallet.id,
                        ledgerTransactionID: profitTransaction.id,
                        role: .cashAccrual,
                        bucket: .booked,
                        origin: .derived,
                        amountMinor: cashAmount,
                        currencyCode: cashWallet.currencyCode,
                        accountingAmountMinor: trade.realizedProfitLossMinor,
                        accountingCurrencyCode: trade.accountingCurrencyCode,
                        occurredAt: trade.occurredAt,
                        now: now,
                        context: context,
                        writePolicy: writePolicy
                    )
                    let cashPosting = cashPostingOutcome.model
                    keepingPostingIDs.insert(cashPosting.id)
                    if cashPostingOutcome.didMutate {
                        result.postingIDs.insert(cashPosting.id)
                        result.walletIDs.insert(cashWallet.id)
                    }
                }
            } else {
                if assignDerivedValue(
                    Optional<UUID>.none,
                    to: \.profitLossLedgerTransactionID,
                    on: trade,
                    writePolicy: writePolicy
                ) {
                    result.tradeIDs.insert(trade.id)
                }
            }

            try deleteUnexpectedLedgerLegs(for: trade, keeping: keepingLedgerIDs, now: now, context: context, result: &result)
            try deleteUnexpectedPostings(for: trade, keeping: keepingPostingIDs, now: now, context: context, result: &result)
        }
    }

    private static func ledgerTransactionMatches(
        _ transaction: LedgerTransaction,
        primaryKind: TransactionPrimaryKind,
        role: InvestmentLedgerLegRole,
        title: String,
        amountMinor: Int64,
        sourceWallet: LedgerWallet,
        destinationWallet: LedgerWallet?,
        destinationAmountMinor: Int64?,
        reportingAmountMinor: Int64,
        reportingCurrencyCode: String,
        occurredAt: Date
    ) -> Bool {
        transaction.primaryKindRawValue == primaryKind.rawValue
            && transaction.transferSubtypeRawValue
                == (primaryKind == .transfer ? TransactionTransferSubtype.internalTransfer.rawValue : nil)
            && transaction.debtIntentRawValue == nil
            && transaction.entryStatusRawValue == TransactionEntryStatus.posted.rawValue
            && transaction.title == title
            && transaction.note == nil
            && transaction.amountMinor == max(amountMinor, 0)
            && transaction.reportingExpenseMinor == 0
            && transaction.reportingIncomeMinor == 0
            && transaction.sourceCurrencyCode == sourceWallet.currencyCode
            && transaction.destinationCurrencyCode == destinationWallet?.currencyCode
            && transaction.destinationAmountMinor == destinationAmountMinor
            && transaction.reportingCurrencyCode == reportingCurrencyCode
            && transaction.reportingAmountMinor == reportingAmountMinor
            && transaction.category == nil
            && transaction.sourceWallet?.id == sourceWallet.id
            && transaction.destinationWallet?.id == destinationWallet?.id
            && transaction.settlementGroupID == nil
            && transaction.settlementObligationID == nil
            && transaction.settlementRoleRawValue == role.rawValue
            && transaction.occurredAt == occurredAt
            && transaction.deletedAt == nil
            && !transaction.isArchived
            && transaction.archivedAt == nil
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
        try upsertLedgerTransactionOutcome(
            id: id,
            primaryKind: primaryKind,
            role: role,
            title: title,
            amountMinor: amountMinor,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            destinationAmountMinor: destinationAmountMinor,
            reportingAmountMinor: reportingAmountMinor,
            reportingCurrencyCode: reportingCurrencyCode,
            occurredAt: occurredAt,
            now: now,
            context: context,
            writePolicy: .always
        ).model
    }

    private static func upsertLedgerTransactionOutcome(
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
        context: ModelContext,
        writePolicy: InvestmentDerivedWritePolicy
    ) throws -> InvestmentUpsertOutcome<LedgerTransaction> {
        let descriptor = FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate<LedgerTransaction> { transaction in
                transaction.id == id
            }
        )
        let existing = try context.fetch(descriptor).first
        if let existing,
           writePolicy == .ifChanged,
           ledgerTransactionMatches(
               existing,
               primaryKind: primaryKind,
               role: role,
               title: title,
               amountMinor: amountMinor,
               sourceWallet: sourceWallet,
               destinationWallet: destinationWallet,
               destinationAmountMinor: destinationAmountMinor,
               reportingAmountMinor: reportingAmountMinor,
               reportingCurrencyCode: reportingCurrencyCode,
               occurredAt: occurredAt
           ) {
            return InvestmentUpsertOutcome(model: existing, didMutate: false)
        }
        let transaction = existing ?? LedgerTransaction(
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
        return InvestmentUpsertOutcome(model: transaction, didMutate: true)
    }

    private static func postingMatches(
        _ posting: InvestmentWalletPosting,
        ownerUserID: UUID,
        eventID: UUID,
        tradeID: UUID?,
        assetID: UUID?,
        walletID: UUID,
        ledgerTransactionID: UUID,
        role: InvestmentPostingRole,
        amountMinor: Int64,
        currencyCode: String,
        accountingAmountMinor: Int64,
        accountingCurrencyCode: String,
        occurredAt: Date
    ) -> Bool {
        posting.ownerUserID == ownerUserID
            && posting.eventID == eventID
            && posting.tradeID == tradeID
            && posting.assetID == assetID
            && posting.walletID == walletID
            && posting.ledgerTransactionID == ledgerTransactionID
            && posting.role == role
            && posting.amountMinor == amountMinor
            && posting.currencyCode == currencyCode
            && posting.accountingAmountMinor == accountingAmountMinor
            && posting.accountingCurrencyCode == accountingCurrencyCode
            && posting.occurredAt == occurredAt
            && posting.deletedAt == nil
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
        try upsertPostingOutcome(
            id: id,
            ownerUserID: ownerUserID,
            trade: trade,
            walletID: walletID,
            ledgerTransactionID: ledgerTransactionID,
            role: role,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            accountingAmountMinor: accountingAmountMinor,
            now: now,
            context: context,
            writePolicy: .always
        ).model
    }

    private static func upsertPostingOutcome(
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
        context: ModelContext,
        writePolicy: InvestmentDerivedWritePolicy
    ) throws -> InvestmentUpsertOutcome<InvestmentWalletPosting> {
        let descriptor = FetchDescriptor<InvestmentWalletPosting>(
            predicate: #Predicate<InvestmentWalletPosting> { posting in
                posting.id == id
            }
        )
        let existing = try context.fetch(descriptor).first
        if let existing,
           writePolicy == .ifChanged,
           postingMatches(
               existing,
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
               occurredAt: trade.occurredAt
           ) {
            return InvestmentUpsertOutcome(model: existing, didMutate: false)
        }
        let posting = existing ?? InvestmentWalletPosting(
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
        return InvestmentUpsertOutcome(model: posting, didMutate: true)
    }

    private static func cashMetadataMatches(
        _ metadata: InvestmentCashPostingMetadata,
        ownerUserID: UUID,
        bucket: InvestmentCashBucket,
        origin: InvestmentCashPostingOrigin
    ) -> Bool {
        metadata.ownerUserID == ownerUserID
            && metadata.cashBucket == bucket
            && metadata.cashOrigin == origin
    }

    private static func upsertCashPosting(
        id: UUID,
        ownerUserID: UUID,
        eventID: UUID,
        tradeID: UUID? = nil,
        assetID: UUID? = nil,
        walletID: UUID,
        ledgerTransactionID: UUID,
        role: InvestmentPostingRole,
        bucket: InvestmentCashBucket,
        origin: InvestmentCashPostingOrigin,
        amountMinor: Int64,
        currencyCode: String,
        accountingAmountMinor: Int64,
        accountingCurrencyCode: String,
        occurredAt: Date,
        now: Date,
        context: ModelContext
    ) throws -> InvestmentWalletPosting {
        try upsertCashPostingOutcome(
            id: id,
            ownerUserID: ownerUserID,
            eventID: eventID,
            tradeID: tradeID,
            assetID: assetID,
            walletID: walletID,
            ledgerTransactionID: ledgerTransactionID,
            role: role,
            bucket: bucket,
            origin: origin,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            accountingAmountMinor: accountingAmountMinor,
            accountingCurrencyCode: accountingCurrencyCode,
            occurredAt: occurredAt,
            now: now,
            context: context,
            writePolicy: .always
        ).model
    }

    private static func upsertCashPostingOutcome(
        id: UUID,
        ownerUserID: UUID,
        eventID: UUID,
        tradeID: UUID?,
        assetID: UUID?,
        walletID: UUID,
        ledgerTransactionID: UUID,
        role: InvestmentPostingRole,
        bucket: InvestmentCashBucket,
        origin: InvestmentCashPostingOrigin,
        amountMinor: Int64,
        currencyCode: String,
        accountingAmountMinor: Int64,
        accountingCurrencyCode: String,
        occurredAt: Date,
        now: Date,
        context: ModelContext,
        writePolicy: InvestmentDerivedWritePolicy
    ) throws -> InvestmentUpsertOutcome<InvestmentWalletPosting> {
        let descriptor = FetchDescriptor<InvestmentWalletPosting>(
            predicate: #Predicate<InvestmentWalletPosting> { posting in posting.id == id }
        )
        let metadataDescriptor = FetchDescriptor<InvestmentCashPostingMetadata>(
            predicate: #Predicate<InvestmentCashPostingMetadata> { metadata in metadata.id == id }
        )
        let existingPosting = try context.fetch(descriptor).first
        let existingMetadata = try context.fetch(metadataDescriptor).first
        if let existingPosting,
           let existingMetadata,
           writePolicy == .ifChanged,
           postingMatches(
               existingPosting,
               ownerUserID: ownerUserID,
               eventID: eventID,
               tradeID: tradeID,
               assetID: assetID,
               walletID: walletID,
               ledgerTransactionID: ledgerTransactionID,
               role: role,
               amountMinor: amountMinor,
               currencyCode: MistiaCurrencyLogic.normalizedCode(currencyCode),
               accountingAmountMinor: accountingAmountMinor,
               accountingCurrencyCode: MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode),
               occurredAt: occurredAt
           ),
           cashMetadataMatches(
               existingMetadata,
               ownerUserID: ownerUserID,
               bucket: bucket,
               origin: origin
           ) {
            return InvestmentUpsertOutcome(model: existingPosting, didMutate: false)
        }
        let posting = existingPosting ?? InvestmentWalletPosting(
            id: id,
            ownerUserID: ownerUserID,
            eventID: eventID,
            tradeID: tradeID,
            assetID: assetID,
            walletID: walletID,
            ledgerTransactionID: ledgerTransactionID,
            role: role,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            accountingAmountMinor: accountingAmountMinor,
            accountingCurrencyCode: accountingCurrencyCode,
            occurredAt: occurredAt,
            createdAt: now,
            updatedAt: now
        )
        if posting.modelContext == nil {
            context.insert(posting)
        }
        posting.ownerUserID = ownerUserID
        posting.eventID = eventID
        posting.tradeID = tradeID
        posting.assetID = assetID
        posting.walletID = walletID
        posting.ledgerTransactionID = ledgerTransactionID
        posting.role = role
        posting.amountMinor = amountMinor
        posting.currencyCode = MistiaCurrencyLogic.normalizedCode(currencyCode)
        posting.accountingAmountMinor = accountingAmountMinor
        posting.accountingCurrencyCode = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        posting.occurredAt = occurredAt
        posting.updatedAt = now
        posting.deletedAt = nil
        let metadata = existingMetadata ?? InvestmentCashPostingMetadata(
            id: id,
            ownerUserID: ownerUserID,
            cashBucket: bucket,
            cashOrigin: origin,
            createdAt: now,
            updatedAt: now
        )
        if metadata.modelContext == nil {
            context.insert(metadata)
        }
        metadata.ownerUserID = ownerUserID
        metadata.cashBucket = bucket
        metadata.cashOrigin = origin
        metadata.updatedAt = now
        return InvestmentUpsertOutcome(model: posting, didMutate: true)
    }

    private static func proportionalLocalCashDelta(
        accountingDeltaMinor: Int64,
        location: InvestmentWalletCashLocation,
        bucket: InvestmentCashBucket,
        ownerUserID: UUID,
        context: ModelContext
    ) throws -> Int64 {
        let locationWalletID = location.walletID
        let postings = try context.fetch(
            FetchDescriptor<InvestmentWalletPosting>(
                predicate: #Predicate<InvestmentWalletPosting> { posting in
                    posting.ownerUserID == ownerUserID
                        && posting.walletID == locationWalletID
                        && posting.deletedAt == nil
                }
            )
        )
        let postingIDs = Set(postings.map(\.id))
        let bucketIDs = Set(
            try context.fetch(FetchDescriptor<InvestmentCashPostingMetadata>())
                .filter { postingIDs.contains($0.id) && $0.cashBucket == bucket }
                .map(\.id)
        )
        let bucketPostings = postings.filter { bucketIDs.contains($0.id) }
        let localOutstanding = bucketPostings.reduce(Int64.zero) { $0 + $1.amountMinor }
        let accountingOutstanding = bucket == .booked ? location.bookedMinor : location.unreconciledMinor
        guard accountingOutstanding != 0 else { return accountingDeltaMinor }
        var value = Decimal(localOutstanding) * Decimal(accountingDeltaMinor)
            / Decimal(accountingOutstanding)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
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

    private static func transactionMetadataNeedsRepair(
        transactionID: UUID,
        ownerUserID: UUID,
        context: ModelContext
    ) throws -> Bool {
        let scopeID = OwnedRecordScope.scopeID(entity: .transaction, recordID: transactionID)
        let scope = try context.fetch(
            FetchDescriptor<OwnedRecordScope>(
                predicate: #Predicate<OwnedRecordScope> { record in record.id == scopeID }
            )
        ).first
        let audit = try TransactionAuditStore.fetch(
            transactionID: transactionID,
            context: context
        )
        return scope?.ownerUserID != ownerUserID
            || audit?.createdByUserID != ownerUserID
            || audit?.lastModifiedByUserID != ownerUserID
    }

    private static func recordTransactionOwnershipIfNeeded(
        _ transaction: LedgerTransaction,
        ownerUserID: UUID,
        transactionDidMutate: Bool,
        now: Date,
        context: ModelContext,
        writePolicy: InvestmentDerivedWritePolicy
    ) throws -> Bool {
        switch writePolicy {
        case .always:
            try recordTransactionOwnership(
                transaction,
                ownerUserID: ownerUserID,
                now: now,
                context: context
            )
            return true
        case .ifChanged:
            let needsRepair: Bool
            if transactionDidMutate {
                needsRepair = true
            } else {
                needsRepair = try transactionMetadataNeedsRepair(
                    transactionID: transaction.id,
                    ownerUserID: ownerUserID,
                    context: context
                )
            }
            guard needsRepair else { return false }
            try recordTransactionOwnership(
                transaction,
                ownerUserID: ownerUserID,
                now: now,
                context: context
            )
            return true
        }
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
            unitLabel: trade.unitLabel,
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
            unitLabel: unitLabel,
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
