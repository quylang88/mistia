import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaAppStorageKey.mistiaShortcutKind) private var shortcutKindRawValue = MistiaShortcutKind.profile.rawValue
    @AppStorage(MistiaAppStorageKey.mistiaShortcutMemberUserID) private var shortcutMemberUserIDRawValue = ""

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

    private var storedShortcutSelection: MistiaShortcutSelection {
        MistiaShortcutSelection(
            storedKindRawValue: shortcutKindRawValue,
            storedMemberUserIDRawValue: shortcutMemberUserIDRawValue
        )
    }

    private var shortcutInput: MistiaShortcutResolveInput {
        MistiaShortcutResolveInput(
            currentUserInitials: sessionStore.summary?.initials ?? "MI",
            currentUserAvatarURL: sessionStore.summary?.avatarURL,
            familyID: familyContextStore.family?.id,
            canOpenFamilyHome: familyContextStore.canPresentFamilyHome,
            members: familyContextStore.members.map { member in
                MistiaShortcutMemberContext(
                    userID: member.userID,
                    displayName: member.displayName,
                    initials: String(member.displayName.prefix(2)).uppercased(),
                    avatarURL: member.avatarURL,
                    canView: familyContextStore.capabilities(for: member).canViewTarget,
                    isCurrentUser: member.userID == sessionStore.signedInUserID
                )
            }
        )
    }

    private var shortcutResolution: MistiaShortcutResolution {
        MistiaShortcutLogic.resolve(
            selection: storedShortcutSelection,
            input: shortcutInput
        )
    }

    private var shortcutNormalizationKey: String {
        let memberFingerprint = familyContextStore.members
            .map { member in
                let canView = familyContextStore.capabilities(for: member).canViewTarget ? "1" : "0"
                let isCurrent = member.userID == sessionStore.signedInUserID ? "1" : "0"
                return "\(member.userID.uuidString.lowercased()):\(canView):\(isCurrent)"
            }
            .sorted()
            .joined(separator: ",")

        return [
            shortcutKindRawValue,
            shortcutMemberUserIDRawValue,
            familyContextStore.family?.id.uuidString.lowercased() ?? "none",
            familyContextStore.canPresentFamilyHome ? "1" : "0",
            sessionStore.signedInUserID?.uuidString.lowercased() ?? "none",
            memberFingerprint
        ].joined(separator: "|")
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

    private var shortcutSection: SettingsSectionDump {
        SettingsSectionDump(
            rows: [
                SettingsRowDump(shortcutResolution: shortcutResolution)
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

                SettingsCardSection(
                    section: shortcutSection,
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
            case .shortcut:
                MistiaShortcutSettingsView()
            }
        }
        .task(id: shortcutNormalizationKey) {
            persistShortcutSelectionIfNeeded(shortcutResolution.selection)
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
        case .openShortcut:
            destination = .shortcut
        case .placeholder:
            break
        }
    }

    private func persistShortcutSelectionIfNeeded(_ selection: MistiaShortcutSelection) {
        guard shortcutKindRawValue != selection.storedKindRawValue
            || shortcutMemberUserIDRawValue != selection.storedMemberUserIDRawValue else {
            return
        }

        shortcutKindRawValue = selection.storedKindRawValue
        shortcutMemberUserIDRawValue = selection.storedMemberUserIDRawValue
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

private struct MistiaShortcutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.mistiaShortcutKind) private var shortcutKindRawValue = MistiaShortcutKind.profile.rawValue
    @AppStorage(MistiaAppStorageKey.mistiaShortcutMemberUserID) private var shortcutMemberUserIDRawValue = ""

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var storedSelection: MistiaShortcutSelection {
        MistiaShortcutSelection(
            storedKindRawValue: shortcutKindRawValue,
            storedMemberUserIDRawValue: shortcutMemberUserIDRawValue
        )
    }

    private var shortcutInput: MistiaShortcutResolveInput {
        MistiaShortcutResolveInput(
            currentUserInitials: sessionStore.summary?.initials ?? "MI",
            currentUserAvatarURL: sessionStore.summary?.avatarURL,
            familyID: familyContextStore.family?.id,
            canOpenFamilyHome: familyContextStore.canPresentFamilyHome,
            members: familyContextStore.members.map { member in
                MistiaShortcutMemberContext(
                    userID: member.userID,
                    displayName: member.displayName,
                    initials: String(member.displayName.prefix(2)).uppercased(),
                    avatarURL: member.avatarURL,
                    canView: familyContextStore.capabilities(for: member).canViewTarget,
                    isCurrentUser: member.userID == sessionStore.signedInUserID
                )
            }
        )
    }

    private var currentResolution: MistiaShortcutResolution {
        MistiaShortcutLogic.resolve(
            selection: storedSelection,
            input: shortcutInput
        )
    }

    private var normalizationKey: String {
        let memberFingerprint = familyContextStore.members
            .map { member in
                let canView = familyContextStore.capabilities(for: member).canViewTarget ? "1" : "0"
                let isCurrent = member.userID == sessionStore.signedInUserID ? "1" : "0"
                return "\(member.userID.uuidString.lowercased()):\(canView):\(isCurrent)"
            }
            .sorted()
            .joined(separator: ",")

        return [
            shortcutKindRawValue,
            shortcutMemberUserIDRawValue,
            familyContextStore.family?.id.uuidString.lowercased() ?? "none",
            familyContextStore.canPresentFamilyHome ? "1" : "0",
            sessionStore.signedInUserID?.uuidString.lowercased() ?? "none",
            memberFingerprint
        ].joined(separator: "|")
    }

    private var sections: [MistiaShortcutOptionSectionDump] {
        var output: [MistiaShortcutOptionSectionDump] = []

        let familySelections: [MistiaShortcutSelection] =
            [.familyOverview]
            + familyContextStore.members.map { member in
                MistiaShortcutSelection(kind: .familyMember, memberUserID: member.userID)
            }

        let familyRows = familySelections.compactMap(makeOption)
        if !familyRows.isEmpty {
            output.append(
                MistiaShortcutOptionSectionDump(
                    title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
                    rows: familyRows
                )
            )
        }

        let utilitySelections: [MistiaShortcutSelection] = [
            .profile,
            .syncSettings,
            .backupRestore,
            .archivedItems
        ]

        output.append(
            MistiaShortcutOptionSectionDump(
                title: mistiaLocalized(vi: "Tiện ích cá nhân", en: "Personal utilities", ja: "個人ユーティリティ"),
                rows: utilitySelections.compactMap(makeOption)
            )
        )

        return output
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Lối tắt Mistia", en: "Mistia shortcut", ja: "Mistia ショートカット"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            Text(
                mistiaLocalized(
                    vi: "Nút pinned trên tab bar sẽ mở thẳng mục bạn chọn ở đây.",
                    en: "The pinned button in the tab bar will open the destination you choose here.",
                    ja: "タブバーの固定ボタンは、ここで選んだ項目を直接開きます。"
                )
            )
            .descriptionTextStyle()
            .padding(.horizontal, 2)

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    MistiaShortcutOptionSectionCard(
                        section: section,
                        selectedSelection: currentResolution.selection,
                        tint: cardTint,
                        accentPurple: accentPurple
                    ) { selection in
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            shortcutKindRawValue = selection.storedKindRawValue
                            shortcutMemberUserIDRawValue = selection.storedMemberUserIDRawValue
                        }
                    }
                }
            }
        }
        .task(id: normalizationKey) {
            persistIfNeeded(currentResolution.selection)
        }
    }

    private func makeOption(_ selection: MistiaShortcutSelection) -> MistiaShortcutOptionRowDump? {
        let resolution = MistiaShortcutLogic.resolve(selection: selection, input: shortcutInput)
        guard resolution.selection == selection else { return nil }

        return MistiaShortcutOptionRowDump(
            selection: selection,
            presentation: resolution.presentation,
            subtitle: subtitle(for: resolution.presentation)
        )
    }

    private func subtitle(for presentation: MistiaShortcutPresentation) -> String? {
        switch presentation.action {
        case .profile:
            return mistiaLocalized(
                vi: "Mở hồ sơ, tài khoản và phần quản lý chính của Mistia.",
                en: "Open your profile, account, and main management area.",
                ja: "プロフィール、アカウント、管理画面を開きます。"
            )

        case .syncSettings:
            return mistiaLocalized(
                vi: "Mở cài đặt đồng bộ. Nếu sync chưa sẵn sàng, nút sẽ đưa về Hồ sơ.",
                en: "Open sync settings. If sync is not ready yet, the button falls back to Profile.",
                ja: "同期設定を開きます。同期の準備ができていない場合はプロフィールを開きます。"
            )

        case .backupRestore:
            return mistiaLocalized(
                vi: "Mở sao lưu cục bộ và khôi phục dữ liệu.",
                en: "Open local backup and restore.",
                ja: "ローカルのバックアップと復元を開きます。"
            )

        case .archivedItems:
            return mistiaLocalized(
                vi: "Mở các ví, danh mục và giao dịch đã lưu trữ.",
                en: "Open archived wallets, categories, and transactions.",
                ja: "アーカイブ済みのウォレット、カテゴリ、取引を開きます。"
            )

        case .familyOverview:
            return mistiaLocalized(
                vi: "Mở thẳng màn tổng quan tài chính của cả gia đình.",
                en: "Open the family financial overview directly.",
                ja: "家族全体の財務概要を直接開きます。"
            )

        case .memberOverview:
            return mistiaLocalized(
                vi: "Chuyển ngay sang chế độ xem dữ liệu của thành viên này trong tab Tổng quan.",
                en: "Jump straight into this member's data in Overview.",
                ja: "概要タブでこのメンバーのデータへすぐ移動します。"
            )
        }
    }

    private func persistIfNeeded(_ selection: MistiaShortcutSelection) {
        guard shortcutKindRawValue != selection.storedKindRawValue
            || shortcutMemberUserIDRawValue != selection.storedMemberUserIDRawValue else {
            return
        }

        shortcutKindRawValue = selection.storedKindRawValue
        shortcutMemberUserIDRawValue = selection.storedMemberUserIDRawValue
    }
}

