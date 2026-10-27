package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.Currency
import kotlinx.serialization.json.*

data class InvestmentCashEventAcknowledgementPlan(val imports:List<CloudRecord>,val acknowledgements:List<Pair<QueuedMutation,CloudRecord>>,val absentAcknowledgements:List<QueuedMutation>)

internal fun cashEventInstant(value:String?):Instant {
    val i=Instant.parse(requireNotNull(value));return Instant.ofEpochSecond(i.epochSecond,Math.rint(i.nano.toDouble()/1000).toLong()*1000)
}
internal fun cashEventBusiness(payload:JsonObject):JsonObject=JsonObject((payload-setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id",LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY)).mapValues{(key,value)->
    if(key in setOf("created_at","occurred_at","deleted_at") && value!=JsonNull)JsonPrimitive(cashEventInstant(payload.financeRawString(key)).toString()) else value
})
internal fun requireCashEventRow(owner:UserId,row:CloudRecord,entity:CloudEntity,remote:Boolean) {
    require(financeRawUuid(owner.value)==owner.value && financeRawUuid(row.id)==row.id && row.entity==entity.table &&
        row.financeRawIdentity(owner,entity,true) && row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==owner.value &&
        row.syncVersion>=(if(remote)1 else 0) && row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==row.payload.financeRawString("updated_at") &&
        row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at"))
    require(row.payload.keys.none{it.startsWith("_mistia_android_") && (remote || entity!=CloudEntity.LEDGER_TRANSACTION || it!=LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY)})
    if(!remote && entity==CloudEntity.LEDGER_TRANSACTION)localCashEventPublicationParents(row)
    for(key in listOf("created_at","updated_at","occurred_at"))cashEventInstant(row.payload.financeRawString(key))
    row.deletedAt?.let(::cashEventInstant)
    val actor=row.payload["last_modified_by_device_id"]
    if(actor!=null && actor!=JsonNull)require(financeRawUuid(requireNotNull(row.payload.financeRawString("last_modified_by_device_id")))==row.payload.financeRawString("last_modified_by_device_id"))
}
private fun cashEventCurrency(value:String?):String {
    val c=requireNotNull(value);require(c.financeReportingCode()==c && Currency.getInstance(c).defaultFractionDigits>=0);return c
}
internal fun requireCashEventLedger(owner:UserId,id:String,row:CloudRecord,remote:Boolean) {
    requireCashEventRow(owner,row,CloudEntity.LEDGER_TRANSACTION,remote);val p=row.payload
    require(row.id==id && p.financeRawString("settlement_role_raw_value") in setOf("investmentCashDeposit","investmentCashWithdrawal") &&
        p.financeRawString("primary_kind_raw_value")=="transfer" && p.financeRawString("transfer_subtype_raw_value")=="internalTransfer" &&
        p.financeRawString("entry_status_raw_value")=="posted" && p.financeRawArchived()==false && !p.financeRawString("title").isNullOrBlank())
    val amount=requireNotNull(p.financeRawLong("amount_minor"));require(amount>0 && p.financeRawLong("destination_amount_minor")==amount &&
        p.financeRawLong("reporting_amount_minor")==amount && p.financeRawLong("reporting_expense_minor")==0L && p.financeRawLong("reporting_income_minor")==0L)
    val currency=cashEventCurrency(p.financeRawString("source_currency_code"))
    require(cashEventCurrency(p.financeRawString("destination_currency_code"))==currency && cashEventCurrency(p.financeRawString("reporting_currency_code"))==currency)
    for(key in listOf("source_wallet_id","destination_wallet_id","created_by_user_id","last_modified_by_user_id"))require(financeRawUuid(requireNotNull(p.financeRawString(key)))==p.financeRawString(key))
    for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at"))
        require(p[key]==null || p[key]==JsonNull)
    require(p["note"]==null || p["note"]==JsonNull || p.financeRawString("note")!=null)
}
internal fun requireCashEventPosting(owner:UserId,id:String,row:CloudRecord,remote:Boolean) {
    requireCashEventRow(owner,row,CloudEntity.INVESTMENT_POSTING,remote);val p=row.payload
    require(p.financeRawString("event_id")==id && p.financeRawString("ledger_transaction_id")==id)
    for(key in listOf("trade_id","asset_id"))require(p[key]==null || p[key]==JsonNull)
    require(financeRawUuid(requireNotNull(p.financeRawString("wallet_id")))==p.financeRawString("wallet_id") &&
        p.financeRawString("role_raw_value") in setOf("cashTransfer","cashAccrual","cashReconciliation","cashConsumption","cashCorrection") &&
        p.financeRawString("cash_bucket_raw_value") in setOf("booked","unreconciled") && p.financeRawString("cash_origin_raw_value") in setOf("manual","derived","inferred"))
    require(p.financeRawLong("amount_minor")!=null && p.financeRawLong("accounting_amount_minor")!=null)
    val currency=cashEventCurrency(p.financeRawString("currency_code"));val accounting=cashEventCurrency(p.financeRawString("accounting_currency_code"))
    if(currency==accounting)require(p.financeRawLong("amount_minor")==p.financeRawLong("accounting_amount_minor"))
}
internal fun requireCashEventCanonical(owner:UserId,id:String,ledger:CloudRecord,posting:CloudRecord,remote:Boolean) {
    requireCashEventLedger(owner,id,ledger,remote);requireCashEventPosting(owner,id,posting,remote)
    val t=ledger.payload;val p=posting.payload;val deposit=t.financeRawString("settlement_role_raw_value")=="investmentCashDeposit"
    val amount=requireNotNull(t.financeRawLong("amount_minor"));val signed=if(deposit)amount else -amount;val currency=t.financeRawString("reporting_currency_code")
    require(posting.id==investmentLedgerIdentity(id,"cash-transfer-posting") && p.financeRawString("role_raw_value")=="cashTransfer" &&
        p.financeRawString("cash_bucket_raw_value")=="booked" && p.financeRawString("cash_origin_raw_value")=="manual" &&
        p.financeRawString("wallet_id")==t.financeRawString(if(deposit)"destination_wallet_id" else "source_wallet_id") &&
        p.financeRawLong("amount_minor")==signed && p.financeRawLong("accounting_amount_minor")==signed &&
        p.financeRawString("currency_code")==currency && p.financeRawString("accounting_currency_code")==currency &&
        cashEventInstant(p.financeRawString("occurred_at"))==cashEventInstant(t.financeRawString("occurred_at")))
    require((ledger.deletedAt==null)==(posting.deletedAt==null))
}

/** Recompute this plan inside the exact-generation Room transaction; it grants no generic financial authority. */
fun planInvestmentCashEventResultAcknowledgement(source:InvestmentCashEventPublicationSnapshot,candidate:InvestmentCashEventCloudSnapshot):InvestmentCashEventAcknowledgementPlan {
    source.requireCoherent();require(source.owner==candidate.owner && source.eventId==candidate.eventId)
    val owner=source.owner;val id=source.eventId;val q=requireNotNull(source.requestedQueue);require(source.matches(q))
    val local=requireNotNull(source.requestedRecord);val canonical=investmentLedgerIdentity(id,"cash-transfer-posting")
    requireCashEventLedger(owner,id,local,false)
    val localPostings=source.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && (it.id==canonical || it.payload.financeRawReference("event_id").id==id)}
    val byLocal=localPostings.associateBy{it.id};val localCanonical=requireNotNull(byLocal[canonical])
    requireCashEventCanonical(owner,id,local,localCanonical,false)
    localPostings.forEach{requireCashEventPosting(owner,id,it,false)}
    val relevantKeys=localPostings.map{it.entity to it.id}.toSet()+(local.entity to local.id)
    val queues=source.pending.filter{it.mutation.entity.table to it.mutation.recordId in relevantKeys}
    val remote=candidate.transaction
    if(remote==null) {
        require(candidate.postings.isEmpty() && local.deletedAt!=null && queues.size==localPostings.size+1 &&
            queues.all{it.mutation.kind==MutationKind.DELETE && it.mutation.baseVersion==0L && !it.remoteIdentityObserved})
        return InvestmentCashEventAcknowledgementPlan(emptyList(),emptyList(),queues)
    }
    requireCashEventLedger(owner,id,remote,true)
    require(remote.syncVersion>=local.syncVersion)
    val posts=candidate.postings;require(posts.size<=10000 && posts.map{it.id}.distinct().size==posts.size)
    val sourceByKey=source.rows.associateBy{it.entity to it.id}
    posts.forEach{row->
        requireCashEventPosting(owner,id,row,true)
        sourceByKey[row.entity to row.id]?.let{known->
            require(known.payload.financeRawString("event_id")==id && known.payload.financeRawString("ledger_transaction_id")==id)
        }
    }
    val byRemote=posts.associateBy{it.id};val remoteCanonical=requireNotNull(byRemote[canonical])
    requireCashEventCanonical(owner,id,remote,remoteCanonical,true)
    require(cashEventInstant(local.payload.financeRawString("created_at"))==cashEventInstant(remote.payload.financeRawString("created_at")))
    if(candidate.remoteIntentWinner) {
        require(resolveInvestmentCashEventPublication(local,remote,q.mutation.deviceId).winner==RecordConflictWinner.REMOTE)
        require(remoteCanonical.syncVersion>=localCanonical.syncVersion)
        val created=if(localCanonical.syncVersion==0L)local.payload.financeRawString("created_at") else localCanonical.payload.financeRawString("created_at")
        require(cashEventInstant(remoteCanonical.payload.financeRawString("created_at"))==cashEventInstant(created))
        if(remote.deletedAt!=null)require(posts.all{it.deletedAt!=null})
        val imports=linkedMapOf((remote.entity to remote.id) to remote,(remoteCanonical.entity to canonical) to remoteCanonical)
        val ack=mutableListOf(q to remote)
        queues.singleOrNull{it.mutation.entity==CloudEntity.INVESTMENT_POSTING && it.mutation.recordId==canonical}?.let{ack+=it to remoteCanonical}
        for(old in localPostings.filter{it.id!=canonical})require(byRemote[old.id]!=null)
        for(row in posts.filter{it.id!=canonical}) {
            val key=row.entity to row.id;val old=byLocal[row.id]
            if(key in source.dirtyKeys) {
                // A different allocation intent is outside the selected ledger/canonical winner.
                require(remote.deletedAt==null)
            } else {
                require(old==null || row.syncVersion>=old.syncVersion && cashEventInstant(row.payload.financeRawString("created_at"))==cashEventInstant(old.payload.financeRawString("created_at")))
                imports[key]=row
            }
        }
        return InvestmentCashEventAcknowledgementPlan(imports.values.toList(),ack,emptyList())
    }
    require((local.deletedAt==null)==(remote.deletedAt==null))
    val imports=linkedMapOf<Pair<String,String>,CloudRecord>();val ack=mutableListOf<Pair<QueuedMutation,CloudRecord>>();val absent=mutableListOf<QueuedMutation>()
    imports[remote.entity to remote.id]=remote;ack+=q to remote
    if(local.deletedAt==null) {
        require(cashEventBusiness(local.payload)==cashEventBusiness(remote.payload))
        require(remoteCanonical.syncVersion>=localCanonical.syncVersion)
        val expected=if(localCanonical.syncVersion==0L)JsonObject(localCanonical.payload+("created_at" to requireNotNull(local.payload["created_at"]))) else localCanonical.payload
        require(cashEventBusiness(expected)==cashEventBusiness(remoteCanonical.payload))
        val canonicalQueue=queues.singleOrNull{it.mutation.recordId==canonical && it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        if(canonicalQueue!=null)ack+=canonicalQueue to remoteCanonical
        imports[remoteCanonical.entity to canonical]=remoteCanonical
        for(old in localPostings.filter{it.id!=canonical})require(byRemote[old.id]!=null)
        for(row in posts.filter{it.id!=canonical}) {
            val key=row.entity to row.id;val old=byLocal[row.id]
            if(key !in source.dirtyKeys) {
                require(old==null || row.syncVersion>=old.syncVersion)
                imports[key]=row
            }
        }
    } else {
        require(posts.all{it.deletedAt!=null})
        require(queues.all{it.mutation.kind==MutationKind.DELETE})
        for(old in localPostings) {
            val current=byRemote[old.id];val queued=queues.singleOrNull{it.mutation.recordId==old.id && it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
            if(current==null) {
                require(queued!=null && queued.mutation.baseVersion==0L && !queued.remoteIdentityObserved && queued.mutation.kind==MutationKind.DELETE)
                absent+=queued
            } else {
                val created=if(old.id==canonical && old.syncVersion==0L)local.payload.financeRawString("created_at") else old.payload.financeRawString("created_at")
                require(current.syncVersion>=old.syncVersion && cashEventInstant(current.payload.financeRawString("created_at"))==cashEventInstant(created))
                if(queued!=null)ack+=queued to current
            }
        }
        for(row in posts)imports[row.entity to row.id]=row
    }
    return InvestmentCashEventAcknowledgementPlan(imports.values.toList(),ack,absent)
}
