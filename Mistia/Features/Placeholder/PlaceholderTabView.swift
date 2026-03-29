import SwiftUI

struct PlaceholderTabView: View {
    let tab: MistiaTab

    var body: some View {
        ZStack {
            MistiaBackgroundView()

            VStack(spacing: 18) {
                MistiaTopBar(title: tab.title, trailingSystemImage: nil)

                Spacer()

                MistiaGlassCard(cornerRadius: 30, tint: tab.accent.opacity(0.16)) {
                    VStack(spacing: 14) {
                        ZStack {
                            MistiaCircleGlassBackground(tint: tab.accent.opacity(0.2))
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(tab.accent)
                        }
                        .frame(width: 78, height: 78)

                        Text(tab.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Tab này đang để trống để ưu tiên hoàn thiện giao diện Tổng quan trước.")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 150)
        }
    }
}
