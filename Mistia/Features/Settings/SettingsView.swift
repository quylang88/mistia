import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaAppLockController.self) private var appLockController
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaAppStorageKey.mistiaShortcutEnabled) private var mistiaShortcutEnabled = false
    @AppStorage(MistiaAppStorageKey.mistiaShortcutKind) private var shortcutKindRawValue = MistiaShortcutKind.backupRestore.rawValue
    @AppStorage(MistiaAppStorageKey.mistiaShortcutMemberUserID) private var shortcutMemberUserIDRawValue = ""
    @AppStorage(MistiaAppStorageKey.notificationsEnabled) private var notificationsEnabled = false

    @State private var destination: SettingsDestination?
    @State private var showFeedbackSheet = false

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
                    title: L10n.settings.appearance.title,
                    icon: "moon.stars.fill",
                    accent: .indigo,
                    value: appearanceMode.title,
                    action: .openAppearance
                ),
                SettingsRowDump(
                    title: L10n.settings.language.title,
                    icon: "globe.asia.australia.fill",
                    accent: .sky,
                    value: appLanguage.displayName,
                    action: .openLanguage
                ),
                SettingsRowDump(
                    title: L10n.settings.currency.title,
                    icon: "yensign.circle.fill",
                    accent: .amber,
                    value: currencyCode,
                    action: .openCurrency
                )
            ]
        )
    }

    private var preferencesSection: SettingsSectionDump {
        SettingsSectionDump(
            rows: [
                SettingsRowDump(
                    title: L10n.settings.notifications.title,
                    icon: "bell.badge.fill",
                    accent: .coral,
                    value: notificationStatusText,
                    action: .openNotifications
                ),
                SettingsRowDump(
                    title: L10n.settings.security.title,
                    icon: "lock.shield.fill",
                    accent: .mint,
                    value: securityStatusText,
                    action: .openSecurity
                )
            ]
        )
    }

    private var notificationStatusText: String {
        notificationsEnabled
            ? L10n.common.on
            : L10n.common.off
    }

    private var securityStatusText: String {
        appLockController.isEnabled
            ? L10n.common.on
            : L10n.common.off
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
                title: L10n.settings.shortcut.title,
                icon: "pin.slash",
                accent: .slate,
                value: L10n.settings.shortcut.offStatus,
                action: .openShortcut
            )
        }

        return SettingsSectionDump(rows: [row])
    }

    private var feedbackSection: SettingsSectionDump {
        SettingsSectionDump(
            rows: [
                SettingsRowDump(
                    title: L10n.settings.feedback.title,
                    icon: "bubble.left.and.bubble.right.fill",
                    accent: .indigo,
                    value: nil,
                    action: .openFeedback
                )
            ]
        )
    }

    private var resetDataSection: SettingsSectionDump {
        SettingsSectionDump(
            rows: [
                SettingsRowDump(
                    title: L10n.settings.resetData.title,
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
            title: L10n.settings.title,
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

                MistiaSectionFooter(L10n.settings.shortcut.description)

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
            case .currency:
                CurrencySettingsView()
            case .notifications:
                NotificationsSettingsView()
            case .security:
                SecuritySettingsView()
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
        .sheet(isPresented: $showFeedbackSheet) {
            SendFeedbackView()
        }
    }

    private func handleTap(_ row: SettingsRowDump) {
        switch row.action {
        case .openAppearance:
            destination = .appearance
        case .openLanguage:
            destination = .language
        case .openCurrency:
            destination = .currency
        case .openNotifications:
            destination = .notifications
        case .openSecurity:
            destination = .security
        case .openBackupRestore:
            destination = .backupRestore
        case .openArchivedItems:
            destination = .archivedItems
        case .openShortcut:
            destination = .shortcut
        case .openResetData:
            destination = .resetData
        case .openFeedback:
            showFeedbackSheet = true
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
            title: L10n.settings.appearance.title,
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
            title: L10n.settings.language.title,
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

private struct CurrencySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.enabledCurrencyCodes) private var enabledCurrencyCodesRawValue = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var rateModeRawValue = MistiaCurrencyRateMode.manual.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = "165"
    @State private var isRefreshingRates = false

    private static let lastUpdatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var enabledCurrencyCodes: [String] {
        MistiaCurrencySettings.enabledCurrencyCodes()
    }

    private var selectedRateMode: MistiaCurrencyRateMode {
        MistiaCurrencyRateMode(rawValue: rateModeRawValue) ?? .manual
    }

    private var showsRateControls: Bool {
        enabledCurrencyCodes.count > 1
    }

    private var rateSourceCurrencyCode: String? {
        enabledCurrencyCodes.first { $0 != primaryCurrencyCode }
    }

    private var rateTargetCurrencyCode: String {
        primaryCurrencyCode
    }

    private var ratePairTitle: String {
        guard let source = rateSourceCurrencyCode else {
            return L10n.settings.currency.rateValue
        }
        return L10n.settings.currency.ratePairValue(source, rateTargetCurrencyCode)
    }

    private var displayedRateText: String? {
        guard let source = rateSourceCurrencyCode,
              let jpyToVNDRate = currentJPYToVNDRate
        else {
            return nil
        }
        return displayText(forJPYToVNDRate: jpyToVNDRate, source: source, target: rateTargetCurrencyCode)
    }

    private var currentJPYToVNDRate: Decimal? {
        switch selectedRateMode {
        case .automatic:
            return MistiaCurrencySettings.cachedRates().first { rate in
                MistiaCurrencyLogic.normalizedCode(rate.baseCurrencyCode) == "JPY"
                    && MistiaCurrencyLogic.normalizedCode(rate.quoteCurrencyCode) == "VND"
            }?.rateDecimal
        case .manual:
            return decimal(from: manualJPYToVNDRate)
        }
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.settings.currency.title,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            VStack(spacing: 14) {
                currencyEnabledCard
                textDetailLayout(L10n.settings.currency.enabledDescription)

                primaryCurrencyCard
                textDetailLayout(L10n.settings.currency.primaryDescription)

                if showsRateControls {
                    rateModeCard
                    textDetailLayout(L10n.settings.currency.rateDescription)
                }
            }
        }
    }

    private var currencyEnabledCard: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(MistiaCurrencyLogic.supportedCurrencyCodes.enumerated()), id: \.element) { index, code in
                    Toggle(isOn: enabledBinding(for: code)) {
                        CurrencySettingsRowTitle(code: code)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    if index < MistiaCurrencyLogic.supportedCurrencyCodes.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    private var primaryCurrencyCard: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
            HStack(spacing: 14) {
                Text(L10n.settings.currency.primaryCurrency)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer(minLength: 12)
                Menu {
                    ForEach(enabledCurrencyCodes, id: \.self) { code in
                        Button {
                            primaryCurrencyCode = code
                        } label: {
                            HStack {
                                Text(currencyMenuTitle(for: code))
                                if code == primaryCurrencyCode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currencyMenuTitle(for: primaryCurrencyCode))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.button)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var rateModeCard: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                Toggle(isOn: automaticRateBinding) {
                    Text(L10n.settings.currency.autoUpdateRates)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                if selectedRateMode == .automatic {
                    Divider().padding(.leading, 18)

                    Button {
                        refreshRates()
                    } label: {
                        HStack(spacing: 12) {
                            Text(isRefreshingRates ? L10n.settings.currency.refreshingRates : L10n.settings.currency.refreshRates)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Spacer()
                            if isRefreshingRates {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                    }
                    .disabled(isRefreshingRates)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    if let lastUpdatedText {
                        Divider().padding(.leading, 18)
                        Text(lastUpdatedText)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                }

                Divider().padding(.leading, 18)

                LabeledContent(ratePairTitle) {
                    if selectedRateMode == .automatic {
                        Text(displayedRateText ?? "—")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(displayedRateText == nil ? .secondary : .primary)
                    } else {
                        TextField(String(), text: displayedManualRateBinding)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private var automaticRateBinding: Binding<Bool> {
        Binding(
            get: { selectedRateMode == .automatic },
            set: { isAutomatic in
                rateModeRawValue = (isAutomatic ? MistiaCurrencyRateMode.automatic : .manual).rawValue
            }
        )
    }

    private var displayedManualRateBinding: Binding<String> {
        Binding(
            get: { displayedRateText ?? manualJPYToVNDRate },
            set: { newValue in
                guard let source = rateSourceCurrencyCode else {
                    manualJPYToVNDRate = newValue
                    return
                }
                if let jpyToVNDRate = jpyToVNDRate(fromDisplayedRateText: newValue, source: source, target: rateTargetCurrencyCode) {
                    manualJPYToVNDRate = rateText(jpyToVNDRate)
                } else if source == "JPY" && rateTargetCurrencyCode == "VND" {
                    manualJPYToVNDRate = newValue
                }
            }
        )
    }

    private var lastUpdatedText: String? {
        guard let date = UserDefaults.standard.object(forKey: MistiaCurrencySettings.StorageKey.lastAutoRateRefreshAt) as? Date else {
            return L10n.settings.currency.notUpdatedYet
        }

        return L10n.settings.currency.lastUpdatedValue(Self.lastUpdatedFormatter.string(from: date))
    }

    private func textDetailLayout(_ text: String) -> some View {
        MistiaSectionFooter(text)
    }

    private func enabledBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { enabledCurrencyCodes.contains(code) },
            set: { isEnabled in
                var codes = enabledCurrencyCodes
                if isEnabled {
                    codes.append(code)
                } else if codes.count > 1 {
                    codes.removeAll { $0 == code }
                }
                MistiaCurrencySettings.setEnabledCurrencyCodes(codes)
                enabledCurrencyCodesRawValue = MistiaCurrencySettings.enabledCurrencyCodes().joined(separator: ",")
                if !MistiaCurrencySettings.enabledCurrencyCodes().contains(primaryCurrencyCode) {
                    primaryCurrencyCode = MistiaCurrencySettings.enabledCurrencyCodes().first ?? "JPY"
                }
            }
        )
    }

    private func refreshRates() {
        isRefreshingRates = true
        Task { @MainActor in
            defer { isRefreshingRates = false }
            if let rate = try? await MistiaExchangeRateService.fetchJPYVNDRate() {
                MistiaCurrencySettings.saveCachedRates([rate])
            }
        }
    }

    private func currencyMenuTitle(for code: String) -> String {
        "\(code) · \(localizedCurrencyName(for: code))"
    }

    private func displayText(forJPYToVNDRate rate: Decimal, source: String, target: String) -> String? {
        if source == "JPY", target == "VND" {
            return rateText(rate)
        }
        if source == "VND", target == "JPY", rate != 0 {
            return rateText(Decimal(1) / rate)
        }
        return nil
    }

    private func jpyToVNDRate(fromDisplayedRateText text: String, source: String, target: String) -> Decimal? {
        guard let displayedRate = decimal(from: text), displayedRate > 0 else {
            return nil
        }
        if source == "JPY", target == "VND" {
            return displayedRate
        }
        if source == "VND", target == "JPY" {
            return Decimal(1) / displayedRate
        }
        return nil
    }

    private func decimal(from text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func rateText(_ decimal: Decimal) -> String {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 8, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}

private struct CurrencySettingsRowTitle: View {
    let code: String

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: code)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            Text(localizedCurrencyName(for: code))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private func localizedCurrencyName(for code: String) -> String {
    switch MistiaCurrencyLogic.normalizedCode(code) {
    case "JPY":
        return L10n.settings.currency.currencyNameJPY
    case "VND":
        return L10n.settings.currency.currencyNameVND
    default:
        return code
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
                    title: L10n.settings.shortcut.familySection,
                    rows: familyRows
                )
            )
        }

        let utilitySelections: [MistiaShortcutSelection] = {
            var selections: [MistiaShortcutSelection] = []
            selections.append(.receiptScan)
            selections.append(contentsOf: [
                .backupRestore,
                .archivedItems
            ])
            // syncNow only available when signed in AND initial sync is completed
            if sessionStore.isSignedIn && !sessionStore.requiresInitialSync {
                selections.append(.syncNow)
            }
            return selections
        }()

        output.append(
            MistiaShortcutOptionSectionDump(
                title: L10n.settings.shortcut.personalUtilitiesSection,
                rows: utilitySelections.compactMap(makeOption)
            )
        )

        return output
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.settings.shortcut.title,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            Toggle(
                L10n.settings.shortcut.enablePinnedButton,
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
            return L10n.settings.shortcut.option.backupRestore.subtitle

        case .archivedItems:
            return L10n.settings.shortcut.option.archivedItems.subtitle

        case .familyOverview:
            return L10n.settings.shortcut.option.familyOverview.subtitle

        case .memberOverview:
            return L10n.settings.shortcut.option.memberOverview.subtitle

        case .receiptScan:
            return L10n.settings.shortcut.option.receiptScan.subtitle

        case .syncNow:
            return L10n.settings.shortcut.option.syncNow.subtitle
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
            title: L10n.settings.resetData.title,
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
                        title: L10n.settings.resetData.reset.title,
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
                        title: L10n.settings.resetData.deleteAllData.title,
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
            L10n.settings.resetData.reset.title,
            isPresented: $showsResetOptions
        ) {
            Button(L10n.settings.resetData.reset.settingsTitle) {
                resetSettings()
            }
            Button(L10n.settings.resetData.reset.notificationsTitle) {
                resetNotifications()
            }
            Button(
                L10n.settings.resetData.reset.categoriesTitle,
                role: .destructive
            ) {
                showsResetCategoriesConfirmation = true
            }
            Button(L10n.common.cancel, role: .cancel) { }
        } message: {
            Text(L10n.settings.resetData.reset.optionsMessage)
        }
        .alert(
            L10n.settings.resetData.reset.categoriesConfirmationTitle,
            isPresented: $showsResetCategoriesConfirmation
        ) {
            Button(
                L10n.settings.resetData.reset.categoriesTitle,
                role: .destructive
            ) {
                resetCategories()
            }
            Button(L10n.common.cancel, role: .cancel) { }
        } message: {
            Text(L10n.settings.resetData.reset.categoriesConfirmationMessage)
        }
        .alert(
            L10n.settings.resetData.deleteAllData.confirmationTitle,
            isPresented: $showsDeleteConfirmation
        ) {
            Button(
                L10n.settings.resetData.deleteAllData.title,
                role: .destructive
            ) {
                deleteAllLocalData()
            }
            Button(L10n.common.cancel, role: .cancel) { }
        } message: {
            Text(L10n.settings.resetData.deleteAllData.confirmationMessage)
        }
        .alert(item: $statusAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.common.ok))
            )
        }
    }

    private func resetSettings() {
        MistiaSettingsResetSupport.resetAppPreferences()
        sessionStore.setAutoSyncEnabled(false)
        statusAlert = ResetDataStatusAlert(
            title: L10n.settings.resetData.settingsResetTitle,
            message: L10n.settings.resetData.settingsResetMessage
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
                    title: L10n.settings.resetData.notificationsResetTitle,
                    message: L10n.settings.resetData.notificationsResetMessage
                )
            } catch {
                statusAlert = ResetDataStatusAlert(
                    title: L10n.settings.resetData.notificationsResetFailedTitle,
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
                    title: L10n.settings.resetData.categoriesResetTitle,
                    message: resetCategoriesSuccessMessage(result)
                )
            } catch {
                statusAlert = ResetDataStatusAlert(
                    title: L10n.settings.resetData.categoriesResetFailedTitle,
                    message: error.localizedDescription
                )
            }
            isWorking = false
        }
    }

    private func resetCategoriesSuccessMessage(_ result: MistiaCategoryResetResult) -> String {
        let base = L10n.settings.resetData.categoriesResetMessage
        guard result.archivedCustomCategoryCount > 0 else { return base }
        let archivedText = L10n.settings.resetData.categoriesArchivedMessage(result.archivedCustomCategoryCount)
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
                    title: L10n.settings.resetData.localDataDeletedTitle,
                    message: L10n.settings.resetData.localDataDeletedMessage
                )
            } catch {
                statusAlert = ResetDataStatusAlert(
                    title: L10n.settings.resetData.deleteDataFailedTitle,
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
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(version) (\(build)) powered by Quý Lăng"
    }

    var body: some View {
        MistiaSectionFooter {
            VStack(spacing: 3) {
                Text(L10n.common.appName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(versionText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
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
    case openCurrency
    case openNotifications
    case openSecurity
    case openBackupRestore
    case openArchivedItems
    case openShortcut
    case openResetData
    case openFeedback
    case placeholder
}

private enum SettingsDestination: String, Identifiable {
    case appearance
    case language
    case currency
    case notifications
    case security
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
            title: L10n.settings.shortcut.title,
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
        case .receiptScan:
            .amber
        case .syncNow:
            .sky
        }
    }
}
