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

    func testFIFOPartialSaleConsumesOldestLotFirst() throws {
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 3_000)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(kind: .buy, quantity: 2, gross: 200, occurredAt: start),
                trade(kind: .buy, quantity: 1, gross: 150, occurredAt: start.addingTimeInterval(1)),
                trade(id: sellID, kind: .sell, quantity: 1, gross: 160, occurredAt: start.addingTimeInterval(2))
            ]
        )

        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 100)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, 60)
        XCTAssertEqual(calculations[sellID]?.positionQuantityAfter, 2)
        XCTAssertEqual(calculations[sellID]?.positionCostBasisAfterMinor, 250)
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

        XCTAssertEqual(calculations[sellID]?.releasedCostBasisMinor, 100)
        XCTAssertEqual(calculations[sellID]?.realizedProfitLossMinor, 80)
        XCTAssertEqual(calculations[sellID]?.positionCostBasisAfterMinor, 200)
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

    func testFIFOSaleAcrossLotsUsesOldestCosts() throws {
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 4_500)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(kind: .buy, quantity: 10, gross: 1_000, occurredAt: start),
                trade(kind: .buy, quantity: 10, gross: 2_000, occurredAt: start.addingTimeInterval(1)),
                trade(id: sellID, kind: .sell, quantity: 12, gross: 1_800, occurredAt: start.addingTimeInterval(2))
            ]
        )
        let remaining = try XCTUnwrap(calculations[sellID])

        XCTAssertEqual(remaining.releasedCostBasisMinor, 1_400)
        XCTAssertEqual(remaining.realizedProfitLossMinor, 400)
        XCTAssertEqual(remaining.positionQuantityAfter, 8)
        XCTAssertEqual(remaining.positionCostBasisAfterMinor, 1_600)
    }

    func testFIFOPartialLotRoundingPreservesTotalCost() throws {
        let firstSellID = UUID()
        let finalSellID = UUID()
        let start = Date(timeIntervalSince1970: 4_600)
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(kind: .buy, quantity: 3, gross: 100, occurredAt: start),
                trade(id: firstSellID, kind: .sell, quantity: 1, gross: 50, occurredAt: start.addingTimeInterval(1)),
                trade(id: finalSellID, kind: .sell, quantity: 2, gross: 100, occurredAt: start.addingTimeInterval(2))
            ]
        )

        XCTAssertEqual(calculations[firstSellID]?.releasedCostBasisMinor, 33)
        XCTAssertEqual(calculations[firstSellID]?.positionCostBasisAfterMinor, 67)
        XCTAssertEqual(calculations[finalSellID]?.releasedCostBasisMinor, 67)
        XCTAssertEqual(calculations[finalSellID]?.positionCostBasisAfterMinor, 0)
    }

    func testInvestmentMonthIntervalUsesSelectedMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let selected = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 2, day: 18))
        )

        let interval = InvestmentPeriodLogic.monthInterval(
            containing: selected,
            calendar: calendar
        )

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: interval.start),
            DateComponents(year: 2025, month: 2, day: 1)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: interval.end),
            DateComponents(year: 2025, month: 3, day: 1)
        )
    }

    func testInvestmentMonthNavigationMovesFromNormalizedMonthStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let selected = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 31))
        )

        let next = InvestmentPeriodLogic.month(
            byAdding: 1,
            to: selected,
            calendar: calendar
        )

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: next),
            DateComponents(year: 2025, month: 2, day: 1)
        )
    }

    func testProductSearchMatchesNameOrChannelWithoutVietnameseDiacritics() {
        XCTAssertTrue(
            InvestmentAssetSearchLogic.matches(
                productName: "Thẻ hiếm",
                channelName: "Đồ sưu tầm",
                query: "the hiem"
            )
        )
        XCTAssertTrue(
            InvestmentAssetSearchLogic.matches(
                productName: "Card A",
                channelName: "Đồ sưu tầm",
                query: "do suu"
            )
        )
        XCTAssertFalse(
            InvestmentAssetSearchLogic.matches(
                productName: "Card A",
                channelName: "Pokémon",
                query: "figure"
            )
        )
        XCTAssertTrue(
            InvestmentAssetSearchLogic.matches(
                values: ["Card A", "Đồ sưu tầm", "Hàng khuyến mãi"],
                query: "khuyen mai"
            )
        )
    }

    func testSummaryContainsOnlyRemainingInventoryCostAndRealizedProfit() {
        let tradeID = UUID()
        let date = Date(timeIntervalSince1970: 5_000)
        let summary = InvestmentSummaryLogic.summary(
            positions: [
                InvestmentAssetPositionSnapshot(
                    id: UUID(),
                    channelID: UUID(),
                    quantity: 1,
                    remainingCostBasisMinor: 100,
                    openLotCount: 1
                )
            ],
            trades: [
                InvestmentTradeCalculation(
                    id: tradeID,
                    releasedCostBasisMinor: 50,
                    realizedProfitLossMinor: 20,
                    positionQuantityAfter: 1,
                    positionCostBasisAfterMinor: 100,
                    openLotCountAfter: 1
                )
            ],
            tradeDates: [tradeID: date],
            period: DateInterval(start: date.addingTimeInterval(-1), end: date.addingTimeInterval(1)),
            investmentWalletBalanceMinor: -30
        )

        XCTAssertEqual(summary.remainingInventoryCostMinor, 100)
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

    func testSaleWithZeroAmountRecordsTotalLossAndClearsPosition() throws {
        let buyID = UUID()
        let lossSellID = UUID()
        let start = Date(timeIntervalSince1970: 7_000)

        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(id: buyID, kind: .buy, quantity: 5, gross: 500, occurredAt: start),
                trade(id: lossSellID, kind: .sell, quantity: 5, gross: 0, occurredAt: start.addingTimeInterval(1))
            ]
        )

        let saleCalc = try XCTUnwrap(calculations[lossSellID])
        XCTAssertEqual(saleCalc.releasedCostBasisMinor, 500)
        XCTAssertEqual(saleCalc.realizedProfitLossMinor, -500)
        XCTAssertEqual(saleCalc.positionQuantityAfter, 0)
        XCTAssertEqual(saleCalc.positionCostBasisAfterMinor, 0)
        XCTAssertEqual(saleCalc.openLotCountAfter, 0)
    }

    func testPartialLossSaleConsumesQuantityAndCostBasisCorrectly() throws {
        let buyID = UUID()
        let lossSellID = UUID()
        let start = Date(timeIntervalSince1970: 8_000)

        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(id: buyID, kind: .buy, quantity: 10, gross: 1_000, occurredAt: start),
                trade(id: lossSellID, kind: .sell, quantity: 4, gross: 0, occurredAt: start.addingTimeInterval(1))
            ]
        )

        let saleCalc = try XCTUnwrap(calculations[lossSellID])
        XCTAssertEqual(saleCalc.releasedCostBasisMinor, 400)
        XCTAssertEqual(saleCalc.realizedProfitLossMinor, -400)
        XCTAssertEqual(saleCalc.positionQuantityAfter, 6)
        XCTAssertEqual(saleCalc.positionCostBasisAfterMinor, 600)
        XCTAssertEqual(saleCalc.openLotCountAfter, 1)
    }

    func testPromotionalFreeBuyAddsZeroCostInventoryAndSaleBecomesProfit() throws {
        let freeBuyID = UUID()
        let sellID = UUID()
        let start = Date(timeIntervalSince1970: 9_000)

        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: [
                trade(id: freeBuyID, kind: .buy, quantity: 3, gross: 0, occurredAt: start),
                trade(id: sellID, kind: .sell, quantity: 2, gross: 80, occurredAt: start.addingTimeInterval(1))
            ]
        )

        let freeBuy = try XCTUnwrap(calculations[freeBuyID])
        XCTAssertEqual(freeBuy.positionQuantityAfter, 3)
        XCTAssertEqual(freeBuy.positionCostBasisAfterMinor, 0)

        let sale = try XCTUnwrap(calculations[sellID])
        XCTAssertEqual(sale.releasedCostBasisMinor, 0)
        XCTAssertEqual(sale.realizedProfitLossMinor, 80)
        XCTAssertEqual(sale.positionQuantityAfter, 1)
        XCTAssertEqual(sale.positionCostBasisAfterMinor, 0)
    }

    func testSummaryExcludesSettledSnapshotsEvenIfStoredCostIsStale() {
        let summary = InvestmentSummaryLogic.summary(
            positions: [
                InvestmentAssetPositionSnapshot(
                    id: UUID(),
                    channelID: UUID(),
                    quantity: 2,
                    remainingCostBasisMinor: 120,
                    openLotCount: 1
                ),
                InvestmentAssetPositionSnapshot(
                    id: UUID(),
                    channelID: UUID(),
                    quantity: 0,
                    remainingCostBasisMinor: 999,
                    openLotCount: 0
                )
            ],
            trades: [],
            tradeDates: [:],
            period: nil,
            investmentWalletBalanceMinor: 0
        )

        XCTAssertEqual(summary.remainingInventoryCostMinor, 120)
    }

    private func trade(
        id: UUID = UUID(),
        kind: InvestmentTradeKind,
        quantity: Decimal,
        gross: Int64,
        occurredAt: Date = Date(timeIntervalSince1970: 10_000),
        createdAt: Date = Date(timeIntervalSince1970: 10_000)
    ) -> InvestmentTradeInput {
        InvestmentTradeInput(
            id: id,
            kind: kind,
            quantity: quantity,
            accountingGrossAmountMinor: gross,
            occurredAt: occurredAt,
            createdAt: createdAt
        )
    }
}
