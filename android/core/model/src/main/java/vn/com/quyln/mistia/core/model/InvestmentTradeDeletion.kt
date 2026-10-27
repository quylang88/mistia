package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

typealias InvestmentTradeDeletionSnapshot=InvestmentTradeCreationSnapshot
data class InvestmentTradeDeletionConsent(val token:String)
data class InvestmentTradeDeletionRequest(val expectedTrade:CloudRecord,val consent:InvestmentTradeDeletionConsent?,val adjustmentTitle:String)
data class InvestmentTradeDeletionReview(val consent:InvestmentTradeDeletionConsent,val comparison:InvestmentFundTimelineComparison,val requiresConfirmation:Boolean)
data class InvestmentTradeDeletionPlan(val trade:CloudRecord,val mutations:List<Pair<CloudRecord,PendingMutation>>,val review:InvestmentTradeDeletionReview)
class InvestmentTradeDeletionConfirmationRequired(val review:InvestmentTradeDeletionReview):IllegalStateException("Trade deletion fund changes require confirmation")

fun planInvestmentTradeDeletion(snapshot:InvestmentTradeDeletionSnapshot,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):InvestmentTradeDeletionPlan {
    fun fail(reason:InvestmentAssetError=InvestmentAssetError.INVALID_ACCOUNTING):Nothing=investmentAssetFail(reason)
    investmentAssetIdentity(snapshot.owner.value);investmentAssetIdentity(deviceId);investmentAssetDate(now)
    val expected=request.expectedTrade
    if(request.adjustmentTitle.isBlank() || !expected.financeRawIdentity(snapshot.owner,CloudEntity.INVESTMENT_TRADE,true) || expected.entity!=CloudEntity.INVESTMENT_TRADE.table || expected.financeRawDeleted(true)!=false)fail(InvestmentAssetError.UNREADABLE_SOURCE)
    if(snapshot.rows.any{row->CloudEntity.fromTable(row.entity)?.let{it in InvestmentTradeCreationSnapshot.entities && row.financeRawIdentity(snapshot.owner,it,true)}!=true} ||
        snapshot.rows.map{it.entity to it.id}.distinct().size!=snapshot.rows.size)fail(InvestmentAssetError.UNREADABLE_SOURCE)
    val current=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==expected.id} ?: fail(InvestmentAssetError.NOT_FOUND)
    if(!expected.matchesVisibleInvestmentTrade(current))fail(InvestmentAssetError.STALE_RECORD)
    val assetId=current.payload.financeRawReference("asset_id").let{if(!it.readable)fail(InvestmentAssetError.UNREADABLE_SOURCE);it.id} ?: fail()
    val asset=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==assetId}?.let(::investmentAssetDecode) ?: fail(InvestmentAssetError.NOT_FOUND)
    val unit=asset.defaultUnitLabel ?: current.payload.financeRawString("unit_label")?.let(InvestmentUnitLabel::normalizedDisplay) ?: fail(InvestmentAssetError.UNIT_REQUIRED)
    val code=investmentAssetCurrency(current.payload.financeRawString("accounting_currency_code").orEmpty()) ?: fail(InvestmentAssetError.INVALID_CURRENCY)
    val assetSource=InvestmentAssetSnapshot(snapshot.owner,snapshot.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentAssetSnapshot.entities})
    fun same(a:CloudRecord,b:CloudRecord)=deletionPayload(a)==deletionPayload(b)
    val baseline=rebuildInvestmentAssetUnitHistory(assetSource,asset,unit,deviceId,now,resolveZeroBuyFunding=false)
    if(baseline.any{row->snapshot.rows.singleOrNull{it.entity==row.entity && it.id==row.id}?.let{same(investmentTradeBaselineExpected(row,it),it)}!=true})fail()
    fun cash(rows:List<CloudRecord>)=InvestmentCashReadSnapshot(snapshot.owner,rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
    val beforeCash=cash(snapshot.rows);val before=investmentFundUsageTimeline(beforeCash,code)
    if(planInvestmentFundEffects(beforeCash,code,before,request.adjustmentTitle,deviceId,now).mutations.isNotEmpty())fail()

    val ledgerRoles=mapOf("funding" to "investmentFunding","capital-return" to "investmentCapitalReturn","profit-loss" to "investmentRealizedProfit")
    val postingRoles=mapOf("funding-posting" to "funding","capital-return-posting" to "capitalReturn","profit-loss-posting" to "realizedProfit","cash-accrual-posting" to "cashAccrual")
    val ledgerIds=ledgerRoles.keys.associateWith{investmentLedgerIdentity(current.id,it)}
    val postingIds=postingRoles.keys.associateWith{investmentLedgerIdentity(current.id,it)}
    val requiredLedger=linkedSetOf<String>();val requiredPostings=linkedSetOf<String>()
    for((key,component) in mapOf("funding_ledger_transaction_id" to "funding","capital_return_ledger_transaction_id" to "capital-return","profit_loss_ledger_transaction_id" to "profit-loss")) {
        val ref=current.payload.financeRawReference(key);if(!ref.readable)fail(InvestmentAssetError.UNREADABLE_SOURCE)
        ref.id?.let{id->
            if(id!=ledgerIds.getValue(component))fail()
            requiredLedger+=id
            requiredPostings+=postingIds.getValue(component+"-posting")
            if(component=="profit-loss")requiredPostings+=postingIds.getValue("cash-accrual-posting")
        }
    }
    val ownedLegs=snapshot.rows.filter{row->row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id in ledgerIds.values}
    val ownedPostings=snapshot.rows.filter{row->
        if(row.entity!=CloudEntity.INVESTMENT_POSTING.table)false else {
            val ref=row.payload.financeRawReference("trade_id");if(!ref.readable)fail(InvestmentAssetError.UNREADABLE_SOURCE)
            ref.id==current.id || row.id in postingIds.values
        }
    }
    if(!ownedLegs.map{it.id}.containsAll(requiredLedger) || !ownedPostings.map{it.id}.containsAll(requiredPostings))fail()
    for(row in ownedLegs) {
        val component=ledgerIds.entries.single{it.value==row.id}.key
        if(row.payload.financeRawString("settlement_role_raw_value")!=ledgerRoles.getValue(component))fail()
    }
    for(row in ownedPostings) {
        val component=postingIds.entries.singleOrNull{it.value==row.id}?.key ?: fail()
        if(row.payload.financeRawReference("trade_id").id!=current.id || row.payload.financeRawString("role_raw_value")!=postingRoles.getValue(component))fail()
    }
    fun review(after:InvestmentFundTimeline):InvestmentTradeDeletionReview {
        val comparison=compareInvestmentFundTimelines(before,after){id->snapshot.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id}.payload.financeRawString("currency_code")!!}
        val token=RecordConflictResolver.semanticFingerprint(buildJsonObject {
            put("operation","deleteInvestmentTrade");put("owner",snapshot.owner.value);put("trade",current.id)
            put("source",JsonArray(snapshot.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)).map{row->buildJsonObject{put("entity",row.entity);put("id",row.id);put("owner",row.ownerUserId);put("fields",deletionPayload(row))}}))
        })
        return InvestmentTradeDeletionReview(InvestmentTradeDeletionConsent(token),comparison,comparison.changes.isNotEmpty())
    }
    when(current.financeRawDeleted(true)) {
        null->fail(InvestmentAssetError.UNREADABLE_SOURCE)
        true->{
            if((ownedLegs+ownedPostings).any{it.financeRawDeleted(true)!=true})fail()
            return InvestmentTradeDeletionPlan(current,emptyList(),review(before))
        }
        false->Unit
    }
    val changes=linkedMapOf<Pair<String,String>,CloudRecord>()
    for(row in listOf(current)+ownedLegs+ownedPostings)if(row.financeRawDeleted(true)==false) {
        val deleted=investmentAssetChanged(row,buildJsonObject{put("deleted_at",now)},deviceId,now).copy(deletedAt=now)
        changes[deleted.entity to deleted.id]=deleted
    }
    fun proposedRows()=snapshot.rows.filterNot{(it.entity to it.id) in changes}+changes.values
    val afterAsset=assetSource.copy(rows=proposedRows().filter{CloudEntity.fromTable(it.entity) in InvestmentAssetSnapshot.entities})
    for(row in rebuildInvestmentAssetUnitHistory(afterAsset,asset,unit,deviceId,now,resolveZeroBuyFunding=false,preserveAccountingErrors=true)) {
        if(snapshot.rows.singleOrNull{it.entity==row.entity && it.id==row.id}?.let{same(row,it)}!=true)changes[row.entity to row.id]=row
    }
    val afterCash=cash(proposedRows());val after=investmentFundUsageTimeline(afterCash,code)
    val effects=planInvestmentFundEffects(afterCash,code,after,request.adjustmentTitle,deviceId,now)
    val review=review(after)
    if((review.requiresConfirmation || request.consent!=null) && request.consent!=review.consent)throw InvestmentTradeDeletionConfirmationRequired(review)
    val writes=changes.values.map{row->row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,snapshot.owner.value,if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,now,row.syncVersion,deviceId)}+effects.mutations
    require(writes.map{it.first.entity to it.first.id}.distinct().size==writes.size)
    return InvestmentTradeDeletionPlan(changes.getValue(current.entity to current.id),writes,review)
}

