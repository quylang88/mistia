package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.Locale

internal fun String.overviewCurrencyCode():String?=trim().uppercase(Locale.ROOT).takeIf {it.length==3 && it.all {letter ->letter in 'A'..'Z'}}

/** Null denotes unavailable reporting conversion; identity preserves original minor units for imports. */
internal fun overviewMoneyMinorExact(amount:Long,source:String,target:String,rates:List<ExchangeRateSnapshot>):BigInteger? =
    overviewMoneyMinorExact(BigInteger.valueOf(amount),source,target,rates)

internal fun overviewMoneyMinorExact(amount:BigInteger,source:String,target:String,rates:List<ExchangeRateSnapshot>):BigInteger? {
    if(amount.signum()==0) return BigInteger.ZERO
    val from=source.overviewCurrencyCode() ?: return null
    val to=target.overviewCurrencyCode() ?: return null
    if(from==to) return amount
    if(from !in CurrencyPreferences.supportedCurrencyCodes || to !in CurrencyPreferences.supportedCurrencyCodes || matchingExchangeRateSnapshot(from,to,rates)==null) return null
    return planningMoneyMinorExact(amount,from,to,rates)
}
