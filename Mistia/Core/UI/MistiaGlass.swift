import SwiftUI

enum MistiaBackgroundTone {
    case standard
    case muted
}

struct MistiaBackgroundView: View {
    var tone: MistiaBackgroundTone = .standard
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                backgroundColor
                    .backgroundExtensionEffect()
            } else {
                backgroundColor
            }
        }
        .ignoresSafeArea()
    }

    private var backgroundColor: Color {
        switch (tone, colorScheme) {
        case (.standard, .dark):
            Color.black
        case (.standard, .light):
            Color(red: 0.96, green: 0.96, blue: 0.98)
        case (.muted, .dark):
            Color.black
        case (.muted, .light):
            Color(red: 0.97, green: 0.97, blue: 0.98)
        @unknown default:
            Color(red: 0.96, green: 0.96, blue: 0.98)
        }
    }
}

struct MistiaPressableButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16
    var tint: Color = Color(red: 0.43, green: 0.23, blue: 0.76)
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? tint.opacity(colorScheme == .dark ? 0.16 : 0.08) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        tint.opacity(configuration.isPressed ? (colorScheme == .dark ? 0.22 : 0.14) : 0),
                        lineWidth: 0.8
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
            .hoverEffect(.highlight)
    }
}

struct MistiaAvatarBadge: View {
    var initials: String = "QL"
    var avatarURL: URL?
    var size: CGFloat = 34
    var showsStatus: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var ringColor: Color {
        colorScheme == .dark ? .white.opacity(0.24) : .white.opacity(0.72)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackAvatar
                        }
                    }
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(ringColor, lineWidth: 0.9)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: size * 0.16, y: size * 0.08)

            if showsStatus {
                Circle()
                    .fill(Color(red: 0.53, green: 0.93, blue: 0.78))
                    .frame(width: size * 0.24, height: size * 0.24)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                colorScheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : .white,
                                lineWidth: 2
                            )
                    }
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.49, green: 0.34, blue: 0.95),
                            Color(red: 0.36, green: 0.50, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.16))
                .padding(size * 0.08)
                .blur(radius: size * 0.02)

            Text(initials)
                .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

struct MistiaGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color
    let interactive: Bool
    let padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat,
        tint: Color = .white.opacity(0.08),
        interactive: Bool = false,
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.interactive = interactive
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                MistiaRoundedGlassBackground(
                    cornerRadius: cornerRadius,
                    tint: tint,
                    interactive: interactive
                )
            }
    }
}

struct MistiaRoundedGlassBackground: View {
    let cornerRadius: CGFloat
    var tint: Color = .white.opacity(0.08)
    var interactive: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    @available(iOS 26, *)
    private var glassStyle: Glass {
        var style = Glass.regular.tint(tint)
        if interactive {
            style = style.interactive(true)
        }
        return style
    }
}

struct MistiaCapsuleGlassBackground: View {
    var tint: Color = .white.opacity(0.08)
    var interactive: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    @available(iOS 26, *)
    private var glassStyle: Glass {
        var style = Glass.regular.tint(tint)
        if interactive {
            style = style.interactive(true)
        }
        return style
    }
}

struct MistiaCircleGlassBackground: View {
    var tint: Color = .white.opacity(0.12)
    var interactive: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    @available(iOS 26, *)
    private var glassStyle: Glass {
        var style = Glass.regular.tint(tint)
        if interactive {
            style = style.interactive(true)
        }
        return style
    }
}

struct MistiaTopBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var showsLeadingAvatar: Bool = true
    var leadingInitials: String = "QL"
    var leadingAvatarURL: URL? = nil
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String? = "bell"
    var onLeadingTap: () -> Void = {}
    var onTrailingTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            leadingAccessory

            Spacer(minLength: 8)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            trailingAccessory
        }
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if let leadingSystemImage {
            MistiaHeaderCircleButton(action: onLeadingTap) {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(headerIconColor)
            }
        } else if showsLeadingAvatar {
            MistiaHeaderCircleButton(action: onLeadingTap) {
                MistiaAvatarBadge(initials: leadingInitials, avatarURL: leadingAvatarURL, size: 28)
            }
        } else {
            Color.clear
                .frame(width: mistiaHeaderCircleSize, height: mistiaHeaderCircleSize)
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if let trailingSystemImage {
            MistiaHeaderCircleButton(action: onTrailingTap) {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(headerIconColor)
            }
        } else {
            Color.clear
                .frame(width: mistiaHeaderCircleSize, height: mistiaHeaderCircleSize)
        }
    }

    private var headerIconColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.72)
    }
}

