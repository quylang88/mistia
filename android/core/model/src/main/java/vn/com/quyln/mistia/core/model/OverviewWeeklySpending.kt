package vn.com.quyln.mistia.core.model

import java.time.*
import java.math.BigInteger
import java.math.BigDecimal
import java.math.RoundingMode

data class OverviewDailySpending(val date:LocalDate,val amountMinor:BigInteger?,val intensity:Double) {
    constructor(date:LocalDate,amountMinor:Long,intensity:Double):this(date,BigInteger.valueOf(amountMinor),intensity)
}
data class OverviewWeekSpending(val start:LocalDate,val isCurrent:Boolean,val points:List<OverviewDailySpending>,val hasUnplacedExpense:Boolean=false) {
    val end:LocalDate get()=start.plusDays(6)
    val hasUnavailableConversion:Boolean get()=hasUnplacedExpense || points.any {it.amountMinor==null}
    val totalMinor:BigInteger? get()=if(hasUnavailableConversion) null else points.fold(BigInteger.ZERO) {sum,point ->sum+checkNotNull(point.amountMinor)}
}
fun overviewWeeklySpending(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,currency:String?=null,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),reference:Instant,zone:ZoneId):List<OverviewWeekSpending> {
    val ownedWallets=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associateBy {it.id}
    val effects=records.mapNotNull {record ->
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null) return@mapNotNull null
        val wallet=ownedWallets[record.sourceWalletId]
        val expense=reportedOverviewExpense(record,wallet?.kind,knownTitles)
        if(expense==0L) return@mapNotNull null
        val occurred=runCatching {Instant.parse(record.occurredAt)}.getOrNull() ?: return@mapNotNull null
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank) ?: wallet?.currencyCode ?: "JPY"
        OverviewReportingEffect(occurred,source,0,expense)
    }
    return overviewWeeklySpendingEffects(effects,currency,rates,reference,zone)
}

fun overviewWeeklySpendingEffects(effects:List<OverviewReportingEffect>,currency:String?=null,
    rates:List<ExchangeRateSnapshot> = emptyList(),reference:Instant,zone:ZoneId):List<OverviewWeekSpending> {
    val current=reference.atZone(zone).toLocalDate().mondayStart()
    val target=(currency ?: "JPY").overviewCurrencyCode() ?: (currency ?: "JPY")
    val totals=mutableMapOf<LocalDate,BigInteger?>()
    var earliest:LocalDate?=null
    var unplaced=false
    for(effect in effects) {
        val expense=effect.expenseMinor
        if(expense==0L) continue
        val date=runCatching {effect.occurredAt?.atZone(zone)?.toLocalDate()}.getOrNull()
        if(date==null) {unplaced=true;continue}
        val start=date.mondayStart()
        if(start>current) continue
        val converted=if(expense==null || effect.sourceCurrencyCode==null) null else overviewMoneyMinorExact(expense,effect.sourceCurrencyCode,target,rates)
        val previous=if(totals.containsKey(date)) totals[date] else BigInteger.ZERO
        totals[date]=previous?.let {subtotal ->converted?.let(subtotal::plus)}
        if(earliest==null || start<earliest) earliest=start
    }
    val pages=mutableListOf<OverviewWeekSpending>()
    var start=(earliest ?: current).coerceAtMost(current)
    while(start<=current) {
        val dates=(0L..6).map {start.plusDays(it)}
        val amounts=dates.map {if(totals.containsKey(it)) totals[it] else BigInteger.ZERO}
        val known=amounts.filterNotNull()
        val minimum=known.minOrNull() ?: BigInteger.ZERO;val maximum=known.maxOrNull() ?: BigInteger.ZERO
        val range=maximum-minimum
        val points=dates.mapIndexed {index,date ->
            val amount=amounts[index]
            val intensity=if(amount==null) 0.0 else if(range.signum()==0) {if(maximum.signum()==0) 0.0 else 0.5}
                else BigDecimal(amount-minimum).divide(BigDecimal(range),24,RoundingMode.HALF_UP).toDouble()
            OverviewDailySpending(date,amount,intensity)
        }
        pages+=OverviewWeekSpending(start,start==current,points,hasUnplacedExpense=unplaced)
        start=start.plusWeeks(1)
    }
    return pages
}
private fun LocalDate.mondayStart():LocalDate=minusDays(dayOfWeek.value.toLong()-1)
