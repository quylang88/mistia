import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum ManagementAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn:
            L10n.management.managementauth.signIn
        case .signUp:
            L10n.management.managementauth.createAccount
        }
    }
}

private struct ManagementAutoSyncDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    let accent: Color

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var autoSyncDescription: String {
        if sessionStore.isAutoSyncEnabled {
            return L10n.management.managementauth.mistiaIsAutomaticallyCheckingAndSyncingData
        } else {
            return L10n.management.managementauth.autoSyncIsOffYourDataWill
        }
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.autoSync,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            ManagementProfileListCard(tint: cardTint) {
                HStack(spacing: 12) {
                    Text(L10n.management.managementauth.autoSync)
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Toggle(String(), isOn: Binding(
                        get: { sessionStore.isAutoSyncEnabled },
                        set: { sessionStore.setAutoSyncEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(accent)
                    .disabled(!sessionStore.canPerformRemoteActions)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(autoSyncDescription)
                    .descriptionTextStyle()
                    .lineSpacing(3)
                    .padding(.horizontal, 2)
            }
            .cardDescriptionStyle()
        }
    }
}

private enum ManagementAuthInput: Hashable {
    case displayName
    case email
    case password
    case confirmPassword
}

private enum ManagementProfileDestination: String, Identifiable {
    case settings
    case syncSettings
    case family
    case dataManagement
    case backupRestore
    case signedInDevices
    case editProfile

    var id: String { rawValue }
}

private enum ManagementSyncSettingsDestination: String, Identifiable {
    case dataManagement
    case autoSync

    var id: String { rawValue }
}

private enum ManagementEditProfileSheet: String, Identifiable {
    case name
    case birthday

    var id: String { rawValue }
}

private enum ManagementProfileAvatarSource: String, Identifiable {
    case camera
    case photoLibrary

    var id: String { rawValue }

    var uiImagePickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            .camera
        case .photoLibrary:
            .photoLibrary
        }
    }
}

private enum ManagementEditProfileDestination: String, Identifiable {
    case personalInfo

    var id: String { rawValue }
}

