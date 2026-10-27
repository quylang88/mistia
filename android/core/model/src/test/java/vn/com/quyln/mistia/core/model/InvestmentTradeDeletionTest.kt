package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradeDeletionTest {
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
    private fun deleting(s:InvestmentTradeDeletionSnapshot,id:String=saleId)=InvestmentTradeDeletionRequest(s.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id},null,"Reserve")
    @Test fun renamingMetadataDoesNotInvalidateAnExistingFundingTitleBeforeTradeDeletion() {
        val s=snapshot().let{it.copy(rows=it.rows.map{row->if(row.entity==CloudEntity.INVESTMENT_ASSET.table)row.copy(payload=JsonObject(row.payload+("name" to JsonPrimitive("New cards")))) else row})}
        val plan=planInvestmentTradeDeletion(s,deleting(s,buyId),device,now)
        assertEquals(now,plan.trade.deletedAt)
        assertEquals(100L,plan.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload.financeRawLong("amount_minor"))
        val corrupt=s.copy(rows=s.rows.map{row->if(row.entity==CloudEntity.LEDGER_TRANSACTION.table)row.copy(payload=JsonObject(row.payload+("amount_minor" to JsonPrimitive(101)))) else row})
        assertTrue(runCatching{planInvestmentTradeDeletion(corrupt,deleting(corrupt,buyId),device,now)}.isFailure)
    }
    @Test fun deletingASaleRestoresFifoStockAndTombstonesItsCapitalProfitAndCashAccrual() {
        val s=sale();val plan=planInvestmentTradeDeletion(s,deleting(s),device,now)
        assertEquals(now,plan.trade.deletedAt);assertEquals(6,plan.mutations.size);assertTrue(plan.mutations.all{it.second.kind==MutationKind.DELETE && it.first.deletedAt==now})
        val after=apply(s,plan.mutations)
        assertEquals(900.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet),setOf(walletId))?.get(walletId))
        val cash=InvestmentCashReadSnapshot(owner,after.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        assertEquals(0.toBigInteger(),investmentCashAllocation(cash.walletSnapshot(),"VND").totalMinor)
        val next=request(gross=80,quantity="2").let{it.copy(draft=it.draft.copy(id="99999999-9999-9999-9999-999999999999"))}
        assertEquals("0",planInvestmentSale(after,next,device,now).trade.payload.financeRawString("position_quantity_after_decimal_string"))
    }
    @Test fun deletingAnAcquisitionNeededByALaterSaleIsRejectedBeforeAnyWrite() {
        val s=sale();val error=runCatching{planInvestmentTradeDeletion(s,deleting(s,buyId),device,now)}.exceptionOrNull()
        assertEquals(InvestmentAccountingError.INSUFFICIENT_POSITION,(error as? InvestmentAccountingException)?.reason)
    }
    @Test fun deletingATotalLossRestoresStockWithoutCreatingAnOrdinaryCashReceipt() {
        val s=sale(gross=0,quantity="2");val plan=planInvestmentTradeDeletion(s,deleting(s),device,now)
        val after=apply(s,plan.mutations)
        assertTrue(plan.mutations.all{it.second.kind==MutationKind.DELETE})
        assertEquals(900.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet),setOf(walletId))?.get(walletId))
        assertEquals("0",planInvestmentSale(after,request(gross=80,quantity="2").let{it.copy(draft=it.draft.copy(id="99999999-9999-9999-9999-999999999999"))},device,now).trade.payload.financeRawString("position_quantity_after_decimal_string"))
    }
    @Test fun anExactDeletedResultRetriesWithoutChangingAnyRecordOrQueue() {
        val s=sale();val r=deleting(s);val plan=planInvestmentTradeDeletion(s,r,device,now)
        val after=apply(s,plan.mutations);val retry=planInvestmentTradeDeletion(after,r,device,"2026-10-24T00:00:00Z")
        assertEquals(plan.trade,retry.trade);assertTrue(retry.mutations.isEmpty())
    }
    @Test fun deletingAnEarlierLotRecomputesLaterSaleCostAndProfitWithoutChangingItsGrossReceipt() {
        var source=snapshot()
        val extraId="88888888-8888-8888-8888-888888888888"
        val second=InvestmentPurchaseRequest(InvestmentPurchaseDraft(extraId,assetId,"2","box",200,200,"VND",null,null,null,walletId,200,null,null,now,now),asset,LedgerWalletRecord.fromCloudRecord(wallet),null,"Reserve")
        source=apply(source,planInvestmentPurchase(source,second,device,now).mutations)
        val r=request(gross=150).let{it.copy(draft=it.draft.copy(occurredAt="2026-10-24T00:00:00Z"))}
        source=apply(source,planInvestmentSale(source,r,device,now).mutations)
        val plan=planInvestmentTradeDeletion(source,deleting(source,buyId),device,now);val after=apply(source,plan.mutations)
        val later=after.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        assertEquals(100L,later.payload.financeRawLong("released_cost_basis_minor"));assertEquals(50L,later.payload.financeRawLong("realized_profit_loss_minor"));assertEquals(150L,later.payload.financeRawLong("gross_amount_minor"))
        assertEquals(950.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet),setOf(walletId))?.get(walletId))
    }
    @Test fun deletingASaleWithLaterReservedSpendingRequiresExactConsentBeforeAnyEffects() {
        val expenseId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val expense=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,expenseId,owner.value,buildJsonObject {
            put("id",expenseId);put("user_id",owner.value);put("created_at","2026-10-24T00:00:00Z");put("updated_at",now);put("occurred_at","2026-10-24T00:00:00Z");put("deleted_at",JsonNull);put("sync_version",0L)
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Spend");put("amount_minor",980L);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull);put("is_archived",false)
            put("reporting_amount_minor",980L);put("reporting_currency_code","VND");put("reporting_expense_minor",980L);put("reporting_income_minor",0L)
        },now,null,0)
        val raw=snapshot().let{it.copy(rows=it.rows+expense)};val saleConsent=(runCatching{planInvestmentSale(raw,request(),device,now)}.exceptionOrNull() as InvestmentSaleConfirmationRequired).review.consent
        val source=apply(raw,planInvestmentSale(raw,request().copy(consent=saleConsent),device,now).mutations)
        val r=deleting(source);val error=runCatching{planInvestmentTradeDeletion(source,r,device,now)}.exceptionOrNull()
        assertTrue(error is InvestmentTradeDeletionConfirmationRequired);val review=(error as InvestmentTradeDeletionConfirmationRequired).review
        assertEquals(30.toBigInteger(),review.comparison.changes.single().previousMinor);assertEquals(0.toBigInteger(),review.comparison.changes.single().proposedMinor)
        val plan=planInvestmentTradeDeletion(source,r.copy(consent=review.consent),device,now)
        assertEquals(MutationKind.DELETE,plan.mutations.single{it.first.id==investmentLedgerIdentity(expenseId,"cash-consumption-booked")}.second.kind)
        val after=apply(source,plan.mutations);assertTrue(planInvestmentTradeDeletion(after,r.copy(consent=review.consent),device,now).mutations.isEmpty())
    }
    @Test fun completedDeletionCannotHideAMissingPostingOrAnActiveProfitLeg() {
        val source=sale();val r=deleting(source);val after=apply(source,planInvestmentTradeDeletion(source,r,device,now).mutations)
        val missing=after.copy(rows=after.rows.filterNot{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(saleId,"cash-accrual-posting")})
        assertTrue(runCatching{planInvestmentTradeDeletion(missing,r,device,now)}.isFailure)
        val active=after.copy(rows=after.rows.map{row->if(row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id==investmentLedgerIdentity(saleId,"profit-loss"))row.copy(deletedAt=null,payload=JsonObject(row.payload+("deleted_at" to JsonNull))) else row})
        assertTrue(runCatching{planInvestmentTradeDeletion(active,r,device,now)}.isFailure)
    }
    @Test fun archivedAssetAndChannelDoNotPreventDeletingTheirExistingTradeHistory() {
        val source=sale().let{it.copy(rows=it.rows.map{row->if(row.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table))row.copy(payload=JsonObject(row.payload+("is_archived" to JsonPrimitive(true)))) else row})}
        assertEquals(now,planInvestmentTradeDeletion(source,deleting(source),device,now).trade.deletedAt)
    }
    @Test fun longAckPrecisionAndUnknownMetadataSurviveDeletionAndDoNotBreakCompletedRetry() {
        val original=sale();val r=deleting(original)
        val source=original.copy(rows=original.rows.map{row->row.copy(syncVersion=9007199254740993L,payload=JsonObject(row.payload+buildJsonObject {
            put("sync_version",9007199254740993L);put("future_flag","keep")
            for(key in listOf("created_at","occurred_at"))row.payload.financeRawString(key)?.let{put(key,it.replace("00Z","00.000Z"))}
        }))})
        val plan=planInvestmentTradeDeletion(source,r,device,now)
        assertEquals(JsonPrimitive("keep"),plan.trade.payload["future_flag"]);assertTrue(plan.mutations.all{it.second.baseVersion==9007199254740993L})
        assertTrue(planInvestmentTradeDeletion(apply(source,plan.mutations),r,device,now).mutations.isEmpty())
    }
    @Test fun deletingAForeignWalletSaleRemovesItsStoredLocalReceiptWithoutNewRates() {
        val foreignId="88888888-8888-8888-8888-888888888888"
        val foreign=WalletDraft(id=foreignId,name="JPY",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,before).record
        val raw=snapshot().let{it.copy(rows=it.rows+foreign)}
        val r=request().let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(foreign),draft=it.draft.copy(capitalWalletId=foreignId,accountingToCapitalRate="0.1"))}
        val source=apply(raw,planInvestmentSale(raw,r,device,now).mutations)
        val after=apply(source,planInvestmentTradeDeletion(source,deleting(source),device,now).mutations)
        val balances=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet,foreign),setOf(walletId,foreignId))!!
        assertEquals(900.toBigInteger(),balances[walletId]);assertEquals(0.toBigInteger(),balances[foreignId])
    }

    @Test fun anUnrelatedAutomaticAdjustmentInAnotherLanguageDoesNotBlockTradeDeletion() {
        val reserveId="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";val expenseId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val reserve=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,reserveId,owner.value,buildJsonObject {
            put("id",reserveId);put("user_id",owner.value);put("event_id","cccccccc-cccc-cccc-cccc-cccccccccccc");put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId);put("ledger_transaction_id",JsonNull)
            put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","unreconciled");put("cash_origin_raw_value","manual");put("amount_minor",1000L);put("currency_code","VND");put("accounting_amount_minor",1000L);put("accounting_currency_code","VND")
            put("occurred_at","2026-10-21T00:00:00Z");put("created_at","2026-10-21T00:00:00Z");put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
        },now,null,0)
        val expense=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,expenseId,owner.value,buildJsonObject {
            put("id",expenseId);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("occurred_at","2026-10-24T00:00:00Z");put("deleted_at",JsonNull);put("sync_version",0L)
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Spend");put("amount_minor",950L);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull);put("is_archived",false)
        },now,null,0)
        val raw=snapshot().let{it.copy(rows=it.rows.map{row->if(row.id==investmentSystemWalletId(owner))row.copy(payload=JsonObject(row.payload+("opening_balance_minor" to JsonPrimitive(1000L)))) else row}+reserve+expense)}
        val cash=InvestmentCashReadSnapshot(owner,raw.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        val source=apply(raw,planInvestmentFundEffects(cash,"VND",investmentFundUsageTimeline(cash,"VND"),"Previous device language",device,now).mutations)
        val r=deleting(source,buyId)
        val error=runCatching{planInvestmentTradeDeletion(source,r,device,now)}.exceptionOrNull()
        assertTrue("A language change must not look like corrupt fund history: "+error,error is InvestmentTradeDeletionConfirmationRequired)
        val review=(error as InvestmentTradeDeletionConfirmationRequired).review
        assertEquals(50.toBigInteger(),review.comparison.changes.single().previousMinor)
        assertEquals(0.toBigInteger(),review.comparison.changes.single().proposedMinor)
        assertEquals(now,planInvestmentTradeDeletion(source,r.copy(consent=review.consent),device,now).trade.deletedAt)
    }

    @Test fun deletingSaleProducesItsLiveIntentParentWithoutAddingEvidenceToFinancialChildren() {
        val source=sale();val request=deleting(source);val plan=planInvestmentTradeDeletion(source,request,device,now)
        val parent=localInvestmentTradePublicationParents(plan.trade).single()
        assertFalse(parent.deleted);assertEquals(investmentTradeIntentFingerprint(request.expectedTrade.payload),parent.fingerprint)
        assertTrue(plan.mutations.filter{it.first.entity!=CloudEntity.INVESTMENT_TRADE.table}.all{LOCAL_TRADE_PUBLICATION_PARENTS_KEY !in it.first.payload})
    }

}
