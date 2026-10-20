package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Original-day details consume original money and eligibility, independently of reporting overrides. */
internal fun overviewRawExpenseDay(owner:UserId,records:List<CloudRecord>,wallets:List<CloudRecord>,day:LocalDate,currency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),zone:ZoneId):OverviewExpenseDay {
    val target=currency.overviewReportingCode() ?: "JPY"
    val metadata=wallets.filter {it.overviewRawIdentity(owner,CloudEntity.LEDGER_WALLET) && it.overviewRawDeleted()!=true}.associateBy {overviewRawUuid(it.id)}
    data class DatedRow(val row:OverviewExpenseDayRow,val occurred:Instant,val created:Instant?)
    val rows=mutableListOf<DatedRow>()
    var uncertainEntries=false
    var uncertainMoney=false
    for(raw in records) {
        if(!raw.overviewRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION)) continue
        val p=raw.payload
        val deleted=raw.overviewRawDeleted();val archived=p.overviewRawArchived()
        val status=p.overviewRawString("entry_status_raw_value")?.let(TransactionEntryStatus::fromWireValue)
        if(deleted==true || archived==true || status==TransactionEntryStatus.DRAFT) continue
        val occurred=p.overviewRawString("occurred_at")?.let {runCatching {Instant.parse(it)}.getOrNull()}
        val date=occurred?.let {runCatching {it.atZone(zone).toLocalDate()}.getOrNull()}
        if(date!=null && date!=day) continue
        val source=p.overviewRawReference("source_wallet_id")
        val wallet=metadata[source.id]
        val kind=wallet?.payload?.overviewRawString("kind_raw_value")?.let(WalletKind::fromWireValue)
        val kindKnown=source.readable && (wallet==null || (wallet.overviewRawDeleted()==false && kind!=null))
        val eligibility=originalExpenseEligibility(raw,kind,kindKnown,knownTitles)
        if(eligibility==false) continue
        val original=p.overviewRawLong("amount_minor")
        if(eligibility==null || deleted==null || archived==null || status!=TransactionEntryStatus.POSTED || date==null) {
            uncertainEntries=true
            if(original!=0L) uncertainMoney=true
            continue
        }
        val code=when {
            p.present("source_currency_code") -> p.overviewRawString("source_currency_code")?.overviewReportingCode()
            !source.readable -> null
            wallet==null -> "JPY"
            wallet.overviewRawDeleted()==null -> null
            else -> wallet.payload.overviewRawString("currency_code")?.overviewReportingCode()
        }
        val money=original?.let {minor ->code?.let {Money(minor,it)}}
        // Display metadata only. The explicit nullable originalMinor, never the placeholder, drives totals.
        // Editing reloads the trusted id from storage; this snapshot must never be saved as a transaction.
        val display=LedgerTransactionRecord.fromCloudRecord(raw.copy(payload=buildJsonObject {
            put("id",overviewRawUuid(raw.id)!!);put("user_id",owner.value);put("entry_status_raw_value","posted");put("amount_minor",original ?: 0)
            for(key in listOf("primary_kind_raw_value","transfer_subtype_raw_value","debt_intent_raw_value","title","note","occurred_at","created_at","settlement_role_raw_value")) p.overviewRawString(key)?.let {put(key,it)}
            source.id?.let {put("source_wallet_id",it)};p.overviewRawReference("category_id").id?.let {put("category_id",it)}
            code?.let {put("source_currency_code",it)}
        },deletedAt=null))
        rows+=DatedRow(OverviewExpenseDayRow(display,money,original),occurred!!,p.overviewRawString("created_at")?.let {runCatching {Instant.parse(it)}.getOrNull()})
    }
    val sorted=rows.sortedWith(compareByDescending<DatedRow> {it.occurred}.thenByDescending {it.created}).map {it.row}
    val total=if(uncertainMoney) null else overviewExpenseDayTotal(sorted,target,rates)
    return OverviewExpenseDay(day,target,sorted,total,uncertainEntries)
}

private fun originalExpenseEligibility(raw:CloudRecord,kind:WalletKind?,kindKnown:Boolean,titles:Map<GeneratedTransactionTitle,Collection<String>>):Boolean? {
    val p=raw.payload
    val role=p.overviewRawString("settlement_role_raw_value")
    if(role?.startsWith("investment")==true) return false
    val unknownRole=p.present("settlement_role_raw_value") && role==null
    val primary=p.overviewRawString("primary_kind_raw_value")?.let(TransactionPrimaryKind::fromWireValue)
    var result:Boolean?=null
    var seen=false
    for(value in primary?.let(::listOf) ?: TransactionPrimaryKind.entries) {
        for((candidate,walletKind) in overviewClassificationCandidates(raw,value,kind,kindKnown,titles)) {
            val next=isOverviewExpenseSpending(candidate,walletKind,titles)
            if(!seen) {seen=true;result=next} else if(result!=next) return null
        }
    }
    return if(result==true && unknownRole) null else result
}

/** Historical labels only; unused wallet opening and kind cannot discard an owned readable name. */
internal fun overviewDayWalletMetadata(owner:UserId,wallets:List<CloudRecord>):Map<String,LedgerWalletRecord> = wallets.mapNotNull {raw ->
    if(!raw.overviewRawIdentity(owner,CloudEntity.LEDGER_WALLET) || raw.overviewRawDeleted()!=false) null
    else raw.payload.overviewRawString("name")?.let {name ->
        LedgerWalletRecord.fromCloudRecord(raw.copy(payload=buildJsonObject {put("id",overviewRawUuid(raw.id)!!);put("user_id",owner.value);put("name",name);put("opening_balance_minor",0)}))
    }
}.associateBy {it.id}
