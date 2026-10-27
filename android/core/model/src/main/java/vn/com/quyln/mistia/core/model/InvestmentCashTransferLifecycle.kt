package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import kotlinx.serialization.json.*

/** Compact visible event token; excludes ACK/device/version and unknown server metadata. */
data class InvestmentCashTransferEvent(val draft:InvestmentCashTransferDraft,val title:String,val ledger:JsonObject,val postings:List<JsonObject>)
data class InvestmentCashTransferLifecycleRead(val event:InvestmentCashTransferEvent,val baseline:InvestmentCashTransferReadView)
sealed interface InvestmentCashTransferLifecycleRequest {
    data class Save(val expected:InvestmentCashTransferEvent,val transfer:InvestmentCashTransferRequest):InvestmentCashTransferLifecycleRequest
    data class Delete(val expected:InvestmentCashTransferEvent,val review:InvestmentCashTransferRequest):InvestmentCashTransferLifecycleRequest
}
fun readInvestmentCashTransferLifecycle(snapshot:InvestmentCashReadSnapshot,eventId:String,walletId:String?=null,requestedMinor:Long?=null):InvestmentCashTransferLifecycleRead {
    val event=cashTransferEvent(snapshot,eventId)
    return InvestmentCashTransferLifecycleRead(event,readInvestmentCashTransfer(withoutCashTransferEvent(snapshot,eventId),event.draft.direction,walletId ?: event.draft.walletId,requestedMinor ?: event.draft.amountMinor))
}
fun planInvestmentCashTransferLifecycle(snapshot:InvestmentCashReadSnapshot,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):InvestmentCashTransferPlan {
    snapshot.requireScoped();lifecycleIdentity(deviceId);lifecycleDate(now)
    val expected=when(request){is InvestmentCashTransferLifecycleRequest.Save->request.expected;is InvestmentCashTransferLifecycleRequest.Delete->request.expected}
    val review=when(request){is InvestmentCashTransferLifecycleRequest.Save->request.transfer;is InvestmentCashTransferLifecycleRequest.Delete->request.review}
    val original=expected.draft;val draft=review.draft
    if(draft.id!=original.id || lifecycleDate(draft.createdAt)!=lifecycleDate(original.createdAt))lifecycleFail(InvestmentCashTransferError.INVALID_INPUT)
    if(draft.direction!=original.direction)lifecycleFail(InvestmentCashTransferError.DIRECTION_LOCKED)
    val current=cashTransferEvent(snapshot,original.id,expected.postings.map{it.lifecycleText("id")}.toSet())
    val ledgerDeleted=current.ledger["deleted_at"]!=JsonNull
    val anyPostingDeleted=current.postings.any{it["deleted_at"]!=JsonNull}
    when(request) {
        is InvestmentCashTransferLifecycleRequest.Save -> {
            if(ledgerDeleted || anyPostingDeleted)lifecycleFail(InvestmentCashTransferError.EVENT_CONFLICT)
            // Swift updates the canonical posting and retains any other cash rows of this event.
            // A retry also proves those retained rows still match the original visible event.
            val canonical=investmentLedgerIdentity(original.id,"cash-transfer-posting")
            fun retained(event:InvestmentCashTransferEvent)=event.postings.filter{it.lifecycleText("id")!=canonical}
            val canonicalSnapshot=snapshot.copy(rows=snapshot.rows.filterNot{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id!=canonical && it.payload.lifecycleReference("event_id")==original.id})
            if(retained(current)==retained(expected) && runCatching{planInvestmentCashTransfer(canonicalSnapshot,review,deviceId,now).mutations.isEmpty()}.getOrDefault(false))return InvestmentCashTransferPlan(emptyList())
            if(current!=expected)lifecycleFail(InvestmentCashTransferError.STALE_RECORD)
            val fresh=planInvestmentCashTransfer(withoutCashTransferEvent(snapshot,original.id),review,deviceId,now)
            val mutations=fresh.mutations.map{(replacement,_) ->
                val raw=snapshot.rows.single{it.entity==replacement.entity && it.id==replacement.id}
                val fields=JsonObject(replacement.payload.filterKeys{it !in setOf("id","user_id","created_at","updated_at","sync_version","last_modified_by_device_id","created_by_user_id")})
                val changed=investmentAssetChanged(raw,fields,deviceId,now).let{row->
                    if(raw.entity==CloudEntity.LEDGER_TRANSACTION.table)row.withPriorCashEventPublication(raw) else row
                }
                changed to PendingMutation(requireNotNull(CloudEntity.fromTable(changed.entity)),changed.id,snapshot.owner.value,MutationKind.UPSERT,changed.payload,now,changed.syncVersion,deviceId)
            }
            return InvestmentCashTransferPlan(mutations)
        }
        is InvestmentCashTransferLifecycleRequest.Delete -> {
            if(draft!=original)lifecycleFail(InvestmentCashTransferError.INVALID_INPUT)
            fun visible(event:InvestmentCashTransferEvent)=event.copy(ledger=JsonObject(event.ledger-("deleted_at")),postings=event.postings.map{JsonObject(it-("deleted_at"))})
            if(visible(current)!=visible(expected))lifecycleFail(InvestmentCashTransferError.STALE_RECORD)
            if(ledgerDeleted && current.postings.all{it["deleted_at"]!=JsonNull})return InvestmentCashTransferPlan(emptyList())
            if(ledgerDeleted || anyPostingDeleted)lifecycleFail(InvestmentCashTransferError.EVENT_CONFLICT)
            val baseline=readInvestmentCashTransfer(withoutCashTransferEvent(snapshot,original.id),draft.direction,draft.walletId,draft.amountMinor)
            if(!review.expectedSystem.matchesVisibleInvestmentWallet(baseline.system) || !review.expectedLinked.matchesVisibleInvestmentWallet(baseline.linked) ||
                !review.expectedSelected.matchesVisibleInvestmentWallet(baseline.selected) || review.expectedPreview!=baseline.preview)lifecycleFail(InvestmentCashTransferError.STALE_RECORD)
            val preview=baseline.preview
            when(draft.direction) {
                InvestmentCashTransferDirection.DEPOSIT -> if(preview.availableInvestmentMinor.signum()<0 || preview.linkedBookedMinor.signum()<0)lifecycleFail(InvestmentCashTransferError.HAS_DEPENDENTS)
                InvestmentCashTransferDirection.WITHDRAWAL -> if(preview.availableInvestmentMinor>preview.realizedProfitMinor.max(BigInteger.ZERO))lifecycleFail(InvestmentCashTransferError.HAS_DEPENDENTS)
            }
            val ids=current.postings.map{it.lifecycleText("id")}.toSet()
            return InvestmentCashTransferPlan(snapshot.rows.filter{(it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==original.id) || (it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id in ids)}.map{raw ->
                val changed=investmentAssetChanged(raw,buildJsonObject{put("deleted_at",now)},deviceId,now).copy(deletedAt=now).let{row->
                    if(raw.entity==CloudEntity.LEDGER_TRANSACTION.table)row.withPriorCashEventPublication(raw) else row
                }
                changed to PendingMutation(requireNotNull(CloudEntity.fromTable(changed.entity)),changed.id,snapshot.owner.value,MutationKind.DELETE,changed.payload,now,changed.syncVersion,deviceId)
            })
        }
    }
}