struct ManagementAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query
    private var storedConflicts: [SyncConflict]

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var isEmailAuthExpanded = false
    @State private var destination: ManagementProfileDestination?
    @FocusState private var focusedField: ManagementAuthInput?
    
    @Environment(\.colorScheme) private var colorScheme

    // Tone màu tím đặc trưng, sáng hơn trong Dark Mode
    private var accent: Color {
        colorScheme == .dark 
            ? MistiaAccent.lightPurple.color 
            : MistiaAccent.purple.color
    }

    private let secondaryBackground = Color(UIColor.secondarySystemBackground)

    private var shouldRefreshFamilyBeforeOpening: Bool {
        familyContextStore.family != nil && familyContextStore.members.count >= 2
    }

    private var activeConflicts: [SyncConflict] {
        storedConflicts
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: sessionStore.isSignedIn
                ? L10n.management.managementauth.profile
                : (isEmailAuthExpanded ? authScreenTitle : L10n.management.managementauth.profile),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: "gearshape",
            hidesSystemBackButton: true,
            onLeadingTap: {
                if isEmailAuthExpanded {
                    withAnimation(.snappy) {
                        isEmailAuthExpanded = false
                        focusedField = nil
                    }
                } else {
                    dismiss()
                }
            },
            onTrailingTap: {
                destination = .settings
            },
            contentSpacing: 18
        ) {
            if !sessionStore.isSignedIn {
                if let banner = sessionStore.authBanner {
                    ManagementAuthBannerCard(banner: banner)
                        .padding(.bottom, 6)
                }
            }

            if !sessionStore.isConfigured {
                configurationCard
            } else if let summary = sessionStore.summary {
                signedInContent(summary: summary)
            } else {
                authForm
            }
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .settings:
                SettingsView()
            case .syncSettings:
                ManagementSyncSettingsView(accent: accent)
            case .family:
                FamilyManagementView()
            case .dataManagement:
                ManagementDataConflictsView(accent: accent)
            case .backupRestore:
                ManagementBackupRestoreView()
            case .signedInDevices:
                ManagementSignedInDevicesView(accent: accent)
            case .editProfile:
                if let summary = sessionStore.summary {
                    ManagementEditProfileView(summary: summary, accent: accent)
                } else {
                    ManagementProfilePlaceholderView(
                        title: L10n.management.managementauth.editProfile,
                        systemImage: "square.and.pencil",
                        accent: accent,
                        message: L10n.management.managementauth.theProfileIsnTReadyToEdit
                    )
                }
            }
        }
        .onChange(of: sessionStore.authPendingEmail) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            DispatchQueue.main.async {
                email = newValue
            }
        }
        .onChange(of: displayName) { _, _ in
            DispatchQueue.main.async {
                sessionStore.clearAuthFieldError(.displayName)
            }
        }
        .onChange(of: email) { _, _ in
            DispatchQueue.main.async {
                sessionStore.clearAuthFieldError(.email)
            }
        }
        .onChange(of: password) { _, _ in
            DispatchQueue.main.async {
                sessionStore.clearAuthFieldError(.password)
                sessionStore.clearAuthFieldError(.confirmPassword)
            }
        }
        .onChange(of: confirmPassword) { _, _ in
            DispatchQueue.main.async {
                sessionStore.clearAuthFieldError(.confirmPassword)
            }
        }
        .sheet(
            item: Binding(
                get: { sessionStore.initialSyncPreview },
                set: { preview in
                    if preview == nil {
                        sessionStore.cancelInitialSyncSelection()
                    } else {
                        sessionStore.initialSyncPreview = preview
                    }
                }
            )
        ) { preview in
            ManagementInitialSyncChoiceSheet(
                preview: preview,
                accent: accent,
                onCancel: {
                    sessionStore.cancelInitialSyncSelection()
                }
            ) { choice in
                Task {
                    await sessionStore.startInitialSync(with: choice)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .overlay {
            if let prompt = sessionStore.pendingAuthenticationPrompt {
                ManagementPendingAuthenticationPromptOverlay(
                    prompt: prompt,
                    accent: accent,
                    isWorking: sessionStore.isWorking,
                    onDecision: { decision in
                        Task {
                            await sessionStore.resolvePendingAuthentication(decision)
                        }
                    },
                    onCancel: {
                        sessionStore.clearPendingAuthenticationPrompt()
                    }
                )
            }
        }
    }

    private var configurationCard: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : accent.opacity(0.14)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ManagementStatusBadge(
                    title: L10n.management.managementauth.notConfigured,
                    systemImage: "wrench.and.screwdriver.fill",
                    accent: accent
                )

                Text(
                    L10n.management.managementauth.mistiaAlreadyHasTheSignInAnd
                )
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

                Text(verbatim: "Mistia/MistiaSyncConfig.plist")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "SUPABASE_URL")
                    Text(verbatim: "SUPABASE_ANON_KEY")
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func signedInContent(summary: SessionSummary) -> some View {
        VStack(spacing: 18) {
            profileHeaderCard(summary: summary)

            ManagementProfileListCard(tint: secondaryBackground) {
                VStack(spacing: 0) {
                    ManagementProfileNavigationRow(
                        title: L10n.management.managementauth.syncSettings2,
                        icon: "arrow.triangle.2.circlepath.icloud",
                        accent: .sky,
                        subtitle: nil,
                        value: syncSettingsValue,
                        badge: dataManagementBadgeText,
                        badgeAccent: .purple
                    ) {
                        destination = .syncSettings
                    }

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: L10n.management.managementauth.backupRestore,
                        icon: "externaldrive.fill.badge.icloud",
                        accent: .mint,
                        subtitle: nil
                    ) {
                        destination = .backupRestore
                    }

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: L10n.management.managementauth.signedInDevices,
                        icon: "desktopcomputer",
                        accent: .teal,
                        subtitle: nil
                    ) {
                        destination = .signedInDevices
                    }
                }
            }

            if let lastErrorMessage = sessionStore.lastErrorMessage {
                ManagementInlineMessageCard(
                    title: L10n.management.managementauth.latestIssue,
                    message: lastErrorMessage,
                    accent: .orange
                )
            }

            ManagementProfileListCard(tint: secondaryBackground) {
                ManagementProfileNavigationRow(
                    title: L10n.management.managementauth.family,
                    icon: "person.3.fill",
                    accent: .lightPurple,
                    subtitle: nil,
                    value: familyContextStore.family?.name ?? L10n.management.managementauth.none,
                    isLoading: false,
                    isDisabled: !sessionStore.canPerformRemoteActions
                ) {
                    openFamily()
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: L10n.management.managementauth.signOutAndKeepLocal,
                confirmationMessage: L10n.management.managementauth.youWillBeSignedOutOfMistia,
                isDisabled: sessionStore.isWorking
            ) {
                Task {
                    await sessionStore.signOut()
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: L10n.management.managementauth.signOutAndDeleteLocal,
                confirmationMessage: L10n.management.managementauth.youWillBeSignedOutAndThe,
                isDisabled: sessionStore.isWorking
            ) {
                Task {
                    await sessionStore.signOutAndDeleteLocalData()
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: L10n.management.managementauth.deleteAccount,
                confirmationMessage: L10n.management.managementauth.yourCloudAccountAndSyncedServerData,
                isDisabled: sessionStore.isWorking || !sessionStore.canPerformRemoteActions
            ) {
                Task {
                    await sessionStore.deleteAccountKeepingLocalData()
                }
            }
        }
    }

    private func openFamily() {
        destination = .family
        guard shouldRefreshFamilyBeforeOpening else {
            return
        }

        Task { @MainActor in
            await familyContextStore.refreshFamilyMetadata(sessionStore: sessionStore)
        }
    }

    private func profileHeaderCard(summary: SessionSummary) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                MistiaAvatarBadge(
                    initials: summary.initials,
                    avatarURL: summary.avatarURL,
                    size: 88,
                    showsStatus: false
                )

                Button {
                    destination = .editProfile
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(accent, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color(UIColor.systemBackground), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.management.managementauth.editProfile)
                .offset(x: 2, y: 2)
                .disabled(!sessionStore.canPerformRemoteActions)
                .opacity(sessionStore.canPerformRemoteActions ? 1 : 0.55)
            }

            Text(summary.displayName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(summary.email)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            ManagementProfileSyncBadge(
                title: lastSyncBadgeTitle,
                accent: sessionStore.isOfflineModeActive
                    ? .sky
                    : (sessionStore.lastSyncAt == nil ? .slate : .mint)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var lastSyncBadgeTitle: String {
        if sessionStore.isOfflineModeActive {
            return L10n.management.managementauth.offline
        }

        guard let lastSyncAt = sessionStore.lastSyncAt else {
            return L10n.management.managementauth.syncIsOff
        }

        return L10n.management.managementauth.syncedAtValue(String(describing: MistiaDateFormatting.dateTimeString(for: lastSyncAt)))
    }

    private var dataManagementBadgeText: String? {
        guard !activeConflicts.isEmpty else { return nil }
        return "\(activeConflicts.count)"
    }

    private var syncSettingsValue: String {
        if sessionStore.isAutoSyncEnabled {
            return L10n.management.managementauth.auto
        }

        if sessionStore.canManageSync {
            return L10n.management.managementauth.manual
        }

        return L10n.common.off
    }

    private var authForm: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            ZStack {
                if !isEmailAuthExpanded {
                    VStack(spacing: 24) {
                        introContent
                        authMenuContent
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        authPhaseContent
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }

            if let lastErrorMessage = lastSignedInIssue {
                ManagementInlineMessageCard(
                    title: L10n.management.managementauth.canTContinueYet,
                    message: lastErrorMessage,
                    accent: .orange
                )
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private var introContent: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.95),
                                accent.opacity(0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "cloud.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: accent.opacity(0.18), radius: 16, y: 8)
            .padding(.bottom, 8)
            
            Text(L10n.management.managementauth.welcomeToMistia)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            
            Text(authIntroCopy)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 32)
    }
    
    private var authMenuContent: some View {
        VStack(spacing: 16) {
            ManagementGoogleActionButton(
                title: L10n.management.managementauth.continueWithGoogle,
                isWorking: sessionStore.isWorking && sessionStore.activeAuthAction == .google,
                accent: accent
            ) {
                Task {
                    await sessionStore.signInWithGoogle()
                }
            }
            .disabled(sessionStore.isWorking)

            ManagementAuthDivider(
                title: L10n.management.managementauth.or
            )

            Button {
                withAnimation(.snappy) {
                    isEmailAuthExpanded = true
                    transition(to: .signIn)
                }
            } label: {
                Text(L10n.management.managementauth.continueWithEmail)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(UIColor.secondarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            
            Text(
                L10n.management.managementauth.byContinuingYouAgreeToOurTerms
            )
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 16)
        }
    }

    private var authScreenTitle: String {
        switch sessionStore.authPhase {
        case .signIn:
            return L10n.management.managementauth.signIn
        case .signUp:
            return L10n.management.managementauth.createAccount
        case .forgotPassword:
            return L10n.management.managementauth.forgotPassword2
        case .verifyEmailPending:
            return L10n.management.managementauth.confirmYourEmail
        }
    }

    private var authIntroCopy: String {
        switch sessionStore.authPhase {
        case .signIn, .signUp:
            return L10n.management.managementauth.useTheSameMistiaAccountToSync
        case .forgotPassword:
            return L10n.management.managementauth.enterTheEmailYouUseWithMistia
        case .verifyEmailPending:
            return L10n.management.managementauth.yourAccountIsWaitingForEmailConfirmation
        }
    }

    private var showsPrimaryModeSwitcher: Bool {
        sessionStore.authPhase == .signIn || sessionStore.authPhase == .signUp
    }

    private var selectedMode: Binding<ManagementAuthMode> {
        Binding(
            get: { sessionStore.authPhase == .signUp ? .signUp : .signIn },
            set: { newValue in
                switch newValue {
                case .signIn:
                    transition(to: .signIn)
                case .signUp:
                    transition(to: .signUp)
                }
            }
        )
    }

    @ViewBuilder
    private var authPhaseContent: some View {
        switch sessionStore.authPhase {
        case .signIn, .signUp:
            primaryAuthForm
        case .forgotPassword:
            forgotPasswordForm
        case .verifyEmailPending:
            verifyEmailPendingContent
        }
    }

    private var primaryAuthForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sessionStore.authPhase == .signUp {
                ManagementAuthFieldContainer(errorMessage: sessionStore.authFieldErrors[.displayName]) {
                    TextField(
                        L10n.management.managementauth.displayName,
                        text: $displayName
                    )
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .displayName)
                    .onSubmit { focusedField = .email }
                }
            }

            ManagementAuthFieldContainer(errorMessage: sessionStore.authFieldErrors[.email]) {
                TextField(
                    L10n.management.managementauth.email2,
                    text: $email
                )
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
            }

            ManagementPasswordInputField(
                placeholder: L10n.management.managementauth.password,
                text: $password,
                isVisible: $isPasswordVisible,
                errorMessage: sessionStore.authFieldErrors[.password],
                textContentType: sessionStore.authPhase == .signUp ? .newPassword : .password,
                submitLabel: sessionStore.authPhase == .signUp ? .next : .go,
                focusField: .password,
                focusedField: $focusedField,
                onSubmit: {
                    if sessionStore.authPhase == .signUp {
                        focusedField = .confirmPassword
                    } else {
                        submit()
                    }
                }
            )

            if sessionStore.authPhase == .signUp {
                ManagementPasswordStrengthMeter(assessment: passwordAssessment)

                ManagementPasswordRequirementChecklist(
                    assessment: passwordAssessment,
                    showsNeutralState: password.isEmpty
                )

                ManagementPasswordInputField(
                    placeholder: L10n.management.managementauth.confirmPassword,
                    text: $confirmPassword,
                    isVisible: $isConfirmPasswordVisible,
                    errorMessage: sessionStore.authFieldErrors[.confirmPassword],
                    textContentType: .newPassword,
                    submitLabel: .done,
                    focusField: .confirmPassword,
                    focusedField: $focusedField,
                    onSubmit: submit
                )
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if sessionStore.isWorking {
                        if sessionStore.activeAuthAction == .credentials {
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                        }
                    }

                    Text(
                        sessionStore.authPhase == .signUp
                            ? L10n.management.managementauth.createAccount
                            : L10n.management.managementauth.signIn
                    )
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? .white : accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isWorking || !canSubmit)
            .opacity((sessionStore.isWorking || !canSubmit) ? 0.6 : 1.0)

            if sessionStore.authPhase != .signUp {
                Button {
                    transition(to: .forgotPassword)
                } label: {
                    Text(L10n.management.managementauth.forgotPassword)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .padding(.top, 4)
            }
            
            VStack(spacing: 0) {
                Divider()
                    .padding(.vertical, 24)

                if sessionStore.authPhase == .signIn {
                    Button {
                        transition(to: .signUp)
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.management.managementauth.donTHaveAnAccount)
                                .foregroundStyle(.secondary)
                            Text(L10n.management.managementauth.signUpNow)
                                .foregroundStyle(accent)
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 14, design: .rounded))
                    }
                    .buttonStyle(.plain)
                } else if sessionStore.authPhase == .signUp {
                    Button {
                        transition(to: .signIn)
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.management.managementauth.alreadyHaveAnAccount)
                                .foregroundStyle(.secondary)
                            Text(L10n.management.managementauth.signIn)
                                .foregroundStyle(accent)
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 14, design: .rounded))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var forgotPasswordForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            ManagementAuthFieldContainer(errorMessage: sessionStore.authFieldErrors[.email]) {
                TextField(
                    L10n.management.managementauth.email2,
                    text: $email
                )
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focusedField, equals: .email)
                .onSubmit { submit() }
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if sessionStore.activeAuthAction == .passwordReset {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                    }

                    Text(
                        L10n.management.managementauth.sendResetEmail
                    )
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? .white : accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isWorking || trimmedEmail.isEmpty)
            .opacity((sessionStore.isWorking || trimmedEmail.isEmpty) ? 0.6 : 1.0)

            Button {
                transition(to: .signIn)
            } label: {
                Text(L10n.management.managementauth.backToSignIn)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
    }

    private var verifyEmailPendingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !activeEmail.isEmpty {
                ManagementAuthEmailChip(email: maskEmail(activeEmail), accent: accent)
            }

            Button {
                Task {
                    await sessionStore.resendConfirmation(email: activeEmail)
                }
            } label: {
                HStack(spacing: 10) {
                    if sessionStore.activeAuthAction == .resendConfirmation {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                    }

                    Text(L10n.management.managementauth.resendConfirmationEmail)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? .white : accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isWorking || activeEmail.isEmpty)
            .opacity((sessionStore.isWorking || activeEmail.isEmpty) ? 0.6 : 1.0)

            Button {
                transition(to: .signIn)
            } label: {
                Text(L10n.management.managementauth.backToSignIn)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
    }

    private var passwordAssessment: PasswordStrengthAssessment {
        PasswordStrengthAssessment(password: password)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeEmail: String {
        sessionStore.authPendingEmail ?? trimmedEmail
    }

    private var canSubmit: Bool {
        switch sessionStore.authPhase {
        case .signIn:
            return !trimmedEmail.isEmpty && !password.isEmpty
        case .signUp:
            return !trimmedDisplayName.isEmpty && !trimmedEmail.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
        case .forgotPassword:
            return !trimmedEmail.isEmpty
        case .verifyEmailPending:
            return false
        }
    }

    private var lastSignedInIssue: String? {
        sessionStore.isSignedIn ? sessionStore.lastErrorMessage : nil
    }

    private func transition(to phase: SessionAuthPhase) {
        sessionStore.showAuthPhase(phase)

        switch phase {
        case .signIn:
            clearPasswords()
            focusedField = .email
        case .signUp:
            clearPasswords()
            focusedField = .displayName
        case .forgotPassword:
            clearPasswords()
            focusedField = .email
        case .verifyEmailPending:
            clearPasswords()
            focusedField = nil
        }
    }

    private func submit() {
        sessionStore.clearAuthBanner()

        let errors = validationErrors()
        guard errors.isEmpty else {
            sessionStore.setAuthFieldErrors(errors)
            focusFirstInvalidField(using: errors)
            return
        }

        sessionStore.setAuthFieldErrors([:])

        Task {
            switch sessionStore.authPhase {
            case .signIn:
                await sessionStore.signIn(email: trimmedEmail, password: password)
                if sessionStore.authPhase == .verifyEmailPending {
                    clearPasswords()
                }
            case .signUp:
                await sessionStore.signUp(
                    email: trimmedEmail,
                    password: password,
                    displayName: trimmedDisplayName
                )
                if sessionStore.authPhase == .verifyEmailPending {
                    clearPasswords()
                }
            case .forgotPassword:
                await sessionStore.requestPasswordReset(email: trimmedEmail)
            case .verifyEmailPending:
                break
            }
        }
    }

    private func validationErrors() -> [SessionAuthField: String] {
        var errors: [SessionAuthField: String] = [:]

        switch sessionStore.authPhase {
        case .signIn:
            if !isValidEmail(trimmedEmail) {
                errors[.email] = L10n.management.managementauth.theEmailFormatDoesnTLookRight
            }

            if password.isEmpty {
                errors[.password] = L10n.management.managementauth.enterYourPasswordToContinue
            }
        case .signUp:
            if trimmedDisplayName.isEmpty {
                errors[.displayName] = L10n.management.managementauth.displayNameCanTBeEmpty
            }

            if !isValidEmail(trimmedEmail) {
                errors[.email] = L10n.management.managementauth.theEmailFormatDoesnTLookRight
            }

            if !passwordAssessment.hasMinimumLength {
                errors[.password] = L10n.management.managementauth.passwordMustBeAtLeastCharacters
            } else if !passwordAssessment.hasUppercase {
                errors[.password] = L10n.management.managementauth.passwordNeedsAtLeastUppercaseLetter
            } else if !passwordAssessment.hasLowercase {
                errors[.password] = L10n.management.managementauth.passwordNeedsAtLeastLowercaseLetter
            }

            if confirmPassword.isEmpty {
                errors[.confirmPassword] = L10n.management.managementauth.reEnterYourPasswordToConfirmIt
            } else if confirmPassword != password {
                errors[.confirmPassword] = L10n.management.managementauth.theConfirmationPasswordDoesnTMatchYet
            }
        case .forgotPassword:
            if !isValidEmail(trimmedEmail) {
                errors[.email] = L10n.management.managementauth.theEmailFormatDoesnTLookRight
            }
        case .verifyEmailPending:
            break
        }

        return errors
    }

    private func focusFirstInvalidField(using errors: [SessionAuthField: String]) {
        let order: [SessionAuthField]
        switch sessionStore.authPhase {
        case .signIn:
            order = [.email, .password]
        case .signUp:
            order = [.displayName, .email, .password, .confirmPassword]
        case .forgotPassword:
            order = [.email]
        case .verifyEmailPending:
            order = []
        }

        guard let first = order.first(where: { errors[$0] != nil }) else {
            return
        }

        switch first {
        case .displayName:
            focusedField = .displayName
        case .email:
            focusedField = .email
        case .password:
            focusedField = .password
        case .confirmPassword:
            focusedField = .confirmPassword
        }
    }

    private func clearPasswords() {
        password = ""
        confirmPassword = ""
        isPasswordVisible = false
        isConfirmPasswordVisible = false
    }

    private func isValidEmail(_ value: String) -> Bool {
        let emailPattern = #"^\S+@\S+\.\S+$"#
        return value.range(of: emailPattern, options: .regularExpression) != nil
    }

    private func maskEmail(_ value: String) -> String {
        let components = value.split(separator: "@", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return value }

        let local = components[0]
        let domain = components[1]
        let visiblePrefix = String(local.prefix(2))
        let hiddenCount = max(local.count - visiblePrefix.count, 1)
        return "\(visiblePrefix)\(String(repeating: "•", count: hiddenCount))@\(domain)"
    }
}

private struct ManagementProfileSectionLabel: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.64) : Color.black.opacity(0.46))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

private struct ManagementPendingAuthenticationPromptOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    let prompt: SessionPendingAuthenticationPrompt
    let accent: Color
    let isWorking: Bool
    let onDecision: (SessionPendingAuthenticationDecision) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.34 : 0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        ManagementPendingAuthenticationSymbolBadge(
                            systemImage: promptSymbolName,
                            accent: accent
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(prompt.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(prompt.message)
                                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(actionOptions) { option in
                            ManagementPendingAuthenticationOptionButton(
                                title: option.title,
                                subtitle: option.subtitle,
                                systemImage: option.systemImage,
                                accent: accent,
                                role: option.role,
                                isDisabled: isWorking
                            ) {
                                onDecision(option.decision)
                            }
                        }
                    }

                    Button(L10n.common.cancel) {
                        onCancel()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        ManagementPendingAuthenticationOptionBackground(
                            accent: accent,
                            role: .normal,
                            isEnabled: !isWorking
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.5 : 1)
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background {
                ManagementPendingAuthenticationCardBackground(accent: accent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            }
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.24) : .black.opacity(0.10),
                radius: 28,
                y: 16
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var promptSymbolName: String {
        switch prompt.kind {
        case .attachGuestData:
            return "person.crop.circle.badge.questionmark"
        case .keepOrDeleteGuestData:
            return "externaldrive.badge.person.crop"
        }
    }

    private var actionOptions: [ManagementPendingAuthenticationOption] {
        switch prompt.kind {
        case .attachGuestData:
            return [
                .init(
                    decision: .attachGuestData,
                    role: .primary,
                    systemImage: "arrow.down.circle.fill",
                    title: L10n.management.managementauth.attachToThisAccount,
                    subtitle: L10n.management.managementauth.keepTheCurrentGuestLocalDataAs
                ),
                .init(
                    decision: .keepGuestDataSeparate,
                    role: .normal,
                    systemImage: "square.split.2x1.fill",
                    title: L10n.management.managementauth.keepGuestSeparate,
                    subtitle: L10n.management.managementauth.signInToThisAccountWithoutMixing
                ),
                .init(
                    decision: .deleteGuestData,
                    role: .destructive,
                    systemImage: "trash.fill",
                    title: L10n.management.managementauth.deleteGuestData,
                    subtitle: L10n.management.managementauth.deleteTheCurrentGuestLocalDataBefore2
                )
            ]

        case .keepOrDeleteGuestData:
            return [
                .init(
                    decision: .keepGuestDataSeparate,
                    role: .primary,
                    systemImage: "square.split.2x1.fill",
                    title: L10n.management.managementauth.keepGuestSeparate,
                    subtitle: L10n.management.managementauth.openThisAccountInItsOwnProfile
                ),
                .init(
                    decision: .deleteGuestData,
                    role: .destructive,
                    systemImage: "trash.fill",
                    title: L10n.management.managementauth.deleteGuestData,
                    subtitle: L10n.management.managementauth.deleteTheCurrentGuestLocalDataBefore
                )
            ]
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.48)
    }
}

private struct ManagementPendingAuthenticationOption: Identifiable {
    let decision: SessionPendingAuthenticationDecision
    let role: ManagementPendingAuthenticationOptionButton.Role
    let systemImage: String
    let title: String
    let subtitle: String

    var id: SessionPendingAuthenticationDecision { decision }
}

private struct ManagementPendingAuthenticationCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(baseFillColor)

            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular.tint(
                            colorScheme == .dark ? .white.opacity(0.06) : accent.opacity(0.08)
                        ),
                        in: .rect(cornerRadius: 30)
                    )
            }
        }
    }

    private var baseFillColor: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.96)
            : Color.white.opacity(0.86)
    }
}

private struct ManagementPendingAuthenticationSymbolBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : accent.opacity(0.12))

            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular
                            .tint(colorScheme == .dark ? .white.opacity(0.08) : accent.opacity(0.10)),
                        in: .circle
                    )
            }

            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 48, height: 48)
        .overlay {
            Circle()
                .strokeBorder(colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.42), lineWidth: 0.75)
        }
    }
}

private struct ManagementPendingAuthenticationOptionButton: View {
    enum Role {
        case primary
        case normal
        case destructive
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let role: Role
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var foregroundColor: Color {
        switch role {
        case .primary:
            .primary
        case .normal:
            .primary
        case .destructive:
            .red
        }
    }

    private var subtitleColor: Color {
        role == .destructive ? .red.opacity(0.78) : .secondary
    }

    private var iconTint: Color {
        switch role {
        case .primary:
            accent
        case .normal:
            colorScheme == .dark ? .white.opacity(0.92) : .primary
        case .destructive:
            .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(colorScheme == .dark ? 0.18 : 0.12))

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(foregroundColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Image(systemName: role == .destructive ? "minus.circle.fill" : "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(role == .destructive ? Color.red : accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ManagementPendingAuthenticationOptionBackground(
                    accent: accent,
                    role: role,
                    isEnabled: !isDisabled
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ManagementPendingAuthenticationOptionBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let role: ManagementPendingAuthenticationOptionButton.Role
    let isEnabled: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(baseFillColor)

            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.clear)
                    .glassEffect(nativeGlassStyle, in: .rect(cornerRadius: 24))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.75)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.44)
    }

    private var baseFillColor: Color {
        switch role {
        case .primary:
            return colorScheme == .dark ? accent.opacity(0.18) : accent.opacity(0.12)
        case .normal:
            return colorScheme == .dark
                ? Color(UIColor.tertiarySystemGroupedBackground).opacity(0.92)
                : Color.white.opacity(0.72)
        case .destructive:
            return colorScheme == .dark ? Color.red.opacity(0.14) : Color.red.opacity(0.08)
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        let tint: Color

        switch role {
        case .primary:
            tint = colorScheme == .dark ? accent.opacity(isEnabled ? 0.18 : 0.08) : accent.opacity(isEnabled ? 0.12 : 0.06)
        case .normal:
            tint = colorScheme == .dark ? .white.opacity(isEnabled ? 0.07 : 0.04) : .white.opacity(isEnabled ? 0.18 : 0.10)
        case .destructive:
            tint = colorScheme == .dark ? .red.opacity(isEnabled ? 0.14 : 0.07) : .red.opacity(isEnabled ? 0.10 : 0.06)
        }

        var style = Glass.regular.tint(tint)
        if isEnabled {
            style = style.interactive(true)
        }
        return style
    }
}

private struct ManagementProfileListCard<Content: View>: View {
    let tint: Color
    let content: Content

    init(
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint, padding: 0) {
            content
        }
    }
}

private struct ManagementProfileSyncBadge: View {
    let title: String
    let accent: MistiaAccent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
        }
        .foregroundStyle(accent.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent.color.opacity(0.12), in: Capsule())
    }
}

private struct ManagementProfileRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 56)
    }
}

private struct ManagementProfileInfoRow: View {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let value: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
            ManagementProfileIconTile(icon: icon, accent: accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
    }
}

private struct ManagementProfileActionRow: View {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let subtitle: String?
    let isDisabled: Bool
    let showsProgress: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ManagementProfileIconTile(icon: icon, accent: accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                if showsProgress {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accent.color))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ManagementProfileToggleRow: View {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let subtitle: String?
    let isOn: Binding<Bool>
    let isDisabled: Bool

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
            ManagementProfileIconTile(icon: icon, accent: accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Toggle(String(), isOn: isOn)
                .labelsHidden()
                .tint(accent.color)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ManagementProfileNavigationRow: View {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let subtitle: String?
    var value: String? = nil
    var badge: String? = nil
    var badgeAccent: MistiaAccent? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
                ManagementProfileIconTile(icon: icon, accent: accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((badgeAccent ?? accent).color, in: Capsule())
                    }

                    if let value {
                        Text(value)
                            .font(.system(size: 14.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accent.color))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ManagementProfileDestructiveRow: View {
    let title: String
    let icon: String
    let accent: MistiaAccent
    let subtitle: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ManagementProfileIconTile(icon: icon, accent: accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent.color)

                    Text(subtitle)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accent.color))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ManagementSettingsFootnote: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.56) : Color.black.opacity(0.44))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }
}

