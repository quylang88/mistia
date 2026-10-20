package vn.com.quyln.mistia.core.model

import java.time.LocalDate
import java.time.ZoneId
import java.time.Instant
import java.math.BigInteger

data class OverviewExpenseDayRow(val transaction:LedgerTransactionRecord,val money:Money?)
data class OverviewExpenseDay(val day:LocalDate,val currencyCode:String,val rows:List<OverviewExpenseDayRow>,val totalMinor:BigInteger?)

fun overviewExpenseDay(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,day:LocalDate,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),zone:ZoneId):OverviewExpenseDay {
    val target=currency.overviewCurrencyCode() ?: "JPY"
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
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank) ?: wallet?.currencyCode ?: "JPY"
        val money=source.overviewCurrencyCode()?.let {Money(record.amountMinor,it)}
        DatedRow(OverviewExpenseDayRow(record,money),occurred,created)
    }.sortedWith(compareByDescending<DatedRow> {it.occurred}.thenByDescending {it.created}).map {it.row}
    var total:BigInteger?=BigInteger.ZERO
    for(row in rows) {
        if(row.transaction.amountMinor==0L) continue
        val converted=row.money?.let {overviewMoneyMinorExact(it.minor,it.currencyCode,target,rates)}
        total=total?.let {subtotal ->converted?.let(subtotal::plus)}
    }
    return OverviewExpenseDay(day,target,rows,total)
}
