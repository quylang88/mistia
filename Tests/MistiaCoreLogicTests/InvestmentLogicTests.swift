import XCTest
@testable import MistiaCoreLogic

final class InvestmentLogicTests: XCTestCase {
    func testBuyOneHundredThenSellOneHundredFiftyReleasesCapitalAndRealizesProfit() throws {
        let buyID = UUID()
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(id: buyID, kind: .buy, quantity: 1, gross: 100, occurredAt: start),
                trade(id: sellID, kind: .sell, quantity: 1, gross: 150, occurredAt: start.addingTimeInterval(1))
            ]
        )

        XCTAssertEqual(calculations[buyID]?.positionCostBasisAfterMinor, 100)
        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 100)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, 50)
        XCTAssertEqual(calculations[sellID]?.positionQuantityAfter, 0)
        XCTAssertEqual(calculations[sellID]?.positionCostBasisAfterMinor, 0)
    }

    func testLossReturnsCostBasisAndMakesInvestmentWalletLegNegative() throws {
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 2_000)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(kind: .buy, quantity: 1, gross: 100, occurredAt: start),
                trade(id: sellID, kind: .sell, quantity: 1, gross: 70, occurredAt: start.addingTimeInterval(1))
            ]
        )

        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 100)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, -30)
    }

    func testWeightedAveragePartialSaleIncludesFees() throws {
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 3_000)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(kind: .buy, quantity: 2, gross: 200, fee: 10, occurredAt: start),
                trade(kind: .buy, quantity: 1, gross: 150, occurredAt: start.addingTimeInterval(1)),
                trade(id: sellID, kind: .sell, quantity: 1, gross: 160, fee: 5, occurredAt: start.addingTimeInterval(2))
            ]
        )

        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 120)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, 35)
        XCTAssertEqual(calculations[sellID]?.positionQuantityAfter, 2)
        XCTAssertEqual(calculations[sellID]?.positionCostBasisAfterMinor, 240)
    }

    func testBackdatedTradeRecalculatesLaterSale() throws {
        let laterBuyID = UUID()
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 4_000)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(id: laterBuyID, kind: .buy, quantity: 1, gross: 200, occurredAt: start.addingTimeInterval(2)),
                trade(id: sellID, kind: .sell, quantity: 1, gross: 180, occurredAt: start.addingTimeInterval(3)),
                trade(kind: .buy, quantity: 1, gross: 100, occurredAt: start)
            ]
        )

        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 150)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, 30)
        XCTAssertEqual(calculations[sellID]?.positionCostBasisAfterMinor, 150)
    }

    func testOversellRejectsEntireRecalculation() {
        XCTAssertThrowsError(
            try InvestmentAccountingEngine.recalculate(
                trades: [
                    trade(kind: .buy, quantity: 1, gross: 100),
                    trade(kind: .sell, quantity: 2, gross: 200)
                ]
            )
        ) { error in
            XCTAssertEqual(error as? InvestmentAccountingError, .insufficientPosition)
        }
    }

    func testOpeningPositionDoesNotCreateProfitUntilSale() throws {
        let sellID = UUID()
        let calculations = try InvestmentAccountingEngine.calculationMap(
            openingPosition: InvestmentOpeningPosition(quantity: 2, costBasisMinor: 100),
            trades: [trade(id: sellID, kind: .sell, quantity: 1, gross: 80)]
        )

        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 50)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, 30)
        XCTAssertEqual(calculations[sellID]?.positionCostBasisAfterMinor, 50)
    }

    func testSummaryFallsBackToCostBasisWithoutValuation() {
        let tradeID = UUID()
        let date = Date(timeIntervalSince1970: 5_000)
        let summary = InvestmentSummaryLogic.summary(
            positions: [
                InvestmentAssetPositionSnapshot(
                    id: UUID(),
                    channelID: UUID(),
                    quantity: 1,
                    remainingCostBasisMinor: 100,
                    marketValueMinor: nil
                )
            ],
            trades: [
                InvestmentTradeCalculation(
                    id: tradeID,
                    releasedCostBasisMinor: 50,
                    realizedProfitLossMinor: 20,
                    positionQuantityAfter: 1,
                    positionCostBasisAfterMinor: 100
                )
            ],
            tradeDates: [tradeID: date],
            period: DateInterval(start: date.addingTimeInterval(-1), end: date.addingTimeInterval(1)),
            investmentWalletBalanceMinor: -30
        )

        XCTAssertEqual(summary.investedCapitalMinor, 100)
        XCTAssertEqual(summary.marketValueMinor, 100)
        XCTAssertEqual(summary.unrealizedProfitLossMinor, 0)
        XCTAssertEqual(summary.realizedProfitLossMinor, 20)
        XCTAssertEqual(summary.investmentWalletBalanceMinor, -30)
    }

    func testSystemWalletIDIsStableAndOwnerScoped() {
        let ownerA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let ownerB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerA),
            InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerA)
        )
        XCTAssertNotEqual(
            InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerA),
            InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerB)
        )
        XCTAssertLessThanOrEqual(
            InvestmentSystemWalletIdentity.canonicalSortOrder,
            Int(Int32.max)
        )
    }

    func testTradesAtSameInstantUseStableUUIDOrder() throws {
        let buyID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let sellID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let instant = Date(timeIntervalSince1970: 6_000)

        let calculations = try InvestmentAccountingEngine.recalculate(
            trades: [
                trade(id: sellID, kind: .sell, quantity: 1, gross: 120, occurredAt: instant, createdAt: instant),
                trade(id: buyID, kind: .buy, quantity: 1, gross: 100, occurredAt: instant, createdAt: instant)
            ]
        )

        XCTAssertEqual(calculations.map(\.id), [buyID, sellID])
        XCTAssertEqual(calculations.last?.realizedProfitLossMinor, 20)
    }

    private func trade(
        id: UUID = UUID(),
        kind: InvestmentTradeKind,
        quantity: Decimal,
        gross: Int64,
        fee: Int64 = 0,
        occurredAt: Date = Date(timeIntervalSince1970: 10_000),
        createdAt: Date = Date(timeIntervalSince1970: 10_000)
    ) -> InvestmentTradeInput {
        InvestmentTradeInput(
            id: id,
            kind: kind,
            quantity: quantity,
            accountingGrossAmountMinor: gross,
            accountingFeeMinor: fee,
            occurredAt: occurredAt,
            createdAt: createdAt
        )
    }
}