private fun lifecycleFail(reason:InvestmentCashTransferError=InvestmentCashTransferError.UNREADABLE_SOURCE):Nothing=throw InvestmentCashTransferException(reason)
private fun lifecycleIdentity(value:String)=financeRawUuid(value)?.takeIf{it==value} ?: lifecycleFail()
private fun lifecycleDate(value:String)=runCatching{Instant.parse(value).toString()}.getOrElse{lifecycleFail()}
private fun JsonObject.lifecycleText(key:String)=financeRawString(key) ?: lifecycleFail()
private fun JsonObject.lifecycleOptional(key:String):String?=if(this[key]==null || this[key]==JsonNull)null else lifecycleText(key)
private fun JsonObject.lifecycleReference(key:String)=financeRawReference(key).let{if(!it.readable)lifecycleFail() else it.id}
private fun JsonObject.lifecycleMinor(key:String)=financeRawLong(key) ?: lifecycleFail()
private fun withoutCashTransferEvent(snapshot:InvestmentCashReadSnapshot,eventId:String):InvestmentCashReadSnapshot=snapshot.copy(rows=snapshot.rows.filterNot{row ->
    (row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id==eventId) ||
        (row.entity==CloudEntity.INVESTMENT_POSTING.table && (row.id==investmentLedgerIdentity(eventId,"cash-transfer-posting") || row.payload.lifecycleReference("event_id")==eventId))
})
private fun cashTransferEvent(snapshot:InvestmentCashReadSnapshot,eventId:String,includeDeletedIds:Set<String>?=null):InvestmentCashTransferEvent {
    snapshot.requireScoped();lifecycleIdentity(eventId)
    val raw=snapshot.rows.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==eventId} ?: lifecycleFail(InvestmentCashTransferError.EVENT_CONFLICT)
    fun checked(row:CloudRecord):JsonObject {
        runCatching{investmentAssetVersion(row)}.getOrElse{lifecycleFail()}
        if(row.financeRawDeleted(true)==null)lifecycleFail()
        val p=row.payload
        val updated=lifecycleDate(p.lifecycleText("updated_at"))
        if(row.updatedAt==null || lifecycleDate(row.updatedAt)!=updated)lifecycleFail()
        lifecycleDate(p.lifecycleText("created_at"));return p
    }
    val p=checked(raw)
    if(includeDeletedIds==null && raw.financeRawDeleted(true)!=false)lifecycleFail(InvestmentCashTransferError.EVENT_CONFLICT)
    val direction=when(p.lifecycleText("settlement_role_raw_value")){"investmentCashDeposit"->InvestmentCashTransferDirection.DEPOSIT;"investmentCashWithdrawal"->InvestmentCashTransferDirection.WITHDRAWAL;else->lifecycleFail()}
    if(p.lifecycleText("primary_kind_raw_value")!="transfer" || p.lifecycleText("transfer_subtype_raw_value")!="internalTransfer" || p.lifecycleText("entry_status_raw_value")!="posted")lifecycleFail()
    for(key in listOf("debt_intent_raw_value","category_id","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value",
        "exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key"))
        if(p[key]!=null && p[key]!=JsonNull)lifecycleFail()
    val amount=p.lifecycleMinor("amount_minor").takeIf{it>0} ?: lifecycleFail()
    if(p.lifecycleMinor("destination_amount_minor")!=amount || p.lifecycleMinor("reporting_amount_minor")!=amount || p.lifecycleMinor("reporting_expense_minor")!=0L || p.lifecycleMinor("reporting_income_minor")!=0L)lifecycleFail()
    val code=p.lifecycleText("source_currency_code").let(::investmentAssetCurrency) ?: lifecycleFail()
    if(listOf("destination_currency_code","reporting_currency_code").any{p.lifecycleText(it).let(::investmentAssetCurrency)!=code})lifecycleFail()
    val source=p.lifecycleReference("source_wallet_id") ?: lifecycleFail();val destination=p.lifecycleReference("destination_wallet_id") ?: lifecycleFail()
    val occurred=lifecycleDate(p.lifecycleText("occurred_at"));val created=lifecycleDate(p.lifecycleText("created_at"));val title=p.lifecycleText("title");val note=p.lifecycleOptional("note")
    val deleted=p.lifecycleOptional("deleted_at")?.let(::lifecycleDate)
    val ledger=buildJsonObject {
        put("id",eventId);put("source_wallet_id",source);put("destination_wallet_id",destination);put("currency_code",code);put("amount_minor",amount)
        put("title",title);put("note",note?.let(::JsonPrimitive) ?: JsonNull);put("occurred_at",occurred);put("created_at",created);put("deleted_at",deleted?.let(::JsonPrimitive) ?: JsonNull)
        put("is_archived",p.financeRawArchived() ?: lifecycleFail());put("archived_at",p.lifecycleOptional("archived_at")?.let{JsonPrimitive(lifecycleDate(it))} ?: JsonNull)
    }
    val canonical=investmentLedgerIdentity(eventId,"cash-transfer-posting")
    val postings=snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && (it.id==canonical || it.payload.lifecycleReference("event_id")==eventId)}.filter{
        when(it.financeRawDeleted(true)){false->true;true->includeDeletedIds?.contains(it.id)==true;null->lifecycleFail()}
    }.sortedBy{it.id}.map{row ->
        val fields=checked(row)
        if(fields.lifecycleReference("event_id")!=eventId || fields.lifecycleReference("ledger_transaction_id")!=eventId || fields.lifecycleReference("trade_id")!=null || fields.lifecycleReference("asset_id")!=null)lifecycleFail()
        val wallet=fields.lifecycleReference("wallet_id") ?: lifecycleFail()
        val role=fields.lifecycleText("role_raw_value");val bucket=fields.lifecycleText("cash_bucket_raw_value");val origin=fields.lifecycleText("cash_origin_raw_value")
        if(role !in setOf("cashTransfer","cashReconciliation","cashConsumption","cashCorrection","cashAccrual") || bucket !in setOf("booked","unreconciled") || origin !in setOf("manual","inferred","derived"))lifecycleFail()
        val currency=fields.lifecycleText("currency_code").let(::investmentAssetCurrency) ?: lifecycleFail()
        val accounting=fields.lifecycleText("accounting_currency_code").let(::investmentAssetCurrency) ?: lifecycleFail()
        val local=fields.lifecycleMinor("amount_minor");val accountingAmount=fields.lifecycleMinor("accounting_amount_minor")
        if(accounting!=code || (currency==code && local!=accountingAmount))lifecycleFail()
        val time=lifecycleDate(fields.lifecycleText("occurred_at"))
        if(row.id==canonical && (wallet!=(if(direction==InvestmentCashTransferDirection.DEPOSIT)destination else source) || currency!=code ||
            local!=(if(direction==InvestmentCashTransferDirection.DEPOSIT)amount else -amount) || role!="cashTransfer" || bucket!="booked" || origin!="manual" || time!=occurred))lifecycleFail()
        buildJsonObject {
            put("id",row.id);put("wallet_id",wallet);put("role_raw_value",role);put("cash_bucket_raw_value",bucket);put("cash_origin_raw_value",origin)
            put("currency_code",currency);put("amount_minor",local);put("accounting_amount_minor",accountingAmount);put("occurred_at",time);put("created_at",lifecycleDate(fields.lifecycleText("created_at")))
            put("deleted_at",fields.lifecycleOptional("deleted_at")?.let{JsonPrimitive(lifecycleDate(it))} ?: JsonNull)
        }
    }
    if(postings.none{it.lifecycleText("id")==canonical})lifecycleFail(InvestmentCashTransferError.EVENT_CONFLICT)
    return InvestmentCashTransferEvent(InvestmentCashTransferDraft(eventId,direction,if(direction==InvestmentCashTransferDirection.DEPOSIT)source else destination,amount,note,occurred,created),title,ledger,postings)
}
