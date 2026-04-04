import SwiftUI

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

struct ManagementAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var isEmailAuthExpanded = false
    @FocusState private var focusedField: ManagementAuthInput?

    @Environment(\.colorScheme) private var colorScheme

    // Tone màu tím đặc trưng, sáng hơn trong Dark Mode
    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.65, green: 0.45, blue: 0.98)
            : Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private let secondaryBackground = Color(UIColor.secondarySystemBackground)

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: sessionStore.isSignedIn
                ? mistiaLocalized(vi: "Tài khoản & sync", en: "Account & sync", ja: "アカウントと同期")
                : (isEmailAuthExpanded ? authScreenTitle : ""),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
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
            contentSpacing: 18
        ) {
            if !sessionStore.isConfigured {
                configurationCard
            } else if let summary = sessionStore.summary {
                signedInContent(summary: summary)
            } else {
                authForm
            }
        }
        .onChange(of: sessionStore.authPendingEmail) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            email = newValue
        }
        .onChange(of: displayName) { _, _ in
            sessionStore.clearAuthFieldError(.displayName)
        }
        .onChange(of: email) { _, _ in
            sessionStore.clearAuthFieldError(.email)
        }
        .onChange(of: password) { _, _ in
            sessionStore.clearAuthFieldError(.password)
            sessionStore.clearAuthFieldError(.confirmPassword)
        }
        .onChange(of: confirmPassword) { _, _ in
            sessionStore.clearAuthFieldError(.confirmPassword)
        }
    }

    private var configurationCard: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: accent.opacity(0.14)
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
        VStack(spacing: 16) {
            MistiaGlassCard(
                cornerRadius: 24,
                tint: accent.opacity(0.12)
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        MistiaAvatarBadge(
                            initials: summary.initials,
                            avatarURL: summary.avatarURL,
                            size: 56,
                            showsStatus: false
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.displayName)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(summary.email)
                                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ManagementSyncStateCard(
                        title: sessionStore.syncStatusTitle,
                        detail: sessionStore.syncStatusDetail,
                        systemImage: sessionStore.syncStatusSystemImage,
                        accent: accent
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastErrorMessage = sessionStore.lastErrorMessage {
                ManagementInlineMessageCard(
                    title: mistiaLocalized(vi: "Lỗi gần nhất", en: "Latest issue", ja: "直近の問題"),
                    message: lastErrorMessage,
                    accent: .orange
                )
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await sessionStore.syncNow()
                    }
                } label: {
                    Label(
                        mistiaLocalized(vi: "Sync ngay", en: "Sync now", ja: "今すぐ同期"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(accent)
                .disabled(!sessionStore.canManageSync || sessionStore.isWorking)

                Button(role: .destructive) {
                    Task {
                        await sessionStore.signOut()
                    }
                } label: {
                    Label(
                        mistiaLocalized(vi: "Đăng xuất", en: "Sign out", ja: "ログアウト"),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glass)
                .tint(.red)
                .disabled(sessionStore.isWorking)
            }
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
                        if let banner = sessionStore.authBanner {
                            ManagementAuthBannerCard(banner: banner)
                        }

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
            Image("MistiaIcon") // Assuming there's a logo, replace with actual logo if needed
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

private struct ManagementSyncStateCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)

                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(detail)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ManagementInlineMessageCard: View {
    let title: String
    let message: String
    let accent: Color

    var body: some View {
        MistiaGlassCard(cornerRadius: 20, tint: accent.opacity(0.14)) {
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
        return isSatisfied ? Color(red: 0.25, green: 0.76, blue: 0.34) : Color.red.opacity(0.92)
    }

    private var textColor: Color {
        if showsNeutralState {
            return .secondary
        }
        return isSatisfied ? Color(red: 0.25, green: 0.76, blue: 0.34) : Color.red.opacity(0.92)
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
            return Color(red: 0.25, green: 0.76, blue: 0.34)
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
            return Color(red: 0.25, green: 0.76, blue: 0.34)
        case .error:
            return Color(red: 0.91, green: 0.29, blue: 0.32)
        }
    }
}
