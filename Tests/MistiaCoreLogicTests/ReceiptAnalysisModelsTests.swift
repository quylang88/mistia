import Foundation
import XCTest
@testable import MistiaCoreLogic

final class ReceiptAnalysisModelsTests: XCTestCase {
    private let categoryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let walletID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testDecodesCompleteReceiptAnalysisResponse() throws {
        let result = try decode("""
        {
          "merchant_name": "FamilyMart",
          "total_minor": "¥1,240",
          "currency_code": "jpy",
          "occurred_at": "2026-05-18",
          "category_id": "\(categoryID.uuidString)",
          "wallet_id": "\(walletID.uuidString)",
          "confidence": 0.91,
          "missing_fields": [],
          "raw_text": "FamilyMart total 1240",
          "quota": {
            "allowed": true,
            "used_count": 4,
            "limit_count": 20,
            "remaining_count": 16,
            "usage_date": "2026-05-17",
            "reset_time_zone": "Asia/Tokyo",
            "retry_after": "2026-05-18T15:00:00Z"
          }
        }
        """)

        XCTAssertEqual(result.merchantName, "FamilyMart")
        XCTAssertEqual(result.totalMinor, 1_240)
        XCTAssertEqual(result.currencyCode, "JPY")
        XCTAssertNotNil(result.occurredAt)
        XCTAssertEqual(result.categoryID, categoryID)
        XCTAssertEqual(result.walletID, walletID)
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.rawText, "FamilyMart total 1240")
        XCTAssertEqual(result.quota?.usedCount, 4)
        XCTAssertEqual(result.quota?.limitCount, 20)
        XCTAssertEqual(result.quota?.remainingCount, 16)
        XCTAssertNotNil(result.quota?.retryAfter)
    }

    func testDecodesMissingWalletAsNil() throws {
        let result = try decode("""
        {
          "merchant_name": "Cafe",
          "total_minor": 680,
          "currency_code": "JPY",
          "occurred_at": null,
          "category_id": "\(categoryID.uuidString)",
          "wallet_id": null,
          "confidence": "0.74",
          "missing_fields": ["walletID"],
          "raw_text": null
        }
        """)

        XCTAssertEqual(result.totalMinor, 680)
        XCTAssertEqual(result.categoryID, categoryID)
        XCTAssertNil(result.walletID)
        XCTAssertEqual(result.confidence, 0.74)
        XCTAssertEqual(result.missingFields, ["walletID"])
    }

    func testDecodesMissingCategoryAsNil() throws {
        let result = try decode("""
        {
          "merchant_name": "Unknown Shop",
          "total_minor": 980,
          "currency_code": "JPY",
          "occurred_at": "2026-05-18T10:30:00Z",
          "category_id": null,
          "wallet_id": "\(walletID.uuidString)",
          "confidence": 0.62,
          "missing_fields": ["categoryID"],
          "raw_text": "receipt text"
        }
        """)

        XCTAssertNil(result.categoryID)
        XCTAssertEqual(result.walletID, walletID)
        XCTAssertEqual(result.missingFields, ["categoryID"])
    }

    func testValidationRemovesIDsOutsideCandidateLists() throws {
        let unknownCategoryID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let unknownWalletID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let result = ReceiptAnalysisResult(
            merchantName: "Store",
            totalMinor: 500,
            currencyCode: "JPY",
            categoryID: unknownCategoryID,
            walletID: unknownWalletID,
            confidence: 0.8
        )

        let validated = result.validated(categoryIDs: [categoryID], walletIDs: [walletID])

        XCTAssertNil(validated.categoryID)
        XCTAssertNil(validated.walletID)
        XCTAssertTrue(validated.missingFields.contains("categoryID"))
        XCTAssertTrue(validated.missingFields.contains("walletID"))
    }

    func testWrongSchemaThrows() {
        XCTAssertThrowsError(try decode("""
        {
          "merchant_name": "Store",
          "total_minor": {},
          "currency_code": "JPY",
          "occurred_at": null,
          "category_id": null,
          "wallet_id": null,
          "confidence": 0.5,
          "missing_fields": [],
          "raw_text": null
        }
        """))

        XCTAssertThrowsError(try decode("""
        {
          "merchant_name": "Store",
          "total_minor": 500,
          "currency_code": "JPY",
          "occurred_at": null,
          "category_id": null,
          "wallet_id": null,
          "missing_fields": [],
          "raw_text": null
        }
        """))
    }

    private func decode(_ json: String) throws -> ReceiptAnalysisResult {
        try JSONDecoder().decode(ReceiptAnalysisResult.self, from: Data(json.utf8))
    }
}
