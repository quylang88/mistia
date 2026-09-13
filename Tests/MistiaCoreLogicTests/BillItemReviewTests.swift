import XCTest
@testable import MistiaCoreLogic

final class BillItemReviewTests: XCTestCase {
    func testCainzReceiptReconcilesIncludingBulkDiscount() {
        let amounts: [Int64] = [2480, 1280, 348, 298, 148, 48, 798, 128, 2780, 2280]
        let items = amounts.enumerated().map { index, amount in
            BillItemAnalysisItem(lineID: "line-\(index)", originalName: "Item \(index)",
                                 quantity: index >= 8 ? 10 : nil,
                                 originalAmountMinor: index == 8 ? 2980 : amount,
                                 discountAmountMinor: index == 8 ? 200 : 0,
                                 finalAmountMinor: amount, confidence: 0.95)
        }
        let result = BillItemAnalysisResult(totalMinor: 10588, confidence: 0.95, items: items)
        XCTAssertEqual(result.itemsTotalMinor, 10588)
        XCTAssertEqual(result.totalDifferenceMinor, 0)
        XCTAssertFalse(result.requiresReview)
        XCTAssertEqual(items.reduce(0) { $0 + ($1.quantity ?? 1) }, 28)
    }

    func testMismatchBlocksReviewCompletionWithoutChangingMoney() {
        let item = BillItemAnalysisItem(lineID: "pen", originalName: "ボールペン替芯", finalAmountMinor: 128, confidence: 0.99)
        let result = BillItemAnalysisResult(totalMinor: 48, confidence: 0.99, items: [item])
        XCTAssertTrue(result.requiresReview)
        XCTAssertEqual(result.totalDifferenceMinor, 80)
        XCTAssertEqual(result.items[0].finalAmountMinor, 128)
    }

    func testMatchingTotalDoesNotHideUncertainSourceOrInvalidDiscountArithmetic() {
        var item = BillItemAnalysisItem(lineID: "softymo", originalName: "ソフティモ", originalAmountMinor: 2980,
                                       discountAmountMinor: 200, finalAmountMinor: 2780, confidence: 0.99, missingFields: ["sourceText"])
        XCTAssertTrue(BillItemAnalysisResult(totalMinor: 2780, confidence: 0.99, items: [item]).requiresReview)
        item.missingFields = []
        item.originalAmountMinor = 3000
        XCTAssertTrue(BillItemAnalysisResult(totalMinor: 2780, confidence: 0.99, items: [item]).requiresReview)
    }

    func testLegacyResponseStillDecodesAndDuplicateIDsStayReviewable() throws {
        let data = Data(#"{"total_minor":96,"confidence":0.9,"items":[{"line_id":"pen","original_name":"Pen","final_amount_minor":48},{"line_id":"pen","original_name":"Pen","final_amount_minor":48}]}"#.utf8)
        let result = try JSONDecoder().decode(BillItemAnalysisResult.self, from: data)
        XCTAssertNil(result.items[0].rawLineText)
        XCTAssertTrue(result.requiresReview)
        let validated = result.validated(categoryIDs: [], walletIDs: [])
        XCTAssertEqual(Set(validated.items.map(\.lineID)).count, 2)
        XCTAssertTrue(validated.requiresReview)
    }

    func testOverflowingTotalIsRejectedAndFullyDiscountedPurchaseIsValid() {
        let item = BillItemAnalysisItem(lineID: "big", originalName: "Big", finalAmountMinor: .max, confidence: 0.8)
        let result = BillItemAnalysisResult(totalMinor: .max, confidence: 0.8, items: [item, item])
        XCTAssertNil(result.itemsTotalMinor)
        XCTAssertTrue(result.requiresReview)
        let free = BillItemAnalysisItem(lineID: "free", originalName: "Free", originalAmountMinor: 300,
                                       discountAmountMinor: 300, finalAmountMinor: 0, confidence: 0.9)
        XCTAssertFalse(free.requiresReview)
    }
}

extension BillItemReviewTests {
    func testManualCorrectionKeepsExplicitRowTotalsAndClearsReviewedFields() throws {
        let item = BillItemAnalysisItem(lineID: "softymo", originalName: "ソフティモ", quantity: 298, originalAmountMinor: 2980,
                                       discountAmountMinor: 2780, finalAmountMinor: 2780, confidence: 0.4,
                                       missingFields: ["sourceText", "quantity", "categoryID"])
        let edited = try XCTUnwrap(item.reviewed(originalAmount: 2980, discountAmount: 200, quantity: 10))
        XCTAssertEqual(edited.finalAmountMinor, 2780)
        XCTAssertEqual(edited.quantity, 10)
        XCTAssertEqual(edited.missingFields, ["categoryID"])
        XCTAssertFalse(edited.requiresReview)
        XCTAssertNil(item.reviewed(originalAmount: -2980, discountAmount: 200, quantity: 10))
        XCTAssertNil(item.reviewed(originalAmount: 2980, discountAmount: 3000, quantity: 10))
    }

    func testProportionalDiscountUsesRemainingMoneyAndCannotBeAppliedTwice() throws {
        let items = [
            BillItemAnalysisItem(lineID: "sale", originalName: "Sale", originalAmountMinor: 1000, discountAmountMinor: 990, finalAmountMinor: 10, confidence: 1),
            BillItemAnalysisItem(lineID: "normal", originalName: "Normal", originalAmountMinor: 1000, finalAmountMinor: 1000, confidence: 1),
            BillItemAnalysisItem(lineID: "coupon", originalName: "Coupon", lineType: .discount, discountAmountMinor: 100, finalAmountMinor: -100, confidence: 1),
        ]
        let allocated = try XCTUnwrap(BillItemDiscountAllocator.allocatingDiscount(itemID: "coupon", in: items))
        XCTAssertEqual(allocated.map(\.finalAmountMinor), [9, 901, 0])
        XCTAssertEqual(allocated.reduce(0) { $0 + $1.finalAmountMinor }, 910)
        XCTAssertFalse(BillItemAnalysisResult(totalMinor: 910, confidence: 1, items: allocated).requiresReview)
        XCTAssertNil(BillItemDiscountAllocator.allocatingDiscount(itemID: "coupon", in: allocated))
        var excessive = items
        excessive[2].finalAmountMinor = -2000
        excessive[2].discountAmountMinor = 2000
        XCTAssertNil(BillItemDiscountAllocator.allocatingDiscount(itemID: "coupon", in: excessive))
    }
}
