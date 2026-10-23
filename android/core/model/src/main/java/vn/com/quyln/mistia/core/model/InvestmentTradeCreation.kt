package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.math.BigInteger
import java.math.BigDecimal
import kotlinx.serialization.json.*

/** One consistent raw read set for actual BUY and SELL creation. */
data class InvestmentTradeCreationSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    companion object {val entities=TransactionInvestmentSaveSnapshot.entities+InvestmentAssetSnapshot.entities}
}
data class InvestmentTradeCreationConsent(val token:String)
data class InvestmentTradeCreationReview(val consent:InvestmentTradeCreationConsent,val comparison:InvestmentFundTimelineComparison,val fundingUsage:InvestmentFundTimelineUsage?,val requiresConfirmation:Boolean)
data class InvestmentTradeCreationPlan(val trade:CloudRecord,val mutations:List<Pair<CloudRecord,PendingMutation>>,val review:InvestmentTradeCreationReview)

/** walletRate is funding→accounting for BUY, accounting→capital-return for SELL. */
internal data class InvestmentTradeCreationDraft(val id:String,val assetId:String,val kind:InvestmentTradeKind,val quantity:String,val unit:String,val grossMinor:Long,
    val accountingMinor:Long,val accountingCurrency:String,val sourceRate:String?,val rateProvider:String?,val rateDate:String?,
    val walletId:String?,val walletMinor:Long?,val walletRate:String?,val note:String?,val occurredAt:String,val createdAt:String)
internal data class InvestmentTradeCreationRequest(val draft:InvestmentTradeCreationDraft,val expectedAsset:InvestmentAssetRecord,val expectedWallet:LedgerWalletRecord?,
    val consent:InvestmentTradeCreationConsent?,val adjustmentTitle:String)

