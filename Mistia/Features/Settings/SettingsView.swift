import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = MistiaAppLanguage.english.rawValue
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @State private var destination: SettingsDestination?

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var appearanceMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }

    private var appLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }

    private var sections: [SettingsSectionDump] {
        [
            SettingsSectionDump(
                rows: [
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Giao diện", en: "Appearance", ja: "表示"),
                        icon: "moon.stars.fill",
                        accent: .indigo,
                        value: appearanceMode.title,
                        action: .openAppearance
                    ),
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Ngôn ngữ", en: "Language", ja: "言語"),
                        icon: "globe.asia.australia.fill",
                        accent: .sky,
                        value: appLanguage.displayName,
                        action: .openLanguage
                    ),
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨"),
                        icon: "yensign.circle.fill",
                        accent: .amber,
                        value: currencyCode,
                        action: .placeholder
                    )
                ]
            ),
            SettingsSectionDump(
                rows: [
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Thông báo", en: "Notifications", ja: "通知"),
                        icon: "bell.badge.fill",
                        accent: .coral,
                        value: nil,
                        action: .placeholder
                    ),
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Bảo mật", en: "Security", ja: "セキュリティ"),
                        icon: "lock.shield.fill",
                        accent: .mint,
                        value: nil,
                        action: .placeholder
                    )
                ]
            ),
            SettingsSectionDump(
                rows: [
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Thói quen", en: "Habits", ja: "習慣"),
                        icon: "circle.hexagongrid.fill",
                        accent: .rose,
                        value: nil,
                        action: .placeholder
                    )
                ]
            ),
            SettingsSectionDump(
                rows: [
                    SettingsRowDump(
                        title: mistiaLocalized(vi: "Gửi feedback", en: "Send feedback", ja: "フィードバック"),
                        icon: "bubble.left.and.bubble.right.fill",
                        accent: .indigo,
                        value: nil,
                        action: .placeholder
                    )
                ]
            )
        ]
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Cài đặt", en: "Settings", ja: "設定"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            VStack(spacing: 18) {
                ForEach(sections) { section in
                    SettingsCardSection(
                        section: section,
                        tint: cardTint,
                        accentPurple: accentPurple,
                        onTap: handleTap
                    )
                }
            }

            SettingsVersionFooter()
                .padding(.top, 6)
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .appearance:
                AppearanceSettingsView()
            case .language:
                LanguageSettingsView()
            }
        }
    }

    private func handleTap(_ row: SettingsRowDump) {
        switch row.action {
        case .openAppearance:
            destination = .appearance
        case .openLanguage:
            destination = .language
        case .placeholder:
            break
        }
    }
}

private struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var selectedMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Giao diện", en: "Appearance", ja: "表示"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            AppearanceModeCard(
                selectedMode: selectedMode,
                accentPurple: accentPurple
            ) { mode in
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    appearanceModeRawValue = mode.rawValue
                }
            }
        }
    }
}

private struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = MistiaAppLanguage.english.rawValue

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var selectedLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Ngôn ngữ", en: "Language", ja: "言語"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            LanguageSelectionCard(
                selectedLanguage: selectedLanguage,
                accentPurple: accentPurple
            ) { language in
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    appLanguageRawValue = language.rawValue
                }
            }
        }
    }
}

private struct SettingsCardSection: View {
    let section: SettingsSectionDump
    let tint: Color
    let accentPurple: Color
    let onTap: (SettingsRowDump) -> Void

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    SettingsRowButton(row: row, accentPurple: accentPurple) {
                        onTap(row)
                    }

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}

private struct SettingsRowButton: View {
    let row: SettingsRowDump
    let accentPurple: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIconTile(icon: row.icon, accent: row.accent)

                Text(row.title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(titleColor)

                Spacer(minLength: 10)

                if let value = row.value {
                    Text(value)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(valueColor.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accentPurple))
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.82)
    }

    private var valueColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : Color.black.opacity(0.48)
    }
}

private struct AppearanceModeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedMode: MistiaAppearanceMode
    let accentPurple: Color
    let onSelect: (MistiaAppearanceMode) -> Void

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(MistiaAppearanceMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        AppearanceModeRow(
                            mode: mode,
                            isSelected: mode == selectedMode,
                            accentPurple: accentPurple
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accentPurple))

                    if index < MistiaAppearanceMode.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }
}

private struct LanguageSelectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedLanguage: MistiaAppLanguage
    let accentPurple: Color
    let onSelect: (MistiaAppLanguage) -> Void

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(MistiaAppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                    Button {
                        onSelect(language)
                    } label: {
                        LanguageOptionRow(
                            language: language,
                            isSelected: language == selectedLanguage,
                            accentPurple: accentPurple
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accentPurple))

                    if index < MistiaAppLanguage.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }
}

private struct AppearanceModeRow: View {
    let mode: MistiaAppearanceMode
    let isSelected: Bool
    let accentPurple: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(mode.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if isSelected {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentPurple.opacity(colorScheme == .dark ? 0.98 : 0.90),
                                    Color(red: 0.62, green: 0.45, blue: 0.94).opacity(colorScheme == .dark ? 0.96 : 0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.24 : 0.56), lineWidth: 0.9)

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.98))
                }
                .frame(width: 26, height: 26)
                .shadow(color: accentPurple.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: colorScheme == .dark ? 8 : 4, y: 1)
            }
        }
    }
}

private struct LanguageOptionRow: View {
    let language: MistiaAppLanguage
    let isSelected: Bool
    let accentPurple: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(language.displayName)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if isSelected {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentPurple.opacity(colorScheme == .dark ? 0.98 : 0.90),
                                    Color(red: 0.62, green: 0.45, blue: 0.94).opacity(colorScheme == .dark ? 0.96 : 0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.24 : 0.56), lineWidth: 0.9)

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.98))
                }
                .frame(width: 26, height: 26)
                .shadow(color: accentPurple.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: colorScheme == .dark ? 8 : 4, y: 1)
            }
        }
    }
}

private struct SettingsVersionFooter: View {
    var body: some View {
        VStack(spacing: 3) {
            Text("Mistia")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(mistiaLocalized(
                vi: "version 16.09 powered by Quý Lăng",
                en: "version 16.09 powered by Quy Lang",
                ja: "version 16.09 powered by Quy Lang"
            ))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct SettingsIconTile: View {
    let icon: String
    let accent: MistiaAccent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.color.opacity(0.15))

            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent.color)
        }
        .frame(width: 32, height: 32)
    }
}

private struct SettingsSectionDump: Identifiable {
    let rows: [SettingsRowDump]

    var id: String {
        rows.map(\.id).joined(separator: "-")
    }
}

private struct SettingsRowDump: Identifiable {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let value: String?
    let action: SettingsRowAction

    var id: String { title }
}

private enum SettingsRowAction {
    case openAppearance
    case openLanguage
    case placeholder
}

private enum SettingsDestination: String, Identifiable {
    case appearance
    case language

    var id: String { rawValue }
}
