import SwiftUI

struct MistiaDestructiveActionSection: View {
    let buttonTitle: String
    let descriptionText: String?
    let popupMessage: String
    let confirmationButtonTitle: String?
    let showsCancelButton: Bool
    let action: () -> Void

    @State private var showsConfirmation = false

    init(
        buttonTitle: String,
        descriptionText: String? = nil,
        popupMessage: String,
        confirmationButtonTitle: String? = nil,
        showsCancelButton: Bool = true,
        action: @escaping () -> Void
    ) {
        self.buttonTitle = buttonTitle
        self.descriptionText = descriptionText
        self.popupMessage = popupMessage
        self.confirmationButtonTitle = confirmationButtonTitle
        self.showsCancelButton = showsCancelButton
        self.action = action
    }

    var body: some View {
        Section {
            Button(action: {
                showsConfirmation = true
            }) {
                Text(buttonTitle)
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "",
                isPresented: $showsConfirmation,
                titleVisibility: .hidden
            ) {
                Button(confirmationButtonTitle ?? buttonTitle, role: .destructive) {
                    action()
                }
                if showsCancelButton {
                    Button(L10n.common.cancel, role: .cancel) { }
                }
            } message: {
                Text(popupMessage)
            }
        } footer: {
            if let descriptionText {
                MistiaSectionFooter(descriptionText, isFormSection: true)
            }
        }
    }
}