private let mistiaHeaderCircleSize: CGFloat = 30

struct MistiaCircleGlassButtonLabel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: mistiaHeaderCircleSize, height: mistiaHeaderCircleSize)
            .contentShape(Circle())
    }
}

struct MistiaHeaderCircleButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    MistiaCircleGlassButtonLabel {
                        content
                    }
                }
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    MistiaCircleGlassButtonLabel {
                        content
                    }
                        .background {
                            MistiaCircleGlassBackground(
                                tint: colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.30),
                                interactive: true
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .hoverEffect(.highlight)
        .accessibilityAddTraits(.isButton)
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        Glass.regular
            .interactive()
    }
}

struct MistiaHeaderCircleMenu<Label: View, MenuContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let label: Label
    @ViewBuilder let content: MenuContent

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Menu {
                    content
                } label: {
                    MistiaCircleGlassButtonLabel {
                        label
                    }
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.circle)
            } else {
                Menu {
                    content
                } label: {
                    MistiaCircleGlassButtonLabel {
                        label
                    }
                    .background {
                        MistiaCircleGlassBackground(
                            tint: colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.30),
                            interactive: true
                        )
                    }
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
            }
        }
        .hoverEffect(.highlight)
        .accessibilityAddTraits(.isButton)
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        Glass.regular
            .interactive()
    }
}

private struct MistiaAttentionPulseAvatar: View {
    let initials: String
    let avatarURL: URL?
    let size: CGFloat
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0

    var body: some View {
        MistiaAvatarBadge(initials: initials, avatarURL: avatarURL, size: size)
            .overlay {
                Circle()
                    .strokeBorder(pulseColor.opacity(pulseOpacity), lineWidth: 2.0)
                    .scaleEffect(pulseScale)
                    .allowsHitTesting(false)
            }
            .task(id: "\(isActive)-\(accessibilityReduceMotion)") {
                await runPulseLoop()
            }
    }

    private var pulseColor: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    @MainActor
    private func resetPulse() {
        pulseScale = 1
        pulseOpacity = 0
    }

    private func runPulseLoop() async {
        resetPulse()
        guard isActive, !accessibilityReduceMotion else { return }

        while !Task.isCancelled {
            await MainActor.run {
                pulseScale = 1
                pulseOpacity = 0.85
                withAnimation(.easeOut(duration: 1.6)) {
                    pulseScale = 2.2
                    pulseOpacity = 0
                }
            }

            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            resetPulse()
        }
    }
}

struct MistiaPinnedTopBarScaffold<PinnedHeader: View, Content: View, TrailingAccessory: View>: View {
    enum HeaderBehavior {
        case fixedInset
        case scrollsThenPins
    }

    let tone: MistiaBackgroundTone
    let title: String
    var embedsInNavigationStack: Bool = true
    var showsLeadingAvatar: Bool = true
    var isLeadingEnabled: Bool = true
    var leadingInitials: String = "QL"
    var leadingAvatarURL: URL? = nil
    var leadingAccessibilityLabel: String? = nil
    var leadingAvatarAttentionPulse: Bool = false
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String? = "bell"
    var hidesSystemBackButton: Bool = false
    var onLeadingTap: () -> Void = {}
    var onTrailingTap: () -> Void = {}
    var onRefresh: (() async -> Void)? = nil
    var contentSpacing: CGFloat = 18
    var contentBottomPadding: CGFloat = 150
    var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline
    var headerBehavior: HeaderBehavior = .fixedInset
    @ViewBuilder let pinnedHeader: PinnedHeader
    @ViewBuilder let trailingAccessory: TrailingAccessory
    @ViewBuilder let content: Content

