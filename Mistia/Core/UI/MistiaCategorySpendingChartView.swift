import Charts
import SwiftUI
import UIKit

struct MistiaCategorySpendingChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDrilldown: MistiaCategoryChartDrilldown?
    @State private var didApplyInitialDrilldown = false

    let snapshot: OverviewCategorySpendingMonthSnapshot
    let resetKey: String
    let startsInFirstDrilldown: Bool
    let accessibilityPrefix: String
    let onPreferredHeightChange: (CGFloat) -> Void

    init(
        snapshot: OverviewCategorySpendingMonthSnapshot,
        resetKey: String? = nil,
        startsInFirstDrilldown: Bool = false,
        accessibilityPrefix: String = "mistia.category.spending",
        onPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.resetKey = resetKey ?? snapshot.id
        self.startsInFirstDrilldown = startsInFirstDrilldown
        self.accessibilityPrefix = accessibilityPrefix
        self.onPreferredHeightChange = onPreferredHeightChange
    }

    private var rootSlices: [MistiaCategoryChartSlice] {
        displaySlices(
            from: snapshot.slices,
            overflowID: "root-\(snapshot.id)",
            allowsCategorySelection: true,
            allowsOverflowSelection: true
        )
    }

    private var visibleSlices: [MistiaCategoryChartSlice] {
        guard let selectedDrilldown else {
            return rootSlices
        }

        return displaySlices(
            from: selectedDrilldown.rawSlices,
            overflowID: "drilldown-\(selectedDrilldown.id)",
            allowsCategorySelection: false,
            allowsOverflowSelection: false
        )
    }

    private var visibleTotalMinor: Int64 {
        visibleSlices.reduce(into: Int64.zero) { partial, slice in
            partial += slice.amountMinor
        }
    }

    private var preferredHeight: CGFloat {
        Self.estimatedHeight(
            visibleSliceCount: visibleSlices.count,
            showsBackButton: selectedDrilldown != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedDrilldown {
                Button {
                    clearDrilldown()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))

                        MistiaFinanceIconView(
                            icon: selectedDrilldown.iconSymbolName,
                            fallbackColor: Color(hex: selectedDrilldown.colorHex),
                            size: 18
                        )

                        Text(selectedDrilldown.name)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(colorScheme == .dark ? .white.opacity(0.05) : .white.opacity(0.62))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityPrefix).back")
            }

            if visibleSlices.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 14) {
                    MistiaCategoryPieChart(
                        slices: visibleSlices,
                        onSelectSlice: selectSlice
                    )
                    .frame(width: 150, height: 150)
                    .frame(width: 150)
                    .accessibilityIdentifier("\(accessibilityPrefix).pie")

                    MistiaCategoryLegendList(
                        slices: visibleSlices,
                        totalMinor: visibleTotalMinor,
                        currencyCode: snapshot.currencyCode,
                        accessibilityPrefix: accessibilityPrefix,
                        onSelectSlice: selectSlice
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: Self.chartSize, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            applyInitialDrilldownIfNeeded()
            onPreferredHeightChange(preferredHeight)
        }
        .onChange(of: preferredHeight) { _, height in
            onPreferredHeightChange(height)
        }
        .onChange(of: resetKey) { _, _ in
            selectedDrilldown = nil
            didApplyInitialDrilldown = false
            applyInitialDrilldownIfNeeded()
        }
        .onChange(of: snapshotSignature) { _, _ in
            selectedDrilldown = nil
            didApplyInitialDrilldown = false
            applyInitialDrilldownIfNeeded()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))

            VStack(spacing: 4) {
                Text(L10n.core.ui.mistiacategoryspendingchart.noSpendingYet)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(L10n.core.ui.mistiacategoryspendingchart.changeTheTimeRangeToSeeMore)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
    }

    private var snapshotSignature: String {
        snapshot.slices
            .map { "\($0.id):\($0.amountMinor):\($0.childSlices.map(\.id).joined(separator: ","))" }
            .joined(separator: "|")
    }

    private func displaySlices(
        from sourceSlices: [OverviewCategorySpendingSlice],
        overflowID: String,
        allowsCategorySelection: Bool,
        allowsOverflowSelection: Bool
    ) -> [MistiaCategoryChartSlice] {
        let positiveSlices = sourceSlices.filter { $0.amountMinor > 0 }
        let leadingSlices = Array(positiveSlices.prefix(Self.maximumVisibleSlices))
        let overflowSlices = Array(positiveSlices.dropFirst(Self.maximumVisibleSlices))

        var displayed = leadingSlices.map { source in
            MistiaCategoryChartSlice(
                id: source.id,
                sourceSliceID: source.id,
                name: source.name,
                iconSymbolName: source.iconSymbolName,
                colorHex: source.colorHex,
                amountMinor: source.amountMinor,
                rawSlices: source.childSlices,
                canSelect: allowsCategorySelection && source.canDrillDown,
                kind: .category
            )
        }

        if !overflowSlices.isEmpty {
            let overflowAmount = overflowSlices.reduce(into: Int64.zero) { partial, slice in
                partial += slice.amountMinor
            }

            displayed.append(
                MistiaCategoryChartSlice(
                    id: "other-\(overflowID)",
                    sourceSliceID: "other-\(overflowID)",
                    name: L10n.core.ui.mistiacategoryspendingchart.other,
                    iconSymbolName: "ellipsis.circle.fill",
                    colorHex: "#7C85A3",
                    amountMinor: overflowAmount,
                    rawSlices: overflowSlices,
                    canSelect: allowsOverflowSelection,
                    kind: .rootOverflow
                )
            )
        }

        return displayed
    }

    private func selectSlice(_ slice: MistiaCategoryChartSlice) {
        guard slice.canSelect else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            selectedDrilldown = MistiaCategoryChartDrilldown(
                id: slice.id,
                sourceSliceID: slice.sourceSliceID,
                name: slice.name,
                iconSymbolName: slice.iconSymbolName,
                colorHex: slice.colorHex,
                rawSlices: slice.rawSlices,
                kind: slice.kind
            )
        }
    }

    private func clearDrilldown() {
        withAnimation(.snappy) {
            selectedDrilldown = nil
        }
    }

    private func applyInitialDrilldownIfNeeded() {
        guard startsInFirstDrilldown,
              !didApplyInitialDrilldown,
              selectedDrilldown == nil,
              let firstSelectableSlice = rootSlices.first(where: \.canSelect)
        else {
            return
        }

        didApplyInitialDrilldown = true
        selectedDrilldown = MistiaCategoryChartDrilldown(
            id: firstSelectableSlice.id,
            sourceSliceID: firstSelectableSlice.sourceSliceID,
            name: firstSelectableSlice.name,
            iconSymbolName: firstSelectableSlice.iconSymbolName,
            colorHex: firstSelectableSlice.colorHex,
            rawSlices: firstSelectableSlice.rawSlices,
            kind: firstSelectableSlice.kind
        )
    }

    static func estimatedHeight(visibleSliceCount: Int, showsBackButton: Bool = false) -> CGFloat {
        let listHeight = MistiaCategoryLegendList.preferredHeight(for: visibleSliceCount)
        let backButtonHeight: CGFloat = showsBackButton ? 34 : 0
        return 20 + backButtonHeight + max(chartSize, listHeight)
    }

    static func preferredRootHeight(for snapshot: OverviewCategorySpendingMonthSnapshot) -> CGFloat {
        estimatedHeight(visibleSliceCount: rootVisibleSliceCount(for: snapshot))
    }

    private static func rootVisibleSliceCount(for snapshot: OverviewCategorySpendingMonthSnapshot) -> Int {
        let positiveSliceCount = snapshot.slices.lazy.filter { $0.amountMinor > 0 }.count
        guard positiveSliceCount > maximumVisibleSlices else {
            return positiveSliceCount
        }
        return maximumVisibleSlices + 1
    }

    private static let chartSize: CGFloat = 150
    private static let maximumVisibleSlices = 5
}

