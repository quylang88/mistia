import SwiftUI

private enum PlanningTopMode: String {
    case budget
    case goals
    case recurring
}

struct PlanningView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let dump = MockDataLoader.planning

    @State private var selectedMode: PlanningTopMode = .budget

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: dump.headerTitle,
            contentSpacing: 18
        ) {
            PlanningTopTabsBar(selection: $selectedMode, tabs: dump.tabs)

            switch selectedMode {
            case .budget:
                budgetContent
            case .goals:
                PlanningPlaceholderCard(placeholder: dump.goalsPlaceholder)
            case .recurring:
                PlanningPlaceholderCard(placeholder: dump.recurringPlaceholder)
            }
        }
    }

    private var budgetContent: some View {
        VStack(spacing: 16) {
            PlanningSummaryCard(summary: dump.summary, tint: cardTint)

            PlanningSection(title: dump.budgetSectionTitle) {
                MistiaGlassCard(cornerRadius: 20, tint: cardTint, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(dump.budgets.enumerated()), id: \.element.id) { index, item in
                            Button { } label: {
                                PlanningBudgetRow(item: item)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                            if index < dump.budgets.count - 1 {
                                Divider()
                                    .padding(.leading, 58)
                            }
                        }
                    }
                }
            }

            PlanningSection(title: dump.watchSectionTitle) {
                MistiaGlassCard(cornerRadius: 20, tint: cardTint, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(dump.watchItems.enumerated()), id: \.element.id) { index, item in
                            Button { } label: {
                                PlanningWatchRow(item: item)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                            if index < dump.watchItems.count - 1 {
                                Divider()
                                    .padding(.leading, 58)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PlanningTopTabsBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: PlanningTopMode
    let tabs: [PlanningTopTabDump]

    private var mistiaPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 10) {
                        tabRow
                    }
                } else {
                    tabRow
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var tabRow: some View {
        HStack(spacing: 10) {
            ForEach(tabs) { tab in
                Button {
                    selection = mode(for: tab.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .bold))

                        Text(tab.title)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selection == mode(for: tab.id) ? mistiaPurple : chipForeground)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background {
                        PlanningTopTabSurface(
                            tint: selection == mode(for: tab.id) ? activeTint : idleTint
                        )
                    }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: mistiaPurple))
            }
        }
    }

    private var chipForeground: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color(red: 0.39, green: 0.42, blue: 0.5)
    }

    private var activeTint: Color {
        colorScheme == .dark ? mistiaPurple.opacity(0.28) : mistiaPurple.opacity(0.16)
    }

    private var idleTint: Color {
        colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.22)
    }

    private func mode(for rawValue: String) -> PlanningTopMode {
        PlanningTopMode(rawValue: rawValue) ?? .budget
    }
}

private struct PlanningSummaryCard: View {
    let summary: PlanningSummaryDump
    let tint: Color

    var body: some View {
        MistiaGlassCard(cornerRadius: 20, tint: tint, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tổng ngân sách: \(summary.totalBudget.mistiaCurrency)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack {
                    Spacer()
                    PlanningProgressRing(progress: summary.progress, label: summary.progressText)
                    Spacer()
                }

                HStack {
                    PlanningMetricBlock(
                        title: "Đã chi:",
                        value: summary.spent.mistiaCurrency,
                        tint: Color(red: 0.97, green: 0.43, blue: 0.46)
                    )

                    Spacer(minLength: 16)

                    PlanningMetricBlock(
                        title: "Còn lại",
                        value: summary.remaining.mistiaCurrency,
                        tint: .mint
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PlanningProgressRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.54, green: 0.82, blue: 1.0),
                            .mint,
                            Color(red: 0.43, green: 0.23, blue: 0.76)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(label)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(width: 128, height: 128)
    }
}

private struct PlanningMetricBlock: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }
}

private struct PlanningSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43))

            content
        }
    }
}

private struct PlanningBudgetRow: View {
    let item: PlanningBudgetItemDump

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: item.icon, accent: item.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(item.spent.mistiaCurrency) / \(item.limit.mistiaCurrency)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text(item.percentText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            PlanningProgressBar(progress: item.progress, tint: item.accent.color)

            HStack {
                Spacer()
                Text(item.daysRemainingText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlanningWatchRow: View {
    let item: PlanningWatchItemDump

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: item.icon, accent: item.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(item.spent.mistiaCurrency) / \(item.limit.mistiaCurrency)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.trailingAmount.mistiaCurrency)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(item.tone.color)

                    Text(item.statusText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(item.tone.color)
                }
            }

            PlanningProgressBar(progress: item.progress, tint: item.tone.color)
        }
    }
}

private struct PlanningProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))

                Capsule()
                    .fill(tint.opacity(colorScheme == .dark ? 0.9 : 0.78))
                    .frame(width: max(proxy.size.width * progress, 18))
            }
        }
        .frame(height: 10)
    }
}

private struct PlanningIconTile: View {
    let icon: String
    let accent: MistiaAccent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.color.opacity(0.14))

            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent.color)
        }
        .frame(width: 30, height: 30)
    }
}

private struct PlanningPlaceholderCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let placeholder: PlanningPlaceholderDump

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 20,
            tint: colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14)
        ) {
            VStack(spacing: 16) {
                ZStack {
                    MistiaCircleGlassBackground(
                        tint: Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.20 : 0.12),
                        interactive: false
                    )

                    Image(systemName: placeholder.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(red: 0.43, green: 0.23, blue: 0.76))
                }
                .frame(width: 72, height: 72)

                Text(placeholder.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(placeholder.message)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }
}

private struct PlanningTopTabSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    var body: some View {
        Capsule()
            .fill(Color.clear)
            .background {
                if #available(iOS 26, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(
                            Glass.regular
                                .tint(tint)
                                .interactive(true),
                            in: .capsule
                        )
                } else {
                    Capsule()
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        .white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                        lineWidth: 0.8
                    )
            }
    }
}
