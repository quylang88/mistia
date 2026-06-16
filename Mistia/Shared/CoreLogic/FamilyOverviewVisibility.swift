import Foundation

nonisolated enum FamilyOverviewVisibility {
    static func showsAssetSummary(
        selectedMonth: Date,
        now: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> Bool {
        calendar.isDate(selectedMonth, equalTo: now, toGranularity: .month)
    }
}
