import SwiftUI

struct MistiaHistorySuggestionsPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let suggestions: [TransactionTitleSuggestion]
    let onApply: (TransactionTitleSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onApply(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(suggestion.title)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, 39)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular
                            .tint(colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.12))
                            .interactive(true),
                        in: .rect(cornerRadius: 18)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.06),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.12) : .black.opacity(0.05),
            radius: 10,
            y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
