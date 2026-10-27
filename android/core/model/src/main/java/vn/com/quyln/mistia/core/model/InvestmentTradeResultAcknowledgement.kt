package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

/** Complete owner-scoped read candidate; rows remain untrusted until the result proof succeeds. */
data class InvestmentTradeCloudSnapshot(val owner:UserId,val affectedAssetIds:Set<String>,val rows:List<CloudRecord>,val remoteIntentWinners:Set<String> = emptySet())
data class InvestmentTradeAcknowledgementPlan(
    val acknowledgements:List<Pair<QueuedMutation,CloudRecord>>,val absentAcknowledgements:List<QueuedMutation>,val imports:List<CloudRecord>,
)

/** Intent includes opaque fields; FIFO, financial references and publication stamps are separate authority. */
fun investmentTradeIntentFingerprint(payload:JsonObject):String {
    val values=(investmentTradePayloadForCloud(payload)-setOf("id","user_id","updated_at","sync_version","last_modified_by_device_id")).toMutableMap()
    val deleted=values.remove("deleted_at")
    for(key in TRADE_OPTIONAL_INTENT_KEYS)if(key !in values)values[key]=JsonNull
    val normalized=values.mapValues{(key,value)->normalizeTradePublicationValue(value,key)}
    return RecordConflictResolver.semanticFingerprint(buildJsonObject{put("intent",JsonObject(normalized));put("is_deleted",deleted!=null && deleted!=JsonNull)})
}

/** A deletion retires the same immutable trade even when earlier local business edits were never published. */
fun investmentTradePublicationIntentsMatch(local:CloudRecord,remote:CloudRecord):Boolean {
    if(local.entity!=CloudEntity.INVESTMENT_TRADE.table || remote.entity!=local.entity || local.id!=remote.id || local.ownerUserId!=remote.ownerUserId)return false
    if(local.deletedAt!=null && remote.deletedAt!=null) {
        if(local.payload.financeRawString("created_at")==null || remote.payload.financeRawString("created_at")==null)return false
        return normalizeTradePublicationValue(local.payload.getValue("created_at"),"created_at")==normalizeTradePublicationValue(remote.payload.getValue("created_at"),"created_at")
    }
    return investmentTradeIntentFingerprint(local.payload)==investmentTradeIntentFingerprint(remote.payload)
}

