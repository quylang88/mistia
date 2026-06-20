import SwiftUI

struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MistiaAppLockController.self) private var appLockController

    @State private var activeSheet: SecuritySettingsSheet?
    @State private var activeSetup: SecuritySettingsSetup?
    @State private var pendingAuthenticatedAction: SecurityProtectedAction?
    @State private var statusAlert: SecuritySettingsStatusAlert?
    @State private var biometricEnrollmentPrompt: SecurityBiometricEnrollmentPrompt?

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.settings.security.title,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 14
        ) {
            VStack(spacing: 14) {
                securityCard {
                    securityToggleRow(
                        title: L10n.settings.security.appLock.title,
                        systemImage: "lock.fill",
                        accent: .mint,
                        isOn: protectionBinding
                    )
                }

                textDetailLayout(L10n.settings.security.appLock.description)

                if appLockController.isEnabled {
                    securityBlockTitle(L10n.settings.security.secretKind.title)

                    securityCard {
                        ForEach(Array(MistiaAppLockSecretKind.allCases.enumerated()), id: \.element.rawValue) { index, kind in
                            Button {
                                handleSecretKindSelection(kind)
                            } label: {
                                SecuritySecretKindRow(
                                    kind: kind,
                                    isSelected: appLockController.configuredSecretKind == kind
                                )
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))

                            if index < MistiaAppLockSecretKind.allCases.count - 1 {
                                securityDivider()
                            }
                        }
                    }

                    securityCard {
                        securityToggleRow(
                            title: biometricTitle,
                            systemImage: biometricIconName,
                            accent: .purple,
                            isOn: biometricBinding,
                            isDisabled: appLockController.biometryKind == .none,
                            prefersHighContrastIcon: true
                        )
                    }

                    securityCard {
                        Button {
                        } label: {
                            HStack(spacing: 12) {
                                SecurityPreferenceIcon(systemImage: "questionmark.circle.fill", accent: .slate)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.settings.security.forgotCode.title)
                                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    Text(L10n.settings.security.forgotCode.description)
                                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 10)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.slate.color))
                        .disabled(true)
                    }
                }
            }
        }
        .fullScreenCover(item: $activeSetup) { setup in
            MistiaAppLockSetupFullScreen(initialKind: setup.kind) { kind, secret in
                handleSetupCompletion(setup.completion, kind: kind, secret: secret)
            }
        }
        .fullScreenCover(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            switch sheet {
            case .authenticate(let action):
                MistiaAppLockAuthenticationFullScreen(kind: appLockController.configuredSecretKind ?? .pin4) {
                    pendingAuthenticatedAction = action
                }
            }
        }
        .alert(item: $statusAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.common.ok))
            )
        }
        .alert(item: $biometricEnrollmentPrompt) { prompt in
            Alert(
                title: Text(L10n.settings.security.biometricPrompt.title(biometricDisplayName(for: prompt.kind))),
                message: Text(L10n.settings.security.biometricPrompt.message(biometricDisplayName(for: prompt.kind))),
                primaryButton: .default(Text(L10n.settings.security.biometricPrompt.confirm(biometricDisplayName(for: prompt.kind)))) {
                    enableBiometricFromEnrollmentPrompt(prompt)
                },
                secondaryButton: .cancel(Text(L10n.settings.security.biometricPrompt.notNow))
            )
        }
    }

    private var protectionBinding: Binding<Bool> {
        Binding(
            get: { appLockController.isEnabled },
            set: { newValue in
                if newValue {
                    activeSetup = SecuritySettingsSetup(kind: .pin4, completion: .enableProtection)
                } else {
                    activeSheet = .authenticate(.disableProtection)
                }
            }
        )
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { appLockController.isBiometricEnabled },
            set: { newValue in
                guard appLockController.biometryKind != .none else {
                    statusAlert = SecuritySettingsStatusAlert(
                        title: L10n.settings.security.status.unavailableTitle,
                        message: L10n.settings.security.biometric.unavailable
                    )
                    return
                }
                activeSheet = .authenticate(newValue ? .enableBiometric : .disableBiometric)
            }
        )
    }

    private var biometricTitle: String {
        biometricDisplayName(for: appLockController.biometryKind)
    }

    private func biometricDisplayName(for kind: MistiaAppLockBiometryKind) -> String {
        switch kind {
        case .faceID:
            L10n.settings.security.biometric.faceID
        case .touchID:
            L10n.settings.security.biometric.touchID
        case .opticID:
            L10n.settings.security.biometric.opticID
        case .none:
            L10n.settings.security.biometric.generic
        }
    }

    private var biometricIconName: String {
        switch appLockController.biometryKind {
        case .faceID:
            "faceid"
        case .touchID:
            "touchid"
        case .opticID:
            "opticid"
        case .none:
            "person.badge.key.fill"
        }
    }

    private func handleSecretKindSelection(_ kind: MistiaAppLockSecretKind) {
        guard appLockController.configuredSecretKind != kind else { return }
        activeSheet = .authenticate(.changeKind(kind))
    }

    private func handleSetupCompletion(
        _ completion: SecuritySetupCompletion,
        kind: MistiaAppLockSecretKind,
        secret: String
    ) {
        do {
            try appLockController.configure(kind: kind, secret: secret)
            switch completion {
            case .enableProtection:
                if appLockController.canOfferBiometricEnrollmentAfterSetup(for: kind) {
                    biometricEnrollmentPrompt = SecurityBiometricEnrollmentPrompt(kind: appLockController.biometryKind)
                } else {
                    statusAlert = SecuritySettingsStatusAlert(
                        title: L10n.settings.security.status.enabledTitle,
                        message: L10n.settings.security.status.enabledMessage
                    )
                }
            case .enableBiometric:
                if kind == .pin4 {
                    try appLockController.setBiometricsEnabled(true)
                    statusAlert = SecuritySettingsStatusAlert(
                        title: biometricEnabledTitle,
                        message: biometricEnabledMessage
                    )
                } else {
                    statusAlert = SecuritySettingsStatusAlert(
                        title: L10n.settings.security.status.changedTitle,
                        message: L10n.settings.security.status.changedMessage
                    )
                }
            case .changeKind:
                statusAlert = SecuritySettingsStatusAlert(
                    title: L10n.settings.security.status.changedTitle,
                    message: L10n.settings.security.status.changedMessage
                )
            }
        } catch {
            statusAlert = SecuritySettingsStatusAlert(
                title: L10n.settings.security.status.errorTitle,
                message: error.localizedDescription
            )
        }
    }

    private func handleAuthenticatedAction(_ action: SecurityProtectedAction) {
        do {
            switch action {
            case .disableProtection:
                try appLockController.disableAfterAuthentication()
                statusAlert = SecuritySettingsStatusAlert(
                    title: L10n.settings.security.status.disabledTitle,
                    message: L10n.settings.security.status.disabledMessage
                )
            case .enableBiometric:
                if appLockController.requiresCodeSetupBeforeBiometric {
                    activeSetup = SecuritySettingsSetup(kind: .pin4, completion: .enableBiometric)
                } else {
                    try appLockController.setBiometricsEnabled(true)
                    statusAlert = SecuritySettingsStatusAlert(
                        title: biometricEnabledTitle,
                        message: biometricEnabledMessage
                    )
                }
            case .disableBiometric:
                try appLockController.setBiometricsEnabled(false)
                statusAlert = SecuritySettingsStatusAlert(
                    title: biometricDisabledTitle,
                    message: biometricDisabledMessage
                )
            case .changeKind(let kind):
                activeSetup = SecuritySettingsSetup(kind: kind, completion: .changeKind)
            }
        } catch {
            statusAlert = SecuritySettingsStatusAlert(
                title: L10n.settings.security.status.errorTitle,
                message: error.localizedDescription
            )
        }
    }

    private var biometricEnabledTitle: String {
        L10n.settings.security.status.biometricEnabledTitle(biometricTitle)
    }

    private var biometricEnabledMessage: String {
        L10n.settings.security.status.biometricEnabledMessage(biometricTitle)
    }

    private var biometricDisabledTitle: String {
        L10n.settings.security.status.biometricDisabledTitle(biometricTitle)
    }

    private var biometricDisabledMessage: String {
        L10n.settings.security.status.biometricDisabledMessage(biometricTitle)
    }

    private func enableBiometricFromEnrollmentPrompt(_ prompt: SecurityBiometricEnrollmentPrompt) {
        do {
            try appLockController.setBiometricsEnabled(true)
            statusAlert = SecuritySettingsStatusAlert(
                title: L10n.settings.security.status.biometricEnabledTitle(biometricDisplayName(for: prompt.kind)),
                message: L10n.settings.security.status.biometricEnabledMessage(biometricDisplayName(for: prompt.kind))
            )
        } catch {
            statusAlert = SecuritySettingsStatusAlert(
                title: L10n.settings.security.status.errorTitle,
                message: error.localizedDescription
            )
        }
    }

    private func handleSheetDismiss() {
        guard let action = pendingAuthenticatedAction else { return }
        pendingAuthenticatedAction = nil
        handleAuthenticatedAction(action)
    }

    @ViewBuilder
    private func securityCard(@ViewBuilder content: () -> some View) -> some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                content()
            }
        }
    }

    private func securityBlockTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private func textDetailLayout(_ text: String) -> some View {
        Text(text)
            .descriptionTextStyle()
            .cardDescriptionStyle()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func securityDivider() -> some View {
        Divider()
            .padding(.leading, 58)
    }

    private func securityToggleRow(
        title: String,
        systemImage: String,
        accent: MistiaAccent,
        isOn: Binding<Bool>,
        isDisabled: Bool = false,
        prefersHighContrastIcon: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            SecurityPreferenceIcon(
                systemImage: systemImage,
                accent: accent,
                prefersHighContrastSymbol: prefersHighContrastIcon
            )

            Text(title)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isDisabled ? .secondary : .primary)

            Spacer(minLength: 10)

            Toggle(String(), isOn: isOn)
                .labelsHidden()
                .tint(MistiaAccent.purple.color)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

struct MistiaAppLockScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MistiaAppLockController.self) private var appLockController
    @State private var didAttemptBiometric = false

    var body: some View {
        AppLockGlassScreenFrame(
            title: L10n.shared.appLock.title,
            topSpacerExtra: 40,
            bottomSpacerExtra: 24
        ) { _ in
            EmptyView()
        } entry: { metrics in
            MistiaAppLockEntryPanel(
                mode: .unlock,
                kind: appLockController.configuredSecretKind ?? .pin4,
                hidesUnlockPrompt: true,
                usesLockScreenLayout: true,
                lockScreenKeypadStyle: metrics.keypadStyle,
                onSubmit: { secret in
                    appLockController.verify(secret: secret)
                }
            )
        } belowEntry: {
            if appLockController.isBiometricEnabled, appLockController.biometryKind != .none {
                biometricButton
                    .padding(.top, 20)
            }
        } footer: { _ in
            EmptyView()
        }
        .task {
            guard !didAttemptBiometric else { return }
            didAttemptBiometric = true
            await authenticateWithBiometrics()
        }
    }

    @ViewBuilder
    private var biometricButton: some View {
        let button = Button {
            AppLockHaptics.light()
            Task { await authenticateWithBiometrics() }
        } label: {
            Label(biometricButtonTitle, systemImage: biometricIconName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
        }
        .tint(colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color)

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var biometricButtonTitle: String {
        switch appLockController.biometryKind {
        case .faceID:
            L10n.shared.appLock.unlockWithFaceID
        case .touchID:
            L10n.shared.appLock.unlockWithTouchID
        case .opticID:
            L10n.shared.appLock.unlockWithOpticID
        case .none:
            L10n.shared.appLock.unlockWithBiometric
        }
    }

    private var biometricIconName: String {
        switch appLockController.biometryKind {
        case .faceID:
            "faceid"
        case .touchID:
            "touchid"
        case .opticID:
            "opticid"
        case .none:
            "person.badge.key.fill"
        }
    }

    private func authenticateWithBiometrics() async {
        _ = await appLockController.authenticateWithBiometrics(
            reason: L10n.shared.appLock.biometricReason
        )
    }
}

private struct MistiaAppLockSetupFullScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: MistiaAppLockSecretKind
    let onComplete: (MistiaAppLockSecretKind, String) -> Void

    init(
        initialKind: MistiaAppLockSecretKind,
        onComplete: @escaping (MistiaAppLockSecretKind, String) -> Void
    ) {
        _selectedKind = State(initialValue: initialKind)
        self.onComplete = onComplete
    }

    var body: some View {
        AppLockGlassScreenFrame(
            title: L10n.shared.appLock.setupCodeTitle,
            subtitle: L10n.shared.appLock.setupCodeSubtitle
        ) { metrics in
            HStack {
                AppLockSetupCloseButton {
                    dismiss()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, metrics.closeTopPadding)
        } entry: { metrics in
            MistiaAppLockEntryPanel(
                mode: .setup,
                kind: selectedKind,
                hidesInitialSetupPrompt: true,
                usesLockScreenLayout: true,
                lockScreenKeypadStyle: metrics.keypadStyle
            ) { secret in
                onComplete(selectedKind, secret)
                dismiss()
                return true
            }
            .id(selectedKind)
        } belowEntry: {
            EmptyView()
        } footer: { metrics in
            AppLockSecretKindIconDock(selection: $selectedKind)
                .padding(.bottom, metrics.dockBottomPadding)
        }
    }
}

private struct AppLockGlassScreenFrame<TopAccessory: View, Entry: View, BelowEntry: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    var topSpacerExtra: CGFloat
    var bottomSpacerExtra: CGFloat
    @ViewBuilder let topAccessory: (AppLockSetupMetrics) -> TopAccessory
    @ViewBuilder let entry: (AppLockSetupMetrics) -> Entry
    @ViewBuilder let belowEntry: () -> BelowEntry
    @ViewBuilder let footer: (AppLockSetupMetrics) -> Footer

    init(
        title: String,
        subtitle: String? = nil,
        topSpacerExtra: CGFloat = 0,
        bottomSpacerExtra: CGFloat = 0,
        @ViewBuilder topAccessory: @escaping (AppLockSetupMetrics) -> TopAccessory,
        @ViewBuilder entry: @escaping (AppLockSetupMetrics) -> Entry,
        @ViewBuilder belowEntry: @escaping () -> BelowEntry,
        @ViewBuilder footer: @escaping (AppLockSetupMetrics) -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.topSpacerExtra = topSpacerExtra
        self.bottomSpacerExtra = bottomSpacerExtra
        self.topAccessory = topAccessory
        self.entry = entry
        self.belowEntry = belowEntry
        self.footer = footer
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = AppLockSetupMetrics(containerHeight: proxy.size.height)

            ZStack {
                AppLockSetupBackground()

                VStack(spacing: 0) {
                    topAccessory(metrics)

                    Spacer(minLength: metrics.topSpacer + topSpacerExtra)

                    VStack(spacing: metrics.contentSpacing) {
                        AppLockGlassScreenHeader(
                            title: title,
                            subtitle: subtitle,
                            lockIconSize: metrics.lockIconSize
                        )

                        entry(metrics)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 420)

                    belowEntry()

                    Spacer(minLength: metrics.bottomSpacer + bottomSpacerExtra)

                    footer(metrics)
                }
            }
        }
    }
}