    init(
        tone: MistiaBackgroundTone,
        title: String,
        embedsInNavigationStack: Bool = true,
        showsLeadingAvatar: Bool = true,
        leadingInitials: String = "QL",
        leadingAvatarURL: URL? = nil,
        leadingAccessibilityLabel: String? = nil,
        leadingAvatarAttentionPulse: Bool = false,
        isLeadingEnabled: Bool = true,
        leadingSystemImage: String? = nil,
        trailingSystemImage: String? = "bell",
        hidesSystemBackButton: Bool = false,
        onLeadingTap: @escaping () -> Void = {},
        onTrailingTap: @escaping () -> Void = {},
        onRefresh: (() async -> Void)? = nil,
        contentSpacing: CGFloat = 18,
        contentBottomPadding: CGFloat = 150,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        headerBehavior: HeaderBehavior = .fixedInset,
        @ViewBuilder pinnedHeader: () -> PinnedHeader,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.title = title
        self.embedsInNavigationStack = embedsInNavigationStack
        self.showsLeadingAvatar = showsLeadingAvatar
        self.isLeadingEnabled = isLeadingEnabled
        self.leadingInitials = leadingInitials
        self.leadingAvatarURL = leadingAvatarURL
        self.leadingAccessibilityLabel = leadingAccessibilityLabel
        self.leadingAvatarAttentionPulse = leadingAvatarAttentionPulse
        self.leadingSystemImage = leadingSystemImage
        self.trailingSystemImage = trailingSystemImage
        self.hidesSystemBackButton = hidesSystemBackButton
        self.onLeadingTap = onLeadingTap
        self.onTrailingTap = onTrailingTap
        self.onRefresh = onRefresh
        self.contentSpacing = contentSpacing
        self.contentBottomPadding = contentBottomPadding
        self.titleDisplayMode = titleDisplayMode
        self.headerBehavior = headerBehavior
        self.pinnedHeader = pinnedHeader()
        self.trailingAccessory = trailingAccessory()
        self.content = content()
    }

    var body: some View {
        Group {
            if embedsInNavigationStack {
                NavigationStack {
                    screenContent
                }
            } else {
                screenContent
            }
        }
    }

    private var baseScrollableContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if headerBehavior == .scrollsThenPins, PinnedHeader.self != EmptyView.self {
                LazyVStack(spacing: contentSpacing, pinnedViews: [.sectionHeaders]) {
                    Section {
                        content
                    } header: {
                        pinnedHeader
                            .padding(.horizontal, -18)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, contentBottomPadding)
            } else {
                LazyVStack(spacing: contentSpacing) {
                    content
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, contentBottomPadding)
            }
        }
        .modifier(MistiaTopScrollEdgeEffect())
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var scrollableContent: some View {
        if let onRefresh {
            baseScrollableContent
                .refreshable {
                    await onRefresh()
                }
        } else {
            baseScrollableContent
        }
    }

