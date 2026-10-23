package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentSaleTest {
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
    @Test fun saleTotalReturnsFifoCapitalAndBooksOnlyRealizedProfitAsInvestmentCash() {
        val s=snapshot();val p=planInvestmentSale(s,request(),device,now)
        assertEquals("sell",p.trade.payload.financeRawString("kind_raw_value"));assertEquals(50L,p.trade.payload.financeRawLong("released_cost_basis_minor"));assertEquals(30L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals("1",p.trade.payload.financeRawString("position_quantity_after_decimal_string"));assertEquals(50L,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
        val after=apply(s,p.mutations);val ledger=after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        assertEquals(980.toBigInteger(),financeWalletBalancesRaw(owner,ledger,listOf(wallet),setOf(walletId))?.get(walletId))
        val cash=InvestmentCashReadSnapshot(owner,after.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        assertEquals(30.toBigInteger(),investmentCashAllocation(cash.walletSnapshot(),"VND").locations.single{it.walletId==walletId}.originalBookedMinor)
    }
    @Test fun totalLossConsumesStockWithoutInventingAnOrdinaryWalletReceipt() {
        val p=planInvestmentSale(snapshot(),request(gross=0,quantity="2"),device,now)
        assertEquals(100L,p.trade.payload.financeRawLong("released_cost_basis_minor"));assertEquals(-100L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals(JsonNull,p.trade.payload["capital_return_wallet_id"]);assertEquals(JsonNull,p.trade.payload["capital_return_ledger_transaction_id"])
        val loss=p.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first
        assertEquals("expense",loss.payload.financeRawString("primary_kind_raw_value"));assertEquals(investmentSystemWalletId(owner),loss.payload.financeRawReference("source_wallet_id").id)
    }
    @Test fun aGiftLotCanBeSoldWithZeroCostAndTheWholeReceiptAsProfit() {
        val p=planInvestmentSale(snapshot(cost=0),request(),device,now)
        assertEquals(0L,p.trade.payload.financeRawLong("released_cost_basis_minor"));assertEquals(80L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
    }
    @Test fun exactKnownResultRetriesWithoutAnyMutation() {
        val s=snapshot();val r=request();val p=planInvestmentSale(s,r,device,now)
        assertTrue(planInvestmentSale(apply(s,p.mutations),r,device,"2026-10-24T00:00:00Z").mutations.isEmpty())
    }
    @Test fun aLossReturnsCapitalAndSubtractsOnlyItsLossSoTheWalletReceivesTheSaleTotal() {
        val s=snapshot();val p=planInvestmentSale(s,request(gross=20),device,now)
        assertEquals(-30L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
        val after=apply(s,p.mutations)
        assertEquals(920.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},listOf(wallet),setOf(walletId))?.get(walletId))
        assertEquals(-30L,p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table && it.first.payload.financeRawString("role_raw_value")=="cashAccrual"}.first.payload.financeRawLong("amount_minor"))
    }
    @Test fun oversellOrDifferentUnitCannotConsumeStockFromAnotherUnitBucket() {
        for(r in listOf(request(quantity="2.00000001"),request(unit="pack"))) {
            assertEquals(InvestmentAccountingError.INSUFFICIENT_POSITION,(runCatching{planInvestmentSale(snapshot(),r,device,now)}.exceptionOrNull() as? InvestmentAccountingException)?.reason)
        }
    }
    @Test fun saleBeforeItsFirstAcquisitionCannotBorrowFutureStock() {
        val r=request();assertEquals(InvestmentAccountingError.INSUFFICIENT_POSITION,(runCatching{planInvestmentSale(snapshot(),r.copy(draft=r.draft.copy(occurredAt="2026-10-21T00:00:00Z")),device,now)}.exceptionOrNull() as? InvestmentAccountingException)?.reason)
    }
    @Test fun fractionalLotsReleaseAnExactPartialCostAndRetainTheRest() {
        val p=planInvestmentSale(snapshot(cost=100,quantity="2.5"),request(gross=30,quantity="0.25"),device,now)
        assertEquals(10L,p.trade.payload.financeRawLong("released_cost_basis_minor"));assertEquals(20L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals("2.25",p.trade.payload.financeRawString("position_quantity_after_decimal_string"));assertEquals(90L,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
    }
    @Test fun foreignCapitalWalletUsesItsStoredDirectRateForCostAndGrossSeparately() {
        val foreignId="88888888-8888-8888-8888-888888888888"
        val foreign=WalletDraft(id=foreignId,name="JPY",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,before).record
        val s=snapshot().let{it.copy(rows=it.rows+foreign)};val r=request().let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(foreign),draft=it.draft.copy(capitalWalletId=foreignId,accountingToCapitalRate="0.1"))}
        val p=planInvestmentSale(s,r,device,now)
        assertEquals(5L,p.trade.payload.financeRawLong("capital_return_wallet_amount_minor"))
        val ledger=p.mutations.map{it.first}.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        assertEquals(8.toBigInteger(),financeWalletBalancesRaw(owner,ledger,listOf(foreign),setOf(foreignId))?.get(foreignId))
        assertTrue(runCatching{planInvestmentSale(s,r.copy(draft=r.draft.copy(accountingToCapitalRate=null)),device,now)}.isFailure)
    }
    @Test fun aCardCannotReceiveSaleCapitalAndALossCannotSelectAnyWallet() {
        val card=wallet.copy(payload=JsonObject(wallet.payload+("kind_raw_value" to JsonPrimitive("creditCard"))))
        val s=snapshot().let{it.copy(rows=it.rows.filterNot{row->row.id==walletId}+card)}
        assertTrue(runCatching{planInvestmentSale(s,request().copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(card)),device,now)}.isFailure)
        val r=request(gross=0);assertTrue(runCatching{planInvestmentSale(snapshot(),r.copy(draft=r.draft.copy(capitalWalletId=walletId),expectedWallet=LedgerWalletRecord.fromCloudRecord(wallet)),device,now)}.isFailure)
    }
    @Test fun wholeLongMaximumBasisAndReceiptHaveNoFloatingPointRounding() {
        val p=planInvestmentSale(snapshot(cost=Long.MAX_VALUE,quantity="1"),request(gross=Long.MAX_VALUE).copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(wallet.copy(payload=JsonObject(wallet.payload+("opening_balance_minor" to JsonPrimitive(Long.MAX_VALUE)))))),device,now)
        assertEquals(Long.MAX_VALUE,p.trade.payload.financeRawLong("released_cost_basis_minor"));assertEquals(0L,p.trade.payload.financeRawLong("realized_profit_loss_minor"))
    }

    @Test fun knownResultCannotRepairAMissingProfitPostingOrReuseAnOccupiedBuyIdentity() {
        val s=snapshot();val r=request();val p=planInvestmentSale(s,r,device,now);val after=apply(s,p.mutations)
        val damaged=after.copy(rows=after.rows.filterNot{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("role_raw_value")=="realizedProfit"})
        assertTrue(runCatching{planInvestmentSale(damaged,r,device,now)}.isFailure)
        assertTrue(runCatching{planInvestmentSale(s,r.copy(draft=r.draft.copy(id=buyId)),device,now)}.isFailure)
    }
    @Test fun equivalentUnitLabelsUseTheSameBucketAndSoldOutStockCannotBeSoldAgain() {
        val s=snapshot();val r=request(gross=100,quantity="2",unit="  BOX  ");val p=planInvestmentSale(s,r,device,now)
        assertEquals("0",p.trade.payload.financeRawString("position_quantity_after_decimal_string"))
        val after=apply(s,p.mutations);val next=r.copy(draft=r.draft.copy(id="99999999-9999-9999-9999-999999999999",quantity="0.1",createdAt="2026-10-24T00:00:00Z",occurredAt="2026-10-24T00:00:00Z"))
        assertEquals(InvestmentAccountingError.INSUFFICIENT_POSITION,(runCatching{planInvestmentSale(after,next,device,now)}.exceptionOrNull() as? InvestmentAccountingException)?.reason)
        assertTrue(planInvestmentSale(after,r,device,now).mutations.isEmpty())
    }
    @Test fun semanticAckPrecisionAndUnknownFieldsDoNotProduceWritesOnRetry() {
        val s=snapshot();val r=request();val after=apply(s,planInvestmentSale(s,r,device,now).mutations).let{it.copy(rows=it.rows.map{row->
            row.copy(syncVersion=9007199254740993L,payload=JsonObject(row.payload+buildJsonObject {
                put("sync_version",9007199254740993L);put("future_flag","preserve")
                for(key in listOf("created_at","occurred_at"))row.payload.financeRawString(key)?.let{put(key,it.replace("00Z","00.000Z"))}
            }))
        })}
        val p=planInvestmentSale(after,r,device,now);assertTrue(p.mutations.isEmpty());assertEquals(9007199254740993L,p.trade.syncVersion)
    }
    @Test fun saleThatChangesHistoricalFundUseRequiresAReviewAndExplicitConsent() {
        val s=snapshot();val r=request();val ordinaryId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val ordinary=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,ordinaryId,owner.value,buildJsonObject {
            put("id",ordinaryId);put("user_id",owner.value);put("created_at","2026-10-24T00:00:00Z");put("updated_at",now);put("occurred_at","2026-10-24T00:00:00Z");put("deleted_at",JsonNull);put("sync_version",0L)
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Spend")
            put("amount_minor",980L);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull)
            put("is_archived",false);put("reporting_amount_minor",980L);put("reporting_currency_code","VND");put("reporting_expense_minor",980L);put("reporting_income_minor",0L)
        },now,null,0)
        // Before the sale there is no reserved cash; the backdated sale now
        // makes30 of the later ordinary expense consume realized investment cash.
        val source=s.copy(rows=s.rows+ordinary)
        val error=runCatching{planInvestmentSale(source,r,device,now)}.exceptionOrNull()
        assertTrue(error is InvestmentSaleConfirmationRequired)
        val review=(error as InvestmentSaleConfirmationRequired).review
        assertEquals(30.toBigInteger(),review.comparison.proposed.usages[ordinaryId]?.investmentToUseMinor)
        val plan=planInvestmentSale(source,r.copy(consent=review.consent),device,now)
        assertTrue(plan.mutations.any{it.first.entity==CloudEntity.INVESTMENT_POSTING.table && it.first.payload.financeRawString("role_raw_value")=="cashConsumption"})
        assertTrue(planInvestmentSale(apply(source,plan.mutations),r.copy(consent=review.consent),device,now).mutations.isEmpty())
    }

    @Test fun nonStringHistoricalUnitCannotBecomeAnImplicitLegacyUnitDuringSale() {
        val s=snapshot().let{it.copy(rows=it.rows.map{row->if(row.entity==CloudEntity.INVESTMENT_TRADE.table)row.copy(payload=JsonObject(row.payload+("unit_label" to buildJsonObject{put("bad",true)}))) else row})}
        val error=runCatching{planInvestmentSale(s,request(),device,now)}.exceptionOrNull()
        assertEquals(InvestmentAssetError.UNREADABLE_SOURCE,(error as? InvestmentAssetException)?.reason)
    }
    @Test fun aNewPurchaseAlsoHoldsRatherThanExtendingHistoryWithAnUnreadableUnit() {
        val s=snapshot().let{it.copy(rows=it.rows.map{row->if(row.entity==CloudEntity.INVESTMENT_TRADE.table)row.copy(payload=JsonObject(row.payload+("unit_label" to JsonPrimitive(5)))) else row})}
        val r=InvestmentPurchaseRequest(InvestmentPurchaseDraft(saleId,assetId,"1","box",1,1,"VND",null,null,null,walletId,1,null,null,now,now),asset,LedgerWalletRecord.fromCloudRecord(wallet),null,"Reserve")
        assertEquals(InvestmentAssetError.UNREADABLE_SOURCE,(runCatching{planInvestmentPurchase(s,r,device,now)}.exceptionOrNull() as? InvestmentAssetException)?.reason)
    }

    @Test fun movingTheSameReservedTotalBetweenLaterExpensesStillRequiresExplicitConsent() {
        val reserveId="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        val reserve=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,reserveId,owner.value,buildJsonObject {
            put("id",reserveId);put("user_id",owner.value);put("event_id","cccccccc-cccc-cccc-cccc-cccccccccccc")
            put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId);put("ledger_transaction_id",JsonNull)
            put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
            put("amount_minor",50L);put("currency_code","VND");put("accounting_amount_minor",50L);put("accounting_currency_code","VND")
            put("occurred_at","2026-10-21T00:00:00Z");put("created_at","2026-10-21T00:00:00Z");put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
        },now,null,0)
        fun expense(id:String,amount:Long,date:String)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",date);put("updated_at",now);put("occurred_at",date);put("deleted_at",JsonNull);put("sync_version",0L)
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Spend")
            put("amount_minor",amount);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull)
            put("is_archived",false);put("reporting_amount_minor",amount);put("reporting_currency_code","VND");put("reporting_expense_minor",amount);put("reporting_income_minor",0L)
        },now,null,0)
        val a="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";val b="dddddddd-dddd-dddd-dddd-dddddddddddd"
        val raw=snapshot().let{it.copy(rows=it.rows+reserve+expense(a,900,"2026-10-23T12:00:00Z")+expense(b,50,"2026-10-24T00:00:00Z"))}
        val cash=InvestmentCashReadSnapshot(owner,raw.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        val initial=investmentFundUsageTimeline(cash,"VND")
        assertEquals(50.toBigInteger(),initial.usages[a]?.investmentToUseMinor)
        val source=apply(raw,planInvestmentFundEffects(cash,"VND",initial,"Reserve",device,now).mutations)
        val error=runCatching{planInvestmentSale(source,request(),device,now)}.exceptionOrNull()
        assertTrue("Moving reserved consumption between expenses needs consent: $error",error is InvestmentSaleConfirmationRequired)
        val review=(error as InvestmentSaleConfirmationRequired).review
        assertEquals(50.toBigInteger(),review.comparison.changes.single().previousMinor)
        assertEquals(50.toBigInteger(),review.comparison.changes.single().proposedMinor)
        assertEquals(0.toBigInteger(),review.comparison.proposed.usages[a]?.investmentToUseMinor ?: 0.toBigInteger())
        assertEquals(50.toBigInteger(),review.comparison.proposed.usages[b]?.investmentToUseMinor)
        val plan=planInvestmentSale(source,request().copy(consent=review.consent),device,now)
        assertTrue(plan.mutations.any{it.first.entity==CloudEntity.INVESTMENT_POSTING.table && it.first.payload.financeRawString("role_raw_value")=="cashConsumption"})
        assertTrue(planInvestmentSale(apply(source,plan.mutations),request(),device,now).mutations.isEmpty())
    }

}