private struct MistiaShortcutOptionSectionCard: View {
    let section: MistiaShortcutOptionSectionDump
    let selectedSelection: MistiaShortcutSelection
    let tint: Color
    let accentPurple: Color
    let onSelect: (MistiaShortcutSelection) -> Void

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        onSelect(row.selection)
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIconTile(iconContent: row.presentation.settingsRowIconContent)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.presentation.title)
                                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 10)

                            if row.selection == selectedSelection {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(MistiaAccent.lightPurple.color)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 15)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accentPurple))

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
                SettingsIconTile(iconContent: row.iconContent)

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
    let iconContent: SettingsRowIconContent

    var body: some View {
        switch iconContent {
        case .system(let icon, let accent):
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.color.opacity(0.15))

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent.color)
            }
            .frame(width: 32, height: 32)

        case .currentUserAvatar(let initials, let avatarURL),
             .memberAvatar(let initials, let avatarURL):
            MistiaAvatarBadge(
                initials: initials,
                avatarURL: avatarURL,
                size: 32,
                showsStatus: false
            )
        }
    }
}

private struct SettingsSectionDump: Identifiable {
    let rows: [SettingsRowDump]

    var id: String {
        rows.map(\.id).joined(separator: "-")
    }
}

private struct MistiaShortcutOptionSectionDump: Identifiable {
    let title: String
    let rows: [MistiaShortcutOptionRowDump]

