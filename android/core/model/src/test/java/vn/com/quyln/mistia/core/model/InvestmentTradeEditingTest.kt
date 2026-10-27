package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradeEditingTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val buyId="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val saleId="77777777-7777-7777-7777-777777777777"
    private val before="2026-10-22T00:00:00Z"
    private val now="2026-10-23T00:00:00Z"
    private val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards","VND",null,"box",0,false,null,before,before,null,0,device)
    private val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000).toMutation(owner,null,device,before).record
    private fun apply(s:InvestmentPurchaseSnapshot,writes:List<Pair<CloudRecord,PendingMutation>>)=s.copy(rows=s.rows.filterNot{row->writes.any{it.first.entity==row.entity && it.first.id==row.id}}+writes.map{it.first})
    private fun snapshot(cost:Long=100,quantity:String="2"):InvestmentPurchaseSnapshot {
        val funding=if(cost>1000)wallet.copy(payload=JsonObject(wallet.payload+("opening_balance_minor" to JsonPrimitive(cost)))) else wallet
        val system=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,before).record.let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))}
        val channelRow=InvestmentChannelRecord(channel,owner.value,"Shop","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,before,before,null,0,device).toCloudRecord()
        val s=InvestmentPurchaseSnapshot(owner,listOf(system,channelRow,asset.toCloudRecord(),funding))
        val r=InvestmentPurchaseRequest(InvestmentPurchaseDraft(buyId,assetId,quantity,"box",cost,cost,"VND",null,null,null,if(cost>0)walletId else null,if(cost>0)cost else null,null,null,before,before),asset,if(cost>0)LedgerWalletRecord.fromCloudRecord(funding) else null,null,"Reserve")
        return apply(s,planInvestmentPurchase(s,r,device,before).mutations)
    }
    private fun request(gross:Long=80,quantity:String="1",unit:String="box")=InvestmentSaleRequest(InvestmentSaleDraft(saleId,assetId,quantity,unit,gross,gross,"VND",null,null,null,if(gross>0)walletId else null,null,null,now,now),asset,if(gross>0)LedgerWalletRecord.fromCloudRecord(wallet) else null,null,"Reserve")

    private fun sale(gross:Long=80,quantity:String="1"):InvestmentTradeDeletionSnapshot {
        val s=snapshot();return apply(s,planInvestmentSale(s,request(gross,quantity),device,now).mutations)
    }
    private fun editing(s:InvestmentTradeCreationSnapshot,id:String=buyId):InvestmentTradeEditRequest {
        val old=s.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id};val p=old.payload
        val buying=p.financeRawString("kind_raw_value")=="buy"
        return InvestmentTradeEditRequest(old,InvestmentTradeEditDraft(id,p.financeRawString("asset_id")!!,if(buying)InvestmentTradeKind.BUY else InvestmentTradeKind.SELL,
            p.financeRawString("quantity_decimal_string")!!,p.financeRawString("unit_label")!!,p.financeRawLong("gross_amount_minor")!!,p.financeRawLong("accounting_gross_amount_minor")!!,"VND",null,null,null,
            if(buying)p.financeRawString("funding_wallet_id") else p.financeRawString("capital_return_wallet_id"),if(buying)p.financeRawLong("funding_wallet_amount_minor") else null,null,
            p.financeRawString("note"),p.financeRawString("occurred_at")!!,p.financeRawString("created_at")!!),asset,LedgerWalletRecord.fromCloudRecord(wallet),null,"Reserve")
    }
    @Test fun editingAcquisitionTotalRecomputesLaterCostAndProfitWithoutNewIdentity() {
        val s=sale();val r=editing(s);val p=planInvestmentTradeEdit(s,r.copy(draft=r.draft.copy(grossMinor=120,accountingMinor=120,walletMinor=120)),device,now)
        assertEquals(buyId,p.trade.id);assertEquals(before,p.trade.payload.financeRawString("created_at"))
        val after=apply(s,p.mutations);val later=after.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        assertEquals(60L,later.payload.financeRawLong("released_cost_basis_minor"));assertEquals(20L,later.payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals("1",later.payload.financeRawString("position_quantity_after_decimal_string"));assertEquals(60L,later.payload.financeRawLong("position_cost_basis_after_minor"))
        assertEquals(960.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet),setOf(walletId))?.get(walletId))
    }
    @Test fun editingSaleQuantityRecomputesCapitalProfitAndStock() {
        val s=sale();val r=editing(s,saleId);val p=planInvestmentTradeEdit(s,r.copy(draft=r.draft.copy(quantity="0.5")),device,now)
        assertEquals(25L,p.trade.payload.financeRawLong("released_cost_basis_minor"));assertEquals(55L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals("1.5",p.trade.payload.financeRawString("position_quantity_after_decimal_string"));assertEquals(75L,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
        assertEquals(saleId,p.trade.id)
    }
    @Test fun replacementFundingExcludesTheOldFundingLegFromCurrentBalance() {
        val raw=snapshot(cost=1000);val r=editing(raw)
        val p=planInvestmentTradeEdit(raw,r.copy(draft=r.draft.copy(grossMinor=900,accountingMinor=900,walletMinor=900)),device,now)
        val after=apply(raw,p.mutations)
        assertEquals(100.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet),setOf(walletId))?.get(walletId))
    }
    @Test fun movingAcquisitionKeepsIdentityAndMovesEveryCanonicalPostingToTheTarget() {
        val target=asset.copy(id="88888888-8888-8888-8888-888888888888",name="Other")
        val raw=snapshot().let{it.copy(rows=it.rows+target.toCloudRecord())};val r=editing(raw)
        val p=planInvestmentTradeEdit(raw,r.copy(expectedAsset=target,draft=r.draft.copy(assetId=target.id)),device,now)
        assertEquals(target.id,p.trade.payload.financeRawString("asset_id"));assertEquals(buyId,p.trade.id)
        val after=apply(raw,p.mutations)
        assertTrue(after.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("trade_id")==buyId}.all{it.payload.financeRawString("asset_id")==target.id})
        assertTrue(after.rows.none{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.financeRawDeleted(true)==false && it.payload.financeRawString("asset_id")==asset.id});assertEquals("2",p.trade.payload.financeRawString("position_quantity_after_decimal_string"))
    }
    @Test fun movingAcquisitionNeededByOriginalSaleRejectsBeforeAnyWrite() {
        val target=asset.copy(id="88888888-8888-8888-8888-888888888888",name="Other")
        val raw=sale().let{it.copy(rows=it.rows+target.toCloudRecord())};val r=editing(raw)
        val e=runCatching{planInvestmentTradeEdit(raw,r.copy(expectedAsset=target,draft=r.draft.copy(assetId=target.id)),device,now)}.exceptionOrNull()
        assertEquals(InvestmentAccountingError.INSUFFICIENT_POSITION,(e as? InvestmentAccountingException)?.reason)
    }
    @Test fun editCannotChangeTradeKindOrCreatedAt() {
        val raw=snapshot();val r=editing(raw)
        for(d in listOf(r.draft.copy(kind=InvestmentTradeKind.SELL),r.draft.copy(createdAt=now))) {
            val e=runCatching{planInvestmentTradeEdit(raw,r.copy(draft=d),device,now)}.exceptionOrNull()
            assertEquals(InvestmentAssetError.STALE_RECORD,(e as? InvestmentAssetException)?.reason)
        }
    }
    @Test fun exactCommittedEditRetriesWithoutChangingAnyRecord() {
        val raw=sale();val r=editing(raw).let{it.copy(draft=it.draft.copy(grossMinor=120,accountingMinor=120,walletMinor=120))}
        val p=planInvestmentTradeEdit(raw,r,device,now);val after=apply(raw,p.mutations)
        assertTrue(planInvestmentTradeEdit(after,r,device,"2026-10-24T00:00:00Z").mutations.isEmpty())
    }
    @Test fun paidToPromotionalStockRetiresFundingWithoutChangingQuantity() {
        val raw=snapshot();val r=editing(raw).let{it.copy(expectedWallet=null,draft=it.draft.copy(grossMinor=0,accountingMinor=0,walletId=null,walletMinor=null))}
        val p=planInvestmentTradeEdit(raw,r,device,now)
        assertEquals("2",p.trade.payload.financeRawString("position_quantity_after_decimal_string"));assertEquals(0L,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
        assertEquals(JsonNull,p.trade.payload["funding_ledger_transaction_id"])
        assertEquals(2,p.mutations.count{it.second.kind==MutationKind.DELETE})
    }

    @Test fun incompletePromotionalEditCannotRetryWithItsOriginalFundingTombstoneMissing() {
        val raw=snapshot();val r=editing(raw).let{it.copy(expectedWallet=null,draft=it.draft.copy(grossMinor=0,accountingMinor=0,walletId=null,walletMinor=null))}
        val after=apply(raw,planInvestmentTradeEdit(raw,r,device,now).mutations)
        val broken=after.copy(rows=after.rows.filterNot{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(buyId,"funding-posting")})
        val e=runCatching{planInvestmentTradeEdit(broken,r,device,now)}.exceptionOrNull()
        assertEquals(InvestmentAssetError.INVALID_ACCOUNTING,(e as? InvestmentAssetException)?.reason)
    }
    @Test fun exactMovedRetryCannotLoseTheOriginalAssetHistory() {
        val target=asset.copy(id="88888888-8888-8888-8888-888888888888",name="Other")
        val raw=snapshot().let{it.copy(rows=it.rows+target.toCloudRecord())};val r=editing(raw).let{it.copy(expectedAsset=target,draft=it.draft.copy(assetId=target.id))}
        val after=apply(raw,planInvestmentTradeEdit(raw,r,device,now).mutations)
        assertTrue(planInvestmentTradeEdit(after,r,device,now).mutations.isEmpty())
        val broken=after.copy(rows=after.rows.filterNot{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==assetId})
        val e=runCatching{planInvestmentTradeEdit(broken,r,device,now)}.exceptionOrNull()
        assertEquals(InvestmentAssetError.NOT_FOUND,(e as? InvestmentAssetException)?.reason)
    }
    @Test fun newerPrimaryNoteCannotBeOverwrittenByAnOldEditIntent() {
        val raw=snapshot();val r=editing(raw).let{it.copy(draft=it.draft.copy(note="My edit"))}
        val changed=raw.copy(rows=raw.rows.map{if(it.id==buyId)it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("Newer unseen edit")))) else it})
        val e=runCatching{planInvestmentTradeEdit(changed,r,device,now)}.exceptionOrNull()
        assertEquals(InvestmentAssetError.STALE_RECORD,(e as? InvestmentAssetException)?.reason)
    }
    @Test fun metadataAckLongPrecisionAndOpaqueFieldsSurviveEditAndRetry() {
        val raw=snapshot();val r=editing(raw).let{it.copy(draft=it.draft.copy(note="Keep me"))}
        val version=9007199254740993L
        val ack=raw.copy(rows=raw.rows.map{it.copy(syncVersion=version,payload=JsonObject(it.payload+buildJsonObject{put("sync_version",version);put("future_flag","keep")}))})
        val p=planInvestmentTradeEdit(ack,r,device,now)
        assertEquals(JsonPrimitive("keep"),p.trade.payload["future_flag"]);assertEquals(version,p.trade.syncVersion)
        assertTrue(p.mutations.all{it.second.baseVersion==version});assertTrue(planInvestmentTradeEdit(apply(ack,p.mutations),r,device,now).mutations.isEmpty())
    }
    @Test fun saleToLossThenBackToReceiptUsesTheSameCanonicalIdentities() {
        val raw=sale();val r=editing(raw,saleId).let{it.copy(expectedWallet=null,draft=it.draft.copy(grossMinor=0,accountingMinor=0,walletId=null))}
        val loss=planInvestmentTradeEdit(raw,r,device,now);val after=apply(raw,loss.mutations)
        assertEquals(-50L,loss.trade.payload.financeRawLong("realized_profit_loss_minor"));assertEquals(JsonNull,loss.trade.payload["capital_return_ledger_transaction_id"])
        assertEquals(investmentSystemWalletId(owner),after.rows.single{it.id==investmentLedgerIdentity(saleId,"cash-accrual-posting")}.payload.financeRawString("wallet_id"))
        val restore=editing(after,saleId).let{it.copy(draft=it.draft.copy(grossMinor=80,accountingMinor=80,walletId=walletId))}
        val p=planInvestmentTradeEdit(after,restore,device,now);val final=apply(after,p.mutations)
        assertEquals(30L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
        assertNull(final.rows.single{it.id==investmentLedgerIdentity(saleId,"capital-return")}.deletedAt)
        assertEquals(walletId,final.rows.single{it.id==investmentLedgerIdentity(saleId,"cash-accrual-posting")}.payload.financeRawString("wallet_id"))
    }
    @Test fun insufficientReplacementMoneyAndOversoldEditRemainRejected() {
        val raw=snapshot();val r=editing(raw)
        val e=runCatching{planInvestmentTradeEdit(raw,r.copy(draft=r.draft.copy(grossMinor=1001,accountingMinor=1001,walletMinor=1001)),device,now)}.exceptionOrNull()
        assertEquals(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,(e as? TransactionValidationException)?.reason)
        val sold=sale();val sell=editing(sold,saleId)
        val stock=runCatching{planInvestmentTradeEdit(sold,sell.copy(draft=sell.draft.copy(quantity="3")),device,now)}.exceptionOrNull()
        assertEquals(InvestmentAccountingError.INSUFFICIENT_POSITION,(stock as? InvestmentAccountingException)?.reason)
    }

    private fun withReserve():InvestmentTradeCreationSnapshot {
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",owner.value,buildJsonObject {
            put("id","bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");put("user_id",owner.value);put("event_id","cccccccc-cccc-cccc-cccc-cccccccccccc");put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId);put("ledger_transaction_id",JsonNull)
            put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual");put("amount_minor",600L);put("currency_code","VND");put("accounting_amount_minor",600L);put("accounting_currency_code","VND")
            put("occurred_at","2026-10-21T00:00:00Z");put("created_at",before);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
        },now,null,0)
        val raw=snapshot(cost=700).let{it.copy(rows=it.rows+posting)}
        val cash=InvestmentCashReadSnapshot(owner,raw.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        return apply(raw,planInvestmentFundEffects(cash,"VND",investmentFundUsageTimeline(cash,"VND"),"Reserve",device,now).mutations)
    }
    @Test fun editingFundingRequiresExactConsentAndRejectsAnOlderSourceReview() {
        val raw=withReserve();val r=editing(raw).let{it.copy(draft=it.draft.copy(grossMinor=600,accountingMinor=600,walletMinor=600))}
        val e=runCatching{planInvestmentTradeEdit(raw,r,device,now)}.exceptionOrNull()
        assertTrue(e is InvestmentTradeEditConfirmationRequired);val review=(e as InvestmentTradeEditConfirmationRequired).review
        assertEquals(300.toBigInteger(),review.comparison.changes.single().previousMinor);assertEquals(200.toBigInteger(),review.comparison.changes.single().proposedMinor)
        val p=planInvestmentTradeEdit(raw,r.copy(consent=review.consent),device,now);val after=apply(raw,p.mutations)
        assertTrue(planInvestmentTradeEdit(after,r.copy(consent=review.consent),device,now).mutations.isEmpty())
        val changed=raw.copy(rows=raw.rows.map{if(it.id==walletId)it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(1001L)))) else it})
        val currentWallet=LedgerWalletRecord.fromCloudRecord(changed.rows.single{it.id==walletId})
        // Keep the altered source's derived baseline canonical before requesting a new edit.
        val cash=InvestmentCashReadSnapshot(owner,changed.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        val coherent=apply(changed,planInvestmentFundEffects(cash,"VND",investmentFundUsageTimeline(cash,"VND"),"Reserve",device,now).mutations)
        assertTrue(runCatching{planInvestmentTradeEdit(coherent,r.copy(expectedWallet=currentWallet,consent=review.consent),device,now)}.exceptionOrNull() is InvestmentTradeEditConfirmationRequired)
    }

    @Test fun cardReplacementExcludesOldLiabilityButStillEnforcesCurrentLimit() {
        val raw=snapshot().let{it.copy(rows=it.rows.map{row->if(row.id==walletId)row.copy(payload=JsonObject(row.payload+buildJsonObject{put("kind_raw_value","creditCard");put("opening_balance_minor",0L)})) else row}+
            CreditCardProfileRecord("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",owner.value,"Bank","visa","1234",120,20,10,null,walletId,null,false,before,before,null,0,device).toCloudRecord())}
        // Canonical funding already has the same wallet currency and role; card kind changes only capacity semantics.
        val r=editing(raw).let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(raw.rows.single{it.id==walletId}),draft=it.draft.copy(grossMinor=120,accountingMinor=120,walletMinor=120))}
        assertEquals(120L,planInvestmentTradeEdit(raw,r,device,now).trade.payload.financeRawLong("gross_amount_minor"))
        val e=runCatching{planInvestmentTradeEdit(raw,r.copy(draft=r.draft.copy(grossMinor=121,accountingMinor=121,walletMinor=121)),device,now)}.exceptionOrNull()
        assertEquals(TransactionValidationError.CREDIT_LIMIT_EXCEEDED,(e as? TransactionValidationException)?.reason)
    }

    @Test fun maximumReplacementTotalRetainsEveryLongDigitAndExactCost() {
        val raw=snapshot().let{it.copy(rows=it.rows.map{row->if(row.id==walletId)row.copy(payload=JsonObject(row.payload+("opening_balance_minor" to JsonPrimitive(Long.MAX_VALUE)))) else row})}
        val r=editing(raw).let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(raw.rows.single{it.id==walletId}),draft=it.draft.copy(grossMinor=Long.MAX_VALUE,accountingMinor=Long.MAX_VALUE,walletMinor=Long.MAX_VALUE))}
        val p=planInvestmentTradeEdit(raw,r,device,now)
        assertEquals(Long.MAX_VALUE,p.trade.payload.financeRawLong("gross_amount_minor"));assertEquals(Long.MAX_VALUE,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
        val after=apply(raw,p.mutations);assertEquals(0.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},setOf(walletId))?.get(walletId))
    }
    @Test fun editingForeignSourceTotalUsesItsExactStoredSourceAndAccountingPair() {
        val foreign=asset.copy(currencyCode="JPY")
        val raw=snapshot(cost=70).let{it.copy(rows=it.rows.map{row->when {
            row.entity==CloudEntity.INVESTMENT_ASSET.table && row.id==assetId->foreign.toCloudRecord()
            row.entity==CloudEntity.INVESTMENT_TRADE.table && row.id==buyId->row.copy(payload=JsonObject(row.payload+buildJsonObject{put("currency_code","JPY");put("gross_amount_minor",7L);put("exchange_rate_decimal_string","10");put("exchange_rate_provider","stored")}))
            else->row
        }})}
        val r=editing(raw).let{it.copy(expectedAsset=foreign,draft=it.draft.copy(grossMinor=8,accountingMinor=80,walletMinor=80,sourceRate="10",rateProvider="stored"))}
        val p=planInvestmentTradeEdit(raw,r,device,now)
        assertEquals(8L,p.trade.payload.financeRawLong("gross_amount_minor"));assertEquals(80L,p.trade.payload.financeRawLong("accounting_gross_amount_minor"));assertEquals("10",p.trade.payload.financeRawString("exchange_rate_decimal_string"))
    }

    @Test fun completedFreeEditRejectsMalformedRetiredFundingMoneyWalletAndLedgerLinks() {
        val raw=snapshot();val r=editing(raw).let{it.copy(expectedWallet=null,draft=it.draft.copy(grossMinor=0,accountingMinor=0,walletId=null,walletMinor=null))}
        val after=apply(raw,planInvestmentTradeEdit(raw,r,device,now).mutations)
        val ledgerId=investmentLedgerIdentity(buyId,"funding");val postingId=investmentLedgerIdentity(buyId,"funding-posting")
        for((id,fields) in listOf(ledgerId to buildJsonObject{put("amount_minor",99L)},ledgerId to buildJsonObject{put("source_wallet_id",investmentSystemWalletId(owner))},
            postingId to buildJsonObject{put("amount_minor",-99L)},postingId to buildJsonObject{put("ledger_transaction_id","99999999-9999-9999-9999-999999999999")})) {
            val broken=after.copy(rows=after.rows.map{if(it.id==id)it.copy(payload=JsonObject(it.payload+fields)) else it})
            val e=runCatching{planInvestmentTradeEdit(broken,r,device,now)}.exceptionOrNull()
            assertEquals("Malformed retired financial field must not be a complete result: "+fields,InvestmentAssetError.INVALID_ACCOUNTING,(e as? InvestmentAssetException)?.reason)
        }
    }

    @Test fun foreignRetiredProfitProofUsesStoredLocalMoneyAndRejectsACorruptCashAccrual() {
        val foreignId="88888888-8888-8888-8888-888888888888"
        val foreign=WalletDraft(id=foreignId,name="JPY",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,before).record
        val raw=snapshot().let{it.copy(rows=it.rows+foreign)}
        val sell=request().let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(foreign),draft=it.draft.copy(capitalWalletId=foreignId,accountingToCapitalRate="0.1"))}
        val source=apply(raw,planInvestmentSale(raw,sell,device,now).mutations)
        val r=editing(source,saleId).let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(foreign),draft=it.draft.copy(grossMinor=50,accountingMinor=50,walletRate="0.1"))}
        val p=planInvestmentTradeEdit(source,r,device,now);val after=apply(source,p.mutations)
        assertEquals(0L,p.trade.payload.financeRawLong("realized_profit_loss_minor"));assertTrue(planInvestmentTradeEdit(after,r,device,now).mutations.isEmpty())
        val retiredId=investmentLedgerIdentity(saleId,"cash-accrual-posting")
        assertEquals(3L,after.rows.single{it.id==retiredId}.payload.financeRawLong("amount_minor"))
        val bad=after.copy(rows=after.rows.map{if(it.id==retiredId)it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonPrimitive(2L)))) else it})
        assertEquals(InvestmentAssetError.INVALID_ACCOUNTING,(runCatching{planInvestmentTradeEdit(bad,r,device,now)}.exceptionOrNull() as? InvestmentAssetException)?.reason)
    }

    @Test fun editingAcquisitionProducesAnOwnedCausalParentButDerivedSaleRebuildDoesNot() {
        val source=sale();val request=editing(source)
        val plan=planInvestmentTradeEdit(source,request.copy(draft=request.draft.copy(grossMinor=120,accountingMinor=120,walletMinor=120)),device,now)
        val old=request.expectedTrade
        val parents=localInvestmentTradePublicationParents(plan.trade)
        assertEquals(1,parents.size);assertEquals(investmentTradeIntentFingerprint(old.payload),parents.single().fingerprint)
        assertEquals(old.syncVersion,parents.single().baseVersion)
        val later=plan.mutations.single{it.first.entity==CloudEntity.INVESTMENT_TRADE.table && it.first.id==saleId}.first
        assertTrue(localInvestmentTradePublicationParents(later).isEmpty())
    }

}