fun planInvestmentTradeResultAcknowledgement(
    source:InvestmentTradePublicationSnapshot,candidate:InvestmentTradeCloudSnapshot,deviceId:String,now:String,
):InvestmentTradeAcknowledgementPlan {
    fun fail(reason:InvestmentTradeResultError=InvestmentTradeResultError.INVALID_RESULT):Nothing=throw InvestmentTradeResultException(reason)
    fun incomplete():Nothing=fail(InvestmentTradeResultError.INCOMPLETE_RESULT)
    source.requireCoherent()
    if(candidate.owner!=source.owner || candidate.rows.map{it.entity to it.id}.distinct().size!=candidate.rows.size)fail()
    val allowed=setOf(CloudEntity.INVESTMENT_TRADE,CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING)
    for(raw in candidate.rows) {
        val entity=CloudEntity.fromTable(raw.entity) ?: fail()
        if(entity !in allowed || financeRawUuid(raw.id)!=raw.id || !raw.financeRawIdentity(source.owner,entity,true) ||
            raw.payload.financeRawString("id")!=raw.id || raw.payload.financeRawString("user_id")!=source.owner.value ||
            raw.syncVersion<0 || raw.payload.financeRawLong("sync_version")!=raw.syncVersion ||
            raw.updatedAt!=raw.payload.financeRawString("updated_at") || raw.financeRawDeleted(true)==null || raw.deletedAt!=raw.payload.financeRawString("deleted_at"))fail()
        for(key in listOf("created_at","updated_at","occurred_at"))Instant.parse(raw.payload.financeRawString(key) ?: fail())
        for(key in listOf("last_modified_by_device_id","created_by_user_id","last_modified_by_user_id")) {
            val reference=raw.payload.financeRawReference(key)
            if(!reference.readable)fail()
        }
    }
    val remoteByKey=candidate.rows.associateBy{it.entity to it.id}
    val sourceByKey=source.rows.associateBy{it.entity to it.id}
    val queues=source.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    for(id in candidate.remoteIntentWinners) {
        val key=CloudEntity.INVESTMENT_TRADE.table to id
        val q=queues[key] ?: fail()
        val local=sourceByKey[key] ?: fail()
        val remote=remoteByKey[key] ?: fail()
        if(resolveInvestmentTradePublication(local,remote,q.mutation.deviceId).winner!=RecordConflictWinner.REMOTE)incomplete()
    }
    val remoteTrades=candidate.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}
    val related=linkedMapOf<String,CloudRecord>()
    for(raw in source.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}) {
        val asset=raw.payload.financeRawReference("asset_id")
        if(!asset.readable || asset.id==null)fail(InvestmentTradeResultError.UNREADABLE_SOURCE)
        if(asset.id in candidate.affectedAssetIds)related[raw.id]=raw
    }
    for(raw in remoteTrades) {
        requireInvestmentTradeForPublication(source.owner,raw,forWrite=false,allowLocalEvidence=false)
        if(raw.payload.financeRawString("asset_id") !in candidate.affectedAssetIds)fail()
        related[raw.id]=raw
    }
    if(related.isEmpty())incomplete()
    // Rebuilt values never prove that a different queued user proposal was accepted.
    for(q in source.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_TRADE && it.mutation.recordId in related}) {
        val key=q.mutation.entity.table to q.mutation.recordId
        val current=sourceByKey[key] ?: fail(InvestmentTradeResultError.UNREADABLE_SOURCE)
        requireInvestmentTradeForPublication(source.owner,current,forWrite=false)
        val remote=remoteByKey[key]
        if(remote==null) {
            if(current.deletedAt==null || q.mutation.baseVersion!=0L || q.remoteIdentityObserved)incomplete()
        } else if(!investmentTradePublicationIntentsMatch(current,remote) && current.id !in candidate.remoteIntentWinners)incomplete()
    }
    val projected=projectInvestmentTradePublicationResult(source,remoteTrades,candidate.affectedAssetIds,deviceId,now)
    val expectedByKey=projected.associateBy{it.entity to it.id}
    data class Identity(val tradeId:String,val component:String,val role:String)
    val identities=linkedMapOf<Pair<String,String>,Identity>()
    for(trade in related.values)for((entity,roles) in listOf(CloudEntity.LEDGER_TRANSACTION to TRADE_LEDGER_ROLES,CloudEntity.INVESTMENT_POSTING to TRADE_POSTING_ROLES))
        for((component,role) in roles) {
            val key=entity.table to investmentLedgerIdentity(trade.id,component)
            if(identities.put(key,Identity(trade.id,component,role))!=null)fail()
        }
    fun financialIdentity(raw:CloudRecord,isRemote:Boolean) {
        val identity=identities[raw.entity to raw.id] ?: fail()
        val ledger=raw.entity==CloudEntity.LEDGER_TRANSACTION.table
        val roleKey=if(ledger)"settlement_role_raw_value" else "role_raw_value"
        if(raw.payload.financeRawString(roleKey)!=identity.role)fail()
        if(ledger) {
            val amount=raw.payload.financeRawLong("amount_minor") ?: fail()
            if(amount<0 || raw.payload.financeRawString("primary_kind_raw_value") !in setOf("income","expense"))fail()
            if(isRemote) {
                if(raw.payload.financeRawString("title")==null || raw.payload.financeRawString("entry_status_raw_value")!="posted")fail()
                for(key in listOf("reporting_amount_minor","reporting_expense_minor","reporting_income_minor"))
                    if(raw.payload.financeRawLong(key)?.let{it>=0}!=true)fail()
                for(key in listOf("source_wallet_id","destination_wallet_id","category_id","settlement_group_id","settlement_obligation_id")) {
                    val ref=raw.payload.financeRawReference(key)
                    if(!ref.readable)fail()
                    if(key in setOf("source_wallet_id","destination_wallet_id") && ref.id!=null && CloudEntity.LEDGER_WALLET.table to ref.id !in sourceByKey)fail()
                }
            }
            for(key in listOf("source_currency_code","reporting_currency_code"))
                if(raw.payload.financeRawString(key)?.let(::investmentAssetCurrency)==null)fail()
        } else {
            val ledgerComponent=if(identity.component=="cash-accrual-posting")"profit-loss" else identity.component.removeSuffix("-posting")
            for((key,id) in listOf("event_id" to identity.tradeId,"trade_id" to identity.tradeId,"ledger_transaction_id" to investmentLedgerIdentity(identity.tradeId,ledgerComponent)))
                if(raw.payload.financeRawReference(key).let{!it.readable || it.id!=id})fail()
            if(raw.payload.financeRawLong("amount_minor")==null || raw.payload.financeRawLong("accounting_amount_minor")==null)fail()
            if(isRemote) {
                val wallet=raw.payload.financeRawReference("wallet_id")
                if(!wallet.readable || wallet.id==null || CloudEntity.LEDGER_WALLET.table to wallet.id !in sourceByKey)fail()
            }
            for(key in listOf("currency_code","accounting_currency_code"))if(raw.payload.financeRawString(key)?.let(::investmentAssetCurrency)==null)fail()
            val asset=raw.payload.financeRawReference("asset_id")
            if(!asset.readable || asset.id !in candidate.affectedAssetIds)fail()
            if(isRemote && asset.id!=related.getValue(identity.tradeId).payload.financeRawReference("asset_id").id)fail()
        }
    }
    for((key,_) in identities)sourceByKey[key]?.let{financialIdentity(it,false)}
    for(raw in candidate.rows.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table}) {
        financialIdentity(raw,true)
        val expected=expectedByKey[raw.entity to raw.id]
        if(raw.deletedAt==null) {
            if(expected==null || expected.deletedAt!=null)fail()
            for((key,value) in expected.payload)if(key !in FINANCIAL_ACK_METADATA &&
                normalizeTradePublicationValue(value,key)!=normalizeTradePublicationValue(raw.payload[key] ?: JsonNull,key))fail()
        } else if(expected?.deletedAt==null && expected!=null)fail()
    }
    for(expected in projected.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table && it.deletedAt==null})
        if(remoteByKey[expected.entity to expected.id]?.deletedAt!=null || remoteByKey[expected.entity to expected.id]==null)incomplete()
    val acknowledged=mutableListOf<Pair<QueuedMutation,CloudRecord>>()
    val absent=mutableListOf<QueuedMutation>()
    for((key,q) in queues) {
        val inScope=q.mutation.entity==CloudEntity.INVESTMENT_TRADE && q.mutation.recordId in related || key in identities
        if(!inScope)continue
        val local=sourceByKey[key] ?: fail(InvestmentTradeResultError.UNREADABLE_SOURCE)
        val remote=remoteByKey[key]
        if(remote==null) {
            if(local.deletedAt==null || q.mutation.baseVersion!=0L || q.remoteIdentityObserved)incomplete()
            absent+=q
        } else {
            val remoteWinner=if(q.mutation.entity==CloudEntity.INVESTMENT_TRADE)q.mutation.recordId in candidate.remoteIntentWinners
                else identities[key]?.tradeId in candidate.remoteIntentWinners
            if((local.deletedAt==null)!=(remote.deletedAt==null) && !remoteWinner)incomplete()
            acknowledged+=q to remote
        }
    }
    val consumed=(acknowledged.map{it.first}+absent).map{it.mutation.entity.table to it.mutation.recordId}.toSet()
    if(candidate.rows.any{it.entity to it.id in source.dirtyKeys && it.entity to it.id !in consumed})incomplete()
    return InvestmentTradeAcknowledgementPlan(acknowledged,absent,candidate.rows)
}

