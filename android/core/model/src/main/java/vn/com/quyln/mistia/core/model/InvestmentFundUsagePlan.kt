package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

enum class InvestmentFundUsageError { UNREADABLE_SOURCE, STALE_CONSENT, EVENT_CONFLICT, ARITHMETIC_RANGE, CURRENCY_MISMATCH }
class InvestmentFundUsageException(val reason:InvestmentFundUsageError):IllegalArgumentException(reason.name)
data class InvestmentFundUsageConsent(val ownerUserId:String,val transactionId:String,val proposalToken:String,val sourceToken:String)
data class InvestmentFundUsageReview(val consent:InvestmentFundUsageConsent,val comparison:InvestmentFundTimelineComparison,val requiresConfirmation:Boolean)
class InvestmentFundUsageConfirmationRequired(val review:InvestmentFundUsageReview):IllegalStateException("Investment fund confirmation required")
data class InvestmentFundUsagePlan(val mutations:List<Pair<CloudRecord,PendingMutation>>)

private fun fundUsageFail(reason:InvestmentFundUsageError=InvestmentFundUsageError.UNREADABLE_SOURCE):Nothing=throw InvestmentFundUsageException(reason)
private fun fundUsageVisible(row:CloudRecord):JsonObject=buildJsonObject {
    put("entity",row.entity);put("identity",row.id);put("owner",row.ownerUserId)
    put("deleted",row.deletedAt?.let{runCatching{Instant.parse(it).toString()}.getOrDefault(it)}?.let(::JsonPrimitive) ?: JsonNull)
    put("financial",buildJsonObject{row.payload.filterKeys{it !in setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id")}.forEach{(key,value)->
        put(key,if(key in setOf("created_at","occurred_at","deleted_at","archived_at") && value is JsonPrimitive && value.isString)
            runCatching{JsonPrimitive(Instant.parse(value.content).toString())}.getOrDefault(value) else value)
    }})
}
private fun fundUsageProposalToken(row:CloudRecord)=RecordConflictResolver.semanticFingerprint(fundUsageVisible(row))

fun reviewInvestmentFundUsage(snapshot:InvestmentCashReadSnapshot,accountingCurrency:String,proposed:CloudRecord):InvestmentFundUsageReview {
    try{snapshot.requireScoped()}catch(_:Exception){fundUsageFail()}
    if(!proposed.financeRawIdentity(snapshot.owner,CloudEntity.LEDGER_TRANSACTION,true) || financeRawUuid(proposed.id)!=proposed.id || requiresInvestmentLedgerDomain(proposed.payload))fundUsageFail()
    val existing=snapshot.rows.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==proposed.id}
    val comparison=try{compareInvestmentFundUsageTimeline(snapshot,accountingCurrency,existing?.id,proposed)}catch(error:InvestmentFundTimelineException){fundUsageFail(
        if(error.reason==InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION)InvestmentFundUsageError.CURRENCY_MISMATCH else InvestmentFundUsageError.UNREADABLE_SOURCE)}
    val sourceToken=RecordConflictResolver.semanticFingerprint(buildJsonObject {
        put("owner",snapshot.owner.value)
        put("rows",JsonArray(snapshot.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)).map(::fundUsageVisible)))
    })
    val needs=comparison.changes.isNotEmpty() || comparison.current.usages[proposed.id]?.investmentToUseMinor?.signum()==1 || comparison.proposed.usages[proposed.id]?.investmentToUseMinor?.signum()==1
    return InvestmentFundUsageReview(InvestmentFundUsageConsent(snapshot.owner.value,proposed.id,fundUsageProposalToken(proposed),sourceToken),comparison,needs)
}

