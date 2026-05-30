import XCTest
@testable import MistiaCoreLogic

final class TransactionSearchLogicTests: XCTestCase {
    func testSearchFiltersIgnoreScreenFiltersAndUseAllTransactions() throws {
        let filters = try XCTUnwrap(TransactionSearchLogic.filters(for: "  coffee  "))

        XCTAssertEqual(filters.timeScope, .allTime)
        XCTAssertEqual(filters.statusScope, .all)
        XCTAssertNil(filters.walletID)
        XCTAssertNil(filters.categoryID)
        XCTAssertNil(filters.transferSubtype)
        XCTAssertNil(filters.minAmountMinor)
        XCTAssertNil(filters.maxAmountMinor)
        XCTAssertFalse(filters.isAdjustmentOnly)
        XCTAssertEqual(filters.searchText, "  coffee  ")
    }

    func testSearchFiltersRequireNonBlankQuery() {
        XCTAssertNil(TransactionSearchLogic.filters(for: ""))
        XCTAssertNil(TransactionSearchLogic.filters(for: "   "))
    }
}
