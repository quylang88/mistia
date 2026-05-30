import SwiftUI

struct MistiaMonthPickerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: Date

    let calendar: Calendar
    let accentColor: Color

    @State private var draftMonth: Int
    @State private var draftYear: Int

    init(selection: Binding<Date>, calendar: Calendar, accentColor: Color) {
        _selection = selection
        self.calendar = calendar
        self.accentColor = accentColor
        let initialDate = selection.wrappedValue
        _draftMonth = State(initialValue: calendar.component(.month, from: initialDate))
        _draftYear = State(initialValue: calendar.component(.year, from: initialDate))
    }

    var body: some View {
        MistiaModalScaffold(
            title: L10n.planning.planning.chooseMonth,
            accent: accentColor,
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
        let currentYear = calendar.component(.year, from: .now)
        if draftYear < currentYear {
            return Array(1...12)
        } else {
            let currentMonth = calendar.component(.month, from: .now)
            return Array(1...currentMonth)
        }
    }

    private var yearOptions: [Int] {
        let currentYear = calendar.component(.year, from: .now)
        let lowerBound = currentYear - 10
        let upperBound = currentYear
        return Array(lowerBound...upperBound)
    }

    private func validateDraft() {
        let currentYear = calendar.component(.year, from: .now)
        let currentMonth = calendar.component(.month, from: .now)
        
        if draftYear == currentYear && draftMonth > currentMonth {
            draftMonth = currentMonth
        }
    }

    private func applySelection() {
        guard let date = calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: 1)) else {
            return
        }

        let startOfTarget = PlanningLogic.startOfMonth(for: date, calendar: calendar)
        let startOfCurrent = PlanningLogic.startOfMonth(for: .now, calendar: calendar)

        if startOfTarget > startOfCurrent {
            selection = startOfCurrent
        } else {
            selection = startOfTarget
        }
    }
}
