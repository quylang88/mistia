import Foundation

nonisolated enum MistiaAppLanguage: String, CaseIterable, Identifiable, Codable {
    case vietnamese = "vi"
    case english = "en"
    case japanese = "ja"

    static let userDefaultsKey = "mistia.settings.app.language"
    static let backupUserDefaultsKey = "mistia.settings.app.language.backup"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .vietnamese:
            "vi_VN"
        case .english:
            "en_US"
        case .japanese:
            "ja_JP"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    var calendar: Calendar {
        MistiaCalendar.gregorian(locale: locale)
    }

    var displayName: String {
        switch self {
        case .vietnamese:
            L10n.settings.language.option.vietnamese
        case .english:
            L10n.settings.language.option.english
        case .japanese:
            L10n.settings.language.option.japanese
        }
    }

    static func infer(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("vi") {
                return .vietnamese
            }

            if normalized.hasPrefix("ja") {
                return .japanese
            }

            if normalized.hasPrefix("en") {
                return .english
            }
        }

        return .english
    }

    static func resolve(
        storedRawValue: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Self {
        if let storedRawValue,
           let storedLanguage = Self(rawValue: storedRawValue) {
            return storedLanguage
        }

        return infer(preferredLanguages: preferredLanguages)
    }

    static func persist(_ language: Self, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: userDefaultsKey)
        defaults.set(language.rawValue, forKey: backupUserDefaultsKey)
    }

    @discardableResult
    static func bootstrapStoredPreference(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Self {
        if let storedRawValue = defaults.string(forKey: userDefaultsKey),
           let storedLanguage = Self(rawValue: storedRawValue) {
            defaults.set(storedLanguage.rawValue, forKey: backupUserDefaultsKey)
            return storedLanguage
        }

        if let backupRawValue = defaults.string(forKey: backupUserDefaultsKey),
           let backupLanguage = Self(rawValue: backupRawValue) {
            defaults.set(backupLanguage.rawValue, forKey: userDefaultsKey)
            return backupLanguage
        }

        let inferredLanguage = infer(preferredLanguages: preferredLanguages)
        persist(inferredLanguage, defaults: defaults)
        return inferredLanguage
    }

    static var current: Self {
        let defaults = UserDefaults.standard
        if let storedRawValue = defaults.string(forKey: userDefaultsKey) {
            return resolve(storedRawValue: storedRawValue)
        }

        if let backupRawValue = defaults.string(forKey: backupUserDefaultsKey) {
            return resolve(storedRawValue: backupRawValue)
        }

        return infer()
    }
}

nonisolated enum MistiaCalendar {
    static var current: Calendar {
        gregorian(locale: .autoupdatingCurrent)
    }

    static func gregorian(
        locale: Locale? = nil,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale ?? .autoupdatingCurrent
        calendar.timeZone = timeZone
        return calendar
    }
}

nonisolated enum MistiaDateFormatting {
    private static let formatterCache = MistiaDateFormatterCache()

    static func shortDateString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        formatterCache.string(
            from: date,
            language: language,
            calendar: calendar,
            style: .dateFormat("dd/MM")
        )
    }

    static func fullDateString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let dateFormat: String
        switch language {
        case .vietnamese:
            dateFormat = "dd/MM/yyyy"
        case .english:
            dateFormat = "yyyy-MM-dd"
        case .japanese:
            dateFormat = "yyyy年M月d日"
        }
        return formatterCache.string(
            from: date,
            language: language,
            calendar: calendar,
            style: .dateFormat(dateFormat)
        )
    }

    static func dateTimeString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let dateFormat: String
        switch language {
        case .vietnamese:
            dateFormat = "HH:mm 'ngày' d 'tháng' M, yyyy"
        case .english:
            dateFormat = "yyyy-MM-dd HH:mm"
        case .japanese:
            dateFormat = "yyyy年M月d日 HH:mm"
        }
        return formatterCache.string(
            from: date,
            language: language,
            calendar: calendar,
            style: .dateFormat(dateFormat)
        )
    }

    static func monthYearString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        formatterCache.string(
            from: date,
            language: language,
            calendar: calendar,
            style: .localizedTemplate("yMMMM")
        )
    }

    static func statementMonthYearString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let dateFormat: String
        switch language {
        case .vietnamese, .english:
            dateFormat = "MM/yyyy"
        case .japanese:
            dateFormat = "yyyy年MM月"
        }
        return formatterCache.string(
            from: date,
            language: language,
            calendar: calendar,
            style: .dateFormat(dateFormat)
        )
    }

    static func weekRangeTitle(
        start: Date,
        end: Date,
        isCurrentWeek: Bool,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let range = "\(shortDateString(for: start, language: language, calendar: calendar)) - \(shortDateString(for: end, language: language, calendar: calendar))"
        guard isCurrentWeek else { return range }
        return L10n.shared.corelogic.mistialocalization.thisWeekValue(String(describing: range))
    }

    static func weekdayLabel(
        for date: Date,
        calendar: Calendar,
        language: MistiaAppLanguage = .current
    ) -> String {
        let weekday = calendar.component(.weekday, from: date)
        return weekdayLabel(for: weekday, language: language)
    }

    static func weekdayLabel(
        for weekday: Int,
        language: MistiaAppLanguage = .current
    ) -> String {
        let labels: [String]

        switch language {
        case .vietnamese:
            labels = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
        case .english:
            labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        case .japanese:
            labels = ["日", "月", "火", "水", "木", "金", "土"]
        }

        return labels[max(min(weekday - 1, labels.count - 1), 0)]
    }

    static func relativeDayLabel(
        for dayDelta: Int,
        language: MistiaAppLanguage = .current
    ) -> String? {
        switch dayDelta {
        case 0:
            return L10n.shared.corelogic.mistialocalization.today(language: language)
        case 1:
            return L10n.shared.corelogic.mistialocalization.yesterday(language: language)
        case 2:
            return L10n.shared.corelogic.mistialocalization.daysAgo(language: language)
        default:
            return nil
        }
    }

    static func relativeTimeLabel(
        for date: Date,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current,
        language: MistiaAppLanguage = .current
    ) -> String {
        let diff = referenceDate.timeIntervalSince(date)

        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dateDay = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: dateDay, to: referenceDay).day ?? 0

        if dayDelta == 0, diff < 3600 {
            let minutes = max(Int(diff / 60), 1)
            return L10n.shared.corelogic.mistialocalization.valueMinAgo(String(describing: minutes), language: language)
        }

        if dayDelta == 0, diff < 6 * 3600 {
            let hours = max(Int(diff / 3600), 1)
            return L10n.shared.corelogic.mistialocalization.valueHrAgo(String(describing: hours), language: language)
        }

        if let label = relativeDayLabel(for: dayDelta, language: language) {
            return label
        }

        return shortDateString(for: date, language: language, calendar: calendar)
    }

}

