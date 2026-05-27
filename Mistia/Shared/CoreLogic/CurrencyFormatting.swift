import Foundation

nonisolated enum MistiaCurrencyFormatting {
    static func locale(for currencyCode: String) -> Locale {
        switch currencyCode.uppercased() {
        case "JPY":
            Locale(identifier: "ja_JP")
        case "VND":
            Locale(identifier: "vi_VN")
        case "USD":
            Locale(identifier: "en_US")
        case "GBP":
            Locale(identifier: "en_GB")
        case "EUR":
            Locale(identifier: "de_DE")
        case "KRW":
            Locale(identifier: "ko_KR")
        case "CNY":
            Locale(identifier: "zh_CN")
        case "TWD":
            Locale(identifier: "zh_TW")
        case "THB":
            Locale(identifier: "th_TH")
        case "SGD":
            Locale(identifier: "en_SG")
        case "AUD":
            Locale(identifier: "en_AU")
        case "CAD":
            Locale(identifier: "en_CA")
        case "HKD":
            Locale(identifier: "zh_HK")
        default:
            Locale(identifier: "en_US")
        }
    }
}

extension Int64 {
    nonisolated func formattedCurrency(code: String) -> String {
        let uppercaseCode = code.uppercased()
        let fractionDigits = MistiaCurrencyLogic.hasMinorFractionDigits(uppercaseCode) ? 2 : 0
        let amount = decimalCurrencyAmount(fractionDigits: fractionDigits)
        let locale = MistiaCurrencyFormatting.locale(for: uppercaseCode)

        return amount.formatted(
            .currency(code: uppercaseCode)
                .precision(.fractionLength(fractionDigits))
                .locale(locale)
        )
    }

    nonisolated var compactAxisLabel: String {
        let absolute = abs(self)
        let sign = self < 0 ? "-" : ""

        if absolute >= 1_000_000 {
            return "\(sign)\(absolute / 1_000_000)M"
        }

        if absolute >= 1_000 {
            return "\(sign)\(absolute / 1_000)K"
        }

        return "\(self)"
    }

    nonisolated private func decimalCurrencyAmount(fractionDigits: Int) -> Decimal {
        guard fractionDigits > 0 else { return Decimal(self) }

        var divisor = Decimal(1)
        for _ in 0..<fractionDigits {
            divisor *= 10
        }

        return Decimal(self) / divisor
    }
}

extension Int {
    nonisolated var compactAxisLabel: String {
        Int64(self).compactAxisLabel
    }
}
