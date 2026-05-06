import SwiftUI

struct FamilyInviteAcceptanceScreen: View {
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
        inviteScreen
            .interactiveDismissDisabled()
    }

    private var inviteScreen: some View {
        NavigationStack {
            ZStack {
                FamilyInviteScreenBackground(accent: accent, showsWelcome: showsWelcomeBackground)
                    .ignoresSafeArea()

                if sessionStore.isSignedIn {
                    signedInContent
                } else {
                    signInRequiredContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
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
        centeredContent(maxWidth: 430) {
            VStack(spacing: 24) {
                Spacer(minLength: 36)

                FamilyInviteStatusSymbol(systemImage: "person.crop.circle.badge.plus", tint: accent)

                VStack(spacing: 9) {
                    Text(mistiaLocalized(
                        vi: "Đăng nhập để xem lời mời",
                        en: "Sign in to view this invite",
                        ja: "招待を確認するにはログイン"
                    ))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
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

                Spacer(minLength: 36)
            }
        }
    }

    private var loadingContent: some View {
        centeredContent(maxWidth: 360) {
            VStack(spacing: 16) {
                Spacer(minLength: 36)

                ProgressView()
                    .controlSize(.large)
                    .tint(accent)

                Text(mistiaLocalized(vi: "Đang kiểm tra lời mời", en: "Checking invite", ja: "招待を確認中"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 36)
            }
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
                    vi: "Bạn là người tạo lời mời này.",
                    en: "You created this invite.",
                    ja: "この招待を作成したアカウントです。"
                ),
                systemImage: "link.badge.plus",
                tint: .orange
            )
        } else if preview.alreadyMemberOfFamily {
            unavailableContent(
                title: mistiaLocalized(vi: "Bạn đã là thành viên", en: "Already a member", ja: "すでにメンバーです"),
                message: mistiaLocalized(
                    vi: "Tài khoản này đã ở trong \(preview.familyName).",
                    en: "This account is already in \(preview.familyName).",
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
                    vi: "Tài khoản này đang thuộc một gia đình khác.",
                    en: "This account currently belongs to another family.",
                    ja: "このアカウントは現在別の家族に参加しています。"
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
        centeredContent(maxWidth: 520) {
            VStack(spacing: 28) {
                Spacer(minLength: 36)

                FamilyInviteWelcomeStage(
                    familyName: preview.familyName,
                    accent: accent
                )

                Spacer(minLength: 24)

                actionsSection(preview)
            }
        }
    }

    private func actionsSection(_ preview: FamilyInvitePreviewRecord) -> some View {
        VStack(spacing: 12) {
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

            HStack(spacing: 12) {
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
    }

    private func unavailableContent(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        clearsPendingInvite: Bool = true
    ) -> some View {
        centeredContent(maxWidth: 430) {
            VStack(spacing: 24) {
                Spacer(minLength: 36)

                FamilyInviteStatusSymbol(systemImage: systemImage, tint: tint)

                VStack(spacing: 9) {
                    Text(title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
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

                Spacer(minLength: 36)
            }
        }
    }

    private func centeredContent<Content: View>(
        maxWidth: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: maxWidth)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Swift.max(0, proxy.size.height - 32))
            }
            .scrollIndicators(.hidden)
        }
    }

    private var loadKey: String {
        "\(route.token):\(sessionStore.signedInUserID?.uuidString.lowercased() ?? "guest")"
    }

    private var showsWelcomeBackground: Bool {
        guard sessionStore.isSignedIn, !isLoading, let preview else { return false }
        return canRespond(to: preview)
    }

    private var navigationTitle: String {
        if !sessionStore.isSignedIn {
            return mistiaLocalized(vi: "Cần đăng nhập", en: "Sign in required", ja: "ログインが必要")
        }

        if isLoading {
            return mistiaLocalized(vi: "Lời mời gia đình", en: "Family invite", ja: "家族への招待")
        }

        if let preview, canRespond(to: preview) {
            return mistiaLocalized(vi: "Chào mừng", en: "Welcome", ja: "ようこそ")
        }

        if isOfflineError {
            return mistiaLocalized(vi: "Lỗi kết nối", en: "Connection error", ja: "接続エラー")
        }

        return mistiaLocalized(vi: "Lỗi lời mời", en: "Invite error", ja: "招待エラー")
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

    private func canRespond(to preview: FamilyInvitePreviewRecord) -> Bool {
        preview.status == .pending
            && preview.inviterUserID != sessionStore.signedInUserID
            && !preview.alreadyMemberOfFamily
            && !preview.belongsToAnotherFamily
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
                vi: "Link này đã được sử dụng.",
                en: "This link has already been used.",
                ja: "このリンクはすでに使用されています。"
            )
        case .declined:
            return mistiaLocalized(
                vi: "Owner cần tạo link mới nếu muốn mời lại.",
                en: "The owner needs to create a new link to invite again.",
                ja: "再招待するには owner が新しいリンクを作成する必要があります。"
            )
        case .expired:
            return mistiaLocalized(
                vi: "Vui lòng yêu cầu người mời gửi lại link mới.",
                en: "Please ask the inviter to send a new link.",
                ja: "招待者に新しいリンクを送ってもらってください。"
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

private struct FamilyInviteScreenBackground: View {
    let accent: Color
    let showsWelcome: Bool

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)

            if showsWelcome {
                LinearGradient(
                    colors: [
                        accent.opacity(0.16),
                        MistiaAccent.sky.color.opacity(0.12),
                        MistiaAccent.coral.color.opacity(0.10),
                        Color(UIColor.systemBackground).opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showsWelcome)
    }
}

private struct FamilyInviteWelcomeStage: View {
    let familyName: String
    let accent: Color

    var body: some View {
        VStack(spacing: 22) {
            FamilyInviteAnimatedGreeting(accent: accent)

            VStack(spacing: 8) {
                Text(mistiaLocalized(vi: "đến với gia đình", en: "to the family", ja: "ファミリーへ"))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(familyName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FamilyInviteAnimatedGreeting: View {
    let accent: Color

    @State private var greetingIndex = 0
    @State private var breathes = false

    private let greetings = ["Welcome", "Chào mừng", "ようこそ"]

    var body: some View {
        Text(greetings[greetingIndex])
            .font(.system(size: 62, weight: .semibold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [accent, MistiaAccent.sky.color, MistiaAccent.coral.color],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.46)
            .scaleEffect(breathes ? 1.02 : 0.98)
            .id(greetingIndex)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.88).combined(with: .opacity),
                removal: .scale(scale: 1.08).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: breathes)
            .task {
                breathes = true
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_650_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                        greetingIndex = (greetingIndex + 1) % greetings.count
                    }
                }
            }
    }
}

private struct FamilyInviteStatusSymbol: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.12))

            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular.tint(tint.opacity(0.12)),
                        in: .circle
                    )
            }

            Image(systemName: systemImage)
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 78, height: 78)
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.46), lineWidth: 0.8)
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
            : Color.white.opacity(0.88)
    }

    private var borderFill: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.48)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
            .padding(.horizontal, 16)
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
                        vi: "Link này sẽ không dùng lại được.",
                        en: "This link cannot be used again.",
                        ja: "このリンクは再利用できません。"
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
