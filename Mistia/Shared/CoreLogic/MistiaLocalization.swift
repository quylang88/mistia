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
            "Tiếng Việt"
        case .english:
            "English"
        case .japanese:
            "日本語"
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

@inline(__always)
nonisolated func mistiaLocalized(
    vi: String,
    en: String,
    ja: String,
    language: MistiaAppLanguage = .current
) -> String {
    switch language {
    case .vietnamese:
        vi
    case .english:
        en
    case .japanese:
        ja
    }
}

@inline(__always)
nonisolated func mistiaCatalog(
    _ key: String,
    language: MistiaAppLanguage = .current
) -> String {
    String(
        localized: String.LocalizationValue(key),
        bundle: .main,
        locale: language.locale
    )
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
    static func shortDateString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let f = formatter(language: language, calendar: calendar)
        f.dateFormat = "dd/MM"
        return f.string(from: date)
    }

    static func fullDateString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let f = formatter(language: language, calendar: calendar)
        switch language {
        case .vietnamese:
            f.dateFormat = "dd/MM/yyyy"
        case .english:
            f.dateFormat = "yyyy-MM-dd"
        case .japanese:
            f.dateFormat = "yyyy年M月d日"
        }
        return f.string(from: date)
    }

    static func dateTimeString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let formatter = formatter(language: language, calendar: calendar)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func monthYearString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        formatter(
            template: "yMMMM",
            language: language,
            calendar: calendar
        ).string(from: date)
    }

    static func statementMonthYearString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        let formatter = formatter(language: language, calendar: calendar)
        switch language {
        case .vietnamese, .english:
            formatter.dateFormat = "MM/yyyy"
        case .japanese:
            formatter.dateFormat = "yyyy年MM月"
        }
        return formatter.string(from: date)
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
        return mistiaLocalized(
            vi: "Tuần này • \(range)",
            en: "This week • \(range)",
            ja: "今週 • \(range)",
            language: language
        )
    }

    static func weekdayLabel(
        for date: Date,
        calendar: Calendar,
        language: MistiaAppLanguage = .current
    ) -> String {
        let weekday = calendar.component(.weekday, from: date)
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
            return mistiaLocalized(
                vi: "Hôm nay",
                en: "Today",
                ja: "今日",
                language: language
            )
        case 1:
            return mistiaLocalized(
                vi: "Hôm qua",
                en: "Yesterday",
                ja: "昨日",
                language: language
            )
        case 2:
            return mistiaLocalized(
                vi: "Hôm kia",
                en: "2 days ago",
                ja: "一昨日",
                language: language
            )
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
        
        // < 1 hour: 3 minutes ago
        if diff < 3600 {
            let minutes = max(Int(diff / 60), 1)
            return mistiaLocalized(
                vi: "\(minutes) phút trước",
                en: "\(minutes) min ago",
                ja: "\(minutes)分前",
                language: language
            )
        }
        
        // < 24 hours: 5 hours ago
        if diff < 86400 {
            let hours = max(Int(diff / 3600), 1)
            return mistiaLocalized(
                vi: "\(hours) tiếng trước",
                en: "\(hours) hr ago",
                ja: "\(hours)時間前",
                language: language
            )
        }
        
        // < 30 days: 10 days ago
        if diff < 2592000 {
            let days = max(Int(diff / 86400), 1)
            return mistiaLocalized(
                vi: "\(days) ngày trước",
                en: "\(days) days ago",
                ja: "\(days)日前",
                language: language
            )
        }
        
        // < 1 year: 1 month ago, 2 months ago
        if diff < 31536000 {
            let months = max(Int(diff / 2592000), 1)
            return mistiaLocalized(
                vi: "\(months) tháng trước",
                en: "\(months) months ago",
                ja: "\(months)ヶ月前",
                language: language
            )
        }

        return fullDateString(for: date, language: language, calendar: calendar)
    }

    private static func formatter(
        template: String? = nil,
        language: MistiaAppLanguage,
        calendar: Calendar? = nil
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        let resolvedCalendar = calendar ?? language.calendar
        formatter.calendar = resolvedCalendar
        formatter.timeZone = resolvedCalendar.timeZone
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
        return formatter
    }
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
