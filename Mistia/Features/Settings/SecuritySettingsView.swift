import SwiftUI

struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MistiaAppLockController.self) private var appLockController

    @State private var activeSheet: SecuritySettingsSheet?
    @State private var pendingAuthenticatedAction: SecurityProtectedAction?
    @State private var statusAlert: SecuritySettingsStatusAlert?

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
                            isDisabled: appLockController.biometryKind == .none
                        )
                    }

                    textDetailLayout(biometricDescription)

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
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            switch sheet {
            case .setup(let kind, let completion):
                MistiaAppLockSetupSheet(kind: kind) { secret in
                    handleSetupCompletion(completion, kind: kind, secret: secret)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .authenticate(let action):
                MistiaAppLockAuthenticationSheet(kind: appLockController.configuredSecretKind ?? .pin4) {
                    pendingAuthenticatedAction = action
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert(item: $statusAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.common.ok))
            )
        }
    }

    private var protectionBinding: Binding<Bool> {
        Binding(
            get: { appLockController.isEnabled },
            set: { newValue in
                if newValue {
                    activeSheet = .setup(.pin4, .enableProtection)
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
        switch appLockController.biometryKind {
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

    private var biometricDescription: String {
        appLockController.biometryKind == .none
            ? L10n.settings.security.biometric.unavailable
            : L10n.settings.security.biometric.description
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
                statusAlert = SecuritySettingsStatusAlert(
                    title: L10n.settings.security.status.enabledTitle,
                    message: L10n.settings.security.status.enabledMessage
                )
            case .enableBiometric:
                try appLockController.setBiometricsEnabled(true)
                statusAlert = SecuritySettingsStatusAlert(
                    title: L10n.settings.security.status.biometricEnabledTitle,
                    message: L10n.settings.security.status.biometricEnabledMessage
                )
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
                if appLockController.requiresPIN4SetupBeforeBiometric {
                    activeSheet = .setup(.pin4, .enableBiometric)
                } else {
                    try appLockController.setBiometricsEnabled(true)
                    statusAlert = SecuritySettingsStatusAlert(
                        title: L10n.settings.security.status.biometricEnabledTitle,
                        message: L10n.settings.security.status.biometricEnabledMessage
                    )
                }
            case .disableBiometric:
                try appLockController.setBiometricsEnabled(false)
                statusAlert = SecuritySettingsStatusAlert(
                    title: L10n.settings.security.status.biometricDisabledTitle,
                    message: L10n.settings.security.status.biometricDisabledMessage
                )
            case .changeKind(let kind):
                activeSheet = .setup(kind, .changeKind)
            }
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
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            SecurityPreferenceIcon(systemImage: systemImage, accent: accent)

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
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(MistiaAccent.mint.color)

                VStack(spacing: 8) {
                    Text(L10n.shared.appLock.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(L10n.shared.appLock.subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                MistiaAppLockEntryPanel(
                    mode: .unlock,
                    kind: appLockController.configuredSecretKind ?? .pin4,
                    onSubmit: { secret in
                        appLockController.verify(secret: secret)
                    }
                )

                Button {
                } label: {
                    Text(L10n.shared.appLock.forgotCode)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .disabled(true)
                .foregroundStyle(.secondary)

                if appLockController.isBiometricEnabled, appLockController.biometryKind != .none {
                    Button {
                        Task { await authenticateWithBiometrics() }
                    } label: {
                        Label(biometricButtonTitle, systemImage: biometricIconName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MistiaAccent.purple.color)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 30)
            .frame(maxWidth: 420)
        }
        .task {
            guard !didAttemptBiometric else { return }
            didAttemptBiometric = true
            await authenticateWithBiometrics()
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

private struct MistiaAppLockSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: MistiaAppLockSecretKind
    let onComplete: (String) -> Void

    var body: some View {
        NavigationStack {
            MistiaAppLockEntryPanel(mode: .setup, kind: kind) { secret in
                onComplete(secret)
                dismiss()
                return true
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .navigationTitle(setupTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.common.cancel) { dismiss() }
                }
            }
        }
    }

    private var setupTitle: String {
        switch kind {
        case .pin4:
            L10n.shared.appLock.setupPin4Title
        case .pin6:
            L10n.shared.appLock.setupPin6Title
        case .customPassword:
            L10n.shared.appLock.setupPasswordTitle
        }
    }
}

private struct MistiaAppLockAuthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MistiaAppLockController.self) private var appLockController
    let kind: MistiaAppLockSecretKind
    let onAuthenticated: () -> Void

    var body: some View {
        NavigationStack {
            MistiaAppLockEntryPanel(mode: .authenticate, kind: kind) { secret in
                guard appLockController.verify(secret: secret) else { return false }
                onAuthenticated()
                dismiss()
                return true
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .navigationTitle(L10n.shared.appLock.enterCurrentCodeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.common.cancel) { dismiss() }
                }
            }
        }
    }
}

private struct MistiaAppLockEntryPanel: View {
    @Environment(MistiaAppLockController.self) private var appLockController
    let mode: MistiaAppLockEntryMode
    let kind: MistiaAppLockSecretKind
    let onSubmit: (String) -> Bool

    @State private var pinInput = ""
    @State private var pendingSecret: String?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(promptTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                if let helperText {
                    Text(helperText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if kind == .customPassword {
                passwordFields
            } else {
                pinDots
                MistiaPINKeypad(
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
    }

    private var passwordFields: some View {
        VStack(spacing: 12) {
            SecureField(L10n.shared.appLock.passwordPlaceholder, text: $password)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            if mode == .setup {
                SecureField(L10n.shared.appLock.confirmPasswordPlaceholder, text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            Button(mode == .setup ? L10n.shared.appLock.continueButton : L10n.shared.appLock.unlock) {
                submitPassword()
            }
            .buttonStyle(.borderedProminent)
            .tint(MistiaAccent.purple.color)
            .disabled(isManualEntryLockedOut || password.isEmpty || (mode == .setup && confirmPassword.isEmpty))
        }
    }

    private var pinDots: some View {
        HStack(spacing: 12) {
            ForEach(0..<pinLength, id: \.self) { index in
                Circle()
                    .fill(index < pinInput.count ? MistiaAccent.purple.color : Color.secondary.opacity(0.24))
                    .frame(width: 13, height: 13)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(promptTitle)
    }

    private var pinLength: Int {
        kind == .pin4 ? 4 : 6
    }

    private var promptTitle: String {
        switch mode {
        case .unlock:
            return kind == .customPassword
                ? L10n.shared.appLock.enterPassword
                : pinLength == 4 ? L10n.shared.appLock.enterPin4 : L10n.shared.appLock.enterPin6
        case .authenticate:
            return L10n.shared.appLock.enterCurrentCodeTitle
        case .setup:
            if pendingSecret == nil {
                return kind == .customPassword
                    ? L10n.shared.appLock.createPassword
                    : pinLength == 4 ? L10n.shared.appLock.createPin4 : L10n.shared.appLock.createPin6
            }
            return kind == .customPassword
                ? L10n.shared.appLock.confirmPassword
                : L10n.shared.appLock.confirmPin
        }
    }

    private var helperText: String? {
        if isManualEntryLockedOut {
            return lockedOutText
        }

        switch mode {
        case .unlock, .authenticate:
            return nil
        case .setup:
            return kind == .customPassword
                ? L10n.shared.appLock.passwordHelper
                : L10n.shared.appLock.pinHelper
        }
    }

    private var lockedOutText: String? {
        guard let lockedUntil = appLockController.failureState.lockedUntil else { return nil }
        let seconds = max(1, Int(ceil(lockedUntil.timeIntervalSince(Date()))))
        return L10n.shared.appLock.tryAgainInSeconds("\(seconds)")
    }

    private var isManualEntryLockedOut: Bool {
        MistiaAppLockLogic.isLockedOut(appLockController.failureState)
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
                errorMessage = MistiaAppLockLogic.isLockedOut(appLockController.failureState)
                    ? lockedOutText
                    : L10n.shared.appLock.wrongCode
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
                errorMessage = MistiaAppLockLogic.isLockedOut(appLockController.failureState)
                    ? lockedOutText
                    : L10n.shared.appLock.wrongCode
                return
            }
            errorMessage = nil
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
        }
    }
}

private struct MistiaPINKeypad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "delete"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(row, id: \.self) { item in
                        keypadButton(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keypadButton(_ item: String) -> some View {
        if item.isEmpty {
            Color.clear
                .frame(width: 66, height: 54)
        } else if item == "delete" {
            Button(action: onDelete) {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 66, height: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else {
            Button {
                onDigit(item)
            } label: {
                Text(verbatim: item)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .frame(width: 66, height: 54)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }
}

private struct SecurityPreferenceIcon: View {
    let systemImage: String
    let accent: MistiaAccent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.color.opacity(0.15))

            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent.color)
        }
        .frame(width: 32, height: 32)
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

private enum SecuritySettingsSheet: Identifiable {
    case setup(MistiaAppLockSecretKind, SecuritySetupCompletion)
    case authenticate(SecurityProtectedAction)

    var id: String {
        switch self {
        case .setup(let kind, let completion):
            "setup-\(kind.rawValue)-\(completion.id)"
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