internal fun planInvestmentTradeCreation(snapshot:InvestmentTradeCreationSnapshot,request:InvestmentTradeCreationRequest,deviceId:String,now:String):InvestmentTradeCreationPlan {
    val buying=request.draft.kind==InvestmentTradeKind.BUY
    val d=request.draft
    investmentAssetIdentity(snapshot.owner.value);investmentAssetIdentity(deviceId);investmentAssetIdentity(d.id);investmentAssetIdentity(d.assetId)
    listOf(now,d.createdAt,d.occurredAt).forEach(::investmentAssetDate)
    fun fail(reason:InvestmentAssetError=InvestmentAssetError.INVALID_ACCOUNTING):Nothing=investmentAssetFail(reason)
    if(snapshot.rows.any{row ->CloudEntity.fromTable(row.entity) !in InvestmentPurchaseSnapshot.entities ||
        !row.financeRawIdentity(snapshot.owner,CloudEntity.fromTable(row.entity)!!,true)} ||
        snapshot.rows.map{it.entity to it.id}.distinct().size!=snapshot.rows.size)fail(InvestmentAssetError.UNREADABLE_SOURCE)
    val rawAsset=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==d.assetId} ?: fail(InvestmentAssetError.NOT_FOUND)
    val asset=InvestmentAssetRecord.fromCloudRecord(rawAsset)
    if(asset.deletedAt!=null || asset.isArchived || !request.expectedAsset.matchesVisibleInvestmentAsset(asset))fail(InvestmentAssetError.STALE_RECORD)
    val channel=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.id==asset.channelId}?.let(InvestmentChannelRecord::fromCloudRecord)
        ?: fail(InvestmentAssetError.MISSING_CHANNEL)
    if(channel.deletedAt!=null || channel.isArchived)fail(InvestmentAssetError.MISSING_CHANNEL)
    val unit=InvestmentUnitLabel.normalizedDisplay(d.unit) ?: fail(InvestmentAssetError.UNIT_REQUIRED)
    if(asset.defaultUnitLabel==null)fail(InvestmentAssetError.UNIT_REQUIRED)
    val quantity=investmentTradeQuantity(d.quantity) ?: fail()
    if(d.grossMinor<0 || d.accountingMinor<0 || (d.grossMinor==0L)!=(d.accountingMinor==0L))fail()
    val code=investmentAssetCurrency(d.accountingCurrency) ?: fail(InvestmentAssetError.INVALID_CURRENCY)
    val system=snapshot.rows.singleOrNull{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==investmentSystemWalletId(snapshot.owner)}
        ?.let(::investmentLinkedWalletRecord) ?: fail(InvestmentAssetError.MISSING_WALLET)
    if(system.kind!=WalletKind.INVESTMENT || system.systemPurposeRawValue!="investmentProfit" || system.currencyCode!=code || system.isArchived || system.deletedAt!=null)fail()
    if(d.grossMinor>0) {
        if(investmentPurchaseConvertedMinor(d.grossMinor,asset.currencyCode,code,d.sourceRate)!=d.accountingMinor)fail()
    } else if(listOf(d.sourceRate,d.rateProvider,d.rateDate,d.walletRate).any{it!=null})fail()
    val wallet=d.walletId?.let{id ->snapshot.rows.singleOrNull{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id}?.let(::investmentLinkedWalletRecord)}
    if(d.grossMinor==0L) {
        if(d.walletId!=null || d.walletMinor!=null || request.expectedWallet!=null)fail()
    } else {
        if(wallet==null || wallet.deletedAt!=null || wallet.isArchived || wallet.kind==null || wallet.kind==WalletKind.INVESTMENT || (!buying && wallet.kind==WalletKind.CREDIT_CARD) || request.expectedWallet?.matchesVisibleInvestmentWallet(wallet)!=true)fail(InvestmentAssetError.MISSING_WALLET)
        if(buying && investmentPurchaseConvertedMinor(d.accountingMinor,code,wallet.currencyCode,d.walletRate,inverse=true)!=d.walletMinor)fail()
        if(!buying && wallet.currencyCode!=code)investmentPurchaseConvertedMinor(d.accountingMinor,code,wallet.currencyCode,d.walletRate)
    }
    val fields=buildJsonObject {
        put("channel_id",asset.channelId);put("asset_id",asset.id);put("kind_raw_value",if(buying)"buy" else "sell");put("quantity_decimal_string",quantity.stripTrailingZeros().toPlainString());put("unit_label",unit)
        put("gross_amount_minor",d.grossMinor);put("currency_code",asset.currencyCode);put("accounting_gross_amount_minor",d.accountingMinor);put("accounting_currency_code",code)
        put("exchange_rate_decimal_string",d.sourceRate?.let(::JsonPrimitive) ?: JsonNull);put("exchange_rate_provider",d.rateProvider?.let(::JsonPrimitive) ?: JsonNull);put("exchange_rate_date",d.rateDate?.let(::JsonPrimitive) ?: JsonNull)
        put("funding_wallet_id",if(buying)d.walletId?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("funding_wallet_currency_code",if(buying)wallet?.currencyCode?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("funding_wallet_amount_minor",if(buying)d.walletMinor?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("funding_to_accounting_rate_decimal_string",if(buying)d.walletRate?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("capital_return_wallet_id",if(!buying)d.walletId?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("capital_return_wallet_currency_code",if(!buying)wallet?.currencyCode?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("capital_return_wallet_amount_minor",JsonNull)
        put("accounting_to_capital_return_rate_decimal_string",if(!buying)d.walletRate?.let(::JsonPrimitive) ?: JsonNull else JsonNull)
        put("note",investmentCashTrimmedText(d.note)?.let(::JsonPrimitive) ?: JsonNull);put("occurred_at",Instant.parse(d.occurredAt).toString())
        for(key in listOf("funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id"))put(key,JsonNull)
    }
    val old=snapshot.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==d.id}
    if(old!=null && (old.financeRawDeleted(true)!=false || fields.filterKeys{it !in setOf("funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id")+(if(buying)emptySet() else setOf("capital_return_wallet_amount_minor"))}.any{(k,v)->purchaseSemantic(old.payload[k],k)!=purchaseSemantic(v,k)} ||
        Instant.parse(old.payload.financeRawString("created_at"))!=Instant.parse(d.createdAt)))fail(InvestmentAssetError.STALE_RECORD)
    val assetSource=InvestmentAssetSnapshot(snapshot.owner,snapshot.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentAssetSnapshot.entities})
    fun same(a:CloudRecord,b:CloudRecord)=a.payload.filterKeys{it !in purchaseAckFields}.mapValues{(key,value)->purchaseSemantic(value,key)}==b.payload.filterKeys{it !in purchaseAckFields}.mapValues{(key,value)->purchaseSemantic(value,key)}
    val baseline=rebuildInvestmentAssetUnitHistory(assetSource,asset,asset.defaultUnitLabel,deviceId,now,resolveZeroBuyFunding=false)
    if(baseline.any{row->snapshot.rows.singleOrNull{it.entity==row.entity && it.id==row.id}?.let{same(row,it)}!=true})fail(InvestmentAssetError.INVALID_ACCOUNTING)
    if(old==null) {
        val ledgerIds=setOf("funding","capital-return","profit-loss").map{investmentLedgerIdentity(d.id,it)}.toSet()
        val postingIds=setOf("funding-posting","capital-return-posting","profit-loss-posting","cash-accrual-posting").map{investmentLedgerIdentity(d.id,it)}.toSet()
        if(snapshot.rows.any{row->(row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id in ledgerIds) ||
            (row.entity==CloudEntity.INVESTMENT_POSTING.table && (row.id in postingIds || row.payload.financeRawReference("trade_id").id==d.id || row.payload.financeRawReference("event_id").id==d.id))})fail(InvestmentAssetError.STALE_RECORD)
    }
    val primary=old ?: CloudRecord(CloudEntity.INVESTMENT_TRADE.table,d.id,snapshot.owner.value,buildJsonObject {
        put("id",d.id);put("user_id",snapshot.owner.value);put("created_at",Instant.parse(d.createdAt).toString());put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L);put("last_modified_by_device_id",deviceId)
        fields.forEach{put(it.key,it.value)}
    },now,null,0L)
    val source=InvestmentAssetSnapshot(snapshot.owner,snapshot.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentAssetSnapshot.entities && !(it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==d.id)}+primary)
    val rebuilt=rebuildInvestmentAssetUnitHistory(source,asset,unit,deviceId,now,resolveZeroBuyFunding=false,preserveAccountingErrors=!buying)
    val changed=rebuilt.filter{row ->snapshot.rows.singleOrNull{it.entity==row.entity && it.id==row.id}?.let{same(row,it)}!=true}
    if(old!=null && changed.isNotEmpty())fail(InvestmentAssetError.STALE_RECORD)
    val trade=rebuilt.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==d.id}
    val cash=InvestmentCashReadSnapshot(snapshot.owner,snapshot.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
    val beforeTimeline=investmentFundUsageTimeline(cash,code)
    if(planInvestmentFundEffects(cash,code,beforeTimeline,request.adjustmentTitle,deviceId,now).mutations.isNotEmpty())fail(InvestmentAssetError.INVALID_ACCOUNTING)
    val afterRows=snapshot.rows.filterNot{row->changed.any{it.entity==row.entity && it.id==row.id}}+changed
    val afterCash=InvestmentCashReadSnapshot(snapshot.owner,afterRows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
    val afterTimeline=investmentFundUsageTimeline(afterCash,code)
    val comparison=tradeComparison(beforeTimeline,afterTimeline,snapshot.rows)
    val fundingUsage=if(buying)afterTimeline.usages[investmentLedgerIdentity(d.id,"funding")] else null
    val effects=planInvestmentFundEffects(afterCash,code,afterTimeline,request.adjustmentTitle,deviceId,now)
    val token=RecordConflictResolver.semanticFingerprint(buildJsonObject {
        put("proposal",JsonObject(fields+("created_at" to JsonPrimitive(Instant.parse(d.createdAt).toString()))+("id" to JsonPrimitive(d.id))))
        put("owner",snapshot.owner.value)
        put("source",JsonArray(snapshot.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)).map{row->buildJsonObject {
            put("entity",row.entity);put("id",row.id);put("owner",row.ownerUserId);put("fields",JsonObject(row.payload.filterKeys{it !in purchaseAckFields}))
        }}))
    })
    val review=InvestmentTradeCreationReview(InvestmentTradeCreationConsent(token),comparison,fundingUsage,comparison.changes.isNotEmpty() || fundingUsage?.investmentToUseMinor?.signum()==1)
    if(old!=null) {
        if(effects.mutations.isNotEmpty())fail(InvestmentAssetError.INVALID_ACCOUNTING)
        return InvestmentTradeCreationPlan(old,emptyList(),review)
    }
    if(buying && wallet!=null) {
        val amount=requireNotNull(d.walletMinor)
        if(wallet.kind==WalletKind.CREDIT_CARD) {
            val full=TransactionInvestmentSaveSnapshot(snapshot.owner,TransactionInvestmentSaveSnapshot.entities.associateWith{entity->snapshot.rows.filter{it.entity==entity.table}})
            val ledger=rebuilt.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==investmentLedgerIdentity(d.id,"funding")}
            val profiles=full.transactionSnapshot().active(CloudEntity.CREDIT_CARD_PROFILE).map(CreditCardProfileRecord::fromCloudRecord)
            requireExactOrdinaryAffordability(full,LedgerTransactionRecord.fromCloudRecord(ledger),profiles,null)
        } else {
            val actual=financeWalletBalancesRaw(snapshot.owner,cash.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},cash.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},setOf(wallet.id))?.get(wallet.id)
                ?: fail(InvestmentAssetError.UNREADABLE_SOURCE)
            val unrecorded=if(wallet.currencyCode==code)investmentCashAllocation(cash.walletSnapshot(),code).locations.singleOrNull{it.walletId==wallet.id}?.originalUnreconciledMinor?.max(BigInteger.ZERO) ?: BigInteger.ZERO else BigInteger.ZERO
            if(BigInteger.valueOf(amount)>actual+unrecorded || fundingUsage?.outcome==InvestmentFundUsageOutcome.INSUFFICIENT_FUNDS)
                throw TransactionValidationException(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE)
        }
    }
    if((review.requiresConfirmation || request.consent!=null) && request.consent!=review.consent) {
        if(buying)throw InvestmentPurchaseConfirmationRequired(review) else throw InvestmentSaleConfirmationRequired(review)
    }
    val writes=changed.map{it to PendingMutation(CloudEntity.fromTable(it.entity)!!,it.id,snapshot.owner.value,if(it.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,it.payload,now,it.syncVersion,deviceId)}+effects.mutations
    require(writes.map{it.first.entity to it.first.id}.distinct().size==writes.size)
    return InvestmentTradeCreationPlan(trade,writes,review)
}


