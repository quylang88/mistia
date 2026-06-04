import SwiftUI

struct MistiaDestructiveActionSection: View {
    private let cornerRadius: CGFloat = 12

    let buttonTitle: String
    let descriptionText: String?
    let popupMessage: String
    let confirmationButtonTitle: String?
    let action: () -> Void

    @State private var showsConfirmation = false

    init(
        buttonTitle: String,
        descriptionText: String? = nil,
        popupMessage: String,
        confirmationButtonTitle: String? = nil,
        action: @escaping () -> Void
    ) {
        self.buttonTitle = buttonTitle
        self.descriptionText = descriptionText
        self.popupMessage = popupMessage
        self.confirmationButtonTitle = confirmationButtonTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                showsConfirmation = true
            }) {
                Text(buttonTitle)
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(
                Color(UIColor.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .buttonStyle(.plain)
            .confirmationDialog(
                "",
                isPresented: $showsConfirmation,
                titleVisibility: .hidden
            ) {
                Button(confirmationButtonTitle ?? buttonTitle, role: .destructive) {
                    action()
                }
                Button(L10n.common.cancel, role: .cancel) { }
            } message: {
                Text(popupMessage)
            }

            if let descriptionText {
                Text(descriptionText)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
