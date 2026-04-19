import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
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

    private var customizationSection: SettingsSectionDump {
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
        )
    }

    private var preferencesSection: SettingsSectionDump {
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
        )
    }

    private var dataSection: SettingsSectionDump {
        SettingsSectionDump(
            rows: [
                SettingsRowDump(dataAction: .backupRestore),
                SettingsRowDump(dataAction: .archivedItems)
            ]
        )
    }

    private var habitsSection: SettingsSectionDump {
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
        )
    }

    private var feedbackSection: SettingsSectionDump {
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
                SettingsCardSection(
                    section: customizationSection,
                    tint: cardTint,
                    accentPurple: accentPurple,
                    onTap: handleTap
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mistiaLocalized(
                        vi: "Tùy chỉnh giao diện, ngôn ngữ và tiền tệ sẽ áp dụng cho toàn bộ ứng dụng Mistia.",
                        en: "Customizing appearance, language, and currency will apply throughout the Mistia app.",
                        ja: "表示、言語、通貨をカスタマイズするとMistia全体に適用されます。"
                    ))
                    .descriptionTextStyle()
                    .padding(.horizontal, 2)
                }
                .cardDescriptionStyle()

                SettingsCardSection(
                    section: preferencesSection,
                    tint: cardTint,
                    accentPurple: accentPurple,
                    onTap: handleTap
                )

                SettingsCardSection(
                    section: dataSection,
                    tint: cardTint,
                    accentPurple: accentPurple,
                    onTap: handleTap
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(mistiaLocalized(
                        vi: "Mở lại mục đã lưu trữ hoặc quản lý bản sao lưu cục bộ để dữ liệu Mistia luôn sẵn sàng khi bạn cần khôi phục.",
                        en: "Review archived items and manage local snapshots so your Mistia data stays ready when you need to restore it.",
                        ja: "アーカイブ済みアイテムの確認やローカルスナップショットの管理を行い、必要なときに Mistia のデータを復元できるようにします。"
                    ))
                    .descriptionTextStyle()
                    .padding(.horizontal, 2)
                }
                .cardDescriptionStyle()

                SettingsCardSection(
                    section: habitsSection,
                    tint: cardTint,
                    accentPurple: accentPurple,
                    onTap: handleTap
                )

                SettingsCardSection(
                    section: feedbackSection,
                    tint: cardTint,
                    accentPurple: accentPurple,
                    onTap: handleTap
                )
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
            case .backupRestore:
                ManagementBackupRestoreView()
            case .archivedItems:
                ManagementArchivedItemsView()
            }
        }
    }

    private func handleTap(_ row: SettingsRowDump) {
        switch row.action {
        case .openAppearance:
            destination = .appearance
        case .openLanguage:
            destination = .language
        case .openBackupRestore:
            destination = .backupRestore
        case .openArchivedItems:
            destination = .archivedItems
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
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""

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
                    MistiaAppLanguage.persist(language)
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
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
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
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
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
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MistiaAccent.lightPurple.color)
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MistiaAccent.lightPurple.color)
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
    case openBackupRestore
    case openArchivedItems
    case placeholder
}

private enum SettingsDestination: String, Identifiable {
    case appearance
    case language
    case backupRestore
    case archivedItems

    var id: String { rawValue }
}

private extension SettingsRowDump {
    init(dataAction: ManagementDataActionKind) {
        switch dataAction {
        case .backupRestore:
            self.init(
                title: dataAction.title,
                icon: dataAction.iconSymbolName,
                accent: .mint,
                value: nil,
                action: .openBackupRestore
            )
        case .archivedItems:
            self.init(
                title: dataAction.title,
                icon: dataAction.iconSymbolName,
                accent: .slate,
                value: nil,
                action: .openArchivedItems
            )
        case .exportData, .importData, .deleteAllData:
            self.init(
                title: dataAction.title,
                icon: dataAction.iconSymbolName,
                accent: .purple,
                value: nil,
                action: .placeholder
            )
        }
    }
}
