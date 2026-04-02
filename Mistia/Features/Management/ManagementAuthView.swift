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

struct ManagementAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    @State private var mode: ManagementAuthMode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""

    private let accent = Color(red: 0.43, green: 0.23, blue: 0.76)

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: sessionStore.isSignedIn
                ? mistiaLocalized(vi: "Tài khoản & sync", en: "Account & sync", ja: "アカウントと同期")
                : mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
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
                        vi: "Mistia đã có sẵn flow đăng nhập và đồng bộ, nhưng bạn cần điền URL cùng anon key của Supabase trước khi dùng.",
                        en: "Mistia already has the sign-in and sync flow, but you need to fill in the Supabase URL and anon key first.",
                        ja: "Mistia にはログインと同期の流れがありますが、使う前に Supabase の URL と anon key を設定する必要があります。"
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
                        MistiaAvatarBadge(initials: summary.initials, size: 56, showsStatus: false)

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
        VStack(spacing: 16) {
            MistiaGlassCard(
                cornerRadius: 24,
                tint: accent.opacity(0.12)
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ManagementStatusBadge(
                        title: mistiaLocalized(vi: "Local-first + cloud sync", en: "Local-first + cloud sync", ja: "ローカルファースト + クラウド同期"),
                        systemImage: "icloud.and.arrow.up.fill",
                        accent: accent
                    )

                    Text(
                        mistiaLocalized(
                            vi: "Dùng cùng một tài khoản Mistia để đồng bộ ví, danh mục, giao dịch và các kế hoạch sang thiết bị khác.",
                            en: "Use the same Mistia account to sync wallets, categories, transactions, and plans across devices.",
                            ja: "同じ Mistia アカウントでウォレット、カテゴリ、取引、計画を別の端末へ同期できます。"
                        )
                    )
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                    MistiaNativeSegmentedControl(
                        selection: $mode,
                        options: ManagementAuthMode.allCases,
                        title: \.title,
                        accent: accent
                    )

                    VStack(spacing: 12) {
                        if mode == .signUp {
                            TextField(
                                mistiaLocalized(vi: "Tên hiển thị", en: "Display name", ja: "表示名"),
                                text: $displayName
                            )
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        TextField(
                            mistiaLocalized(vi: "Email", en: "Email", ja: "メールアドレス"),
                            text: $email
                        )
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        SecureField(
                            mistiaLocalized(vi: "Mật khẩu", en: "Password", ja: "パスワード"),
                            text: $password
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 10) {
                            if sessionStore.isWorking {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(
                                mode == .signIn
                                    ? mistiaLocalized(vi: "Đăng nhập", en: "Sign in", ja: "ログイン")
                                    : mistiaLocalized(vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成")
                            )
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(accent)
                    .disabled(sessionStore.isWorking || !canSubmit)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ManagementSyncStateCard(
                title: sessionStore.syncStatusTitle,
                detail: sessionStore.syncStatusDetail,
                systemImage: sessionStore.syncStatusSystemImage,
                accent: accent
            )

            if let lastErrorMessage = sessionStore.lastErrorMessage {
                ManagementInlineMessageCard(
                    title: mistiaLocalized(vi: "Chưa thể tiếp tục", en: "Can't continue yet", ja: "まだ続行できません"),
                    message: lastErrorMessage,
                    accent: .orange
                )
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && (mode == .signIn || !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            switch mode {
            case .signIn:
                await sessionStore.signIn(email: trimmedEmail, password: password)
            case .signUp:
                await sessionStore.signUp(
                    email: trimmedEmail,
                    password: password,
                    displayName: trimmedDisplayName
                )
            }
        }
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
