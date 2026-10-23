package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

enum class InvestmentFundTimelineError { UNREADABLE_SOURCE, INVALID_REPLACEMENT, UNSUPPORTED_CURRENCY_CONVERSION }
class InvestmentFundTimelineException(val reason:InvestmentFundTimelineError):IllegalArgumentException(reason.name)

data class InvestmentFundTimelineUsage(val transactionId:String,val walletId:String,val currencyCode:String,
    val requestedMinor:BigInteger,val ordinaryAvailableMinor:BigInteger,val bookedToUseMinor:BigInteger,
    val unreconciledToUseMinor:BigInteger,val remainingInvestmentMinor:BigInteger,val outcome:InvestmentFundUsageOutcome) {
    val investmentToUseMinor get()=bookedToUseMinor+unreconciledToUseMinor
}
data class InvestmentFundTimeline(val usages:Map<String,InvestmentFundTimelineUsage>,val availableByWalletId:Map<String,BigInteger>,
    val actualByWalletId:Map<String,BigInteger>)
data class InvestmentFundTimelineWalletChange(val walletId:String,val currencyCode:String,val previousMinor:BigInteger,
    val proposedMinor:BigInteger,val remainingInvestmentMinor:BigInteger) {
    val restoreMinor get()=(previousMinor-proposedMinor).max(BigInteger.ZERO)
}
data class InvestmentFundTimelineComparison(val current:InvestmentFundTimeline,val proposed:InvestmentFundTimeline,
    val changes:List<InvestmentFundTimelineWalletChange>) {
    val primaryChange get()=changes.firstOrNull()
}

/** The timeline is a read proof, not permission to write or replace frozen user consent. */
fun investmentFundUsageTimeline(snapshot:InvestmentCashReadSnapshot,accountingCurrency:String):InvestmentFundTimeline =
    FundTimelineSource(snapshot,accountingCurrency).replay()

/** Null replacement removes an existing owned event. Null identity compares a new proposal. */
fun compareInvestmentFundUsageTimeline(snapshot:InvestmentCashReadSnapshot,accountingCurrency:String,
    replacingTransactionId:String?,proposed:CloudRecord?):InvestmentFundTimelineComparison {
    val source=FundTimelineSource(snapshot,accountingCurrency)
    val old=replacingTransactionId?.let{id ->
        if(financeRawUuid(id)!=id)timelineFail(InvestmentFundTimelineError.INVALID_REPLACEMENT)
        snapshot.rows.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id}
            ?.takeIf{it.financeRawDeleted(true)==false && !requiresInvestmentLedgerDomain(it.payload)}
            ?: timelineFail(InvestmentFundTimelineError.INVALID_REPLACEMENT)
    }
    if(proposed!=null) {
        if(!proposed.financeRawIdentity(snapshot.owner,CloudEntity.LEDGER_TRANSACTION,true) || financeRawUuid(proposed.id)!=proposed.id ||
            (old!=null && proposed.id!=old.id) || requiresInvestmentLedgerDomain(proposed.payload) ||
            (old==null && snapshot.rows.any{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==proposed.id}))
            timelineFail(InvestmentFundTimelineError.INVALID_REPLACEMENT)
    } else if(old==null)timelineFail(InvestmentFundTimelineError.INVALID_REPLACEMENT)
    val current=source.replay();val next=source.replay(replacingTransactionId,proposed)
    return compareInvestmentFundTimelines(current,next){id->source.wallets.getValue(id).currencyCode}
}