private val deletionAckKeys=setOf(LOCAL_TRADE_PUBLICATION_PARENTS_KEY,"updated_at","sync_version","last_modified_by_device_id","last_modified_by_user_id")
private val deletionSemanticKeys=setOf("id","user_id","channel_id","asset_id","kind_raw_value","quantity_decimal_string","unit_label","gross_amount_minor","currency_code","accounting_gross_amount_minor","accounting_currency_code","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","funding_wallet_id","funding_wallet_currency_code","funding_wallet_amount_minor","funding_to_accounting_rate_decimal_string","capital_return_wallet_id","capital_return_wallet_currency_code","capital_return_wallet_amount_minor","accounting_to_capital_return_rate_decimal_string","note","occurred_at","created_at","funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id","released_cost_basis_minor","realized_profit_loss_minor","position_quantity_after_decimal_string","position_cost_basis_after_minor")
private fun deletionSemantic(value:JsonElement?,key:String):JsonElement?=if(key in setOf("created_at","occurred_at","deleted_at","archived_at") && value is JsonPrimitive && value.isString)
    runCatching{JsonPrimitive(Instant.parse(value.content).toString())}.getOrDefault(value) else value
private fun deletionPayload(row:CloudRecord)=JsonObject(row.payload.filterKeys{it !in deletionAckKeys}.mapValues{(key,value)->deletionSemantic(value,key)!!})

/** Visible trade intent excludes metadata ACKs and preserves opaque future fields. */
fun CloudRecord.matchesVisibleInvestmentTrade(other:CloudRecord):Boolean =
    entity==CloudEntity.INVESTMENT_TRADE.table && other.entity==entity && ownerUserId==other.ownerUserId && id==other.id &&
        deletionSemanticKeys.all{key->deletionSemantic(payload[key],key)==deletionSemantic(other.payload[key],key)}
