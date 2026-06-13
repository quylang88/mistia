import XCTest
@testable import MistiaCoreLogic

final class MistiaAmountCalculatorLogicTests: XCTestCase {
    func testEvaluatesAdditionSubtractionMultiplicationAndDivisionWithPrecedence() {
        XCTAssertEqual(
            MistiaAmountCalculatorLogic.evaluation(for: ["1", "+", "2", "×", "3"]).integerResult,
            7
        )
        XCTAssertEqual(
            MistiaAmountCalculatorLogic.evaluation(for: ["100", "-", "20", "÷", "4"]).integerResult,
            95
        )
    }

    func testRejectsFractionalDivisionResults() {
        let evaluation = MistiaAmountCalculatorLogic.evaluation(for: ["100", "÷", "3"])

        XCTAssertNil(evaluation.integerResult)
        XCTAssertEqual(evaluation.error, .fractionalResult)
        XCTAssertFalse(evaluation.canCommit)
    }

    func testRejectsDivisionByZero() {
        let evaluation = MistiaAmountCalculatorLogic.evaluation(for: ["100", "÷", "0"])

        XCTAssertNil(evaluation.integerResult)
        XCTAssertEqual(evaluation.error, .divisionByZero)
        XCTAssertFalse(evaluation.canCommit)
    }

    func testRejectsNonPositiveResults() {
        XCTAssertEqual(
            MistiaAmountCalculatorLogic.evaluation(for: ["1", "-", "1"]).error,
            .nonPositiveResult
        )
        XCTAssertEqual(
            MistiaAmountCalculatorLogic.evaluation(for: ["1", "-", "2"]).error,
            .nonPositiveResult
        )
    }

    func testRejectsOverflow() {
        let evaluation = MistiaAmountCalculatorLogic.evaluation(
            for: ["9_223_372_036_854_775_807", "+", "1"]
        )

        XCTAssertNil(evaluation.integerResult)
        XCTAssertEqual(evaluation.error, .overflow)
        XCTAssertFalse(evaluation.canCommit)
    }

    func testFormatsCommittedResultForCurrencyInput() {
        XCTAssertEqual(
            MistiaAmountCalculatorLogic.committedInputText(for: 1_234_567),
            "1,234,567"
        )
    }
}
