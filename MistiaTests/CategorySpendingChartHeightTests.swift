import XCTest
@testable import Mistia

final class CategorySpendingChartHeightTests: XCTestCase {
    func testPreferredRootHeightExpandsForOverflowLegendRows() {
        let month = OverviewCategorySpendingMonthSnapshot(
            monthStart: Date(timeIntervalSince1970: 1_770_000_000),
            title: "05/2026",
            currencyCode: "JPY",
            slices: (0..<7).map { index in
                OverviewCategorySpendingSlice(
                    id: "category-\(index)",
                    categoryID: UUID(),
                    name: "Category \(index)",
                    iconSymbolName: "circle.fill",
                    colorHex: "#2DAA9E",
                    amountMinor: Int64(1_000 + index),
                    childSlices: []
                )
            }
        )

        XCTAssertEqual(
            MistiaCategorySpendingChartView.preferredRootHeight(for: month),
            MistiaCategorySpendingChartView.estimatedHeight(visibleSliceCount: 6)
        )
    }
}
