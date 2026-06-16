import SwiftUI

struct MistiaMonthSelectionBounds: Equatable {
    let minimumMonth: Date
    let maximumMonth: Date

    init(minimumMonth: Date, maximumMonth: Date, calendar: Calendar) {
        let normalizedMinimum = PlanningLogic.startOfMonth(for: minimumMonth, calendar: calendar)
        let normalizedMaximum = PlanningLogic.startOfMonth(for: maximumMonth, calendar: calendar)
        self.minimumMonth = min(normalizedMinimum, normalizedMaximum)
        self.maximumMonth = max(normalizedMinimum, normalizedMaximum)
    }

    static func standard(
        calendar: Calendar,
        referenceDate: Date = .now
    ) -> MistiaMonthSelectionBounds {
        let maximumMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let maximumYear = calendar.component(.year, from: maximumMonth)
        let minimumMonth = calendar.date(
            from: DateComponents(year: maximumYear - 10, month: 1, day: 1)
        ) ?? maximumMonth
        return MistiaMonthSelectionBounds(
            minimumMonth: minimumMonth,
            maximumMonth: maximumMonth,
            calendar: calendar
        )
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let month = PlanningLogic.startOfMonth(for: date, calendar: calendar)
        return month >= minimumMonth && month <= maximumMonth
    }

    func clamped(_ date: Date, calendar: Calendar) -> Date {
        let month = PlanningLogic.startOfMonth(for: date, calendar: calendar)
        return min(max(month, minimumMonth), maximumMonth)
    }
}

struct MistiaMonthNavigationControl: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding private var selection: Date

    private let calendar: Calendar
    private let accentColor: Color
    private let bounds: MistiaMonthSelectionBounds

    @State private var isMonthPickerPresented = false

    init(
        selection: Binding<Date>,
        calendar: Calendar,
        accentColor: Color = MistiaAccent.purple.color,
        bounds: MistiaMonthSelectionBounds? = nil
    ) {
        _selection = selection
        self.calendar = calendar
        self.accentColor = accentColor
        self.bounds = bounds ?? .standard(calendar: calendar)
    }

    var body: some View {
        HStack(spacing: 10) {
            stepButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.core.ui.mistiamonthnavigation.previousMonth,
                delta: -1
            )

            monthPickerButton

            stepButton(
                systemImage: "chevron.right",
                accessibilityLabel: L10n.core.ui.mistiamonthnavigation.nextMonth,
                delta: 1
            )
        }
        .sheet(isPresented: $isMonthPickerPresented) {
            MistiaMonthPickerSheet(
                selection: $selection,
                calendar: calendar,
                accentColor: accentColor,
                bounds: bounds
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.hidden)
        }
        .onAppear {
            clampSelectionIfNeeded()
        }
        .onChange(of: selection) { _, newValue in
            clampSelectionIfNeeded(newValue)
        }
    }

    private var monthPickerButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: { isMonthPickerPresented = true }) {
                    monthPickerLabel
                }
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.capsule)
            } else {
                Button(action: { isMonthPickerPresented = true }) {
                    monthPickerLabel
                        .background {
                            MistiaCapsuleGlassBackground(
                                tint: accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12),
                                interactive: true
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(Text(L10n.core.ui.mistiamonthnavigation.chooseMonth))
    }

    private var monthPickerLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .bold))

            Text(MistiaDateFormatting.statementMonthYearString(for: selection, calendar: calendar))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Capsule())
    }

    private func stepButton(
        systemImage: String,
        accessibilityLabel: String,
        delta: Int
    ) -> some View {
        let isEnabled = canAdvance(by: delta)
        return MistiaHeaderCircleButton {
            advance(by: delta)
        } content: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func canAdvance(by delta: Int) -> Bool {
        guard let target = calendar.date(byAdding: .month, value: delta, to: selection) else {
            return false
        }
        return bounds.contains(target, calendar: calendar)
    }

    private func advance(by delta: Int) {
        guard let target = calendar.date(byAdding: .month, value: delta, to: selection),
              bounds.contains(target, calendar: calendar)
        else {
            return
        }
        withAnimation(.snappy) {
            selection = PlanningLogic.startOfMonth(for: target, calendar: calendar)
        }
    }

    private func clampSelectionIfNeeded(_ date: Date? = nil) {
        let source = date ?? selection
        let clamped = bounds.clamped(source, calendar: calendar)
        if clamped != source {
            selection = clamped
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        Glass.regular
            .tint(accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .interactive()
    }
}