private struct AppLockGlassScreenHeader: View {
    let title: String
    let subtitle: String?
    let lockIconSize: CGFloat

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: lockIconSize, weight: .semibold))
                .foregroundStyle(MistiaAccent.mint.color)

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct AppLockSetupMetrics {
    let isCompactHeight: Bool

    init(containerHeight: CGFloat) {
        isCompactHeight = containerHeight < 880
    }

    var closeTopPadding: CGFloat {
        isCompactHeight ? 18 : 20
    }

    var topSpacer: CGFloat {
        isCompactHeight ? 14 : 24
    }

    var contentSpacing: CGFloat {
        isCompactHeight ? 18 : 24
    }

    var lockIconSize: CGFloat {
        isCompactHeight ? 32 : 36
    }

    var bottomSpacer: CGFloat {
        isCompactHeight ? 12 : 18
    }

    var dockBottomPadding: CGFloat {
        isCompactHeight ? 14 : 20
    }

    var keypadStyle: MistiaPINKeypadStyle {
        isCompactHeight ? .lockScreenCompact : .lockScreen
    }
}

private struct AppLockSetupBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MistiaAccent.slate.color.opacity(0.28),
                    MistiaAccent.purple.color.opacity(0.10),
                    MistiaAccent.mint.color.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }
}

