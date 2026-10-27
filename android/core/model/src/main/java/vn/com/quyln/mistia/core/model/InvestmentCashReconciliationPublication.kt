package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull

data class InvestmentCashReconciliationGroup(val ledger:CloudRecord,val holder:CloudRecord,val linked:CloudRecord) {
    val rows:List<CloudRecord> get()=listOf(ledger,holder,linked)
}
data class InvestmentCashReconciliationCloudSnapshot(val owner:UserId,val eventId:String,val ledger:CloudRecord?,val postings:List<CloudRecord>)
interface InvestmentCashReconciliationRemote {
    suspend fun fetchEvent(owner:UserId,eventId:String,accessToken:String):InvestmentCashReconciliationCloudSnapshot
    suspend fun createLedger(owner:UserId,eventId:String,ledger:CloudRecord,accessToken:String):CloudRecord?
    suspend fun publishPostings(owner:UserId,eventId:String,group:InvestmentCashReconciliationGroup,expectedVersions:Map<String,Long>,accessToken:String):List<CloudRecord>
}
/** Confirmed reconciliation events are immutable; business changes require a new event. */
fun requireInvestmentCashReconciliationLedger(owner:UserId,eventId:String,ledger:CloudRecord,remote:Boolean) {
    require(financeRawUuid(eventId)==eventId)
    requireCashEventRow(owner,ledger,CloudEntity.LEDGER_TRANSACTION,remote)
    val p=ledger.payload
    require(ledger.id==investmentLedgerIdentity(eventId,"cash-reconciliation") && ledger.deletedAt==null &&
        p.keys.none{it.startsWith("_mistia_android_")} && p.financeRawString("settlement_role_raw_value")=="investmentReconciliation" &&
        p.financeRawString("primary_kind_raw_value")=="transfer" && p.financeRawString("transfer_subtype_raw_value")=="internalTransfer" &&
        p.financeRawString("entry_status_raw_value")=="posted" && p.financeRawArchived()==false && !p.financeRawString("title").isNullOrBlank())
    val amount=requireNotNull(p.financeRawLong("amount_minor"));require(amount>0 && p.financeRawLong("destination_amount_minor")==amount &&
        p.financeRawLong("reporting_amount_minor")==amount && p.financeRawLong("reporting_income_minor")==0L && p.financeRawLong("reporting_expense_minor")==0L)
    val currency=requireNotNull(p.financeRawString("reporting_currency_code"))
    require(currency.financeReportingCode()==currency && java.util.Currency.getInstance(currency).defaultFractionDigits>=0 &&
        p.financeRawString("source_currency_code")==currency && p.financeRawString("destination_currency_code")==currency)
    for(key in listOf("source_wallet_id","destination_wallet_id","created_by_user_id","last_modified_by_user_id"))
        require(financeRawUuid(requireNotNull(p.financeRawString(key)))==p.financeRawString(key))
    require(p.financeRawString("source_wallet_id")!=p.financeRawString("destination_wallet_id"))
    for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value",
        "exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at"))require(p[key]==null || p[key]==JsonNull)
    require(p["note"]==null || p["note"]==JsonNull || p.financeRawString("note")!=null)
}
fun requireInvestmentCashReconciliationGroup(owner:UserId,eventId:String,group:InvestmentCashReconciliationGroup,remote:Boolean) {
    requireInvestmentCashReconciliationLedger(owner,eventId,group.ledger,remote)
    val ledger=group.ledger.payload
    val booked=requireNotNull(group.linked.payload.financeRawLong("amount_minor"))
    require(booked>0 && booked<=requireNotNull(ledger.financeRawLong("amount_minor")))
    for((index,row) in listOf(group.holder,group.linked).withIndex()) {
        requireCashEventRow(owner,row,CloudEntity.INVESTMENT_POSTING,remote)
        val p=row.payload;val signed=if(index==0)-booked else booked
        require(row.id==investmentLedgerIdentity(eventId,if(index==0)"holder-cash-posting" else "linked-cash-posting") && row.deletedAt==null &&
            p.financeRawString("event_id")==eventId && p.financeRawString("ledger_transaction_id")==group.ledger.id &&
            p.financeRawString("wallet_id")==ledger.financeRawString(if(index==0)"source_wallet_id" else "destination_wallet_id") &&
            p.financeRawString("role_raw_value")=="cashReconciliation" && p.financeRawString("cash_bucket_raw_value")=="booked" &&
            p.financeRawString("cash_origin_raw_value")=="manual" && p.financeRawLong("amount_minor")==signed && p.financeRawLong("accounting_amount_minor")==signed &&
            p.financeRawString("currency_code")==ledger.financeRawString("reporting_currency_code") && p.financeRawString("accounting_currency_code")==ledger.financeRawString("reporting_currency_code") &&
            cashEventInstant(p.financeRawString("occurred_at"))==cashEventInstant(ledger.financeRawString("occurred_at")))
        for(key in listOf("trade_id","asset_id"))require(p[key]==null || p[key]==kotlinx.serialization.json.JsonNull)
    }
}
fun investmentCashReconciliationGroup(source:InvestmentCashEventPublicationSnapshot):InvestmentCashReconciliationGroup {
    source.requireCoherent();val id=source.eventId
    fun row(entity:CloudEntity,component:String)=requireNotNull(source.rows.singleOrNull{it.entity==entity.table && it.id==investmentLedgerIdentity(id,component)})
    val group=InvestmentCashReconciliationGroup(row(CloudEntity.LEDGER_TRANSACTION,"cash-reconciliation"),row(CloudEntity.INVESTMENT_POSTING,"holder-cash-posting"),row(CloudEntity.INVESTMENT_POSTING,"linked-cash-posting"))
    requireInvestmentCashReconciliationGroup(source.owner,id,group,false)
    require(source.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id}.map{it.id}.toSet()==setOf(group.holder.id,group.linked.id))
    require(source.rows.none{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id})
    return group
}
fun investmentCashReconciliationQueues(source:InvestmentCashEventPublicationSnapshot):List<QueuedMutation> {
    val group=investmentCashReconciliationGroup(source);val keys=group.rows.map{it.entity to it.id}.toSet()
    return source.pending.filter{it.mutation.entity.table to it.mutation.recordId in keys}
}
fun investmentCashReconciliationBusinessMatches(local:CloudRecord,remote:CloudRecord):Boolean =
    local.entity==remote.entity && local.id==remote.id && local.ownerUserId==remote.ownerUserId &&
        remote.syncVersion>=local.syncVersion && cashEventBusiness(local.payload)==cashEventBusiness(remote.payload)

