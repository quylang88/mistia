import SwiftUI

enum MistiaTab: String, CaseIterable, Hashable {
    case overview
    case transactions
    case planning
    case settings

    var title: String {
        switch self {
        case .overview:
            "Tổng quan"
        case .transactions:
            "Giao dịch"
        case .planning:
            "Kế hoạch"
        case .settings:
            "Quản lý"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "house.fill"
        case .transactions:
            "list.bullet.rectangle.portrait.fill"
        case .planning:
            "wallet.pass.fill"
        case .settings:
            "tray.full.fill"
        }
    }

    var accent: Color {
        switch self {
        case .overview:
            .blue
        case .transactions:
            .cyan
        case .planning:
            Color(red: 0.24, green: 0.45, blue: 0.96)
        case .settings:
            Color(red: 0.43, green: 0.23, blue: 0.76)
        }
    }
}

struct RootTabView: View {
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.hideQuickCreate) private var hideQuickCreate = false
    @State private var selectedTab: MistiaTab = .overview
    @State private var isAssistantPresented = false
    @State private var isQuickCreatePresented = false

    var body: some View {
        MistiaNativeTabShell(
            selectedTab: $selectedTab,
            appearanceMode: appearanceMode,
            hidesQuickCreate: hideQuickCreate,
            onAssistantTap: { isAssistantPresented = true },
            onQuickCreateTap: { isQuickCreatePresented = true }
        )
        .ignoresSafeArea()
        .sheet(isPresented: $isAssistantPresented) {
            MistiaAssistantSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isQuickCreatePresented) {
            MistiaQuickCreateSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var appearanceMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }
}

private struct MistiaAssistantSheet: View {
    var body: some View {
        ZStack {
            MistiaBackgroundView()

            VStack(spacing: 18) {
                Text("Mistia Assistant")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                MistiaGlassCard(
                    cornerRadius: 28,
                    tint: Color(red: 0.29, green: 0.50, blue: 0.96).opacity(0.14)
                ) {
                    VStack(spacing: 14) {
                        ZStack {
                            MistiaRoundedGlassBackground(
                                cornerRadius: 24,
                                tint: Color.white.opacity(0.08)
                            )

                            MistiaAssistantGlyph(isCompact: false)
                        }
                        .frame(width: 76, height: 76)

                        Text("Tab AI assistant đang được giữ chỗ để hoàn thiện UI trước, chưa nối logic chat hoặc automation.")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct MistiaQuickCreateSheet: View {
    var body: some View {
        ZStack {
            MistiaBackgroundView()

            VStack(spacing: 18) {
                Text("Tạo nhanh")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                MistiaGlassCard(
                    cornerRadius: 28,
                    tint: Color(red: 0.44, green: 0.24, blue: 0.78).opacity(0.14)
                ) {
                    VStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(.white.opacity(0.08), in: Circle())

                        Text("Nút plus đang là placeholder để chốt UI Slack-style trước. Chưa nối flow tạo giao dịch hoặc item mới.")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct MistiaAssistantGlyph: View {
    let isCompact: Bool

    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: isCompact ? 18 : 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .shadow(color: .black.opacity(0.12), radius: isCompact ? 4 : 8, y: 2)
    }
}
