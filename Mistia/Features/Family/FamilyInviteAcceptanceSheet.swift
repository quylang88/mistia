import SwiftUI

struct FamilyInviteAcceptanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    let route: FamilyInviteRoute

    @State private var preview: FamilyInvitePreviewRecord?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var isOpeningAccount = false
    @State private var showsAccount = false
    @State private var showsDeclineCallout = false

    private var accent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    var body: some View {
        inviteModal
            .interactiveDismissDisabled()
    }

    private var inviteModal: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        if sessionStore.isSignedIn {
                            signedInContent
                        } else {
                            signInRequiredContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: loadKey) {
                await loadPreviewIfNeeded()
            }
            .onChange(of: sessionStore.signedInUserID) { _, newValue in
                if newValue != nil {
                    isOpeningAccount = false
                    showsAccount = false
                    Task { await loadPreviewIfNeeded(force: true) }
                }
            }
            .sheet(isPresented: $showsAccount, onDismiss: {
                if !sessionStore.isSignedIn {
                    isOpeningAccount = false
                }
            }) {
                NavigationStack {
                    ManagementAccountView()
                }
            }
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if isLoading {
            loadingContent
        } else if let preview {
            previewContent(preview)
        } else {
            unavailableContent(
                title: offlineTitle,
                message: errorMessage ?? offlineMessage,
                systemImage: isOfflineError ? "wifi.slash" : "exclamationmark.triangle.fill",
                tint: isOfflineError ? .orange : .red,
                clearsPendingInvite: !isOfflineError
            )
        }
    }

    private var signInRequiredContent: some View {
        FamilyInviteGlassSurface(cornerRadius: 30, tint: accent.opacity(0.10), padding: 22) {
            VStack(spacing: 18) {
                FamilyInviteSymbol(systemImage: "person.crop.circle.badge.plus", tint: accent)

                VStack(spacing: 8) {
                    Text(mistiaLocalized(
                        vi: "Đăng nhập để xem lời mời",
                        en: "Sign in to view this invite",
                        ja: "招待を確認するにはログイン"
                    ))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                    Text(mistiaLocalized(
                        vi: "Mistia sẽ giữ lời mời này và tự mở lại sau khi bạn đăng nhập.",
                        en: "Mistia will keep this invite and reopen it after you sign in.",
                        ja: "ログイン後、この招待を自動で再開します。"
                    ))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                FamilyInviteActionButton(
                    title: mistiaLocalized(vi: "Đăng nhập ngay", en: "Sign in now", ja: "今すぐログイン"),
                    systemImage: "person.crop.circle",
                    style: .primary(accent),
                    isLoading: isOpeningAccount
                ) {
                    guard !isOpeningAccount else { return }
                    isOpeningAccount = true
                    showsAccount = true
                }
            }
        }
    }

    private var loadingContent: some View {
        FamilyInviteGlassSurface(cornerRadius: 30, tint: accent.opacity(0.10), padding: 24) {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(accent)

                Text(mistiaLocalized(vi: "Đang kiểm tra lời mời", en: "Checking invite", ja: "招待を確認中"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: FamilyInvitePreviewRecord) -> some View {
        if preview.inviterUserID == sessionStore.signedInUserID {
            unavailableContent(
                title: mistiaLocalized(
                    vi: "Link này không dành cho bạn",
                    en: "This link is not for you",
                    ja: "このリンクは利用できません"
                ),
                message: mistiaLocalized(
                    vi: "Bạn là người tạo lời mời này. Hãy gửi link cho thành viên cần tham gia.",
                    en: "You created this invite. Send the link to the person who should join.",
                    ja: "この招待を作成したアカウントです。参加する相手にリンクを共有してください。"
                ),
                systemImage: "link.badge.plus",
                tint: .orange
            )
        } else if preview.alreadyMemberOfFamily {
            unavailableContent(
                title: mistiaLocalized(vi: "Bạn đã là thành viên", en: "Already a member", ja: "すでにメンバーです"),
                message: mistiaLocalized(
                    vi: "Tài khoản này đã thuộc gia đình \(preview.familyName).",
                    en: "This account already belongs to \(preview.familyName).",
                    ja: "このアカウントはすでに \(preview.familyName) に参加しています。"
                ),
                systemImage: "checkmark.circle.fill",
                tint: .mint
            )
        } else if preview.belongsToAnotherFamily {
            unavailableContent(
                title: mistiaLocalized(
                    vi: "Đang ở gia đình khác",
                    en: "Already in another family",
                    ja: "別の家族に参加中"
                ),
                message: mistiaLocalized(
                    vi: "Tài khoản này hiện đã thuộc một gia đình khác. Vui lòng rời gia đình hiện tại trước khi tham gia gia đình mới.",
                    en: "This account currently belongs to another family. Please leave the current family before joining a new one.",
                    ja: "このアカウントは現在別の家族に参加しています。新しい家族に参加する前に現在の家族から退出してください。"
                ),
                systemImage: "person.2.slash",
                tint: .orange
            )
        } else if preview.status != .pending {
            unavailableContent(
                title: title(for: preview.status),
                message: message(for: preview.status),
                systemImage: systemImage(for: preview.status),
                tint: tint(for: preview.status)
            )
        } else {
            welcomeContent(preview)
        }
    }

    private func welcomeContent(_ preview: FamilyInvitePreviewRecord) -> some View {
        VStack(spacing: 14) {
            FamilyInviteGlassSurface(cornerRadius: 30, tint: accent.opacity(0.10), padding: 22) {
                VStack(spacing: 18) {
                    FamilyInviteSymbol(systemImage: "person.3.fill", tint: accent)

                    VStack(spacing: 8) {
                        Text(mistiaLocalized(
                            vi: "Tham gia \(preview.familyName)",
                            en: "Join \(preview.familyName)",
                            ja: "\(preview.familyName) に参加"
                        ))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                        Text(mistiaLocalized(
                            vi: "\(preview.inviterName) đã mời bạn vào gia đình trên Mistia.",
                            en: "\(preview.inviterName) invited you to join this Mistia family.",
                            ja: "\(preview.inviterName) さんがMistiaの家族に招待しました。"
                        ))
                        .font(.system(size: 15.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        FamilyInviteFactRow(
                            title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
                            value: preview.familyName,
                            systemImage: "person.3"
                        )
                        Divider().padding(.leading, 54)
                        FamilyInviteFactRow(
                            title: mistiaLocalized(vi: "Người mời", en: "Inviter", ja: "招待者"),
                            value: preview.inviterName,
                            systemImage: "person.crop.circle"
                        )
                        Divider().padding(.leading, 54)
                        FamilyInviteFactRow(
                            title: mistiaLocalized(vi: "Vai trò", en: "Role", ja: "役割"),
                            value: preview.role.inviteTitle,
                            systemImage: "person.badge.key"
                        )
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }

            permissionSection(for: preview.role)
            privacySection(for: preview.role)
            actionsSection(preview)
        }
    }

    private func permissionSection(for role: FamilyRole) -> some View {
        FamilyInviteGlassSurface(cornerRadius: 24, tint: accent.opacity(0.06), padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    mistiaLocalized(vi: "Quyền khi tham gia", en: "Access after joining", ja: "参加後の権限"),
                    systemImage: "checkmark.shield.fill"
                )
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(role.permissionSummaries, id: \.self) { summary in
                        Label(summary, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func privacySection(for role: FamilyRole) -> some View {
        FamilyInviteGlassSurface(cornerRadius: 24, tint: Color.orange.opacity(role == .kid ? 0.14 : 0.08), padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    mistiaLocalized(vi: "Dữ liệu vẫn theo quyền", en: "Data still follows permissions", ja: "データは権限に従います"),
                    systemImage: "lock.shield.fill"
                )
                .font(.system(size: 16, weight: .bold, design: .rounded))

                Text(mistiaLocalized(
                    vi: "Tham gia gia đình không đồng nghĩa với toàn quyền xem hay sửa dữ liệu của nhau. Quyền xem và thao tác vẫn do owner cấp rõ ràng.",
                    en: "Joining a family does not grant full access to everyone's data. View and edit access still depends on explicit owner permissions.",
                    ja: "家族に参加しても全員のデータを自由に見たり編集したりできるわけではありません。表示と操作の権限は owner が明示的に設定します。"
                ))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionsSection(_ preview: FamilyInvitePreviewRecord) -> some View {
        VStack(spacing: 10) {
            if showsDeclineCallout {
                FamilyInviteDeclineCallout(
                    isDeclining: isDeclining,
                    onCancel: {
                        withAnimation(.snappy) {
                            showsDeclineCallout = false
                        }
                    },
                    onConfirm: {
                        Task { await decline() }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            FamilyInviteActionButton(
                title: mistiaLocalized(vi: "Chấp nhận", en: "Accept", ja: "承認"),
                systemImage: "checkmark",
                style: .primary(accent),
                isLoading: isAccepting,
                isDisabled: isDeclining
            ) {
                Task { await accept(preview) }
            }

            FamilyInviteActionButton(
                title: mistiaLocalized(vi: "Từ chối", en: "Decline", ja: "辞退"),
                systemImage: "xmark",
                style: .secondary(.red),
                isDisabled: isAccepting || isDeclining
            ) {
                withAnimation(.snappy) {
                    showsDeclineCallout = true
                }
            }
        }
    }

    private func unavailableContent(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        clearsPendingInvite: Bool = true
    ) -> some View {
        FamilyInviteGlassSurface(cornerRadius: 30, tint: tint.opacity(0.10), padding: 22) {
            VStack(spacing: 18) {
                FamilyInviteSymbol(systemImage: systemImage, tint: tint)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FamilyInviteActionButton(
                    title: mistiaLocalized(vi: "Đồng ý", en: "OK", ja: "OK"),
                    systemImage: "checkmark",
                    style: .primary(accent)
                ) {
                    if clearsPendingInvite {
                        familyContextStore.clearPendingInvite()
                    } else {
                        familyContextStore.dismissPendingInviteForNow()
                    }
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var loadKey: String {
        "\(route.token):\(sessionStore.signedInUserID?.uuidString.lowercased() ?? "guest")"
    }

    private var isOfflineError: Bool {
        guard let errorMessage else {
            return sessionStore.isOfflineModeActive
        }
        return sessionStore.isOfflineModeActive
            || errorMessage == sessionStore.remoteUnavailableReason
            || errorMessage.localizedCaseInsensitiveContains("offline")
            || errorMessage.localizedCaseInsensitiveContains("network")
            || errorMessage.localizedCaseInsensitiveContains("kết nối")
    }

    private var offlineTitle: String {
        isOfflineError
            ? mistiaLocalized(vi: "Không có kết nối", en: "No connection", ja: "接続がありません")
            : mistiaLocalized(vi: "Lời mời không khả dụng", en: "Invite unavailable", ja: "招待を利用できません")
    }

    private var offlineMessage: String {
        sessionStore.remoteUnavailableReason ?? mistiaLocalized(
            vi: "Không thể kiểm tra lời mời lúc này.",
            en: "Mistia can't check this invite right now.",
            ja: "現在この招待を確認できません。"
        )
    }

    private func loadPreviewIfNeeded(force: Bool = false) async {
        guard sessionStore.isSignedIn else { return }
        guard force || preview == nil || errorMessage != nil else { return }

        isLoading = true
        errorMessage = nil
        showsDeclineCallout = false
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
        guard !isAccepting else { return }

        isAccepting = true
        showsDeclineCallout = false
        defer { isAccepting = false }

        let didJoin = await familyContextStore.acceptInvite(
            token: route.token,
            sessionStore: sessionStore
        )

        if didJoin {
            self.preview = preview
            familyContextStore.activateFamilyHome()
            let acceptedFamilyID = familyContextStore.family?.id
            familyContextStore.clearPendingInvite()
            dismiss()
            if let acceptedFamilyID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    familyContextStore.requestFamilyOverviewPresentation(familyID: acceptedFamilyID)
                }
            }
        } else {
            errorMessage = familyContextStore.lastErrorMessage
            await loadPreviewIfNeeded(force: true)
        }
    }

    private func decline() async {
        guard !isDeclining else { return }

        isDeclining = true
        defer { isDeclining = false }

        let didDecline = await familyContextStore.declineInvite(
            token: route.token,
            sessionStore: sessionStore
        )

        if didDecline {
            dismiss()
        } else {
            showsDeclineCallout = false
            errorMessage = familyContextStore.lastErrorMessage
            await loadPreviewIfNeeded(force: true)
        }
    }

    private func title(for status: FamilyInviteStatus) -> String {
        switch status {
        case .pending:
            return ""
        case .accepted:
            return mistiaLocalized(vi: "Lời mời đã được dùng", en: "Invite already used", ja: "招待は使用済みです")
        case .declined:
            return mistiaLocalized(vi: "Lời mời đã bị từ chối", en: "Invite declined", ja: "招待は辞退済みです")
        case .expired:
            return mistiaLocalized(vi: "Lời mời đã hết hạn", en: "Invite expired", ja: "招待の期限が切れました")
        case .revoked:
            return mistiaLocalized(vi: "Lời mời đã bị thu hồi", en: "Invite revoked", ja: "招待は取り消されました")
        case .invalid:
            return mistiaLocalized(vi: "Lời mời không hợp lệ", en: "Invite invalid", ja: "招待は無効です")
        }
    }

    private func message(for status: FamilyInviteStatus) -> String {
        switch status {
        case .pending:
            return ""
        case .accepted:
            return mistiaLocalized(
                vi: "Link này đã được sử dụng. Hãy yêu cầu owner gửi lời mời mới nếu cần.",
                en: "This link has already been used. Ask the owner for a new invite if needed.",
                ja: "このリンクはすでに使用されています。必要な場合は owner に新しい招待を依頼してください。"
            )
        case .declined:
            return mistiaLocalized(
                vi: "Bạn đã từ chối lời mời này. Owner cần tạo link mới nếu muốn mời lại.",
                en: "This invite has been declined. The owner needs to create a new link to invite again.",
                ja: "この招待は辞退されています。再招待するには owner が新しいリンクを作成する必要があります。"
            )
        case .expired:
            return mistiaLocalized(
                vi: "Link này đã hết hạn. Vui lòng yêu cầu người mời gửi lại link mới.",
                en: "This link has expired. Please ask the inviter to send a new link.",
                ja: "このリンクは期限切れです。招待者に新しいリンクを送ってもらってください。"
            )
        case .revoked:
            return mistiaLocalized(
                vi: "Owner đã thu hồi lời mời này.",
                en: "The owner revoked this invite.",
                ja: "owner がこの招待を取り消しました。"
            )
        case .invalid:
            return mistiaLocalized(
                vi: "Link này không còn hợp lệ.",
                en: "This link is no longer valid.",
                ja: "このリンクは無効です。"
            )
        }
    }

    private func systemImage(for status: FamilyInviteStatus) -> String {
        switch status {
        case .pending:
            return "person.3.fill"
        case .accepted:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        case .expired:
            return "clock.badge.exclamationmark"
        case .revoked:
            return "link.badge.minus"
        case .invalid:
            return "exclamationmark.triangle.fill"
        }
    }

    private func tint(for status: FamilyInviteStatus) -> Color {
        switch status {
        case .pending:
            return accent
        case .accepted:
            return .mint
        case .declined, .revoked, .invalid:
            return .red
        case .expired:
            return .orange
        }
    }
}

private struct FamilyInviteGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color
    let padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat,
        tint: Color,
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                FamilyInviteGlassBackground(cornerRadius: cornerRadius, tint: tint)
            }
    }
}

private struct FamilyInviteGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(baseFill)

            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular.tint(tint),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderFill, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 20, y: 10)
    }

    private var baseFill: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemGroupedBackground).opacity(0.96)
            : Color.white.opacity(0.86)
    }

    private var borderFill: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.48)
    }
}

private struct FamilyInviteSymbol: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.13))

            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular.tint(tint.opacity(0.12)),
                        in: .circle
                    )
            }

            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 76, height: 76)
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.44), lineWidth: 0.8)
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
                .frame(width: 30, height: 30)
                .background(MistiaAccent.purple.color.opacity(0.10), in: Circle())

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