private val TRADE_OPTIONAL_INTENT_KEYS=setOf("unit_label","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date",
    "funding_wallet_id","capital_return_wallet_id","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string","note")
private val FINANCIAL_ACK_METADATA=setOf("id","user_id","created_at","updated_at","deleted_at","sync_version","last_modified_by_device_id","created_by_user_id","last_modified_by_user_id")
private val TRADE_LEDGER_ROLES=mapOf("funding" to "investmentFunding","capital-return" to "investmentCapitalReturn","profit-loss" to "investmentRealizedProfit")
private val TRADE_POSTING_ROLES=mapOf("funding-posting" to "funding","capital-return-posting" to "capitalReturn","profit-loss-posting" to "realizedProfit","cash-accrual-posting" to "cashAccrual")
private fun normalizeTradePublicationValue(value:JsonElement,key:String):JsonElement {
    if(value==JsonNull)return value
    val text=(value as? JsonPrimitive)?.takeIf{it.isString}?.content
    return when {
        key in setOf("created_at","occurred_at") && text!=null->{
            val instant=Instant.parse(text)
            JsonPrimitive(Instant.ofEpochSecond(instant.epochSecond,Math.rint(instant.nano.toDouble()/1000).toLong()*1000).toString())
        }
        key in setOf("quantity_decimal_string","position_quantity_after_decimal_string","exchange_rate_decimal_string","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string") && text!=null->
            JsonPrimitive(text.toBigDecimal().stripTrailingZeros().toPlainString())
        key=="unit_label"->InvestmentUnitLabel.normalizedDisplay(text)?.let(::JsonPrimitive) ?: JsonNull
        key=="note"->text?.trim()?.takeUnless{it.isEmpty()}?.let(::JsonPrimitive) ?: JsonNull
        (key=="currency_code" || key.endsWith("_currency_code")) && text!=null->JsonPrimitive(requireNotNull(investmentAssetCurrency(text)))
        key.endsWith("_id") && text!=null->financeRawUuid(text)?.let(::JsonPrimitive) ?: value
        else->value
    }
}