/** Only derived effects; the caller must atomically validate/write the primary transaction too. */
fun planInvestmentFundUsage(snapshot:InvestmentCashReadSnapshot,accountingCurrency:String,proposed:CloudRecord,
    consent:InvestmentFundUsageConsent?,adjustmentTitle:String,deviceId:String,now:String):InvestmentFundUsagePlan {
    if(financeRawUuid(deviceId)!=deviceId || runCatching{Instant.parse(now)}.isFailure || adjustmentTitle.isBlank())fundUsageFail()
    val review=reviewInvestmentFundUsage(snapshot,accountingCurrency,proposed)
    val code=investmentAssetCurrency(accountingCurrency) ?: fundUsageFail()
    val transactions=(snapshot.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id!=proposed.id}+proposed).associateBy{it.id}
    val wallets=snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associateBy{it.id}
    val desired=linkedMapOf<Pair<CloudEntity,String>,JsonObject>()
    fun wire(value:BigInteger)=try{value.longValueExact()}catch(_:ArithmeticException){fundUsageFail(InvestmentFundUsageError.ARITHMETIC_RANGE)}
    for(use in review.comparison.proposed.usages.values) {
        val transaction=transactions[use.transactionId] ?: fundUsageFail();val p=transaction.payload
        val occurred=p.financeRawString("occurred_at") ?: fundUsageFail()
        val destination=if(p.financeRawString("primary_kind_raw_value")=="transfer" && p.financeRawString("transfer_subtype_raw_value")=="internalTransfer")
            p.financeRawReference("destination_wallet_id").let{reference->if(!reference.readable)fundUsageFail() else reference.id?.let(wallets::get)}
                ?.takeIf{it.financeRawDeleted(true)==false && it.payload.financeRawArchived()==false && it.payload.financeRawString("kind_raw_value")!="creditCard"} else null
        for((component,amount) in listOf("booked" to use.bookedToUseMinor,"unreconciled" to use.unreconciledToUseMinor)) {
            if(amount.signum()<=0)continue
            fun posting(componentId:String,walletId:String,bucket:String,delta:BigInteger) {
                desired[CloudEntity.INVESTMENT_POSTING to investmentLedgerIdentity(use.transactionId,componentId)]=buildJsonObject {
                    put("event_id",use.transactionId);put("ledger_transaction_id",use.transactionId);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId)
                    put("role_raw_value",if(destination==null)"cashConsumption" else "cashTransfer");put("cash_bucket_raw_value",bucket);put("cash_origin_raw_value","derived")
                    put("amount_minor",wire(delta));put("accounting_amount_minor",wire(delta));put("currency_code",code);put("accounting_currency_code",code);put("occurred_at",occurred);put("deleted_at",JsonNull)
                }
            }
            posting("cash-consumption-"+component,use.walletId,component,amount.negate())
            if(destination!=null)posting("cash-destination-"+component,destination.id,"booked",amount)
        }
        if(use.unreconciledToUseMinor.signum()>0) {
            val system=investmentSystemWalletId(snapshot.owner);val systemWallet=wallets[system] ?: fundUsageFail()
            if(systemWallet.payload.financeRawString("system_purpose_raw_value")!="investmentProfit")fundUsageFail()
            val amount=wire(use.unreconciledToUseMinor)
            desired[CloudEntity.LEDGER_TRANSACTION to investmentLedgerIdentity(use.transactionId,"cash-unreconciled-adjustment")]=buildJsonObject {
                put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted");put("title",adjustmentTitle)
                put("source_wallet_id",system);put("destination_wallet_id",use.walletId);put("amount_minor",amount);put("destination_amount_minor",amount)
                put("source_currency_code",code);put("destination_currency_code",code);put("reporting_currency_code",code);put("reporting_amount_minor",amount)
                put("reporting_expense_minor",0L);put("reporting_income_minor",0L);put("settlement_role_raw_value","investmentReserveUse");put("occurred_at",occurred);put("is_archived",false);put("deleted_at",JsonNull)
                put("created_by_user_id",snapshot.owner.value);put("last_modified_by_user_id",snapshot.owner.value)
                for(key in listOf("debt_intent_raw_value","category_id","settlement_group_id","settlement_obligation_id","archived_at","note",
                    "conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))put(key,JsonNull)
            }
        }
    }
    fun isDerivedPosting(row:CloudRecord)=row.entity==CloudEntity.INVESTMENT_POSTING.table &&
        row.payload.financeRawString("cash_origin_raw_value")=="derived" && row.payload.financeRawString("role_raw_value") in setOf("cashConsumption","cashTransfer")
    val changes=mutableListOf<Pair<CloudRecord,PendingMutation>>()
    fun queue(row:CloudRecord,kind:MutationKind) {
        val entity=CloudEntity.fromTable(row.entity) ?: fundUsageFail()
        changes+=row to PendingMutation(entity,row.id,snapshot.owner.value,kind,row.payload,now,row.syncVersion,deviceId)
    }
    fun validateExisting(row:CloudRecord) {
        try{investmentAssetVersion(row);Instant.parse(row.payload.financeRawString("created_at"));Instant.parse(row.payload.financeRawString("updated_at"))}catch(_:Exception){fundUsageFail()}
        if(row.financeRawDeleted(true)==null)fundUsageFail()
    }
    for((key,fields) in desired) {
        val (entity,id)=key;val current=snapshot.rows.singleOrNull{it.entity==entity.table && it.id==id}
        if(current!=null) {
            validateExisting(current)
            if(entity==CloudEntity.INVESTMENT_POSTING) {
                if(!isDerivedPosting(current) || current.payload.financeRawReference("event_id").id!=fields.financeRawReference("event_id").id ||
                    current.payload.financeRawReference("ledger_transaction_id").id!=fields.financeRawReference("ledger_transaction_id").id ||
                    current.payload.financePresent("trade_id") || current.payload.financePresent("asset_id"))fundUsageFail(InvestmentFundUsageError.EVENT_CONFLICT)
            } else {
                val p=current.payload
                if(p.financeRawString("settlement_role_raw_value")!="investmentReserveUse" || p.financeRawString("primary_kind_raw_value")!="transfer" ||
                    p.financeRawString("transfer_subtype_raw_value")!="internalTransfer" || p.financeRawReference("source_wallet_id").id!=investmentSystemWalletId(snapshot.owner) ||
                    p.financeRawReference("destination_wallet_id").let{!it.readable || it.id==null || it.id !in wallets} ||
                    listOf("debt_intent_raw_value","category_id","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value",
                        "exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key").any(p::financePresent))
                    fundUsageFail(InvestmentFundUsageError.EVENT_CONFLICT)
            }
            val preserved=if(entity==CloudEntity.LEDGER_TRANSACTION && "created_by_user_id" in current.payload)
                JsonObject(fields+("created_by_user_id" to current.payload.getValue("created_by_user_id"))) else fields
            val identical=current.financeRawDeleted(true)==false && current.deletedAt==null && preserved.all{(field,value)->
                if(field=="last_modified_by_user_id")true
                else if(field=="occurred_at")runCatching{Instant.parse(current.payload.financeRawString(field))==Instant.parse(value.jsonPrimitive.content)}.getOrDefault(false)
                else current.payload[field]==value
            }
            if(identical)continue
            val changed=try{investmentAssetChanged(current,preserved,deviceId,now).copy(deletedAt=null)}catch(_:Exception){fundUsageFail()}
            queue(changed,MutationKind.UPSERT)
        } else {
            val created=CloudRecord(entity.table,id,snapshot.owner.value,buildJsonObject {
                put("id",id);put("user_id",snapshot.owner.value);put("created_at",now);put("updated_at",now);put("sync_version",0L);put("last_modified_by_device_id",deviceId);fields.forEach{put(it.key,it.value)}
            },now,null,0)
            queue(created,MutationKind.UPSERT)
        }
    }
    for(row in snapshot.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))) {
        val derived=isDerivedPosting(row) || (row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")
        val entity=CloudEntity.fromTable(row.entity) ?: fundUsageFail()
        if(!derived || (entity to row.id) in desired || row.financeRawDeleted(true)==true)continue
        validateExisting(row)
        val deleted=try{investmentAssetChanged(row,buildJsonObject{put("deleted_at",now)},deviceId,now).copy(deletedAt=now)}catch(_:Exception){fundUsageFail()}
        queue(deleted,MutationKind.DELETE)
    }
    if(consent==null && review.requiresConfirmation)throw InvestmentFundUsageConfirmationRequired(review)
    if(consent!=null && consent!=review.consent) {
        val existing=transactions[proposed.id]?.takeIf{snapshot.rows.any{row->row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id==proposed.id && fundUsageProposalToken(row)==fundUsageProposalToken(proposed)}}
        val complete=changes.isEmpty() && existing!=null && consent.ownerUserId==review.consent.ownerUserId && consent.transactionId==review.consent.transactionId && consent.proposalToken==review.consent.proposalToken
        if(!complete)fundUsageFail(InvestmentFundUsageError.STALE_CONSENT)
    }
    return InvestmentFundUsagePlan(changes)
}
