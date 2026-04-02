import SwiftUI

struct MistiaBlockCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var tint: Color = .white.opacity(0.12)
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background {
                if #available(iOS 26, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            Glass.regular
                                .tint(tint)
                                .interactive(false),
                            in: .rect(cornerRadius: cornerRadius)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.08 : 0.26),
                                .white.opacity(colorScheme == .dark ? 0.03 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.14 : 0.035),
                radius: 10,
                y: 4
            )
    }
}

struct MistiaBlockCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var tint: Color = .white.opacity(0.12)
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                MistiaBlockCardBackground(
                    tint: tint,
                    cornerRadius: cornerRadius
                )
            }
    }
}

struct MistiaFooterAddButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var accent: Color = Color(red: 0.43, green: 0.23, blue: 0.76)
    let action: () -> Void

    private var buttonFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(buttonForeground)

                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(buttonForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(buttonFill)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16, tint: buttonForeground))
    }
}

struct MistiaEmptyStateContent: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let buttonTitle: String?
    var accent: Color = Color(red: 0.43, green: 0.23, blue: 0.76)
    let symbols: [String]
    var action: (() -> Void)? = nil

    private var capsuleFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : accent
    }

    private var symbolBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.10
    }

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    ZStack {
                        Circle()
                            .fill(accent.opacity(symbolBackgroundOpacity + Double(index) * 0.025))

                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(buttonForeground)
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(buttonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            Capsule()
                                .fill(capsuleFill)
                        }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 24, tint: buttonForeground))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
