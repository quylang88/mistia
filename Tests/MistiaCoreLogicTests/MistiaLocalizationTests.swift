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
        MistiaAppLanguage.persist(.vietnamese)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
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
        MistiaAppLanguage.persist(.vietnamese)
        let vietnameseJPY = Int64(123_456).formattedCurrency(code: "JPY")

        MistiaAppLanguage.persist(.english)
        let englishJPY = Int64(123_456).formattedCurrency(code: "JPY")

        MistiaAppLanguage.persist(.japanese)
        let japaneseJPY = Int64(123_456).formattedCurrency(code: "JPY")

        XCTAssertEqual(vietnameseJPY, englishJPY)
        XCTAssertEqual(englishJPY, japaneseJPY)
        XCTAssertTrue(vietnameseJPY.first.map { $0 == "¥" || $0 == "￥" } ?? false)
    }

    func testBootstrapStoredPreferenceRestoresBackupBeforeInferringSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.set(
            MistiaAppLanguage.japanese.rawValue,
            forKey: MistiaAppLanguage.backupUserDefaultsKey
        )

        let restored = MistiaAppLanguage.bootstrapStoredPreference(
            preferredLanguages: ["vi-VN", "en-US"]
        )

        XCTAssertEqual(restored, .japanese)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: MistiaAppLanguage.userDefaultsKey),
            MistiaAppLanguage.japanese.rawValue
        )
    }

    func testLegacyDefaultIconColorsMapIntoCurrentPalette() {
        XCTAssertEqual(MistiaIconColorPalette.migratedLegacyDefaultHex("#F59B3F"), "#FF9F1C")
        XCTAssertEqual(MistiaIconColorPalette.migratedLegacyDefaultHex("#FF7E67"), "#F26A5A")
        XCTAssertEqual(MistiaIconColorPalette.migratedLegacyDefaultHex("#7C85A3"), "#8A8A8E")
        XCTAssertEqual(MistiaIconColorPalette.migratedLegacyDefaultHex("#FFB13B"), "#FF9F1C")
        XCTAssertEqual(MistiaIconColorPalette.migratedLegacyDefaultHex("#F45C7E"), "#F26A5A")
        XCTAssertEqual(MistiaIconColorPalette.migratedLegacyDefaultHex("#8A6BFF"), "#9A67FF")

        XCTAssertEqual(MistiaIconColorPalette.presetHexes.count, 10)
        XCTAssertFalse(MistiaIconColorPalette.presetHexes.contains("#F59B3F"))
        XCTAssertFalse(MistiaIconColorPalette.presetHexes.contains("#7C85A3"))
    }

    func testLegacyDefaultIconAppearanceStillCountsAsDefault() {
        XCTAssertTrue(
            LedgerWalletKind.creditCard.matchesDefaultIconAppearance(
                symbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
                colorHex: "#7C85A3"
            )
        )
        XCTAssertTrue(
            TransactionCategoryKind.expense.matchesDefaultIconAppearance(
                symbolName: TransactionCategoryKind.expense.defaultIconSymbolName,
                colorHex: "#F59B3F"
            )
        )
        XCTAssertEqual(
            MistiaIconColorPalette.pickerSelectionHex(forStored: "#7C85A3"),
            "#8A8A8E"
        )
        XCTAssertFalse(MistiaIconColorPalette.shouldShowCurrentSwatch(forStored: "#7C85A3"))
        XCTAssertTrue(MistiaIconColorPalette.shouldShowCurrentSwatch(forStored: "#123456"))
    }
}
