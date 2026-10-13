package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.util.Locale

/** Reporting only: retain conversion overflow until the final display boundary. */
internal fun planningMoneyMinorExact(amount:Long,source:String?,target:String,rates:List<ExchangeRateSnapshot>):BigInteger {
    fun currency(code:String?)=code?.trim()?.uppercase(Locale.ROOT)?.takeIf { it=="JPY" || it=="VND" } ?: "JPY"
    val from=currency(source)
    val to=currency(target)
    if(from==to) return BigInteger.valueOf(amount)
    val snapshot=matchingExchangeRateSnapshot(from,to,rates) ?: return BigInteger.ZERO
    val rate=snapshot.rateDecimalString.toBigDecimal()
    val value=BigDecimal.valueOf(amount)
    return if(currency(snapshot.baseCurrencyCode)==from) value.multiply(rate).setScale(0,RoundingMode.HALF_UP).toBigIntegerExact()
        else value.divide(rate,0,RoundingMode.HALF_UP).toBigIntegerExact()
}
