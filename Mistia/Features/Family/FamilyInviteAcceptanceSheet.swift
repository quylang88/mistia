import SwiftUI

struct FamilyInviteAcceptanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    let route: FamilyInviteRoute

    @State private var preview: FamilyInvitePreviewRecord?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isAccepting = false
    @State private var didAccept = false
    @State private var showsAccount = false
    @State private var showsDeclineConfirmation = false

    private var accent: Color {
        MistiaAccent.purple.color
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if sessionStore.isSignedIn {
                        signedInContent
                    } else {
                        signInRequiredContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(mistiaLocalized(vi: "Lời mời gia đình", en: "Family invite", ja: "家族への招待"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        familyContextStore.dismissPendingInviteForNow()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .task(id: loadKey) {
                await loadPreviewIfNeeded()
            }
            .onChange(of: sessionStore.signedInUserID) { _, newValue in
                if newValue != nil {
                    showsAccount = false
                    Task { await loadPreviewIfNeeded(force: true) }
                }
            }
            .sheet(isPresented: $showsAccount) {
                NavigationStack {
                    ManagementAccountView()
                }
            }
            .confirmationDialog(
                mistiaLocalized(
                    vi: "Bạn có chắc muốn từ chối lời mời tham gia gia đình này không?",
                    en: "Are you sure you want to decline this family invite?",
                    ja: "この家族への招待を辞退しますか？"
                ),
                isPresented: $showsDeclineConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    mistiaLocalized(vi: "Từ chối", en: "Decline", ja: "辞退"),
                    role: .destructive
                ) {
                    familyContextStore.clearPendingInvite()
                    dismiss()
                }

                Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {}
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var signedInContent: some View {
        if didAccept {
            acceptedContent
        } else if isLoading {
            loadingContent
        } else if let preview {
            previewContent(preview)
        } else {
            inviteErrorContent(
                message: errorMessage ?? mistiaLocalized(
                    vi: "Không thể kiểm tra lời mời do mất kết nối. Vui lòng thử lại.",
                    en: "Can't check this invite because the connection is unavailable. Please try again.",
                    ja: "接続できないため招待を確認できません。もう一度お試しください。"
                )
            )
        }
    }

    private var signInRequiredContent: some View {
        VStack(spacing: 18) {
            inviteSymbol(systemImage: "person.crop.circle.badge.plus")

            VStack(spacing: 8) {
                Text(mistiaLocalized(
                    vi: "Đăng nhập để tiếp tục tham gia gia đình trên Mistia",
                    en: "Sign in to continue joining this Mistia family",
                    ja: "Mistiaの家族に参加するにはログインしてください"
                ))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

                Text(mistiaLocalized(
                    vi: "Mistia sẽ giữ lời mời này và tự mở lại sau khi bạn đăng nhập hoặc tạo tài khoản.",
                    en: "Mistia will keep this invite and reopen it after you sign in or create an account.",
                    ja: "ログインまたはアカウント作成後、この招待を自動で再開します。"
                ))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Button {
                showsAccount = true
            } label: {
                Text(mistiaLocalized(vi: "Đăng nhập hoặc tạo tài khoản", en: "Sign in or create account", ja: "ログインまたはアカウント作成"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)

            Button {
                familyContextStore.dismissPendingInviteForNow()
                dismiss()
            } label: {
                Text(mistiaLocalized(vi: "Để sau", en: "Later", ja: "あとで"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text(mistiaLocalized(vi: "Đang kiểm tra lời mời", en: "Checking invite", ja: "招待を確認中"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var acceptedContent: some View {
        VStack(spacing: 18) {
            inviteSymbol(systemImage: "checkmark.circle.fill", tint: .mint)

            Text(mistiaLocalized(
                vi: "Bạn đã tham gia gia đình \(preview?.familyName ?? "")",
                en: "You've joined \(preview?.familyName ?? "")",
                ja: "\(preview?.familyName ?? "") に参加しました"
            ))
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)

            Button {
                familyContextStore.clearPendingInvite()
                familyContextStore.activateFamilyHome()
                dismiss()
            } label: {
                Text(mistiaLocalized(vi: "Mở Gia đình", en: "Open Family", ja: "家族を開く"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func previewContent(_ preview: FamilyInvitePreviewRecord) -> some View {
        if preview.inviterUserID == sessionStore.signedInUserID {
            inviteErrorContent(
                title: mistiaLocalized(
                    vi: "Link này không khả dụng với bạn",
                    en: "This link isn't available to you",
                    ja: "このリンクはこのアカウントでは利用できません"
                ),
                message: mistiaLocalized(
                    vi: "Bạn là người tạo lời mời này. Hãy gửi link cho thành viên cần tham gia; tài khoản của bạn không thể dùng chính lời mời này.",
                    en: "You created this invite. Send the link to the person who should join; your account can't use its own invite.",
                    ja: "この招待を作成したアカウントです。参加する相手にリンクを共有してください。このアカウントでは使用できません。"
                ),
                showsRetry: false,
                actionTitle: mistiaLocalized(vi: "Mở Gia đình", en: "Open Family", ja: "家族を開く"),
                action: {
                    familyContextStore.clearPendingInvite()
                    familyContextStore.activateFamilyHome()
                    dismiss()
                }
            )
        } else if preview.alreadyMemberOfFamily {
            inviteErrorContent(
                title: mistiaLocalized(vi: "Bạn đã là thành viên", en: "Already a member", ja: "すでにメンバーです"),
                message: mistiaLocalized(
                    vi: "Bạn đã là thành viên của gia đình này.",
                    en: "You're already a member of this family.",
                    ja: "あなたはすでにこの家族のメンバーです。"
                ),
                actionTitle: mistiaLocalized(vi: "Mở Gia đình", en: "Open Family", ja: "家族を開く"),
                action: {
                    familyContextStore.clearPendingInvite()
                    familyContextStore.activateFamilyHome()
                    dismiss()
                }
            )
        } else if preview.belongsToAnotherFamily {
            inviteErrorContent(message: mistiaLocalized(
                vi: "Tài khoản này hiện đã thuộc một gia đình khác. Vui lòng rời gia đình hiện tại trước khi tham gia gia đình mới.",
                en: "This account currently belongs to another family. Please leave the current family before joining a new one.",
                ja: "このアカウントは現在別の家族に参加しています。新しい家族に参加する前に現在の家族から退出してください。"
            ))
        } else if preview.status != .pending {
            inviteErrorContent(message: message(for: preview.status))
        } else {
            welcomeContent(preview)
        }
    }

    private func welcomeContent(_ preview: FamilyInvitePreviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                inviteSymbol(systemImage: "person.3.fill")

                Text(mistiaLocalized(
                    vi: "Chào mừng đến với gia đình \(preview.familyName)",
                    en: "Welcome to \(preview.familyName)",
                    ja: "\(preview.familyName) へようこそ"
                ))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

                Text(mistiaLocalized(
                    vi: "\(preview.inviterName) đã mời bạn tham gia gia đình trên Mistia.",
                    en: "\(preview.inviterName) invited you to join their family on Mistia.",
                    ja: "\(preview.inviterName) さんがMistiaの家族に招待しました。"
                ))
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            MistiaGlassCard(cornerRadius: 16, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
                VStack(spacing: 0) {
                    FamilyInviteFactRow(
                        title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
                        value: preview.familyName,
                        systemImage: "person.3"
                    )
                    Divider().padding(.leading, 52)
                    FamilyInviteFactRow(
                        title: mistiaLocalized(vi: "Người mời", en: "Inviter", ja: "招待者"),
                        value: preview.inviterName,
                        systemImage: "person.crop.circle"
                    )
                    Divider().padding(.leading, 52)
                    FamilyInviteFactRow(
                        title: mistiaLocalized(vi: "Vai trò của bạn", en: "Your role", ja: "あなたの役割"),
                        value: preview.role.inviteTitle,
                        systemImage: "person.badge.key"
                    )
                }
            }

            permissionSection(for: preview.role)
            privacySection(for: preview.role)

            VStack(spacing: 10) {
                Button {
                    Task { await accept(preview) }
                } label: {
                    if isAccepting {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(mistiaLocalized(vi: "Tham gia gia đình", en: "Join family", ja: "家族に参加"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accent)
                .disabled(isAccepting)

                Button {
                    showsDeclineConfirmation = true
                } label: {
                    Text(mistiaLocalized(vi: "Từ chối", en: "Decline", ja: "辞退"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func permissionSection(for role: FamilyRole) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mistiaLocalized(vi: "Quyền cơ bản", en: "Basic permissions", ja: "基本権限"))
                .font(.system(size: 16, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(role.permissionSummaries, id: \.self) { summary in
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func privacySection(for role: FamilyRole) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                mistiaLocalized(vi: "Quyền riêng tư", en: "Privacy", ja: "プライバシー"),
                systemImage: "lock.shield"
            )
            .font(.system(size: 16, weight: .bold, design: .rounded))

            Text(mistiaLocalized(
                vi: "Tham gia gia đình không đồng nghĩa với việc mọi người có toàn quyền xem dữ liệu của nhau. Quyền xem và thao tác dữ liệu sẽ phụ thuộc vào cài đặt quyền của gia đình.",
                en: "Joining a family does not give everyone full access to each other's data. View and edit access still depends on family permissions.",
                ja: "家族に参加しても、全員が互いのデータを自由に見られるわけではありません。表示と操作の権限は家族の権限設定に従います。"
            ))
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if role == .kid {
                Text(mistiaLocalized(
                    vi: "Tài khoản trẻ em sẽ chịu sự quản lý của phụ huynh hoặc chủ gia đình. Một số thông tin và quyền thao tác có thể bị giới hạn.",
                    en: "A child account is managed by a parent or family owner. Some information and actions may be limited.",
                    ja: "子どもアカウントは保護者または家族の所有者によって管理され、一部の情報や操作が制限される場合があります。"
                ))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(role == .kid ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inviteErrorContent(
        title: String = mistiaLocalized(vi: "Lời mời không khả dụng", en: "Invite unavailable", ja: "招待を利用できません"),
        message: String,
        showsRetry: Bool = true,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 18) {
            inviteSymbol(systemImage: "exclamationmark.triangle.fill", tint: .orange)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showsRetry {
                Button {
                    Task { await loadPreviewIfNeeded(force: true) }
                } label: {
                    Text(mistiaLocalized(vi: "Thử lại", en: "Try again", ja: "再試行"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accent)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                familyContextStore.clearPendingInvite()
                dismiss()
            } label: {
                Text(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func inviteSymbol(
        systemImage: String,
        tint: Color? = nil
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .background((tint ?? accent).gradient, in: Circle())
            .shadow(color: (tint ?? accent).opacity(0.18), radius: 18, y: 8)
    }

    private var loadKey: String {
        "\(route.token):\(sessionStore.signedInUserID?.uuidString.lowercased() ?? "guest")"
    }

    private func loadPreviewIfNeeded(force: Bool = false) async {
        guard sessionStore.isSignedIn else { return }
        guard force || preview == nil || errorMessage != nil else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            preview = try await familyContextStore.previewInvite(
                token: route.token,
                sessionStore: sessionStore
            )
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func accept(_ preview: FamilyInvitePreviewRecord) async {
        isAccepting = true
        defer { isAccepting = false }

        let didJoin = await familyContextStore.acceptInvite(
            token: route.token,
            sessionStore: sessionStore
        )

        if didJoin {
            self.preview = preview
            didAccept = true
        } else {
            errorMessage = familyContextStore.lastErrorMessage
            await loadPreviewIfNeeded(force: true)
        }
    }

    private func message(for status: FamilyInviteStatus) -> String {
        switch status {
        case .pending:
            return ""
        case .accepted:
            return mistiaLocalized(
                vi: "Lời mời này đã được sử dụng.",
                en: "This invite has already been used.",
                ja: "この招待はすでに使用されています。"
            )
        case .expired:
            return mistiaLocalized(
                vi: "Lời mời đã hết hạn. Vui lòng yêu cầu người mời gửi lại link mới.",
                en: "This invite has expired. Please ask the inviter to send a new link.",
                ja: "この招待は期限切れです。招待者に新しいリンクを送ってもらってください。"
            )
        case .revoked:
            return mistiaLocalized(
                vi: "Lời mời này đã bị thu hồi.",
                en: "This invite has been revoked.",
                ja: "この招待は取り消されました。"
            )
        case .invalid:
            return mistiaLocalized(
                vi: "Lời mời này không còn hợp lệ.",
                en: "This invite is no longer valid.",
                ja: "この招待は無効です。"
            )
        }
    }
}

private struct FamilyInviteFactRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MistiaAccent.purple.color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private extension FamilyRole {
    var inviteTitle: String {
        switch self {
        case .owner:
            return mistiaLocalized(vi: "Chủ sở hữu", en: "Owner", ja: "Owner")
        case .member:
            return mistiaLocalized(vi: "Thành viên", en: "Member", ja: "Member")
        case .kid:
            return mistiaLocalized(vi: "Trẻ em", en: "Kid", ja: "Kid")
        }
    }

    var permissionSummaries: [String] {
        switch self {
        case .owner:
            return [
                mistiaLocalized(vi: "Có thể quản lý gia đình và lời mời.", en: "Can manage the family and invites.", ja: "家族と招待を管理できます。"),
                mistiaLocalized(vi: "Có thể quản lý role và quyền của thành viên.", en: "Can manage member roles and permissions.", ja: "メンバーの役割と権限を管理できます。"),
                mistiaLocalized(vi: "Dữ liệu tài chính vẫn được kiểm tra theo quyền cụ thể.", en: "Financial data still follows explicit permissions.", ja: "金融データは個別の権限に従います。")
            ]
        case .member:
            return [
                mistiaLocalized(vi: "Có thể dùng không gian gia đình theo quyền được cấp.", en: "Can use the family space based on granted permissions.", ja: "付与された権限に応じて家族スペースを利用できます。"),
                mistiaLocalized(vi: "Mặc định không xem ví riêng của người khác.", en: "Does not see others' private wallets by default.", ja: "初期状態では他の人の個人ウォレットは表示されません。"),
                mistiaLocalized(vi: "Có thể được owner cấp thêm quyền cụ thể.", en: "Can receive additional permissions from an owner.", ja: "所有者から追加権限を付与できます。")
            ]
        case .kid:
            return [
                mistiaLocalized(vi: "Mặc định không xem dữ liệu của thành viên khác.", en: "Cannot view other members' data by default.", ja: "初期状態では他のメンバーのデータを表示できません。"),
                mistiaLocalized(vi: "Một số thao tác có thể bị giới hạn.", en: "Some actions may be limited.", ja: "一部の操作が制限される場合があります。"),
                mistiaLocalized(vi: "Phụ huynh hoặc owner có thể quản lý quyền.", en: "A parent or owner can manage permissions.", ja: "保護者または所有者が権限を管理できます。")
            ]
        }
    }
}
