import XCTest
@testable import MistiaCoreLogic

final class MistiaLocalizationTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_775_131_200) // 2026-04-02 12:00:00 UTC

    private struct DatePayload: Codable, Equatable {
        let occurredAt: Date
    }

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

    func testGeneratedL10nFollowsSelectedAppLanguage() {
        XCTAssertEqual(L10n.settings.title(language: .vietnamese), "Cài đặt")
        XCTAssertEqual(L10n.settings.title(language: .english), "Settings")
        XCTAssertEqual(L10n.settings.title(language: .japanese), "設定")

        MistiaAppLanguage.persist(.english)
        XCTAssertEqual(L10n.settings.title, "Settings")

        MistiaAppLanguage.persist(.japanese)
        XCTAssertEqual(L10n.settings.title, "設定")

        MistiaAppLanguage.persist(.vietnamese)
        XCTAssertEqual(L10n.common.cancel, "Hủy")
    }

    func testMonthYearFormattingUsesLanguageSpecificLocaleProfiles() {
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

    func testFullDateFormattingUsesSharedAppFormats() {
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(for: referenceDate, language: .vietnamese),
            "02/04/2026"
        )
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(for: referenceDate, language: .english),
            "2026-04-02"
        )
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(for: referenceDate, language: .japanese),
            "2026年4月2日"
        )
    }

    func testRemoteDateEncodingKeepsUTCInstantWhileFormattingInPhoneTimezone() throws {
        let japanCalendar = MistiaCalendar.gregorian(
            locale: Locale(identifier: "ja_JP"),
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )
        var components = DateComponents()
        components.calendar = japanCalendar
        components.year = 2026
        components.month = 5
        components.day = 6
        components.hour = 18
        components.minute = 15
        components.second = 49
        components.nanosecond = 204_000_000

        let localDate = try XCTUnwrap(japanCalendar.date(from: components))
        let encoded = try JSONEncoder.mistiaRemoteAPIEncoder.encode(DatePayload(occurredAt: localDate))
        let payload = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(payload.contains("\"occurredAt\":\"2026-05-06T09:15:49.204Z\""))
        XCTAssertEqual(
            MistiaDateFormatting.fullDateString(
                for: localDate,
                language: .japanese,
                calendar: japanCalendar
            ),
            "2026年5月6日"
        )

        let decoded = try JSONDecoder.mistiaRemoteAPIDecoder.decode(DatePayload.self, from: encoded)
        XCTAssertEqual(decoded.occurredAt, localDate)
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

    func testActiveSystemCategoryDefaultsHaveLanguageSpecificTitles() {
        for parentKey in MistiaSystemCategoryParentKey.activeDefaults {
            let knownNames = Set(parentKey.knownDefaultNames())

            XCTAssertTrue(knownNames.contains(parentKey.localizedTitle(for: .english)), parentKey.rawValue)
            XCTAssertTrue(knownNames.contains(parentKey.localizedTitle(for: .japanese)), parentKey.rawValue)
            XCTAssertNotEqual(
                parentKey.localizedTitle(for: .english),
                parentKey.localizedTitle(for: .vietnamese),
                parentKey.rawValue
            )
            XCTAssertNotEqual(
                parentKey.localizedTitle(for: .japanese),
                parentKey.localizedTitle(for: .vietnamese),
                parentKey.rawValue
            )
        }

        let englishMatchesVietnamese: Set<MistiaSystemCategoryKey> = [.internet, .gas, .cashback]
        for systemKey in MistiaSystemCategoryKey.activeDefaults {
            let knownNames = Set(systemKey.knownDefaultNames())

            XCTAssertTrue(knownNames.contains(systemKey.localizedTitle(for: .english)), systemKey.rawValue)
            XCTAssertTrue(knownNames.contains(systemKey.localizedTitle(for: .japanese)), systemKey.rawValue)
            if !englishMatchesVietnamese.contains(systemKey) {
                XCTAssertNotEqual(
                    systemKey.localizedTitle(for: .english),
                    systemKey.localizedTitle(for: .vietnamese),
                    systemKey.rawValue
                )
            }
            XCTAssertNotEqual(
                systemKey.localizedTitle(for: .japanese),
                systemKey.localizedTitle(for: .vietnamese),
                systemKey.rawValue
            )
        }
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

    func testDefaultIconColorsResolveToNearestPaletteColor() {
        XCTAssertEqual(MistiaIconColorPalette.presetHex(forDefault: "#F59B3F"), "#FF9F1C")
        XCTAssertEqual(MistiaIconColorPalette.presetHex(forDefault: "#FF7E67"), "#F26A5A")
        XCTAssertEqual(MistiaIconColorPalette.presetHex(forDefault: "#7C85A3"), "#8A8A8E")
        XCTAssertEqual(MistiaIconColorPalette.presetHex(forDefault: "#FFB13B"), "#FF9F1C")
        XCTAssertEqual(MistiaIconColorPalette.presetHex(forDefault: "#F45C7E"), "#F26A5A")
        XCTAssertEqual(MistiaIconColorPalette.presetHex(forDefault: "#8A6BFF"), "#9A67FF")

        XCTAssertEqual(MistiaIconColorPalette.presetHexes.count, 10)
        XCTAssertFalse(MistiaIconColorPalette.presetHexes.contains("#F59B3F"))
        XCTAssertFalse(MistiaIconColorPalette.presetHexes.contains("#7C85A3"))
    }

    func testDefaultIconAppearanceAcceptsStoredOrCanonicalDefaultColor() {
        XCTAssertTrue(
            LedgerWalletKind.creditCard.matchesDefaultIconAppearance(
                symbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
                colorHex: "#7C85A3"
            )
        )
        XCTAssertTrue(
            TransactionCategoryKind.expense.matchesDefaultIconAppearance(
                symbolName: TransactionCategoryKind.expense.defaultIconSymbolName,
                colorHex: MistiaIconColorPalette.presetHex(
                    forDefault: TransactionCategoryKind.expense.defaultColorHex
                )
            )
        )
        XCTAssertEqual(
            MistiaIconColorPalette.pickerSelectionHex(forStored: "#7C85A3"),
            "#7C85A3"
        )
        XCTAssertTrue(MistiaIconColorPalette.shouldShowCurrentSwatch(forStored: "#7C85A3"))
        XCTAssertTrue(MistiaIconColorPalette.shouldShowCurrentSwatch(forStored: "#123456"))
    }

    func testRecurringBillQuickPickDefaultsStayUniqueAndBillRelevant() {
        let quickPickKeys = MistiaSystemCategoryKey.recurringBillQuickPickDefaults

        XCTAssertEqual(quickPickKeys.count, Set(quickPickKeys).count)
        XCTAssertTrue(quickPickKeys.contains(.rent))
        XCTAssertTrue(quickPickKeys.contains(.mortgageInstallment))
        XCTAssertTrue(quickPickKeys.contains(.electricity))
        XCTAssertTrue(quickPickKeys.contains(.water))
        XCTAssertTrue(quickPickKeys.contains(.internet))
        XCTAssertTrue(quickPickKeys.contains(.phone))
        XCTAssertTrue(quickPickKeys.contains(.gas))
        XCTAssertTrue(quickPickKeys.contains(.publicTransport))
        XCTAssertTrue(quickPickKeys.contains(.parking))
        XCTAssertTrue(quickPickKeys.contains(.tolls))
        XCTAssertTrue(quickPickKeys.contains(.fuel))
        XCTAssertTrue(quickPickKeys.contains(.vehicleMaintenance))
        XCTAssertTrue(quickPickKeys.contains(.vehicleRepair))
        XCTAssertTrue(quickPickKeys.contains(.vehicleInsurance))
        XCTAssertTrue(quickPickKeys.contains(.vehicleRegistration))
        XCTAssertTrue(quickPickKeys.contains(.loanRepayment))
        XCTAssertFalse(quickPickKeys.contains(.otherExpense))
    }
}
