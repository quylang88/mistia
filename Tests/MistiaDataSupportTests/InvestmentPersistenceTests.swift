import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class InvestmentPersistenceTests: XCTestCase {
    func testAssetSaveCreatesAndEditsProductMetadata() throws {
        let fixture = try makeFixture()
        let assetID = UUID()

        let created = try InvestmentPersistenceService.saveAsset(
            ownerUserID: fixture.ownerID,
            draft: InvestmentAssetDraft(
                id: assetID,
                channelID: fixture.channel.id,
                name: "  Promotional cards  ",
                currencyCode: "jpy"
            ),
            context: fixture.context
        )
        XCTAssertEqual(created.name, "Promotional cards")
        XCTAssertEqual(created.currencyCode, "JPY")

        let updated = try InvestmentPersistenceService.saveAsset(
            ownerUserID: fixture.ownerID,
            draft: InvestmentAssetDraft(
                id: assetID,
                channelID: fixture.channel.id,
                name: "Promotional cards – box A",
                currencyCode: "JPY",
                createdAt: created.createdAt
            ),
            context: fixture.context
        )
        XCTAssertEqual(updated.id, assetID)
        XCTAssertEqual(updated.name, "Promotional cards – box A")
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<InvestmentAsset>())
                .filter { $0.id == assetID }
                .count,
            1
        )
    }

    func testFirstDefaultUnitOnLegacyAssetBackfillsItsUnitlessHistoryWithoutChangingAccounting() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 80,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let beforeBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
        let beforeSell = try XCTUnwrap(fetchTrade(id: sell.id, fixture))
        let beforeAccounting = (
            beforeBuy.grossAmountMinor,
            beforeSell.grossAmountMinor,
            beforeSell.releasedCostBasisMinor,
            beforeSell.realizedProfitLossMinor,
            beforeSell.positionCostBasisAfterMinor,
            try balance(fixture.fundingWallet, fixture),
            try balance(fixture.capitalWallet, fixture)
        )

        let saved = try InvestmentPersistenceService.saveAsset(
            ownerUserID: fixture.ownerID,
            draft: InvestmentAssetDraft(
                id: fixture.asset.id,
                channelID: fixture.channel.id,
                name: fixture.asset.name,
                currencyCode: fixture.asset.currencyCode,
                defaultUnitLabel: "  gift   pack ",
                createdAt: fixture.asset.createdAt
            ),
            context: fixture.context
        )

        let afterBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
        let afterSell = try XCTUnwrap(fetchTrade(id: sell.id, fixture))
        XCTAssertEqual(saved.defaultUnitLabel, "gift pack")
        XCTAssertEqual(afterBuy.unitLabel, "gift pack")
        XCTAssertEqual(afterSell.unitLabel, "gift pack")
        XCTAssertEqual(afterBuy.grossAmountMinor, beforeAccounting.0)
        XCTAssertEqual(afterSell.grossAmountMinor, beforeAccounting.1)
        XCTAssertEqual(afterSell.releasedCostBasisMinor, beforeAccounting.2)
        XCTAssertEqual(afterSell.realizedProfitLossMinor, beforeAccounting.3)
        XCTAssertEqual(afterSell.positionCostBasisAfterMinor, beforeAccounting.4)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), beforeAccounting.5)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), beforeAccounting.6)
    }

    func testEditingTradeUnitRebuildsHistoryAndRejectsHistoricalUnitOversellAtomically() throws {
        let fixture = try makeFixture()
        let packBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            unit: "pack",
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            unit: "box",
            gross: 300,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let sale = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            unit: "pack",
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(2)
        )
        let balanceBefore = try balance(fixture.fundingWallet, fixture)

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    id: packBuy.id,
                    channelID: fixture.channel.id,
                    assetID: fixture.asset.id,
                    kind: .buy,
                    quantity: 1,
                    unitLabel: "box",
                    grossAmountMinor: 100,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 100,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: fixture.fundingWallet.id,
                    occurredAt: fixture.start,
                    createdAt: packBuy.createdAt
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentAccountingError, .insufficientPosition)
        }

        XCTAssertEqual(try fetchTrade(id: packBuy.id, fixture)?.unitLabel, "pack")
        XCTAssertEqual(try fetchTrade(id: sale.id, fixture)?.releasedCostBasisMinor, 100)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), balanceBefore)
    }

    func testAssetAccountingIdentityIsLockedAfterFIFOHistoryExists() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        let renamed = try InvestmentPersistenceService.saveAsset(
            ownerUserID: fixture.ownerID,
            draft: InvestmentAssetDraft(
                id: fixture.asset.id,
                channelID: fixture.channel.id,
                name: "Renamed FIFO product",
                currencyCode: "JPY",
                createdAt: fixture.asset.createdAt
            ),
            context: fixture.context
        )
        XCTAssertEqual(renamed.name, "Renamed FIFO product")
        XCTAssertEqual(try fetchTrade(id: buy.id, fixture)?.positionQuantityAfter, 2)
        XCTAssertEqual(try fetchTrade(id: buy.id, fixture)?.positionCostBasisAfterMinor, 100)

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveAsset(
                ownerUserID: fixture.ownerID,
                draft: InvestmentAssetDraft(
                    id: fixture.asset.id,
                    channelID: fixture.channel.id,
                    name: renamed.name,
                    currencyCode: "VND",
                    createdAt: fixture.asset.createdAt
                ),
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .assetHistoryLocksAccounting)
        }
        XCTAssertEqual(fixture.asset.currencyCode, "JPY")
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
    }

    func testBuyAndProfitableSaleCreditsFullProceedsToReceivingWallet() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let systemWallet = try XCTUnwrap(fetchSystemWallet(fixture))
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 150)
        XCTAssertEqual(try balance(systemWallet, fixture), 0)

        let storedBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
        let storedSell = try XCTUnwrap(fetchTrade(id: sell.id, fixture))
        XCTAssertEqual(storedBuy.realizedProfitLossMinor, 0)
        XCTAssertEqual(storedSell.releasedCostBasisMinor, 100)
        XCTAssertEqual(storedSell.realizedProfitLossMinor, 50)

        let legs = try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
            .filter { $0.financialDomain == .investment && $0.deletedAt == nil }
        XCTAssertEqual(legs.count, 3)
        XCTAssertTrue(legs.allSatisfy { $0.reportingExpenseMinor == 0 && $0.reportingIncomeMinor == 0 })
    }

    func testLossStillCreditsExactSaleProceedsToReceivingWallet() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 70,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let systemWallet = try XCTUnwrap(fetchSystemWallet(fixture))
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 70)
        XCTAssertEqual(try balance(systemWallet, fixture), 0)
    }

    func testSellWithZeroAmountDeductsTotalLossFromSelectedWallet() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 200,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let lossSale = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 2,
            gross: 0,
            capitalWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let systemWallet = try XCTUnwrap(fetchSystemWallet(fixture))
        // The selected wallet pays both the original purchase and the liquidation loss.
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 600)
        // Capital wallet was untouched (0 balance)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 0)
        XCTAssertEqual(try balance(systemWallet, fixture), 0)

        let storedBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
        let storedLoss = try XCTUnwrap(fetchTrade(id: lossSale.id, fixture))
        XCTAssertEqual(storedBuy.realizedProfitLossMinor, 0)
        XCTAssertEqual(storedLoss.releasedCostBasisMinor, 200)
        XCTAssertEqual(storedLoss.realizedProfitLossMinor, -200)
        XCTAssertEqual(storedLoss.positionQuantityAfter, 0)
        XCTAssertEqual(storedLoss.positionCostBasisAfterMinor, 0)
        XCTAssertEqual(storedLoss.capitalReturnWalletID, fixture.fundingWallet.id)
        XCTAssertNil(storedLoss.capitalReturnLedgerTransactionID)
        XCTAssertNotNil(storedLoss.profitLossLedgerTransactionID)
    }

    func testPromotionalFreeBuyCanBeAddedEditedAndDeletedWithoutWalletDrift() throws {
        let fixture = try makeFixture()
        let freeBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 3,
            gross: 0,
            fundingWalletID: nil,
            occurredAt: fixture.start
        )

        var stored = try XCTUnwrap(fetchTrade(id: freeBuy.id, fixture))
        XCTAssertEqual(stored.positionQuantityAfter, 3)
        XCTAssertEqual(stored.positionCostBasisAfterMinor, 0)
        XCTAssertNil(stored.fundingWalletID)
        XCTAssertNil(stored.fundingLedgerTransactionID)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .filter { $0.tradeID == freeBuy.id }
                .isEmpty
        )

        _ = try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: freeBuy.id,
                channelID: fixture.channel.id,
                assetID: fixture.asset.id,
                kind: .buy,
                quantity: 4,
                grossAmountMinor: 120,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 120,
                accountingCurrencyCode: "JPY",
                fundingWalletID: fixture.fundingWallet.id,
                occurredAt: fixture.start,
                createdAt: freeBuy.createdAt
            ),
            rates: [],
            context: fixture.context
        )

        stored = try XCTUnwrap(fetchTrade(id: freeBuy.id, fixture))
        XCTAssertEqual(stored.positionQuantityAfter, 4)
        XCTAssertEqual(stored.positionCostBasisAfterMinor, 120)
        XCTAssertEqual(stored.fundingWalletID, fixture.fundingWallet.id)
        XCTAssertNotNil(stored.fundingLedgerTransactionID)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 880)

        _ = try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: freeBuy.id,
                channelID: fixture.channel.id,
                assetID: fixture.asset.id,
                kind: .buy,
                quantity: 5,
                grossAmountMinor: 0,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 0,
                accountingCurrencyCode: "JPY",
                occurredAt: fixture.start,
                createdAt: freeBuy.createdAt
            ),
            rates: [],
            context: fixture.context
        )

        stored = try XCTUnwrap(fetchTrade(id: freeBuy.id, fixture))
        XCTAssertEqual(stored.positionQuantityAfter, 5)
        XCTAssertEqual(stored.positionCostBasisAfterMinor, 0)
        XCTAssertNil(stored.fundingWalletID)
        XCTAssertNil(stored.fundingLedgerTransactionID)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
                .filter { $0.id == InvestmentLedgerIdentity.derivedID(eventID: freeBuy.id, component: "funding") }
                .allSatisfy { $0.deletedAt != nil }
        )
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .filter { $0.tradeID == freeBuy.id }
                .allSatisfy { $0.deletedAt != nil }
        )

        _ = try InvestmentPersistenceService.deleteTrade(
            ownerUserID: fixture.ownerID,
            tradeID: freeBuy.id,
            context: fixture.context
        )

        stored = try XCTUnwrap(fetchTrade(id: freeBuy.id, fixture))
        XCTAssertNotNil(stored.deletedAt)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
    }

    func testPromotionalFreeBuyRequiresBothAmountsAndWalletShapeToMatch() throws {
        let fixture = try makeFixture()

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    channelID: fixture.channel.id,
                    assetID: fixture.asset.id,
                    kind: .buy,
                    quantity: 1,
                    grossAmountMinor: 0,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 0,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: fixture.fundingWallet.id,
                    occurredAt: fixture.start
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .invalidWallet)
        }

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    channelID: fixture.channel.id,
                    assetID: fixture.asset.id,
                    kind: .buy,
                    quantity: 1,
                    grossAmountMinor: 100,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 0,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: fixture.fundingWallet.id,
                    occurredAt: fixture.start
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
        }
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
    }

    func testSellingPromotionalFreeInventoryCreditsOnlyInvestmentProfit() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 0,
            fundingWalletID: nil,
            occurredAt: fixture.start
        )
        let sale = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 2,
            gross: 80,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let storedSale = try XCTUnwrap(fetchTrade(id: sale.id, fixture))
        XCTAssertEqual(storedSale.releasedCostBasisMinor, 0)
        XCTAssertEqual(storedSale.realizedProfitLossMinor, 80)
        XCTAssertEqual(storedSale.positionQuantityAfter, 0)
        XCTAssertEqual(storedSale.positionCostBasisAfterMinor, 0)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 80)
        XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 0)
    }

    func testBuyUsesTotalOrderAmountWithoutMultiplyingByQuantity() throws {
        let fixture = try makeFixture()
        let draft = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 3,
            gross: 120,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let trade = try XCTUnwrap(fetchTrade(id: draft.id, fixture))

        XCTAssertEqual(trade.positionQuantityAfter, 3)
        XCTAssertEqual(trade.positionCostBasisAfterMinor, 120)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 880)
    }

    func testRemoteInvestmentPayloadsOmitRemovedFields() throws {
        let fixture = try makeFixture()
        let draft = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 3,
            gross: 120,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let trade = try XCTUnwrap(fetchTrade(id: draft.id, fixture))
        let assetPayload = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(RemoteInvestmentAsset(local: fixture.asset))
            ) as? [String: Any]
        )
        let tradePayload = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(RemoteInvestmentTrade(local: trade))
            ) as? [String: Any]
        )

        XCTAssertNil(assetPayload["symbol"])
        XCTAssertNil(assetPayload["opening_quantity_decimal_string"])
        XCTAssertNil(assetPayload["opening_cost_minor"])
        XCTAssertNil(tradePayload["fee_minor"])
        XCTAssertNil(tradePayload["accounting_fee_minor"])
    }

    func testTradeRejectsSourceCurrencyThatDoesNotMatchAsset() throws {
        let fixture = try makeFixture()
        let draft = InvestmentTradeDraft(
            channelID: fixture.channel.id,
            assetID: fixture.asset.id,
            kind: .buy,
            quantity: 1,
            grossAmountMinor: 100,
            currencyCode: "VND",
            accountingGrossAmountMinor: 100,
            accountingCurrencyCode: "JPY",
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: draft,
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
        }
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<InvestmentTrade>()).isEmpty)
    }

    func testBackdatedBuyRewritesDownstreamSaleLegs() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 200,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let sellDraft = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 180,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(2)
        )
        XCTAssertEqual(try fetchTrade(id: sellDraft.id, fixture)?.realizedProfitLossMinor, -20)

        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        let recalculatedSell = try XCTUnwrap(fetchTrade(id: sellDraft.id, fixture))
        XCTAssertEqual(recalculatedSell.releasedCostBasisMinor, 100)
        XCTAssertEqual(recalculatedSell.realizedProfitLossMinor, 80)
        let systemWallet = try XCTUnwrap(fetchSystemWallet(fixture))
        XCTAssertEqual(try balance(systemWallet, fixture), 0)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 180)
    }

    func testCrossCurrencyWalletLegsPreserveAccountingSaleIdentityAfterRounding() throws {
        let fixture = try makeFixture()
        fixture.fundingWallet.currencyCode = "VND"
        fixture.capitalWallet.currencyCode = "VND"
        try fixture.context.save()
        let rates = [
            MistiaExchangeRate(
                baseCurrencyCode: "JPY",
                quoteCurrencyCode: "VND",
                rateDecimalString: "2",
                provider: "test",
                fetchedAt: fixture.start,
                rateDate: "2026-08-09"
            )
        ]
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start,
            rates: rates
        )
        let sale = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 151,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1),
            rates: rates
        )

        let storedSale = try XCTUnwrap(fetchTrade(id: sale.id, fixture))
        XCTAssertEqual(storedSale.releasedCostBasisMinor, 100)
        XCTAssertEqual(storedSale.capitalReturnWalletAmountMinor, 200)
        XCTAssertEqual(storedSale.realizedProfitLossMinor, 51)
        XCTAssertEqual(
            storedSale.releasedCostBasisMinor + storedSale.realizedProfitLossMinor,
            storedSale.accountingGrossAmountMinor
        )
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 800)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 302)
        XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 0)
        let cashSnapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        let capitalLocation = try XCTUnwrap(
            cashSnapshot.locations.first { $0.walletID == fixture.capitalWallet.id }
        )
        XCTAssertEqual(capitalLocation.bookedMinor, 51)
        XCTAssertEqual(capitalLocation.originalBookedMinor, 102)
        XCTAssertEqual(capitalLocation.currencyCode, "VND")
    }

    func testOversellLeavesExistingPositionAndWalletBalancesUnchanged() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        XCTAssertThrowsError(
            try saveTrade(
                fixture: fixture,
                kind: .sell,
                quantity: 2,
                gross: 200,
                capitalWalletID: fixture.capitalWallet.id,
                occurredAt: fixture.start.addingTimeInterval(1)
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentAccountingError, .insufficientPosition)
        }

        let activeTrades = try fixture.context.fetch(FetchDescriptor<InvestmentTrade>())
            .filter { $0.deletedAt == nil }
        XCTAssertEqual(activeTrades.count, 1)
        XCTAssertEqual(activeTrades.first?.positionQuantityAfter, 1)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 0)
    }

    func testSyncExportsProfitTransferButNeverServerDerivedLedgerOrPostings() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let derivedLedgerID = InvestmentLedgerIdentity.derivedID(eventID: buy.id, component: "funding")
        let derivedLedgerMutation = MistiaSyncMutation(
            entity: .transaction,
            recordID: derivedLedgerID,
            subjectUserID: fixture.ownerID,
            kind: .upsert,
            modifiedAt: fixture.start
        )
        XCTAssertNil(
            try MistiaSyncLocalStore.exportRecord(
                for: derivedLedgerMutation,
                from: fixture.container
            )
        )

        let postingID = InvestmentLedgerIdentity.derivedID(eventID: buy.id, component: "funding-posting")
        let postingMutation = MistiaSyncMutation(
            entity: .investmentPosting,
            recordID: postingID,
            subjectUserID: fixture.ownerID,
            kind: .upsert,
            modifiedAt: fixture.start
        )
        XCTAssertNil(
            try MistiaSyncLocalStore.exportRecord(
                for: postingMutation,
                from: fixture.container
            )
        )

        let linkedWallet = LedgerWallet(
            name: "Investment Cash",
            kind: .cash,
            iconSymbolName: "banknote.fill",
            iconColorHex: "#9A67FF",
            currencyCode: "JPY",
            openingBalanceMinor: 0
        )
        fixture.context.insert(linkedWallet)
        try MistiaRecordOwnershipStore.upsert(
            entity: .wallet,
            recordID: linkedWallet.id,
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
        _ = try InvestmentPersistenceService.setLinkedWallet(
            ownerUserID: fixture.ownerID,
            linkedWalletID: linkedWallet.id,
            context: fixture.context
        )
        let transferResult = try InvestmentPersistenceService.reconcileCash(
            ownerUserID: fixture.ownerID,
            requests: [
                InvestmentReconciliationRequest(
                    walletID: fixture.capitalWallet.id,
                    accountingAmountMinor: 10
                )
            ],
            context: fixture.context
        ).persistence
        let transferID = try XCTUnwrap(transferResult.ledgerTransactionIDs.first)
        let transferMutation = MistiaSyncMutation(
            entity: .transaction,
            recordID: transferID,
            subjectUserID: fixture.ownerID,
            kind: .upsert,
            modifiedAt: .now
        )
        let transferRecord = try MistiaSyncLocalStore.exportRecord(
            for: transferMutation,
            from: fixture.container
        )
        guard case .transaction(let row) = transferRecord else {
            return XCTFail("Expected the investment profit transfer to remain uploadable")
        }
        XCTAssertEqual(row.settlementRoleRawValue, InvestmentLedgerLegRole.investmentReconciliation.rawValue)
    }

    func testGuestOwnershipReassignmentMovesInvestmentDomainAndSystemWalletIdentity() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = buy
        let newOwnerID = UUID()

        try MistiaSyncLocalStore.reassignLocalOwnership(
            from: fixture.ownerID,
            to: newOwnerID,
            in: fixture.container
        )
        let verificationContext = ModelContext(fixture.container)

        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<InvestmentChannel>()).first?.ownerUserID,
            newOwnerID
        )
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<InvestmentAsset>()).first?.ownerUserID,
            newOwnerID
        )
        XCTAssertTrue(
            try verificationContext.fetch(FetchDescriptor<InvestmentTrade>())
                .allSatisfy { $0.ownerUserID == newOwnerID }
        )
        XCTAssertTrue(
            try verificationContext.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .allSatisfy { $0.ownerUserID == newOwnerID }
        )
        let walletIDs = Set(try verificationContext.fetch(FetchDescriptor<LedgerWallet>()).map(\.id))
        XCTAssertFalse(walletIDs.contains(InvestmentSystemWalletIdentity.walletID(ownerUserID: fixture.ownerID)))
        XCTAssertTrue(walletIDs.contains(InvestmentSystemWalletIdentity.walletID(ownerUserID: newOwnerID)))
    }

    func testPrivacyPurgeRemovesOnlyRevokedOwnersInvestmentCache() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        try InvestmentPrivacyCacheService.purge(
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )

        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<InvestmentChannel>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<InvestmentAsset>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<InvestmentTrade>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>()).isEmpty)
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
                .allSatisfy { $0.financialDomain == .ordinary }
        )
        let remainingWalletIDs = Set(try fixture.context.fetch(FetchDescriptor<LedgerWallet>()).map(\.id))
        XCTAssertTrue(remainingWalletIDs.contains(fixture.fundingWallet.id))
        XCTAssertTrue(remainingWalletIDs.contains(fixture.capitalWallet.id))
        XCTAssertFalse(
            remainingWalletIDs.contains(
                InvestmentSystemWalletIdentity.walletID(ownerUserID: fixture.ownerID)
            )
        )
    }

    func testEditingBuyMovesItBetweenAssetsAndWalletsAndRebuildsBothHistories() throws {
        let fixture = try makeFixture()
        let secondWallet = LedgerWallet(
            name: "Second funding",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#111111",
            currencyCode: "JPY",
            openingBalanceMinor: 1_000
        )
        fixture.context.insert(secondWallet)
        let secondChannel = try InvestmentPersistenceService.createChannel(
            ownerUserID: fixture.ownerID,
            name: "Second shop",
            iconSymbolName: "shippingbox.fill",
            iconColorHex: "#9A67FF",
            primaryCurrencyCode: "JPY",
            context: fixture.context
        ).channel
        let secondAsset = try InvestmentPersistenceService.createAsset(
            ownerUserID: fixture.ownerID,
            channelID: secondChannel.id,
            name: "Item B",
            currencyCode: "JPY",
            context: fixture.context
        )
        let movedBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 3,
            gross: 120,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let remainingBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 50,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let correctedDate = fixture.start.addingTimeInterval(100)
        let result = try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: movedBuy.id,
                channelID: secondChannel.id,
                assetID: secondAsset.id,
                kind: .buy,
                quantity: 4,
                grossAmountMinor: 200,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 200,
                accountingCurrencyCode: "JPY",
                fundingWalletID: secondWallet.id,
                note: "Corrected buy",
                occurredAt: correctedDate,
                createdAt: movedBuy.createdAt
            ),
            rates: [],
            now: correctedDate.addingTimeInterval(1),
            context: fixture.context
        )

        let storedMovedBuy = try XCTUnwrap(fetchTrade(id: movedBuy.id, fixture))
        XCTAssertEqual(storedMovedBuy.id, movedBuy.id)
        XCTAssertEqual(storedMovedBuy.kind, .buy)
        XCTAssertEqual(storedMovedBuy.channelID, secondChannel.id)
        XCTAssertEqual(storedMovedBuy.assetID, secondAsset.id)
        XCTAssertEqual(storedMovedBuy.quantity, 4)
        XCTAssertEqual(storedMovedBuy.grossAmountMinor, 200)
        XCTAssertEqual(storedMovedBuy.occurredAt, correctedDate)
        XCTAssertEqual(storedMovedBuy.fundingWalletID, secondWallet.id)
        XCTAssertEqual(storedMovedBuy.note, "Corrected buy")
        XCTAssertEqual(storedMovedBuy.positionQuantityAfter, 4)
        XCTAssertEqual(storedMovedBuy.positionCostBasisAfterMinor, 200)

        let storedRemainingBuy = try XCTUnwrap(fetchTrade(id: remainingBuy.id, fixture))
        XCTAssertEqual(storedRemainingBuy.assetID, fixture.asset.id)
        XCTAssertEqual(storedRemainingBuy.positionQuantityAfter, 1)
        XCTAssertEqual(storedRemainingBuy.positionCostBasisAfterMinor, 50)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 950)
        XCTAssertEqual(try balance(secondWallet, fixture), 800)
        XCTAssertTrue(result.walletIDs.contains(fixture.fundingWallet.id))
        XCTAssertTrue(result.walletIDs.contains(secondWallet.id))

        let posting = try XCTUnwrap(
            fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .first { $0.tradeID == movedBuy.id && $0.deletedAt == nil }
        )
        XCTAssertEqual(posting.assetID, secondAsset.id)
        XCTAssertEqual(posting.walletID, secondWallet.id)
        XCTAssertEqual(posting.amountMinor, -200)
    }

    func testEditingExistingSellMovesItBetweenAssetsAndCapitalWalletsAndRebuildsBothHistories() throws {
        let fixture = try makeFixture()
        let secondCapitalWallet = LedgerWallet(
            name: "Second capital",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#333333",
            currencyCode: "JPY",
            openingBalanceMinor: 0
        )
        fixture.context.insert(secondCapitalWallet)
        let secondChannel = try InvestmentPersistenceService.createChannel(
            ownerUserID: fixture.ownerID,
            name: "Second shop",
            iconSymbolName: "shippingbox.fill",
            iconColorHex: "#9A67FF",
            primaryCurrencyCode: "JPY",
            context: fixture.context
        ).channel
        let secondAsset = try InvestmentPersistenceService.createAsset(
            ownerUserID: fixture.ownerID,
            channelID: secondChannel.id,
            name: "Item B",
            currencyCode: "JPY",
            context: fixture.context
        )

        let originalBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            asset: secondAsset,
            channel: secondChannel,
            kind: .buy,
            quantity: 4,
            gross: 160,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let originalSell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(2)
        )
        let correctedDate = fixture.start.addingTimeInterval(3)

        let result = try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: originalSell.id,
                channelID: secondChannel.id,
                assetID: secondAsset.id,
                kind: .sell,
                quantity: 3,
                grossAmountMinor: 260,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 260,
                accountingCurrencyCode: "JPY",
                capitalReturnWalletID: secondCapitalWallet.id,
                note: "Corrected sale",
                occurredAt: correctedDate,
                createdAt: originalSell.createdAt
            ),
            rates: [],
            now: correctedDate.addingTimeInterval(1),
            context: fixture.context
        )

        let storedSell = try XCTUnwrap(fetchTrade(id: originalSell.id, fixture))
        XCTAssertEqual(storedSell.id, originalSell.id)
        XCTAssertEqual(storedSell.kind, .sell)
        XCTAssertEqual(storedSell.channelID, secondChannel.id)
        XCTAssertEqual(storedSell.assetID, secondAsset.id)
        XCTAssertEqual(storedSell.quantity, 3)
        XCTAssertEqual(storedSell.grossAmountMinor, 260)
        XCTAssertEqual(storedSell.occurredAt, correctedDate)
        XCTAssertEqual(storedSell.capitalReturnWalletID, secondCapitalWallet.id)
        XCTAssertEqual(storedSell.note, "Corrected sale")
        XCTAssertEqual(storedSell.releasedCostBasisMinor, 120)
        XCTAssertEqual(storedSell.realizedProfitLossMinor, 140)
        XCTAssertEqual(storedSell.positionQuantityAfter, 1)
        XCTAssertEqual(storedSell.positionCostBasisAfterMinor, 40)

        let rebuiltOriginalBuy = try XCTUnwrap(fetchTrade(id: originalBuy.id, fixture))
        XCTAssertEqual(rebuiltOriginalBuy.positionQuantityAfter, 2)
        XCTAssertEqual(rebuiltOriginalBuy.positionCostBasisAfterMinor, 100)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 0)
        XCTAssertEqual(try balance(secondCapitalWallet, fixture), 260)
        XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 0)
        XCTAssertTrue(result.walletIDs.contains(fixture.capitalWallet.id))
        XCTAssertTrue(result.walletIDs.contains(secondCapitalWallet.id))

        let activePostings = try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .filter { $0.tradeID == originalSell.id && $0.deletedAt == nil }
        XCTAssertEqual(Set(activePostings.map(\.assetID)), [secondAsset.id])
        XCTAssertTrue(activePostings.contains { $0.walletID == secondCapitalWallet.id })
    }

    func testEditingExistingSellToInsufficientTargetPositionLeavesOriginalStateUnchanged() throws {
        let fixture = try makeFixture()
        let secondChannel = try InvestmentPersistenceService.createChannel(
            ownerUserID: fixture.ownerID,
            name: "Second shop",
            iconSymbolName: "shippingbox.fill",
            iconColorHex: "#9A67FF",
            primaryCurrencyCode: "JPY",
            context: fixture.context
        ).channel
        let secondAsset = try InvestmentPersistenceService.createAsset(
            ownerUserID: fixture.ownerID,
            channelID: secondChannel.id,
            name: "Item B",
            currencyCode: "JPY",
            context: fixture.context
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            asset: secondAsset,
            channel: secondChannel,
            kind: .buy,
            quantity: 1,
            gross: 40,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let originalSell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(2)
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    id: originalSell.id,
                    channelID: secondChannel.id,
                    assetID: secondAsset.id,
                    kind: .sell,
                    quantity: 2,
                    grossAmountMinor: 300,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 300,
                    accountingCurrencyCode: "JPY",
                    capitalReturnWalletID: fixture.capitalWallet.id,
                    occurredAt: fixture.start.addingTimeInterval(3),
                    createdAt: originalSell.createdAt
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentAccountingError, .insufficientPosition)
        }

        let storedSell = try XCTUnwrap(fetchTrade(id: originalSell.id, fixture))
        XCTAssertEqual(storedSell.assetID, fixture.asset.id)
        XCTAssertEqual(storedSell.channelID, fixture.channel.id)
        XCTAssertEqual(storedSell.quantity, 1)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 150)
        XCTAssertNil(storedSell.deletedAt)
    }

    func testEditingExistingSellCannotChangeSellIntoBuy() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    id: sell.id,
                    channelID: fixture.channel.id,
                    assetID: fixture.asset.id,
                    kind: .buy,
                    quantity: 1,
                    grossAmountMinor: 100,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 100,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: fixture.fundingWallet.id,
                    occurredAt: fixture.start.addingTimeInterval(2),
                    createdAt: sell.createdAt
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
        }
        XCTAssertEqual(try fetchTrade(id: sell.id, fixture)?.kind, .sell)
    }

    func testDeletingBuySoftDeletesTradeAndRestoresFundingWallet() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        let result = try InvestmentPersistenceService.deleteTrade(
            ownerUserID: fixture.ownerID,
            tradeID: buy.id,
            now: fixture.start.addingTimeInterval(1),
            context: fixture.context
        )

        let storedBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
        XCTAssertNotNil(storedBuy.deletedAt)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
        XCTAssertEqual(result.deletedTradeIDs, [buy.id])
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
                .filter { $0.financialDomain == .investment }
                .allSatisfy { $0.deletedAt != nil }
        )
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .filter { $0.tradeID == buy.id }
                .allSatisfy { $0.deletedAt != nil }
        )
    }

    func testDeletingAssetWithoutHistorySoftDeletesAsset() throws {
        let fixture = try makeFixture()
        let deletedAt = fixture.start.addingTimeInterval(1)

        let deletedAsset = try InvestmentPersistenceService.deleteAsset(
            ownerUserID: fixture.ownerID,
            assetID: fixture.asset.id,
            now: deletedAt,
            context: fixture.context
        )

        XCTAssertEqual(deletedAsset.deletedAt, deletedAt)
        XCTAssertEqual(deletedAsset.updatedAt, deletedAt)
        XCTAssertEqual(fixture.asset.deletedAt, deletedAt)
    }

    func testDeletingAssetWithRemainingInventoryIsRejected() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.deleteAsset(
                ownerUserID: fixture.ownerID,
                assetID: fixture.asset.id,
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .assetHasRemainingInventory)
        }
        XCTAssertNil(fixture.asset.deletedAt)
    }

    func testDeletingSettledAssetSoftDeletesAssetAndKeepsTradeHistory() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 2,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        _ = try InvestmentPersistenceService.deleteAsset(
            ownerUserID: fixture.ownerID,
            assetID: fixture.asset.id,
            now: fixture.start.addingTimeInterval(2),
            context: fixture.context
        )

        XCTAssertNotNil(fixture.asset.deletedAt)
        XCTAssertNil(try fetchTrade(id: buy.id, fixture)?.deletedAt)
        XCTAssertNil(try fetchTrade(id: sell.id, fixture)?.deletedAt)
    }

    func testDeletingBuyRequiredByExistingSaleReturnsFriendlyError() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 75,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.deleteTrade(
                ownerUserID: fixture.ownerID,
                tradeID: buy.id,
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentAccountingError, .insufficientPosition)
            XCTAssertEqual(error.localizedDescription, L10n.investment.error.insufficientPosition)
        }
        XCTAssertNil(try fetchTrade(id: buy.id, fixture)?.deletedAt)
        XCTAssertNil(try fetchTrade(id: sell.id, fixture)?.deletedAt)
    }

    func testDeletingSellSoftDeletesTradeAndRestoresPositionCapitalAndProfit() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let result = try InvestmentPersistenceService.deleteTrade(
            ownerUserID: fixture.ownerID,
            tradeID: sell.id,
            now: fixture.start.addingTimeInterval(2),
            context: fixture.context
        )

        let storedBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
        let storedSell = try XCTUnwrap(fetchTrade(id: sell.id, fixture))
        XCTAssertNotNil(storedSell.deletedAt)
        XCTAssertEqual(storedBuy.positionQuantityAfter, 2)
        XCTAssertEqual(storedBuy.positionCostBasisAfterMinor, 100)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 0)
        XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 0)
        XCTAssertEqual(result.deletedTradeIDs, [sell.id])
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .filter { $0.tradeID == sell.id }
                .allSatisfy { $0.deletedAt != nil }
        )
    }

    func testEditingExistingTradeCannotChangeBuyIntoSell() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 200,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let editedBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 50,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    id: editedBuy.id,
                    channelID: fixture.channel.id,
                    assetID: fixture.asset.id,
                    kind: .sell,
                    quantity: 1,
                    grossAmountMinor: 70,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 70,
                    accountingCurrencyCode: "JPY",
                    capitalReturnWalletID: fixture.capitalWallet.id,
                    occurredAt: fixture.start.addingTimeInterval(2),
                    createdAt: editedBuy.createdAt
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
        }
        XCTAssertEqual(try fetchTrade(id: editedBuy.id, fixture)?.kind, .buy)
    }

    func testEditingBuyWithInsufficientNewWalletLeavesOriginalStateUnchanged() throws {
        let fixture = try makeFixture()
        let lowBalanceWallet = LedgerWallet(
            name: "Low balance",
            kind: .cash,
            iconSymbolName: "banknote.fill",
            iconColorHex: "#222222",
            currencyCode: "JPY",
            openingBalanceMinor: 10
        )
        fixture.context.insert(lowBalanceWallet)
        let original = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        XCTAssertThrowsError(
            try InvestmentPersistenceService.saveTrade(
                ownerUserID: fixture.ownerID,
                draft: InvestmentTradeDraft(
                    id: original.id,
                    channelID: fixture.channel.id,
                    assetID: fixture.asset.id,
                    kind: .buy,
                    quantity: 2,
                    grossAmountMinor: 50,
                    currencyCode: "JPY",
                    accountingGrossAmountMinor: 50,
                    accountingCurrencyCode: "JPY",
                    fundingWalletID: lowBalanceWallet.id,
                    occurredAt: fixture.start.addingTimeInterval(1),
                    createdAt: original.createdAt
                ),
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .insufficientFunds)
        }

        let stored = try XCTUnwrap(fetchTrade(id: original.id, fixture))
        XCTAssertEqual(stored.quantity, 1)
        XCTAssertEqual(stored.grossAmountMinor, 100)
        XCTAssertEqual(stored.fundingWalletID, fixture.fundingWallet.id)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
        XCTAssertEqual(try balance(lowBalanceWallet, fixture), 10)
    }

    func testEditingBuyWithinSameAssetReusesOneDerivedLedgerAndPosting() throws {
        let fixture = try makeFixture()
        let original = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 3,
            gross: 120,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let correctedDate = fixture.start.addingTimeInterval(10)

        _ = try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: original.id,
                channelID: fixture.channel.id,
                assetID: fixture.asset.id,
                kind: .buy,
                quantity: 2,
                grossAmountMinor: 90,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 90,
                accountingCurrencyCode: "JPY",
                fundingWalletID: fixture.fundingWallet.id,
                note: "Same asset correction",
                occurredAt: correctedDate,
                createdAt: original.createdAt
            ),
            rates: [],
            context: fixture.context
        )

        let fundingLedgerID = InvestmentLedgerIdentity.derivedID(eventID: original.id, component: "funding")
        let fundingPostingID = InvestmentLedgerIdentity.derivedID(eventID: original.id, component: "funding-posting")
        let activeLedgers = try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
            .filter { $0.id == fundingLedgerID && $0.deletedAt == nil }
        let activePostings = try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .filter { $0.id == fundingPostingID && $0.deletedAt == nil }
        XCTAssertEqual(activeLedgers.count, 1)
        XCTAssertEqual(activeLedgers.first?.amountMinor, 90)
        XCTAssertEqual(activePostings.count, 1)
        XCTAssertEqual(activePostings.first?.amountMinor, -90)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 910)
    }

    func testProfitTransferCanIncludeOrdinaryMoneyAboveHeldProfit() throws {
        let fixture = try makeFixture()
        let linkedWallet = LedgerWallet(
            name: "Investment Cash",
            kind: .cash,
            iconSymbolName: "banknote.fill",
            iconColorHex: "#9A67FF",
            currencyCode: "JPY",
            openingBalanceMinor: 0
        )
        fixture.context.insert(linkedWallet)
        try MistiaRecordOwnershipStore.upsert(
            entity: .wallet,
            recordID: linkedWallet.id,
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
        _ = try InvestmentPersistenceService.setLinkedWallet(
            ownerUserID: fixture.ownerID,
            linkedWalletID: linkedWallet.id,
            context: fixture.context
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        let reconciliation = try InvestmentPersistenceService.reconcileCash(
            ownerUserID: fixture.ownerID,
            requests: [
                InvestmentReconciliationRequest(
                    walletID: fixture.capitalWallet.id,
                    accountingAmountMinor: 80
                )
            ],
            context: fixture.context
        )

        let snapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        XCTAssertEqual(reconciliation.instructions.first?.accountingAmountMinor, 80)
        XCTAssertEqual(snapshot.totalMinor, 50)
        XCTAssertEqual(snapshot.locations.first { $0.walletID == fixture.capitalWallet.id }?.bookedMinor ?? 0, 0)
        XCTAssertEqual(snapshot.locations.first { $0.walletID == linkedWallet.id }?.bookedMinor, 50)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 70)
        XCTAssertEqual(try balance(linkedWallet, fixture), 80)

        let reconciliationEventID = try XCTUnwrap(reconciliation.instructions.first?.id)
        let transferPostings = try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .filter { $0.eventID == reconciliationEventID && $0.role == .cashReconciliation }
        XCTAssertEqual(transferPostings.reduce(0) { $0 + $1.accountingAmountMinor }, 0)
        XCTAssertEqual(transferPostings.map(\.accountingAmountMinor).sorted(), [-50, 50])
    }

    func testInvestmentCashSaleReconciliationAndConsumptionScenario() throws {
        let fixture = try makeFixture()
        let linkedWallet = LedgerWallet(
            name: "Investment Cash",
            kind: .cash,
            iconSymbolName: "banknote.fill",
            iconColorHex: "#9A67FF",
            currencyCode: "JPY",
            openingBalanceMinor: 0
        )
        fixture.context.insert(linkedWallet)
        try MistiaRecordOwnershipStore.upsert(
            entity: .wallet,
            recordID: linkedWallet.id,
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
        _ = try InvestmentPersistenceService.setLinkedWallet(
            ownerUserID: fixture.ownerID,
            linkedWalletID: linkedWallet.id,
            context: fixture.context
        )

        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        var snapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        XCTAssertEqual(snapshot.totalMinor, 50)
        XCTAssertEqual(snapshot.locations.first { $0.walletID == fixture.capitalWallet.id }?.bookedMinor, 50)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 150)

        _ = try InvestmentPersistenceService.reconcileCash(
            ownerUserID: fixture.ownerID,
            requests: [
                InvestmentReconciliationRequest(
                    walletID: fixture.capitalWallet.id,
                    accountingAmountMinor: 50
                )
            ],
            context: fixture.context
        )
        snapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        XCTAssertEqual(snapshot.unreconciledMinor, 0)
        XCTAssertEqual(snapshot.locations.first { $0.walletID == fixture.capitalWallet.id }?.bookedMinor ?? 0, 0)
        XCTAssertEqual(snapshot.locations.first { $0.walletID == linkedWallet.id }?.bookedMinor, 50)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 100)
        XCTAssertEqual(try balance(linkedWallet, fixture), 50)

        let preview = try InvestmentPersistenceService.fundUsagePreview(
            ownerUserID: fixture.ownerID,
            wallet: linkedWallet,
            requestedMinor: 20,
            visibleWalletBalanceMinor: 50,
            context: fixture.context
        )
        XCTAssertEqual(preview.bookedToUseMinor, 20)
        XCTAssertEqual(preview.remainingInvestmentMinor, 30)
        let expense = LedgerTransaction(
            primaryKind: .expense,
            title: "Use investment cash",
            amountMinor: 20,
            sourceCurrencyCode: "JPY",
            occurredAt: fixture.start.addingTimeInterval(2),
            sourceWallet: linkedWallet
        )
        fixture.context.insert(expense)
        _ = try InvestmentPersistenceService.recordFundUsage(
            ownerUserID: fixture.ownerID,
            transaction: expense,
            preview: preview,
            context: fixture.context
        )
        try fixture.context.save()
        snapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        XCTAssertEqual(snapshot.totalMinor, 30)

        _ = try InvestmentPersistenceService.clearFundUsage(
            ownerUserID: fixture.ownerID,
            transactionID: expense.id,
            context: fixture.context
        )
        try fixture.context.save()
        snapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        XCTAssertEqual(snapshot.totalMinor, 50)

        let creditCard = LedgerWallet(
            name: "Card",
            kind: .creditCard,
            iconSymbolName: "creditcard.fill",
            iconColorHex: "#222222",
            currencyCode: "JPY",
            openingBalanceMinor: 0
        )
        fixture.context.insert(creditCard)
        try MistiaRecordOwnershipStore.upsert(
            entity: .wallet,
            recordID: creditCard.id,
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
        let cardPayment = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Pay card",
            amountMinor: 20,
            sourceCurrencyCode: "JPY",
            destinationCurrencyCode: "JPY",
            destinationAmountMinor: 20,
            occurredAt: fixture.start.addingTimeInterval(3),
            sourceWallet: linkedWallet,
            destinationWallet: creditCard
        )
        fixture.context.insert(cardPayment)
        _ = try InvestmentPersistenceService.recordFundUsage(
            ownerUserID: fixture.ownerID,
            transaction: cardPayment,
            preview: preview,
            context: fixture.context
        )
        try fixture.context.save()
        snapshot = try InvestmentPersistenceService.cashAllocationSnapshot(
            ownerUserID: fixture.ownerID,
            accountingCurrencyCode: "JPY",
            context: fixture.context
        )
        XCTAssertEqual(snapshot.totalMinor, 30)
        XCTAssertNil(snapshot.locations.first { $0.walletID == creditCard.id })

        let remoteSnapshot = try MistiaSyncLocalStore.exportSnapshot(
            for: fixture.ownerID,
            from: fixture.container
        )
        XCTAssertEqual(
            remoteSnapshot.wallets.first {
                $0.id == InvestmentSystemWalletIdentity.walletID(ownerUserID: fixture.ownerID)
            }?.investmentLinkedWalletID,
            linkedWallet.id
        )
        XCTAssertTrue(
            remoteSnapshot.investmentPostings.contains {
                $0.cashBucketRawValue == InvestmentCashBucket.booked.rawValue
                    && $0.cashOriginRawValue != nil
            }
        )
    }

    func testTargetedReconciliationRepairsOnlyRequestedAssetHistory() throws {
        let fixture = try makeFixture()
        let secondAsset = try InvestmentPersistenceService.createAsset(
            ownerUserID: fixture.ownerID,
            channelID: fixture.channel.id,
            name: "Item B",
            currencyCode: "JPY",
            context: fixture.context
        )
        let firstBuy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let secondBuy = try saveTrade(
            fixture: fixture,
            asset: secondAsset,
            kind: .buy,
            quantity: 3,
            gross: 300,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let first = try XCTUnwrap(fetchTrade(id: firstBuy.id, fixture))
        let second = try XCTUnwrap(fetchTrade(id: secondBuy.id, fixture))
        let secondUpdatedAt = second.updatedAt
        let secondCostBasis = second.positionCostBasisAfterMinor

        first.positionCostBasisAfterMinor = -1
        try fixture.context.save()

        let result = try InvestmentPersistenceService.reconcileTrades(
            assetIDs: [fixture.asset.id],
            ownerUserID: fixture.ownerID,
            now: fixture.start.addingTimeInterval(100),
            context: fixture.context
        )

        XCTAssertEqual(try fetchTrade(id: firstBuy.id, fixture)?.positionCostBasisAfterMinor, 100)
        XCTAssertEqual(try fetchTrade(id: secondBuy.id, fixture)?.positionCostBasisAfterMinor, secondCostBasis)
        XCTAssertEqual(try fetchTrade(id: secondBuy.id, fixture)?.updatedAt, secondUpdatedAt)
        XCTAssertTrue(result.tradeIDs.contains(firstBuy.id))
        XCTAssertFalse(result.tradeIDs.contains(secondBuy.id))
    }

    func testTargetedReconciliationWithNoAssetIDsDoesNoWork() throws {
        let fixture = try makeFixture()
        _ = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 1,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )

        let result = try InvestmentPersistenceService.reconcileTrades(
            assetIDs: [],
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )

        XCTAssertEqual(result, InvestmentPersistenceResult())
    }

    func testRepeatedTargetedReconciliationIsANoOpAndPreservesDerivedTimestamps() throws {
        let fixture = try makeFixture()
        let buy = try saveTrade(
            fixture: fixture,
            kind: .buy,
            quantity: 2,
            gross: 100,
            fundingWalletID: fixture.fundingWallet.id,
            occurredAt: fixture.start
        )
        let sell = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 80,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )
        let ledgerBefore = Dictionary(
            uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
                .map { ($0.id, $0.updatedAt) }
        )
        let postingBefore = Dictionary(
            uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                .map { ($0.id, $0.updatedAt) }
        )
        let tradeBefore = Dictionary(
            uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<InvestmentTrade>())
                .map { ($0.id, $0.updatedAt) }
        )

        let result = try InvestmentPersistenceService.reconcileTrades(
            assetIDs: [fixture.asset.id],
            ownerUserID: fixture.ownerID,
            now: fixture.start.addingTimeInterval(1_000),
            context: fixture.context
        )

        XCTAssertEqual(result, InvestmentPersistenceResult())
        XCTAssertFalse(fixture.context.hasChanges)
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
                    .map { ($0.id, $0.updatedAt) }
            ),
            ledgerBefore
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
                    .map { ($0.id, $0.updatedAt) }
            ),
            postingBefore
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<InvestmentTrade>())
                    .map { ($0.id, $0.updatedAt) }
            ),
            tradeBefore
        )
        XCTAssertEqual(try fetchTrade(id: buy.id, fixture)?.positionCostBasisAfterMinor, 100)
        XCTAssertEqual(try fetchTrade(id: sell.id, fixture)?.realizedProfitLossMinor, 30)
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 80)
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let ownerID: UUID
        let channel: InvestmentChannel
        let asset: InvestmentAsset
        let fundingWallet: LedgerWallet
        let capitalWallet: LedgerWallet
        let start: Date
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema(versionedSchema: MistiaSchemaV11.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let ownerID = UUID()
        let start = Date(timeIntervalSince1970: 100_000)
        let fundingWallet = LedgerWallet(
            name: "Funding",
            kind: .cash,
            iconSymbolName: "banknote.fill",
            iconColorHex: "#000000",
            currencyCode: "JPY",
            openingBalanceMinor: 1_000
        )
        let capitalWallet = LedgerWallet(
            name: "Capital",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#000000",
            currencyCode: "JPY",
            openingBalanceMinor: 0
        )
        context.insert(fundingWallet)
        context.insert(capitalWallet)
        let created = try InvestmentPersistenceService.createChannel(
            ownerUserID: ownerID,
            name: "Shop",
            iconSymbolName: "storefront.fill",
            iconColorHex: "#9A67FF",
            primaryCurrencyCode: "JPY",
            context: context
        )
        let asset = try InvestmentPersistenceService.createAsset(
            ownerUserID: ownerID,
            channelID: created.channel.id,
            name: "Item A",
            currencyCode: "JPY",
            context: context
        )
        return Fixture(
            container: container,
            context: context,
            ownerID: ownerID,
            channel: created.channel,
            asset: asset,
            fundingWallet: fundingWallet,
            capitalWallet: capitalWallet,
            start: start
        )
    }

    @discardableResult
    private func saveTrade(
        fixture: Fixture,
        asset: InvestmentAsset? = nil,
        channel: InvestmentChannel? = nil,
        kind: InvestmentTradeKind,
        quantity: Decimal,
        unit: String? = nil,
        gross: Int64,
        fundingWalletID: UUID? = nil,
        capitalWalletID: UUID? = nil,
        occurredAt: Date,
        rates: [MistiaExchangeRate] = []
    ) throws -> InvestmentTradeDraft {
        let resolvedAsset = asset ?? fixture.asset
        let resolvedChannel = channel ?? fixture.channel
        let draft = InvestmentTradeDraft(
            channelID: resolvedChannel.id,
            assetID: resolvedAsset.id,
            kind: kind,
            quantity: quantity,
            unitLabel: unit,
            grossAmountMinor: gross,
            currencyCode: resolvedAsset.currencyCode,
            accountingGrossAmountMinor: gross,
            accountingCurrencyCode: "JPY",
            fundingWalletID: fundingWalletID,
            capitalReturnWalletID: capitalWalletID,
            occurredAt: occurredAt,
            createdAt: occurredAt
        )
        _ = try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: draft,
            rates: rates,
            context: fixture.context
        )
        return draft
    }

    private func fetchTrade(id: UUID, _ fixture: Fixture) throws -> InvestmentTrade? {
        try fixture.context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in trade.id == id }
            )
        ).first
    }

    private func fetchSystemWallet(_ fixture: Fixture) throws -> LedgerWallet? {
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: fixture.ownerID)
        return try fixture.context.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate<LedgerWallet> { wallet in wallet.id == id }
            )
        ).first
    }

    private func balance(_ wallet: LedgerWallet, _ fixture: Fixture) throws -> Int64 {
        try InvestmentPersistenceService.currentBalance(wallet: wallet, context: fixture.context)
    }
}
