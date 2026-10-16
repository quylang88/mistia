package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Locale
import kotlinx.coroutines.flow.StateFlow

enum class CurrencyRateMode { MANUAL, AUTOMATIC }

data class CurrencyPreferences(
    val enabledCurrencyCodes: List<String> = listOf("JPY"),
    val primaryCurrencyCode: String = "JPY",
    val rateMode: CurrencyRateMode = CurrencyRateMode.MANUAL,
    val manualJPYToVNDRate: String = "165",
) {
    fun withEnabled(code: String, enabled: Boolean): CurrencyPreferences {
        val canonical = code.trim().uppercase(Locale.ROOT)
        if (canonical !in supportedCurrencyCodes) return this
        val selected = if (enabled) enabledCurrencyCodes + canonical
            else if (enabledCurrencyCodes.size > 1) enabledCurrencyCodes - canonical else enabledCurrencyCodes
        val ordered = supportedCurrencyCodes.filter { it in selected }
        return copy(enabledCurrencyCodes = ordered, primaryCurrencyCode = primaryCurrencyCode.takeIf { it in ordered } ?: ordered.first())
    }

    fun withPrimary(code: String): CurrencyPreferences {
        val canonical = code.trim().uppercase(Locale.ROOT)
        return if (canonical in enabledCurrencyCodes) copy(primaryCurrencyCode = canonical) else this
    }

    fun withDisplayedManualRate(text: String): CurrencyPreferences {
        val source = enabledCurrencyCodes.firstOrNull { it != primaryCurrencyCode }
        if (source == null) return copy(manualJPYToVNDRate = text)
        val parsed = decimal(text)?.takeIf { it.signum() > 0 }
        val canonical = if (parsed == null) null else if (source == "JPY") parsed
            else BigDecimal.ONE.divide(parsed, 40, RoundingMode.HALF_UP)
        return when {
            canonical != null -> copy(manualJPYToVNDRate = rateText(canonical))
            source == "JPY" -> copy(manualJPYToVNDRate = text)
            else -> this
        }
    }

    fun displayedRate(rates: List<ExchangeRateSnapshot> = emptyList()): String? {
        val source = enabledCurrencyCodes.firstOrNull { it != primaryCurrencyCode } ?: return null
        val rate = when (rateMode) {
            CurrencyRateMode.MANUAL -> decimal(manualJPYToVNDRate)
            CurrencyRateMode.AUTOMATIC -> rates.firstOrNull { it.baseCurrencyCode == "JPY" && it.quoteCurrencyCode == "VND" }
                ?.rateDecimalString?.let(::decimal)
        } ?: return null
        return if (source == "JPY") rateText(rate)
            else rate.takeIf { it.signum() != 0 }?.let { rateText(BigDecimal.ONE.divide(it, 40, RoundingMode.HALF_UP)) }
    }

    // A stable device-setting snapshot has no remote fetch timestamp or date.
    fun manualRates(): List<ExchangeRateSnapshot> = listOf(ExchangeRateSnapshot("JPY", "VND",
        manualJPYToVNDRate.trim().takeUnless { it.isEmpty() } ?: "165", "manual", 0, null))

    companion object {
        val supportedCurrencyCodes = listOf("JPY", "VND")
        fun fromStored(enabled: String?, primary: String?, mode: String?, manual: String?): CurrencyPreferences {
            // Swift normalizedCode maps unknown codes to JPY before ordering/deduplication.
            fun normalized(code: String?) = code?.trim()?.uppercase(Locale.ROOT)?.takeIf { it in supportedCurrencyCodes } ?: "JPY"
            val selected = enabled?.split(',')?.filter { it.isNotEmpty() }?.map(::normalized).orEmpty()
            val ordered = supportedCurrencyCodes.filter { it in selected }.ifEmpty { listOf("JPY") }
            return CurrencyPreferences(ordered, normalized(primary).takeIf { it in ordered } ?: ordered.first(),
                if (mode == "automatic") CurrencyRateMode.AUTOMATIC else CurrencyRateMode.MANUAL,
                manual ?: "165")
        }
        private fun decimal(text: String): BigDecimal? = text.trim().replace(',', '.').toBigDecimalOrNull()
        private fun rateText(value: BigDecimal): String = value.setScale(8, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
    }
}

interface CurrencyPreferencesStore {
    val state: StateFlow<CurrencyPreferences>
    fun setEnabled(code: String, enabled: Boolean)
    fun setPrimary(code: String)
    fun setAutomatic(automatic: Boolean)
    fun setDisplayedManualRate(text: String)
}
