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

    func testCurrencyInputFormattingGroupsThousandsWhileTyping() {
        XCTAssertEqual(MistiaCurrencyInputFormatting.groupedInput("1234"), "1,234")
        XCTAssertEqual(MistiaCurrencyInputFormatting.groupedInput("1234567"), "1,234,567")
        XCTAssertEqual(MistiaCurrencyInputFormatting.groupedInput("12,34a56"), "123,456")
        XCTAssertEqual(MistiaCurrencyInputFormatting.groupedInput(""), "")
    }

    func testCurrencyInputParsingIgnoresGroupingSeparators() {
        XCTAssertEqual("1,234,567".currencyInputToMinorUnits(currencyCode: "JPY"), 1_234_567)
        XCTAssertEqual("12,34a56".currencyInputToMinorUnits(currencyCode: "VND"), 123_456)
    }
}
