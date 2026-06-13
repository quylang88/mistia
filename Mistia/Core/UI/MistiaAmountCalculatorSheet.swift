import SwiftUI

struct MistiaAmountCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCommit: (String) -> Void

    @State private var tokens: [String]
    @State private var currentNumber: String
    @State private var alertMessage: String?

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
            GeometryReader { proxy in
                let metrics = CalculatorSheetMetrics(availableHeight: proxy.size.height)

                VStack(spacing: metrics.stackSpacing) {
                    displayPanel(metrics: metrics)
                    keypad(metrics: metrics)
                }
                .padding(.horizontal, 18)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
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
                    .accessibilityLabel(L10n.common.ok)
                }
            }
        }
        .presentationBackground(groupedBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .alert(
            L10n.shared.amountCalculator.title,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
        }
    }

    private func displayPanel(metrics: CalculatorSheetMetrics) -> some View {
        VStack(alignment: .trailing, spacing: metrics.displayTextSpacing) {
            Text(expressionText)
                .font(.system(size: metrics.expressionFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(L10n.shared.amountCalculator.expression)

            Text(resultText)
                .font(.system(size: metrics.resultFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(evaluation.canCommit ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(L10n.shared.amountCalculator.result)
        }
        .padding(.horizontal, metrics.displayHorizontalPadding)
        .padding(.vertical, metrics.displayVerticalPadding)
        .frame(height: metrics.displayHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private func keypad(metrics: CalculatorSheetMetrics) -> some View {
        Grid(horizontalSpacing: metrics.gridSpacing, verticalSpacing: metrics.gridSpacing) {
            GridRow {
                calculatorButton("C", role: .utility, metrics: metrics) { clear() }
                calculatorButton("⌫", role: .utility, metrics: metrics) { deleteBackward() }
                calculatorButton("÷", role: .operation, metrics: metrics) { appendOperator("÷") }
                calculatorButton("×", role: .operation, metrics: metrics) { appendOperator("×") }
            }
            GridRow {
                calculatorButton("7", metrics: metrics) { appendDigit("7") }
                calculatorButton("8", metrics: metrics) { appendDigit("8") }
                calculatorButton("9", metrics: metrics) { appendDigit("9") }
                calculatorButton("-", role: .operation, metrics: metrics) { appendOperator("-") }
            }
            GridRow {
                calculatorButton("4", metrics: metrics) { appendDigit("4") }
                calculatorButton("5", metrics: metrics) { appendDigit("5") }
                calculatorButton("6", metrics: metrics) { appendDigit("6") }
                calculatorButton("+", role: .operation, metrics: metrics) { appendOperator("+") }
            }
            GridRow {
                calculatorButton("1", metrics: metrics) { appendDigit("1") }
                calculatorButton("2", metrics: metrics) { appendDigit("2") }
                calculatorButton("3", metrics: metrics) { appendDigit("3") }
                calculatorButton("=", role: .operation, metrics: metrics) { collapseToResultIfPossible() }
            }
            GridRow {
                calculatorButton("0", metrics: metrics) { appendDigit("0") }
                    .gridCellColumns(2)
                calculatorButton("00", metrics: metrics) { appendDigit("00") }
                calculatorButton("OK", role: .confirm, metrics: metrics) { commit() }
            }
        }
    }

    private func calculatorButton(
        _ title: String,
        role: CalculatorButtonRole = .number,
        metrics: CalculatorSheetMetrics,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(buttonFont(for: title, role: role, metrics: metrics))
                .foregroundStyle(role.foregroundStyle)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: metrics.buttonCornerRadius, style: .continuous)
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
        guard let integerResult = evaluation.integerResult else {
            alertMessage = validationMessage
            return
        }
        onCommit(MistiaAmountCalculatorLogic.committedInputText(for: integerResult))
        dismiss()
    }

    private var validationMessage: String {
        switch evaluation.error {
        case .divisionByZero:
            L10n.shared.amountCalculator.divisionByZero
        case .overflow:
            L10n.shared.amountCalculator.resultTooLarge
        case .fractionalResult,
             .nonPositiveResult,
             .invalidExpression,
             .incompleteExpression,
             .emptyExpression,
             nil:
            L10n.shared.amountCalculator.integerPositiveRequired
        }
    }

    private func decimalDisplayText(for value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func buttonFont(for title: String, role: CalculatorButtonRole, metrics: CalculatorSheetMetrics) -> Font {
        if title == "OK" {
            return .system(size: metrics.okFontSize, weight: .bold, design: .rounded)
        }

        switch role {
        case .number:
            return .system(size: metrics.numberFontSize, weight: .semibold, design: .rounded)
        case .operation, .utility, .confirm:
            return .system(size: metrics.operatorFontSize, weight: .semibold, design: .rounded)
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

private struct CalculatorSheetMetrics {
    let availableHeight: CGFloat

    private var compactness: CGFloat {
        let normalized = (availableHeight - 360) / 140
        return min(max(normalized, 0), 1)
    }

    var topPadding: CGFloat {
        14 + (20 * compactness)
    }

    var bottomPadding: CGFloat {
        10 + (8 * compactness)
    }

    var stackSpacing: CGFloat {
        10 + (6 * compactness)
    }

    var gridSpacing: CGFloat {
        7 + (3 * compactness)
    }

    var displayTextSpacing: CGFloat {
        4 + (2 * compactness)
    }

    var displayHorizontalPadding: CGFloat {
        16 + (2 * compactness)
    }

    var displayVerticalPadding: CGFloat {
        14 + (6 * compactness)
    }

    var displayHeight: CGFloat {
        88 + (24 * compactness)
    }

    var buttonHeight: CGFloat {
        let reservedHeight = topPadding
            + bottomPadding
            + displayHeight
            + stackSpacing
            + (gridSpacing * 4)
        let availableButtonHeight = (availableHeight - reservedHeight) / 5
        return min(max(availableButtonHeight, 40), 50)
    }

    var buttonCornerRadius: CGFloat {
        13 + (3 * compactness)
    }

    var expressionFontSize: CGFloat {
        13 + (2 * compactness)
    }

    var resultFontSize: CGFloat {
        29 + (7 * compactness)
    }

    var numberFontSize: CGFloat {
        19 + (3 * compactness)
    }

    var operatorFontSize: CGFloat {
        18 + (2 * compactness)
    }

    var okFontSize: CGFloat {
        15 + (2 * compactness)
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
