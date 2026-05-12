import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaAppStorageKey.mistiaShortcutEnabled) private var mistiaShortcutEnabled = false
    @AppStorage(MistiaAppStorageKey.mistiaShortcutKind) private var shortcutKindRawValue = MistiaShortcutKind.backupRestore.rawValue
    @AppStorage(MistiaAppStorageKey.mistiaShortcutMemberUserID) private var shortcutMemberUserIDRawValue = ""
    @AppStorage(MistiaAppStorageKey.notificationsEnabled) private var notificationsEnabled = false

    @State private var destination: SettingsDestination?

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
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
                    value: notificationStatusText,
                    action: .openNotifications
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

    private var notificationStatusText: String {
        notificationsEnabled
            ? mistiaLocalized(vi: "Bật", en: "On", ja: "オン")
            : mistiaLocalized(vi: "Tắt", en: "Off", ja: "オフ")
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
        let row: SettingsRowDump
        if mistiaShortcutEnabled {
            row = SettingsRowDump(shortcutResolution: shortcutResolution)
        } else {
            row = SettingsRowDump(
                title: mistiaLocalized(vi: "Lối tắt Mistia", en: "Mistia shortcut", ja: "Mistia ショートカット"),
                icon: "pin.slash",
                accent: .slate,
                value: mistiaLocalized(vi: "Đang tắt", en: "Off", ja: "オフ"),
                action: .openShortcut
            )
        }

        return SettingsSectionDump(rows: [row])
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

    private var resetDataSection: SettingsSectionDump {
        SettingsSectionDump(
            rows: [
                SettingsRowDump(
                    title: mistiaLocalized(vi: "Đặt lại & dữ liệu", en: "Reset & data", ja: "リセットとデータ"),
                    icon: "gearshape.2.fill",
                    accent: .amber,
                    value: nil,
                    action: .openResetData
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
                    onTap: handleTap
                )

                SettingsCardSection(
                    section: preferencesSection,
                    tint: cardTint,
                    onTap: handleTap
                )

                SettingsCardSection(
                    section: dataSection,
                    tint: cardTint,
                    onTap: handleTap
                )

                SettingsCardSection(
                    section: shortcutSection,
                    tint: cardTint,
                    onTap: handleTap
                )

                Text(
                    mistiaLocalized(
                        vi: "Bật Lối tắt Mistia để hiện nút pinned ở tab bar. Nút này sẽ mở thẳng mục bạn chọn.",
                        en: "Enable the Mistia shortcut to show a pinned button in the tab bar. It opens the destination you choose.",
                        ja: "Mistia ショートカットを有効にするとタブバーに固定ボタンが表示されます。選んだ項目を直接開きます。"
                    )
                )
                .descriptionTextStyle()
                .cardDescriptionStyle()

                SettingsCardSection(
                    section: resetDataSection,
                    tint: cardTint,
                    onTap: handleTap
                )

                SettingsCardSection(
                    section: feedbackSection,
                    tint: cardTint,
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
            case .notifications:
                NotificationsSettingsView()
            case .backupRestore:
                ManagementBackupRestoreView()
            case .archivedItems:
                ManagementArchivedItemsView()
            case .shortcut:
                MistiaShortcutSettingsView()
            case .resetData:
                ResetDataSettingsView()
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
        case .openNotifications:
            destination = .notifications
        case .openBackupRestore:
            destination = .backupRestore
        case .openArchivedItems:
            destination = .archivedItems
        case .openShortcut:
            destination = .shortcut
        case .openResetData:
            destination = .resetData
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
    @AppStorage(MistiaAppStorageKey.mistiaShortcutEnabled) private var mistiaShortcutEnabled = false
    @AppStorage(MistiaAppStorageKey.mistiaShortcutKind) private var shortcutKindRawValue = MistiaShortcutKind.backupRestore.rawValue
    @AppStorage(MistiaAppStorageKey.mistiaShortcutMemberUserID) private var shortcutMemberUserIDRawValue = ""

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
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

        let utilitySelections: [MistiaShortcutSelection] = {
            var selections: [MistiaShortcutSelection] = [
                .backupRestore,
                .archivedItems
            ]
            // syncNow only available when signed in AND initial sync is completed
            if sessionStore.isSignedIn && !sessionStore.requiresInitialSync {
                selections.append(.syncNow)
            }
            return selections
        }()

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
            Toggle(
                mistiaLocalized(
                    vi: "Bật nút pinned",
                    en: "Enable pinned button",
                    ja: "固定ボタンを有効にする"
                ),
                isOn: $mistiaShortcutEnabled
            )
            .tint(MistiaAccent.purple.color)
            .toggleStyle(.switch)
            .onChange(of: mistiaShortcutEnabled) { _, newValue in
                guard newValue else { return }
                let availableSelections: Set<String> = Set(
                    sections.flatMap { $0.rows.map { $0.selection.storedKindRawValue } }
                )
                guard !availableSelections.contains(shortcutKindRawValue) else { return }
                guard let firstSelection = sections.first?.rows.first?.selection else { return }
                shortcutKindRawValue = firstSelection.storedKindRawValue
                shortcutMemberUserIDRawValue = firstSelection.storedMemberUserIDRawValue
            }

            if mistiaShortcutEnabled {
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
                        ) { selection in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                shortcutKindRawValue = selection.storedKindRawValue
                                shortcutMemberUserIDRawValue = selection.storedMemberUserIDRawValue
                            }
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

        case .syncNow:
            return mistiaLocalized(
                vi: "Đồng bộ dữ liệu ngay lập tức với cloud.",
                en: "Sync data immediately with cloud.",
                ja: "すぐにクラウドとデータを同期します。"
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

private struct ResetDataSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    @State private var showsResetOptions = false
    @State private var showsResetCategoriesConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var statusAlert: ResetDataStatusAlert?
    @State private var isWorking = false

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Đặt lại & dữ liệu", en: "Reset & data", ja: "リセットとデータ"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    ResetDataActionRow(
                        title: mistiaLocalized(vi: "Reset", en: "Reset", ja: "リセット"),
                        icon: "arrow.clockwise.circle.fill",
                        accent: .sky,
                        role: nil,
                        isDestructive: false,
                        isWorking: isWorking
                    ) {
                        showsResetOptions = true
                    }

                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 0)

                    ResetDataActionRow(
                        title: mistiaLocalized(vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除"),
                        icon: "trash.fill",
                        accent: .expense,
                        role: .destructive,
                        isDestructive: true,
                        isWorking: isWorking
                    ) {
                        showsDeleteConfirmation = true
                    }
                }
            }
        }
        .alert(
            mistiaLocalized(vi: "Reset", en: "Reset", ja: "リセット"),
            isPresented: $showsResetOptions
        ) {
            Button(mistiaLocalized(vi: "Reset cài đặt", en: "Reset settings", ja: "設定をリセット")) {
                resetSettings()
            }
            Button(mistiaLocalized(vi: "Reset thông báo", en: "Reset notifications", ja: "通知をリセット")) {
                resetNotifications()
            }
            Button(
                mistiaLocalized(vi: "Reset danh mục", en: "Reset categories", ja: "カテゴリをリセット"),
                role: .destructive
            ) {
                showsResetCategoriesConfirmation = true
            }
            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(
                mistiaLocalized(
                    vi: "Chọn phần bạn muốn đưa về trạng thái ban đầu.",
                    en: "Choose what you want to return to its default state.",
                    ja: "初期状態に戻す項目を選んでください。"
                )
            )
        }
        .alert(
            mistiaLocalized(vi: "Reset danh mục?", en: "Reset categories?", ja: "カテゴリをリセットしますか？"),
            isPresented: $showsResetCategoriesConfirmation
        ) {
            Button(
                mistiaLocalized(vi: "Reset danh mục", en: "Reset categories", ja: "カテゴリをリセット"),
                role: .destructive
            ) {
                resetCategories()
            }
            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(
                mistiaLocalized(
                    vi: "Danh mục system sẽ về mặc định. Danh mục tự tạo được chuyển vào lưu trữ.",
                    en: "System categories return to defaults. Custom categories move to archived items.",
                    ja: "システムカテゴリを初期状態に戻し、作成したカテゴリはアーカイブに移動します。"
                )
            )
        }
        .alert(
            mistiaLocalized(vi: "Xóa tất cả dữ liệu?", en: "Delete all data?", ja: "すべてのデータを削除しますか？"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(
                mistiaLocalized(vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除"),
                role: .destructive
            ) {
                deleteAllLocalData()
            }
            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(
                mistiaLocalized(
                    vi: "Mistia chỉ xóa dữ liệu local trên thiết bị này. Đăng nhập, hồ sơ cloud và gia đình vẫn được giữ.",
                    en: "Mistia will only clear local data on this device. Sign-in, cloud profile, and family are preserved.",
                    ja: "この端末のローカルデータのみを削除します。ログイン、クラウドプロフィール、家族は保持されます。"
                )
            )
        }
        .alert(item: $statusAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(mistiaLocalized(vi: "OK", en: "OK", ja: "OK")))
            )
        }
    }

    private func resetSettings() {
        MistiaSettingsResetSupport.resetAppPreferences()
        sessionStore.setAutoSyncEnabled(false)
        statusAlert = ResetDataStatusAlert(
            title: mistiaLocalized(vi: "Đã reset cài đặt", en: "Settings reset", ja: "設定をリセットしました"),
            message: mistiaLocalized(
                vi: "Cài đặt app đã về mặc định. Dữ liệu, đăng nhập và gia đình không bị thay đổi.",
                en: "App settings are back to defaults. Data, sign-in, and family were not changed.",
                ja: "アプリ設定を初期状態に戻しました。データ、ログイン、家族は変更していません。"
            )
        )
    }

    private func resetNotifications() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try MistiaNotificationStore.clearAll(in: sessionStore.currentModelContainer.mainContext)
                await MistiaLocalNotificationScheduler.clearAllScheduledReminders()
                statusAlert = ResetDataStatusAlert(
                    title: mistiaLocalized(vi: "Đã reset thông báo", en: "Notifications reset", ja: "通知をリセットしました"),
                    message: mistiaLocalized(
                        vi: "Trung tâm thông báo trên thiết bị này đã về 0 row.",
                        en: "The notification center on this device is now empty.",
                        ja: "この端末の通知センターを空にしました。"
                    )
                )
            } catch {
                statusAlert = ResetDataStatusAlert(
                    title: mistiaLocalized(vi: "Không thể reset thông báo", en: "Couldn't reset notifications", ja: "通知をリセットできませんでした"),
                    message: error.localizedDescription
                )
            }
            isWorking = false
        }
    }

    private func resetCategories() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                let result = try MistiaBootstrap.resetCategoriesToSystemDefaults(
                    modelContext: sessionStore.currentModelContainer.mainContext
                )
                statusAlert = ResetDataStatusAlert(
                    title: mistiaLocalized(vi: "Đã reset danh mục", en: "Categories reset", ja: "カテゴリをリセットしました"),
                    message: resetCategoriesSuccessMessage(result)
                )
            } catch {
                statusAlert = ResetDataStatusAlert(
                    title: mistiaLocalized(vi: "Không thể reset danh mục", en: "Couldn't reset categories", ja: "カテゴリをリセットできませんでした"),
                    message: error.localizedDescription
                )
            }
            isWorking = false
        }
    }

    private func resetCategoriesSuccessMessage(_ result: MistiaCategoryResetResult) -> String {
        let base = mistiaLocalized(
            vi: "Danh mục system trên thiết bị này đã về trạng thái ban đầu.",
            en: "System categories on this device are back to defaults.",
            ja: "この端末のシステムカテゴリを初期状態に戻しました。"
        )
        guard result.archivedCustomCategoryCount > 0 else { return base }
        let archivedText = mistiaLocalized(
            vi: "\(result.archivedCustomCategoryCount) danh mục tự tạo đã được lưu trữ.",
            en: "\(result.archivedCustomCategoryCount) custom categories were archived.",
            ja: "作成したカテゴリ \(result.archivedCustomCategoryCount) 件をアーカイブしました。"
        )
        return "\(base) \(archivedText)"
    }

    private func deleteAllLocalData() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await sessionStore.resetCurrentDeviceLocalData()
                await MistiaLocalNotificationScheduler.clearAllScheduledReminders()
                statusAlert = ResetDataStatusAlert(
                    title: mistiaLocalized(vi: "Đã xóa dữ liệu local", en: "Local data deleted", ja: "ローカルデータを削除しました"),
                    message: mistiaLocalized(
                        vi: "Thiết bị này đã về trạng thái dữ liệu ban đầu. Cloud, đăng nhập và gia đình vẫn được giữ.",
                        en: "This device is back to a clean local data state. Cloud, sign-in, and family are preserved.",
                        ja: "この端末のデータを初期状態に戻しました。クラウド、ログイン、家族は保持されています。"
                    )
                )
            } catch {
                statusAlert = ResetDataStatusAlert(
                    title: mistiaLocalized(vi: "Không thể xóa dữ liệu", en: "Couldn't delete data", ja: "データを削除できませんでした"),
                    message: error.localizedDescription
                )
            }
            isWorking = false
        }
    }
}

