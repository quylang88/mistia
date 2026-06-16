import Foundation

nonisolated struct MistiaExchangeRate: Codable, Equatable, Identifiable {
    var id: String { "\(baseCurrencyCode.uppercased())-\(quoteCurrencyCode.uppercased())-\(rateDate ?? "latest")" }

    let baseCurrencyCode: String
    let quoteCurrencyCode: String
    let rateDecimalString: String
    let provider: String
    let fetchedAt: Date
    let rateDate: String?

    var rateDecimal: Decimal? {
        Decimal(string: rateDecimalString, locale: Locale(identifier: "en_US_POSIX"))
    }
}

nonisolated struct MistiaExchangeRateIndex: Equatable {
    private struct Pair: Hashable {
        let base: String
        let quote: String
    }

    private let ratesByPair: [Pair: Decimal]

    init(rates: [MistiaExchangeRate]) {
        var ratesByPair: [Pair: Decimal] = [:]
        ratesByPair.reserveCapacity(rates.count)

        for rate in rates {
            guard let decimal = rate.rateDecimal else { continue }
            let pair = Pair(
                base: MistiaCurrencyLogic.normalizedCode(rate.baseCurrencyCode),
                quote: MistiaCurrencyLogic.normalizedCode(rate.quoteCurrencyCode)
            )
            if ratesByPair[pair] == nil {
                ratesByPair[pair] = decimal
            }
        }

        self.ratesByPair = ratesByPair
    }

    fileprivate func directRate(
        fromNormalized source: String,
        toNormalized target: String
    ) -> Decimal? {
        ratesByPair[Pair(base: source, quote: target)]
    }
}

nonisolated enum MistiaCurrencyConversionMode: String, Codable, CaseIterable, Identifiable {
    case appRate
    case manual

    var id: String { rawValue }
}

nonisolated enum MistiaCurrencyRateMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }
}

enum MistiaCurrencySettings {
    enum StorageKey {
        static let primaryCurrencyCode = "mistia.settings.currency.code"
        static let enabledCurrencyCodes = "mistia.settings.currency.enabled-codes"
        static let rateMode = "mistia.settings.currency.rate-mode"
        static let manualJPYToVNDRate = "mistia.settings.currency.manual-rate.jpy-vnd"
        static let cachedRatesData = "mistia.settings.currency.cached-rates.data"
        static let lastAutoRateRefreshAt = "mistia.settings.currency.last-auto-refresh-at"
    }

    static func enabledCurrencyCodes(defaults: UserDefaults = .standard) -> [String] {
        guard let raw = defaults.string(forKey: StorageKey.enabledCurrencyCodes)?.nilIfBlank else {
            return ["JPY"]
        }

        let codes = raw
            .split(separator: ",")
            .map { MistiaCurrencyLogic.normalizedCode(String($0)) }
            .filter { MistiaCurrencyLogic.supportedCurrencyCodes.contains($0) }
        return Array(Set(codes)).sortedBySupportedCurrencyOrder.nonEmpty ?? ["JPY"]
    }

    static func setEnabledCurrencyCodes(_ codes: [String], defaults: UserDefaults = .standard) {
        let normalized = Array(Set(codes.map(MistiaCurrencyLogic.normalizedCode)))
            .filter { MistiaCurrencyLogic.supportedCurrencyCodes.contains($0) }
            .sortedBySupportedCurrencyOrder
        defaults.set((normalized.nonEmpty ?? ["JPY"]).joined(separator: ","), forKey: StorageKey.enabledCurrencyCodes)
    }

    static func primaryCurrencyCode(defaults: UserDefaults = .standard) -> String {
        let code = MistiaCurrencyLogic.normalizedCode(defaults.string(forKey: StorageKey.primaryCurrencyCode))
        let enabled = enabledCurrencyCodes(defaults: defaults)
        return enabled.contains(code) ? code : (enabled.first ?? "JPY")
    }

    static func rateMode(defaults: UserDefaults = .standard) -> MistiaCurrencyRateMode {
        MistiaCurrencyRateMode(rawValue: defaults.string(forKey: StorageKey.rateMode) ?? "") ?? .manual
    }

    static func rates(defaults: UserDefaults = .standard) -> [MistiaExchangeRate] {
        switch rateMode(defaults: defaults) {
        case .automatic:
            return cachedRates(defaults: defaults)
        case .manual:
            return manualRates(defaults: defaults)
        }
    }

    static func cachedRates(defaults: UserDefaults = .standard) -> [MistiaExchangeRate] {
        guard let data = defaults.data(forKey: StorageKey.cachedRatesData),
              let rates = try? JSONDecoder().decode([MistiaExchangeRate].self, from: data)
        else {
            return []
        }
        return rates
    }

