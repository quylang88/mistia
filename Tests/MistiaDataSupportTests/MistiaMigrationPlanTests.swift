import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaMigrationPlanTests: XCTestCase {
    func testV4StoreOpensWithPauseDefaults() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let billID = UUID()
        try createCurrentV4Store(at: storeURL, billID: billID)

        let container = try openCurrentStore(at: storeURL)
        let context = ModelContext(container)
        let bills = try context.fetch(FetchDescriptor<RecurringBillPlan>())

        XCTAssertEqual(bills.map(\.id), [billID])
        XCTAssertEqual(bills.first?.name, "Internet")
        XCTAssertEqual(bills.first?.scheduleKind, .recurring)
        XCTAssertEqual(bills.first?.resolvedPaymentStartDay, 12)
        XCTAssertFalse(bills.first?.resolvedHasExplicitDueDate ?? true)
        XCTAssertFalse(bills.first?.isPaused ?? true)
        XCTAssertNil(bills.first?.pausedAt)
        XCTAssertNil(bills.first?.resumeStartMonth)

        bills.first?.autoPayEnabled = true
        bills.first?.autoPayDay = 10
        try context.save()

        let reopenedContainer = try openCurrentStore(at: storeURL)
        let reopenedBills = try ModelContext(reopenedContainer).fetch(FetchDescriptor<RecurringBillPlan>())
        XCTAssertEqual(reopenedBills.first?.autoPayEnabled, true)
        XCTAssertEqual(reopenedBills.first?.autoPayDay, 10)
    }

    func testMigrationPlanUsesFrozenLegacySchemasAndCurrentV10() {
        let schemaNames = MistiaMigrationPlan.schemas.map { String(reflecting: $0) }
        let v4ModelNames = MistiaSchemaV4.models.map { String(reflecting: $0) }
        let v5ModelNames = MistiaSchemaV5.models.map { String(reflecting: $0) }
        let v6ModelNames = MistiaSchemaV6.models.map { String(reflecting: $0) }
        let v7ModelNames = MistiaSchemaV7.models.map { String(reflecting: $0) }
        let v8ModelNames = MistiaSchemaV8.models.map { String(reflecting: $0) }
        let v9ModelNames = MistiaSchemaV9.models.map { String(reflecting: $0) }
        let v10ModelNames = MistiaSchemaV10.models.map { String(reflecting: $0) }
        let v11ModelNames = MistiaSchemaV11.models.map { String(reflecting: $0) }

        XCTAssertEqual(schemaNames.count, Set(schemaNames).count)
        XCTAssertEqual(schemaNames, [
            "MistiaCoreLogic.MistiaSchemaV4",
            "MistiaCoreLogic.MistiaSchemaV5",
            "MistiaCoreLogic.MistiaSchemaV6",
            "MistiaCoreLogic.MistiaSchemaV7",
            "MistiaCoreLogic.MistiaSchemaV8",
            "MistiaCoreLogic.MistiaSchemaV9",
            "MistiaCoreLogic.MistiaSchemaV10",
            "MistiaCoreLogic.MistiaSchemaV11"
        ])
        XCTAssertEqual(MistiaMigrationPlan.stages.count, 6)
        XCTAssertEqual(
            MistiaLegacyV4ToV5MigrationPlan.schemas.map { String(reflecting: $0) },
            ["MistiaCoreLogic.MistiaSchemaV4", "MistiaCoreLogic.MistiaSchemaV5"]
        )
        XCTAssertTrue(v4ModelNames.contains("MistiaCoreLogic.MistiaSchemaV4Models.RecurringBillPlan"))
        XCTAssertFalse(v4ModelNames.contains("MistiaCoreLogic.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("MistiaCoreLogic.RecurringBillPlan"))
        XCTAssertTrue(v5ModelNames.contains("MistiaCoreLogic.MistiaSchemaV5Models.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.LedgerTransaction"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementGroup"))
        XCTAssertTrue(v6ModelNames.contains("MistiaCoreLogic.SettlementParticipant"))
        XCTAssertFalse(v6ModelNames.contains("MistiaCoreLogic.SettlementObligation"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.InvestmentChannel"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.MistiaSchemaV7InvestmentModels.InvestmentAsset"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.MistiaSchemaV7InvestmentModels.InvestmentTrade"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.InvestmentValuation"))
        XCTAssertTrue(v7ModelNames.contains("MistiaCoreLogic.MistiaSchemaV10InvestmentPostingModels.InvestmentWalletPosting"))
        XCTAssertTrue(v8ModelNames.contains("MistiaCoreLogic.MistiaSchemaV8InvestmentModels.InvestmentAsset"))
        XCTAssertTrue(v8ModelNames.contains("MistiaCoreLogic.MistiaSchemaV9InvestmentTradeModels.InvestmentTrade"))
        XCTAssertFalse(v8ModelNames.contains("MistiaCoreLogic.MistiaSchemaV7InvestmentModels.InvestmentAsset"))
        XCTAssertTrue(v9ModelNames.contains("MistiaCoreLogic.MistiaSchemaV9InvestmentModels.InvestmentAsset"))
        XCTAssertTrue(v9ModelNames.contains("MistiaCoreLogic.MistiaSchemaV9InvestmentTradeModels.InvestmentTrade"))
        XCTAssertFalse(v9ModelNames.contains("MistiaCoreLogic.InvestmentValuation"))
        XCTAssertTrue(v10ModelNames.contains("MistiaCoreLogic.MistiaSchemaV10InvestmentModels.InvestmentAsset"))
        XCTAssertTrue(v10ModelNames.contains("MistiaCoreLogic.InvestmentTrade"))
        XCTAssertTrue(v10ModelNames.contains("MistiaCoreLogic.MistiaSchemaV10InvestmentPostingModels.InvestmentWalletPosting"))
        XCTAssertTrue(v11ModelNames.contains("MistiaCoreLogic.MistiaSchemaV10InvestmentPostingModels.InvestmentWalletPosting"))
        XCTAssertTrue(v11ModelNames.contains("MistiaCoreLogic.InvestmentCashPostingMetadata"))
        XCTAssertTrue(v11ModelNames.contains("MistiaCoreLogic.InvestmentWalletConfiguration"))
    }

    func testV8InvestmentStoreMigratesToV10WithoutValuations() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let valuationID = UUID()
        let v8Schema = Schema(versionedSchema: MistiaSchemaV8.self)
        let v8Configuration = ModelConfiguration("default", schema: v8Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v8Schema, configurations: [v8Configuration])
            let context = ModelContext(container)
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Cards"))
            context.insert(
                MistiaSchemaV8.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Legacy product",
                    currencyCode: "JPY"
                )
            )
            context.insert(
                InvestmentValuation(
                    id: valuationID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    assetID: assetID,
                    marketValueMinor: 1_000,
                    accountingMarketValueMinor: 1_000,
                    currencyCode: "JPY",
                    accountingCurrencyCode: "JPY"
                )
            )
            context.insert(
                SyncConflict(
                    entityRawValue: "investment_valuations",
                    recordID: valuationID,
                    conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                    localPayloadJSON: "{}",
                    remotePayloadJSON: "{}",
                    baseVersion: 1,
                    remoteVersion: 2
                )
            )
            try context.save()
        }

        let v9Schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let v9Configuration = ModelConfiguration("default", schema: v9Schema, url: storeURL)
        let migrated = try MistiaDataStack.LaunchState.openContainer(
            schema: v9Schema,
            configuration: v9Configuration,
            storeURL: storeURL,
            fileManager: .default
        )
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetch(FetchDescriptor<InvestmentAsset>()).first?.id, assetID)
        XCTAssertNil(try context.fetch(FetchDescriptor<InvestmentAsset>()).first?.imagePath)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SyncConflict>()).map(\.entityRawValue),
            []
        )
    }

    func testV9UnitlessInvestmentStoreOpensInV10WithoutChangingAccounting() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let tradeID = UUID()
        let walletID = UUID()
        let ledgerID = UUID()
        let postingID = UUID()
        let occurredAt = Date(timeIntervalSince1970: 1_700_100_000)
        let v9Schema = Schema(versionedSchema: MistiaSchemaV9.self)
        let v9Configuration = ModelConfiguration("default", schema: v9Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v9Schema, configurations: [v9Configuration])
            let context = ModelContext(container)
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Legacy"))
            context.insert(
                MistiaSchemaV9.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Legacy stock",
                    currencyCode: "JPY"
                )
            )
            context.insert(
                MistiaSchemaV9.InvestmentTrade(
                    id: tradeID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    assetID: assetID,
                    kind: .buy,
                    quantity: 30,
                    grossAmountMinor: 3_000,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 3_000,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: walletID,
                    fundingWalletCurrencyCode: "JPY",
                    fundingWalletAmountMinor: 3_000,
                    fundingLedgerTransactionID: ledgerID,
                    positionQuantityAfter: 30,
                    positionCostBasisAfterMinor: 3_000,
                    occurredAt: occurredAt,
                    createdAt: occurredAt,
                    updatedAt: occurredAt
                )
            )
            context.insert(
                MistiaSchemaV9.InvestmentWalletPosting(
                    id: postingID,
                    ownerUserID: ownerID,
                    eventID: tradeID,
                    tradeID: tradeID,
                    assetID: assetID,
                    walletID: walletID,
                    ledgerTransactionID: ledgerID,
                    role: .funding,
                    amountMinor: -3_000,
                    currencyCode: "JPY",
                    accountingAmountMinor: -3_000,
                    accountingCurrencyCode: "JPY",
                    occurredAt: occurredAt,
                    createdAt: occurredAt,
                    updatedAt: occurredAt
                )
            )
            try context.save()
        }

        let v10Schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let v10Configuration = ModelConfiguration("default", schema: v10Schema, url: storeURL)
        let migrated = try MistiaDataStack.LaunchState.openContainer(
            schema: v10Schema,
            configuration: v10Configuration,
            storeURL: storeURL,
            fileManager: .default
        )
        let context = ModelContext(migrated)
        let asset = try XCTUnwrap(context.fetch(FetchDescriptor<InvestmentAsset>()).first)
        let trade = try XCTUnwrap(context.fetch(FetchDescriptor<InvestmentTrade>()).first)
        let posting = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<InvestmentWalletPosting>()
            ).first
        )

        XCTAssertNil(asset.defaultUnitLabel)
        XCTAssertNil(trade.unitLabel)
        XCTAssertEqual(trade.quantity, 30)
        XCTAssertEqual(trade.grossAmountMinor, 3_000)
        XCTAssertEqual(trade.positionCostBasisAfterMinor, 3_000)
        XCTAssertEqual(posting.amountMinor, -3_000)
        XCTAssertEqual(posting.accountingAmountMinor, -3_000)
    }

    func testV8InvestmentStoreRebuildsTradeSnapshotsAndPostingsWithFIFO() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let fundingWalletID = UUID()
        let capitalWalletID = UUID()
        let firstBuyID = UUID()
        let secondBuyID = UUID()
        let saleID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let v8Schema = Schema(versionedSchema: MistiaSchemaV8.self)
        let v8Configuration = ModelConfiguration("default", schema: v8Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v8Schema, configurations: [v8Configuration])
            let context = ModelContext(container)
            context.insert(
                LedgerWallet(
                    id: fundingWalletID,
                    name: "Funding",
                    kind: .cash,
                    iconSymbolName: "banknote.fill",
                    iconColorHex: "#000000",
                    currencyCode: "JPY"
                )
            )
            context.insert(
                LedgerWallet(
                    id: capitalWalletID,
                    name: "Capital return",
                    kind: .bank,
                    iconSymbolName: "building.columns.fill",
                    iconColorHex: "#000000",
                    currencyCode: "JPY"
                )
            )
            context.insert(
                LedgerWallet(
                    id: InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerID),
                    name: "Investment",
                    kind: .investment,
                    iconSymbolName: LedgerWalletKind.investment.defaultIconSymbolName,
                    iconColorHex: LedgerWalletKind.investment.defaultColorHex,
                    currencyCode: "JPY"
                )
            )
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Cards"))
            context.insert(
                MistiaSchemaV8.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Product",
                    currencyCode: "JPY"
                )
            )

            context.insert(
                InvestmentTrade(
                    id: firstBuyID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    assetID: assetID,
                    kind: .buy,
                    quantity: 2,
                    grossAmountMinor: 200,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 200,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: fundingWalletID,
                    fundingWalletCurrencyCode: "JPY",
                    fundingWalletAmountMinor: 200,
                    positionQuantityAfter: 2,
                    positionCostBasisAfterMinor: 200,
                    occurredAt: start,
                    createdAt: start
                )
            )
            context.insert(
                InvestmentTrade(
                    id: secondBuyID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    assetID: assetID,
                    kind: .buy,
                    quantity: 1,
                    grossAmountMinor: 150,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 150,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: fundingWalletID,
                    fundingWalletCurrencyCode: "JPY",
                    fundingWalletAmountMinor: 150,
                    positionQuantityAfter: 3,
                    positionCostBasisAfterMinor: 350,
                    occurredAt: start.addingTimeInterval(1),
                    createdAt: start.addingTimeInterval(1)
                )
            )
            context.insert(
                InvestmentTrade(
                    id: saleID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    assetID: assetID,
                    kind: .sell,
                    quantity: 1,
                    grossAmountMinor: 160,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 160,
                    accountingCurrencyCode: "JPY",
                    capitalReturnWalletID: capitalWalletID,
                    capitalReturnWalletCurrencyCode: "JPY",
                    capitalReturnWalletAmountMinor: 117,
                    releasedCostBasisMinor: 117,
                    realizedProfitLossMinor: 43,
                    positionQuantityAfter: 2,
                    positionCostBasisAfterMinor: 233,
                    occurredAt: start.addingTimeInterval(2),
                    createdAt: start.addingTimeInterval(2)
                )
            )
            try context.save()
        }

        let v9Schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let v9Configuration = ModelConfiguration("default", schema: v9Schema, url: storeURL)
        let migrated = try MistiaDataStack.LaunchState.openContainer(
            schema: v9Schema,
            configuration: v9Configuration,
            storeURL: storeURL,
            fileManager: .default
        )
        let context = ModelContext(migrated)
        let trades = try context.fetch(FetchDescriptor<InvestmentTrade>())
        let sale = try XCTUnwrap(trades.first(where: { $0.id == saleID }))

        XCTAssertEqual(sale.releasedCostBasisMinor, 100)
        XCTAssertEqual(sale.realizedProfitLossMinor, 60)
        XCTAssertEqual(sale.capitalReturnWalletAmountMinor, 100)
        XCTAssertEqual(sale.positionQuantityAfter, 2)
        XCTAssertEqual(sale.positionCostBasisAfterMinor, 250)

        let postings = try context.fetch(
            FetchDescriptor<InvestmentWalletPosting>()
        )
            .filter { $0.tradeID == saleID }
        XCTAssertEqual(postings.first(where: { $0.role == .capitalReturn })?.amountMinor, 100)
        XCTAssertEqual(postings.first(where: { $0.role == .realizedProfit })?.amountMinor, 60)
    }

    func testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let tradeID = UUID()
        let fundingWalletID = UUID()
        let fundingLedgerID = InvestmentLedgerIdentity.derivedID(eventID: tradeID, component: "funding")
        let fundingPostingID = InvestmentLedgerIdentity.derivedID(eventID: tradeID, component: "funding-posting")
        let v7Schema = Schema(versionedSchema: MistiaSchemaV7.self)
        let v7Configuration = ModelConfiguration("default", schema: v7Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v7Schema, configurations: [v7Configuration])
            let context = ModelContext(container)
            let fundingWallet = LedgerWallet(
                id: fundingWalletID,
                name: "Funding",
                kind: .cash,
                iconSymbolName: "banknote.fill",
                iconColorHex: "#000000",
                currencyCode: "JPY"
            )
            context.insert(fundingWallet)
            context.insert(
                LedgerWallet(
                    id: InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerID),
                    name: "Investment",
                    kind: .investment,
                    iconSymbolName: LedgerWalletKind.investment.defaultIconSymbolName,
                    iconColorHex: LedgerWalletKind.investment.defaultColorHex,
                    currencyCode: "JPY"
                )
            )
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Legacy"))
            context.insert(
                MistiaSchemaV7.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Legacy asset",
                    symbol: "OLD",
                    currencyCode: "JPY",
                    openingQuantityDecimalString: "2",
                    openingCostMinor: 100
                )
            )
            let trade = MistiaSchemaV7.InvestmentTrade(
                id: tradeID,
                ownerUserID: ownerID,
                channelID: channelID,
                assetID: assetID,
                kindRawValue: InvestmentTradeKind.buy.rawValue,
                quantityDecimalString: "1",
                grossAmountMinor: 120,
                feeMinor: 10,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 120,
                accountingFeeMinor: 10,
                accountingCurrencyCode: "JPY",
                fundingWalletID: fundingWalletID
            )
            trade.fundingWalletCurrencyCode = "JPY"
            trade.fundingWalletAmountMinor = 130
            trade.fundingLedgerTransactionID = fundingLedgerID
            trade.positionQuantityAfterDecimalString = "3"
            trade.positionCostBasisAfterMinor = 230
            context.insert(trade)
            context.insert(
                LedgerTransaction(
                    id: fundingLedgerID,
                    primaryKind: .expense,
                    title: "Legacy asset",
                    amountMinor: 130,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0,
                    sourceCurrencyCode: "JPY",
                    reportingCurrencyCode: "JPY",
                    reportingAmountMinor: 130,
                    occurredAt: trade.occurredAt,
                    sourceWallet: fundingWallet
                )
            )
            context.insert(
                MistiaSchemaV7.InvestmentWalletPosting(
                    id: fundingPostingID,
                    ownerUserID: ownerID,
                    eventID: tradeID,
                    tradeID: tradeID,
                    assetID: assetID,
                    walletID: fundingWalletID,
                    ledgerTransactionID: fundingLedgerID,
                    role: .funding,
                    amountMinor: -130,
                    currencyCode: "JPY",
                    accountingAmountMinor: -130,
                    accountingCurrencyCode: "JPY"
                )
            )
            context.insert(
                SyncConflict(
                    entityRawValue: MistiaSyncEntity.investmentAsset.rawValue,
                    recordID: assetID,
                    conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                    localPayloadJSON: """
                    {"id":"\(assetID.uuidString)","name":"Legacy asset","symbol":"OLD","opening_quantity_decimal_string":"2","opening_cost_minor":100}
                    """,
                    remotePayloadJSON: """
                    {"id":"\(assetID.uuidString)","name":"Remote asset","symbol":"REMOTE","opening_quantity_decimal_string":"4","opening_cost_minor":240}
                    """,
                    baseVersion: 1,
                    remoteVersion: 2
                )
            )
            context.insert(
                SyncConflict(
                    entityRawValue: MistiaSyncEntity.investmentTrade.rawValue,
                    recordID: tradeID,
                    conflictKindRawValue: MistiaSyncConflictKind.editEdit.rawValue,
                    localPayloadJSON: """
                    {"id":"\(tradeID.uuidString)","gross_amount_minor":120,"fee_minor":10,"accounting_fee_minor":10}
                    """,
                    remotePayloadJSON: """
                    {"id":"\(tradeID.uuidString)","gross_amount_minor":120,"fee_minor":20,"accounting_fee_minor":20}
                    """,
                    baseVersion: 1,
                    remoteVersion: 2
                )
            )
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let v8Configuration = ModelConfiguration("default", schema: v8Schema, url: storeURL)
        let migrated = try MistiaDataStack.LaunchState.openContainer(
            schema: v8Schema,
            configuration: v8Configuration,
            storeURL: storeURL,
            fileManager: .default
        )
        let trades = try ModelContext(migrated).fetch(FetchDescriptor<InvestmentTrade>())
        let stored = try XCTUnwrap(trades.first(where: { $0.id == tradeID }))

        XCTAssertEqual(stored.positionQuantityAfter, 1)
        XCTAssertEqual(stored.positionCostBasisAfterMinor, 120)
        XCTAssertEqual(stored.fundingWalletAmountMinor, 120)
        let ledger = try ModelContext(migrated).fetch(FetchDescriptor<LedgerTransaction>())
        let posting = try ModelContext(migrated).fetch(
            FetchDescriptor<InvestmentWalletPosting>()
        )
        XCTAssertEqual(ledger.first(where: { $0.id == fundingLedgerID })?.amountMinor, 120)
        XCTAssertEqual(ledger.first(where: { $0.id == fundingLedgerID })?.reportingAmountMinor, 120)
        XCTAssertEqual(posting.first(where: { $0.id == fundingPostingID })?.amountMinor, -120)
        XCTAssertEqual(posting.first(where: { $0.id == fundingPostingID })?.accountingAmountMinor, -120)
        let conflicts = try ModelContext(migrated).fetch(FetchDescriptor<SyncConflict>())
        XCTAssertEqual(conflicts.count, 2)
        for conflict in conflicts {
            for payload in [conflict.localPayloadJSON, conflict.remotePayloadJSON] {
                XCTAssertFalse(payload.contains("symbol"))
                XCTAssertFalse(payload.contains("opening_quantity_decimal_string"))
                XCTAssertFalse(payload.contains("opening_cost_minor"))
                XCTAssertFalse(payload.contains("fee_minor"))
                XCTAssertFalse(payload.contains("accounting_fee_minor"))
            }
        }
    }

    func testV7InvestmentMigrationRejectsOversellThatReliedOnOpeningPositionAtomically() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let ownerID = UUID()
        let channelID = UUID()
        let assetID = UUID()
        let tradeID = UUID()
        let capitalWalletID = UUID()
        let v7Schema = Schema(versionedSchema: MistiaSchemaV7.self)
        let v7Configuration = ModelConfiguration("default", schema: v7Schema, url: storeURL)
        do {
            let container = try ModelContainer(for: v7Schema, configurations: [v7Configuration])
            let context = ModelContext(container)
            context.insert(
                LedgerWallet(
                    id: capitalWalletID,
                    name: "Capital return",
                    kind: .bank,
                    iconSymbolName: "building.columns.fill",
                    iconColorHex: "#000000",
                    currencyCode: "JPY"
                )
            )
            context.insert(
                LedgerWallet(
                    id: InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerID),
                    name: "Investment",
                    kind: .investment,
                    iconSymbolName: LedgerWalletKind.investment.defaultIconSymbolName,
                    iconColorHex: LedgerWalletKind.investment.defaultColorHex,
                    currencyCode: "JPY"
                )
            )
            context.insert(InvestmentChannel(id: channelID, ownerUserID: ownerID, name: "Legacy"))
            context.insert(
                MistiaSchemaV7.InvestmentAsset(
                    id: assetID,
                    ownerUserID: ownerID,
                    channelID: channelID,
                    name: "Opening-only asset",
                    symbol: "OLD",
                    currencyCode: "JPY",
                    openingQuantityDecimalString: "1",
                    openingCostMinor: 100
                )
            )
            let trade = MistiaSchemaV7.InvestmentTrade(
                id: tradeID,
                ownerUserID: ownerID,
                channelID: channelID,
                assetID: assetID,
                kindRawValue: InvestmentTradeKind.sell.rawValue,
                quantityDecimalString: "1",
                grossAmountMinor: 150,
                feeMinor: 5,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 150,
                accountingFeeMinor: 5,
                accountingCurrencyCode: "JPY",
                capitalReturnWalletID: capitalWalletID
            )
            trade.capitalReturnWalletCurrencyCode = "JPY"
            trade.capitalReturnWalletAmountMinor = 100
            trade.releasedCostBasisMinor = 100
            trade.realizedProfitLossMinor = 45
            trade.positionQuantityAfterDecimalString = "0"
            trade.positionCostBasisAfterMinor = 0
            context.insert(trade)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let v8Configuration = ModelConfiguration("default", schema: v8Schema, url: storeURL)
        XCTAssertThrowsError(
            try MistiaDataStack.LaunchState.openContainer(
                schema: v8Schema,
                configuration: v8Configuration,
                storeURL: storeURL,
                fileManager: .default
            )
        )

        let reopenedV7 = try ModelContainer(for: v7Schema, configurations: [v7Configuration])
        let context = ModelContext(reopenedV7)
        let assets = try context.fetch(FetchDescriptor<MistiaSchemaV7.InvestmentAsset>())
        let trades = try context.fetch(FetchDescriptor<MistiaSchemaV7.InvestmentTrade>())
        XCTAssertEqual(assets.first(where: { $0.id == assetID })?.openingQuantityDecimalString, "1")
        XCTAssertEqual(assets.first(where: { $0.id == assetID })?.openingCostMinor, 100)
        XCTAssertEqual(trades.first(where: { $0.id == tradeID })?.accountingFeeMinor, 5)
        XCTAssertEqual(trades.first(where: { $0.id == tradeID })?.realizedProfitLossMinor, 45)
    }

    func testPendingSettlementsMigrationIncludesPreparingParticipantsAndStatus() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260611125548_pending_settlements.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create table if not exists public.settlement_participants"))
        XCTAssertTrue(migration.contains("kind_raw_value in ('sharedExpense')"))
        XCTAssertFalse(migration.contains("create table if not exists public.settlement_obligations"))
        XCTAssertTrue(migration.contains("status_raw_value in ('preparing', 'open', 'partiallySettled', 'settled')"))
        XCTAssertTrue(migration.contains("is_archived boolean not null default false"))
        XCTAssertTrue(migration.contains("archived_at timestamptz"))
        XCTAssertTrue(migration.contains("display_name text not null default ''"))
        XCTAssertTrue(migration.contains("normalized_key text"))
        XCTAssertTrue(migration.contains("is_self boolean not null default false"))
        XCTAssertTrue(migration.contains("settlement_participants_group_id_idx"))
        XCTAssertTrue(migration.contains("settlement_participants_family_select"))
    }

    func testInvestmentUnitsMigrationKeepsCloudColumnsNullableAndPatchesAtomicRPCs() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260822050000_add_investment_units.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("add column if not exists default_unit_label text"))
        XCTAssertTrue(migration.contains("add column if not exists unit_label text"))
        XCTAssertFalse(migration.contains("default_unit_label text not null"))
        XCTAssertFalse(migration.contains("unit_label text not null"))
        XCTAssertTrue(migration.contains("public.investment_unit_key(trade_row.unit_label)"))
        XCTAssertTrue(migration.contains("incoming.unit_label := existing.unit_label"))
        XCTAssertTrue(migration.contains("incoming.unit_label := public.investment_normalize_unit_label(asset_row.default_unit_label)"))
        XCTAssertTrue(migration.contains("incoming.default_unit_label := existing.default_unit_label"))
        XCTAssertTrue(migration.contains("set unit_label = incoming.default_unit_label"))
        XCTAssertTrue(migration.contains("perform public.investment_rebuild_asset"))
    }

    func testInvestmentCashMigrationLinksWalletsAndSerializesBatchReconciliation() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260824090000_link_investment_cash_wallet.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("add column if not exists investment_linked_wallet_id uuid"))
        XCTAssertTrue(migration.contains("add column if not exists cash_bucket_raw_value text"))
        XCTAssertTrue(migration.contains("'booked', 'unreconciled'"))
        XCTAssertTrue(migration.contains("'derived', 'inferred', 'manual'"))
        XCTAssertTrue(migration.contains("create or replace function public.mutate_investment_cash_postings"))
        XCTAssertTrue(migration.contains("pg_advisory_xact_lock"))
        XCTAssertTrue(migration.contains("A reconciliation event must contain exactly two postings"))
        XCTAssertTrue(migration.contains("Reconciliation exceeds the outstanding investment cash"))
        XCTAssertTrue(migration.contains("public.has_investment_permission(owner_id, 'edit')"))
        XCTAssertTrue(migration.contains("'wallet', wallet_id_value, 'use'"))
        XCTAssertTrue(migration.contains("Move investment cash and unlink this wallet"))
        XCTAssertTrue(migration.contains("role_raw_value = 'realizedProfit'"))
    }

    func testFamilyTransferRPCMigrationGuardsPermissionsAndWritesBothRows() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260523120000_family_transfer_rpc.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.create_family_transfer"))
        XCTAssertTrue(migration.contains("public.shared_active_family_id(actor_id, p_recipient_user_id)"))
        XCTAssertTrue(migration.contains("public.can_operate_wallet(p_destination_wallet_id)"))
        XCTAssertTrue(migration.contains("p_amount_minor <= 0"))
        XCTAssertTrue(migration.contains("'familyTransfer'"))
        XCTAssertEqual(migration.components(separatedBy: "insert into public.ledger_transactions").count - 1, 2)
        XCTAssertTrue(migration.contains("insert into public.family_notifications"))
        XCTAssertTrue(migration.contains("'family-transfer:' || recipient_transaction_id::text"))
        XCTAssertTrue(migration.contains("grant execute on function public.create_family_transfer"))
    }

    func testFamilyTransferNoteUpdateMigrationIncludesNoteParameter() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260523130000_update_family_transfer_note.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.create_family_transfer"))
        XCTAssertTrue(migration.contains("p_note text default null"))
        XCTAssertTrue(migration.contains("sender_note || chr(10) || chr(10) || trim(p_note)"))
        XCTAssertTrue(migration.contains("recipient_note || chr(10) || chr(10) || trim(p_note)"))
        XCTAssertTrue(migration.contains("grant execute on function public.create_family_transfer(uuid, uuid, uuid, uuid, bigint, timestamptz, text)"))
    }

    func testFamilyTransferMetadataAndNoteFixMigration() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260524000000_fix_family_transfer_notification_metadata_and_note.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.create_family_transfer"))
        XCTAssertTrue(migration.contains("p_note text default null"))
        XCTAssertTrue(migration.contains("sender_note := trim(p_note);"))
        XCTAssertTrue(migration.contains("recipient_note := trim(p_note);"))
        XCTAssertTrue(migration.contains("amount_minor', p_amount_minor::text"))
        XCTAssertTrue(migration.contains("grant execute on function public.create_family_transfer(uuid, uuid, uuid, uuid, bigint, timestamptz, text)"))
    }

    func testFamilyTransferLocalizedTitleMigrationAddsClientTitleParameters() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260608090000_family_transfer_localized_titles.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("p_sender_title text default null"))
        XCTAssertTrue(migration.contains("p_recipient_title text default null"))
        XCTAssertTrue(migration.contains("coalesce(nullif(trim(p_sender_title), ''), 'Chuyển tiền gia đình')"))
        XCTAssertTrue(migration.contains("coalesce(nullif(trim(p_recipient_title), ''), 'Nhận tiền gia đình')"))
        XCTAssertTrue(migration.contains("uuid, uuid, uuid, uuid, bigint, bigint, text, text, text, text, timestamptz, text, text, text"))
    }

    func testTransactionCreatorWalletAccessMigrationRestoresCreatorManageBranch() throws {
        let migrationURL = repositoryRootURL()
            .appending(path: "supabase/migrations/20260616115354_restore_transaction_creator_wallet_access.sql")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)

        XCTAssertTrue(migration.contains("create or replace function public.can_manage_transaction"))
        XCTAssertTrue(migration.contains("auth.uid() = created_by_user_id"))
        XCTAssertTrue(migration.contains("public.can_operate_wallet(source_wallet_id)"))
        XCTAssertTrue(migration.contains("public.has_family_permission_grant(owner_user_id, 'transaction', null, 'edit')"))
        XCTAssertTrue(migration.contains("grant execute on function public.can_manage_transaction"))
    }

    private func createCurrentV4Store(at storeURL: URL, billID: UUID) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            MistiaSchemaV4.RecurringBillPlan(
                id: billID,
                name: "Internet",
                iconSymbolName: "wifi",
                amountMinor: 4_200,
                dueDay: 12,
                frequencyMonths: 1
            )
        )
        try context.save()
    }

    private func openCurrentStore(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)

        return try MistiaDataStack.LaunchState.openContainer(
            schema: schema,
            configuration: configuration,
            storeURL: storeURL,
            fileManager: .default
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "mistia-migration-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("store")
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func removeStoreArtifacts(at storeURL: URL) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
