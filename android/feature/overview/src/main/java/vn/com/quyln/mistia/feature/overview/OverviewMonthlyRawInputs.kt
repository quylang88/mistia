package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

internal fun overviewRawMonthlyCashflow(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val current=YearMonth.from(reference.atZone(zone))
    val effects=overviewRawReportingEffects(owner,records,wallets,knownTitles) {YearMonth.from(it.atZone(zone))<=current}
    return overviewMonthlyCashflowEffects(effects,currency,rates,reference,zone)
}
