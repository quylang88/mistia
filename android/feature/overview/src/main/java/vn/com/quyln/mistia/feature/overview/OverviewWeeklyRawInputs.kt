package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

internal fun overviewRawWeeklySpending(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,currency:String?=null,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),reference:Instant,zone:ZoneId):List<OverviewWeekSpending> {
    val today=reference.atZone(zone).toLocalDate()
    val end=today.plusDays(7L-today.dayOfWeek.value)
    val effects=overviewRawReportingEffects(owner,records,wallets,knownTitles) {it.atZone(zone).toLocalDate()<=end}
    return overviewWeeklySpendingEffects(effects,currency,rates,reference,zone)
}