private struct ManagementProfileCenteredDestructiveButton: View {
    let title: String
    let confirmationMessage: String
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsConfirmation = false

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemBackground)
            : Color(UIColor.systemBackground)
    }

    var body: some View {
        Button {
            showsConfirmation = true
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .confirmationDialog(
            "",
            isPresented: $showsConfirmation,
            titleVisibility: .hidden
        ) {
            Button(title, role: .destructive) {
                action()
            }
            Button(L10n.common.cancel, role: .cancel) { }
        } message: {
            Text(confirmationMessage)
        }
    }
}

private struct ManagementProfilePrimaryActionButton: View {
    let title: String
    let accent: Color
    let isDisabled: Bool
    let showsProgress: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        showsProgress ? Color(UIColor.systemGray4) : MistiaAccent.purple.color
    }

    private var foregroundColor: Color {
        .white
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity)

                if showsProgress {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(foregroundColor)
                            .padding(.trailing, 20)
                    }
                }
            }
            .padding(.vertical, 17)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || showsProgress)
        .scaleEffect((isDisabled || showsProgress) ? 0.98 : 1.0)
        .animation(.snappy, value: showsProgress)
    }
}

private struct ManagementProfileIconTile: View {
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

private struct ManagementStatusBadge: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(accent)
    }
}

private struct ManagementInitialSyncChoiceSheet: View {
    let preview: MistiaInitialSyncPreview
    let accent: Color
    let onCancel: () -> Void
    let onSelect: (MistiaInitialSyncChoice) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(
                            preview.remoteActiveCount == 0
                            ? L10n.management.managementauth.theCloudHasNoDataYetExcept(String(describing: preview.localActiveCount))
                            : L10n.management.managementauth.thisDeviceHasValueRecordsAndThe(String(describing: preview.localActiveCount), String(describing: preview.remoteActiveCount))
                        )
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            ManagementInitialSyncChoiceButton(
                                title: L10n.management.managementauth.mergeSafely,
                                detail: L10n.management.managementauth.keepBothSidesMergeByRecordID,
                                accent: accent,
                                isRecommended: true
                            ) {
                                onSelect(.mergeSafely)
                            }

                            ManagementInitialSyncChoiceButton(
                                title: L10n.management.managementauth.useThisDevice,
                                detail: L10n.management.managementauth.uploadLocalDataToTheCloudAnd,
                                accent: accent,
                                isRecommended: false
                            ) {
                                onSelect(.useDevice)
                            }

