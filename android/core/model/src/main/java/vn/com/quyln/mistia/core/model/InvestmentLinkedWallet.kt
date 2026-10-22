package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

data class InvestmentWalletSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    fun requireUnchanged(current:InvestmentWalletSnapshot) {
        require(owner==current.owner)
        fun ordered(values:List<CloudRecord>)=values.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))
        require(ordered(rows)==ordered(current.rows))
    }
    companion object {val entities=setOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING)}
}

data class InvestmentWalletLinkRequest(
    val expectedSystem:LedgerWalletRecord,
    val expectedTarget:LedgerWalletRecord,
    val eventId:String,
    val moveAllBookedCash:Boolean,
    val expectedBookedMinor:Long,
    val ledgerTitle:String,
)

enum class InvestmentWalletLinkError { INVALID_WALLET, UNREADABLE_SOURCE, STALE_RECORD, UNREADABLE_CASH, EVENT_CONFLICT }
class InvestmentWalletLinkException(val reason:InvestmentWalletLinkError):IllegalArgumentException(reason.name)
data class InvestmentWalletLinkPlan(val linkedWalletId:String,val mutations:List<Pair<CloudRecord,PendingMutation>>)

fun planInvestmentWalletLink(
    snapshot:InvestmentWalletSnapshot,request:InvestmentWalletLinkRequest,deviceId:String,now:String,
):InvestmentWalletLinkPlan {
    fun fail(reason:InvestmentWalletLinkError):Nothing=throw InvestmentWalletLinkException(reason)
    fun unreadable():Nothing=fail(InvestmentWalletLinkError.UNREADABLE_SOURCE)
    fun identity(value:String):String=financeRawUuid(value)?.takeIf{it==value} ?: unreadable()
    fun instant(value:String)=try{Instant.parse(value)}catch(_:Exception){unreadable()}
    identity(snapshot.owner.value);identity(deviceId);identity(request.eventId);instant(now)
    if(snapshot.rows.any { row ->
        val entity=CloudEntity.fromTable(row.entity)
        entity !in InvestmentWalletSnapshot.entities || row.ownerUserId!=snapshot.owner.value ||
            !row.financeRawIdentity(snapshot.owner,requireNotNull(entity),true) || financeRawUuid(row.id)!=row.id
    } || snapshot.rows.map{it.entity to it.id}.distinct().size!=snapshot.rows.size)unreadable()
    fun record(entity:CloudEntity,id:String)=snapshot.rows.singleOrNull{it.entity==entity.table && it.id==id}
    fun wallet(raw:CloudRecord)=investmentLinkedWalletRecord(raw)
    fun visible(expected:LedgerWalletRecord,current:LedgerWalletRecord):Boolean =
        expected.copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=instant(expected.createdAt).toString())==
            current.copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=instant(current.createdAt).toString())
    val systemId=investmentSystemWalletId(snapshot.owner)
    if(request.expectedSystem.id!=systemId || request.expectedSystem.ownerUserId!=snapshot.owner.value ||
        request.expectedTarget.ownerUserId!=snapshot.owner.value)fail(InvestmentWalletLinkError.INVALID_WALLET)
    val rawSystem=record(CloudEntity.LEDGER_WALLET,systemId) ?: fail(InvestmentWalletLinkError.INVALID_WALLET)
    val system=wallet(rawSystem)
    val code=investmentAssetCurrency(system.currencyCode) ?: unreadable()
    if(system.kind!=WalletKind.INVESTMENT || system.systemPurposeRawValue!="investmentProfit" ||
        system.deletedAt!=null || system.isArchived)fail(InvestmentWalletLinkError.INVALID_WALLET)
    val targetId=identity(request.expectedTarget.id)
    val target=record(CloudEntity.LEDGER_WALLET,targetId)?.let(::wallet) ?: fail(InvestmentWalletLinkError.INVALID_WALLET)
    if(target.kind==null || target.kind in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) ||
        target.id==systemId || target.systemPurposeRawValue=="investmentProfit" || target.deletedAt!=null || target.isArchived ||
        investmentAssetCurrency(target.currencyCode)!=code)fail(InvestmentWalletLinkError.INVALID_WALLET)
    if(!visible(request.expectedTarget,target))fail(InvestmentWalletLinkError.STALE_RECORD)
    val previousId=request.expectedSystem.investmentLinkedWalletId
    val ledgerId=investmentLedgerIdentity(request.eventId,"linked-wallet-move")
    val oldPostingId=investmentLedgerIdentity(request.eventId,"old-linked-cash-posting")
    val newPostingId=investmentLedgerIdentity(request.eventId,"new-linked-cash-posting")
    val eventRecords=listOf(record(CloudEntity.LEDGER_TRANSACTION,ledgerId),record(CloudEntity.INVESTMENT_POSTING,oldPostingId),record(CloudEntity.INVESTMENT_POSTING,newPostingId))
    fun verifyEvent():Boolean {
        if(!request.moveAllBookedCash || request.expectedBookedMinor<=0 || previousId==null || eventRecords.any{it==null})return false
        if(eventRecords.any{raw ->runCatching {
            val row=requireNotNull(raw)
            investmentAssetVersion(row)
            for(key in listOf("created_at","updated_at","occurred_at"))Instant.parse(requireNotNull(row.payload.financeRawString(key)))
            require(row.financeRawDeleted(true)==false)
        }.isFailure})return false
        val ledger=eventRecords[0]!!;val p=ledger.payload
        if(p.financeRawArchived()!=false || p.financeRawString("settlement_role_raw_value")!="investmentReconciliation" ||
            p.financeRawString("primary_kind_raw_value")!="transfer" || p.financeRawString("transfer_subtype_raw_value")!="internalTransfer" ||
            p.financeRawString("source_wallet_id")!=previousId || p.financeRawString("destination_wallet_id")!=targetId ||
            p.financeRawString("source_currency_code")!=code || p.financeRawString("destination_currency_code")!=code ||
            p.financeRawString("reporting_currency_code")!=code || p.financeRawString("entry_status_raw_value")!="posted" ||
            listOf("amount_minor","destination_amount_minor","reporting_amount_minor").any{p.financeRawLong(it)!=request.expectedBookedMinor})return false
        return eventRecords.drop(1).withIndex().all{(index,raw) ->
            val row=raw!!;val body=row.payload;val signed=if(index==0)-request.expectedBookedMinor else request.expectedBookedMinor
            row.financeRawDeleted(true)==false && body.financeRawString("event_id")==request.eventId &&
                body.financeRawString("wallet_id")== (if(index==0)previousId else targetId) &&
                body.financeRawString("ledger_transaction_id")==ledgerId && body.financeRawString("role_raw_value")=="cashTransfer" &&
                body["trade_id"]==JsonNull && body["asset_id"]==JsonNull && body.financeRawString("cash_bucket_raw_value")=="booked" &&
                body.financeRawString("cash_origin_raw_value")=="manual" && body.financeRawString("currency_code")==code &&
                body.financeRawString("accounting_currency_code")==code && body.financeRawLong("amount_minor")==signed &&
                body.financeRawLong("accounting_amount_minor")==signed &&
                Instant.parse(body.financeRawString("occurred_at"))==Instant.parse(p.financeRawString("occurred_at"))
        }
    }
    if(eventRecords.any{it!=null}) {
        if(system.investmentLinkedWalletId==targetId && verifyEvent())return InvestmentWalletLinkPlan(targetId,emptyList())
        fail(InvestmentWalletLinkError.EVENT_CONFLICT)
    }
    if(!visible(request.expectedSystem,system)) {
        if(!request.moveAllBookedCash && system.investmentLinkedWalletId==targetId &&
            visible(request.expectedSystem.copy(investmentLinkedWalletId=targetId),system))return InvestmentWalletLinkPlan(targetId,emptyList())
        fail(InvestmentWalletLinkError.STALE_RECORD)
    }
    if(system.investmentLinkedWalletId==targetId)return InvestmentWalletLinkPlan(targetId,emptyList())
    var amount=0L
    if(request.moveAllBookedCash && previousId!=null) {
        val previous=record(CloudEntity.LEDGER_WALLET,identity(previousId))?.let(::wallet) ?: fail(InvestmentWalletLinkError.INVALID_WALLET)
        if(previous.deletedAt!=null || previous.kind==null || previous.kind in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) ||
            investmentAssetCurrency(previous.currencyCode)!=code)fail(InvestmentWalletLinkError.INVALID_WALLET)
        amount=investmentBookedCashMinor(snapshot,previousId,code)
        if(amount!=request.expectedBookedMinor)fail(InvestmentWalletLinkError.STALE_RECORD)
    }
    val changed=investmentAssetChanged(rawSystem,buildJsonObject{put("investment_linked_wallet_id",targetId)},deviceId,now)
    val rows=mutableListOf(changed)
    fun create(entity:CloudEntity,id:String,fields:JsonObject):CloudRecord=CloudRecord(entity.table,id,snapshot.owner.value,buildJsonObject {
        put("id",id);put("user_id",snapshot.owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
        put("sync_version",0L);put("last_modified_by_device_id",deviceId);fields.forEach{put(it.key,it.value)}
    },now,null,0L)
    if(amount>0) {
        if(normalizedInvestmentChannelName(request.ledgerTitle).isEmpty())unreadable()
        rows+=create(CloudEntity.LEDGER_TRANSACTION,ledgerId,buildJsonObject {
            put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
            put("title",request.ledgerTitle);put("amount_minor",amount);put("source_wallet_id",previousId);put("destination_wallet_id",targetId)
            put("source_currency_code",code);put("destination_currency_code",code);put("destination_amount_minor",amount)
            put("reporting_currency_code",code);put("reporting_amount_minor",amount);put("reporting_expense_minor",0L);put("reporting_income_minor",0L)
            put("settlement_role_raw_value","investmentReconciliation");put("occurred_at",now);put("is_archived",false)
            put("created_by_user_id",snapshot.owner.value);put("last_modified_by_user_id",snapshot.owner.value)
            for(key in listOf("note","debt_intent_raw_value","category_id","settlement_group_id","settlement_obligation_id","archived_at",
                "conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))put(key,JsonNull)
        })
        for((index,id) in listOf(oldPostingId,newPostingId).withIndex())rows+=create(CloudEntity.INVESTMENT_POSTING,id,buildJsonObject {
            val signed=if(index==0)-amount else amount
            put("event_id",request.eventId);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",if(index==0)previousId else targetId)
            put("ledger_transaction_id",ledgerId);put("role_raw_value","cashTransfer");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
            put("amount_minor",signed);put("currency_code",code);put("accounting_amount_minor",signed);put("accounting_currency_code",code);put("occurred_at",now)
        })
    }
    return InvestmentWalletLinkPlan(targetId,rows.map{row ->row to PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,snapshot.owner.value,
        MutationKind.UPSERT,row.payload,now,row.syncVersion,deviceId)})
}

fun investmentLinkedWalletRecord(raw:CloudRecord):LedgerWalletRecord {
    fun unreadable():Nothing=throw InvestmentWalletLinkException(InvestmentWalletLinkError.UNREADABLE_SOURCE)
    fun instant(value:String)=try{Instant.parse(value)}catch(_:Exception){unreadable()}
    val p=raw.payload
    if(raw.entity!=CloudEntity.LEDGER_WALLET.table || p.financeRawLong("opening_balance_minor")==null ||
        p.financeRawArchived()==null || raw.financeRawDeleted(true)==null || p.financeRawString("name")==null ||
        p.financeRawString("kind_raw_value")==null || p.financeRawString("currency_code")==null)unreadable()
    try{investmentAssetVersion(raw)}catch(_:Exception){unreadable()}
    instant(p.financeRawString("created_at") ?: unreadable());instant(p.financeRawString("updated_at") ?: unreadable())
    val link=p.financeRawReference("investment_linked_wallet_id");if(!link.readable)unreadable()
    for(key in listOf("system_purpose_raw_value","last_modified_by_device_id","archived_at","deleted_at"))
        if(p[key]!=null && p[key]!=JsonNull && p.financeRawString(key)==null)unreadable()
    return try{LedgerWalletRecord.fromCloudRecord(raw)}catch(_:Exception){unreadable()}
}

fun investmentBookedCashMinor(snapshot:InvestmentWalletSnapshot,walletId:String?,code:String):Long {
    fun fail(reason:InvestmentWalletLinkError):Nothing=throw InvestmentWalletLinkException(reason)
    requireInvestmentWalletReadScope(snapshot)
    if(walletId==null)return 0L
    var sum=BigInteger.ZERO
    for(raw in snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}) {
        val deleted=raw.financeRawDeleted(true) ?: fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        if(deleted)continue
        val p=raw.payload;val bucket=p.financeRawString("cash_bucket_raw_value")
        if(bucket==null) {
            if(p["cash_bucket_raw_value"]!=null && p["cash_bucket_raw_value"]!=JsonNull)fail(InvestmentWalletLinkError.UNREADABLE_CASH)
            if(p.financeRawString("role_raw_value") in setOf("funding","capitalReturn","realizedProfit"))continue
            fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        }
        if(bucket !in setOf("booked","unreconciled"))fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        val ref=p.financeRawReference("wallet_id")
        if(!ref.readable || ref.id==null)fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        if(bucket!="booked" || ref.id!=walletId)continue
        if(p.financeRawString("currency_code")!=code || p.financeRawString("accounting_currency_code")!=code)fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        val value=p.financeRawLong("accounting_amount_minor") ?: fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        if(p.financeRawLong("amount_minor")!=value)fail(InvestmentWalletLinkError.UNREADABLE_CASH)
        sum=sum.add(BigInteger.valueOf(value))
    }
    return try{sum.longValueExact().coerceAtLeast(0)}catch(_:ArithmeticException){fail(InvestmentWalletLinkError.UNREADABLE_CASH)}
}

