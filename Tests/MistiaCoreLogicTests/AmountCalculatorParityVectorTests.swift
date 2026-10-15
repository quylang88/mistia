import Foundation
import XCTest
@testable import MistiaCoreLogic

final class AmountCalculatorParityVectorTests: XCTestCase {
    private struct Document: Decodable { let version: Int; let cases: [Vector] }
    private struct Vector: Decodable {
        let name: String; let tokens: [String]; let expectedInteger: String?; let expectedError: String?; let expectedDecimal: String?
    }
    func testSameAndroidCalculatorVectorsAgainstActualSwiftEngine() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: root.appendingPathComponent("contracts/golden/amount-calculator-v1.json")))
        XCTAssertEqual(doc.version, 1); XCTAssertEqual(doc.cases.count, 36)
        for vector in doc.cases {
            let result = MistiaAmountCalculatorLogic.evaluation(for: vector.tokens)
            XCTAssertEqual(result.integerResult.map(String.init), vector.expectedInteger, vector.name)
            XCTAssertEqual(result.error.map { String(describing: $0) }, vector.expectedError, vector.name)
            XCTAssertEqual(result.decimalResult.map { NSDecimalNumber(decimal: $0).stringValue }, vector.expectedDecimal, vector.name)
            XCTAssertEqual(result.canCommit, vector.expectedInteger != nil && vector.expectedError == nil, vector.name)
        }
    }
}
