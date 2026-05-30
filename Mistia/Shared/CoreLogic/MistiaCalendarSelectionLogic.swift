import Foundation

enum MistiaCalendarSelectionLogic {
    static func replacingMonthYear(
        in selection: Date,
        month: Int,
        year: Int,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: selection
        )
        components.year = year
        components.month = month
        components.day = min(
            components.day ?? 1,
            numberOfDays(inMonth: month, year: year, calendar: calendar)
        )

        return calendar.date(from: components) ?? selection
    }

    private static func numberOfDays(inMonth month: Int, year: Int, calendar: Calendar) -> Int {
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