/** Reserved allocation identity and buckets matter even when wallet totals agree. */
internal fun compareInvestmentFundTimelines(before:InvestmentFundTimeline,after:InvestmentFundTimeline,currencyForWallet:(String)->String):InvestmentFundTimelineComparison {
    fun totals(t:InvestmentFundTimeline)=t.usages.values.groupBy{it.walletId}.mapValues{(_,values)->values.fold(BigInteger.ZERO){sum,use->sum+use.investmentToUseMinor}}
    val previous=totals(before);val next=totals(after)
    // Equal wallet totals can hide moving booked/unreconciled consumption
    // between transactions. Those derived records still need explicit consent.
    val reallocated=buildSet {
        (before.usages.keys+after.usages.keys).forEach{id->
            val old=before.usages[id];val new=after.usages[id]
            fun reserved(use:InvestmentFundTimelineUsage?)=use?.takeIf{it.investmentToUseMinor.signum()>0}?.let{Triple(it.walletId,it.bookedToUseMinor,it.unreconciledToUseMinor)}
            if(reserved(old)!=reserved(new)) {
                old?.takeIf{it.investmentToUseMinor.signum()>0}?.let{add(it.walletId)}
                new?.takeIf{it.investmentToUseMinor.signum()>0}?.let{add(it.walletId)}
            }
        }
    }
    val changes=(previous.keys+next.keys).mapNotNull{id ->
        val old=previous[id] ?: BigInteger.ZERO;val new=next[id] ?: BigInteger.ZERO
        if(old==new && id !in reallocated)null else InvestmentFundTimelineWalletChange(id,currencyForWallet(id),old,new,after.availableByWalletId[id] ?: BigInteger.ZERO)
    }.sortedWith(compareByDescending<InvestmentFundTimelineWalletChange>{(it.proposedMinor-it.previousMinor).abs()}.thenByDescending{it.walletId})
    return InvestmentFundTimelineComparison(before,after,changes)
}

private fun timelineFail(reason:InvestmentFundTimelineError=InvestmentFundTimelineError.UNREADABLE_SOURCE):Nothing=throw InvestmentFundTimelineException(reason)
private fun JsonObject.timelineString(key:String)=financeRawString(key) ?: timelineFail()
private fun JsonObject.timelineInstant(key:String)=runCatching{Instant.parse(timelineString(key))}.getOrElse{timelineFail()}
private fun JsonObject.timelineReference(key:String)=financeRawReference(key).let{if(!it.readable)timelineFail() else it.id}
private data class FundTimelineEvent(val id:String,val occurred:Instant,val created:Instant,val priority:Int,
    val ledger:CloudRecord?=null,val walletId:String?=null,val bucket:String?=null,val amount:BigInteger=BigInteger.ZERO,
    val localAmount:BigInteger=BigInteger.ZERO,
    val deltas:Map<String,BigInteger> = emptyMap())

