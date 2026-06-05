import Foundation
import XCTest
@testable import Mistia

final class MistiaLocalizationTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_775_131_200) // 2026-04-02 12:00:00 UTC

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    func testDateTimeFormattingUsesLocaleSpecificTimestampOrder() {
        XCTAssertEqual(
            MistiaDateFormatting.dateTimeString(
                for: referenceDate,
                language: .vietnamese,
                calendar: gregorianCalendar
            ),
            "12:00 ngày 2 tháng 4, năm 2026"
        )
        XCTAssertEqual(
            MistiaDateFormatting.dateTimeString(
                for: referenceDate,
                language: .english,
                calendar: gregorianCalendar
            ),
            "2026-04-02 12:00"
        )
        XCTAssertEqual(
            MistiaDateFormatting.dateTimeString(
                for: referenceDate,
                language: .japanese,
                calendar: gregorianCalendar
            ),
            "2026年4月2日 12:00"
        )
    }
}