private fun requireInvestmentWalletReadScope(snapshot:InvestmentWalletSnapshot) {
    if(financeRawUuid(snapshot.owner.value)!=snapshot.owner.value || snapshot.rows.any { row ->
        val entity=CloudEntity.fromTable(row.entity)
        entity==null || entity !in InvestmentWalletSnapshot.entities || !row.financeRawIdentity(snapshot.owner,entity,true) || financeRawUuid(row.id)!=row.id
    } || snapshot.rows.map{it.entity to it.id}.distinct().size!=snapshot.rows.size)
        throw InvestmentWalletLinkException(InvestmentWalletLinkError.UNREADABLE_SOURCE)
}

fun LedgerWalletRecord.matchesVisibleInvestmentWallet(other:LedgerWalletRecord):Boolean =
    copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=Instant.parse(createdAt).toString())==
        other.copy(updatedAt="",syncVersion=0,lastModifiedByDeviceId=null,createdAt=Instant.parse(other.createdAt).toString())

data class InvestmentLinkedWalletView(
    val system:LedgerWalletRecord,val linkedWallet:LedgerWalletRecord?,
    val eligibleWallets:List<LedgerWalletRecord>,val bookedMinor:Long?,
)
fun investmentLinkedWalletView(snapshot:InvestmentWalletSnapshot):InvestmentLinkedWalletView {
    requireInvestmentWalletReadScope(snapshot)
    val wallets=snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.map(::investmentLinkedWalletRecord)
    val system=wallets.singleOrNull{it.id==investmentSystemWalletId(snapshot.owner)}
        ?: throw InvestmentWalletLinkException(InvestmentWalletLinkError.INVALID_WALLET)
    val code=investmentAssetCurrency(system.currencyCode)
        ?: throw InvestmentWalletLinkException(InvestmentWalletLinkError.UNREADABLE_SOURCE)
    if(system.kind!=WalletKind.INVESTMENT || system.systemPurposeRawValue!="investmentProfit" || system.deletedAt!=null || system.isArchived)
        throw InvestmentWalletLinkException(InvestmentWalletLinkError.INVALID_WALLET)
    val eligible=wallets.filter{it.kind!=null && it.kind !in setOf(WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) && it.id!=system.id &&
        it.systemPurposeRawValue!="investmentProfit" && !it.isArchived && it.deletedAt==null && investmentAssetCurrency(it.currencyCode)==code}
        .sortedWith(compareBy(LedgerWalletRecord::sortOrder).thenBy{Instant.parse(it.createdAt)}.thenBy(LedgerWalletRecord::id))
    val linked=wallets.singleOrNull{it.id==system.investmentLinkedWalletId}
    val movable=system.investmentLinkedWalletId==null || (linked!=null && linked.deletedAt==null && linked.kind!=null &&
        linked.kind !in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT) && investmentAssetCurrency(linked.currencyCode)==code)
    val booked=if(movable)runCatching{investmentBookedCashMinor(snapshot,system.investmentLinkedWalletId,code)}.getOrNull() else null
    return InvestmentLinkedWalletView(system,linked,eligible,booked)
}
