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
              "line_type": "purchase",
              "original_amount_minor": 320,
              "discount_amount_minor": 20,
              "final_amount_minor": 300,
              "category_id": "\(categoryID.uuidString)",
              "confidence": 0.89
            },
            {
              "line_id": "2",
              "original_name": "のどごし生",
              "translated_name": "Bia Nodogoshi Nama",
              "line_type": "purchase",
              "original_amount_minor": "800",
              "discount_amount_minor": 0,
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
        XCTAssertEqual(result.items[0].lineType, .purchase)
        XCTAssertEqual(result.items[0].originalName, "牛乳")
        XCTAssertEqual(result.items[0].translatedName, "Sữa")
        XCTAssertEqual(result.items[0].originalAmountMinor, 320)
        XCTAssertEqual(result.items[0].discountAmountMinor, 20)
        XCTAssertEqual(result.items[0].finalAmountMinor, 300)
        XCTAssertEqual(result.items[0].transactionAmountMinor, 300)
        XCTAssertEqual(result.items[0].categoryID, categoryID)
        XCTAssertEqual(result.items[1].translatedName, "Bia Nodogoshi Nama")
        XCTAssertEqual(result.items[1].finalAmountMinor, 800)
        XCTAssertEqual(result.quota?.usedCount, 2)
    }

    func testDecodesFallbackBillDateFormats() throws {
        let result = try decode("""
        {
          "merchant_name": "スーパー玉出",
          "total_minor": 1100,
          "currency_code": "JPY",
          "occurred_at": "2026-05-19 21:34",
          "wallet_id": "\(walletID.uuidString)",
          "multiple_bills_detected": false,
          "confidence": 0.92,
          "missing_fields": [],
          "raw_text": "スーパー玉出 合計 1100",
          "items": []
        }
        """)

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: try XCTUnwrap(result.occurredAt)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 21)
        XCTAssertEqual(components.minute, 34)
    }

    func testDecodesDiscountRecordAsNegativeAmountWithoutCategory() throws {
        let result = try decode("""
        {
          "merchant_name": "ドラッグストア",
          "total_minor": 900,
          "currency_code": "JPY",
          "occurred_at": null,
          "wallet_id": "\(walletID.uuidString)",
          "multiple_bills_detected": false,
          "confidence": 0.88,
          "missing_fields": [],
          "raw_text": "値引 -100",
          "items": [
            {
              "line_id": "d1",
              "original_name": "値引",
              "translated_name": "Giảm giá",
              "line_type": "discount",
              "original_amount_minor": null,
              "discount_amount_minor": 100,
              "final_amount_minor": -100,
              "category_id": null,
              "confidence": 0.91,
              "missing_fields": []
            }
          ]
        }
        """)

        XCTAssertEqual(result.items[0].lineType, .discount)
        XCTAssertEqual(result.items[0].translatedName, "Giảm giá")
        XCTAssertNil(result.items[0].originalAmountMinor)
        XCTAssertEqual(result.items[0].discountAmountMinor, 100)
        XCTAssertEqual(result.items[0].finalAmountMinor, -100)
        XCTAssertEqual(result.items[0].transactionAmountMinor, -100)
        XCTAssertNil(result.items[0].categoryID)
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

    func testExpenseSelectionAllowsDiscountWithSameWalletWithoutCategory() {
        let purchase = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID)
        let discount = makeCandidate(
            itemID: "discount",
            walletID: walletID,
            categoryID: nil,
            lineType: .discount,
            amountMinor: -100
        )
        let otherWalletDiscount = makeCandidate(
            itemID: "other-discount",
            walletID: otherWalletID,
            categoryID: nil,
            lineType: .discount,
            amountMinor: -100
        )
        let sameCategoryPurchase = makeCandidate(itemID: "b", walletID: walletID, categoryID: categoryID)
        let differentCategoryPurchase = makeCandidate(itemID: "c", walletID: walletID, categoryID: otherCategoryID)

        XCTAssertTrue(BillItemSelectionLogic.canSelect(discount, selected: [purchase], mode: .expense))
        XCTAssertFalse(BillItemSelectionLogic.canSelect(otherWalletDiscount, selected: [purchase], mode: .expense))
        XCTAssertTrue(BillItemSelectionLogic.canSelect(purchase, selected: [discount], mode: .expense))
        XCTAssertTrue(BillItemSelectionLogic.canSelect(sameCategoryPurchase, selected: [discount, purchase], mode: .expense))
        XCTAssertFalse(BillItemSelectionLogic.canSelect(differentCategoryPurchase, selected: [discount, purchase], mode: .expense))
    }

    func testLendSelectionOnlyRequiresSameWallet() {
        let first = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID)
        let differentCategory = makeCandidate(itemID: "b", walletID: walletID, categoryID: otherCategoryID)
        let differentWallet = makeCandidate(itemID: "c", walletID: otherWalletID, categoryID: categoryID)
        let discount = makeCandidate(itemID: "discount", walletID: walletID, categoryID: nil, lineType: .discount, amountMinor: -100)

        XCTAssertTrue(BillItemSelectionLogic.canSelect(differentCategory, selected: [first], mode: .lend))
        XCTAssertTrue(BillItemSelectionLogic.canSelect(discount, selected: [first], mode: .lend))
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

    func testExpenseDraftUsesDiscountAmountAndPurchaseCategory() throws {
        let purchase = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID, amountMinor: 1_000)
        let discount = makeCandidate(itemID: "discount", walletID: walletID, categoryID: nil, lineType: .discount, amountMinor: -150)

        let draft = try XCTUnwrap(BillItemSelectionLogic.transactionDraft(
            for: [purchase, discount],
            mode: .expense,
            fallbackDate: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertEqual(draft.amountMinor, 850)
        XCTAssertEqual(draft.categoryID, categoryID)
    }

    func testLockedGroupRejectsNonPositiveTotal() {
        let discount = makeCandidate(itemID: "discount", walletID: walletID, categoryID: nil, lineType: .discount, amountMinor: -150)

        let group = BillItemSelectionLogic.lockedGroup(
            for: [discount],
            mode: .expense,
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        )

        XCTAssertNil(group)
    }

    func testLockedGroupLocksItemsUntilCancelled() throws {
        let purchase = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID, amountMinor: 1_000)
        let discount = makeCandidate(itemID: "discount", walletID: walletID, categoryID: nil, lineType: .discount, amountMinor: -150)
        let group = try XCTUnwrap(BillItemSelectionLogic.lockedGroup(
            for: [purchase, discount],
            mode: .expense,
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        ))

        XCTAssertEqual(group.amountMinor, 850)
        XCTAssertEqual(BillItemSelectionLogic.lockedItemIDs(in: [group]), [purchase.id, discount.id])
        XCTAssertEqual(BillItemSelectionLogic.lockedItemIDs(in: []), [])
    }

    func testSelectionSnapshotPrecomputesCandidatesSelectionAndLockedItemsByBill() throws {
        let billID = UUID()
        let purchase = BillItemAnalysisItem(
            lineID: "a",
            originalName: "A",
            lineType: .purchase,
            originalAmountMinor: 1_000,
            discountAmountMinor: 0,
            finalAmountMinor: 1_000,
            categoryID: categoryID,
            confidence: 0.9
        )
        let locked = BillItemAnalysisItem(
            lineID: "locked",
            originalName: "Locked",
            lineType: .purchase,
            originalAmountMinor: 2_000,
            discountAmountMinor: 0,
            finalAmountMinor: 2_000,
            categoryID: categoryID,
            confidence: 0.9
        )
        let lockedID = BillItemSelectionID(billID: billID, itemID: locked.lineID)
        let group = BillItemLockedGroup(
            id: UUID(),
            mode: .expense,
            itemIDs: [lockedID],
            amountMinor: locked.transactionAmountMinor
        )

        let snapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: Date(timeIntervalSince1970: 100),
                    items: [purchase, locked],
                    createdItemIDs: [],
                    lockedGroups: [group]
                )
            ],
            selectedIDs: [BillItemSelectionID(billID: billID, itemID: purchase.lineID)]
        )

        XCTAssertEqual(snapshot.candidatesByBillID[billID]?.count, 2)
        XCTAssertEqual(snapshot.selectedCandidatesByBillID[billID]?.map(\.id.itemID), ["a"])
        XCTAssertEqual(snapshot.lockedItemIDsByBillID[billID], [lockedID])
        XCTAssertEqual(snapshot.candidatesByID[lockedID]?.isLocked, true)
    }

    func testSelectionSnapshotPrecomputesSelectableIDsForCurrentMode() throws {
        let first = makeCandidate(itemID: "a", walletID: walletID, categoryID: categoryID)
        let sameGroup = makeCandidate(itemID: "b", walletID: walletID, categoryID: categoryID)
        let differentCategory = makeCandidate(itemID: "c", walletID: walletID, categoryID: otherCategoryID)
        let otherBill = makeCandidate(billID: otherBillID, itemID: "e", walletID: walletID, categoryID: categoryID)

        let snapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: nil,
                    items: [
                        makeItem(first),
                        makeItem(sameGroup),
                        makeItem(differentCategory)
                    ],
                    createdItemIDs: [],
                    lockedGroups: []
                ),
                BillItemSelectionBillSnapshot(
                    billID: otherBillID,
                    walletID: walletID,
                    merchantName: "Other",
                    occurredAt: nil,
                    items: [makeItem(otherBill)],
                    createdItemIDs: [],
                    lockedGroups: []
                )
            ],
            selectedIDs: [first.id]
        )

        XCTAssertEqual(snapshot.selectableIDs(mode: .expense), [sameGroup.id])
        XCTAssertEqual(snapshot.selectableIDs(mode: .lend), [sameGroup.id, differentCategory.id])
    }

    func testQuantitySelectionCanLockPartialMultipackAndLeaveRemainingQuantity() throws {
        let item = BillItemAnalysisItem(
            lineID: "multipack",
            originalName: "A",
            lineType: .purchase,
            quantity: 5,
            originalAmountMinor: 500,
            discountAmountMinor: 0,
            finalAmountMinor: 500,
            categoryID: categoryID,
            confidence: 0.9
        )
        let selectionID = BillItemSelectionID(billID: billID, itemID: item.lineID)
        let selectedSnapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: nil,
                    items: [item],
                    createdAllocations: [:],
                    lockedGroups: []
                )
            ],
            selectedQuantities: [selectionID: 3]
        )

        let selectedCandidate = try XCTUnwrap(selectedSnapshot.selectedCandidates.first)
        XCTAssertEqual(selectedCandidate.totalQuantity, 5)
        XCTAssertEqual(selectedCandidate.availableQuantity, 5)
        XCTAssertEqual(selectedCandidate.selectedQuantity, 3)
        XCTAssertEqual(selectedCandidate.amountMinor, 300)

        let group = try XCTUnwrap(BillItemSelectionLogic.lockedGroup(
            for: selectedSnapshot.selectedCandidates,
            mode: .expense,
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        ))
        XCTAssertEqual(group.itemAllocations[selectionID]?.quantity, 3)
        XCTAssertEqual(group.amountMinor, 300)

        let remainingSnapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: nil,
                    items: [item],
                    createdAllocations: [:],
                    lockedGroups: [group]
                )
            ],
            selectedQuantities: [:]
        )

        let remainingCandidate = try XCTUnwrap(remainingSnapshot.candidatesByID[selectionID])
        XCTAssertEqual(remainingCandidate.lockedQuantity, 3)
        XCTAssertEqual(remainingCandidate.availableQuantity, 2)
        XCTAssertEqual(remainingCandidate.amountMinor, 200)
        XCTAssertTrue(remainingSnapshot.selectableIDs(mode: .expense).contains(selectionID))
    }

    func testQuantitySelectionAllocatesRemaindersDeterministically() throws {
        let item = BillItemAnalysisItem(
            lineID: "uneven",
            originalName: "A",
            lineType: .purchase,
            quantity: 3,
            originalAmountMinor: 100,
            discountAmountMinor: 0,
            finalAmountMinor: 100,
            categoryID: categoryID,
            confidence: 0.9
        )
        let selectionID = BillItemSelectionID(billID: billID, itemID: item.lineID)
        let selectedSnapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: nil,
                    items: [item],
                    createdAllocations: [:],
                    lockedGroups: []
                )
            ],
            selectedQuantities: [selectionID: 2]
        )
        let group = try XCTUnwrap(BillItemSelectionLogic.lockedGroup(
            for: selectedSnapshot.selectedCandidates,
            mode: .expense
        ))

        XCTAssertEqual(group.itemAllocations[selectionID]?.quantity, 2)
        XCTAssertEqual(group.itemAllocations[selectionID]?.amountMinor, 67)
        XCTAssertEqual(group.amountMinor, 67)

        let createdSnapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: nil,
                    items: [item],
                    createdAllocations: ["uneven": group.itemAllocations[selectionID]!],
                    lockedGroups: []
                )
            ],
            selectedQuantities: [:]
        )
        let remainingCandidate = try XCTUnwrap(createdSnapshot.candidatesByID[selectionID])
        XCTAssertEqual(remainingCandidate.createdQuantity, 2)
        XCTAssertEqual(remainingCandidate.availableQuantity, 1)
        XCTAssertEqual(remainingCandidate.amountMinor, 33)
        XCTAssertEqual((group.itemAllocations[selectionID]?.amountMinor ?? 0) + remainingCandidate.amountMinor, 100)
    }

    func testQuantitySelectionRulesStillRequireSameCategoryForExpense() throws {
        let first = BillItemAnalysisItem(
            lineID: "a",
            originalName: "A",
            lineType: .purchase,
            quantity: 5,
            originalAmountMinor: 500,
            discountAmountMinor: 0,
            finalAmountMinor: 500,
            categoryID: categoryID,
            confidence: 0.9
        )
        let second = BillItemAnalysisItem(
            lineID: "b",
            originalName: "B",
            lineType: .purchase,
            quantity: 5,
            originalAmountMinor: 500,
            discountAmountMinor: 0,
            finalAmountMinor: 500,
            categoryID: otherCategoryID,
            confidence: 0.9
        )
        let firstID = BillItemSelectionID(billID: billID, itemID: first.lineID)
        let secondID = BillItemSelectionID(billID: billID, itemID: second.lineID)

        let snapshot = BillItemSelectionSnapshot(
            bills: [
                BillItemSelectionBillSnapshot(
                    billID: billID,
                    walletID: walletID,
                    merchantName: "Store",
                    occurredAt: nil,
                    items: [first, second],
                    createdAllocations: [:],
                    lockedGroups: []
                )
            ],
            selectedQuantities: [firstID: 2]
        )

        XCTAssertFalse(snapshot.selectableIDs(mode: .expense).contains(secondID))
        XCTAssertTrue(snapshot.selectableIDs(mode: .lend).contains(secondID))
    }

    func testAllocatesDiscountRecordAcrossPurchaseItemsAndClearsDiscountLine() throws {
        let first = BillItemAnalysisItem(
            lineID: "a",
            originalName: "A",
            lineType: .purchase,
            originalAmountMinor: 1_000,
            discountAmountMinor: 0,
            finalAmountMinor: 1_000,
            categoryID: categoryID,
            confidence: 0.9
        )
        let second = BillItemAnalysisItem(
            lineID: "b",
            originalName: "B",
            lineType: .purchase,
            originalAmountMinor: 3_000,
            discountAmountMinor: 0,
            finalAmountMinor: 3_000,
            categoryID: categoryID,
            confidence: 0.9
        )
        let discount = BillItemAnalysisItem(
            lineID: "d",
            originalName: "値引",
            lineType: .discount,
            originalAmountMinor: nil,
            discountAmountMinor: 400,
            finalAmountMinor: -400,
            categoryID: nil,
            confidence: 0.9
        )

        let allocated = try XCTUnwrap(BillItemDiscountAllocator.allocatingDiscount(
            itemID: "d",
            in: [first, second, discount]
        ))

        XCTAssertEqual(allocated.map(\.finalAmountMinor).reduce(0, +), 3_600)
        XCTAssertEqual(allocated[0].discountAmountMinor, 100)
        XCTAssertEqual(allocated[0].finalAmountMinor, 900)
        XCTAssertEqual(allocated[1].discountAmountMinor, 300)
        XCTAssertEqual(allocated[1].finalAmountMinor, 2_700)
        XCTAssertEqual(allocated[2].lineType, .discount)
        XCTAssertEqual(allocated[2].finalAmountMinor, 0)
    }

    private func decode(_ json: String) throws -> BillItemAnalysisResult {
        try JSONDecoder().decode(BillItemAnalysisResult.self, from: Data(json.utf8))
    }

    private func makeCandidate(
        billID: UUID? = nil,
        itemID: String,
        walletID: UUID?,
        categoryID: UUID?,
        lineType: BillItemLineType = .purchase,
        amountMinor: Int64 = 100,
        merchantName: String? = "Store",
        occurredAt: Date? = nil,
        isCreated: Bool = false
    ) -> BillItemSelectionCandidate {
        BillItemSelectionCandidate(
            id: BillItemSelectionID(billID: billID ?? self.billID, itemID: itemID),
            walletID: walletID,
            categoryID: categoryID,
            lineType: lineType,
            amountMinor: amountMinor,
            merchantName: merchantName,
            occurredAt: occurredAt,
            isCreated: isCreated
        )
    }

    private func makeItem(_ candidate: BillItemSelectionCandidate) -> BillItemAnalysisItem {
        BillItemAnalysisItem(
            lineID: candidate.id.itemID,
            originalName: candidate.id.itemID,
            lineType: candidate.lineType,
            finalAmountMinor: candidate.amountMinor,
            categoryID: candidate.categoryID,
            confidence: 0.9
        )
    }

    private func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter.mistiaSyncWithoutFractionalSeconds.date(from: value)!
    }
}