    static func saveCachedRates(_ rates: [MistiaExchangeRate], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rates) else { return }
        defaults.set(data, forKey: StorageKey.cachedRatesData)
        defaults.set(Date(), forKey: StorageKey.lastAutoRateRefreshAt)
    }

    static func manualRates(defaults: UserDefaults = .standard) -> [MistiaExchangeRate] {
        let rate = defaults.string(forKey: StorageKey.manualJPYToVNDRate)?.nilIfBlank ?? "165"
        return [
            MistiaExchangeRate(
                baseCurrencyCode: "JPY",
                quoteCurrencyCode: "VND",
                rateDecimalString: rate,
                provider: "manual",
                fetchedAt: Date(),
                rateDate: nil
            )
        ]
    }
}

nonisolated enum MistiaCurrencyLogic {
    static let supportedCurrencyCodes = ["JPY", "VND"]

    static func normalizedCode(_ code: String?) -> String {
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return supportedCurrencyCodes.contains(trimmed) ? trimmed : "JPY"
    }

    static func hasMinorFractionDigits(_ currencyCode: String) -> Bool {
        switch normalizedCode(currencyCode) {
        case "JPY", "VND":
            return false
        default:
            return true
        }
    }

    static func convertedMinorAmount(
        _ amountMinor: Int64,
        from sourceCurrencyCode: String,
        to targetCurrencyCode: String,
        rates: [MistiaExchangeRate]
    ) -> Int64? {
        let source = normalizedCode(sourceCurrencyCode)
        let target = normalizedCode(targetCurrencyCode)
        guard source != target else { return amountMinor }

        if let direct = rates.first(where: {
            normalizedCode($0.baseCurrencyCode) == source
                && normalizedCode($0.quoteCurrencyCode) == target
        })?.rateDecimal {
            return roundedMinorAmount(Decimal(amountMinor) * direct)
        }

        if let inverse = rates.first(where: {
            normalizedCode($0.baseCurrencyCode) == target
                && normalizedCode($0.quoteCurrencyCode) == source
        })?.rateDecimal, inverse != 0 {
            return roundedMinorAmount(Decimal(amountMinor) / inverse)
        }

        return nil
    }

    static func convertedMinorAmount(
        _ amountMinor: Int64,
        from sourceCurrencyCode: String,
        to targetCurrencyCode: String,
        rateIndex: MistiaExchangeRateIndex
    ) -> Int64? {
        let source = normalizedCode(sourceCurrencyCode)
        let target = normalizedCode(targetCurrencyCode)
        guard source != target else { return amountMinor }

        if let direct = rateIndex.directRate(fromNormalized: source, toNormalized: target) {
            return roundedMinorAmount(Decimal(amountMinor) * direct)
        }

        if let inverse = rateIndex.directRate(fromNormalized: target, toNormalized: source),
           inverse != 0 {
            return roundedMinorAmount(Decimal(amountMinor) / inverse)
        }

        return nil
    }

    static func approximatePrimaryAmountText(
        amountMinor: Int64,
        sourceCurrencyCode: String,
        primaryCurrencyCode: String,
        rates: [MistiaExchangeRate]
    ) -> String? {
        let source = normalizedCode(sourceCurrencyCode)
        let primary = normalizedCode(primaryCurrencyCode)
        guard source != primary,
              let converted = convertedMinorAmount(
                amountMinor,
                from: source,
                to: primary,
                rates: rates
              )
        else {
            return nil
        }

        return "~" + converted.formattedCurrency(code: primary)
    }

    static func approximatePrimaryAmountText(
        amountMinor: Int64,
        sourceCurrencyCode: String,
        primaryCurrencyCode: String,
        rateIndex: MistiaExchangeRateIndex
    ) -> String? {
        let source = normalizedCode(sourceCurrencyCode)
        let primary = normalizedCode(primaryCurrencyCode)
        guard source != primary,
              let converted = convertedMinorAmount(
                amountMinor,
                from: source,
                to: primary,
                rateIndex: rateIndex
              )
        else {
            return nil
        }

        return "~" + converted.formattedCurrency(code: primary)
    }

    static func reportingMinorAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String?,
        reportingCurrencyCode: String,
        snapshotAmountMinor: Int64? = nil,
        snapshotCurrencyCode: String? = nil,
        rates: [MistiaExchangeRate]
    ) -> Int64? {
        let source = normalizedCode(sourceCurrencyCode)
        let reporting = normalizedCode(reportingCurrencyCode)

        if source == reporting {
            return amountMinor
        }

        if let snapshotAmountMinor,
           normalizedCode(snapshotCurrencyCode) == reporting {
            return snapshotAmountMinor
        }

        return convertedMinorAmount(
            amountMinor,
            from: source,
            to: reporting,
            rates: rates
        )
    }

    static func reportingMinorAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String?,
        reportingCurrencyCode: String,
        snapshotAmountMinor: Int64? = nil,
        snapshotCurrencyCode: String? = nil,
        rateIndex: MistiaExchangeRateIndex
    ) -> Int64? {
        let source = normalizedCode(sourceCurrencyCode)
        let reporting = normalizedCode(reportingCurrencyCode)

        if source == reporting {
            return amountMinor
        }

        if let snapshotAmountMinor,
           normalizedCode(snapshotCurrencyCode) == reporting {
            return snapshotAmountMinor
        }

        return convertedMinorAmount(
            amountMinor,
            from: source,
            to: reporting,
            rateIndex: rateIndex
        )
    }

    static func reportingMinorAmount(
        for record: TransactionRecordSnapshot,
        reportingCurrencyCode: String,
        rates: [MistiaExchangeRate]
    ) -> Int64? {
        reportingMinorAmount(
            amountMinor: record.amountMinor,
            sourceCurrencyCode: record.sourceCurrencyCode,
            reportingCurrencyCode: reportingCurrencyCode,
            snapshotAmountMinor: record.reportingAmountMinor,
            snapshotCurrencyCode: record.reportingCurrencyCode,
            rates: rates
        )
    }

    static func reportingMinorAmount(
        for record: TransactionRecordSnapshot,
        reportingCurrencyCode: String,
        rateIndex: MistiaExchangeRateIndex
    ) -> Int64? {
        reportingMinorAmount(
            amountMinor: record.amountMinor,
            sourceCurrencyCode: record.sourceCurrencyCode,
            reportingCurrencyCode: reportingCurrencyCode,
            snapshotAmountMinor: record.reportingAmountMinor,
            snapshotCurrencyCode: record.reportingCurrencyCode,
            rateIndex: rateIndex
        )
    }

    private static func roundedMinorAmount(_ value: Decimal) -> Int64? {
        var mutable = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &mutable, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}

