import SwiftUI
import UIKit

/// Modifier to dismiss keyboard when tapping outside input fields
extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

extension Binding where Value == String {
    func currencyInputGrouped() -> Binding<String> {
        Binding(
            get: {
                MistiaCurrencyInputFormatting.groupedInput(wrappedValue)
            },
            set: { newValue in
                wrappedValue = MistiaCurrencyInputFormatting.groupedInput(newValue)
            }
        )
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
