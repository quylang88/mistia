import SwiftUI

struct ManagementView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MistiaAppStorageKey.hideQuickCreate) private var hideQuickCreate = false
    @State private var showsSettings = false

    private let dump = MockDataLoader.management

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    var body: some View {
        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .muted,
                title: dump.headerTitle,
                embedsInNavigationStack: false,
                showsLeadingAvatar: false,
                trailingSystemImage: "gearshape",
                onTrailingTap: { showsSettings = true },
                contentSpacing: 20
            ) {
                ManagementProfileCard(profile: dump.profile, tint: cardTint, accent: accentPurple)

                ManagementSection(title: dump.accountsSectionTitle, titleColor: sectionLabelColor) {
                    ManagementCard(tint: cardTint) {
                        VStack(spacing: 0) {
                            ForEach(Array(dump.accounts.enumerated()), id: \.element.id) { index, account in
                                ManagementAccountRow(item: account)
                                if index < dump.accounts.count - 1 {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }

                            Divider()
                                .padding(.horizontal, 14)

                            ManagementInlineCTA(
                                title: "Thêm nguồn tiền mới",
                                message: "Sắp xếp ví, thẻ và tài khoản theo đúng nhịp quản lý của bạn.",
                                buttonTitle: dump.addAccountLabel,
                                accent: accentPurple,
                                symbols: ["creditcard.fill", "wallet.pass.fill", "building.columns.fill", "plus"]
                            )
                        }
                    }
                }

                ManagementSection(title: dump.categoriesSectionTitle, titleColor: sectionLabelColor) {
                    ManagementCard(tint: cardTint) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(dump.categoryGroupTitle)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 6)

                            ForEach(Array(dump.categories.enumerated()), id: \.element.id) { index, category in
                                ManagementCategoryRow(item: category)
                                if index < dump.categories.count - 1 {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }

                            Divider()
                                .padding(.horizontal, 14)

                            ManagementInlineCTA(
                                title: "Tạo danh mục riêng",
                                message: "Giữ những nhóm chi tiêu quan trọng trong một flow gọn và dễ chạm hơn.",
                                buttonTitle: dump.addCategoryLabel,
                                accent: accentPurple,
                                symbols: ["tag.fill", "square.grid.2x2.fill", "chart.bar.fill", "plus"]
                            )
                        }
                    }
                }

                ManagementSection(title: dump.dataSectionTitle, titleColor: sectionLabelColor) {
                    ManagementCard(tint: cardTint) {
                        VStack(spacing: 0) {
                            ForEach(Array(dump.dataActions.enumerated()), id: \.element.id) { index, action in
                                ManagementActionRow(item: action)
                                if index < dump.dataActions.count - 1 {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView()
            }
        }
        .onAppear {
            hideQuickCreate = showsSettings
        }
        .onChange(of: showsSettings, initial: true) { _, newValue in
            hideQuickCreate = newValue
        }
        .onDisappear {
            hideQuickCreate = false
        }
    }
}

private struct ManagementSection<Content: View>: View {
    let title: String
    let titleColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(titleColor)
                .padding(.horizontal, 2)

            content
        }
    }
}

private struct ManagementCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                ManagementCardBackground(tint: tint)
            }
    }
}

private struct ManagementProfileCard: View {
    let profile: ManagementProfileDump
    let tint: Color
    let accent: Color

    var body: some View {
        Button { } label: {
            ManagementCard(tint: tint) {
                HStack(spacing: 14) {
                    MistiaAvatarBadge(initials: profile.initials, size: 50, showsStatus: false)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(profile.email)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ManagementChevron()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20, tint: accent))
    }
}

private struct ManagementAccountRow: View {
    let item: ManagementAccountItemDump

    var body: some View {
        Button { } label: {
            HStack(alignment: .top, spacing: 12) {
                ManagementIconTile(icon: item.icon, accent: item.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let footnote = item.footnote {
                        Text(footnote)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let trailingAmount = item.trailingAmount {
                    Text(trailingAmount.mistiaCurrency)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }
}

private struct ManagementCategoryRow: View {
    let item: ManagementCategoryItemDump

    var body: some View {
        Button { } label: {
            HStack(spacing: 12) {
                ManagementIconTile(icon: item.icon, accent: item.accent)

                Text(item.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text(item.amount.mistiaCurrency)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                ManagementChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }
}

private struct ManagementActionRow: View {
    let item: ManagementActionItemDump

    var body: some View {
        Button { } label: {
            HStack(spacing: 12) {
                ManagementIconTile(icon: item.icon, accent: item.accent)

                Text(item.title)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(item.accent == .rose ? item.accent.color : .primary)

                Spacer()

                ManagementChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }
}

private struct ManagementInlineCTA: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let message: String
    let buttonTitle: String
    let accent: Color
    let symbols: [String]

    private var capsuleFill: Color {
        colorScheme == .dark ? accent.opacity(0.18) : accent.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.76, green: 0.69, blue: 1.0)
            : accent
    }

    private var symbolBackgroundOpacity: Double {
        colorScheme == .dark ? 0.16 : 0.10
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

            Button { } label: {
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(buttonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(capsuleFill)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(accent.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 0.8)
                    }
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 24, tint: buttonForeground))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

private struct ManagementIconTile: View {
    let icon: String
    let accent: MistiaAccent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.color.opacity(0.14))

            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent.color)
        }
        .frame(width: 30, height: 30)
    }
}

private struct ManagementChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tertiary)
    }
}

private struct ManagementCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.clear)
            .background {
                if #available(iOS 26, *) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            Glass.regular
                                .tint(tint)
                                .interactive(false),
                            in: .rect(cornerRadius: 20)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