private class FundTimelineSource(val snapshot:InvestmentCashReadSnapshot,accountingCurrency:String) {
    private val code=investmentAssetCurrency(accountingCurrency) ?: timelineFail()
    private val owner=snapshot.owner
    val wallets:Map<String,LedgerWalletRecord>
    private val zeroWallets:List<CloudRecord>
    private val postings:List<CloudRecord>
    init {
        try{snapshot.requireScoped()}catch(_:Exception){timelineFail()}
        val activeWallets=snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.filter {
            when(it.financeRawDeleted(true)){true->false;false->true;null->timelineFail()}
        }.filter {when(it.payload.financeRawArchived()){true->false;false->true;null->timelineFail()}}
        wallets=activeWallets.associate{raw ->
            val record=try{investmentLinkedWalletRecord(raw)}catch(_:Exception){timelineFail()}
            if(record.kind==null)timelineFail()
            raw.id to record
        }
        zeroWallets=activeWallets.map{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(0L))))}
        postings=snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
    }
    private fun validatedFunding(raw:CloudRecord):Boolean {
        val p=raw.payload
        if(p.financeRawString("settlement_role_raw_value")!="investmentFunding")return false
        val candidates=snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawReference("funding_ledger_transaction_id").id==raw.id}
        if(candidates.isEmpty())return false
        val trade=candidates.singleOrNull() ?: timelineFail();val t=trade.payload
        if(trade.financeRawDeleted(true)!=false || t.financeRawString("kind_raw_value")!="buy" || raw.id!=investmentLedgerIdentity(trade.id,"funding") ||
            p.financeRawString("primary_kind_raw_value")!="expense" || p.financeRawString("entry_status_raw_value")!="posted" ||
            p.financeRawReference("source_wallet_id").id!=t.financeRawReference("funding_wallet_id").id ||
            p.financeRawLong("amount_minor")!=t.financeRawLong("funding_wallet_amount_minor") || p.financeRawLong("amount_minor")?.let{it>0}!=true ||
            p.financeRawString("source_currency_code")!=t.financeRawString("funding_wallet_currency_code") ||
            p.financeRawString("reporting_currency_code")!=t.financeRawString("accounting_currency_code") ||
            p.financeRawLong("reporting_amount_minor")!=t.financeRawLong("accounting_gross_amount_minor"))timelineFail()
        return true
    }
    fun replay(replacing:String?=null,proposed:CloudRecord?=null):InvestmentFundTimeline {
        val events=mutableListOf<FundTimelineEvent>()
        val noncash=setOf("funding","capitalReturn","realizedProfit","transferOut","transferIn")
        val cashRoles=setOf("cashAccrual","cashTransfer","cashConsumption","cashReconciliation","cashCorrection")
        for(raw in postings) {
            if(raw.financeRawDeleted(true)==true)continue
            if(raw.financeRawDeleted(true)!=false)timelineFail()
            val p=raw.payload;val role=p.timelineString("role_raw_value")
            if(role !in noncash && role !in cashRoles)timelineFail()
            val bucket=p.financeRawString("cash_bucket_raw_value")
            if(bucket==null && !p.financePresent("cash_bucket_raw_value") && role in noncash)continue
            if(bucket !in setOf("booked","unreconciled"))timelineFail()
            val origin=p.timelineString("cash_origin_raw_value")
            if(origin !in setOf("manual","derived"))timelineFail()
            if(role=="cashConsumption" || (role=="cashTransfer" && origin=="derived"))continue
            val event=p.timelineReference("event_id") ?: timelineFail()
            if(event==replacing)continue
            val wallet=p.timelineReference("wallet_id") ?: timelineFail()
            val w=wallets[wallet] ?: continue
            if(w.kind==WalletKind.CREDIT_CARD)continue
            val localCode=investmentAssetCurrency(p.timelineString("currency_code")) ?: timelineFail()
            val accountCode=investmentAssetCurrency(p.timelineString("accounting_currency_code")) ?: timelineFail()
            val local=p.financeRawLong("amount_minor")?.let(BigInteger::valueOf) ?: timelineFail()
            val amount=p.financeRawLong("accounting_amount_minor")?.let(BigInteger::valueOf) ?: timelineFail()
            if(accountCode!=code || localCode!=w.currencyCode || (localCode==code && local!=amount))timelineFail()
            events+=FundTimelineEvent(raw.id,p.timelineInstant("occurred_at"),p.timelineInstant("created_at"),0,walletId=wallet,bucket=bucket,amount=amount,localAmount=local)
        }
        val transactions=snapshot.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id!=replacing}+listOfNotNull(proposed)
        for(raw in transactions) {
            if(raw.financeRawDeleted(true)==true || raw.payload.financeRawArchived()==true || raw.payload.financeRawString("entry_status_raw_value")=="draft")continue
            if(raw.financeRawDeleted(true)!=false || raw.payload.financeRawArchived()!=false)timelineFail()
            val role=raw.payload["settlement_role_raw_value"]
            if(role!=null && role!=JsonNull && raw.payload.financeRawString("settlement_role_raw_value")==null)timelineFail()
            if(raw.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")continue
            val deltas=financeWalletBalancesRaw(owner,listOf(raw),zeroWallets) ?: timelineFail()
            val nonzero=deltas.filterValues{it.signum()!=0}
            if(nonzero.isEmpty())continue
            val source=raw.payload.timelineReference("source_wallet_id")
            if(source in nonzero && raw.payload.financePresent("source_currency_code")) {
                val declared=investmentAssetCurrency(raw.payload.timelineString("source_currency_code")) ?: timelineFail()
                if(declared!=wallets.getValue(requireNotNull(source)).currencyCode)timelineFail()
            }
            events+=FundTimelineEvent(raw.id,raw.payload.timelineInstant("occurred_at"),raw.payload.timelineInstant("created_at"),1,ledger=raw,deltas=nonzero)
        }
        events.sortWith(compareBy(FundTimelineEvent::occurred,FundTimelineEvent::created,FundTimelineEvent::priority,FundTimelineEvent::id))
        val actual=wallets.values.filter{it.kind!=WalletKind.CREDIT_CARD}.associate{it.id to BigInteger.valueOf(it.openingBalanceMinor)}.toMutableMap()
        val booked=actual.keys.associateWith{BigInteger.ZERO}.toMutableMap()
        val unreconciled=actual.keys.associateWith{BigInteger.ZERO}.toMutableMap()
        val localBooked=actual.keys.associateWith{BigInteger.ZERO}.toMutableMap()
        val localUnreconciled=actual.keys.associateWith{BigInteger.ZERO}.toMutableMap()
        val usages=linkedMapOf<String,InvestmentFundTimelineUsage>()
        fun add(target:MutableMap<String,BigInteger>,id:String,amount:BigInteger){target[id]=(target[id] ?: BigInteger.ZERO)+amount}
        for(event in events) {
            val raw=event.ledger
            if(raw==null) {
                add(if(event.bucket=="booked")booked else unreconciled,requireNotNull(event.walletId),event.amount)
                add(if(event.bucket=="booked")localBooked else localUnreconciled,event.walletId,event.localAmount)
                continue
            }
            if(!requiresInvestmentLedgerDomain(raw.payload) || validatedFunding(raw))for((wallet,delta) in event.deltas.filterValues{it.signum()<0}) {
                val w=wallets.getValue(wallet);if(w.kind==WalletKind.CREDIT_CARD)continue
                val request=delta.negate();val beforeBooked=(booked[wallet] ?: BigInteger.ZERO).max(BigInteger.ZERO)
                val beforeUnreconciled=(unreconciled[wallet] ?: BigInteger.ZERO).max(BigInteger.ZERO)
                val ordinary=((actual[wallet] ?: BigInteger.ZERO)-(localBooked[wallet] ?: BigInteger.ZERO).max(BigInteger.ZERO)).max(BigInteger.ZERO)
                val needed=(request-ordinary).max(BigInteger.ZERO)
                if(w.currencyCode!=code) {
                    val localReserve=(localBooked[wallet] ?: BigInteger.ZERO).max(BigInteger.ZERO)+(localUnreconciled[wallet] ?: BigInteger.ZERO).max(BigInteger.ZERO)
                    if(needed.signum()>0 && localReserve.signum()>0)timelineFail(InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION)
                    continue
                }
                val useBooked=beforeBooked.min(needed);val useUnreconciled=beforeUnreconciled.min(needed-useBooked)
                val use=useBooked+useUnreconciled
                if(use.signum()==0)continue
                if(w.currencyCode!=code)timelineFail(InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION)
                val p=raw.payload
                val destination=if(p.financeRawString("primary_kind_raw_value")=="transfer" && p.financeRawString("transfer_subtype_raw_value")=="internalTransfer")
                    p.timelineReference("destination_wallet_id")?.let(wallets::get)?.takeIf{it.kind!=WalletKind.CREDIT_CARD} else null
                if(destination!=null && destination.currencyCode!=code)timelineFail(InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION)
                add(booked,wallet,-useBooked);add(unreconciled,wallet,-useUnreconciled)
                add(localBooked,wallet,-useBooked);add(localUnreconciled,wallet,-useUnreconciled)
                if(destination!=null){add(booked,destination.id,use);add(localBooked,destination.id,use)}
                if(useUnreconciled.signum()>0) {
                    val system=investmentSystemWalletId(owner)
                    val systemWallet=wallets[system] ?: timelineFail()
                    if(systemWallet.kind!=WalletKind.INVESTMENT || systemWallet.systemPurposeRawValue!="investmentProfit" || systemWallet.currencyCode!=code)timelineFail()
                    add(actual,wallet,useUnreconciled);add(actual,system,-useUnreconciled)
                }
                val remaining=((booked[wallet] ?: BigInteger.ZERO)+(unreconciled[wallet] ?: BigInteger.ZERO)).max(BigInteger.ZERO)
                usages[event.id]=InvestmentFundTimelineUsage(event.id,wallet,w.currencyCode,request,ordinary,useBooked,useUnreconciled,remaining,
                    if(needed>use)InvestmentFundUsageOutcome.INSUFFICIENT_FUNDS else InvestmentFundUsageOutcome.REQUIRES_CONFIRMATION)
            }
            event.deltas.forEach{(wallet,delta)->add(actual,wallet,delta)}
        }
        val available=actual.keys.associateWith{((booked[it] ?: BigInteger.ZERO)+(unreconciled[it] ?: BigInteger.ZERO)).max(BigInteger.ZERO)}
        return InvestmentFundTimeline(usages.toMap(),available,actual.toMap())
    }
}
