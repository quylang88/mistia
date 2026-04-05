import SwiftUI

struct MistiaArchiveSection: View {
    let buttonTitle: String
    let descriptionText: String
    let popupMessage: String
    let action: () -> Void

    @State private var isShowingPopup = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.snappy) {
                    isShowingPopup.toggle()
                }
            }) {
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        colorScheme == .dark
                            ? Color(UIColor.secondarySystemGroupedBackground)
                            : .white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                if isShowingPopup {
                    MistiaArchivePopup(
                        message: popupMessage,
                        actionTitle: buttonTitle,
                        onConfirm: {
                            withAnimation(.snappy) {
                                isShowingPopup = false
                            }
                            action()
                        }
                    )
                    .alignmentGuide(.bottom) { d in d[.bottom] + d.height + 8 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(99)
                }
            }

            Text(descriptionText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onTapGesture {
            if isShowingPopup {
                withAnimation(.snappy) {
                    isShowingPopup = false
                }
            }
        }
    }
}

private struct MistiaArchivePopup: View {
    let message: String
    let actionTitle: String
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onConfirm) {
                Text(actionTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.9), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(
            colorScheme == .dark ? Color(white: 0.15) : .white,
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 16)
    }
}
