import SwiftUI
import UIKit

/// Modifier to dismiss keyboard when tapping outside input fields
extension View {
    func dismissKeyboardOnTap() -> some View {
        self
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    hideKeyboard()
                }
            )
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
