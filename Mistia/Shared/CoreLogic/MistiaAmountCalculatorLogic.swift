import Foundation

nonisolated enum MistiaAmountCalculatorLogic {
    enum EvaluationError: Equatable {
        case emptyExpression
        case incompleteExpression
        case invalidExpression
        case divisionByZero
        case fractionalResult
        case nonPositiveResult
        case overflow
    }

    struct Evaluation: Equatable {
        let decimalResult: Decimal?
        let integerResult: Int64?
        let error: EvaluationError?

        var canCommit: Bool {
            integerResult != nil && error == nil
        }
    }

    static func evaluation(for tokens: [String]) -> Evaluation {
        let normalizedTokens = tokens.filter { !$0.isEmpty }
        guard !normalizedTokens.isEmpty else {
            return Evaluation(decimalResult: nil, integerResult: nil, error: .emptyExpression)
        }
        guard normalizedTokens.count % 2 == 1 else {
            return Evaluation(decimalResult: nil, integerResult: nil, error: .incompleteExpression)
        }

        var values: [Decimal] = []
        var operators: [String] = []

        for (index, token) in normalizedTokens.enumerated() {
            if index.isMultiple(of: 2) {
                guard let value = decimalNumber(from: token) else {
                    return Evaluation(decimalResult: nil, integerResult: nil, error: .invalidExpression)
                }
                values.append(value)
            } else {
                guard isOperator(token) else {
                    return Evaluation(decimalResult: nil, integerResult: nil, error: .invalidExpression)
                }
                operators.append(token)
            }
        }

        guard var currentTerm = values.first else {
            return Evaluation(decimalResult: nil, integerResult: nil, error: .emptyExpression)
        }

        var additiveTerms: [Decimal] = []
        var additiveOperators: [String] = []

        for (operatorIndex, operation) in operators.enumerated() {
            let nextValue = values[operatorIndex + 1]

            switch operation {
            case "×":
                currentTerm *= nextValue
            case "÷":
                guard nextValue != 0 else {
                    return Evaluation(decimalResult: nil, integerResult: nil, error: .divisionByZero)
                }
                currentTerm /= nextValue
            case "+", "-":
                additiveTerms.append(currentTerm)
                additiveOperators.append(operation)
                currentTerm = nextValue
            default:
                return Evaluation(decimalResult: nil, integerResult: nil, error: .invalidExpression)
            }
        }

        additiveTerms.append(currentTerm)

        var result = additiveTerms[0]
        for (index, operation) in additiveOperators.enumerated() {
            let nextTerm = additiveTerms[index + 1]
            if operation == "+" {
                result += nextTerm
            } else {
                result -= nextTerm
            }
        }

        return validatedEvaluation(for: result)
    }

    static func committedInputText(for value: Int64) -> String {
        MistiaCurrencyInputFormatting.groupedInput(String(value))
    }

    private static func validatedEvaluation(for result: Decimal) -> Evaluation {
        guard result > 0 else {
            return Evaluation(decimalResult: result, integerResult: nil, error: .nonPositiveResult)
        }

        let maxInt64 = Decimal(string: String(Int64.max)) ?? Decimal(Int64.max)
        guard result <= maxInt64 else {
            return Evaluation(decimalResult: result, integerResult: nil, error: .overflow)
        }

        var rounded = Decimal()
        var value = result
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded == result else {
            return Evaluation(decimalResult: result, integerResult: nil, error: .fractionalResult)
        }

        let number = NSDecimalNumber(decimal: rounded)
        let integerResult = number.int64Value
        guard Decimal(integerResult) == rounded else {
            return Evaluation(decimalResult: result, integerResult: nil, error: .overflow)
        }

        return Evaluation(decimalResult: result, integerResult: integerResult, error: nil)
    }

    private static func decimalNumber(from token: String) -> Decimal? {
        let digits = token.replacingOccurrences(
            of: "[^0-9]",
            with: "",
            options: .regularExpression
        )
        guard !digits.isEmpty else { return nil }
        return Decimal(string: digits)
    }

    private static func isOperator(_ token: String) -> Bool {
        token == "+" || token == "-" || token == "×" || token == "÷"
    }
}