private struct ResetDataActionRow: View {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let role: ButtonRole?
    let isDestructive: Bool
    let isWorking: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                SettingsIconTile(iconContent: .system(icon: icon, accent: accent))

                Text(title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(titleColor)

                Spacer(minLength: 10)

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(valueColor.opacity(0.82))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accent.color))
        .disabled(isWorking)
        .opacity(isWorking ? 0.62 : 1)
    }

    private var titleColor: Color {
        if isDestructive {
            return MistiaAccent.expense.color
        }
        return colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.82)
    }

    private var valueColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : Color.black.opacity(0.48)
    }
}

private struct ResetDataStatusAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct MistiaShortcutOptionSectionCard: View {
    let section: MistiaShortcutOptionSectionDump
    let selectedSelection: MistiaShortcutSelection
    let tint: Color
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
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))

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
    let onTap: (SettingsRowDump) -> Void

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    SettingsRowButton(row: row) {
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
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))
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
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))

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
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))

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
    case openNotifications
    case openBackupRestore
    case openArchivedItems
    case openShortcut
    case openResetData
    case placeholder
}

private enum SettingsDestination: String, Identifiable {
    case appearance
    case language
    case notifications
    case backupRestore
    case archivedItems
    case shortcut
    case resetData

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
        case .backupRestore:
            .mint
        case .archivedItems:
            .slate
        case .familyOverview:
            .indigo
        case .memberOverview:
            .rose
        case .syncNow:
            .sky
        }
    }
}
