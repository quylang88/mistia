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
            mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン")
        case .signUp:
            mistiaLocalized(vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成")
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
            return mistiaLocalized(
                vi: "Mistia đang tự động kiểm tra và đồng bộ dữ liệu. Để đạt hiệu quả tốt nhất, hãy đảm bảo iPhone của bạn được kết nối Wi-Fi và cắm sạc khi có thể. Hệ thống sẽ ưu tiên chạy ngầm khi bạn không sử dụng ứng dụng.",
                en: "Mistia is automatically checking and syncing data. For best performance, ensure your iPhone is connected to Wi-Fi and charging when possible. The system prioritizes background sync when you're not using the app.",
                ja: "Mistia はデータを自動的に確認して同期しています。最高のパフォーマンスを得るために、可能であれば iPhone を Wi-Fi に接続し、充電状態にしてください。アプリを使用していない間のバックグラウンド同期が優先されます。"
            )
        } else {
            return mistiaLocalized(
                vi: "Tự động đồng bộ đang tắt. Dữ liệu của bạn sẽ chỉ được cập nhật khi bạn nhấn nút 'Đồng bộ ngay' một cách thủ công. Bật tính năng này để đảm bảo dữ liệu luôn được cập nhật mới nhất trên mọi thiết bị.",
                en: "Auto sync is off. Your data will only update when you manually tap the 'Sync now' button. Enable this feature to keep your data up to date across all your devices automatically.",
                ja: "自動同期はオフです。データは「今すぐ同期」ボタンを手動で押したときにのみ更新されます。すべてのデバイスでデータを最新の状態に保つには、この機能を有効にしてください。"
            )
        }
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Tự động đồng bộ", en: "Auto sync", ja: "自動同期"),
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
                    Text(mistiaLocalized(vi: "Tự động đồng bộ", en: "Auto sync", ja: "自動同期"))
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Toggle("", isOn: Binding(
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
                ManagementBackupRestoreView()
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
                        title: mistiaLocalized(vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元"),
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
                    accent: .lightPurple,
                    subtitle: nil,
                    value: familyContextStore.family?.name ?? mistiaLocalized(vi: "Chưa có", en: "None", ja: "未設定"),
                    isDisabled: !sessionStore.canPerformRemoteActions
                ) {
                    destination = .family
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: mistiaLocalized(vi: "Đăng xuất và giữ local", en: "Sign out and keep local", ja: "ログアウトしてローカルを保持"),
                confirmationMessage: mistiaLocalized(
                    vi: "Bạn sẽ bị đăng xuất khỏi Mistia trên thiết bị này. Dữ liệu local hiện có vẫn được giữ lại.",
                    en: "You will be signed out of Mistia on this device. Existing local data will stay on the device.",
                    ja: "この端末で Mistia からログアウトします。既存のローカルデータは保持されます。"
                ),
                isDisabled: sessionStore.isWorking
            ) {
                Task {
                    await sessionStore.signOut()
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: mistiaLocalized(vi: "Đăng xuất và xóa local", en: "Sign out and delete local", ja: "ログアウトしてローカルを削除"),
                confirmationMessage: mistiaLocalized(
                    vi: "Bạn sẽ bị đăng xuất và toàn bộ dữ liệu local của profile hiện tại trên máy này sẽ bị xóa. Các profile local khác trên thiết bị vẫn được giữ nguyên.",
                    en: "You will be signed out and the current profile's local data on this device will be deleted. Other local profiles on this device will stay untouched.",
                    ja: "ログアウトして、この端末にある現在のプロフィールのローカルデータを削除します。この端末上の他のローカルプロフィールは保持されます。"
                ),
                isDisabled: sessionStore.isWorking
            ) {
                Task {
                    await sessionStore.signOutAndDeleteLocalData()
                }
            }

            ManagementProfileCenteredDestructiveButton(
                title: mistiaLocalized(vi: "Xóa tài khoản", en: "Delete account", ja: "アカウントを削除"),
                confirmationMessage: mistiaLocalized(
                    vi: "Tài khoản và dữ liệu đồng bộ trên cloud sẽ bị xóa vĩnh viễn. Dữ liệu local trên máy này vẫn được giữ lại.",
                    en: "Your cloud account and synced server data will be permanently deleted. Local data on this device will remain.",
                    ja: "クラウドアカウントと同期済みサーバーデータは完全に削除されます。この端末のローカルデータは保持されます。"
                ),
                isDisabled: sessionStore.isWorking || !sessionStore.canPerformRemoteActions
            ) {
                Task {
                    await sessionStore.deleteAccountKeepingLocalData()
                }
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
            return mistiaLocalized(
                vi: "Đang ngoại tuyến",
                en: "Offline",
                ja: "オフライン"
            )
        }

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

                    Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")) {
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
                    title: mistiaLocalized(
                        vi: "Gắn vào tài khoản này",
                        en: "Attach to this account",
                        ja: "このアカウントに紐づける"
                    ),
                    subtitle: mistiaLocalized(
                        vi: "Giữ luôn dữ liệu local guest hiện tại như dữ liệu của tài khoản này.",
                        en: "Keep the current guest local data as part of this account.",
                        ja: "現在のゲストローカルデータをこのアカウントのデータとして引き継ぎます。"
                    )
                ),
                .init(
                    decision: .keepGuestDataSeparate,
                    role: .normal,
                    systemImage: "square.split.2x1.fill",
                    title: mistiaLocalized(
                        vi: "Giữ guest riêng",
                        en: "Keep guest separate",
                        ja: "ゲストを分離したまま保持"
                    ),
                    subtitle: mistiaLocalized(
                        vi: "Đăng nhập tài khoản này nhưng không trộn với dữ liệu guest hiện tại.",
                        en: "Sign in to this account without mixing in the current guest data.",
                        ja: "現在のゲストデータとは分けたまま、このアカウントでログインします。"
                    )
                ),
                .init(
                    decision: .deleteGuestData,
                    role: .destructive,
                    systemImage: "trash.fill",
                    title: mistiaLocalized(
                        vi: "Xóa dữ liệu guest",
                        en: "Delete guest data",
                        ja: "ゲストデータを削除"
                    ),
                    subtitle: mistiaLocalized(
                        vi: "Xóa local guest hiện tại rồi mở tài khoản này với trạng thái sạch.",
                        en: "Delete the current guest local data before opening this account cleanly.",
                        ja: "現在のゲストローカルデータを削除してから、このアカウントをクリーンに開きます。"
                    )
                )
            ]

        case .keepOrDeleteGuestData:
            return [
                .init(
                    decision: .keepGuestDataSeparate,
                    role: .primary,
                    systemImage: "square.split.2x1.fill",
                    title: mistiaLocalized(
                        vi: "Giữ guest riêng",
                        en: "Keep guest separate",
                        ja: "ゲストを分離したまま保持"
                    ),
                    subtitle: mistiaLocalized(
                        vi: "Mở tài khoản này bằng profile riêng, không chuyển dữ liệu guest cũ sang.",
                        en: "Open this account in its own profile without moving over the old guest data.",
                        ja: "古いゲストデータを移さず、このアカウント専用のプロファイルで開きます。"
                    )
                ),
                .init(
                    decision: .deleteGuestData,
                    role: .destructive,
                    systemImage: "trash.fill",
                    title: mistiaLocalized(
                        vi: "Xóa dữ liệu guest",
                        en: "Delete guest data",
                        ja: "ゲストデータを削除"
                    ),
                    subtitle: mistiaLocalized(
                        vi: "Xóa local guest hiện tại trước khi tiếp tục với tài khoản này.",
                        en: "Delete the current guest local data before continuing with this account.",
                        ja: "このアカウントを続ける前に、現在のゲストローカルデータを削除します。"
                    )
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
            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
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
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                        VStack(spacing: 12) {
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
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(
                mistiaLocalized(
                    vi: "Đồng bộ lần đầu",
                    en: "First sync",
                    ja: "初回同期"
                )
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
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
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
            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                ManagementInlineMessageCard(
                    title: mistiaLocalized(
                        vi: "Cần mạng để xử lý conflict",
                        en: "Resolving conflicts needs the network",
                        ja: "競合の解決にはネットワークが必要です"
                    ),
                    message: remoteUnavailableReason,
                    accent: MistiaAccent.sky.color
                )
            }

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
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    ManagementInlineMessageCard(
                        title: mistiaLocalized(
                            vi: "Chỉnh sửa hồ sơ cần mạng",
                            en: "Editing your profile needs the network",
                            ja: "プロフィール編集にはネットワークが必要です"
                        ),
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
                        Text(mistiaLocalized(vi: "Đổi ảnh", en: "Change Photo", ja: "写真を変更"))
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
                            title: mistiaLocalized(vi: "Họ và tên", en: "Full name", ja: "氏名"),
                            value: draftDisplayName,
                            isDisabled: !sessionStore.canPerformRemoteActions
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

        return mistiaLocalized(
            vi: "Đã đồng bộ lúc \(MistiaDateFormatting.dateTimeString(for: lastSyncAt))",
            en: "Synced at \(MistiaDateFormatting.dateTimeString(for: lastSyncAt, language: .english))",
            ja: "\(MistiaDateFormatting.dateTimeString(for: lastSyncAt, language: .japanese)) に同期済み"
        )
    }

    private var syncExplanatoryText: String {
        mistiaLocalized(
            vi: "Mistia đang thực hiện đồng bộ dữ liệu của bạn với hệ thống đám mây để đảm bảo mọi thay đổi được lưu trữ an toàn. Quá trình này giúp bạn có thể truy cập dữ liệu mới nhất trên tất cả các thiết bị của mình.",
            en: "Mistia is syncing your data with the cloud to ensure all changes are stored safely. This process allows you to access the latest data across all your devices.",
            ja: "Mistia はデータをクラウドと同期して, すべての変更が安全に保存されるようにしています。このプロセスにより, すべてのデバイスで最新のデータにアクセスできるようになります。"
        )
    }

    private var autoSyncValue: String {
        if sessionStore.isAutoSyncEnabled {
            return mistiaLocalized(vi: "Bật", en: "On", ja: "オン")
        } else {
            return mistiaLocalized(vi: "Tắt", en: "Off", ja: "オフ")
        }
    }

    private func timeRemainingLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return mistiaLocalized(
                vi: "Còn khoảng \(Int(seconds)) giây",
                en: "About \(Int(seconds)) seconds left",
                ja: "残り約 \(Int(seconds)) 秒"
            )
        } else {
            let minutes = Int(seconds / 60)
            return mistiaLocalized(
                vi: "Còn khoảng \(minutes) phút",
                en: "About \(minutes) minutes left",
                ja: "残り約 \(minutes) 分"
            )
        }
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
                        let issueCount = storedConflicts.count + sessionStore.possibleDuplicateCount
                        if issueCount > 0 {
                            destination = .dataManagement
                        } else {
                            showsNoConflictsAlert = true
                        }
                    }

                    ManagementProfileRowDivider()

                    ManagementProfileNavigationRow(
                        title: mistiaLocalized(vi: "Tự động đồng bộ", en: "Auto sync", ja: "自動同期"),
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
                                Text("\(Int(progress * 100))%")
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
                        title: mistiaLocalized(vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期"),
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
            mistiaLocalized(
                vi: "Dữ liệu đã tối ưu",
                en: "Data is optimized",
                ja: "データは最適化されています"
            ),
            isPresented: $showsNoConflictsAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(
                mistiaLocalized(
                    vi: "Hiện tại dữ liệu của bạn đã được đồng bộ hoàn toàn, không có bất đồng bộ nào cần xử lý.",
                    en: "Your data is currently fully synced, no conflicts need attention.",
                    ja: "現在、データは完全に同期されており、解決が必要な競合はありません。"
                )
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

private struct ManagementBackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ManagementBackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

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
            tone: .standard,
            title: mistiaLocalized(vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            ManagementInlineMessageCard(
                title: mistiaLocalized(vi: "Snapshot khẩn cấp", en: "Emergency snapshot", ja: "緊急スナップショット"),
                message: mistiaLocalized(
                    vi: "Tạo file `.mistiabackup` để lưu lại toàn bộ dữ liệu local hiện tại. Khi nhập lại snapshot, Mistia chỉ khôi phục local trước và sẽ không tự đẩy lên cloud cho tới khi bạn tự bấm Đồng bộ ngay.",
                    en: "Create a `.mistiabackup` file to capture the current local state. When you restore it, Mistia updates local data first and won't push to the cloud until you manually tap Sync now.",
                    ja: "現在のローカル状態を `.mistiabackup` ファイルとして保存できます。復元時はまずローカルデータだけを更新し、手動で「今すぐ同期」を押すまでクラウドへは自動送信しません。"
                ),
                accent: .mint
            )

            ManagementProfileListCard(tint: cardTint) {
                VStack(spacing: 0) {
                    backupActionRow(
                        title: mistiaLocalized(vi: "Tạo snapshot", en: "Create snapshot", ja: "スナップショットを作成"),
                        subtitle: mistiaLocalized(
                            vi: "Xuất dữ liệu local hiện tại thành một file `.mistiabackup`.",
                            en: "Export the current local data into a single `.mistiabackup` file.",
                            ja: "現在のローカルデータを 1 つの `.mistiabackup` ファイルとして書き出します。"
                        ),
                        systemImage: "square.and.arrow.up.fill",
                        tint: .blue,
                        isDisabled: isBusy,
                        action: exportSnapshot
                    )

                    ManagementProfileRowDivider()

                    backupActionRow(
                        title: mistiaLocalized(vi: "Nhập snapshot", en: "Import snapshot", ja: "スナップショットを読み込む"),
                        subtitle: restoreMode == .merge
                            ? mistiaLocalized(
                                vi: "Nhập file và ưu tiên dữ liệu trong snapshot khi trùng ID, nhưng vẫn giữ các mục local khác.",
                                en: "Import the file and let snapshot values win on matching IDs while keeping unrelated local records.",
                                ja: "同じ ID はスナップショット側を優先しつつ、関係ないローカルレコードは維持して読み込みます。"
                            )
                            : mistiaLocalized(
                                vi: "Nhập file và thay toàn bộ dữ liệu local hiện tại sau khi Mistia tạo một safety snapshot nội bộ.",
                                en: "Import the file and replace the current local dataset after Mistia creates an internal safety snapshot first.",
                                ja: "先に内部の安全用スナップショットを作成したうえで、現在のローカルデータ全体を置き換えて読み込みます。"
                            ),
                        systemImage: "square.and.arrow.down.fill",
                        tint: .mint,
                        isDisabled: isBusy,
                        action: { isImporting = true }
                    )
                }
            }

            ManagementProfileListCard(tint: cardTint) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(mistiaLocalized(vi: "Chế độ khôi phục", en: "Restore mode", ja: "復元モード"))
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Picker("", selection: $restoreMode) {
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
                        Text(mistiaLocalized(vi: "Nội dung snapshot gần nhất", en: "Latest snapshot summary", ja: "直近のスナップショット概要"))
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            mistiaLocalized(
                                vi: "Bản sao lưu format V\(latestSummary.manifest.backupFormatVersion) • app \(latestSummary.manifest.appVersion) (\(latestSummary.manifest.appBuild)) • schema local V\(latestSummary.manifest.localSchemaVersion)",
                                en: "Backup format V\(latestSummary.manifest.backupFormatVersion) • app \(latestSummary.manifest.appVersion) (\(latestSummary.manifest.appBuild)) • local schema V\(latestSummary.manifest.localSchemaVersion)",
                                ja: "バックアップ形式 V\(latestSummary.manifest.backupFormatVersion) • app \(latestSummary.manifest.appVersion) (\(latestSummary.manifest.appBuild)) • ローカルスキーマ V\(latestSummary.manifest.localSchemaVersion)"
                            )
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
                    title: mistiaLocalized(vi: "Đang chờ bạn kiểm tra rồi sync", en: "Waiting for your review before sync", ja: "確認後の手動同期待ち"),
                    message: mistiaLocalized(
                        vi: "Tự động sync đang tạm dừng sau khi khôi phục snapshot. Khi bạn đã kiểm tra dữ liệu ổn, hãy vào Đồng bộ dữ liệu và nhấn Đồng bộ ngay.",
                        en: "Auto sync is paused after the restore. Once you've reviewed the data, open Sync settings and tap Sync now.",
                        ja: "スナップショット復元後は自動同期を停止しています。データ確認後に同期設定へ移動して「今すぐ同期」を押してください。"
                    ),
                    accent: .orange
                )
            }

            if let latestRestoreResult, let safetySnapshotURL = latestRestoreResult.safetySnapshotURL {
                ManagementProfileListCard(tint: cardTint) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(mistiaLocalized(vi: "Safety snapshot nội bộ", en: "Internal safety snapshot", ja: "内部安全スナップショット"))
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            mistiaLocalized(
                                vi: "Mistia đã tạo một snapshot an toàn trước khi thay toàn bộ dữ liệu local. Bạn có thể share file này ra ngoài nếu muốn giữ thêm một lớp dự phòng.",
                                en: "Mistia created a safety snapshot before replacing local data. You can share that file if you want an extra fallback copy.",
                                ja: "ローカルデータを置き換える前に、安全用スナップショットを作成しました。追加の予備として外部共有することもできます。"
                            )
                        )
                        .descriptionTextStyle()

                        Button {
                            shareItem = TransactionShareItem(url: safetySnapshotURL)
                        } label: {
                            Label(
                                mistiaLocalized(vi: "Chia sẻ safety snapshot", en: "Share safety snapshot", ja: "安全スナップショットを共有"),
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
                title: Text(mistiaCatalog(alert.title)),
                message: Text(mistiaCatalog(alert.message)),
                dismissButton: .default(Text(mistiaLocalized(vi: "OK", en: "OK", ja: "OK")))
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
                title: mistiaLocalized(vi: "Không thể tạo snapshot", en: "Couldn't create snapshot", ja: "スナップショットを作成できませんでした"),
                message: error.localizedDescription
            )
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                alert = ManagementBackupAlert(
                    title: mistiaLocalized(vi: "Không có file nào được chọn", en: "No file selected", ja: "ファイルが選択されていません"),
                    message: mistiaLocalized(
                        vi: "Hãy chọn một file `.mistiabackup` để tiếp tục.",
                        en: "Choose a `.mistiabackup` file to continue.",
                        ja: "続行するには `.mistiabackup` ファイルを選択してください。"
                    )
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
                    let data = try Data(contentsOf: url)
                    let summary = try MistiaBackupStore.validateBackup(data)
                    latestSummary = summary
                    latestRestoreResult = try await sessionStore.restoreBackup(
                        data: data,
                        mode: restoreMode
                    )

                    alert = ManagementBackupAlert(
                        title: mistiaLocalized(vi: "Đã khôi phục snapshot", en: "Snapshot restored", ja: "スナップショットを復元しました"),
                        message: restoreMode == .merge
                            ? mistiaLocalized(
                                vi: "Mistia đã merge dữ liệu từ snapshot vào local. Hãy kiểm tra lại rồi tự bấm Đồng bộ ngay nếu bạn muốn cập nhật cloud.",
                                en: "Mistia merged the snapshot into local data. Review it, then manually tap Sync now if you want to update the cloud.",
                                ja: "スナップショットをローカルデータへマージしました。内容を確認してから、必要に応じて手動で「今すぐ同期」を押してください。"
                            )
                            : mistiaLocalized(
                                vi: "Mistia đã thay dữ liệu local bằng snapshot đã chọn và giữ lại một safety snapshot nội bộ trước đó.",
                                en: "Mistia replaced local data with the selected snapshot and kept an internal safety snapshot beforehand.",
                                ja: "選択したスナップショットでローカルデータを置き換え、事前に内部の安全用スナップショットも保存しました。"
                            )
                    )
                } catch {
                    alert = ManagementBackupAlert(
                        title: mistiaLocalized(vi: "Không thể nhập snapshot", en: "Couldn't import snapshot", ja: "スナップショットを読み込めませんでした"),
                        message: error.localizedDescription
                    )
                }
            }
        case .failure(let error):
            alert = ManagementBackupAlert(
                title: mistiaLocalized(vi: "Không thể mở file", en: "Couldn't open file", ja: "ファイルを開けませんでした"),
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
            mistiaLocalized(vi: "Merge", en: "Merge", ja: "マージ")
        case .replaceLocal:
            mistiaLocalized(vi: "Thay local", en: "Replace local", ja: "ローカルを置換")
        }
    }

    var localizedDescription: String {
        switch self {
        case .merge:
            mistiaLocalized(
                vi: "Giữ dữ liệu local không liên quan, nhưng nếu snapshot có cùng ID thì bản trong snapshot sẽ ghi đè lên local.",
                en: "Keep unrelated local records, but if the snapshot contains the same ID, the snapshot version wins.",
                ja: "関係のないローカルレコードは維持しつつ、同じ ID がある場合はスナップショット側を優先します。"
            )
        case .replaceLocal:
            mistiaLocalized(
                vi: "Mistia sẽ tạo safety snapshot nội bộ, xóa toàn bộ dữ liệu local hiện tại rồi khôi phục đúng nội dung snapshot bạn đã chọn.",
                en: "Mistia first creates an internal safety snapshot, clears the current local dataset, then restores exactly what the selected snapshot contains.",
                ja: "最初に内部の安全用スナップショットを作成し、現在のローカルデータを消去してから、選択したスナップショットの内容をそのまま復元します。"
            )
        }
    }
}

private extension MistiaBackupValidationSummary {
    var localizedBreakdown: String {
        mistiaLocalized(
            vi: "Tổng \(activeRecordCount) bản ghi dữ liệu • Ví \(walletCount) • Thẻ \(creditCardProfileCount) • Danh mục \(categoryCount) • Giao dịch \(transactionCount) • Ngân sách \(budgetPlanCount) • Mục tiêu \(savingsGoalCount) • Hóa đơn định kỳ \(recurringBillPlanCount) • Trả góp \(installmentPlanCount) • Kỳ hạn \(dueOccurrenceCount) • Hồ sơ \(userProfileCount) • Quyền sở hữu \(ownershipScopeCount) • Audit \(transactionAuditCount)",
            en: "\(activeRecordCount) data records total • Wallets \(walletCount) • Cards \(creditCardProfileCount) • Categories \(categoryCount) • Transactions \(transactionCount) • Budgets \(budgetPlanCount) • Goals \(savingsGoalCount) • Recurring bills \(recurringBillPlanCount) • Installments \(installmentPlanCount) • Due occurrences \(dueOccurrenceCount) • Profiles \(userProfileCount) • Ownership scopes \(ownershipScopeCount) • Audits \(transactionAuditCount)",
            ja: "データ \(activeRecordCount) 件 • ウォレット \(walletCount) • カード \(creditCardProfileCount) • カテゴリ \(categoryCount) • 取引 \(transactionCount) • 予算 \(budgetPlanCount) • 目標 \(savingsGoalCount) • 定期請求 \(recurringBillPlanCount) • 分割払い \(installmentPlanCount) • 支払予定 \(dueOccurrenceCount) • プロフィール \(userProfileCount) • 所有スコープ \(ownershipScopeCount) • 監査 \(transactionAuditCount)"
        )
    }
}

private extension UTType {
    static let mistiaBackup = UTType(filenameExtension: "mistiabackup") ?? UTType(exportedAs: "app.mistia.backup", conformingTo: .data)
}