private struct MistiaCategoryChartSlice: Equatable, Identifiable {
    let id: String
    let sourceSliceID: String
    let name: String
    let iconSymbolName: String
    let colorHex: String
    let amountMinor: Int64
    let rawSlices: [OverviewCategorySpendingSlice]
    let canSelect: Bool
    let kind: MistiaCategoryChartDrilldown.Kind
}

private struct MistiaCategoryChartDrilldown: Equatable, Identifiable {
    enum Kind: Equatable {
        case category
        case rootOverflow
    }

    let id: String
    let sourceSliceID: String
    let name: String
    let iconSymbolName: String
    let colorHex: String
    let rawSlices: [OverviewCategorySpendingSlice]
    let kind: Kind
}

private struct MistiaCategoryPieChart: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAngle: Double?

    let slices: [MistiaCategoryChartSlice]
    let onSelectSlice: (MistiaCategoryChartSlice) -> Void

    private var prominentSlice: MistiaCategoryChartSlice? {
        slices.max { $0.amountMinor < $1.amountMinor }
    }

    private var prominentColor: Color {
        Color(hex: prominentSlice?.colorHex ?? "#2DAA9E")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045))
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
                }

            Chart(slices) { slice in
                let isProminent = slice.id == prominentSlice?.id

                SectorMark(
                    angle: .value(L10n.common.chart.spending, Double(slice.amountMinor)),
                    innerRadius: .ratio(0.0),
                    outerRadius: .ratio(isProminent ? 1.0 : 0.92),
                    angularInset: slices.count == 1 ? 0 : 1.8
                )
                .cornerRadius(slices.count == 1 ? 0 : (isProminent ? 7 : 4))
                .foregroundStyle(Color(hex: slice.colorHex).gradient)
                .opacity(isProminent ? 1 : 0.90)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAngle)
            .padding(2)
        }
        .shadow(color: prominentColor.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 12, y: 5)
        .onChange(of: selectedAngle) { _, value in
            defer {
                DispatchQueue.main.async {
                    selectedAngle = nil
                }
            }

            guard let value,
                  let slice = slice(at: value),
                  slice.canSelect
            else {
                return
            }

            onSelectSlice(slice)
        }
    }

    private func slice(at selectedValue: Double) -> MistiaCategoryChartSlice? {
        var lowerBound = 0.0

        for slice in slices {
            let upperBound = lowerBound + Double(slice.amountMinor)
            if selectedValue >= lowerBound && selectedValue <= upperBound {
                return slice
            }
            lowerBound = upperBound
        }

        return nil
    }
}

