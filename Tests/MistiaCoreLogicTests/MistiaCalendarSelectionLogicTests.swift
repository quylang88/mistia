import XCTest
@testable import MistiaCoreLogic

final class MistiaCalendarSelectionLogicTests: XCTestCase {
    func testReplacingMonthYearPreservesDayAndTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let original = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 2,
            hour: 15,
            minute: 45,
            second: 30
        )))

        let updated = MistiaCalendarSelectionLogic.replacingMonthYear(
            in: original,
            month: 8,
            year: 2026,
            calendar: calendar
        )

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: updated)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 2)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 45)
        XCTAssertEqual(components.second, 30)
    }

    func testReplacingMonthYearClampsDayToTargetMonthLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let original = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 31,
            hour: 9,
            minute: 10
        )))

        let updated = MistiaCalendarSelectionLogic.replacingMonthYear(
            in: original,
            month: 2,
            year: 2026,
            calendar: calendar
        )

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: updated)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 10)
    }
}
