import SwiftUI
import UIKit

/// Modifier to dismiss keyboard when tapping outside input fields
extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

struct MistiaCurrencyInputField: View {
    let placeholder: String
    @Binding var text: String
    var font: UIFont = .mistiaRounded(size: 17, weight: .regular)
    var textColor: UIColor = .label
    var placeholderColor: UIColor = .tertiaryLabel
    var showsCalculatorButton: Bool = true
    var requestsFocus: Bool = false
    var selectsAllOnFocus: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.multilineTextAlignment) private var multilineTextAlignment
    @State private var isCalculatorPresented = false

    init(
        _ placeholder: String,
        text: Binding<String>,
        font: UIFont = .mistiaRounded(size: 17, weight: .regular),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .tertiaryLabel,
        showsCalculatorButton: Bool = true,
        requestsFocus: Bool = false,
        selectsAllOnFocus: Bool = false
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.showsCalculatorButton = showsCalculatorButton
        self.requestsFocus = requestsFocus
        self.selectsAllOnFocus = selectsAllOnFocus
    }

    var body: some View {
        HStack(spacing: 8) {
            MistiaCurrencyUITextField(
                placeholder,
                text: $text,
                font: font,
                textColor: textColor,
                placeholderColor: placeholderColor,
                textAlignment: multilineTextAlignment.uiTextAlignment,
                isEnabled: isEnabled,
                requestsFocus: requestsFocus,
                selectsAllOnFocus: selectsAllOnFocus
            )
            .frame(maxWidth: .infinity, alignment: multilineTextAlignment.frameAlignment)

            if showsCalculatorButton {
                MistiaSmallIconButton(
                    systemImage: "plus.forwardslash.minus",
                    accessibilityLabel: L10n.shared.amountCalculator.openCalculator,
                    isEnabled: isEnabled
                ) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    isCalculatorPresented = true
                }
            }
        }
        .sheet(isPresented: $isCalculatorPresented) {
            MistiaAmountCalculatorSheet(initialText: text) { committedText in
                text = committedText
            }
        }
    }
}

private struct MistiaCurrencyUITextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var textAlignment: NSTextAlignment
    var isEnabled: Bool
    var requestsFocus: Bool
    var selectsAllOnFocus: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        font: UIFont,
        textColor: UIColor,
        placeholderColor: UIColor,
        textAlignment: NSTextAlignment,
        isEnabled: Bool,
        requestsFocus: Bool,
        selectsAllOnFocus: Bool
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.textAlignment = textAlignment
        self.isEnabled = isEnabled
        self.requestsFocus = requestsFocus
        self.selectsAllOnFocus = selectsAllOnFocus
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.keyboardType = .numberPad
        textField.font = font
        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.isEnabled = isEnabled
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        applyPlaceholder(to: textField)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.font = font
        uiView.textColor = textColor
        uiView.textAlignment = textAlignment
        uiView.isEnabled = isEnabled
        applyPlaceholder(to: uiView)

        let grouped = MistiaCurrencyInputFormatting.groupedInput(text)
        if uiView.text != grouped {
            uiView.text = grouped
        }

        guard requestsFocus, !uiView.isFirstResponder else { return }

        DispatchQueue.main.async {
            guard requestsFocus else { return }
            uiView.becomeFirstResponder()
            if selectsAllOnFocus {
                uiView.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyPlaceholder(to textField: UITextField) {
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MistiaCurrencyUITextField

        init(parent: MistiaCurrencyUITextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            let grouped = MistiaCurrencyInputFormatting.groupedInput(textField.text ?? "")
            parent.text = grouped

            if textField.text != grouped {
                textField.text = grouped
            }
        }
    }
}

private extension TextAlignment {
    var uiTextAlignment: NSTextAlignment {
        switch self {
        case .leading:
            .natural
        case .center:
            .center
        case .trailing:
            .right
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }
}

extension UIFont {
    static func mistiaRounded(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedView: UIView?
        private weak var recognizer: UITapGestureRecognizer?

        func installIfNeeded(from markerView: UIView) {
            guard let container = markerView.window ?? markerView.superview, installedView !== container else { return }

            if let recognizer, let installedView {
                installedView.removeGestureRecognizer(recognizer)
            }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            container.addGestureRecognizer(recognizer)

            self.installedView = container
            self.recognizer = recognizer
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view else { return true }
            return !view.isInsideKeyboardDismissExcludedArea
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    var isInsideKeyboardDismissExcludedArea: Bool {
        if self is UIControl || self is UITextField || self is UITextView {
            return true
        }

        if NSStringFromClass(type(of: self)).contains("Cell") {
            return true
        }

        return superview?.isInsideKeyboardDismissExcludedArea ?? false
    }
}