private struct MistiaCategoryLegendList: View {
    let slices: [MistiaCategoryChartSlice]
    let totalMinor: Int64
    let currencyCode: String
    let accessibilityPrefix: String
    let onSelectSlice: (MistiaCategoryChartSlice) -> Void

    private var showsPercentage: Bool {
        slices.count > 1
    }

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(slices) { slice in
                if slice.canSelect {
                    Button {
                        onSelectSlice(slice)
                    } label: {
                        MistiaCategoryLegendRow(
                            slice: slice,
                            totalMinor: totalMinor,
                            currencyCode: currencyCode,
                            showsPercentage: showsPercentage
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(accessibilityPrefix).row.\(slice.id)")
                } else {
                    MistiaCategoryLegendRow(
                        slice: slice,
                        totalMinor: totalMinor,
                        currencyCode: currencyCode,
                        showsPercentage: showsPercentage
                    )
                    .accessibilityIdentifier("\(accessibilityPrefix).row.\(slice.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: showsPercentage ? .topLeading : .center)
    }

    static func preferredHeight(for rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowMinHeight + CGFloat(rowCount - 1) * rowSpacing
    }

    private static let rowMinHeight: CGFloat = 42
    private static let rowSpacing: CGFloat = 7
}

private struct MistiaCategoryLegendRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let slice: MistiaCategoryChartSlice
    let totalMinor: Int64
    let currencyCode: String
    let showsPercentage: Bool

    private var percentageText: String {
        guard totalMinor > 0 else { return "0%" }

        let percentage = Double(slice.amountMinor) / Double(totalMinor) * 100
        return "\(Int(percentage.rounded()))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: slice.colorHex))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(slice.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(slice.amountMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            if showsPercentage {
                Text(percentageText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: slice.colorHex))
                    .frame(minWidth: 34, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 42)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? .white.opacity(0.035) : .white.opacity(0.58))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
