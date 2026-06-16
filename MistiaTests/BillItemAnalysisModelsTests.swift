import XCTest
@testable import Mistia

final class BillItemAnalysisModelsTests: XCTestCase {
    func testAIBillRenderContextCacheKeyInvalidatesForSelectionAndItemCategoryChanges() {
        let billID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let walletID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let categoryID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let alternateCategoryID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let itemID = BillItemSelectionID(billID: billID, itemID: "line-1")
        let baseBill = BillItemSelectionBillSnapshot(
            billID: billID,
            walletID: walletID,
            merchantName: "Market",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            items: [
                BillItemAnalysisItem(
                    lineID: "line-1",
                    originalName: "Milk",
                    quantity: 2,
                    finalAmountMinor: 600,
                    categoryID: categoryID,
                    confidence: 0.9
                )
            ],
            createdAllocations: [:],
            lockedGroups: []
        )
        let changedCategoryBill = BillItemSelectionBillSnapshot(
            billID: billID,
            walletID: walletID,
            merchantName: "Market",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            items: [
                BillItemAnalysisItem(
                    lineID: "line-1",
                    originalName: "Milk",
                    quantity: 2,
                    finalAmountMinor: 600,
                    categoryID: alternateCategoryID,
                    confidence: 0.9
                )
            ],
            createdAllocations: [:],
            lockedGroups: []
        )

        let baseKey = AIBillRenderContextCacheKey(
            mode: .expense,
            bills: [baseBill],
            selectedQuantities: [itemID: 1],
            quickCreateSubjectUserID: walletID,
            currentSelfUserID: walletID,
            activeLocalProfileUserID: walletID,
            signedInUserID: nil,
            selectedSubjectUserID: walletID,
            familyAccessSignature: 10,
            walletSignature: .empty,
            categorySignature: .empty,
            ownershipSignature: .empty
        )

        let changedSelectionKey = AIBillRenderContextCacheKey(
            mode: .expense,
            bills: [baseBill],
            selectedQuantities: [itemID: 2],
            quickCreateSubjectUserID: walletID,
            currentSelfUserID: walletID,
            activeLocalProfileUserID: walletID,
            signedInUserID: nil,
            selectedSubjectUserID: walletID,
            familyAccessSignature: 10,
            walletSignature: .empty,
            categorySignature: .empty,
            ownershipSignature: .empty
        )
        let changedCategoryKey = AIBillRenderContextCacheKey(
            mode: .expense,
            bills: [changedCategoryBill],
            selectedQuantities: [itemID: 1],
            quickCreateSubjectUserID: walletID,
            currentSelfUserID: walletID,
            activeLocalProfileUserID: walletID,
            signedInUserID: nil,
            selectedSubjectUserID: walletID,
            familyAccessSignature: 10,
            walletSignature: .empty,
            categorySignature: .empty,
            ownershipSignature: .empty
        )

        XCTAssertNotEqual(baseKey, changedSelectionKey)
        XCTAssertNotEqual(baseKey, changedCategoryKey)
    }

    func testItemDecodesQuantityForMultipackReceiptRows() throws {
        let json = """
        {
          "line_id": "line-1",
          "original_name": "KORI KRILL OIL 152C",
          "translated_name": "Dầu nhuyễn thể Kori",
          "line_type": "purchase",
          "quantity": 4,
          "original_amount_minor": 11392,
          "discount_amount_minor": 240,
          "final_amount_minor": 11152,
          "category_id": null,
          "confidence": 0.86,
          "missing_fields": []
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder.mistiaRemoteAPIDecoder.decode(BillItemAnalysisItem.self, from: json)

        XCTAssertEqual(item.quantity, 4)
        XCTAssertEqual(item.originalAmountMinor, 11_392)
        XCTAssertEqual(item.discountAmountMinor, 240)
        XCTAssertEqual(item.finalAmountMinor, 11_152)
        XCTAssertEqual(item.quantityUnitAmountMinor, 2_788)
    }

    func testItemDoesNotShowDiscountBreakdownForQuantityOnlyRows() {
        let item = BillItemAnalysisItem(
            lineID: "line-1",
            originalName: "KORI KRILL OIL152C",
            lineType: .purchase,
            quantity: 3,
            originalAmountMinor: 8_544,
            discountAmountMinor: 0,
            finalAmountMinor: 8_544,
            confidence: 0.9
        )

        XCTAssertFalse(item.showsDiscountBreakdown)
        XCTAssertEqual(item.quantityUnitAmountMinor, 2_848)
    }

    func testItemShowsDiscountBreakdownOnlyForExplicitDiscounts() {
        let item = BillItemAnalysisItem(
            lineID: "line-1",
            originalName: "PAMPERS P-L TPD",
            lineType: .purchase,
            originalAmountMinor: 800,
            discountAmountMinor: 67,
            finalAmountMinor: 733,
            confidence: 0.9
        )

        XCTAssertTrue(item.showsDiscountBreakdown)
    }
}
