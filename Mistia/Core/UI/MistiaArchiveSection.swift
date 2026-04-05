import SwiftUI

struct MistiaArchiveSection: View {
    let buttonTitle: String
    let descriptionText: String
    let popupMessage: String
    let action: () -> Void

    @State private var showsConfirmation = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                showsConfirmation = true
            }) {
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "",
                isPresented: $showsConfirmation,
                titleVisibility: .hidden
            ) {
                Button(buttonTitle, role: .destructive) {
                    action()
                }
                Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
            } message: {
                Text(popupMessage)
            }
            
            Text(descriptionText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
