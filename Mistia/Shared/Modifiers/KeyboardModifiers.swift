import SwiftUI
import UIKit

/// Modifier to dismiss keyboard when tapping outside input fields
extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

struct MistiaCurrencyInputField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var font: UIFont = .mistiaRounded(size: 17, weight: .regular)
    var textColor: UIColor = .label
    var placeholderColor: UIColor = .tertiaryLabel

    init(
        _ placeholder: String,
        text: Binding<String>,
        font: UIFont = .mistiaRounded(size: 17, weight: .regular),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .tertiaryLabel
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.keyboardType = .numberPad
        textField.font = font
        textField.textColor = textColor
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
        applyPlaceholder(to: uiView)

        let grouped = MistiaCurrencyInputFormatting.groupedInput(text)
        if uiView.text != grouped {
            uiView.text = grouped
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
        var parent: MistiaCurrencyInputField

        init(parent: MistiaCurrencyInputField) {
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
