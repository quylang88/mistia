package vn.com.quyln.mistia.core.model

import java.time.*
import java.math.BigInteger
import java.math.BigDecimal
import java.math.RoundingMode

data class OverviewDailySpending(val date:LocalDate,val amountMinor:Long,val intensity:Double)
data class OverviewWeekSpending(val start:LocalDate,val isCurrent:Boolean,val points:List<OverviewDailySpending>) {val end:LocalDate get()=start.plusDays(6)}
fun overviewWeeklySpending(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,currency:String?=null,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),reference:Instant,zone:ZoneId):List<OverviewWeekSpending> {
    val day=reference.atZone(zone).toLocalDate();val current=day.mondayStart()
    val kinds=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associate {it.id to it.kind}
    val totals=mutableMapOf<LocalDate,BigInteger>()
    var earliest:LocalDate?=null
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null) continue
        val expense=reportedOverviewExpense(record,kinds[record.sourceWalletId],knownTitles)
        if(expense==0L) continue
        val date=runCatching {Instant.parse(record.occurredAt).atZone(zone).toLocalDate()}.getOrNull() ?: continue
        val amount=if(currency==null) BigInteger.valueOf(expense) else planningMoneyMinorExact(expense,record.sourceCurrencyCode,currency,rates)
        totals[date]=(totals[date] ?: BigInteger.ZERO)+amount
        val start=date.mondayStart()
        if(earliest==null || start<earliest) earliest=start
    }
    val pages=mutableListOf<OverviewWeekSpending>()
    var start=(earliest ?: current).coerceAtMost(current)
    while(start<=current) {
        val dates=(0L..6).map {start.plusDays(it)}
        val amounts=dates.map {(totals[it] ?: BigInteger.ZERO).clampedWeekAmount()}
        val minimum=amounts.minOrNull() ?: 0;val maximum=amounts.maxOrNull() ?: 0
        val range=BigInteger.valueOf(maximum)-BigInteger.valueOf(minimum)
        val points=dates.mapIndexed {index,date ->
            val amount=amounts[index]
            val intensity=if(range.signum()==0) {if(maximum==0L) 0.0 else 0.5}
                else BigDecimal(BigInteger.valueOf(amount)-BigInteger.valueOf(minimum)).divide(BigDecimal(range),24,RoundingMode.HALF_UP).toDouble()
            OverviewDailySpending(date,amount,intensity)
        }
        pages+=OverviewWeekSpending(start,start==current,points)
        start=start.plusWeeks(1)
    }
    return pages
}
private fun LocalDate.mondayStart():LocalDate=minusDays(dayOfWeek.value.toLong()-1)
private fun BigInteger.clampedWeekAmount():Long=max(BigInteger.valueOf(Long.MIN_VALUE)).min(BigInteger.valueOf(Long.MAX_VALUE)).toLong()
