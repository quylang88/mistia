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
    var tint: Color = .white.opacity(0.08)
    var interactive: Bool = false
    var padding: CGFloat = 18
    private let content: Content

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
            .fill(Color(UIColor.secondarySystemGroupedBackground))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.12 : 0.03),
                radius: 10,
                y: 4
            )
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
            .fill(Color.clear)
            .background {
                if #available(iOS 26, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(glassStyle, in: .capsule)
                } else {
                    Capsule()
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.2), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.10 : 0.03), radius: 8, y: 3)
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
            .fill(Color.clear)
            .background {
                if #available(iOS 26, *) {
                    Circle()
                        .fill(.clear)
                        .glassEffect(glassStyle, in: .circle)
                } else {
                    Circle()
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.22), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, y: 4)
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
                MistiaAvatarBadge(initials: leadingInitials, size: 28)
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

private let mistiaHeaderCircleSize: CGFloat = 38

private struct MistiaHeaderCircleButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    content
                        .frame(width: mistiaHeaderCircleSize, height: mistiaHeaderCircleSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    content
                        .frame(width: mistiaHeaderCircleSize, height: mistiaHeaderCircleSize)
                        .contentShape(Circle())
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

struct MistiaPinnedTopBarScaffold<PinnedHeader: View, Content: View>: View {
    let tone: MistiaBackgroundTone
    let title: String
    var embedsInNavigationStack: Bool = true
    var showsLeadingAvatar: Bool = true
    var leadingInitials: String = "QL"
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String? = "bell"
    var hidesSystemBackButton: Bool = false
    var onLeadingTap: () -> Void = {}
    var onTrailingTap: () -> Void = {}
    var contentSpacing: CGFloat = 18
    var contentBottomPadding: CGFloat = 150
    @ViewBuilder let pinnedHeader: PinnedHeader
    @ViewBuilder let content: Content

    init(
        tone: MistiaBackgroundTone,
        title: String,
        embedsInNavigationStack: Bool = true,
        showsLeadingAvatar: Bool = true,
        leadingInitials: String = "QL",
        leadingSystemImage: String? = nil,
        trailingSystemImage: String? = "bell",
        hidesSystemBackButton: Bool = false,
        onLeadingTap: @escaping () -> Void = {},
        onTrailingTap: @escaping () -> Void = {},
        contentSpacing: CGFloat = 18,
        contentBottomPadding: CGFloat = 150,
        @ViewBuilder pinnedHeader: () -> PinnedHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.title = title
        self.embedsInNavigationStack = embedsInNavigationStack
        self.showsLeadingAvatar = showsLeadingAvatar
        self.leadingInitials = leadingInitials
        self.leadingSystemImage = leadingSystemImage
        self.trailingSystemImage = trailingSystemImage
        self.hidesSystemBackButton = hidesSystemBackButton
        self.onLeadingTap = onLeadingTap
        self.onTrailingTap = onTrailingTap
        self.contentSpacing = contentSpacing
        self.contentBottomPadding = contentBottomPadding
        self.pinnedHeader = pinnedHeader()
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

    @ViewBuilder
    private var scrollableContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: contentSpacing) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, contentBottomPadding)
        }
        .modifier(MistiaTopScrollEdgeEffect())
        .scrollIndicators(.hidden)
    }

    private var screenContent: some View {
        ZStack {
            MistiaBackgroundView(tone: tone)

            if PinnedHeader.self != EmptyView.self {
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hidesSystemBackButton)
        .toolbar {
            leadingToolbarContent
            trailingToolbarContent
        }
        .toolbarBackgroundVisibility(.automatic, for: .navigationBar)
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
        if trailingSystemImage != nil {
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
        } else if showsLeadingAvatar {
            MistiaHeaderCircleButton(action: onLeadingTap) {
                MistiaAvatarBadge(initials: leadingInitials, size: 28)
            }
        }
    }

    @ViewBuilder
    private var trailingToolbarAccessory: some View {
        if let trailingSystemImage {
            MistiaHeaderCircleButton(action: onTrailingTap) {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
        }
    }
}

extension MistiaPinnedTopBarScaffold where PinnedHeader == EmptyView {
    init(
        tone: MistiaBackgroundTone,
        title: String,
        embedsInNavigationStack: Bool = true,
        showsLeadingAvatar: Bool = true,
        leadingInitials: String = "QL",
        leadingSystemImage: String? = nil,
        trailingSystemImage: String? = "bell",
        hidesSystemBackButton: Bool = false,
        onLeadingTap: @escaping () -> Void = {},
        onTrailingTap: @escaping () -> Void = {},
        contentSpacing: CGFloat = 18,
        contentBottomPadding: CGFloat = 150,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tone: tone,
            title: title,
            embedsInNavigationStack: embedsInNavigationStack,
            showsLeadingAvatar: showsLeadingAvatar,
            leadingInitials: leadingInitials,
            leadingSystemImage: leadingSystemImage,
            trailingSystemImage: trailingSystemImage,
            hidesSystemBackButton: hidesSystemBackButton,
            onLeadingTap: onLeadingTap,
            onTrailingTap: onTrailingTap,
            contentSpacing: contentSpacing,
            contentBottomPadding: contentBottomPadding,
            pinnedHeader: { EmptyView() },
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

struct MistiaFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 12)

            MistiaGlassCard(
                cornerRadius: 20,
                tint: Color(UIColor.secondarySystemGroupedBackground),
                padding: 16
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
            }
        }
    }
}

struct MistiaFormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            content
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