                            ManagementInitialSyncChoiceButton(
                                title: L10n.management.managementauth.useCloud2,
                                detail: L10n.management.managementauth.replaceTheCurrentLocalSnapshotWithThe,
                                accent: .secondary,
                                isRecommended: false
                            ) {
                                onSelect(.useCloud)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(
                L10n.management.managementauth.firstSync
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ManagementInitialSyncChoiceButton: View {
    let title: String
    let detail: String
    let accent: Color
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if isRecommended {
                        Text(L10n.management.managementauth.recommended)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }

                Text(detail)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
    }
}

private struct ManagementSyncConflictSection: Identifiable {
    let entity: MistiaSyncEntity
    let conflicts: [SyncConflict]

    var id: String { entity.rawValue }

    var title: String { entity.displayTitle }

    var systemImage: String {
        entity.managementConflictSystemImageName
    }
}

private extension MistiaSyncEntity {
    var managementConflictSystemImageName: String {
        switch self {
        case .wallet:
            return "wallet.pass.fill"
        case .creditCardProfile:
            return "creditcard.fill"
        case .category:
            return "square.grid.2x2.fill"
        case .settlementGroup:
            return "hourglass.circle.fill"
        case .settlementParticipant:
            return "person.2.fill"
        case .transaction:
            return "list.bullet.rectangle.portrait.fill"
        case .budgetPlan:
            return "chart.pie.fill"
        case .savingsGoal:
            return "target"
        case .recurringBillPlan:
            return "calendar.badge.clock"
        case .installmentPlan:
            return "calendar.badge.exclamationmark"
        case .dueOccurrenceRecord:
            return "checklist"
        }
    }
}

private struct ManagementSyncConflictCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var storedWallets: [LedgerWallet]
    @Query private var storedCreditCardProfiles: [CreditCardProfile]
    @Query private var storedCategories: [TransactionCategory]
    @Query private var storedTransactions: [LedgerTransaction]
    @Query private var storedBudgetPlans: [BudgetPlan]
    @Query private var storedSavingsGoals: [SavingsGoal]
    @Query private var storedRecurringBillPlans: [RecurringBillPlan]
    @Query private var storedInstallmentPlans: [InstallmentPlan]
    @Query private var storedDueOccurrences: [DueOccurrenceRecord]

    let conflict: SyncConflict
    let accent: Color
    let isDisabled: Bool
    let onResolve: (MistiaSyncConflictResolution) -> Void

    private var differences: [MistiaSyncConflictDifference] {
        conflict.conflictDifferences
    }

    private var friendlyDifferences: [MistiaSyncConflictDifference] {
        differences.map { referenceResolver.resolving($0) }
    }

    private var visibleDifferences: [MistiaSyncConflictDifference] {
        let userFacingDifferences = friendlyDifferences.filter { !isInternalConflictField($0.id) }
        let semanticDifferences = userFacingDifferences.filter { !isMetadataConflictField($0.id) }
        if !semanticDifferences.isEmpty {
            return Array(semanticDifferences.prefix(3))
        }
        if !userFacingDifferences.isEmpty {
            return Array(userFacingDifferences.prefix(2))
        }
        return []
    }

    private var recordTitle: String {
        let localTitle = conflict.localRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localTitle.isEmpty, localTitle != conflict.entity.displayTitle {
            return localTitle
        }

        let remoteTitle = conflict.remoteRecordSummary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteTitle.isEmpty {
            return remoteTitle
        }

        return conflict.entity.displayTitle
    }

    private var recordSubtitle: String {
        conflict.entity.displayTitle
    }

    private var referenceResolver: ManagementConflictReferenceResolver {
        ManagementConflictReferenceResolver(
            wallets: storedWallets,
            creditCardProfiles: storedCreditCardProfiles,
            categories: storedCategories,
            transactions: storedTransactions,
            budgetPlans: storedBudgetPlans,
            savingsGoals: storedSavingsGoals,
            recurringBillPlans: storedRecurringBillPlans,
            installmentPlans: storedInstallmentPlans,
            dueOccurrences: storedDueOccurrences
        )
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: cardTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(colorScheme == .dark ? 0.20 : 0.13))

                        Image(systemName: conflict.entity.managementConflictSystemImageName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(recordTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(recordSubtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                }

                VStack(spacing: 0) {
                    if visibleDifferences.isEmpty {
                        Text(
                            L10n.management.managementauth.conflictInUpdateTiming
                        )
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                    } else {
                        ForEach(Array(visibleDifferences.enumerated()), id: \.element.id) { index, difference in
                            ManagementConflictCompactDifferenceRow(difference: difference)

                            if index < visibleDifferences.count - 1 {
                                Divider()
                                    .padding(.leading, 92)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        conflictButtons
                    }

                    VStack(spacing: 10) {
                        conflictButtons
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var conflictButtons: some View {
        Button {
            onResolve(.useLocal)
        } label: {
            Label(
                L10n.management.managementauth.useLocal,
                systemImage: "icloud.and.arrow.up.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
        .disabled(isDisabled)

        Button {
            onResolve(.useRemote)
        } label: {
            Label(
                L10n.management.managementauth.useCloud,
                systemImage: "icloud.and.arrow.down.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(accent)
        .disabled(isDisabled)
    }

    private var cardTint: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.96)
            : accent.opacity(0.10)
    }

    private func isInternalConflictField(_ id: String) -> Bool {
        let normalized = id
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return normalized == "id"
            || normalized == "uid"
            || normalized == "recordid"
            || normalized.hasSuffix("userid")
            || normalized.hasSuffix("deviceid")
            || normalized == "device"
            || normalized.contains("device")
            || normalized == "systemkey"
            || normalized == "synckey"
            || normalized == "syncversion"
            || normalized == "version"
    }

    private func isMetadataConflictField(_ id: String) -> Bool {
        let normalized = id
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return normalized == "updatedat"
            || normalized == "deletedat"
            || normalized == "createdat"
            || normalized == "archivedat"
    }
}

private struct ManagementConflictReferenceResolver {
    let wallets: [LedgerWallet]
    let creditCardProfiles: [CreditCardProfile]
    let categories: [TransactionCategory]
    let transactions: [LedgerTransaction]
    let budgetPlans: [BudgetPlan]
    let savingsGoals: [SavingsGoal]
    let recurringBillPlans: [RecurringBillPlan]
    let installmentPlans: [InstallmentPlan]
    let dueOccurrences: [DueOccurrenceRecord]

    func resolving(_ difference: MistiaSyncConflictDifference) -> MistiaSyncConflictDifference {
        MistiaSyncConflictDifference(
            id: difference.id,
            fieldTitle: difference.fieldTitle,
            localValue: resolvedValue(for: difference.id, rawValue: difference.localRawValue, fallback: difference.localValue),
            remoteValue: resolvedValue(for: difference.id, rawValue: difference.remoteRawValue, fallback: difference.remoteValue),
            localRawValue: difference.localRawValue,
            remoteRawValue: difference.remoteRawValue
        )
    }

    private func resolvedValue(for fieldID: String, rawValue: String?, fallback: String) -> String {
        guard let rawValue, let uuid = UUID(uuidString: rawValue) else {
            return fallback
        }

        switch fieldID {
        case "wallet",
             "walletID",
             "walletId",
             "wallet_id",
             "sourceWallet",
             "sourceWalletID",
             "sourceWalletId",
             "source_wallet_id",
             "destinationWallet",
             "destinationWalletID",
             "destinationWalletId",
             "destination_wallet_id",
             "paymentWallet",
             "paymentWalletID",
             "paymentWalletId",
             "payment_wallet_id",
             "linkedWallet",
             "linkedWalletID",
             "linkedWalletId",
             "linked_wallet_id":
            return walletName(for: uuid) ?? unavailableName
        case "category",
             "categoryID",
             "categoryId",
             "category_id",
             "parent",
             "parentCategoryID",
             "parentCategoryId",
             "parent_category_id":
            return categoryName(for: uuid) ?? unavailableName
        case "transaction",
             "transactionID",
             "transactionId",
             "transaction_id",
             "linkedTransactionID",
             "linkedTransactionId",
             "linked_transaction_id":
            return transactionName(for: uuid) ?? unavailableName
        case "source", "sourceID", "sourceId", "source_id":
            return sourceName(for: uuid) ?? unavailableName
        default:
            return genericName(for: uuid) ?? unavailableName
        }
    }

    private func walletName(for id: UUID) -> String? {
        wallets.first { $0.id == id }.map { wallet in
            compactConflictName(wallet.name, wallet.currencyCode)
        }
    }

    private func categoryName(for id: UUID) -> String? {
        categories.first { $0.id == id }.map { category in
            if let parent = category.parentCategory {
                return "\(parent.localizedDisplayName) / \(category.localizedDisplayName)"
            }
            return category.localizedDisplayName
        }
    }

    private func transactionName(for id: UUID) -> String? {
        transactions.first { $0.id == id }.map { transaction in
            let title = transaction.localizedTransactionTitle.isEmpty
                ? L10n.management.managementauth.unnamedTransaction
                : transaction.localizedTransactionTitle
            let currencyCode = transaction.sourceWallet?.currencyCode ?? transaction.destinationWallet?.currencyCode ?? "JPY"
            return compactConflictName(title, transaction.amountMinor.formattedCurrency(code: currencyCode))
        }
    }

    private func creditCardName(for id: UUID) -> String? {
        creditCardProfiles.first { $0.id == id }.map { profile in
            profile.issuerName.isEmpty ? profile.last4 : compactConflictName(profile.issuerName, profile.last4)
        }
    }

    private func budgetName(for id: UUID) -> String? {
        budgetPlans.first { $0.id == id }.map { plan in
            compactConflictName(
                plan.category?.localizedDisplayName ?? L10n.management.managementauth.budget,
                plan.limitMinor.formattedCurrency(code: plan.currencyCode)
            )
        }
    }

    private func goalName(for id: UUID) -> String? {
        savingsGoals.first { $0.id == id }?.name
    }

    private func recurringBillName(for id: UUID) -> String? {
        recurringBillPlans.first { $0.id == id }?.name
    }

    private func installmentName(for id: UUID) -> String? {
        installmentPlans.first { $0.id == id }?.name
    }

    private func dueOccurrenceName(for id: UUID) -> String? {
        dueOccurrences.first { $0.id == id }.map { due in
            compactConflictName(
                L10n.management.managementauth.dueOccurrence,
                due.selectedMonthKey
            )
        }
    }

    private func sourceName(for id: UUID) -> String? {
        recurringBillName(for: id)
            ?? installmentName(for: id)
            ?? budgetName(for: id)
            ?? goalName(for: id)
            ?? creditCardName(for: id)
            ?? transactionName(for: id)
            ?? walletName(for: id)
            ?? categoryName(for: id)
    }

    private func genericName(for id: UUID) -> String? {
        walletName(for: id)
            ?? categoryName(for: id)
            ?? transactionName(for: id)
            ?? creditCardName(for: id)
            ?? budgetName(for: id)
            ?? goalName(for: id)
            ?? recurringBillName(for: id)
            ?? installmentName(for: id)
            ?? dueOccurrenceName(for: id)
    }

    private var unavailableName: String {
        L10n.management.managementauth.nameUnavailable
    }

    private func compactConflictName(_ values: String?...) -> String {
        values
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " • ")
    }
}

private struct ManagementConflictCompactDifferenceRow: View {
    let difference: MistiaSyncConflictDifference

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(difference.fieldTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 78, alignment: .leading)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 3) {
                ManagementConflictCompactValueLine(
                    title: L10n.management.managementauth.local,
                    value: difference.localValue
                )

                ManagementConflictCompactValueLine(
                    title: L10n.management.managementauth.cloud,
                    value: difference.remoteValue
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}

private struct ManagementConflictCompactValueLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ManagementConflictSectionHeader: View {
    let section: ManagementSyncConflictSection
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12), in: Circle())

            Text(section.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(verbatim: "\(section.conflicts.count)")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(MistiaAccent.purple.color, in: Capsule())
        }
    }
}

private struct ManagementDataConflictsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Query private var storedConflicts: [SyncConflict]

    let accent: Color

    private var activeConflicts: [SyncConflict] {
        storedConflicts
    }

    private var conflictSections: [ManagementSyncConflictSection] {
        MistiaSyncEntity.allCases.compactMap { entity in
            let rows = activeConflicts.filter { $0.entity == entity }
            guard !rows.isEmpty else { return nil }
            return ManagementSyncConflictSection(entity: entity, conflicts: rows)
        }
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.dataManagement,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                ManagementInlineMessageCard(
                    title: L10n.management.managementauth.resolvingConflictsNeedsTheNetwork,
                    message: remoteUnavailableReason,
                    accent: MistiaAccent.sky.color
                )
            }

            if activeConflicts.isEmpty {
                ManagementProfilePlaceholderCard(
                    title: L10n.management.managementauth.noConflictsYet,
                    message: L10n.management.managementauth.whenSyncConflictsOrReviewNeededData,
                    systemImage: "checkmark.shield.fill",
                    accent: accent
                )
            } else {
                VStack(spacing: 20) {
                    ForEach(conflictSections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            ManagementConflictSectionHeader(section: section, accent: accent)

                            VStack(spacing: 12) {
                                ForEach(section.conflicts) { conflict in
                                    ManagementSyncConflictCard(
                                        conflict: conflict,
                                        accent: accent,
                                        isDisabled: !sessionStore.canPerformRemoteActions
                                    ) { resolution in
                                        Task {
                                            await sessionStore.resolveSyncConflict(
                                                id: conflict.id,
                                                resolution: resolution
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ManagementEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calendar) private var calendar
    @Environment(SessionStore.self) private var sessionStore

    let summary: SessionSummary
    let accent: Color

    @State private var activeSheet: ManagementEditProfileSheet?
    @State private var destination: ManagementEditProfileDestination?
    @State private var draftDisplayName: String
    @State private var birthday: Date
    @State private var hasBirthday: Bool
    @State private var draftAvatarURL: URL?
    @State private var avatarSource: ManagementProfileAvatarSource?
    @State private var showsAvatarSourceDialog = false
    @State private var showsPrivacySheet = false
    @State private var profileErrorMessage: String?

    init(summary: SessionSummary, accent: Color) {
        self.summary = summary
        self.accent = accent
        _draftDisplayName = State(initialValue: summary.displayName)
        _birthday = State(initialValue: MistiaCalendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now)
        _hasBirthday = State(initialValue: false)
        _draftAvatarURL = State(initialValue: summary.avatarURL)
    }

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var birthdayLabel: String {
        guard hasBirthday else {
            return L10n.management.managementauth.add
        }

        return MistiaDateFormatting.fullDateString(
            for: birthday,
            language: MistiaAppLanguage.current,
            calendar: calendar
        )
    }

    private var privacyButtonTitle: String {
        L10n.management.managementauth.learnHowMistiaUsesPersonalInformation
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.editProfile,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 22
        ) {
            VStack(spacing: 18) {
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    ManagementInlineMessageCard(
                        title: L10n.management.managementauth.editingYourProfileNeedsTheNetwork,
                        message: remoteUnavailableReason,
                        accent: MistiaAccent.sky.color
                    )
                }

                VStack(spacing: 14) {
                    ManagementEditableAvatarBadge(
                        initials: currentInitials,
                        avatarURL: draftAvatarURL,
                        size: 116
                    )

                    Button {
                        showsAvatarSourceDialog = true
                    } label: {
                        Text(L10n.management.managementauth.changePhoto)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accent.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!sessionStore.canPerformRemoteActions)
                    .opacity(sessionStore.canPerformRemoteActions ? 1 : 0.55)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ManagementProfileListCard(tint: cardTint) {
                    VStack(spacing: 0) {
                        ManagementEditProfileNavigationRow(
                            title: L10n.management.managementauth.fullName,
                            value: draftDisplayName,
                            isDisabled: !sessionStore.canPerformRemoteActions
                        ) {
                            activeSheet = .name
                        }

                        ManagementEditProfileRowDivider()

                        ManagementEditProfileInfoRow(
                            title: L10n.management.managementauth.email,
                            value: summary.email
                        )

                        ManagementEditProfileRowDivider()

                        ManagementEditProfileNavigationRow(
                            title: L10n.management.managementauth.birthday,
                            value: birthdayLabel,
                            isDisabled: !sessionStore.canPerformRemoteActions
                        ) {
                            activeSheet = .birthday
                        }
                    }
                }

                Button {
                    showsPrivacySheet = true
                } label: {
                    Text(privacyButtonTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .personalInfo:
                EmptyView()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .name:
                ManagementEditProfileNameEditorView(
                    accent: accent,
                    displayName: $draftDisplayName
                ) { updatedDisplayName in
                    persistProfileChanges(displayName: updatedDisplayName)
                }
                .presentationDetents([.medium])
            case .birthday:
                ManagementEditProfileBirthdayEditorView(
                    accent: accent,
                    birthday: $birthday,
                    hasBirthday: $hasBirthday
                ) { updatedBirthday in
                    persistProfileChanges(birthday: updatedBirthday)
                }
                .presentationDetents([.large])
            }
        }
        .sheet(item: $avatarSource) { source in
            ManagementProfileImagePicker(sourceType: source.uiImagePickerSourceType) { image in
                handlePickedAvatar(image)
            }
        }
        .confirmationDialog(
            L10n.management.managementauth.changeProfilePhoto,
            isPresented: $showsAvatarSourceDialog,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(L10n.management.managementauth.takePhoto) {
                    avatarSource = .camera
                }
            }

            Button(L10n.management.managementauth.chooseFromLibrary) {
                avatarSource = .photoLibrary
            }

            Button(L10n.common.cancel, role: .cancel) { }
        }
        .alert(
            L10n.management.managementauth.couldnTUpdateProfile,
            isPresented: Binding(
                get: { profileErrorMessage != nil },
                set: { if !$0 { profileErrorMessage = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text(profileErrorMessage ?? "")
        }
        .sheet(isPresented: $showsPrivacySheet) {
            MistiaPrivacySheet(context: .profile)
        }
        .task {
            draftAvatarURL = sessionStore.summary?.avatarURL ?? summary.avatarURL
            if let storedBirthday = sessionStore.storedBirthday(for: summary.userID) {
                birthday = storedBirthday
                hasBirthday = true
            }
        }
    }

    private var currentInitials: String {
        let components = draftDisplayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        return components.isEmpty ? summary.initials : components.joined()
    }

    private func persistProfileChanges(
        displayName: String? = nil,
        birthday: Date? = nil,
        avatarJPEGData: Data? = nil
    ) {
        guard sessionStore.canPerformRemoteActions else {
            profileErrorMessage = sessionStore.remoteUnavailableReason
            return
        }

        profileErrorMessage = nil

        Task {
            do {
                try await sessionStore.updateProfile(
                    displayName: displayName ?? draftDisplayName,
                    birthday: hasBirthday ? (birthday ?? self.birthday) : birthday,
                    avatarJPEGData: avatarJPEGData
                )

                if let refreshedSummary = sessionStore.summary {
                    draftDisplayName = refreshedSummary.displayName
                    draftAvatarURL = refreshedSummary.avatarURL
                }

                if let birthday {
                    self.birthday = birthday
                    hasBirthday = true
                }
            } catch {
                profileErrorMessage = error.localizedDescription
            }
        }
    }

    private func handlePickedAvatar(_ image: UIImage) {
        guard let avatarJPEGData = image.jpegData(compressionQuality: 0.9) else {
            profileErrorMessage = L10n.management.managementauth.couldnTProcessTheSelectedImage
            return
        }

        persistProfileChanges(avatarJPEGData: avatarJPEGData)
    }
}

private struct ManagementEditProfileNavigationRow: View {
    let title: String
    let value: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ManagementEditProfileInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

private struct ManagementEditProfileRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}


private struct ManagementEditProfileNameEditorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    @Binding var displayName: String
    let onSave: (String) -> Void

    @State private var familyName: String
    @State private var givenName: String

    init(accent: Color, displayName: Binding<String>, onSave: @escaping (String) -> Void) {
        self.accent = accent
        _displayName = displayName
        self.onSave = onSave

        let parts = Self.split(displayName.wrappedValue)
        _familyName = State(initialValue: parts.familyName)
        _givenName = State(initialValue: parts.givenName)
    }

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaModalScaffold(
            title: L10n.management.managementauth.fullName,
            accent: MistiaAccent.purple.color,
            dismissGuardConfiguration: MistiaDismissGuardConfiguration(
                mode: .editing,
                hasUnsavedChanges: composedDisplayName != displayName
            )
        ) {
            displayName = composedDisplayName
            onSave(displayName)
        } content: {
            ManagementProfileListCard(tint: cardTint) {
                VStack(spacing: 0) {
                    ManagementEditProfileTextFieldRow(
                        title: L10n.management.managementauth.lastName,
                        text: $familyName
                    )

                    ManagementEditProfileRowDivider()

                    ManagementEditProfileTextFieldRow(
                        title: L10n.management.managementauth.firstName,
                        text: $givenName
                    )
                }
            }
        }
    }

    private static func split(_ displayName: String) -> (familyName: String, givenName: String) {
        let components = displayName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard let last = components.last else {
            return ("", "")
        }

        let family = components.dropLast().joined(separator: " ")
        return (family, last)
    }

    private var composedDisplayName: String {
        [
            familyName.trimmingCharacters(in: .whitespacesAndNewlines),
            givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct ManagementEditProfileTextFieldRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 16.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .leading)

            TextField(String(), text: $text)
                .font(.system(size: 16.5, weight: .medium, design: .rounded))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

private struct ManagementEditProfileBirthdayEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    let accent: Color
    @Binding var birthday: Date
    @Binding var hasBirthday: Bool
    let onSave: (Date) -> Void

    @State private var draftBirthday: Date

    init(
        accent: Color,
        birthday: Binding<Date>,
        hasBirthday: Binding<Bool>,
        onSave: @escaping (Date) -> Void
    ) {
        self.accent = accent
        _birthday = birthday
        _hasBirthday = hasBirthday
        self.onSave = onSave
        _draftBirthday = State(initialValue: birthday.wrappedValue)
    }

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaModalScaffold(
            title: L10n.management.managementauth.birthday,
            accent: MistiaAccent.purple.color,
            dismissGuardConfiguration: MistiaDismissGuardConfiguration(
                mode: .editing,
                hasUnsavedChanges: draftBirthday != birthday
            )
        ) {
            birthday = draftBirthday
            hasBirthday = true
            onSave(draftBirthday)
        } content: {
            VStack(spacing: 18) {
                ManagementProfileListCard(tint: cardTint) {
                    ManagementEditProfileInfoRow(
                        title: L10n.management.managementauth.birthday,
                        value: MistiaDateFormatting.fullDateString(
                            for: draftBirthday,
                            language: MistiaAppLanguage.current,
                            calendar: calendar
                        )
                    )
                }

                MistiaCalendarView(
                    selection: $draftBirthday,
                    calendar: calendar,
                    language: MistiaAppLanguage.current,
                    selectableRange: .through(...Date()),
                    accent: MistiaAccent.purple.color
                )
            }
        }
    }
}

private struct ManagementEditableAvatarBadge: View {
    let initials: String
    let avatarURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.47, green: 0.26, blue: 0.82),
                            Color(red: 0.74, green: 0.58, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials)
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

private struct ManagementProfileImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let dismiss: DismissAction
        private let onImagePicked: (UIImage) -> Void

        init(dismiss: DismissAction, onImagePicked: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            dismiss()
            if let image {
                onImagePicked(image)
            }
        }
    }
}

private struct ManagementProfilePersonalInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.personalInformation,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
                VStack(alignment: .leading, spacing: 18) {
                    ManagementProfilePersonalInfoItem(
                        title: L10n.management.managementauth.nameAndProfilePhoto,
                        message: L10n.management.managementauth.mistiaUsesYourNameAndProfilePhoto
                    )

                    ManagementProfilePersonalInfoItem(
                        title: L10n.management.managementauth.birthday,
                        message: L10n.management.managementauth.yourBirthdayCanHelpPersonalizeFutureExperiences
                    )

                    ManagementProfilePersonalInfoItem(
                        title: L10n.management.managementauth.dataControls,
                        message: L10n.management.managementauth.youCanAlwaysSignOutDisableSync
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ManagementProfilePersonalInfoItem: View {
    let title: String
    let message: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        bodyView
    }
}

private enum ManagementSignedInDeviceActionKind: String {
    case signOut
    case forget
}

private struct ManagementSignedInDevicePendingAction: Identifiable {
    let kind: ManagementSignedInDeviceActionKind
    let device: MistiaAccountDevice

    var id: String {
        "\(kind.rawValue)-\(device.id.uuidString)"
    }

    var confirmationTitle: String {
        switch kind {
        case .signOut:
            L10n.management.managementauth.signOutDeviceConfirmationTitle
        case .forget:
            L10n.management.managementauth.forgetDeviceConfirmationTitle
        }
    }

    var message: String {
        switch kind {
        case .signOut:
            if device.isCurrentDevice() {
                return L10n.management.managementauth.signOutThisDeviceConfirmationMessage
            }
            return L10n.management.managementauth.signOutDeviceConfirmationMessage
        case .forget:
            if device.status == .signedIn {
                return L10n.management.managementauth.forgetSignedInDeviceConfirmationMessage
            }
            return L10n.management.managementauth.forgetSignedOutDeviceConfirmationMessage
        }
    }

    var destructiveTitle: String {
        switch kind {
        case .signOut:
            device.isCurrentDevice()
                ? L10n.management.managementauth.signOutThisDevice
                : L10n.management.managementauth.signOutDevice
        case .forget:
            L10n.management.managementauth.forgetDevice
        }
    }
}

private struct ManagementSignedInDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    let accent: Color

    @State private var pendingAction: ManagementSignedInDevicePendingAction?

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.signedInDevices,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            ManagementProfileListCard(tint: cardTint) {
                deviceListContent
            }

            if let errorMessage = sessionStore.accountDevicesErrorMessage {
                ManagementInlineMessageCard(
                    title: L10n.management.managementauth.latestIssue,
                    message: errorMessage,
                    accent: .orange
                )
            }

            ManagementProfileListCard(tint: cardTint) {
                ManagementProfileActionRow(
                    title: L10n.management.managementauth.refreshDevices,
                    icon: "arrow.clockwise.icloud",
                    accent: .sky,
                    subtitle: nil,
                    isDisabled: sessionStore.isLoadingAccountDevices,
                    showsProgress: sessionStore.isLoadingAccountDevices
                ) {
                    Task {
                        await sessionStore.refreshAccountDevices()
                    }
                }
            }
        }
        .task {
            await sessionStore.refreshAccountDevices()
        }
        .alert(
            pendingAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingAction = nil
                    }
                }
            ),
            presenting: pendingAction
        ) { action in
            Button(action.destructiveTitle, role: .destructive) {
                perform(action)
            }
            Button(L10n.common.cancel, role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    @ViewBuilder
    private var deviceListContent: some View {
        if sessionStore.accountDevices.isEmpty {
            if sessionStore.isLoadingAccountDevices {
                ManagementSignedInDevicesLoadingRow(accent: .teal)
            } else {
                ManagementSignedInDevicesEmptyRow(accent: .teal)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessionStore.accountDevices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 {
                        ManagementProfileRowDivider()
                    }

                    ManagementSignedInDeviceRow(
                        device: device,
                        isWorking: sessionStore.isLoadingAccountDevices,
                        onSignOut: {
                            pendingAction = ManagementSignedInDevicePendingAction(kind: .signOut, device: device)
                        },
                        onForget: {
                            pendingAction = ManagementSignedInDevicePendingAction(kind: .forget, device: device)
                        }
                    )
                }
            }
        }
    }

    private func perform(_ action: ManagementSignedInDevicePendingAction) {
        pendingAction = nil
        Task {
            switch action.kind {
            case .signOut:
                await sessionStore.requestAccountDeviceSignOut(action.device)
            case .forget:
                await sessionStore.forgetAccountDevice(action.device)
            }
        }
    }
}

private struct ManagementSignedInDeviceRow: View {
    let device: MistiaAccountDevice
    let isWorking: Bool
    let onSignOut: () -> Void
    let onForget: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ManagementProfileIconTile(icon: "iphone", accent: .teal)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(device.displayName)
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if device.isCurrentDevice() {
                        ManagementSignedInDevicePill(
                            title: L10n.management.managementauth.currentDeviceBadge,
                            accent: .sky
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(metadataText)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(lastSeenText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                ManagementSignedInDevicePill(
                    title: statusTitle,
                    accent: statusAccent
                )
            }

            Spacer(minLength: 10)

            Menu {
                if device.status == .signedIn {
                    Button(role: .destructive, action: onSignOut) {
                        Label(signOutTitle, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Button(role: .destructive, action: onForget) {
                    Label(L10n.management.managementauth.forgetDevice, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .menuOrder(.fixed)
            .disabled(isWorking)
            .opacity(isWorking ? 0.55 : 1)
            .accessibilityLabel(L10n.management.managementauth.deviceActionsAccessibility)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
    }

    private var signOutTitle: String {
        device.isCurrentDevice()
            ? L10n.management.managementauth.signOutThisDevice
            : L10n.management.managementauth.signOutDevice
    }

    private var lastSeenText: String {
        L10n.management.managementauth.deviceLastSeenValue(
            MistiaDateFormatting.relativeTimeLabel(for: device.lastSeenAt)
        )
    }

    private var metadataText: String {
        let model = modelText
        let system = systemText

        if !model.isEmpty, !system.isEmpty {
            return L10n.management.managementauth.deviceMetadataValue(
                String(describing: model),
                String(describing: system)
            )
        }

        if !model.isEmpty {
            return model
        }

        if !system.isEmpty {
            return system
        }

        return L10n.management.managementauth.deviceUnknownMetadata
    }

    private var modelText: String {
        let displayName = trimmed(device.modelDisplayName)
        let identifier = trimmed(device.modelIdentifier)

        guard !displayName.isEmpty else {
            return identifier
        }

        guard !identifier.isEmpty, identifier != displayName else {
            return displayName
        }

        return L10n.management.managementauth.deviceModelValue(
            String(describing: displayName),
            String(describing: identifier)
        )
    }

    private var systemText: String {
        [trimmed(device.systemName), trimmed(device.systemVersion)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var statusTitle: String {
        switch device.status {
        case .signedIn:
            L10n.management.managementauth.deviceStatusSignedIn
        case .signedOut:
            L10n.management.managementauth.deviceStatusSignedOut
        case .forgotten:
            L10n.management.managementauth.deviceStatusForgotten
        case .unknown:
            L10n.management.managementauth.deviceStatusUnknown
        }
    }

    private var statusAccent: MistiaAccent {
        switch device.status {
        case .signedIn:
            .mint
        case .signedOut:
            .slate
        case .forgotten:
            .amber
        case .unknown:
            .slate
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ManagementSignedInDevicePill: View {
    let title: String
    let accent: MistiaAccent

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(accent.color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent.color.opacity(0.12), in: Capsule())
    }
}

private struct ManagementSignedInDevicesEmptyRow: View {
    let accent: MistiaAccent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ManagementProfileIconTile(icon: "iphone.slash", accent: accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.management.managementauth.signedInDevicesEmptyTitle)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(L10n.management.managementauth.signedInDevicesEmptyMessage)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
    }
}

private struct ManagementSignedInDevicesLoadingRow: View {
    let accent: MistiaAccent

    var body: some View {
        HStack(spacing: 12) {
            ManagementProfileIconTile(icon: "iphone", accent: accent)

            Text(L10n.management.managementauth.signedInDevicesLoading)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            ProgressView()
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
    }
}

private struct ManagementProfilePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let systemImage: String
    let accent: Color
    let message: String

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: title,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            ManagementProfilePlaceholderCard(
                title: title,
                message: message,
                systemImage: systemImage,
                accent: accent
            )
        }
    }
}

private struct ManagementProfilePlaceholderCard: View {
    let title: String
    let message: String
    let systemImage: String
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : accent.opacity(0.12)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.14))

                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 56, height: 56)

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ManagementSyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Query private var storedConflicts: [SyncConflict]

    @State private var destination: ManagementSyncSettingsDestination?
    @State private var showsNoConflictsAlert = false

    let accent: Color

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var lastSyncValue: String {
        guard let lastSyncAt = sessionStore.lastSyncAt else {
            return ""
        }

        return L10n.management.managementauth.syncedAtValue(String(describing: MistiaDateFormatting.dateTimeString(for: lastSyncAt)))
    }

    private var syncExplanatoryText: String {
        L10n.management.managementauth.mistiaIsSyncingYourDataWithThe
    }

    private var autoSyncValue: String {
        if sessionStore.isAutoSyncEnabled {
            return L10n.common.on
        } else {
            return L10n.common.off
        }
    }

    private func timeRemainingLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return L10n.management.managementauth.aboutValueSecondsLeft(String(describing: Int(seconds)))
        } else {
            let minutes = Int(seconds / 60)
            return L10n.management.managementauth.aboutValueMinutesLeft(String(describing: minutes))
        }
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.management.managementauth.syncSettings,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            ManagementProfileListCard(tint: cardTint) {
                VStack(spacing: 0) {
                    ManagementProfileNavigationRow(
                        title: L10n.management.managementauth.manageSyncedData,
                        icon: "externaldrive.badge.person.crop",
                        accent: .purple,
                        subtitle: nil,
                        badge: {
                            storedConflicts.isEmpty ? nil : "\(storedConflicts.count)"
                        }(),
                        badgeAccent: .purple
                    ) {
                        if !storedConflicts.isEmpty {
                            destination = .dataManagement
                        } else {
                            showsNoConflictsAlert = true
                        }
                    }

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: L10n.management.managementauth.autoSync,
                        icon: "arrow.triangle.2.circlepath.icloud",
                        accent: .mint,
                        subtitle: sessionStore.canPerformRemoteActions ? nil : sessionStore.remoteUnavailableReason,
                        value: autoSyncValue
                    ) {
                        destination = .autoSync
                    }
                }
            }

            if !sessionStore.isCheckingData, let progress = sessionStore.syncProgress {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        Image("AppIconAsset")
                            .resizable()
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(spacing: 8) {
                            ProgressView(value: progress, total: 1.0)
                                .tint(accent)
                                .scaleEffect(x: 1, y: 0.8)
                                .clipShape(Capsule())

                            HStack {
                                Text(verbatim: "\(Int(progress * 100))%")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(accent)

                                Spacer()

                                if let remaining = sessionStore.syncTimeRemaining, remaining > 0 {
                                    Text(timeRemainingLabel(remaining))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Text(syncExplanatoryText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ManagementProfilePrimaryActionButton(
                        title: L10n.management.managementauth.syncNow,
                        accent: accent,
                        isDisabled: !sessionStore.canPerformRemoteActions || sessionStore.isManualSyncInProgress,
                        showsProgress: sessionStore.isManualSyncInProgress && sessionStore.canPerformRemoteActions
                    ) {
                        Task {
                            await sessionStore.syncNow(isManual: true)
                        }
                    }

                    if !lastSyncValue.isEmpty, !sessionStore.isManualSyncInProgress {
                        Text(lastSyncValue)
                            .descriptionTextStyle()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .dataManagement:
                ManagementDataConflictsView(accent: accent)
            case .autoSync:
                ManagementAutoSyncDetailView(accent: accent)
            }
        }
        .alert(
            L10n.management.managementauth.dataIsOptimized,
            isPresented: $showsNoConflictsAlert
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text(
                L10n.management.managementauth.yourDataIsCurrentlyFullySyncedNo
            )
        }
    }
}

private struct ManagementInlineMessageCard: View {
    let title: String
    let message: String
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MistiaGlassCard(cornerRadius: 20, tint: colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : accent.opacity(0.14)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ManagementAuthBannerCard: View {
    let banner: SessionAuthBanner

    var body: some View {
        ManagementInlineMessageCard(
            title: banner.title,
            message: banner.message,
            accent: banner.style.accent
        )
    }
}

private struct ManagementAuthFieldContainer<Content: View>: View {
    let errorMessage: String?
    let content: Content

    init(
        errorMessage: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.errorMessage = errorMessage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if errorMessage != nil {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.red.opacity(0.8), lineWidth: 1)
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct ManagementPasswordInputField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool
    let errorMessage: String?
    let textContentType: UITextContentType?
    let submitLabel: SubmitLabel
    let focusField: ManagementAuthInput
    let focusedField: FocusState<ManagementAuthInput?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        ManagementAuthFieldContainer(errorMessage: errorMessage) {
            HStack(spacing: 12) {
                Group {
                    if isVisible {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .privacySensitive()
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused(focusedField, equals: focusField)
                .onSubmit(onSubmit)

                Button {
                    isVisible.toggle()
                    Task { @MainActor in
                        focusedField.wrappedValue = focusField
                    }
                } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isVisible
                        ? L10n.management.managementauth.hidePassword
                        : L10n.management.managementauth.showPassword
                )
            }
        }
    }
}

private struct ManagementAuthDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 1)

            Text(title)
                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 1)
        }
    }
}

private struct ManagementGoogleActionButton: View {
    let title: String
    let isWorking: Bool
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isWorking {
                    ProgressView()
                        .tint(colorScheme == .dark ? .black : .white)
                } else {
                    ManagementGoogleMark()
                }

                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(colorScheme == .dark ? .white : accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ManagementGoogleMark: View {
    var body: some View {
        Text(verbatim: "G")
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.91, green: 0.29, blue: 0.24),
                        Color(red: 0.96, green: 0.74, blue: 0.18),
                        Color(red: 0.20, green: 0.55, blue: 0.98),
                        Color(red: 0.20, green: 0.71, blue: 0.37)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct ManagementAuthEmailChip: View {
    let email: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)

            Text(email)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.07), in: Capsule())
    }
}

private struct ManagementPasswordStrengthMeter: View {
    let assessment: PasswordStrengthAssessment

    private let palette: [Color] = [
        Color(red: 0.91, green: 0.29, blue: 0.32),
        Color(red: 0.96, green: 0.55, blue: 0.24),
        Color(red: 0.92, green: 0.75, blue: 0.24),
        Color(red: 0.20, green: 0.77, blue: 0.65),
        Color(red: 0.25, green: 0.76, blue: 0.34)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index < assessment.filledSegments ? palette[index] : .white.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                }
            }

            if let level = assessment.level {
                Text(level.title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(level.tint)
            }
        }
    }
}

private struct ManagementPasswordRequirementChecklist: View {
    let assessment: PasswordStrengthAssessment
    let showsNeutralState: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ManagementPasswordRequirementRow(
                title: L10n.management.managementauth.atLeastCharacters,
                isSatisfied: assessment.hasMinimumLength,
                showsNeutralState: showsNeutralState
            )

            ManagementPasswordRequirementRow(
                title: L10n.management.managementauth.atLeastUppercaseLetter,
                isSatisfied: assessment.hasUppercase,
                showsNeutralState: showsNeutralState
            )

            ManagementPasswordRequirementRow(
                title: L10n.management.managementauth.atLeastLowercaseLetter,
                isSatisfied: assessment.hasLowercase,
                showsNeutralState: showsNeutralState
            )
        }
    }
}

private struct ManagementPasswordRequirementRow: View {
    let title: String
    let isSatisfied: Bool
    let showsNeutralState: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
        }
    }

    private var iconName: String {
        if showsNeutralState {
            return "circle.dashed"
        }
        return isSatisfied ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var iconColor: Color {
        if showsNeutralState {
            return .secondary
        }
        return isSatisfied ? MistiaAccent.income.color : Color.red.opacity(0.92)
    }

    private var textColor: Color {
        if showsNeutralState {
            return .secondary
        }
        return isSatisfied ? MistiaAccent.income.color : Color.red.opacity(0.92)
    }
}

private struct PasswordStrengthAssessment {
    let hasMinimumLength: Bool
    let hasUppercase: Bool
    let hasLowercase: Bool
    let hasDigit: Bool
    let hasSymbol: Bool
    let level: PasswordStrengthLevel?

    init(password: String) {
        let scalars = password.unicodeScalars
        hasMinimumLength = password.count >= 8
        hasUppercase = scalars.contains(where: CharacterSet.uppercaseLetters.contains)
        hasLowercase = scalars.contains(where: CharacterSet.lowercaseLetters.contains)
        hasDigit = scalars.contains(where: CharacterSet.decimalDigits.contains)
        hasSymbol = scalars.contains(where: { CharacterSet.alphanumerics.inverted.contains($0) })

        guard !password.isEmpty else {
            level = nil
            return
        }

        if password.count < 4 {
            level = .veryWeak
        } else if password.count < 8 {
            level = .weak
        } else if !hasUppercase || !hasLowercase {
            level = .weak
        } else if hasDigit && hasSymbol {
            level = .veryStrong
        } else if hasDigit || hasSymbol {
            level = .strong
        } else {
            level = .normal
        }
    }

    var filledSegments: Int {
        level?.filledSegments ?? 0
    }
}

private enum PasswordStrengthLevel {
    case veryWeak
    case weak
    case normal
    case strong
    case veryStrong

    var filledSegments: Int {
        switch self {
        case .veryWeak:
            return 1
        case .weak:
            return 2
        case .normal:
            return 3
        case .strong:
            return 4
        case .veryStrong:
            return 5
        }
    }

    var tint: Color {
        switch self {
        case .veryWeak:
            return Color(red: 0.91, green: 0.29, blue: 0.32)
        case .weak:
            return Color(red: 0.96, green: 0.55, blue: 0.24)
        case .normal:
            return Color(red: 0.92, green: 0.75, blue: 0.24)
        case .strong:
            return Color(red: 0.20, green: 0.77, blue: 0.65)
        case .veryStrong:
            return MistiaAccent.income.color
        }
    }

    var title: String {
        switch self {
        case .veryWeak:
            return L10n.management.managementauth.veryWeak
        case .weak:
            return L10n.management.managementauth.weak
        case .normal:
            return L10n.management.managementauth.normal
        case .strong:
            return L10n.management.managementauth.strong
        case .veryStrong:
            return L10n.management.managementauth.veryStrong
        }
    }
}

private extension SessionAuthBannerStyle {
    var accent: Color {
        switch self {
        case .info:
            return Color(red: 0.30, green: 0.59, blue: 0.95)
        case .success:
            return MistiaAccent.income.color
        case .error:
            return Color(red: 0.91, green: 0.29, blue: 0.32)
        }
    }
}

private struct ManagementBackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ManagementBackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    var isModalPresentation: Bool = false

    @State private var restoreMode: MistiaBackupRestoreMode = .merge
    @State private var isImporting = false
    @State private var isRestoring = false
    @State private var shareItem: TransactionShareItem?
    @State private var latestSummary: MistiaBackupValidationSummary?
    @State private var latestRestoreResult: MistiaBackupRestoreResult?
    @State private var alert: ManagementBackupAlert?

    private var accent: Color {
        MistiaAccent.income.color
    }

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var isBusy: Bool {
        isRestoring || sessionStore.isAnySyncInProgress
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: isModalPresentation ? .modal : .standard,
            title: L10n.management.managementauth.backupRestore,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: isModalPresentation ? "xmark" : "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18,
            contentBottomPadding: isModalPresentation ? 40 : 150
        ) {
            ManagementInlineMessageCard(
                title: L10n.management.managementauth.emergencySnapshot,
                message: L10n.management.managementauth.createAMistiabackupFileToCaptureThe,
                accent: .mint
            )

            ManagementProfileListCard(tint: cardTint) {
                VStack(spacing: 0) {
                    backupActionRow(
                        title: L10n.management.managementauth.createSnapshot,
                        subtitle: L10n.management.managementauth.exportTheCurrentLocalDataIntoA,
                        systemImage: "square.and.arrow.up.fill",
                        tint: .blue,
                        isDisabled: isBusy,
                        action: exportSnapshot
                    )

                    ManagementProfileRowDivider()

                    backupActionRow(
                        title: L10n.management.managementauth.importSnapshot,
                        subtitle: restoreMode == .merge
                            ? L10n.management.managementauth.importTheFileAndLetSnapshotValues
                            : L10n.management.managementauth.importTheFileAndReplaceTheCurrent,
                        systemImage: "square.and.arrow.down.fill",
                        tint: .mint,
                        isDisabled: isBusy,
                        action: { isImporting = true }
                    )
                }
            }

            ManagementProfileListCard(tint: cardTint) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.management.managementauth.restoreMode)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Picker(String(), selection: $restoreMode) {
                        ForEach(MistiaBackupRestoreMode.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(restoreMode.localizedDescription)
                        .descriptionTextStyle()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
            }

            if let latestSummary {
                ManagementProfileListCard(tint: cardTint) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.management.managementauth.latestSnapshotSummary)
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            L10n.management.managementauth.backupFormatVValueAppValueValue(String(describing: latestSummary.manifest.backupFormatVersion), String(describing: latestSummary.manifest.appVersion), String(describing: latestSummary.manifest.appBuild), String(describing: latestSummary.manifest.localSchemaVersion))
                        )
                        .descriptionTextStyle()

                        Text(latestSummary.localizedBreakdown)
                            .descriptionTextStyle()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                }
            }

            if sessionStore.isManualSyncRequiredAfterRestore {
                ManagementInlineMessageCard(
                    title: L10n.management.managementauth.waitingForYourReviewBeforeSync,
                    message: L10n.management.managementauth.autoSyncIsPausedAfterTheRestore,
                    accent: .orange
                )
            }

            if let latestRestoreResult, let safetySnapshotURL = latestRestoreResult.safetySnapshotURL {
                ManagementProfileListCard(tint: cardTint) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.management.managementauth.internalSafetySnapshot)
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            L10n.management.managementauth.mistiaCreatedASafetySnapshotBeforeReplacing
                        )
                        .descriptionTextStyle()

                        Button {
                            shareItem = TransactionShareItem(url: safetySnapshotURL)
                        } label: {
                            Label(
                                L10n.management.managementauth.shareSafetySnapshot,
                                systemImage: "square.and.arrow.up"
                            )
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                }
            }
        }
        .sheet(item: $shareItem) { item in
            TransactionShareSheet(url: item.url)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.mistiaBackup],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text((alert.title)),
                message: Text((alert.message)),
                dismissButton: .default(Text(L10n.common.ok))
            )
        }
    }

    private func backupActionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if isDisabled {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func exportSnapshot() {
        do {
            let exportResult = try sessionStore.exportBackup(
                appVersion: currentAppVersion(),
                appBuild: currentAppBuild()
            )
            let url = try writeShareFile(
                named: exportResult.fileName,
                data: exportResult.data
            )
            latestSummary = exportResult.summary
            latestRestoreResult = nil
            shareItem = TransactionShareItem(url: url)
        } catch {
            alert = ManagementBackupAlert(
                title: L10n.management.managementauth.couldnTCreateSnapshot,
                message: error.localizedDescription
            )
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                alert = ManagementBackupAlert(
                    title: L10n.management.managementauth.noFileSelected,
                    message: L10n.management.managementauth.chooseAMistiabackupFileToContinue
                )
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            Task { @MainActor in
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                    isRestoring = false
                }

                isRestoring = true

                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: url)
                    }.value
                    let summary = try MistiaBackupStore.validateBackup(data)
                    latestSummary = summary
                    latestRestoreResult = try await sessionStore.restoreBackup(
                        data: data,
                        mode: restoreMode
                    )

                    alert = ManagementBackupAlert(
                        title: L10n.management.managementauth.snapshotRestored,
                        message: restoreMode == .merge
                            ? L10n.management.managementauth.mistiaMergedTheSnapshotIntoLocalData
                            : L10n.management.managementauth.mistiaReplacedLocalDataWithTheSelected
                    )
                } catch {
                    alert = ManagementBackupAlert(
                        title: L10n.management.managementauth.couldnTImportSnapshot,
                        message: error.localizedDescription
                    )
                }
            }
        case .failure(let error):
            alert = ManagementBackupAlert(
                title: L10n.management.managementauth.couldnTOpenFile,
                message: error.localizedDescription
            )
        }
    }

    private func writeShareFile(
        named fileName: String,
        data: Data
    ) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mistia-backup-share", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileURL = directoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func currentAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func currentAppBuild() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}

