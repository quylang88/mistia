import SwiftUI

enum MistiaDatePickerMode {
    case date
    case dateAndTime
}

struct MistiaDatePickerRow: View {
    let title: String
    @Binding var selection: Date
    var mode: MistiaDatePickerMode = .date

    @Environment(\.calendar) private var calendar
    @State private var isPickerPresented = false

    var body: some View {
        switch mode {
        case .date:
            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(dateText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .buttonStyle(.plain)
            .datePickerPopover(
                isPresented: $isPickerPresented,
                selection: $selection,
                calendar: calendar
            )

        case .dateAndTime:
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                DatePicker(
                    "",
                    selection: $selection,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.locale, MistiaAppLanguage.current.locale)
                .tint(MistiaAccent.purple.color)

                Button {
                    isPickerPresented = true
                } label: {
                    Text(dateText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .buttonStyle(.plain)
            }
            .datePickerPopover(
                isPresented: $isPickerPresented,
                selection: $selection,
                calendar: calendar
            )
        }
    }

    private var dateText: String {
        MistiaDateFormatting.fullDateString(for: selection, calendar: calendar)
    }
}

private extension View {
    func datePickerPopover(
        isPresented: Binding<Bool>,
        selection: Binding<Date>,
        calendar: Calendar
    ) -> some View {
        popover(isPresented: isPresented) {
            MistiaDatePickerPanel(
                selection: selection,
                calendar: calendar
            )
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium])
        }
    }
}

private struct MistiaDatePickerPanel: View {
    @Binding var selection: Date
    let calendar: Calendar

    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: Date
    @State private var isMonthYearPickerPresented = false

    init(selection: Binding<Date>, calendar: Calendar) {
        self._selection = selection
        self.calendar = calendar
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            calendarGrid
        }
        .padding(18)
        .frame(minWidth: 320)
        .background(groupedBackground)
        .presentationBackground(groupedBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            MistiaHeaderCircleButton(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            monthYearPicker
                .frame(maxWidth: .infinity)

            Button {
                selection = draftSelection
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
        }
        .frame(height: 36)
    }

    private var monthYearPicker: some View {
        Button {
            isMonthYearPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(MistiaDateFormatting.monthYearString(for: draftSelection, calendar: calendar))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isMonthYearPickerPresented) {
            monthYearWheelPicker
                .presentationCompactAdaptation(.popover)
        }
    }

    private var calendarGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: calendarColumns, spacing: 8) {
                ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(for: date)
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var monthYearWheelPicker: some View {
        HStack(spacing: 4) {
            Picker("", selection: monthBinding) {
                ForEach(1...12, id: \.self) { month in
                    Text(monthTitle(for: month))
                        .tag(month)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: 150)
            .clipped()

            Picker("", selection: yearBinding) {
                ForEach(yearRange, id: \.self) { year in
                    Text(String(year))
                        .tag(year)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: 104)
            .clipped()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 292, height: 180)
        .background(groupedBackground)
    }

    @ViewBuilder
    private func dayButton(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: draftSelection)
        let isToday = calendar.isDateInToday(date)

        Button {
            draftSelection = replacingDay(with: date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    Circle()
                        .fill(isSelected ? MistiaAccent.purple.color : Color.clear)
                }
                .overlay {
                    Circle()
                        .stroke(
                            isToday && !isSelected ? MistiaAccent.purple.color.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private var groupedBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: draftSelection) },
            set: { updateDraftSelection(month: $0, year: calendar.component(.year, from: draftSelection)) }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: draftSelection) },
            set: { updateDraftSelection(month: calendar.component(.month, from: draftSelection), year: $0) }
        )
    }

    private var yearRange: ClosedRange<Int> {
        let selectedYear = calendar.component(.year, from: draftSelection)
        return (selectedYear - 50)...(selectedYear + 50)
    }

    private var weekdayLabels: [String] {
        (0..<7).map { offset in
            let weekday = ((calendar.firstWeekday + offset - 1) % 7) + 1
            return weekdayLabel(for: weekday)
        }
    }

    private var monthGridDays: [Date?] {
        guard let monthStart = startOfMonth(for: draftSelection),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        let rawDays: [Date?] = Array(repeating: nil, count: leadingEmptyDays) + dates.map(Optional.some)
        let trailingEmptyDays = (7 - rawDays.count % 7) % 7
        return rawDays + Array(repeating: nil, count: trailingEmptyDays)
    }

    private func updateDraftSelection(month: Int, year: Int) {
        var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .nanosecond], from: draftSelection)
        components.year = year
        components.month = month
        components.day = min(
            components.day ?? 1,
            numberOfDays(inMonth: month, year: year)
        )

        if let updatedDate = calendar.date(from: components) {
            draftSelection = updatedDate
        }
    }

    private func replacingDay(with date: Date) -> Date {
        var selectedComponents = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: draftSelection)
        selectedComponents.hour = timeComponents.hour
        selectedComponents.minute = timeComponents.minute
        selectedComponents.second = timeComponents.second
        selectedComponents.nanosecond = timeComponents.nanosecond
        return calendar.date(from: selectedComponents) ?? date
    }

    private func startOfMonth(for date: Date) -> Date? {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return calendar.date(from: components)
    }

    private func numberOfDays(inMonth month: Int, year: Int) -> Int {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 31 }
        return range.count
    }

    private func monthTitle(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = MistiaAppLanguage.current.locale
        formatter.calendar = calendar
        return formatter.monthSymbols[max(0, min(month - 1, formatter.monthSymbols.count - 1))]
    }

    private func weekdayLabel(for weekday: Int) -> String {
        switch MistiaAppLanguage.current {
        case .vietnamese:
            return ["CN", "T2", "T3", "T4", "T5", "T6", "T7"][max(0, min(weekday - 1, 6))]
        case .english:
            return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][max(0, min(weekday - 1, 6))]
        case .japanese:
            return ["日", "月", "火", "水", "木", "金", "土"][max(0, min(weekday - 1, 6))]
        }
    }
}
