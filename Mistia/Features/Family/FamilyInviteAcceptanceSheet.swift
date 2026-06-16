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
    @State private var pendingResponseAction: FamilyInviteResponseAction?

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
        centeredContent(maxWidth: 430) {
            VStack(spacing: 24) {
                Spacer(minLength: 36)

                FamilyInviteStatusSymbol(systemImage: "person.crop.circle.badge.plus", tint: accent)

                VStack(spacing: 9) {
                    Text(L10n.family.familyinviteacceptance.signInToViewThisInvite)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                    Text(L10n.family.familyinviteacceptance.mistiaWillKeepThisInviteAndReopen)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                FamilyInviteActionButton(
                    title: L10n.family.familyinviteacceptance.signInNow,
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

                Text(L10n.family.familyinviteacceptance.checkingInvite)
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
                title: L10n.family.familyinviteacceptance.notForYou,
                message: L10n.family.familyinviteacceptance.youCreatedThisInvite,
                systemImage: "link.badge.plus",
                tint: .orange
            )
        } else if preview.alreadyMemberOfFamily {
            unavailableContent(
                title: L10n.family.familyinviteacceptance.alreadyJoined,
                message: L10n.family.familyinviteacceptance.thisAccountIsAlreadyInValue(String(describing: preview.familyName)),
                systemImage: "checkmark.circle.fill",
                tint: .mint
            )
        } else if preview.belongsToAnotherFamily {
            unavailableContent(
                title: L10n.family.familyinviteacceptance.anotherFamily,
                message: L10n.family.familyinviteacceptance.thisAccountCurrentlyBelongsToAnotherFamily,
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
        HStack(spacing: 12) {
            FamilyInviteActionButton(
                title: L10n.family.familyinviteacceptance.accept,
                systemImage: "checkmark",
                style: .primary(accent),
                isLoading: isAccepting,
                isDisabled: isDeclining
            ) {
                presentResponseAction(.accept)
            }

            FamilyInviteActionButton(
                title: L10n.family.familyinviteacceptance.decline,
                systemImage: "xmark",
                style: .secondary(.red),
                isDisabled: isAccepting || isDeclining
            ) {
                presentResponseAction(.decline)
            }
        }
        .overlay {
            if pendingResponseAction != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissResponseMenu()
                    }
                    .allowsHitTesting(!isAccepting && !isDeclining)
            }
        }
        .overlay(alignment: .bottom) {
            if let pendingResponseAction {
                FamilyInviteResponseMenu(
                    action: pendingResponseAction,
                    accent: accent,
                    isLoading: isAccepting || isDeclining,
                    onConfirm: {
                        switch pendingResponseAction {
                        case .accept:
                            Task { await accept(preview) }
                        case .decline:
                            Task { await decline() }
                        }
                    }
                )
                .padding(.bottom, 62)
                .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: pendingResponseAction)
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
                    title: L10n.family.familyinviteacceptance.ok,
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
            ? L10n.family.familyinviteacceptance.offline
            : L10n.family.familyinviteacceptance.unavailable
    }

    private var offlineMessage: String {
        sessionStore.remoteUnavailableReason ?? L10n.family.familyinviteacceptance.mistiaCanTCheckThisInviteRight
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
        pendingResponseAction = nil
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
        pendingResponseAction = nil
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
            pendingResponseAction = nil
            errorMessage = familyContextStore.lastErrorMessage
            await loadPreviewIfNeeded(force: true)
        }
    }

    private func presentResponseAction(_ action: FamilyInviteResponseAction) {
        guard !isAccepting, !isDeclining else { return }
        withAnimation(.snappy) {
            pendingResponseAction = pendingResponseAction == action ? nil : action
        }
    }

    private func dismissResponseMenu() {
        guard !isAccepting, !isDeclining else { return }
        withAnimation(.snappy) {
            pendingResponseAction = nil
        }
    }

    private func title(for status: FamilyInviteStatus) -> String {
        switch status {
        case .pending:
            return ""
        case .accepted:
            return L10n.family.familyinviteacceptance.alreadyUsed
        case .declined:
            return L10n.family.familyinviteacceptance.declined
        case .expired:
            return L10n.family.familyinviteacceptance.expired
        case .revoked:
            return L10n.family.familyinviteacceptance.revoked
        case .invalid:
            return L10n.family.familyinviteacceptance.invalid
        }
    }

    private func message(for status: FamilyInviteStatus) -> String {
        switch status {
        case .pending:
            return ""
        case .accepted:
            return L10n.family.familyinviteacceptance.thisLinkHasAlreadyBeenUsed
        case .declined:
            return L10n.family.familyinviteacceptance.theOwnerNeedsToCreateANew
        case .expired:
            return L10n.family.familyinviteacceptance.pleaseAskTheInviterToSendA
        case .revoked:
            return L10n.family.familyinviteacceptance.theOwnerRevokedThisInvite
        case .invalid:
            return L10n.family.familyinviteacceptance.thisLinkIsNoLongerValid
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
                Text(L10n.family.familyinviteacceptance.toTheFamily)
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

private enum FamilyInviteResponseAction: Equatable {
    case accept
    case decline

    var title: String {
        switch self {
        case .accept:
            return L10n.family.familyinviteacceptance.acceptThisInvite
        case .decline:
            return L10n.family.familyinviteacceptance.declineThisInvite
        }
    }

    var message: String {
        switch self {
        case .accept:
            return L10n.family.familyinviteacceptance.youWillJoinThisFamilyAfterConfirming
        case .decline:
            return L10n.family.familyinviteacceptance.thisLinkCannotBeUsedAgain
        }
    }

    var confirmTitle: String {
        switch self {
        case .accept:
            return L10n.family.familyinviteacceptance.accept
        case .decline:
            return L10n.family.familyinviteacceptance.decline
        }
    }

    var systemImage: String {
        switch self {
        case .accept:
            return "checkmark"
        case .decline:
            return "xmark"
        }
    }

    func tint(accent: Color) -> Color {
        switch self {
        case .accept:
            return accent
        case .decline:
            return .red
        }
    }

    func buttonStyle(accent: Color) -> FamilyInviteActionButtonStyle {
        switch self {
        case .accept:
            return .primary(accent)
        case .decline:
            return .destructive
        }
    }
}

private enum FamilyInviteActionButtonStyle {
    case primary(Color)
    case secondary(Color)
    case destructive
}

private struct FamilyInviteActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

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
            .background {
                Capsule()
                    .fill(backgroundFill)

                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(nativeGlassStyle, in: .capsule)
                }
            }
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

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        let tintOpacity: Double
        switch style {
        case .primary:
            tintOpacity = colorScheme == .dark ? 0.30 : 0.42
        case .secondary:
            tintOpacity = colorScheme == .dark ? 0.16 : 0.22
        case .destructive:
            tintOpacity = colorScheme == .dark ? 0.28 : 0.38
        }

        var glass = Glass.regular.tint(backgroundFill.opacity(tintOpacity))
        if !isDisabled && !isLoading {
            glass = glass.interactive(true)
        }
        return glass
    }
}

private struct FamilyInviteResponseMenu: View {
    let action: FamilyInviteResponseAction
    let accent: Color
    let isLoading: Bool
    let onConfirm: () -> Void

    var body: some View {
        FamilyInviteGlassSurface(cornerRadius: 22, tint: action.tint(accent: accent).opacity(0.12), padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(action.tint(accent: accent))

                    Text(action.message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FamilyInviteActionButton(
                    title: action.confirmTitle,
                    systemImage: action.systemImage,
                    style: action.buttonStyle(accent: accent),
                    isLoading: isLoading,
                    action: onConfirm
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}
