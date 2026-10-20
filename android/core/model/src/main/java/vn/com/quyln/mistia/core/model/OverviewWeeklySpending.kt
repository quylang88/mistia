package vn.com.quyln.mistia.core.model

import java.time.*
import java.math.BigInteger
import java.math.BigDecimal
import java.math.RoundingMode

data class OverviewDailySpending(val date:LocalDate,val amountMinor:BigInteger?,val intensity:Double) {
    constructor(date:LocalDate,amountMinor:Long,intensity:Double):this(date,BigInteger.valueOf(amountMinor),intensity)
}
data class OverviewWeekSpending(val start:LocalDate,val isCurrent:Boolean,val points:List<OverviewDailySpending>) {
    val end:LocalDate get()=start.plusDays(6)
    val hasUnavailableConversion:Boolean get()=points.any {it.amountMinor==null}
    val totalMinor:BigInteger? get()=if(hasUnavailableConversion) null else points.fold(BigInteger.ZERO) {sum,point ->sum+checkNotNull(point.amountMinor)}
}
fun overviewWeeklySpending(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,currency:String?=null,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),reference:Instant,zone:ZoneId):List<OverviewWeekSpending> {
    val day=reference.atZone(zone).toLocalDate();val current=day.mondayStart()
    val ownedWallets=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associateBy {it.id}
    val target=(currency ?: "JPY").overviewCurrencyCode() ?: (currency ?: "JPY")
    val totals=mutableMapOf<LocalDate,BigInteger?>()
    var earliest:LocalDate?=null
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null) continue
        val wallet=ownedWallets[record.sourceWalletId]
        val expense=reportedOverviewExpense(record,wallet?.kind,knownTitles)
        if(expense==0L) continue
        val date=runCatching {Instant.parse(record.occurredAt).atZone(zone).toLocalDate()}.getOrNull() ?: continue
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank) ?: wallet?.currencyCode ?: "JPY"
        val previous=if(totals.containsKey(date)) totals[date] else BigInteger.ZERO
        totals[date]=previous?.let {subtotal ->overviewMoneyMinorExact(expense,source,target,rates)?.let(subtotal::plus)}
        val start=date.mondayStart()
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
        pages+=OverviewWeekSpending(start,start==current,points)
        start=start.plusWeeks(1)
    }
    return pages
}
private fun LocalDate.mondayStart():LocalDate=minusDays(dayOfWeek.value.toLong()-1)