    var id: String { title }
}

private struct MistiaShortcutOptionRowDump: Identifiable {
    let selection: MistiaShortcutSelection
    let presentation: MistiaShortcutPresentation
    let subtitle: String?

    var id: String {
        [
            selection.storedKindRawValue,
            selection.storedMemberUserIDRawValue
        ].joined(separator: "-")
    }
}

private struct SettingsRowDump: Identifiable {
    let title: String
    let iconContent: SettingsRowIconContent
    let value: String?
    let action: SettingsRowAction

    var id: String { title }
}

private enum SettingsRowIconContent: Equatable {
    case system(icon: String, accent: MistiaAccent)
    case currentUserAvatar(initials: String, avatarURL: URL?)
    case memberAvatar(initials: String, avatarURL: URL?)
}

private enum SettingsRowAction {
    case openAppearance
    case openLanguage
    case openBackupRestore
    case openArchivedItems
    case openShortcut
    case placeholder
}

private enum SettingsDestination: String, Identifiable {
    case appearance
    case language
    case backupRestore
    case archivedItems
    case shortcut

    var id: String { rawValue }
}

private extension SettingsRowDump {
    init(
        title: String,
        icon: String,
        accent: MistiaAccent,
        value: String?,
        action: SettingsRowAction
    ) {
        self.init(
            title: title,
            iconContent: .system(icon: icon, accent: accent),
            value: value,
            action: action
        )
    }

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

    init(shortcutResolution: MistiaShortcutResolution) {
        self.init(
            title: mistiaLocalized(vi: "Lối tắt Mistia", en: "Mistia shortcut", ja: "Mistia ショートカット"),
            iconContent: shortcutResolution.presentation.settingsRowIconContent,
            value: shortcutResolution.presentation.title,
            action: .openShortcut
        )
    }
}

private extension MistiaShortcutPresentation {
    var settingsRowIconContent: SettingsRowIconContent {
        switch icon {
        case .systemImage(let systemName):
            SettingsRowIconContent.system(
                icon: systemName,
                accent: selectionAccent
            )

        case .currentUserAvatar(let initials, let avatarURL):
            .currentUserAvatar(initials: initials, avatarURL: avatarURL)

        case .memberAvatar(let initials, let avatarURL):
            .memberAvatar(initials: initials, avatarURL: avatarURL)
        }
    }

    private var selectionAccent: MistiaAccent {
        switch action {
        case .profile:
            .rose
        case .syncSettings:
            .sky
        case .backupRestore:
            .mint
        case .archivedItems:
            .slate
        case .familyOverview:
            .indigo
        case .memberOverview:
            .rose
        }
    }
}
