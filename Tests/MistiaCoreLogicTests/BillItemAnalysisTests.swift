import XCTest
@testable import MistiaCoreLogic

final class BillItemAnalysisTests: XCTestCase {
    private let categoryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherCategoryID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let walletID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let otherWalletID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let billID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let otherBillID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    func testDecodesItemizedBillAnalysisResponse() throws {
        let result = try decode("""
        {
          "merchant_name": "スーパー玉出",
          "total_minor": "¥1,100",
          "currency_code": "jpy",
          "occurred_at": "2026-05-19T21:34:00+09:00",
          "wallet_id": "\(walletID.uuidString)",
          "multiple_bills_detected": false,
          "confidence": 0.92,
          "missing_fields": [],
          "raw_text": "スーパー玉出 合計 1100",
          "items": [
            {
              "line_id": "1",
              "original_name": "牛乳",
              "translated_name": "Sữa",
              "final_amount_minor": 300,
              "category_id": "\(categoryID.uuidString)",
              "confidence": 0.89
            },
            {
              "line_id": "2",
              "original_name": "Apple",
              "translated_name": null,
              "final_amount_minor": "800",
              "category_id": "\(categoryID.uuidString)",
              "confidence": "0.84"
            }
          ],
          "quota": {
            "allowed": true,
            "used_count": 2,
            "limit_count": 20,
            "remaining_count": 18
          }
        }
        """)

        XCTAssertEqual(result.merchantName, "スーパー玉出")
        XCTAssertEqual(result.totalMinor, 1_100)
        XCTAssertEqual(result.currencyCode, "JPY")
        XCTAssertEqual(result.walletID, walletID)
        XCTAssertFalse(result.multipleBillsDetected)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].lineID, "1")
        XCTAssertEqual(result.items[0].originalName, "牛乳")
        XCTAssertEqual(result.items[0].translatedName, "Sữa")
        XCTAssertEqual(result.items[0].finalAmountMinor, 300)
        XCTAssertEqual(result.items[0].categoryID, categoryID)
        XCTAssertNil(result.items[1].translatedName)
        XCTAssertEqual(result.items[1].finalAmountMinor, 800)
        XCTAssertEqual(result.quota?.usedCount, 2)
    }

    func testValidationRemovesIDsOutsideCandidateLists() {
        let unknownCategoryID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let unknownWalletID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let result = BillItemAnalysisResult(
            merchantName: "Store",
            totalMinor: 900,
            currencyCode: "JPY",
            walletID: unknownWalletID,
            confidence: 0.8,
            items: [
                BillItemAnalysisItem(
                    lineID: "1",
                    originalName: "Known",
                    translatedName: nil,
                    finalAmountMinor: 400,
                    categoryID: categoryID,
                    confidence: 0.9
                ),
                BillItemAnalysisItem(
                    lineID: "2",
                    originalName: "Unknown",
                    translatedName: nil,
                    finalAmountMinor: 500,
                    categoryID: unknownCategoryID,
                    confidence: 0.7
                )
            ]
        )

        let validated = result.validated(
            categoryIDs: [categoryID],
            walletIDs: [walletID]
        )

        XCTAssertNil(validated.walletID)
        XCTAssertEqual(validated.items[0].categoryID, categoryID)
        XCTAssertNil(validated.items[1].categoryID)
        XCTAssertTrue(validated.missingFields.contains("walletID"))
        XCTAssertTrue(validated.missingFields.contains("itemCategoryID"))
    }

    func testDecodesMultipleBillsDetectedResponse() throws {
        let result = try decode("""
        {
          "merchant_name": null,
          "total_minor": null,
          "currency_code": "JPY",
          "occurred_at": null,
          "wallet_id": null,
          "multiple_bills_detected": true,
          "confidence": 0.31,
          "missing_fields": ["singleBillImage"],
          "raw_text": "two receipts visible",
          "items": []
        }
        """)

        XCTAssertTrue(result.multipleBillsDetected)
        XCTAssertEqual(result.items, [])
        XCTAssertTrue(result.missingFields.contains("singleBillImage"))
    }

    func testExpenseSelectionRequiresSameWalletAndCategory() {
        let first = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID)
        let sameGroup = makeCandidate(itemID: "b", walletID: walletID, categoryID: categoryID)
        let differentCategory = makeCandidate(itemID: "c", walletID: walletID, categoryID: otherCategoryID)
        let differentWallet = makeCandidate(itemID: "d", walletID: otherWalletID, categoryID: categoryID)

        XCTAssertTrue(BillItemSelectionLogic.canSelect(first, selected: [], mode: .expense))
        XCTAssertTrue(BillItemSelectionLogic.canSelect(sameGroup, selected: [first], mode: .expense))
        XCTAssertFalse(BillItemSelectionLogic.canSelect(differentCategory, selected: [first], mode: .expense))
        XCTAssertFalse(BillItemSelectionLogic.canSelect(differentWallet, selected: [first], mode: .expense))
    }

    func testLendSelectionOnlyRequiresSameWallet() {
        let first = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID)
        let differentCategory = makeCandidate(itemID: "b", walletID: walletID, categoryID: otherCategoryID)
        let differentWallet = makeCandidate(itemID: "c", walletID: otherWalletID, categoryID: categoryID)

        XCTAssertTrue(BillItemSelectionLogic.canSelect(differentCategory, selected: [first], mode: .lend))
        XCTAssertFalse(BillItemSelectionLogic.canSelect(differentWallet, selected: [first], mode: .lend))
    }

    func testCreatedItemsAreNotSelectable() {
        let created = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID, isCreated: true)

        XCTAssertFalse(BillItemSelectionLogic.canSelect(created, selected: [], mode: .expense))
    }

    func testChangingModeDropsInvalidSelection() {
        let first = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID)
        let sameWalletDifferentCategory = makeCandidate(itemID: "b", walletID: walletID, categoryID: otherCategoryID)
        let candidates = [first, sameWalletDifferentCategory]
        let lendSelection = Set(candidates.map(\.id))

        let expenseSelection = BillItemSelectionLogic.normalizedSelection(
            lendSelection,
            candidates: candidates,
            mode: .expense
        )

        XCTAssertEqual(expenseSelection, [first.id])
    }

    func testExpenseDraftUsesMerchantWhenSelectionHasSameMerchant() throws {
        let occurredAt = makeDate("2026-05-19T21:34:00Z")
        let first = makeCandidate(
            billID: billID,
            itemID: "a",
            walletID: walletID,
            categoryID: categoryID,
            amountMinor: 300,
            merchantName: "FamilyMart",
            occurredAt: occurredAt
        )
        let second = makeCandidate(
            billID: otherBillID,
            itemID: "b",
            walletID: walletID,
            categoryID: categoryID,
            amountMinor: 500,
            merchantName: "FamilyMart",
            occurredAt: occurredAt
        )

        let draft = try XCTUnwrap(BillItemSelectionLogic.transactionDraft(
            for: [first, second],
            mode: .expense,
            fallbackDate: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertEqual(draft.primaryKind, .expense)
        XCTAssertEqual(draft.amountMinor, 800)
        XCTAssertEqual(draft.title, "FamilyMart")
        XCTAssertEqual(draft.walletID, walletID)
        XCTAssertEqual(draft.categoryID, categoryID)
        XCTAssertEqual(draft.occurredAt, occurredAt)
        XCTAssertNil(draft.receiptAttachmentBillID)
    }

    func testDraftLeavesTitleBlankAndUsesFallbackDateForMixedMerchantsAndDates() throws {
        let first = makeCandidate(
            billID: billID,
            itemID: "a",
            walletID: walletID,
            categoryID: categoryID,
            merchantName: "FamilyMart",
            occurredAt: makeDate("2026-05-19T21:34:00Z")
        )
        let second = makeCandidate(
            billID: otherBillID,
            itemID: "b",
            walletID: walletID,
            categoryID: categoryID,
            merchantName: "Lawson",
            occurredAt: makeDate("2026-05-20T08:00:00Z")
        )
        let fallbackDate = Date(timeIntervalSince1970: 42)

        let draft = try XCTUnwrap(BillItemSelectionLogic.transactionDraft(
            for: [first, second],
            mode: .expense,
            fallbackDate: fallbackDate
        ))

        XCTAssertEqual(draft.title, "")
        XCTAssertEqual(draft.occurredAt, fallbackDate)
    }

    func testSingleBillDraftCarriesReceiptAttachmentBillID() throws {
        let first = makeCandidate(billID: billID, itemID: "a", walletID: walletID, categoryID: categoryID)
        let second = makeCandidate(billID: billID, itemID: "b", walletID: walletID, categoryID: categoryID)

        let draft = try XCTUnwrap(BillItemSelectionLogic.transactionDraft(
            for: [first, second],
            mode: .expense,
            fallbackDate: Date()
        ))

        XCTAssertEqual(draft.receiptAttachmentBillID, billID)
    }

    func testLendDraftUsesDebtTransferAndDoesNotRequireCategory() throws {
        let first = makeCandidate(itemID: "a", walletID: walletID, categoryID: nil, amountMinor: 700)
        let second = makeCandidate(itemID: "b", walletID: walletID, categoryID: otherCategoryID, amountMinor: 800)

        let draft = try XCTUnwrap(BillItemSelectionLogic.transactionDraft(
            for: [first, second],
            mode: .lend,
            fallbackDate: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertEqual(draft.primaryKind, .transfer)
        XCTAssertEqual(draft.transferSubtype, .debt)
        XCTAssertEqual(draft.debtIntent, .lend)
        XCTAssertEqual(draft.amountMinor, 1_500)
        XCTAssertEqual(draft.walletID, walletID)
        XCTAssertNil(draft.categoryID)
    }

    private func decode(_ json: String) throws -> BillItemAnalysisResult {
        try JSONDecoder().decode(BillItemAnalysisResult.self, from: Data(json.utf8))
    }

    private func makeCandidate(
        billID: UUID? = nil,
        itemID: String,
        walletID: UUID?,
        categoryID: UUID?,
        amountMinor: Int64 = 100,
        merchantName: String? = "Store",
        occurredAt: Date? = nil,
        isCreated: Bool = false
    ) -> BillItemSelectionCandidate {
        BillItemSelectionCandidate(
            id: BillItemSelectionID(billID: billID ?? self.billID, itemID: itemID),
            walletID: walletID,
            categoryID: categoryID,
            amountMinor: amountMinor,
            merchantName: merchantName,
            occurredAt: occurredAt,
            isCreated: isCreated
        )
    }

    private func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter.mistiaSyncWithoutFractionalSeconds.date(from: value)!
    }
}