    private var screenContent: some View {
        ZStack {
            MistiaBackgroundView(tone: tone)

            if PinnedHeader.self != EmptyView.self && headerBehavior == .fixedInset {
                scrollableContent
                    .safeAreaInset(edge: .top) {
                        pinnedHeader
                            .background(.clear)
                            .background(MistiaBackgroundView(tone: tone).opacity(0.0))
                    }
            } else {
                scrollableContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(titleDisplayMode)
        .navigationBarBackButtonHidden(hidesSystemBackButton)
        .toolbar {
            leadingToolbarContent
            trailingToolbarContent
        }
        .toolbarBackgroundVisibility(.automatic, for: .navigationBar)
        .background {
            MistiaInteractivePopGestureHelper()
        }
    }

    @ToolbarContentBuilder
    private var leadingToolbarContent: some ToolbarContent {
        if leadingSystemImage != nil || showsLeadingAvatar {
            ToolbarItem(placement: .topBarLeading) {
                leadingToolbarAccessory
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        if trailingSystemImage != nil || TrailingAccessory.self != EmptyView.self {
            ToolbarItem(placement: .topBarTrailing) {
                trailingToolbarAccessory
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    @ViewBuilder
    private var leadingToolbarAccessory: some View {
        if let leadingSystemImage {
            MistiaHeaderCircleButton(action: onLeadingTap) {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
            .disabled(!isLeadingEnabled)
            .opacity(isLeadingEnabled ? 1 : 0.45)
        } else if showsLeadingAvatar {
            leadingAvatarButton
        }
    }

    @ViewBuilder
    private var leadingAvatarButton: some View {
        let button = MistiaHeaderCircleButton(action: onLeadingTap) {
            MistiaAttentionPulseAvatar(
                initials: leadingInitials,
                avatarURL: leadingAvatarURL,
                size: 28,
                isActive: leadingAvatarAttentionPulse
            )
        }
        .disabled(!isLeadingEnabled)
        .opacity(isLeadingEnabled ? 1 : 0.45)

        if let leadingAccessibilityLabel {
            button.accessibilityLabel(Text(leadingAccessibilityLabel))
        } else {
            button
        }
    }

    @ViewBuilder
    private var trailingToolbarAccessory: some View {
        if TrailingAccessory.self != EmptyView.self {
            trailingAccessory
        } else if let trailingSystemImage {
            MistiaHeaderCircleButton(action: onTrailingTap) {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
        }
    }
}

extension MistiaPinnedTopBarScaffold where TrailingAccessory == EmptyView {
    init(
        tone: MistiaBackgroundTone,
        title: String,
        embedsInNavigationStack: Bool = true,
        showsLeadingAvatar: Bool = true,
        leadingInitials: String = "QL",
        leadingAvatarURL: URL? = nil,
        leadingAccessibilityLabel: String? = nil,
        leadingAvatarAttentionPulse: Bool = false,
        isLeadingEnabled: Bool = true,
        leadingSystemImage: String? = nil,
        trailingSystemImage: String? = "bell",
        hidesSystemBackButton: Bool = false,
        onLeadingTap: @escaping () -> Void = {},
        onTrailingTap: @escaping () -> Void = {},
        onRefresh: (() async -> Void)? = nil,
        contentSpacing: CGFloat = 18,
        contentBottomPadding: CGFloat = 150,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        headerBehavior: HeaderBehavior = .fixedInset,
        @ViewBuilder pinnedHeader: () -> PinnedHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tone: tone,
            title: title,
            embedsInNavigationStack: embedsInNavigationStack,
            showsLeadingAvatar: showsLeadingAvatar,
            leadingInitials: leadingInitials,
            leadingAvatarURL: leadingAvatarURL,
            leadingAccessibilityLabel: leadingAccessibilityLabel,
            leadingAvatarAttentionPulse: leadingAvatarAttentionPulse,
            isLeadingEnabled: isLeadingEnabled,
            leadingSystemImage: leadingSystemImage,
            trailingSystemImage: trailingSystemImage,
            hidesSystemBackButton: hidesSystemBackButton,
            onLeadingTap: onLeadingTap,
            onTrailingTap: onTrailingTap,
            onRefresh: onRefresh,
            contentSpacing: contentSpacing,
            contentBottomPadding: contentBottomPadding,
            titleDisplayMode: titleDisplayMode,
            headerBehavior: headerBehavior,
            pinnedHeader: pinnedHeader,
            trailingAccessory: { EmptyView() },
            content: content
        )
    }
}

extension MistiaPinnedTopBarScaffold where PinnedHeader == EmptyView, TrailingAccessory == EmptyView {
    init(
        tone: MistiaBackgroundTone,
        title: String,
        embedsInNavigationStack: Bool = true,
        showsLeadingAvatar: Bool = true,
        leadingInitials: String = "QL",
        leadingAvatarURL: URL? = nil,
        leadingAccessibilityLabel: String? = nil,
        leadingAvatarAttentionPulse: Bool = false,
        isLeadingEnabled: Bool = true,
        leadingSystemImage: String? = nil,
        trailingSystemImage: String? = "bell",
        hidesSystemBackButton: Bool = false,
        onLeadingTap: @escaping () -> Void = {},
        onTrailingTap: @escaping () -> Void = {},
        onRefresh: (() async -> Void)? = nil,
        contentSpacing: CGFloat = 18,
        contentBottomPadding: CGFloat = 150,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        headerBehavior: HeaderBehavior = .fixedInset,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tone: tone,
            title: title,
            embedsInNavigationStack: embedsInNavigationStack,
            showsLeadingAvatar: showsLeadingAvatar,
            leadingInitials: leadingInitials,
            leadingAvatarURL: leadingAvatarURL,
            leadingAccessibilityLabel: leadingAccessibilityLabel,
            leadingAvatarAttentionPulse: leadingAvatarAttentionPulse,
            isLeadingEnabled: isLeadingEnabled,
            leadingSystemImage: leadingSystemImage,
            trailingSystemImage: trailingSystemImage,
            hidesSystemBackButton: hidesSystemBackButton,
            onLeadingTap: onLeadingTap,
            onTrailingTap: onTrailingTap,
            onRefresh: onRefresh,
            contentSpacing: contentSpacing,
            contentBottomPadding: contentBottomPadding,
            titleDisplayMode: titleDisplayMode,
            headerBehavior: headerBehavior,
            pinnedHeader: { EmptyView() },
            trailingAccessory: { EmptyView() },
            content: content
        )
    }
}

private struct MistiaTopScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                content
            }
        }
    }
}

struct MistiaChip: View {
    let title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                MistiaCapsuleGlassBackground(tint: tint.opacity(0.18))
            }
    }
}

private struct MistiaInteractivePopGestureHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopGestureViewController {
        let controller = PopGestureViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PopGestureViewController, context: Context) {
        uiViewController.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class PopGestureViewController: UIViewController {
        var coordinator: Coordinator?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let navigationController = navigationController {
                // Assert control over the shared navigation controller's delegate
                navigationController.interactivePopGestureRecognizer?.delegate = coordinator
                coordinator?.navigationController = navigationController
            }
        }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            return (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
