import Foundation

extension Int64 {
    nonisolated func formattedCurrency(code: String) -> String {
        let uppercaseCode = code.uppercased()
        let fractionDigits = uppercaseCode == "JPY" ? 0 : 2
        let amount = decimalCurrencyAmount(fractionDigits: fractionDigits)
        let locale = Locale(identifier: uppercaseCode == "JPY" ? "ja_JP" : "en_US_POSIX")

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

    private func decimalCurrencyAmount(fractionDigits: Int) -> Decimal {
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
