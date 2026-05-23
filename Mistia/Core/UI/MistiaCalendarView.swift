import SwiftUI

struct MistiaCalendarView: View {
    @Binding var selection: Date
    let calendar: Calendar
    let language: MistiaAppLanguage
    let selectableRange: AnyRange<Date>?
    let accent: Color

    @State private var displayedMonth: Date
    @State private var isMonthYearPickerPresented = false
    @Environment(\.mistiaCalendarHeaderHidden) private var isHeaderHidden

    init(
        selection: Binding<Date>,
        calendar: Calendar,
        language: MistiaAppLanguage = .current,
        selectableRange: AnyRange<Date>? = nil,
        accent: Color = MistiaAccent.purple.color
    ) {
        self._selection = selection
        self.calendar = calendar
        self.language = language
        self.selectableRange = selectableRange
        self.accent = accent
        _displayedMonth = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 16) {
            if !isHeaderHidden {
                header
            }
            calendarGrid
        }
        .onChange(of: selection) { _, newValue in
            if !calendar.isDate(newValue, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newValue
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            monthYearPicker

            Spacer()

            HStack(spacing: 20) {
                Button {
                    advanceMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)

                Button {
                    advanceMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)
        }
    }

    private var monthYearPicker: some View {
        Button {
            isMonthYearPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(MistiaDateFormatting.monthYearString(for: displayedMonth, calendar: calendar))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isMonthYearPickerPresented) {
            MistiaMonthYearWheelPicker(
                selection: $displayedMonth,
                calendar: calendar,
                language: language,
                selectableRange: selectableRange
            )
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


    @ViewBuilder
    private func dayButton(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let isEnabled = isSelectable(date)

        Button {
            selection = replacingDay(with: date)
        } label: {
            Text(verbatim: "\(calendar.component(.day, from: date))")
                .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(dayForegroundColor(isSelected: isSelected, isEnabled: isEnabled))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    Circle()
                        .fill(isSelected ? accent : (isToday ? accent.opacity(0.18) : Color.clear))
                }
                .overlay {
                    if isToday && !isSelected {
                        Circle()
                            .stroke(
                                accent.opacity(0.4),
                                lineWidth: 1
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }


    private var weekdayLabels: [String] {
        (0..<7).map { offset in
            let weekday = ((calendar.firstWeekday + offset - 1) % 7) + 1
            return MistiaDateFormatting.weekdayLabel(for: weekday, language: language)
        }
    }

    private var monthGridDays: [Date?] {
        guard let monthStart = startOfMonth(for: displayedMonth),
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


    private func replacingDay(with date: Date) -> Date {
        var selectedComponents = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: selection)
        selectedComponents.hour = timeComponents.hour
        selectedComponents.minute = timeComponents.minute
        selectedComponents.second = timeComponents.second
        selectedComponents.nanosecond = timeComponents.nanosecond
        let target = calendar.date(from: selectedComponents) ?? date
        return AnyRange.clamped(target, to: selectableRange, calendar: calendar)
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

    private func isSelectable(_ date: Date) -> Bool {
        guard let selectableRange else { return true }
        return selectableRange.contains(date, in: calendar)
    }

    private func dayForegroundColor(isSelected: Bool, isEnabled: Bool) -> Color {
        if isSelected { return .white }
        if isEnabled { return .primary }
        return .secondary.opacity(0.45)
    }

    private func advanceMonth(by delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.snappy) {
                displayedMonth = newMonth
            }
        }
    }
}

struct MistiaMonthYearWheelPicker: View {
    @Binding var selection: Date
    let calendar: Calendar
    let language: MistiaAppLanguage
    let selectableRange: AnyRange<Date>?

    private var monthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = calendar
        return formatter.monthSymbols
    }

    var body: some View {
        HStack(spacing: 4) {
            Picker(String(), selection: monthBinding) {
                ForEach(1...12, id: \.self) { month in
                    Text(monthTitle(for: month))
                        .tag(month)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: 150)
            .clipped()

            Picker(String(), selection: yearBinding) {
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
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: selection) },
            set: { updateSelection(month: $0, year: calendar.component(.year, from: selection)) }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: selection) },
            set: { updateSelection(month: calendar.component(.month, from: selection), year: $0) }
        )
    }

    private var yearRange: ClosedRange<Int> {
        let selectedYear = calendar.component(.year, from: selection)
        let currentYear = calendar.component(.year, from: .now)
        let start = min(selectedYear - 50, 1900)
        let end = max(selectedYear + 50, currentYear + 10)
        return start...end
    }

    private func updateSelection(month: Int, year: Int) {
        var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .nanosecond], from: selection)
        components.year = year
        components.month = month
        components.day = min(
            components.day ?? 1,
            numberOfDays(inMonth: month, year: year)
        )

        if let updatedDate = calendar.date(from: components) {
            selection = AnyRange.clamped(updatedDate, to: selectableRange, calendar: calendar)
        }
    }

    private func monthTitle(for month: Int) -> String {
        guard !monthSymbols.isEmpty else { return String(month) }
        return monthSymbols[max(0, min(month - 1, monthSymbols.count - 1))]
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
}

enum AnyRange<Bound: Comparable> {
    case closed(ClosedRange<Bound>)
    case through(PartialRangeThrough<Bound>)
    case from(PartialRangeFrom<Bound>)

    var lowerBound: Bound? {
        switch self {
        case .closed(let range): return range.lowerBound
        case .through: return nil
        case .from(let range): return range.lowerBound
        }
    }

    var upperBound: Bound? {
        switch self {
        case .closed(let range): return range.upperBound
        case .through(let range): return range.upperBound
        case .from: return nil
        }
    }

    func contains(_ value: Bound) -> Bool {
        switch self {
        case .closed(let range): return range.contains(value)
        case .through(let range): return range.contains(value)
        case .from(let range): return range.contains(value)
        }
    }
}

extension AnyRange where Bound == Date {
    static func clamped(_ date: Date, to range: AnyRange<Date>?, calendar: Calendar) -> Date {
        guard let range else { return date }
        if range.contains(date, in: calendar) {
            return date
        }

        if let lower = range.lowerBound {
            let lowerDay = calendar.startOfDay(for: lower)
            let day = calendar.startOfDay(for: date)
            if day < lowerDay { return lowerDay }
        }

        if let upper = range.upperBound {
            let upperDay = calendar.startOfDay(for: upper)
            let day = calendar.startOfDay(for: date)
            if day > upperDay { return upperDay }
        }

        return date
    }

    func contains(_ date: Date, in calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)

        switch self {
        case .closed(let range):
            return day >= calendar.startOfDay(for: range.lowerBound) &&
                   day <= calendar.startOfDay(for: range.upperBound)
        case .through(let range):
            return day <= calendar.startOfDay(for: range.upperBound)
        case .from(let range):
            return day >= calendar.startOfDay(for: range.lowerBound)
        }
    }
}

private struct MistiaCalendarHeaderHiddenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var mistiaCalendarHeaderHidden: Bool {
        get { self[MistiaCalendarHeaderHiddenKey.self] }
        set { self[MistiaCalendarHeaderHiddenKey.self] = newValue }
    }
}

extension View {
    func calendarHeaderHidden(_ hidden: Bool = true) -> some View {
        environment(\.mistiaCalendarHeaderHidden, hidden)
    }
}
