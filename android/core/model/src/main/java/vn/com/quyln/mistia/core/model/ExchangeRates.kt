package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Locale
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable

@Serializable
data class ExchangeRateSnapshot(
    val baseCurrencyCode: String,
    val quoteCurrencyCode: String,
    val rateDecimalString: String,
    val provider: String,
    val fetchedAtEpochMillis: Long,
    val rateDate: String?,
)

data class ExchangeRateResolution(
    val destinationAmountMinor: Long,
    val rateDecimalString: String,
    val provider: String,
    val rateDate: String?,
)

interface ExchangeRateRepository {
    val rates: StateFlow<List<ExchangeRateSnapshot>>
    suspend fun refreshIfStale(nowEpochMillis: Long = System.currentTimeMillis()): Result<Unit>
}

fun resolveExchangeRate(
    amountMinor: Long,
    sourceCurrencyCode: String,
    destinationCurrencyCode: String,
    rates: List<ExchangeRateSnapshot>,
): ExchangeRateResolution? {
    val source = supportedCurrencyCode(sourceCurrencyCode) ?: return null
    val destination = supportedCurrencyCode(destinationCurrencyCode) ?: return null
    if (source == destination) return null
    val snapshot = matchingExchangeRateSnapshot(source, destination, rates) ?: return null
    val base = supportedCurrencyCode(snapshot.baseCurrencyCode) ?: return null
    val rate = snapshot.rateDecimalString.toBigDecimalOrNull() ?: return null
    val converted = if (base == source) {
        BigDecimal.valueOf(amountMinor).multiply(rate)
    } else {
        BigDecimal.valueOf(amountMinor).divide(rate, RATE_DIVISION_SCALE, RoundingMode.HALF_UP)
    }
    val minor = runCatching {
        converted.setScale(0, RoundingMode.HALF_UP).longValueExact()
    }.getOrNull() ?: return null
    return ExchangeRateResolution(
        destinationAmountMinor = minor,
        rateDecimalString = snapshot.rateDecimalString,
        provider = snapshot.provider,
        rateDate = snapshot.rateDate,
    )
}

fun matchingExchangeRateSnapshot(
    sourceCurrencyCode: String,
    destinationCurrencyCode: String,
    rates: List<ExchangeRateSnapshot>,
): ExchangeRateSnapshot? {
    val source = supportedCurrencyCode(sourceCurrencyCode) ?: return null
    val destination = supportedCurrencyCode(destinationCurrencyCode) ?: return null
    if (source == destination) return null
    return rates.firstOrNull { snapshot ->
        val base = supportedCurrencyCode(snapshot.baseCurrencyCode) ?: return@firstOrNull false
        val quote = supportedCurrencyCode(snapshot.quoteCurrencyCode) ?: return@firstOrNull false
        val rateIsValid = snapshot.rateDecimalString.toBigDecimalOrNull()?.signum() == 1
        rateIsValid && ((base == source && quote == destination) ||
            (base == destination && quote == source))
    }
}

private fun supportedCurrencyCode(value: String): String? = value.trim()
    .uppercase(Locale.ROOT)
    .takeIf { it == "JPY" || it == "VND" }

private const val RATE_DIVISION_SCALE = 24
