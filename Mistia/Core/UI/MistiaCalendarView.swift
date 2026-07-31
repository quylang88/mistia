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
    @Environment(\.colorScheme) private var colorScheme

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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                
                Button {
                    advanceMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
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
                    .foregroundStyle(MistiaAccent.lightPurple.color)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MistiaAccent.lightPurple.color)
                    .rotationEffect(.degrees(isMonthYearPickerPresented ? 90 : 0))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isMonthYearPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            MistiaMonthYearWheelPicker(
                selection: $selection,
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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
        guard let selectableRange = selectableRange else { return true }
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
    private let monthSymbols: [String]

    init(
        selection: Binding<Date>,
        calendar: Calendar,
        language: MistiaAppLanguage,
        selectableRange: AnyRange<Date>?
    ) {
        self._selection = selection
        self.calendar = calendar
        self.language = language
        self.selectableRange = selectableRange
        self.monthSymbols = Self.makeMonthSymbols(calendar: calendar, language: language)
    }

    private static func makeMonthSymbols(
        calendar: Calendar,
        language: MistiaAppLanguage
    ) -> [String] {
        MonthSymbolsCache.symbols(for: calendar, language: language)
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
        let updatedDate = MistiaCalendarSelectionLogic.replacingMonthYear(
            in: selection,
            month: month,
            year: year,
            calendar: calendar
        )
        selection = AnyRange.clamped(updatedDate, to: selectableRange, calendar: calendar)
    }

    private func monthTitle(for month: Int) -> String {
        guard !monthSymbols.isEmpty else { return String(month) }
        return monthSymbols[max(0, min(month - 1, monthSymbols.count - 1))]
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

private struct MonthSymbolsKey: Hashable {
    let calendarIdentifier: Calendar.Identifier
    let localeIdentifier: String
}

private enum MonthSymbolsCache {
    private static var cache: [MonthSymbolsKey: [String]] = [:]
    private static let lock = NSLock()

    static func symbols(for calendar: Calendar, language: MistiaAppLanguage) -> [String] {
        let key = MonthSymbolsKey(
            calendarIdentifier: calendar.identifier,
            localeIdentifier: language.locale.identifier
        )
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = calendar
        let symbols = formatter.monthSymbols ?? []
        cache[key] = symbols
        return symbols
    }
}
