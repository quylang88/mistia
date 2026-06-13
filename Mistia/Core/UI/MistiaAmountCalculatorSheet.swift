import SwiftUI

struct MistiaAmountCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCommit: (String) -> Void

    @State private var tokens: [String]
    @State private var currentNumber: String

    private let accent = MistiaAccent.purple.color
    private let groupedBackground = Color(UIColor.systemGroupedBackground)

    init(initialText: String, onCommit: @escaping (String) -> Void) {
        self.onCommit = onCommit

        let digits = Self.digits(from: initialText)
        self._tokens = State(initialValue: digits.isEmpty ? [] : [digits])
        self._currentNumber = State(initialValue: digits)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                displayPanel
                keypad
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(groupedBackground.ignoresSafeArea())
            .navigationTitle(L10n.shared.amountCalculator.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.common.cancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        commit()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(accent)
                    .disabled(!evaluation.canCommit)
                    .accessibilityLabel(L10n.common.ok)
                }
            }
        }
        .presentationBackground(groupedBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private var displayPanel: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(expressionText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(L10n.shared.amountCalculator.expression)

            Text(resultText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(evaluation.canCommit ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(L10n.shared.amountCalculator.result)

            Text(validationText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(validationText.isEmpty ? .clear : .red)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(validationText.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                calculatorButton("C", role: .utility) { clear() }
                calculatorButton("⌫", role: .utility) { deleteBackward() }
                calculatorButton("÷", role: .operation) { appendOperator("÷") }
                calculatorButton("×", role: .operation) { appendOperator("×") }
            }
            GridRow {
                calculatorButton("7") { appendDigit("7") }
                calculatorButton("8") { appendDigit("8") }
                calculatorButton("9") { appendDigit("9") }
                calculatorButton("-", role: .operation) { appendOperator("-") }
            }
            GridRow {
                calculatorButton("4") { appendDigit("4") }
                calculatorButton("5") { appendDigit("5") }
                calculatorButton("6") { appendDigit("6") }
                calculatorButton("+", role: .operation) { appendOperator("+") }
            }
            GridRow {
                calculatorButton("1") { appendDigit("1") }
                calculatorButton("2") { appendDigit("2") }
                calculatorButton("3") { appendDigit("3") }
                calculatorButton("=", role: .operation) { collapseToResultIfPossible() }
            }
            GridRow {
                calculatorButton("0") { appendDigit("0") }
                    .gridCellColumns(2)
                calculatorButton("00") { appendDigit("00") }
                calculatorButton("OK", role: .confirm, isEnabled: evaluation.canCommit) { commit() }
            }
        }
    }

    private func calculatorButton(
        _ title: String,
        role: CalculatorButtonRole = .number,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(buttonFont(for: title, role: role))
                .foregroundStyle(role.foregroundStyle)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(role.backgroundStyle)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var expressionText: String {
        let text = tokens.joined(separator: " ")
        return text.isEmpty ? "0" : text
    }

    private var resultText: String {
        if evaluation.error == .incompleteExpression || evaluation.error == .emptyExpression {
            return lastNumberText
        }

        if let integerResult = evaluation.integerResult {
            return MistiaAmountCalculatorLogic.committedInputText(for: integerResult)
        }

        if let decimalResult = evaluation.decimalResult {
            return decimalDisplayText(for: decimalResult)
        }

        return currentNumber.isEmpty
            ? "0"
            : MistiaCurrencyInputFormatting.groupedInput(currentNumber)
    }

    private var lastNumberText: String {
        let number = currentNumber.isEmpty
            ? tokens.last(where: { !isOperator($0) }) ?? ""
            : currentNumber
        return number.isEmpty ? "0" : MistiaCurrencyInputFormatting.groupedInput(number)
    }

    private var validationText: String {
        switch evaluation.error {
        case .divisionByZero:
            L10n.shared.amountCalculator.divisionByZero
        case .fractionalResult:
            L10n.shared.amountCalculator.integerPositiveRequired
        case .nonPositiveResult:
            L10n.shared.amountCalculator.integerPositiveRequired
        case .overflow:
            L10n.shared.amountCalculator.resultTooLarge
        case .invalidExpression, .incompleteExpression, .emptyExpression:
            ""
        case nil:
            ""
        }
    }

    private var evaluation: MistiaAmountCalculatorLogic.Evaluation {
        MistiaAmountCalculatorLogic.evaluation(for: tokens)
    }

    private func appendDigit(_ digit: String) {
        if tokens.isEmpty || isOperator(tokens.last) {
            currentNumber = digit == "00" ? "0" : digit
            tokens.append(currentNumber)
            return
        }

        if currentNumber == "0" {
            currentNumber = digit == "00" ? "0" : digit
        } else {
            currentNumber += digit
        }

        tokens[tokens.count - 1] = currentNumber
    }

    private func appendOperator(_ operation: String) {
        guard !tokens.isEmpty else { return }

        if isOperator(tokens.last) {
            tokens[tokens.count - 1] = operation
            return
        }

        tokens.append(operation)
        currentNumber = ""
    }

    private func deleteBackward() {
        guard !tokens.isEmpty else { return }

        if isOperator(tokens.last) {
            tokens.removeLast()
            currentNumber = Self.digits(from: tokens.last ?? "")
            return
        }

        currentNumber = String(currentNumber.dropLast())
        if currentNumber.isEmpty {
            tokens.removeLast()
            currentNumber = Self.digits(from: tokens.last ?? "")
        } else {
            tokens[tokens.count - 1] = currentNumber
        }
    }

    private func clear() {
        tokens = []
        currentNumber = ""
    }

    private func collapseToResultIfPossible() {
        guard let integerResult = evaluation.integerResult else { return }
        currentNumber = String(integerResult)
        tokens = [currentNumber]
    }

    private func commit() {
        guard let integerResult = evaluation.integerResult else { return }
        onCommit(MistiaAmountCalculatorLogic.committedInputText(for: integerResult))
        dismiss()
    }

    private func decimalDisplayText(for value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func buttonFont(for title: String, role: CalculatorButtonRole) -> Font {
        if title == "OK" {
            return .system(size: 17, weight: .bold, design: .rounded)
        }

        switch role {
        case .number:
            return .system(size: 22, weight: .semibold, design: .rounded)
        case .operation, .utility, .confirm:
            return .system(size: 20, weight: .semibold, design: .rounded)
        }
    }

    private func isOperator(_ token: String?) -> Bool {
        guard let token else { return false }
        return token == "+" || token == "-" || token == "×" || token == "÷"
    }

    private static func digits(from input: String) -> String {
        input.replacingOccurrences(
            of: "[^0-9]",
            with: "",
            options: .regularExpression
        )
    }
}

private enum CalculatorButtonRole {
    case number
    case operation
    case utility
    case confirm

    var foregroundStyle: Color {
        switch self {
        case .number:
            .primary
        case .operation, .confirm:
            .white
        case .utility:
            .secondary
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .number:
            Color(UIColor.secondarySystemGroupedBackground)
        case .operation:
            MistiaAccent.purple.color
        case .utility:
            Color(UIColor.tertiarySystemGroupedBackground)
        case .confirm:
            MistiaAccent.checkmarkPurple.color
        }
    }
}