private extension MistiaBackupRestoreMode {
    var localizedTitle: String {
        switch self {
        case .merge:
            L10n.management.managementauth.merge
        case .replaceLocal:
            L10n.management.managementauth.replaceLocal
        }
    }

    var localizedDescription: String {
        switch self {
        case .merge:
            L10n.management.managementauth.keepUnrelatedLocalRecordsButIfThe
        case .replaceLocal:
            L10n.management.managementauth.mistiaFirstCreatesAnInternalSafetySnapshot
        }
    }
}

private extension MistiaBackupValidationSummary {
    var localizedBreakdown: String {
        L10n.management.managementauth.valueDataRecordsTotalWalletsValueCards(String(describing: activeRecordCount), String(describing: walletCount), String(describing: creditCardProfileCount), String(describing: categoryCount), String(describing: transactionCount), String(describing: budgetPlanCount), String(describing: savingsGoalCount), String(describing: recurringBillPlanCount), String(describing: installmentPlanCount), String(describing: dueOccurrenceCount), String(describing: userProfileCount), String(describing: ownershipScopeCount), String(describing: transactionAuditCount))
    }
}

private extension UTType {
    static let mistiaBackup = UTType(filenameExtension: "mistiabackup") ?? UTType(exportedAs: "app.mistia.backup", conformingTo: .data)
}