private val purchaseAckFields=setOf("updated_at","sync_version","last_modified_by_device_id","last_modified_by_user_id")
private fun tradeComparison(before:InvestmentFundTimeline,after:InvestmentFundTimeline,rows:List<CloudRecord>):InvestmentFundTimelineComparison {
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
        if(old==new && id !in reallocated)null else InvestmentFundTimelineWalletChange(id,rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id}.payload.financeRawString("currency_code")!!,old,new,after.availableByWalletId[id] ?: BigInteger.ZERO)
    }.sortedWith(compareByDescending<InvestmentFundTimelineWalletChange>{(it.proposedMinor-it.previousMinor).abs()}.thenByDescending{it.walletId})
    return InvestmentFundTimelineComparison(before,after,changes)
}

private fun purchaseSemantic(value:JsonElement?,key:String):JsonElement?=if(key in setOf("created_at","occurred_at","deleted_at","archived_at") && value is JsonPrimitive && value.isString)
    runCatching{JsonPrimitive(Instant.parse(value.content).toString())}.getOrDefault(value) else value


/** Same representable Decimal quantity for form limits, wire input and FIFO arithmetic. */
fun investmentTradeQuantity(value:String):BigDecimal? {
    val parsed=value.takeIf{it.length<=256}?.toBigDecimalOrNull()?.takeIf{it.signum()>0 && it.scale() in -165..128} ?: return null
    return runCatching{InvestmentDecimalMath.quantity(parsed)}.getOrNull()?.takeIf{it.signum()>0}
}