private struct AppLockSetupCloseButton: View {
    let action: () -> Void

    var body: some View {
        let button = Button {
            AppLockHaptics.light()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(L10n.common.close)

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glass(.regular.interactive()))
        } else {
            button.buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct AppLockSecretKindIconDock: View {
    @Binding var selection: MistiaAppLockSecretKind

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 14) {
                    content
                }
            } else {
                content
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(spacing: 10) {
            AppLockSecretKindIconButton(kind: .pin4, selection: $selection)
            AppLockSecretKindIconButton(kind: .pin6, selection: $selection)
            AppLockSecretKindIconButton(kind: .customPassword, selection: $selection)
        }
    }
}

private struct AppLockSecretKindIconButton: View {
    let kind: MistiaAppLockSecretKind
    @Binding var selection: MistiaAppLockSecretKind

    private var isSelected: Bool {
        selection == kind
    }

    var body: some View {
        let button = Button {
            guard selection != kind else { return }
            AppLockHaptics.light()
            withAnimation(.snappy) {
                selection = kind
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 38, height: 38)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if #available(iOS 26.0, *) {
            if isSelected {
                button
                    .buttonStyle(.glassProminent)
                    .tint(MistiaAccent.purple.color)
            } else {
                button.buttonStyle(.glass(.regular.interactive()))
            }
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? MistiaAccent.purple.color.opacity(0.8) : .white.opacity(0.18), lineWidth: 1)
                }
        }
    }

    private var iconName: String {
        switch kind {
        case .pin4:
            "square.grid.2x2.fill"
        case .pin6:
            "circle.grid.3x3.fill"
        case .customPassword:
            "keyboard.fill"
        }
    }

    private var accessibilityLabel: String {
        switch kind {
        case .pin4:
            L10n.shared.appLock.optionPin4
        case .pin6:
            L10n.shared.appLock.optionPin6
        case .customPassword:
            L10n.shared.appLock.optionPassword
        }
    }
}

private struct MistiaAppLockAuthenticationFullScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MistiaAppLockController.self) private var appLockController
    let kind: MistiaAppLockSecretKind
    let onAuthenticated: () -> Void

    var body: some View {
        AppLockGlassScreenFrame(title: L10n.shared.appLock.enterCurrentCodeTitle) { metrics in
            HStack {
                AppLockSetupCloseButton {
                    dismiss()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, metrics.closeTopPadding)
        } entry: { metrics in
            MistiaAppLockEntryPanel(
                mode: .authenticate,
                kind: kind,
                hidesAuthenticationPrompt: true,
                usesLockScreenLayout: true,
                lockScreenKeypadStyle: metrics.keypadStyle
            ) { secret in
                guard appLockController.verify(secret: secret) else { return false }
                onAuthenticated()
                dismiss()
                return true
            }
        } belowEntry: {
            EmptyView()
        } footer: { _ in
            EmptyView()
        }
    }
}

private struct MistiaAppLockEntryPanel: View {
    @Environment(MistiaAppLockController.self) private var appLockController
    let mode: MistiaAppLockEntryMode
    let kind: MistiaAppLockSecretKind
    var hidesInitialSetupPrompt = false
    var hidesUnlockPrompt = false
    var hidesAuthenticationPrompt = false
    var usesLockScreenLayout = false
    var lockScreenKeypadStyle: MistiaPINKeypadStyle = .lockScreen
    let onSubmit: (String) -> Bool