nonisolated private final class MistiaDateFormatterCache: @unchecked Sendable {
    private var formatters: [MistiaDateFormatterCacheKey: DateFormatter] = [:]
    private let lock = NSLock()

    func string(
        from date: Date,
        language: MistiaAppLanguage,
        calendar: Calendar?,
        style: MistiaDateFormatterCacheStyle
    ) -> String {
        let resolvedCalendar = calendar ?? language.calendar
        let key = MistiaDateFormatterCacheKey(
            languageRawValue: language.rawValue,
            calendarIdentifier: String(describing: resolvedCalendar.identifier),
            localeIdentifier: language.locale.identifier,
            timeZoneIdentifier: resolvedCalendar.timeZone.identifier,
            style: style
        )

        lock.lock()
        defer { lock.unlock() }

        if let formatter = formatters[key] {
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = resolvedCalendar
        formatter.timeZone = resolvedCalendar.timeZone
        switch style {
        case .dateFormat(let dateFormat):
            formatter.dateFormat = dateFormat
        case .localizedTemplate(let template):
            formatter.setLocalizedDateFormatFromTemplate(template)
        }

        formatters[key] = formatter
        return formatter.string(from: date)
    }
}

nonisolated private struct MistiaDateFormatterCacheKey: Hashable {
    let languageRawValue: String
    let calendarIdentifier: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let style: MistiaDateFormatterCacheStyle
}

nonisolated private enum MistiaDateFormatterCacheStyle: Hashable {
    case dateFormat(String)
    case localizedTemplate(String)
}

nonisolated enum MistiaIconColorPalette {
    static let fallbackHex = "#8A8A8E"

    static let presetHexes: [String] = [
        "#2DAA9E",
        "#6BCB77",
        "#F26A5A",
        "#FF9F1C",
        "#FFE45E",
        "#57B7FF",
        "#5B7BFF",
        "#FF6FB5",
        "#9A67FF",
        "#8A8A8E"
    ]

    static func normalizedHex(_ hex: String) -> String {
        let sanitized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        if sanitized.count == 8 {
            let prefix = String(sanitized.prefix(6))
            if isHexString(prefix) {
                return "#\(prefix)"
            }
        }

        if sanitized.count == 6, isHexString(sanitized) {
            return "#\(sanitized)"
        }

        return fallbackHex
    }

    static func containsPreset(_ hex: String) -> Bool {
        presetHexes.contains(normalizedHex(hex))
    }

    static func pickerSelectionHex(forStored hex: String) -> String {
        normalizedHex(hex)
    }

    static func shouldShowCurrentSwatch(forStored hex: String) -> Bool {
        let normalized = normalizedHex(hex)
        return !containsPreset(normalized)
    }

    static func presetHex(forDefault hex: String) -> String {
        let normalized = normalizedHex(hex)
        if containsPreset(normalized) {
            return normalized
        }
        return nearestPresetHex(to: normalized)
    }

    static func nearestPresetHex(to hex: String) -> String {
        let normalized = normalizedHex(hex)
        guard let source = rgbComponents(for: normalized) else {
            return fallbackHex
        }

        return presetHexes.min { lhs, rhs in
            squaredDistance(from: source, to: lhs) < squaredDistance(from: source, to: rhs)
        } ?? fallbackHex
    }

    private static func squaredDistance(
        from source: (red: Int, green: Int, blue: Int),
        to targetHex: String
    ) -> Int {
        guard let target = rgbComponents(for: targetHex) else {
            return .max
        }

        let redDelta = source.red - target.red
        let greenDelta = source.green - target.green
        let blueDelta = source.blue - target.blue
        return redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta
    }

    private static func rgbComponents(for hex: String) -> (red: Int, green: Int, blue: Int)? {
        let normalized = normalizedHex(hex)
        let hexDigits = String(normalized.dropFirst())
        guard hexDigits.count == 6, let value = Int(hexDigits, radix: 16) else {
            return nil
        }

        return (
            red: (value & 0xFF0000) >> 16,
            green: (value & 0x00FF00) >> 8,
            blue: value & 0x0000FF
        )
    }

    private static func isHexString(_ value: String) -> Bool {
        let allowedHexDigits = Set("0123456789ABCDEF")
        return !value.isEmpty && value.allSatisfy { allowedHexDigits.contains($0) }
    }
}
