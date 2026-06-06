import XCTest
@testable import Mistia

final class BillItemAnalysisModelsTests: XCTestCase {
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
    }
}
