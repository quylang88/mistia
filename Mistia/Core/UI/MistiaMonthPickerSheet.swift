import SwiftUI

struct MistiaMonthPickerSheet: View {
    @Binding var selection: Date

    let calendar: Calendar
    let accentColor: Color
    let bounds: MistiaMonthSelectionBounds

    @State private var draftMonth: Int
    @State private var draftYear: Int

    init(
        selection: Binding<Date>,
        calendar: Calendar,
        accentColor: Color,
        bounds: MistiaMonthSelectionBounds? = nil
    ) {
        _selection = selection
        self.calendar = calendar
        self.accentColor = accentColor
        let resolvedBounds = bounds ?? .standard(calendar: calendar)
        self.bounds = resolvedBounds
        let initialDate = resolvedBounds.clamped(selection.wrappedValue, calendar: calendar)
        _draftMonth = State(initialValue: calendar.component(.month, from: initialDate))
        _draftYear = State(initialValue: calendar.component(.year, from: initialDate))
    }

    var body: some View {
        MistiaModalScaffold(
            title: L10n.planning.planning.chooseMonth,
            accent: accentColor,
            dismissGuardConfiguration: MistiaDismissGuardConfiguration(
                mode: .editing,
                hasUnsavedChanges: draftDate != bounds.clamped(selection, calendar: calendar)
            ),
            onSave: applySelection
        ) {
            HStack(spacing: 0) {
                Picker(L10n.planning.planning.month, selection: $draftMonth) {
                    ForEach(allowedMonths, id: \.self) { month in
                        Text(
                            L10n.planning.planning.monthValue(String(describing: month))
                        )
                        .tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker(L10n.planning.planning.year, selection: $draftYear) {
                    ForEach(yearOptions, id: \.self) { year in
                        Text(
                            L10n.planning.planning.yearValue(String(describing: year))
                        )
                        .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .onChange(of: draftYear) { _, _ in
                    validateDraft()
                }
            }
            .frame(height: 220)
        }
    }

    private var allowedMonths: [Int] {
        var lowerBound = 1
        var upperBound = 12
        if draftYear == calendar.component(.year, from: bounds.minimumMonth) {
            lowerBound = calendar.component(.month, from: bounds.minimumMonth)
        }
        if draftYear == calendar.component(.year, from: bounds.maximumMonth) {
            upperBound = calendar.component(.month, from: bounds.maximumMonth)
        }
        return lowerBound <= upperBound ? Array(lowerBound...upperBound) : []
    }

    private var yearOptions: [Int] {
        let lowerBound = calendar.component(.year, from: bounds.minimumMonth)
        let upperBound = calendar.component(.year, from: bounds.maximumMonth)
        return Array(lowerBound...upperBound)
    }

    private var draftDate: Date {
        calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: 1))
            .map { bounds.clamped($0, calendar: calendar) }
            ?? bounds.clamped(selection, calendar: calendar)
    }

    private func validateDraft() {
        guard let date = calendar.date(
            from: DateComponents(year: draftYear, month: draftMonth, day: 1)
        ) else { return }
        let clamped = bounds.clamped(date, calendar: calendar)
        draftMonth = calendar.component(.month, from: clamped)
        draftYear = calendar.component(.year, from: clamped)
    }

    private func applySelection() {
        guard let date = calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: 1)) else {
            return
        }

        selection = bounds.clamped(date, calendar: calendar)
    }
}
