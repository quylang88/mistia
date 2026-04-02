import Foundation

nonisolated enum MistiaAppLanguage: String, CaseIterable, Identifiable, Codable {
    case vietnamese = "vi"
    case english = "en"
    case japanese = "ja"

    static let userDefaultsKey = "mistia.settings.app.language"

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
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
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

    static var current: Self {
        resolve(storedRawValue: UserDefaults.standard.string(forKey: userDefaultsKey))
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

nonisolated enum MistiaDateFormatting {
    static func shortDateString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        formatter(
            template: "ddMM",
            language: language,
            calendar: calendar
        ).string(from: date)
    }

    static func fullDateString(
        for date: Date,
        language: MistiaAppLanguage = .current,
        calendar: Calendar? = nil
    ) -> String {
        formatter(
            template: "ddMMyyyy",
            language: language,
            calendar: calendar
        ).string(from: date)
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
        calendar: Calendar = .current,
        language: MistiaAppLanguage = .current
    ) -> String {
        let startOfReference = calendar.startOfDay(for: referenceDate)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startOfDate, to: startOfReference).day ?? 0

        if dayDelta == 0 {
            let minutes = max(Int(referenceDate.timeIntervalSince(date) / 60), 0)
            if minutes < 60 {
                let safeMinutes = max(minutes, 1)
                return mistiaLocalized(
                    vi: "\(safeMinutes) phút trước",
                    en: "\(safeMinutes) min ago",
                    ja: "\(safeMinutes)分前",
                    language: language
                )
            }

            let hours = max(Int(referenceDate.timeIntervalSince(date) / 3_600), 0)
            if hours < 10 {
                let safeHours = max(hours, 1)
                return mistiaLocalized(
                    vi: "\(safeHours) tiếng trước",
                    en: "\(safeHours) hr ago",
                    ja: "\(safeHours)時間前",
                    language: language
                )
            }
        }

        if let relativeLabel = relativeDayLabel(for: dayDelta, language: language) {
            return relativeLabel
        }

        return shortDateString(for: date, language: language, calendar: calendar)
    }

    private static func formatter(
        template: String? = nil,
        language: MistiaAppLanguage,
        calendar: Calendar? = nil
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = calendar ?? language.calendar
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
        return formatter
    }
}
