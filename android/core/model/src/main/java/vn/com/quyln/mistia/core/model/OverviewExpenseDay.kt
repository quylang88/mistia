package vn.com.quyln.mistia.core.model

import java.time.LocalDate
import java.time.ZoneId
import java.time.Instant
import java.util.Locale
import java.math.BigInteger

data class OverviewExpenseDayRow(val transaction:LedgerTransactionRecord,val money:Money)
data class OverviewExpenseDay(val day:LocalDate,val currencyCode:String,val rows:List<OverviewExpenseDayRow>,val totalMinor:Long?)

fun overviewExpenseDay(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,day:LocalDate,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),zone:ZoneId):OverviewExpenseDay {
    val target=currency.dayCurrency() ?: "JPY"
    val ownedWallets=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associateBy {it.id}
    data class DatedRow(val row:OverviewExpenseDayRow,val occurred:Instant,val created:Instant)
    val rows=records.mapNotNull {record ->
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null ||
            record.settlementRoleWireValue?.startsWith("investment")==true) return@mapNotNull null
        val wallet=ownedWallets[record.sourceWalletId]
        if(!isOverviewExpenseSpending(record,wallet?.kind,knownTitles)) return@mapNotNull null
        val occurred=runCatching {Instant.parse(record.occurredAt)}.getOrNull() ?: return@mapNotNull null
        val created=runCatching {Instant.parse(record.createdAt)}.getOrNull() ?: return@mapNotNull null
        if(occurred.atZone(zone).toLocalDate()!=day) return@mapNotNull null
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank)?.let {it.dayCurrency() ?: return@mapNotNull null}
            ?: wallet?.currencyCode?.dayCurrency() ?: target
        DatedRow(OverviewExpenseDayRow(record,Money(record.amountMinor,source)),occurred,created)
    }.sortedWith(compareByDescending<DatedRow> {it.occurred}.thenByDescending {it.created}).map {it.row}
    var total=BigInteger.ZERO
    var available=true
    for(row in rows) {
        val source=row.money.currencyCode
        if(source==target || row.money.minor==0L) total+=BigInteger.valueOf(row.money.minor)
        else if(source in CurrencyPreferences.supportedCurrencyCodes && target in CurrencyPreferences.supportedCurrencyCodes && matchingExchangeRateSnapshot(source,target,rates)!=null)
            total+=planningMoneyMinorExact(row.money.minor,source,target,rates)
        else available=false
    }
    return OverviewExpenseDay(day,target,rows,if(available) total.max(BigInteger.valueOf(Long.MIN_VALUE)).min(BigInteger.valueOf(Long.MAX_VALUE)).toLong() else null)
}
private fun String.dayCurrency():String?=trim().uppercase(Locale.ROOT).takeIf {it.matches(Regex("[A-Z]{3}"))}
