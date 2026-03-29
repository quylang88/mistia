import SwiftUI

private enum TransactionSegment: String, CaseIterable, Hashable {
    case all
    case expense
    case income

    var title: String {
        switch self {
        case .all:
            "Tất cả"
        case .expense:
            "Chi tiêu"
        case .income:
            "Thu nhập"
        }
    }

    var tint: Color {
        switch self {
        case .all:
            .indigo
        case .expense:
            Color(red: 0.97, green: 0.43, blue: 0.46)
        case .income:
            .mint
        }
    }

    var kind: TransactionKind? {
        switch self {
        case .all:
            nil
        case .expense:
            .expense
        case .income:
            .income
        }
    }
}

private enum TransactionsSheet: String, Identifiable {
    case filters

    var id: String { rawValue }
}

struct TransactionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let dump = MockDataLoader.transactions

    @State private var selectedSegment: TransactionSegment = .all
    @State private var activeSheet: TransactionsSheet?

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14)
    }

    private var idleCapsuleTint: Color {
        colorScheme == .dark ? .white.opacity(0.045) : .white.opacity(0.18)
    }

    private var visibleSections: [TransactionSectionDump] {
        dump.sections.compactMap { section in
            let items = section.items.filter { item in
                guard let kind = selectedSegment.kind else { return true }
                return item.kind == kind
            }

            guard !items.isEmpty else { return nil }
            return TransactionSectionDump(
                title: section.title,
                trailingLabel: section.trailingLabel,
                items: items
            )
        }
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: dump.headerTitle,
            trailingSystemImage: "magnifyingglass",
            contentSpacing: 16
        ) {
            toolbarChips
            TransactionSummaryCard(summary: dump.summary)
            segmentSelector

            ForEach(visibleSections) { section in
                TransactionSectionCard(section: section)
            }
        }
        .sheet(item: $activeSheet) { _ in
            TransactionFilterSheetView(sheet: dump.filterSheet)
                .presentationDetents([.height(378)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
    }

    private var toolbarChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                TransactionToolbarChip(
                    icon: "magnifyingglass",
                    title: dump.timeframeLabel,
                    tint: accentPurple
                )

                TransactionToolbarChip(
                    icon: "wallet.pass",
                    title: dump.walletLabel,
                    tint: MistiaAccent.slate.color
                )

                Button {
                    activeSheet = .filters
                } label: {
                    TransactionToolbarChip(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "Bộ lọc",
                        tint: accentPurple,
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private var segmentSelector: some View {
        HStack(spacing: 8) {
            ForEach(TransactionSegment.allCases, id: \.self) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    HStack(spacing: 6) {
                        if segment != .all {
                            Circle()
                                .fill(segment.tint)
                                .frame(width: 7, height: 7)
                        }

                        Text(segment.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selectedSegment == segment ? accentPurple : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        MistiaCapsuleGlassBackground(
                            tint: selectedSegment == segment
                                ? accentPurple.opacity(colorScheme == .dark ? 0.25 : 0.14)
                                : idleCapsuleTint,
                            interactive: true
                        )
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            Button { } label: {
                ZStack {
                    MistiaCircleGlassBackground(tint: .white.opacity(0.08), interactive: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TransactionSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: TransactionSummaryDump

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14)
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 20, tint: cardTint, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                TransactionSummaryMetric(
                    title: "Chi",
                    value: summary.expense.mistiaCurrency,
                    tint: Color(red: 0.97, green: 0.43, blue: 0.46)
                )

                Spacer(minLength: 6)

                TransactionSummaryMetric(
                    title: "Thu",
                    value: summary.income.mistiaCurrency,
                    tint: .mint
                )

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(summary.totalTransactions)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Giao dịch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TransactionSummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct TransactionSectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let section: TransactionSectionDump

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(section.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text(section.trailingLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            MistiaGlassCard(
                cornerRadius: 20,
                tint: colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14),
                padding: 0
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        Button { } label: {
                            TransactionRow(item: item)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                        if index < section.items.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    let item: TransactionListItemDump

    var body: some View {
        HStack(spacing: 12) {
            TransactionIconTile(item: item)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.merchant)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            Text(item.displayAmount)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(item.amountTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct TransactionIconTile: View {
    let item: TransactionListItemDump

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.accent.color.opacity(0.14))

            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(item.accent.color)
        }
        .frame(width: 30, height: 30)
    }
}

private struct TransactionToolbarChip: View {
    let icon: String
    let title: String
    let tint: Color
    var isInteractive: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            MistiaCapsuleGlassBackground(
                tint: tint.opacity(isInteractive ? 0.18 : 0.12),
                interactive: isInteractive
            )
        }
    }
}

private struct TransactionFilterSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let sheet: TransactionFilterSheetDump
    @Environment(\.dismiss) private var dismiss

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.024) : .white.opacity(0.16)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 12) {
                Capsule()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 42, height: 5)
                    .padding(.top, 8)

                MistiaGlassCard(
                    cornerRadius: 24,
                    tint: cardTint,
                    padding: 18
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(sheet.title)
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(sheet.code)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(sheet.rows.enumerated()), id: \.element.id) { index, row in
                                Button { } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: row.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 18)

                                        Text(row.title)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        Text(row.value)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

                                if index < sheet.rows.count - 1 {
                                    Divider()
                                        .padding(.leading, 30)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            TransactionActionButton(
                                title: sheet.resetLabel,
                                tint: .white.opacity(0.06),
                                foreground: .secondary
                            ) {
                                dismiss()
                            }

                            TransactionActionButton(
                                title: sheet.applyLabel,
                                tint: Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.30 : 0.18),
                                foreground: Color(red: 0.43, green: 0.23, blue: 0.76)
                            ) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
    }
}

private struct TransactionActionButton: View {
    let title: String
    let tint: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    MistiaCapsuleGlassBackground(tint: tint, interactive: true)
                }
        }
        .buttonStyle(
            MistiaPressableButtonStyle(
                cornerRadius: 22,
                tint: Color(red: 0.43, green: 0.23, blue: 0.76)
            )
        )
    }
}

private extension TransactionListItemDump {
    var amountTint: Color {
        kind == .income ? .mint : Color(red: 0.97, green: 0.43, blue: 0.46)
    }

    var displayAmount: String {
        let prefix = kind == .income ? "+" : "-"
        return prefix + amount.mistiaCurrency
    }
}