private enum FamilyInviteActionButtonStyle {
    case primary(Color)
    case secondary(Color)
    case destructive
}

private struct FamilyInviteActionButton: View {
    let title: String
    let systemImage: String?
    let style: FamilyInviteActionButtonStyle
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        style: FamilyInviteActionButtonStyle,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(backgroundFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderFill, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.55 : 1)
        .animation(.snappy, value: isLoading)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary(let tint):
            return tint
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .primary(let tint):
            return tint
        case .secondary(let tint):
            return tint.opacity(0.10)
        case .destructive:
            return .red
        }
    }

    private var borderFill: Color {
        switch style {
        case .primary:
            return .white.opacity(0.16)
        case .secondary(let tint):
            return tint.opacity(0.22)
        case .destructive:
            return .white.opacity(0.16)
        }
    }
}

private struct FamilyInviteDeclineCallout: View {
    let isDeclining: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FamilyInviteGlassSurface(cornerRadius: 22, tint: Color.red.opacity(0.10), padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        mistiaLocalized(vi: "Từ chối lời mời?", en: "Decline this invite?", ja: "この招待を辞退しますか？"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)

                    Text(mistiaLocalized(
                        vi: "Sau khi từ chối, link này sẽ không dùng lại được. Owner cần tạo lời mời mới nếu muốn mời lại.",
                        en: "After declining, this link cannot be used again. The owner needs to create a new invite to invite again.",
                        ja: "辞退すると、このリンクは再利用できません。再招待するには owner が新しい招待を作成する必要があります。"
                    ))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        FamilyInviteActionButton(
                            title: mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"),
                            style: .secondary(.secondary),
                            isDisabled: isDeclining,
                            action: onCancel
                        )

                        FamilyInviteActionButton(
                            title: mistiaLocalized(vi: "Từ chối", en: "Decline", ja: "辞退"),
                            style: .destructive,
                            isLoading: isDeclining,
                            action: onConfirm
                        )
                    }
                }
            }

            FamilyInviteCalloutArrow()
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .frame(width: 22, height: 11)
                .padding(.trailing, 54)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct FamilyInviteCalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
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