    @State private var pinInput = ""
    @State private var pendingSecret: String?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var countdownNow = Date()

    var body: some View {
        VStack(spacing: usesLockScreenLayout ? 24 : 18) {
            if shouldShowPromptBlock {
                VStack(spacing: 6) {
                    if shouldShowPromptTitle {
                        Text(promptTitle)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                    }

                    if let helperText {
                        Text(helperText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            if kind == .customPassword {
                passwordFields
            } else {
                pinDots
                MistiaPINKeypad(
                    style: usesLockScreenLayout ? lockScreenKeypadStyle : .compact,
                    onDigit: appendDigit,
                    onDelete: deleteDigit
                )
                .disabled(isManualEntryLockedOut)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MistiaAccent.expense.color)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: appLockController.failureState.lockedUntil) {
            await updateLockoutCountdown(until: appLockController.failureState.lockedUntil)
        }
    }

    private var passwordFields: some View {
        VStack(spacing: usesLockScreenLayout ? 14 : 12) {
            passwordField(
                placeholder: L10n.shared.appLock.passwordPlaceholder,
                text: $password,
                contentType: .password
            )

            if mode == .setup {
                passwordField(
                    placeholder: L10n.shared.appLock.confirmPasswordPlaceholder,
                    text: $confirmPassword,
                    contentType: .newPassword
                )
            }

            passwordSubmitButton
        }
        .frame(maxWidth: usesLockScreenLayout ? 340 : .infinity)
    }

    @ViewBuilder
    private func passwordField(
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType
    ) -> some View {
        if usesLockScreenLayout {
            SecureField(placeholder, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .modifier(AppLockPasswordFieldGlassStyle(isEnabled: true))
        } else {
            SecureField(placeholder, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var passwordSubmitButton: some View {
        let button = Button(mode == .setup ? L10n.shared.appLock.continueButton : L10n.shared.appLock.unlock) {
            submitPassword()
        }
        .tint(MistiaAccent.purple.color)
        .disabled(isManualEntryLockedOut || password.isEmpty || (mode == .setup && confirmPassword.isEmpty))

        if usesLockScreenLayout {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var pinDots: some View {
        HStack(spacing: usesLockScreenLayout ? 15 : 12) {
            ForEach(0..<pinLength, id: \.self) { index in
                Circle()
                    .fill(index < pinInput.count ? MistiaAccent.tabActive.color : Color.secondary.opacity(0.24))
                    .frame(
                        width: usesLockScreenLayout ? 14 : 13,
                        height: usesLockScreenLayout ? 14 : 13
                    )
            }
        }
        .padding(.vertical, usesLockScreenLayout ? 8 : 4)
        .accessibilityLabel(promptTitle)
    }

    private var pinLength: Int {
        kind == .pin4 ? 4 : 6
    }

    private var promptTitle: String {
        switch mode {
        case .unlock:
            return L10n.shared.appLock.title
        case .authenticate:
            return L10n.shared.appLock.enterCurrentCodeTitle
        case .setup:
            if pendingSecret == nil {
                return L10n.shared.appLock.setupCodeTitle
            }
            return kind == .customPassword
                ? L10n.shared.appLock.confirmPassword
                : L10n.shared.appLock.confirmPin
        }
    }

    private var shouldShowPromptTitle: Bool {
        if mode == .unlock && hidesUnlockPrompt {
            return false
        }
        if mode == .authenticate && hidesAuthenticationPrompt {
            return false
        }
        return !(mode == .setup && hidesInitialSetupPrompt && pendingSecret == nil)
    }

    private var shouldShowPromptBlock: Bool {
        shouldShowPromptTitle || helperText != nil
    }

    private var helperText: String? {
        if isManualEntryLockedOut {
            return lockedOutText
        }

        switch mode {
        case .unlock, .authenticate:
            return nil
        case .setup:
            return kind == .customPassword ? L10n.shared.appLock.passwordHelper : nil
        }
    }

    private var lockedOutText: String? {
        guard let lockedUntil = appLockController.failureState.lockedUntil else { return nil }
        let remaining = lockedUntil.timeIntervalSince(countdownNow)
        guard remaining > 0 else { return nil }

        if remaining >= 60 {
            let minutes = max(1, Int(ceil(remaining / 60)))
            return L10n.shared.appLock.tryAgainInMinutes("\(minutes)")
        }

        let seconds = max(1, Int(ceil(remaining)))
        return L10n.shared.appLock.tryAgainInSeconds("\(seconds)")
    }

    private var isManualEntryLockedOut: Bool {
        MistiaAppLockLogic.isLockedOut(appLockController.failureState, now: countdownNow)
    }

    private func appendDigit(_ digit: String) {
        guard !MistiaAppLockLogic.isLockedOut(appLockController.failureState),
              pinInput.count < pinLength
        else { return }

        pinInput.append(digit)
        guard pinInput.count == pinLength else { return }
        submitPIN()
    }

    private func deleteDigit() {
        guard !pinInput.isEmpty else { return }
        pinInput.removeLast()
        errorMessage = nil
    }

    private func submitPIN() {
        let candidate = pinInput
        switch mode {
        case .setup:
            if let pendingSecret {
                guard candidate == pendingSecret else {
                    pinInput = ""
                    self.pendingSecret = nil
                    errorMessage = L10n.shared.appLock.codeMismatch
                    return
                }
                _ = onSubmit(candidate)
            } else {
                pendingSecret = candidate
                pinInput = ""
                errorMessage = nil
            }
        case .unlock, .authenticate:
            guard onSubmit(candidate) else {
                pinInput = ""
                errorMessage = isManualEntryLockedOut ? nil : L10n.shared.appLock.wrongCode
                return
            }
            errorMessage = nil
        }
    }

    private func submitPassword() {
        switch mode {
        case .setup:
            guard password == confirmPassword else {
                errorMessage = L10n.shared.appLock.codeMismatch
                return
            }
            if let failure = MistiaAppLockLogic.validationFailure(for: password, kind: kind) {
                errorMessage = message(for: failure)
                return
            }
            _ = onSubmit(password)
        case .unlock, .authenticate:
            guard onSubmit(password) else {
                password = ""
                errorMessage = isManualEntryLockedOut ? nil : L10n.shared.appLock.wrongCode
                return
            }
            errorMessage = nil
        }
    }

    private func updateLockoutCountdown(until lockedUntil: Date?) async {
        guard let lockedUntil else {
            countdownNow = Date()
            return
        }

        while !Task.isCancelled {
            let now = Date()
            countdownNow = now

            guard now < lockedUntil else {
                errorMessage = nil
                return
            }

            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func message(for failure: MistiaAppLockSecretValidationFailure) -> String {
        switch failure {
        case .pin4RequiresFourDigits:
            L10n.shared.appLock.pin4Validation
        case .pin6RequiresSixDigits:
            L10n.shared.appLock.pin6Validation
        case .customPasswordTooShort:
            L10n.shared.appLock.passwordValidation
        case .customPasswordMissingLetter:
            L10n.shared.appLock.passwordMissingLetterValidation
        case .customPasswordMissingDigit:
            L10n.shared.appLock.passwordMissingDigitValidation
        case .customPasswordMissingUppercase:
            L10n.shared.appLock.passwordMissingUppercaseValidation
        case .customPasswordMissingLowercase:
            L10n.shared.appLock.passwordMissingLowercaseValidation
        }
    }
}

private struct AppLockPasswordFieldGlassStyle: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background {
                    AppLockGlassRoundedBackground(cornerRadius: 18)
                }
        } else {
            content
        }
    }
}

private struct AppLockGlassRoundedBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

private enum MistiaPINKeypadStyle {
    case compact
    case lockScreen
    case lockScreenCompact

    var isLockScreen: Bool {
        switch self {
        case .compact:
            false
        case .lockScreen, .lockScreenCompact:
            true
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .compact:
            12
        case .lockScreen:
            18
        case .lockScreenCompact:
            14
        }
    }

    var columnSpacing: CGFloat {
        switch self {
        case .compact:
            18
        case .lockScreen:
            22
        case .lockScreenCompact:
            18
        }
    }

    var keyWidth: CGFloat {
        switch self {
        case .compact:
            66
        case .lockScreen:
            78
        case .lockScreenCompact:
            70
        }
    }

    var keyHeight: CGFloat {
        switch self {
        case .compact:
            54
        case .lockScreen:
            78
        case .lockScreenCompact:
            70
        }
    }

    var digitFontSize: CGFloat {
        switch self {
        case .compact:
            26
        case .lockScreen:
            32
        case .lockScreenCompact:
            29
        }
    }

    var trailingControlRowOffset: CGFloat {
        switch self {
        case .compact:
            0
        case .lockScreen:
            13
        case .lockScreenCompact:
            12
        }
    }
}

private struct MistiaPINKeypad: View {
    var style: MistiaPINKeypadStyle = .compact
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "delete"]
    ]

    var body: some View {
        Group {
            if style.isLockScreen, #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: style.columnSpacing) {
                    keypadRows
                }
            } else {
                keypadRows
            }
        }
    }

    private var keypadRows: some View {
        VStack(spacing: style.rowSpacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: style.columnSpacing) {
                    ForEach(row, id: \.self) { item in
                        if style.isLockScreen {
                            lockScreenKeypadButton(item)
                        } else {
                            compactKeypadButton(item)
                        }
                    }
                }
                .offset(x: row.first == "" ? style.trailingControlRowOffset : 0)
            }
        }
    }

    @ViewBuilder
    private func compactKeypadButton(_ item: String) -> some View {
        if item.isEmpty {
            Color.clear
                .frame(width: style.keyWidth, height: style.keyHeight)
        } else if item == "delete" {
            Button {
                AppLockHaptics.light()
                onDelete()
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: style.keyWidth, height: style.keyHeight)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else {
            Button {
                AppLockHaptics.light()
                onDigit(item)
            } label: {
                Text(verbatim: item)
                    .font(.system(size: style.digitFontSize, weight: .semibold, design: .rounded))
                    .frame(width: style.keyWidth, height: style.keyHeight)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func lockScreenKeypadButton(_ item: String) -> some View {
        if item.isEmpty {
            Color.clear
                .frame(width: style.keyWidth, height: style.keyHeight)
        } else if item == "delete" {
            AppLockGlassKeyButton(keySize: style.keyWidth, action: onDelete) {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        } else {
            AppLockGlassKeyButton(keySize: style.keyWidth) {
                onDigit(item)
            } label: {
                Text(verbatim: item)
                    .font(.system(size: style.digitFontSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

private struct AppLockGlassKeyButton<Label: View>: View {
    let keySize: CGFloat
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        let button = Button {
            AppLockHaptics.light()
            action()
        } label: {
            label
                .frame(width: keySize, height: keySize)
                .contentShape(Circle())
        }
        .buttonBorderShape(.circle)
        .foregroundStyle(.primary)

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glass(.regular.interactive()))
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private enum AppLockHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct SecurityPreferenceIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let accent: MistiaAccent
    var prefersHighContrastSymbol = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    if prefersHighContrastSymbol && colorScheme == .dark {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(MistiaAccent.lightPurple.color.opacity(0.42), lineWidth: 1)
                    }
                }

            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)
        }
        .frame(width: 32, height: 32)
    }

    private var backgroundColor: Color {
        if prefersHighContrastSymbol && colorScheme == .dark {
            return MistiaAccent.lightPurple.color.opacity(0.26)
        }
        return accent.color.opacity(0.15)
    }

    private var symbolColor: Color {
        if prefersHighContrastSymbol && colorScheme == .dark {
            return MistiaAccent.checkmarkPurple.color
        }
        return accent.color
    }
}

private struct SecuritySecretKindRow: View {
    let kind: MistiaAppLockSecretKind
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SecurityPreferenceIcon(systemImage: iconName, accent: accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MistiaAccent.lightPurple.color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
    }

    private var title: String {
        switch kind {
        case .pin4:
            L10n.settings.security.secretKind.pin4.title
        case .pin6:
            L10n.settings.security.secretKind.pin6.title
        case .customPassword:
            L10n.settings.security.secretKind.customPassword.title
        }
    }

    private var subtitle: String {
        switch kind {
        case .pin4:
            L10n.settings.security.secretKind.pin4.subtitle
        case .pin6:
            L10n.settings.security.secretKind.pin6.subtitle
        case .customPassword:
            L10n.settings.security.secretKind.customPassword.subtitle
        }
    }

    private var iconName: String {
        switch kind {
        case .pin4:
            "number.square.fill"
        case .pin6:
            "number.circle.fill"
        case .customPassword:
            "keyboard.fill"
        }
    }

    private var accent: MistiaAccent {
        switch kind {
        case .pin4:
            .mint
        case .pin6:
            .sky
        case .customPassword:
            .amber
        }
    }
}

private enum MistiaAppLockEntryMode {
    case unlock
    case authenticate
    case setup
}

private struct SecuritySettingsSetup: Identifiable {
    let kind: MistiaAppLockSecretKind
    let completion: SecuritySetupCompletion

    var id: String {
        "setup-\(kind.rawValue)-\(completion.id)"
    }
}

private enum SecuritySettingsSheet: Identifiable {
    case authenticate(SecurityProtectedAction)

    var id: String {
        switch self {
        case .authenticate(let action):
            "auth-\(action.id)"
        }
    }
}

private enum SecuritySetupCompletion {
    case enableProtection
    case enableBiometric
    case changeKind

    var id: String {
        switch self {
        case .enableProtection:
            "enableProtection"
        case .enableBiometric:
            "enableBiometric"
        case .changeKind:
            "changeKind"
        }
    }
}

private enum SecurityProtectedAction {
    case disableProtection
    case enableBiometric
    case disableBiometric
    case changeKind(MistiaAppLockSecretKind)

    var id: String {
        switch self {
        case .disableProtection:
            "disableProtection"
        case .enableBiometric:
            "enableBiometric"
        case .disableBiometric:
            "disableBiometric"
        case .changeKind(let kind):
            "changeKind-\(kind.rawValue)"
        }
    }
}

private struct SecuritySettingsStatusAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct SecurityBiometricEnrollmentPrompt: Identifiable {
    let id = UUID()
    let kind: MistiaAppLockBiometryKind
}
