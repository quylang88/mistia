import SwiftData
import SwiftUI
import UIKit

private enum ManagementAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn:
            mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン")
        case .signUp:
            mistiaLocalized(vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成")
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

private enum ManagementProfileDestructiveAction: String, Identifiable {
    case signOut
    case deleteAccount

    var id: String { rawValue }
}

private enum ManagementSyncSettingsDestination: String, Identifiable {
    case dataManagement

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
    @State private var destructiveAction: ManagementProfileDestructiveAction?
    @FocusState private var focusedField: ManagementAuthInput?
    
    @Environment(\.colorScheme) private var colorScheme

    // Tone màu tím đặc trưng, sáng hơn trong Dark Mode
    private var accent: Color {
        colorScheme == .dark 
            ? MistiaAccent.lightPurple.color 
            : MistiaAccent.purple.color
    }

    private let secondaryBackground = Color(UIColor.secondarySystemBackground)

    private var activeConflicts: [SyncConflict] {
        storedConflicts
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: sessionStore.isSignedIn
                ? mistiaLocalized(vi: "Hồ sơ", en: "Profile", ja: "プロフィール")
                : (isEmailAuthExpanded ? authScreenTitle : mistiaLocalized(vi: "Hồ sơ", en: "Profile", ja: "プロフィール")),
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
                ManagementProfilePlaceholderView(
                    title: mistiaLocalized(vi: "Sao lưu / Khôi phục", en: "Backup / Restore", ja: "バックアップ / 復元"),
                    systemImage: "externaldrive.fill.badge.icloud",
                    accent: accent,
                    message: mistiaLocalized(
                        vi: "UI entry cho sao lưu và khôi phục đã sẵn sàng. Logic chi tiết sẽ được nối ở bước sau.",
                        en: "The UI entry for backup and restore is ready. Detailed logic can be connected later.",
                        ja: "バックアップと復元の UI 導線は準備できています。詳細ロジックは次の段階で接続できます。"
                    )
                )
            case .signedInDevices:
                ManagementProfilePlaceholderView(
                    title: mistiaLocalized(vi: "Thiết bị đã đăng nhập", en: "Signed-in devices", ja: "サインイン済みデバイス"),
                    systemImage: "desktopcomputer",
                    accent: accent,
                    message: mistiaLocalized(
                        vi: "Màn này sẽ hiển thị các thiết bị đã đăng nhập vào tài khoản Mistia của bạn.",
                        en: "This screen will list devices currently signed in to your Mistia account.",
                        ja: "この画面では Mistia アカウントにログインしている端末を表示します。"
                    )
                )
            case .editProfile:
                if let summary = sessionStore.summary {
                    ManagementEditProfileView(summary: summary, accent: accent)
                } else {
                    ManagementProfilePlaceholderView(
                        title: mistiaLocalized(vi: "Sửa hồ sơ", en: "Edit profile", ja: "プロフィールを編集"),
                        systemImage: "square.and.pencil",
                        accent: accent,
                        message: mistiaLocalized(
                            vi: "Hồ sơ hiện chưa sẵn sàng để chỉnh sửa vì phiên đăng nhập chưa được khôi phục.",
                            en: "The profile isn't ready to edit yet because the signed-in session hasn't been restored.",
                            ja: "ログイン状態の復元がまだ完了していないため、プロフィールを編集できません。"
                        )
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
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            destructiveActionConfirmationTitle,
            isPresented: Binding(
                get: { destructiveAction != nil },
                set: { isPresented in
                    if !isPresented {
                        destructiveAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            switch destructiveAction {
            case .signOut:
                Button(
                    mistiaLocalized(vi: "Đăng xuất", en: "Sign out", ja: "ログアウト"),
                    role: .destructive
                ) {
                    destructiveAction = nil
                    Task {
                        await sessionStore.signOut()
                    }
                }
            case .deleteAccount:
                Button(
                    mistiaLocalized(vi: "Xóa tài khoản", en: "Delete account", ja: "アカウントを削除"),
                    role: .destructive
                ) {
                    destructiveAction = nil
                    Task {
                        await sessionStore.deleteAccountKeepingLocalData()
                    }
                }
            case .none:
                EmptyView()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {
                destructiveAction = nil
            }
        } message: {
            Text(destructiveActionConfirmationMessage)
        }
    }

    private var configurationCard: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : accent.opacity(0.14)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ManagementStatusBadge(
                    title: mistiaLocalized(vi: "Chưa cấu hình", en: "Not configured", ja: "未設定"),
                    systemImage: "wrench.and.screwdriver.fill",
                    accent: accent
                )

                Text(
                    mistiaLocalized(
                        vi: "Mistia đã có sẵn flow đăng nhập và đồng bộ, nhưng bạn cần điền URL cùng public key của dịch vụ cloud trước khi dùng.",
                        en: "Mistia already has the sign-in and sync flow, but you need to fill in the cloud service URL and public key first.",
                        ja: "Mistia にはログインと同期の流れがありますが、使う前にクラウドサービスの URL と公開キーを設定する必要があります。"
                    )
                )
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

                Text("Mistia/MistiaSyncConfig.plist")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SUPABASE_URL")
                    Text("SUPABASE_ANON_KEY")
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
                        title: mistiaLocalized(vi: "Đồng bộ dữ liệu", en: "Sync settings", ja: "同期設定"),
                        icon: "arrow.triangle.2.circlepath.icloud",
                        accent: .sky,
                        subtitle: nil,
                        value: syncSettingsValue,
                        badge: dataManagementBadgeText
                    ) {
                        destination = .syncSettings
                    }

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: mistiaLocalized(vi: "Sao lưu / Khôi phục", en: "Backup / Restore", ja: "バックアップ / 復元"),
                        icon: "externaldrive.fill.badge.icloud",
                        accent: .mint,
                        subtitle: nil
                    ) {
                        destination = .backupRestore
                    }

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: mistiaLocalized(vi: "Thiết bị đã đăng nhập", en: "Signed-in devices", ja: "サインイン済みデバイス"),
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
                    title: mistiaLocalized(vi: "Lỗi gần nhất", en: "Latest issue", ja: "直近の問題"),
                    message: lastErrorMessage,
                    accent: .orange
                )
            }

            ManagementProfileListCard(tint: secondaryBackground) {
                ManagementProfileNavigationRow(
                    title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
                    icon: "person.3.fill",
                    accent: .purple,
                    subtitle: nil,
                    value: familyContextStore.family?.name ?? mistiaLocalized(vi: "Chưa có", en: "None", ja: "未設定")
                ) {
                    destination = .family
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: mistiaLocalized(vi: "Đăng xuất", en: "Sign out", ja: "ログアウト"),
                isDisabled: sessionStore.isWorking
            ) {
                destructiveAction = .signOut
            }

            ManagementProfileCenteredDestructiveButton(
                title: mistiaLocalized(vi: "Xóa tài khoản", en: "Delete account", ja: "アカウントを削除"),
                isDisabled: sessionStore.isWorking
            ) {
                destructiveAction = .deleteAccount
            }
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
                .accessibilityLabel(mistiaLocalized(vi: "Sửa hồ sơ", en: "Edit profile", ja: "プロフィールを編集"))
                .offset(x: 2, y: 2)
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
                accent: sessionStore.lastSyncAt == nil ? .slate : .mint
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var lastSyncBadgeTitle: String {
        guard let lastSyncAt = sessionStore.lastSyncAt else {
            return mistiaLocalized(
                vi: "Chưa đồng bộ",
                en: "Sync is off",
                ja: "同期はオフです"
            )
        }

        return mistiaLocalized(
            vi: "Đã đồng bộ lúc \(MistiaDateFormatting.dateTimeString(for: lastSyncAt))",
            en: "Synced at \(MistiaDateFormatting.dateTimeString(for: lastSyncAt, language: .english))",
            ja: "\(MistiaDateFormatting.dateTimeString(for: lastSyncAt, language: .japanese)) に同期済み"
        )
    }

    private var dataManagementBadgeText: String? {
        let issueCount = activeConflicts.count + sessionStore.possibleDuplicateCount
        guard issueCount > 0 else { return nil }
        return "\(issueCount)"
    }

    private var syncSettingsValue: String {
        if sessionStore.isAutoSyncEnabled {
            return mistiaLocalized(vi: "Tự động", en: "Auto", ja: "自動")
        }

        if sessionStore.canManageSync {
            return mistiaLocalized(vi: "Thủ công", en: "Manual", ja: "手動")
        }

        return mistiaLocalized(vi: "Tắt", en: "Off", ja: "オフ")
    }

    private var destructiveActionConfirmationTitle: String {
        switch destructiveAction {
        case .signOut:
            return mistiaLocalized(
                vi: "Đăng xuất khỏi thiết bị này?",
                en: "Sign out of this device?",
                ja: "この端末からログアウトしますか？"
            )
        case .deleteAccount:
            return mistiaLocalized(
                vi: "Xóa tài khoản này?",
                en: "Delete this account?",
                ja: "このアカウントを削除しますか？"
            )
        case .none:
            return ""
        }
    }

    private var destructiveActionConfirmationMessage: String {
        switch destructiveAction {
        case .signOut:
            return mistiaLocalized(
                vi: "Bạn sẽ bị đăng xuất khỏi Mistia trên thiết bị này. Dữ liệu local hiện có vẫn được giữ lại.",
                en: "You will be signed out of Mistia on this device. Existing local data will stay on the device.",
                ja: "この端末で Mistia からログアウトします。既存のローカルデータは保持されます。"
            )
        case .deleteAccount:
            return mistiaLocalized(
                vi: "Tài khoản và dữ liệu đồng bộ trên cloud sẽ bị xóa vĩnh viễn. Dữ liệu local trên máy này vẫn được giữ lại.",
                en: "Your cloud account and synced server data will be permanently deleted. Local data on this device will remain.",
                ja: "クラウドアカウントと同期済みサーバーデータは完全に削除されます。この端末のローカルデータは保持されます。"
            )
        case .none:
            return ""
        }
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
                    title: mistiaLocalized(vi: "Chưa thể tiếp tục", en: "Can't continue yet", ja: "まだ続行できません"),
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
            
            Text(mistiaLocalized(vi: "Chào mừng đến với Mistia", en: "Welcome to Mistia", ja: "Mistiaへようこそ"))
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
                title: mistiaLocalized(
                    vi: "Tiếp tục với Google",
                    en: "Continue with Google",
                    ja: "Google で続行"
                ),
                isWorking: sessionStore.isWorking && sessionStore.activeAuthAction == .google,
                accent: accent
            ) {
                Task {
                    await sessionStore.signInWithGoogle()
                }
            }
            .disabled(sessionStore.isWorking)

            ManagementAuthDivider(
                title: mistiaLocalized(vi: "hoặc", en: "or", ja: "または")
            )

            Button {
                withAnimation(.snappy) {
                    isEmailAuthExpanded = true
                    transition(to: .signIn)
                }
            } label: {
                Text(mistiaLocalized(vi: "Tiếp tục bằng Email", en: "Continue with Email", ja: "メールで続行"))
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(UIColor.secondarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            
            Text(
                mistiaLocalized(
                    vi: "Bằng việc tiếp tục, bạn đồng ý với Điều khoản Dịch vụ và Chính sách Bảo mật của chúng tôi.",
                    en: "By continuing, you agree to our Terms of Service and Privacy Policy.",
                    ja: "続行することで、利用規約とプライバシーポリシーに同意したことになります。"
                )
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
            return mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン")
        case .signUp:
            return mistiaLocalized(vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成")
        case .forgotPassword:
            return mistiaLocalized(vi: "Quên mật khẩu", en: "Forgot password", ja: "パスワードをお忘れですか")
        case .verifyEmailPending:
            return mistiaLocalized(vi: "Xác nhận email", en: "Confirm your email", ja: "メール確認")
        }
    }

    private var authIntroCopy: String {
        switch sessionStore.authPhase {
        case .signIn, .signUp:
            return mistiaLocalized(
                vi: "Dùng cùng một tài khoản Mistia để đồng bộ ví, danh mục, giao dịch và các kế hoạch sang thiết bị khác.",
                en: "Use the same Mistia account to sync wallets, categories, transactions, and plans across devices.",
                ja: "同じ Mistia アカウントでウォレット、カテゴリ、取引、計画を別の端末へ同期できます。"
            )
        case .forgotPassword:
            return mistiaLocalized(
                vi: "Nhập email bạn dùng với Mistia. Nếu hợp lệ, hệ thống sẽ gửi email đặt lại mật khẩu.",
                en: "Enter the email you use with Mistia. If it's valid, the system will send a reset email.",
                ja: "Mistia で使っているメールアドレスを入力してください。有効であればシステムが再設定メールを送信します。"
            )
        case .verifyEmailPending:
            return mistiaLocalized(
                vi: "Tài khoản của bạn đang chờ xác nhận email trước khi có thể đăng nhập và bật đồng bộ.",
                en: "Your account is waiting for email confirmation before it can sign in and start syncing.",
                ja: "このアカウントはメール確認が完了するまでログインと同期を開始できません。"
            )
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
                        mistiaLocalized(vi: "Tên hiển thị", en: "Display name", ja: "表示名"),
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
                    mistiaLocalized(vi: "Email", en: "Email", ja: "メールアドレス"),
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
                placeholder: mistiaLocalized(vi: "Mật khẩu", en: "Password", ja: "パスワード"),
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
                    placeholder: mistiaLocalized(vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを再入力"),
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
                            ? mistiaLocalized(vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成")
                            : mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン")
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
                    Text(mistiaLocalized(vi: "Quên mật khẩu?", en: "Forgot password?", ja: "パスワードをお忘れですか？"))
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
                            Text(mistiaLocalized(vi: "Chưa có tài khoản?", en: "Don't have an account?", ja: "アカウントがありませんか？"))
                                .foregroundStyle(.secondary)
                            Text(mistiaLocalized(vi: "Đăng ký ngay", en: "Sign up now", ja: "今すぐ登録"))
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
                            Text(mistiaLocalized(vi: "Đã có tài khoản?", en: "Already have an account?", ja: "すでにアカウントをお持ちですか？"))
                                .foregroundStyle(.secondary)
                            Text(mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン"))
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
                    mistiaLocalized(vi: "Email", en: "Email", ja: "メールアドレス"),
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
                        mistiaLocalized(vi: "Gửi email đặt lại mật khẩu", en: "Send reset email", ja: "再設定メールを送信")
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
                Text(mistiaLocalized(vi: "Quay lại đăng nhập", en: "Back to sign in", ja: "ログインへ戻る"))
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

                    Text(mistiaLocalized(vi: "Gửi lại email xác nhận", en: "Resend confirmation email", ja: "確認メールを再送"))
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
                Text(mistiaLocalized(vi: "Quay lại đăng nhập", en: "Back to sign in", ja: "ログインへ戻る"))
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
                errors[.email] = mistiaLocalized(
                    vi: "Email chưa đúng định dạng.",
                    en: "The email format doesn't look right.",
                    ja: "メールアドレスの形式が正しくありません。"
                )
            }

            if password.isEmpty {
                errors[.password] = mistiaLocalized(
                    vi: "Nhập mật khẩu để tiếp tục.",
                    en: "Enter your password to continue.",
                    ja: "続行するにはパスワードを入力してください。"
                )
            }
        case .signUp:
            if trimmedDisplayName.isEmpty {
                errors[.displayName] = mistiaLocalized(
                    vi: "Tên hiển thị không được để trống.",
                    en: "Display name can't be empty.",
                    ja: "表示名は空にできません。"
                )
            }

            if !isValidEmail(trimmedEmail) {
                errors[.email] = mistiaLocalized(
                    vi: "Email chưa đúng định dạng.",
                    en: "The email format doesn't look right.",
                    ja: "メールアドレスの形式が正しくありません。"
                )
            }

            if !passwordAssessment.hasMinimumLength {
                errors[.password] = mistiaLocalized(
                    vi: "Mật khẩu cần ít nhất 8 ký tự.",
                    en: "Password must be at least 8 characters.",
                    ja: "パスワードは 8 文字以上である必要があります。"
                )
            } else if !passwordAssessment.hasUppercase {
                errors[.password] = mistiaLocalized(
                    vi: "Mật khẩu cần ít nhất 1 chữ viết hoa.",
                    en: "Password needs at least 1 uppercase letter.",
                    ja: "パスワードには大文字を 1 文字以上含めてください。"
                )
            } else if !passwordAssessment.hasLowercase {
                errors[.password] = mistiaLocalized(
                    vi: "Mật khẩu cần ít nhất 1 chữ viết thường.",
                    en: "Password needs at least 1 lowercase letter.",
                    ja: "パスワードには小文字を 1 文字以上含めてください。"
                )
            }

            if confirmPassword.isEmpty {
                errors[.confirmPassword] = mistiaLocalized(
                    vi: "Nhập lại mật khẩu để xác nhận.",
                    en: "Re-enter your password to confirm it.",
                    ja: "確認のためパスワードを再入力してください。"
                )
            } else if confirmPassword != password {
                errors[.confirmPassword] = mistiaLocalized(
                    vi: "Mật khẩu nhập lại chưa khớp.",
                    en: "The confirmation password doesn't match yet.",
                    ja: "確認用パスワードがまだ一致していません。"
                )
            }
        case .forgotPassword:
            if !isValidEmail(trimmedEmail) {
                errors[.email] = mistiaLocalized(
                    vi: "Email chưa đúng định dạng.",
                    en: "The email format doesn't look right.",
                    ja: "メールアドレスの形式が正しくありません。"
                )
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

            Toggle("", isOn: isOn)
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
                            .background(accent.color, in: Capsule())
                    }

                    if let value {
                        Text(value)
                            .font(.system(size: 14.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: accent.color))
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
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemBackground)
            : Color(UIColor.systemBackground)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(MistiaAccent.expense.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
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
        colorScheme == .dark
            ? .white
            : Color(UIColor.systemBackground)
    }

    private var foregroundColor: Color {
        if colorScheme == .dark {
            return MistiaAccent.lightPurple.color
        }
        return accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showsProgress {
                    ProgressView()
                        .tint(foregroundColor)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(foregroundColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
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
        VStack(alignment: .leading, spacing: 18) {
            Text(
                mistiaLocalized(
                    vi: "Chọn cách đồng bộ lần đầu",
                    en: "Choose the first sync strategy",
                    ja: "初回同期の方法を選択"
                )
            )
            .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(
                preview.remoteActiveCount == 0
                ? mistiaLocalized(
                    vi: "Cloud hiện chưa có dữ liệu nào (ngoại trừ hồ sơ của bạn). Máy này đang có \(preview.localActiveCount) bản ghi. Hãy chọn cách bạn muốn bắt đầu.",
                    en: "The cloud has no data yet (except your profile). This device has \(preview.localActiveCount) records. Choose how you want to start.",
                    ja: "クラウドにはまだデータがありません（プロフィールを除く）。この端末には \(preview.localActiveCount) 件のレコードがあります。開始方法を選択してください。"
                )
                : mistiaLocalized(
                    vi: "Máy này đang có \(preview.localActiveCount) bản ghi và cloud đang có \(preview.remoteActiveCount) bản ghi. Mistia sẽ ưu tiên an toàn dữ liệu trước.",
                    en: "This device has \(preview.localActiveCount) records and the cloud has \(preview.remoteActiveCount) records. Mistia will prioritize data safety first.",
                    ja: "この端末には \(preview.localActiveCount) 件、クラウドには \(preview.remoteActiveCount) 件のレコードがあります。Mistia はまずデータの安全性を優先します。"
                )
            )
            .font(.system(size: 14.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ManagementInitialSyncChoiceButton(
                    title: mistiaLocalized(vi: "Gộp an toàn", en: "Merge safely", ja: "安全にマージ"),
                    detail: mistiaLocalized(
                        vi: "Giữ cả hai phía, gộp theo ID, không tự động nhập nhằng giao dịch giống nhau.",
                        en: "Keep both sides, merge by record ID, and avoid risky automatic transaction dedupe.",
                        ja: "両側のデータを保持し、レコード ID で統合しつつ危険な自動重複排除は行いません。"
                    ),
                    accent: accent,
                    isRecommended: true
                ) {
                    onSelect(.mergeSafely)
                }

                ManagementInitialSyncChoiceButton(
                    title: mistiaLocalized(vi: "Dùng dữ liệu trên máy này", en: "Use this device", ja: "この端末を使う"),
                    detail: mistiaLocalized(
                        vi: "Đẩy local lên cloud và tombstone các bản chỉ có trên cloud.",
                        en: "Upload local data to the cloud and tombstone cloud-only records.",
                        ja: "ローカルデータをクラウドへアップロードし、クラウドにしかないレコードは tombstone 化します。"
                    ),
                    accent: accent,
                    isRecommended: false
                ) {
                    onSelect(.useDevice)
                }

                ManagementInitialSyncChoiceButton(
                    title: mistiaLocalized(vi: "Dùng dữ liệu trên cloud", en: "Use cloud", ja: "クラウドを使う"),
                    detail: mistiaLocalized(
                        vi: "Xóa snapshot local hiện tại rồi kéo toàn bộ cloud về máy.",
                        en: "Replace the current local snapshot with the full cloud state.",
                        ja: "現在のローカルスナップショットを置き換えて、クラウド全体を取得します。"
                    ),
                    accent: .secondary,
                    isRecommended: false
                ) {
                    onSelect(.useCloud)
                }
            }

            Button(
                mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"),
                role: .cancel,
                action: onCancel
            )
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
        .padding(24)
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
                        Text(mistiaLocalized(vi: "Khuyên dùng", en: "Recommended", ja: "おすすめ"))
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
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ManagementSyncConflictCard: View {
    let conflict: SyncConflict
    let accent: Color
    let isDisabled: Bool
    let onResolve: (MistiaSyncConflictResolution) -> Void

    var body: some View {
        MistiaGlassCard(cornerRadius: 20, tint: accent.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(conflict.conflictKind.localizedTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(conflict.entity.displayTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mistiaLocalized(vi: "Máy này", en: "This device", ja: "この端末"))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(conflict.localPreviewTitle)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(mistiaLocalized(vi: "Cloud", en: "Cloud", ja: "クラウド"))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(conflict.remotePreviewTitle)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 10) {
                    Button(conflict.conflictKind.localActionTitle) {
                        onResolve(.useLocal)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(accent)
                    .disabled(isDisabled)

                    Button(conflict.conflictKind.remoteActionTitle) {
                        onResolve(.useRemote)
                    }
                    .buttonStyle(.glass)
                    .tint(.secondary)
                    .disabled(isDisabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Quản lý dữ liệu", en: "Data management", ja: "データ管理"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            if sessionStore.possibleDuplicateCount > 0 {
                ManagementInlineMessageCard(
                    title: mistiaLocalized(
                        vi: "Có giao dịch có thể bị trùng",
                        en: "Possible duplicates detected",
                        ja: "重複の可能性がある取引があります"
                    ),
                    message: mistiaLocalized(
                        vi: "Mistia đang giữ an toàn cả hai bản ghi. Hiện có \(sessionStore.possibleDuplicateCount) giao dịch cần bạn rà lại sau sync.",
                        en: "Mistia kept both records safely. There are currently \(sessionStore.possibleDuplicateCount) transactions to review after sync.",
                        ja: "両方のレコードを安全に保持しています。同期後に確認が必要な取引が \(sessionStore.possibleDuplicateCount) 件あります。"
                    ),
                    accent: .orange
                )
            }

            if activeConflicts.isEmpty {
                ManagementProfilePlaceholderCard(
                    title: mistiaLocalized(vi: "Chưa có conflict", en: "No conflicts yet", ja: "競合はまだありません"),
                    message: mistiaLocalized(
                        vi: "Khi đồng bộ phát sinh conflict hoặc dữ liệu cần rà lại, bạn sẽ quản lý tại đây.",
                        en: "When sync conflicts or review-needed data appear, you will manage them here.",
                        ja: "同期競合や確認が必要なデータが発生したら、ここで管理できます。"
                    ),
                    systemImage: "checkmark.shield.fill",
                    accent: accent
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(activeConflicts) { conflict in
                        ManagementSyncConflictCard(
                            conflict: conflict,
                            accent: accent,
                            isDisabled: !sessionStore.canManageSync
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
        _birthday = State(initialValue: Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now)
        _hasBirthday = State(initialValue: false)
        _draftAvatarURL = State(initialValue: summary.avatarURL)
    }

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var birthdayLabel: String {
        guard hasBirthday else {
            return mistiaLocalized(vi: "Thêm", en: "Add", ja: "追加")
        }

        return MistiaDateFormatting.fullDateString(
            for: birthday,
            language: MistiaAppLanguage.current,
            calendar: calendar
        )
    }

    private var privacyButtonTitle: String {
        mistiaLocalized(
            vi: "Tìm hiểu cách Mistia sử dụng thông tin cá nhân",
            en: "Learn how Mistia uses personal information",
            ja: "Mistia の個人情報の利用方法を確認する"
        )
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Sửa hồ sơ", en: "Edit profile", ja: "プロフィールを編集"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 22
        ) {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    ManagementEditableAvatarBadge(
                        initials: currentInitials,
                        avatarURL: draftAvatarURL,
                        size: 116
                    )

                    Button {
                        showsAvatarSourceDialog = true
                    } label: {
                        Text(mistiaLocalized(vi: "Đổi ảnh", en: "Change Photo", ja: "写真を変更"))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accent.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ManagementProfileListCard(tint: cardTint) {
                    VStack(spacing: 0) {
                        ManagementEditProfileNavigationRow(
                            title: mistiaLocalized(vi: "Họ và tên", en: "Full name", ja: "氏名"),
                            value: draftDisplayName
                        ) {
                            activeSheet = .name
                        }

                        ManagementEditProfileRowDivider()

                        ManagementEditProfileInfoRow(
                            title: mistiaLocalized(vi: "Email", en: "Email", ja: "メール"),
                            value: summary.email
                        )

                        ManagementEditProfileRowDivider()

                        ManagementEditProfileNavigationRow(
                            title: mistiaLocalized(vi: "Ngày sinh", en: "Birthday", ja: "生年月日"),
                            value: birthdayLabel
                        ) {
                            activeSheet = .birthday
                        }
                    }
                }

                Button {
                    showsPrivacySheet = true
                } label: {
                    Text(privacyButtonTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
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
            case .birthday:
                ManagementEditProfileBirthdayEditorView(
                    accent: accent,
                    birthday: $birthday,
                    hasBirthday: $hasBirthday
                ) { updatedBirthday in
                    persistProfileChanges(birthday: updatedBirthday)
                }
            }
        }
        .sheet(item: $avatarSource) { source in
            ManagementProfileImagePicker(sourceType: source.uiImagePickerSourceType) { image in
                handlePickedAvatar(image)
            }
        }
        .confirmationDialog(
            mistiaLocalized(vi: "Đổi ảnh đại diện", en: "Change profile photo", ja: "プロフィール写真を変更"),
            isPresented: $showsAvatarSourceDialog,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(mistiaLocalized(vi: "Chụp ảnh", en: "Take Photo", ja: "写真を撮る")) {
                    avatarSource = .camera
                }
            }

            Button(mistiaLocalized(vi: "Chọn từ thư viện", en: "Choose from Library", ja: "ライブラリから選択")) {
                avatarSource = .photoLibrary
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        }
        .alert(
            mistiaLocalized(vi: "Chưa thể cập nhật hồ sơ", en: "Couldn't update profile", ja: "プロフィールを更新できませんでした"),
            isPresented: Binding(
                get: { profileErrorMessage != nil },
                set: { if !$0 { profileErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(profileErrorMessage ?? "")
        }
        .sheet(isPresented: $showsPrivacySheet) {
            MistiaPrivacySheet()
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
            profileErrorMessage = mistiaLocalized(
                vi: "Không xử lý được ảnh đã chọn.",
                en: "Couldn't process the selected image.",
                ja: "選択した画像を処理できませんでした。"
            )
            return
        }

        persistProfileChanges(avatarJPEGData: avatarJPEGData)
    }
}

private struct ManagementEditProfileNavigationRow: View {
    let title: String
    let value: String
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

private struct ManagementEditProfileModalScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let accent: Color
    let onSave: () -> Void
    let content: Content

    private var modalBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    private var toolbarConfirmTint: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var toolbarConfirmForeground: Color {
        Color(red: 0.88, green: 0.78, blue: 1.0)
    }

    init(
        title: String,
        accent: Color,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                modalBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        content
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(toolbarConfirmForeground)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(toolbarConfirmTint)
                }
            }
        }
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
        ManagementEditProfileModalScaffold(
            title: mistiaLocalized(vi: "Họ và tên", en: "Full name", ja: "氏名"),
            accent: accent
        ) {
            displayName = [
                familyName.trimmingCharacters(in: .whitespacesAndNewlines),
                givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            onSave(displayName)
        } content: {
            ManagementProfileListCard(tint: cardTint) {
                VStack(spacing: 0) {
                    ManagementEditProfileTextFieldRow(
                        title: mistiaLocalized(vi: "Họ", en: "Last name", ja: "姓"),
                        text: $familyName
                    )

                    ManagementEditProfileRowDivider()

                    ManagementEditProfileTextFieldRow(
                        title: mistiaLocalized(vi: "Tên", en: "First name", ja: "名"),
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

            TextField("", text: $text)
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
        ManagementEditProfileModalScaffold(
            title: mistiaLocalized(vi: "Ngày sinh", en: "Birthday", ja: "生年月日"),
            accent: accent
        ) {
            birthday = draftBirthday
            hasBirthday = true
            onSave(draftBirthday)
        } content: {
            VStack(spacing: 18) {
                ManagementProfileListCard(tint: cardTint) {
                    ManagementEditProfileInfoRow(
                        title: mistiaLocalized(vi: "Ngày sinh", en: "Birthday", ja: "生年月日"),
                        value: MistiaDateFormatting.fullDateString(
                            for: draftBirthday,
                            language: MistiaAppLanguage.current,
                            calendar: calendar
                        )
                    )
                }

                MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
                    DatePicker(
                        "",
                        selection: $draftBirthday,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(accent)
                    .environment(\.locale, locale)
                    .environment(\.calendar, calendar)
                }
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
            title: mistiaLocalized(vi: "Thông tin cá nhân", en: "Personal information", ja: "個人情報"),
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
                        title: mistiaLocalized(vi: "Tên và ảnh đại diện", en: "Name and profile photo", ja: "名前とプロフィール写真"),
                        message: mistiaLocalized(
                            vi: "Mistia dùng tên và ảnh đại diện để hiển thị hồ sơ của bạn trên thiết bị đã đăng nhập và trong các vùng liên quan đến tài khoản.",
                            en: "Mistia uses your name and profile photo to present your account consistently across signed-in devices and account-related surfaces.",
                            ja: "Mistia は、サインイン済みデバイスやアカウント関連画面でプロフィールを一貫して表示するために、名前とプロフィール写真を使用します。"
                        )
                    )

                    ManagementProfilePersonalInfoItem(
                        title: mistiaLocalized(vi: "Ngày sinh", en: "Birthday", ja: "生年月日"),
                        message: mistiaLocalized(
                            vi: "Ngày sinh giúp cá nhân hóa trải nghiệm trong tương lai, ví dụ các nhắc nhở hoặc thiết lập phù hợp với độ tuổi. Bạn có thể cập nhật lại bất kỳ lúc nào.",
                            en: "Your birthday can help personalize future experiences such as reminders or age-appropriate settings. You can update it anytime.",
                            ja: "生年月日は、将来のリマインダーや年齢に応じた設定などを個人化するために利用される場合があります。いつでも変更できます。"
                        )
                    )

                    ManagementProfilePersonalInfoItem(
                        title: mistiaLocalized(vi: "Quyền kiểm soát dữ liệu", en: "Data controls", ja: "データ管理"),
                        message: mistiaLocalized(
                            vi: "Bạn luôn có thể đăng xuất, tắt đồng bộ, hoặc xóa tài khoản cloud trong phần Hồ sơ. Dữ liệu local trên thiết bị vẫn được kiểm soát riêng theo các lựa chọn đó.",
                            en: "You can always sign out, disable sync, or delete your cloud account from Profile. Local data on your device remains under the control of those choices.",
                            ja: "プロフィール画面から、ログアウト、同期の無効化、クラウドアカウントの削除をいつでも行えます。ローカルデータはその選択に応じて管理されます。"
                        )
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

private struct ManagementSyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Query private var storedConflicts: [SyncConflict]

    @State private var destination: ManagementSyncSettingsDestination?

    let accent: Color

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    private var lastSyncValue: String {
        guard let lastSyncAt = sessionStore.lastSyncAt else {
            return mistiaLocalized(vi: "Chưa có", en: "None yet", ja: "まだありません")
        }

        return MistiaDateFormatting.dateTimeString(for: lastSyncAt)
    }

    private var dataManagementSummary: String {
        let issueCount = storedConflicts.count + sessionStore.possibleDuplicateCount
        if issueCount > 0 {
            return mistiaLocalized(
                vi: "Hiện có \(issueCount) mục cần bạn rà lại sau đồng bộ, bao gồm conflict và dữ liệu nghi trùng.",
                en: "There are \(issueCount) items to review after syncing, including conflicts and possible duplicates.",
                ja: "同期後に確認が必要な項目が \(issueCount) 件あり、競合や重複候補をここで確認できます。"
            )
        }

        return mistiaLocalized(
            vi: "Xem conflict, dữ liệu cần rà lại và các quyết định đồng bộ đã phát sinh.",
            en: "Review conflicts, records that need attention, and sync decisions that were raised.",
            ja: "競合や確認が必要なデータ、同期時に発生した判断項目を確認します。"
        )
    }

    private var autoSyncFootnote: String {
        mistiaLocalized(
            vi: "Khi bật, Mistia sẽ tự kiểm tra thay đổi và đồng bộ định kỳ trong lúc bạn đang đăng nhập.",
            en: "When enabled, Mistia periodically checks for changes and syncs automatically while you're signed in.",
            ja: "有効にすると、サインイン中に変更を定期確認し、自動で同期します。"
        )
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Cài đặt đồng bộ", en: "Sync settings", ja: "同期設定"),
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
                    ManagementProfileInfoRow(
                        title: mistiaLocalized(vi: "Lần đồng bộ gần nhất", en: "Last sync", ja: "前回の同期"),
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        accent: .slate,
                        value: lastSyncValue,
                        subtitle: nil
                    )

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: mistiaLocalized(vi: "Quản lý dữ liệu đồng bộ", en: "Manage synced data", ja: "同期データを管理"),
                        icon: "externaldrive.badge.person.crop",
                        accent: .amber,
                        subtitle: nil,
                        badge: {
                            let issueCount = storedConflicts.count + sessionStore.possibleDuplicateCount
                            return issueCount > 0 ? "\(issueCount)" : nil
                        }()
                    ) {
                        destination = .dataManagement
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(dataManagementSummary)
                    .descriptionTextStyle()
                    .padding(.horizontal, 2)
            }
            .cardDescriptionStyle()

            ManagementProfileListCard(tint: cardTint) {
                ManagementProfileToggleRow(
                    title: mistiaLocalized(vi: "Tự động đồng bộ", en: "Auto sync", ja: "自動同期"),
                    icon: "arrow.triangle.2.circlepath.icloud",
                    accent: .mint,
                    subtitle: nil,
                    isOn: Binding(
                        get: { sessionStore.isAutoSyncEnabled },
                        set: { sessionStore.setAutoSyncEnabled($0) }
                    ),
                    isDisabled: !sessionStore.canManageSync
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(autoSyncFootnote)
                    .descriptionTextStyle()
                    .padding(.horizontal, 2)
            }
            .cardDescriptionStyle()

            ManagementProfilePrimaryActionButton(
                title: mistiaLocalized(vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期"),
                accent: accent,
                isDisabled: !sessionStore.canManageSync || sessionStore.isWorking,
                showsProgress: sessionStore.isWorking && sessionStore.canManageSync
            ) {
                Task {
                    await sessionStore.syncNow()
                }
            }
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .dataManagement:
                ManagementDataConflictsView(accent: accent)
            }
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
                        ? mistiaLocalized(vi: "Ẩn mật khẩu", en: "Hide password", ja: "パスワードを隠す")
                        : mistiaLocalized(vi: "Hiện mật khẩu", en: "Show password", ja: "パスワードを表示")
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
        Text("G")
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
                title: mistiaLocalized(
                    vi: "Ít nhất 8 ký tự",
                    en: "At least 8 characters",
                    ja: "8 文字以上"
                ),
                isSatisfied: assessment.hasMinimumLength,
                showsNeutralState: showsNeutralState
            )

            ManagementPasswordRequirementRow(
                title: mistiaLocalized(
                    vi: "Ít nhất 1 chữ viết hoa",
                    en: "At least 1 uppercase letter",
                    ja: "大文字を 1 文字以上"
                ),
                isSatisfied: assessment.hasUppercase,
                showsNeutralState: showsNeutralState
            )

            ManagementPasswordRequirementRow(
                title: mistiaLocalized(
                    vi: "Ít nhất 1 chữ viết thường",
                    en: "At least 1 lowercase letter",
                    ja: "小文字を 1 文字以上"
                ),
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
            return mistiaLocalized(vi: "Rất yếu", en: "Very weak", ja: "とても弱い")
        case .weak:
            return mistiaLocalized(vi: "Yếu", en: "Weak", ja: "弱い")
        case .normal:
            return mistiaLocalized(vi: "Ổn", en: "Normal", ja: "普通")
        case .strong:
            return mistiaLocalized(vi: "Mạnh", en: "Strong", ja: "強い")
        case .veryStrong:
            return mistiaLocalized(vi: "Rất mạnh", en: "Very strong", ja: "とても強い")
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
