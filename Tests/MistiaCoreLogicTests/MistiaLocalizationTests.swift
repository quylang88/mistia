import XCTest
@testable import MistiaCoreLogic

final class MistiaLocalizationTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_775_131_200) // 2026-04-02 12:00:00 UTC

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(
            MistiaAppLanguage.vietnamese.rawValue,
            forKey: MistiaAppLanguage.userDefaultsKey
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        super.tearDown()
    }

    func testInferLanguageFromPreferredLanguages() {
        XCTAssertEqual(
            MistiaAppLanguage.infer(preferredLanguages: ["vi-VN", "en-US"]),
            .vietnamese
        )
        XCTAssertEqual(
            MistiaAppLanguage.infer(preferredLanguages: ["ja-JP", "en-US"]),
            .japanese
        )
        XCTAssertEqual(
            MistiaAppLanguage.infer(preferredLanguages: ["en-GB"]),
            .english
        )
    }

    func testResolveFallsBackToEnglishForUnsupportedLanguage() {
        XCTAssertEqual(
            MistiaAppLanguage.resolve(
                storedRawValue: nil,
                preferredLanguages: ["fr-FR", "de-DE"]
            ),
            .english
        )
        XCTAssertEqual(
            MistiaAppLanguage.resolve(
                storedRawValue: "ja",
                preferredLanguages: ["vi-VN"]
            ),
            .japanese
        )
    }

    func testDateFormattingUsesLanguageSpecificLocaleProfiles() {
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(for: referenceDate, language: .vietnamese),
            "02/04/2026"
        )
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(for: referenceDate, language: .english),
            "04/02/2026"
        )
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(for: referenceDate, language: .japanese),
            "2026/04/02"
        )

        XCTAssertEqual(
            MistiaDateFormatting.monthYearString(for: referenceDate, language: .vietnamese),
            "tháng 4 năm 2026"
        )
        XCTAssertEqual(
            MistiaDateFormatting.monthYearString(for: referenceDate, language: .english),
            "April 2026"
        )
        XCTAssertEqual(
            MistiaDateFormatting.monthYearString(for: referenceDate, language: .japanese),
            "2026年4月"
        )
    }

    func testRelativeLabelsFollowSelectedLanguage() {
        let sameDay = referenceDate.addingTimeInterval(-25 * 60)
        XCTAssertEqual(
            MistiaDateFormatting.relativeTimeLabel(
                for: sameDay,
                referenceDate: referenceDate,
                calendar: gregorianCalendar,
                language: .vietnamese
            ),
            "25 phút trước"
        )
        XCTAssertEqual(
            MistiaDateFormatting.relativeTimeLabel(
                for: sameDay,
                referenceDate: referenceDate,
                calendar: gregorianCalendar,
                language: .english
            ),
            "25 min ago"
        )
        XCTAssertEqual(
            MistiaDateFormatting.relativeTimeLabel(
                for: sameDay,
                referenceDate: referenceDate,
                calendar: gregorianCalendar,
                language: .japanese
            ),
            "25分前"
        )

        XCTAssertEqual(
            MistiaDateFormatting.relativeDayLabel(for: 0, language: .vietnamese),
            "Hôm nay"
        )
        XCTAssertEqual(
            MistiaDateFormatting.relativeDayLabel(for: 1, language: .english),
            "Yesterday"
        )
        XCTAssertEqual(
            MistiaDateFormatting.relativeDayLabel(for: 2, language: .japanese),
            "一昨日"
        )
    }

    func testSystemCategoryLocalizedTitlesPreserveKnownDefaultNames() {
        let systemKey = MistiaSystemCategoryKey.food

        XCTAssertEqual(systemKey.localizedTitle(for: .vietnamese), "Ăn uống")
        XCTAssertEqual(systemKey.localizedTitle(for: .english), "Food & drinks")
        XCTAssertEqual(systemKey.localizedTitle(for: .japanese), "食費")

        let knownNames = Set(systemKey.knownDefaultNames())
        XCTAssertTrue(knownNames.contains("Ăn uống"))
        XCTAssertTrue(knownNames.contains("Food & drinks"))
        XCTAssertTrue(knownNames.contains("食費"))
    }

    func testCurrencyFormattingDoesNotChangeWhenAppLanguageChanges() {
        UserDefaults.standard.set(
            MistiaAppLanguage.vietnamese.rawValue,
            forKey: MistiaAppLanguage.userDefaultsKey
        )
        let vietnameseJPY = Int64(123_456).formattedCurrency(code: "JPY")

        UserDefaults.standard.set(
            MistiaAppLanguage.english.rawValue,
            forKey: MistiaAppLanguage.userDefaultsKey
        )
        let englishJPY = Int64(123_456).formattedCurrency(code: "JPY")

        UserDefaults.standard.set(
            MistiaAppLanguage.japanese.rawValue,
            forKey: MistiaAppLanguage.userDefaultsKey
        )
        let japaneseJPY = Int64(123_456).formattedCurrency(code: "JPY")

        XCTAssertEqual(vietnameseJPY, englishJPY)
        XCTAssertEqual(englishJPY, japaneseJPY)
        XCTAssertTrue(vietnameseJPY.first.map { $0 == "¥" || $0 == "￥" } ?? false)
    }
}