enum MistiaExchangeRateService {
    struct FrankfurterRateResponse: Decodable {
        let date: String?
        let base: String
        let quote: String
        let rate: Decimal
    }

    static func fetchJPYVNDRate() async throws -> MistiaExchangeRate {
        let url = URL(string: "https://api.frankfurter.dev/v2/rate/JPY/VND")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .throw
        let response = try decoder.decode(FrankfurterRateResponse.self, from: data)
        return MistiaExchangeRate(
            baseCurrencyCode: response.base,
            quoteCurrencyCode: response.quote,
            rateDecimalString: NSDecimalNumber(decimal: response.rate).stringValue,
            provider: "frankfurter",
            fetchedAt: Date(),
            rateDate: response.date
        )
    }
}

enum MistiaCurrencyRateMaintenance {
    static func refreshIfNeeded(
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        calendar: Calendar = MistiaCalendar.current
    ) async {
        guard MistiaCurrencySettings.rateMode(defaults: defaults) == .automatic,
              shouldRefresh(defaults: defaults, now: now, calendar: calendar)
        else {
            return
        }

        do {
            let rate = try await MistiaExchangeRateService.fetchJPYVNDRate()
            MistiaCurrencySettings.saveCachedRates([rate], defaults: defaults)
        } catch {
            #if DEBUG
            print("MistiaCurrencyRateMaintenance: failed to refresh rates: \(error)")
            #endif
        }
    }

    static func shouldRefresh(
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        calendar: Calendar = MistiaCalendar.current
    ) -> Bool {
        guard let seven = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now),
              now >= seven
        else {
            return false
        }

        guard let last = defaults.object(forKey: MistiaCurrencySettings.StorageKey.lastAutoRateRefreshAt) as? Date else {
            return true
        }

        return !calendar.isDate(last, inSameDayAs: now)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == String {
    var sortedBySupportedCurrencyOrder: [String] {
        sorted { lhs, rhs in
            let lhsIndex = MistiaCurrencyLogic.supportedCurrencyCodes.firstIndex(of: lhs) ?? .max
            let rhsIndex = MistiaCurrencyLogic.supportedCurrencyCodes.firstIndex(of: rhs) ?? .max
            return lhsIndex < rhsIndex
        }
    }

    var nonEmpty: [String]? {
        isEmpty ? nil : self
    }
}
