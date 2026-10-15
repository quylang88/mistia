package vn.com.quyln.mistia.feature.planning

/** Presentation only: preserve malformed input for validation; never change the unit or precision. */
internal fun groupedMinorAmountInput(text: String): String {
    val raw = text.trim()
    if (!Regex("-?[0-9,]*").matches(raw)) return text
    val negative = raw.startsWith("-")
    val digits = raw.removePrefix("-").replace(",", "")
    return (if (negative) "-" else "") + digits.reversed().chunked(3).joinToString(",").reversed()
}

internal fun planningAmountInput(text: String, currency: String): String =
    if (currency.trim().uppercase(java.util.Locale.ROOT) in setOf("JPY", "VND")) groupedMinorAmountInput(text) else text
