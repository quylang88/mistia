package vn.com.quyln.mistia.core.designsystem

import java.math.BigDecimal
import java.math.BigInteger
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/** Swift pins presentation locale to the currency, independently of app/device language. */
private fun currencyPresentationLocale(code: String): Locale = Locale.forLanguageTag(when (code) {
    "JPY" -> "ja-JP"
    "VND" -> "vi-VN"
    "USD" -> "en-US"
    "GBP" -> "en-GB"
    "EUR" -> "de-DE"
    "KRW" -> "ko-KR"
    "CNY" -> "zh-CN"
    "TWD" -> "zh-TW"
    "THB" -> "th-TH"
    "SGD" -> "en-SG"
    "AUD" -> "en-AU"
    "CAD" -> "en-CA"
    "HKD" -> "zh-HK"
    else -> "en-US"
})

fun formatMinorUnits(minor:Long,currencyCode:String):String = formatCurrencyMinorDecimal(BigDecimal.valueOf(minor),currencyCode)
fun formatMinorUnits(minor:BigInteger,currencyCode:String):String = formatCurrencyMinorDecimal(BigDecimal(minor),currencyCode)

/** Magnitude remains exact even when abs(Long.MIN_VALUE) cannot fit in Long. */
fun formatMinorUnitsMagnitude(minor:Long,currencyCode:String):String = formatCurrencyMinorDecimal(BigDecimal.valueOf(minor).abs(),currencyCode)

private fun formatCurrencyMinorDecimal(minor:BigDecimal,currencyCode:String):String {
    val currency = runCatching { Currency.getInstance(currencyCode) }.getOrNull()
    val digits = currency?.defaultFractionDigits?.coerceAtLeast(0) ?: 0
    val value = minor.movePointLeft(digits)
    if (currency == null) return "$value $currencyCode"
    return NumberFormat.getCurrencyInstance(currencyPresentationLocale(currency.currencyCode)).apply {
        this.currency = currency
        minimumFractionDigits = digits
        maximumFractionDigits = digits
    }.format(value)
}
