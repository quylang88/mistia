import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class InvestmentPersistenceTests: XCTestCase {
    func testBuyAndProfitableSaleSplitCapitalAndProfitAcrossWallets() throws {
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
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 100)
        XCTAssertEqual(try balance(systemWallet, fixture), 50)

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

    func testLossCanMakeInvestmentWalletNegativeWhileReturningFullCostBasis() throws {
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
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 100)
        XCTAssertEqual(try balance(systemWallet, fixture), -30)
    }

    func testOutboundTransferCannotExceedPositiveInvestmentBalance() throws {
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
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1)
        )

        _ = try InvestmentPersistenceService.createOutboundTransfer(
            ownerUserID: fixture.ownerID,
            destinationWalletID: fixture.capitalWallet.id,
            sourceAmountMinor: 40,
            destinationAmountMinor: 40,
            rates: [],
            context: fixture.context
        )
        let systemWallet = try XCTUnwrap(fetchSystemWallet(fixture))
        XCTAssertEqual(try balance(systemWallet, fixture), 10)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 140)

        XCTAssertThrowsError(
            try InvestmentPersistenceService.createOutboundTransfer(
                ownerUserID: fixture.ownerID,
                destinationWalletID: fixture.capitalWallet.id,
                sourceAmountMinor: 11,
                destinationAmountMinor: 11,
                rates: [],
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .transferExceedsPositiveBalance)
        }
    }

    func testCrossCurrencyOutboundTransferUsesExactDestinationSnapshot() throws {
        let fixture = try makeFixture()
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
            occurredAt: fixture.start
        )
        _ = try saveTrade(
            fixture: fixture,
            kind: .sell,
            quantity: 1,
            gross: 150,
            capitalWalletID: fixture.capitalWallet.id,
            occurredAt: fixture.start.addingTimeInterval(1),
            rates: rates
        )

        _ = try InvestmentPersistenceService.createOutboundTransfer(
            ownerUserID: fixture.ownerID,
            destinationWalletID: fixture.capitalWallet.id,
            sourceAmountMinor: 10,
            destinationAmountMinor: 20,
            rates: rates,
            context: fixture.context
        )

        XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 40)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 220)
        XCTAssertThrowsError(
            try InvestmentPersistenceService.createOutboundTransfer(
                ownerUserID: fixture.ownerID,
                destinationWalletID: fixture.capitalWallet.id,
                sourceAmountMinor: 10,
                destinationAmountMinor: 21,
                rates: rates,
                context: fixture.context
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
        }
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
        XCTAssertEqual(recalculatedSell.releasedCostBasisMinor, 150)
        XCTAssertEqual(recalculatedSell.realizedProfitLossMinor, 30)
        let systemWallet = try XCTUnwrap(fetchSystemWallet(fixture))
        XCTAssertEqual(try balance(systemWallet, fixture), 30)
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
            storedSale.accountingGrossAmountMinor - storedSale.accountingFeeMinor
        )
        XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 800)
        XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 200)
        XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 51)
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

    func testSyncExportsOutboundTransferButNeverServerDerivedLedgerOrPostings() throws {
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

        let transferResult = try InvestmentPersistenceService.createOutboundTransfer(
            ownerUserID: fixture.ownerID,
            destinationWalletID: fixture.capitalWallet.id,
            sourceAmountMinor: 10,
            destinationAmountMinor: 10,
            rates: [],
            context: fixture.context
        )
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
            return XCTFail("Expected the outbound investment transfer to remain uploadable")
        }
        XCTAssertEqual(row.settlementRoleRawValue, InvestmentLedgerLegRole.investmentTransfer.rawValue)
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
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<InvestmentValuation>()).isEmpty)
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
        let schema = Schema(versionedSchema: MistiaSchemaV7.self)
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
            symbol: nil,
            currencyCode: "JPY",
            openingQuantity: 0,
            openingCostMinor: 0,
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
        kind: InvestmentTradeKind,
        quantity: Decimal,
        gross: Int64,
        fundingWalletID: UUID? = nil,
        capitalWalletID: UUID? = nil,
        occurredAt: Date,
        rates: [MistiaExchangeRate] = []
    ) throws -> InvestmentTradeDraft {
        let draft = InvestmentTradeDraft(
            channelID: fixture.channel.id,
            assetID: fixture.asset.id,
            kind: kind,
            quantity: quantity,
            grossAmountMinor: gross,
            currencyCode: "JPY",
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
