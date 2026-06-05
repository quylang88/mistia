import Foundation
import XCTest
@testable import Mistia

final class CurrencyLogicPerformanceTests: XCTestCase {
    func testExchangeRateIndexConvertsDirectAndInversePairs() {
        let index = MistiaExchangeRateIndex(rates: [
            makeRate(base: "JPY", quote: "VND", decimal: "165")
        ])

        XCTAssertEqual(
            MistiaCurrencyLogic.convertedMinorAmount(
                100,
                from: "JPY",
                to: "VND",
                rateIndex: index
            ),
            16_500
        )
        XCTAssertEqual(
            MistiaCurrencyLogic.convertedMinorAmount(
                16_500,
                from: "VND",
                to: "JPY",
                rateIndex: index
            ),
            100
        )
    }

    func testExchangeRateIndexPreservesFirstMatchingRateSemantics() {
        let index = MistiaExchangeRateIndex(rates: [
            makeRate(base: "JPY", quote: "VND", decimal: "165"),
            makeRate(base: "JPY", quote: "VND", decimal: "200")
        ])

        XCTAssertEqual(
            MistiaCurrencyLogic.convertedMinorAmount(
                100,
                from: "JPY",
                to: "VND",
                rateIndex: index
            ),
            16_500
        )
    }

    private func makeRate(
        base: String,
        quote: String,
        decimal: String
    ) -> MistiaExchangeRate {
        MistiaExchangeRate(
            baseCurrencyCode: base,
            quoteCurrencyCode: quote,
            rateDecimalString: decimal,
            provider: "test",
            fetchedAt: Date(timeIntervalSince1970: 1_774_051_200),
            rateDate: "2026-03-21"
        )
    }
}