/** Only this complete canonical proof can clear reconciliation financial queues. */
fun planInvestmentCashReconciliationAcknowledgement(source:InvestmentCashEventPublicationSnapshot,candidate:InvestmentCashReconciliationCloudSnapshot):InvestmentCashEventAcknowledgementPlan {
    require(source.owner==candidate.owner && source.eventId==candidate.eventId)
    val local=investmentCashReconciliationGroup(source);val ledger=requireNotNull(candidate.ledger)
    require(candidate.postings.size==2 && candidate.postings.map{it.id}.distinct().size==2)
    val remote=InvestmentCashReconciliationGroup(ledger,requireNotNull(candidate.postings.singleOrNull{it.id==local.holder.id}),requireNotNull(candidate.postings.singleOrNull{it.id==local.linked.id}))
    requireInvestmentCashReconciliationGroup(source.owner,source.eventId,remote,true)
    for((a,b) in local.rows.zip(remote.rows))require(investmentCashReconciliationBusinessMatches(a,b))
    val queues=investmentCashReconciliationQueues(source);require(queues.isNotEmpty())
    val byKey=remote.rows.associateBy{it.entity to it.id}
    return InvestmentCashEventAcknowledgementPlan(remote.rows,queues.map{it to byKey.getValue(it.mutation.entity.table to it.mutation.recordId)},emptyList())
}

/** Closed redacted retry conditions; arbitrary SQL diagnostics never become local errors. */
val INVESTMENT_CASH_RECONCILIATION_RETRY_CODES=setOf("version_conflict","investment_cash_holder_limit","investment_cash_used","investment_cash_ledger_missing","investment_cash_invalid_wallet")
