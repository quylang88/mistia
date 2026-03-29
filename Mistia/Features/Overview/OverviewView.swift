import Charts
import SwiftUI

struct OverviewView: View {
    private let dump = MockDataLoader.dashboard

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: dump.headerTitle,
            contentSpacing: 18
        ) {
            OverviewHeroCard(balance: dump.balance)
            BudgetFocusSection(rows: dump.budgets)
            UpcomingBillsSection(rows: dump.upcomingBills)
            RecentTransactionsSection(rows: dump.recentTransactions)
        }
    }
}

private struct OverviewHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let balance: BalanceSectionDump

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.024) : .white.opacity(0.16)
    }

    private var insetSurface: Color {
        colorScheme == .dark ? .white.opacity(0.035) : .black.opacity(0.03)
    }

    private var chartMax: Int {
        max((balance.chart.map(\.value).max() ?? 0) + 40_000, 200_000)
    }

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: cardTint
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(balance.title)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(balance.totalBalance.mistiaCurrency)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)

                    MistiaChip(title: balance.filterLabel, tint: accentPurple)
                }

                HStack(spacing: 14) {
                    SummaryMetricColumn(
                        title: "Thu tháng này",
                        value: balance.incomeThisMonth.mistiaCurrency,
                        accent: .mint
                    )

                    Divider()
                        .frame(height: 26)

                    SummaryMetricColumn(
                        title: "Chi tháng này",
                        value: balance.expenseThisMonth.mistiaCurrency,
                        accent: .coral
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(balance.insightTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(balance.insightSubtitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    Chart(balance.chart) { point in
                        BarMark(
                            x: .value("Ngày", point.label),
                            y: .value("Giá trị", point.value)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(point.tone.color.gradient)
                        .opacity(0.92)
                    }
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: balance.chart.map(\.label)) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08))
                            AxisValueLabel {
                                if let number = value.as(Int.self) {
                                    Text(number.mistiaAxisLabel)
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0 ... chartMax)
                    .frame(height: 122)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(insetSurface)
                    }
                }
            }
        }
    }
}

private struct SummaryMetricColumn: View {
    let title: String
    let value: String
    let accent: MistiaAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetFocusSection: View {
    let rows: [BudgetRowDump]

    var body: some View {
        OverviewSection(title: "Ngân sách cần chú ý") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { } label: {
                        BudgetRow(row: row)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
    }
}

private struct BudgetRow: View {
    let row: BudgetRowDump

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: row.icon, accent: row.accent)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(row.spent.mistiaCurrency)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("/ \(row.limit.mistiaCurrency)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: row.progress)
                    .tint(row.accent.color)

                Text(row.daysRemainingText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(row.accent.color)
            }
        }
    }
}

private struct UpcomingBillsSection: View {
    let rows: [UpcomingBillDump]

    var body: some View {
        OverviewSection(title: "Khoản sắp đến hạn") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { } label: {
                        HStack(spacing: 12) {
                            OverviewIcon(icon: row.icon, accent: row.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Text(row.dueTime)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(row.amount.mistiaCurrency)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
    }
}

private struct RecentTransactionsSection: View {
    let rows: [TransactionRowDump]

    var body: some View {
        OverviewSection(title: "Giao dịch gần đây") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { } label: {
                        HStack(spacing: 12) {
                            OverviewIcon(icon: row.icon, accent: row.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.merchant)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(row.timeLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Text(row.amount.mistiaCurrency)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(row.kind == .income ? Color.mint : .primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
    }
}

private struct OverviewSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43))

                Spacer()

                Text("Xem tất cả")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            MistiaGlassCard(
                cornerRadius: 20,
                tint: colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14),
                padding: 0
            ) {
                content
            }
        }
    }
}

private struct OverviewIcon: View {
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
