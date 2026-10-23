package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentPurchaseTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-23T00:00:00Z"
    private val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,0,device)
    private val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record
    private fun snapshot():InvestmentPurchaseSnapshot {
        val channelRow=InvestmentChannelRecord(channel,owner.value,"Shop","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val rawSystem=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record
        val system=rawSystem.copy(payload=JsonObject(rawSystem.payload+buildJsonObject {put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))
        return InvestmentPurchaseSnapshot(owner,listOf(channelRow,system,asset.toCloudRecord(),wallet))
    }
    private fun request()=InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,now,now),asset,LedgerWalletRecord.fromCloudRecord(wallet),null,"Reserve")
    private fun apply(s:InvestmentPurchaseSnapshot,p:InvestmentPurchasePlan)=s.copy(rows=s.rows.filterNot{row->p.mutations.any{it.first.entity==row.entity && it.first.id==row.id}}+p.mutations.map{it.first})
    @Test fun purchaseAmountIsTheTotalOrderAndNeverMultipliedByExactQuantity() {
        val p=planInvestmentPurchase(snapshot(),request(),device,now)
        assertEquals(3,p.mutations.size)
        assertEquals("2.5",p.trade.payload.financeRawString("position_quantity_after_decimal_string"))
        assertEquals(70L,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
        val ledger=p.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first
        assertEquals(70L,ledger.payload.financeRawLong("amount_minor"))
        assertEquals("investmentFunding",ledger.payload.financeRawString("settlement_role_raw_value"))
        assertEquals(30.toBigInteger(),financeWalletBalancesRaw(owner,listOf(ledger),listOf(wallet),setOf(walletId))?.get(walletId))
        assertFalse(p.review.requiresConfirmation)
    }
    @Test fun promotionalStockHasExactQuantityButNoWalletLedgerOrPosting() {
        val r=request();val p=planInvestmentPurchase(snapshot(),r.copy(draft=r.draft.copy(grossMinor=0,accountingMinor=0,fundingWalletId=null,fundingMinor=null),expectedWallet=null),device,now)
        assertEquals(1,p.mutations.size);assertEquals(0L,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
        assertEquals("2.5",p.trade.payload.financeRawString("position_quantity_after_decimal_string"))
        assertEquals(JsonNull,p.trade.payload["funding_ledger_transaction_id"])
    }
    @Test fun identicalRetryProvesCompleteResultAndNeverRequeuesIt() {
        val s=snapshot();val r=request();val p=planInvestmentPurchase(s,r,device,now)
        assertTrue(planInvestmentPurchase(apply(s,p),r,device,"2026-10-24T00:00:00Z").mutations.isEmpty())
    }
    private fun replace(s:InvestmentPurchaseSnapshot,row:CloudRecord)=s.copy(rows=s.rows.filterNot{it.entity==row.entity && it.id==row.id}+row)
    private fun changed(row:CloudRecord,fields:JsonObject)=row.copy(payload=JsonObject(row.payload+fields))
    @Test fun insufficientCurrentCashDoesNotAdmitAnUnfundedPurchase() {
        val s=replace(snapshot(),changed(wallet,buildJsonObject{put("opening_balance_minor",60L)}))
        val r=request().copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(s.rows.single{it.id==walletId}))
        val error=runCatching{planInvestmentPurchase(s,r,device,now)}.exceptionOrNull()
        assertTrue("insufficient cash must fail",error is TransactionValidationException)
    }
    @Test fun paidForeignAssetRequiresExactSourceRateAndConvertedTotal() {
        val foreign=asset.copy(currencyCode="JPY");val s=replace(snapshot(),foreign.toCloudRecord());val r=request()
        val correct=r.copy(expectedAsset=foreign,draft=r.draft.copy(grossMinor=7,sourceRate="10",rateProvider="manual"))
        assertEquals(70L,planInvestmentPurchase(s,correct,device,now).trade.payload.financeRawLong("accounting_gross_amount_minor"))
        for(rate in listOf(null,"0","-10","11"))assertTrue(runCatching{planInvestmentPurchase(s,correct.copy(draft=correct.draft.copy(sourceRate=rate)),device,now)}.isFailure)
    }
    @Test fun quantityMustBePositiveRepresentableAndUnitCannotBeBlank() {
        for(quantity in listOf("0","-1","NaN","1e999999"))assertTrue(runCatching{val r=request();planInvestmentPurchase(snapshot(),r.copy(draft=r.draft.copy(quantity=quantity)),device,now)}.isFailure)
        val r=request();assertTrue(runCatching{planInvestmentPurchase(snapshot(),r.copy(draft=r.draft.copy(unit="  ")),device,now)}.isFailure)
    }
    @Test fun exactLongMaximumPurchaseNeverRoundsThroughDouble() {
        val raw=changed(wallet,buildJsonObject{put("opening_balance_minor",Long.MAX_VALUE)})
        val r=request();val p=planInvestmentPurchase(replace(snapshot(),raw),r.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(raw),draft=r.draft.copy(grossMinor=Long.MAX_VALUE,accountingMinor=Long.MAX_VALUE,fundingMinor=Long.MAX_VALUE)),device,now)
        assertEquals(Long.MAX_VALUE,p.trade.payload.financeRawLong("position_cost_basis_after_minor"))
    }
    @Test fun incompleteKnownResultIsHeldInsteadOfRepairingItsMissingPosting() {
        val s=snapshot();val r=request();val p=planInvestmentPurchase(s,r,device,now)
        val partial=apply(s,p).let{it.copy(rows=it.rows.filterNot{row->row.entity==CloudEntity.INVESTMENT_POSTING.table})}
        assertTrue(runCatching{planInvestmentPurchase(partial,r,device,now)}.isFailure)
    }
    @Test fun occupiedFundingIdentityCannotBeOverwrittenEvenWithInvestmentLookingRole() {
        val r=request();val ledger=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,investmentLedgerIdentity(id,"funding"),owner.value,buildJsonObject {
            put("id",investmentLedgerIdentity(id,"funding"));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
            put("sync_version",0L);put("settlement_role_raw_value","investmentFunding");put("amount_minor",1L)
        },now,null,0)
        assertTrue(runCatching{planInvestmentPurchase(snapshot().copy(rows=snapshot().rows+ledger),r,device,now)}.isFailure)
    }
    private fun reserve(amount:Long)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,"77777777-7777-7777-7777-777777777777",owner.value,buildJsonObject {
        put("id","77777777-7777-7777-7777-777777777777");put("user_id",owner.value);put("event_id","88888888-8888-8888-8888-888888888888")
        put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId);put("ledger_transaction_id",JsonNull)
        put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",amount);put("currency_code","VND");put("accounting_amount_minor",amount);put("accounting_currency_code","VND")
        put("occurred_at","2026-10-22T00:00:00Z");put("created_at","2026-10-22T00:00:00Z");put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
    },now,null,0)
    @Test fun reservedMoneyNeedsExactConsentAndSurvivesGlobalOrdinaryRebuild() {
        val s=snapshot().let{it.copy(rows=it.rows+reserve(60))};val r=request()
        val error=runCatching{planInvestmentPurchase(s,r,device,now)}.exceptionOrNull()
        assertTrue("purchase must request fund consent",error is InvestmentPurchaseConfirmationRequired)
        val review=(error as InvestmentPurchaseConfirmationRequired).review
        assertEquals(30.toBigInteger(),review.fundingUsage?.investmentToUseMinor)
        val p=planInvestmentPurchase(s,r.copy(consent=review.consent),device,now)
        val after=apply(s,p);val cash=InvestmentCashReadSnapshot(owner,after.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        val timeline=investmentFundUsageTimeline(cash,"VND")
        assertEquals(30.toBigInteger(),timeline.usages[investmentLedgerIdentity(id,"funding")]?.investmentToUseMinor)
        assertEquals(30.toBigInteger(),investmentCashAllocation(cash.walletSnapshot(),"VND").locations.single{it.walletId==walletId}.originalBookedMinor)
        assertTrue(planInvestmentPurchase(after,r.copy(consent=review.consent),device,now).mutations.isEmpty())
        val changed=replace(s,changed(wallet,buildJsonObject{put("opening_balance_minor",101L)}))
        assertTrue(runCatching{planInvestmentPurchase(changed,r.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(changed.rows.single{it.id==walletId}),consent=review.consent),device,now)}.exceptionOrNull() is InvestmentPurchaseConfirmationRequired)
    }
    @Test fun backdatedPurchaseReleasesTheEarlierLotAndRecomputesLaterSaleProfit() {
        val firstRequest=request().let{it.copy(draft=it.draft.copy(quantity="1",occurredAt="2026-10-22T00:00:00Z"))}
        val first=planInvestmentPurchase(snapshot(),firstRequest,device,now);var s=apply(snapshot(),first)
        val saleId="99999999-9999-9999-9999-999999999999"
        val sale=changed(first.trade,buildJsonObject{
            put("id",saleId);put("kind_raw_value","sell");put("gross_amount_minor",100L);put("accounting_gross_amount_minor",100L)
            put("funding_wallet_id",JsonNull);put("funding_wallet_currency_code",JsonNull);put("funding_wallet_amount_minor",JsonNull)
            put("funding_ledger_transaction_id",JsonNull);put("capital_return_wallet_id",walletId);put("capital_return_wallet_currency_code","VND")
            put("occurred_at",now)
        }).copy(id=saleId)
        s=s.copy(rows=s.rows+sale)
        val rebuilt=rebuildInvestmentAssetUnitHistory(InvestmentAssetSnapshot(owner,s.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentAssetSnapshot.entities}),asset,"box",device,now,false)
        s=s.copy(rows=s.rows.filterNot{row->rebuilt.any{it.entity==row.entity && it.id==row.id}}+rebuilt)
        val newId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val r=request().let{it.copy(draft=it.draft.copy(id=newId,quantity="1",grossMinor=20,accountingMinor=20,fundingMinor=20,occurredAt="2026-10-21T00:00:00Z"))}
        val p=planInvestmentPurchase(s,r,device,now)
        val updated=p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_TRADE.table && it.first.id==saleId}.first
        assertEquals(20L,updated.payload.financeRawLong("released_cost_basis_minor"));assertEquals(80L,updated.payload.financeRawLong("realized_profit_loss_minor"))
        val zeroProfit=r.copy(draft=r.draft.copy(grossMinor=100,accountingMinor=100,fundingMinor=100))
        val cleared=planInvestmentPurchase(s,zeroProfit,device,now)
        val tombstones=cleared.mutations.filter{it.first.deletedAt!=null}
        assertEquals(3,tombstones.size);assertTrue(tombstones.all{it.second.kind==MutationKind.DELETE})

    }

    @Test fun foreignFundingUsesTheInverseStoredMajorUnitRateAndRejectsWrongMinor() {
        val foreign=changed(wallet,buildJsonObject{put("currency_code","JPY")})
        val s=replace(snapshot(),foreign);val r=request().let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(foreign),draft=it.draft.copy(fundingMinor=7,fundingToAccountingRate="10"))}
        val p=planInvestmentPurchase(s,r,device,now)
        assertEquals(7L,p.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload.financeRawLong("amount_minor"))
        assertTrue(runCatching{planInvestmentPurchase(s,r.copy(draft=r.draft.copy(fundingMinor=70)),device,now)}.isFailure)
    }
    @Test fun accountingForeignReserveCannotBeSpentByComparingDifferentMinorUnits() {
        val foreign=changed(wallet,buildJsonObject{put("currency_code","JPY");put("opening_balance_minor",10L)})
        val earmark=changed(reserve(60),buildJsonObject{put("currency_code","JPY");put("amount_minor",6L)})
        val s=replace(snapshot(),foreign).let{it.copy(rows=it.rows+earmark)}
        val r=request().let{it.copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(foreign),draft=it.draft.copy(fundingMinor=7,fundingToAccountingRate="10"))}
        assertEquals(InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION,(runCatching{planInvestmentPurchase(s,r,device,now)}.exceptionOrNull() as? InvestmentFundTimelineException)?.reason)
        val ordinary=r.copy(draft=r.draft.copy(grossMinor=30,accountingMinor=30,fundingMinor=3))
        assertFalse(planInvestmentPurchase(s,ordinary,device,now).review.requiresConfirmation)
    }
    @Test fun cardFundingUsesExactCreditLimitRatherThanOpeningCash() {
        val card=changed(wallet,buildJsonObject{put("kind_raw_value","creditCard");put("opening_balance_minor",0L)})
        fun source(limit:Long)=replace(snapshot(),card).let{it.copy(rows=it.rows+CreditCardProfileRecord("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",owner.value,"Bank","visa","1234",limit,20,10,null,walletId,null,false,now,now,null,0,device).toCloudRecord())}
        val r=request().copy(expectedWallet=LedgerWalletRecord.fromCloudRecord(card))
        assertEquals(3,planInvestmentPurchase(source(70),r,device,now).mutations.size)
        assertEquals(TransactionValidationError.CREDIT_LIMIT_EXCEEDED,(runCatching{planInvestmentPurchase(source(69),r,device,now)}.exceptionOrNull() as? TransactionValidationException)?.reason)
    }
    @Test fun ordinarySaveReplaysAndRetainsPurchaseFundingConsumption() {
        val s=snapshot().let{it.copy(rows=it.rows+reserve(60))};val r=request()
        val review=(runCatching{planInvestmentPurchase(s,r,device,now)}.exceptionOrNull() as InvestmentPurchaseConfirmationRequired).review
        val saved=apply(s,planInvestmentPurchase(s,r.copy(consent=review.consent),device,now))
        val ordinary=saved.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.let{row->changed(row,buildJsonObject {
            put("id","cccccccc-cccc-cccc-cccc-cccccccccccc");put("primary_kind_raw_value","income");put("settlement_role_raw_value",JsonNull)
            put("amount_minor",1L);put("reporting_amount_minor",1L);put("reporting_income_minor",1L);put("occurred_at","2026-10-24T00:00:00Z")
        }).copy(id="cccccccc-cccc-cccc-cccc-cccccccccccc")}

        val cash=InvestmentCashReadSnapshot(owner,saved.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        val usage=reviewInvestmentFundUsage(cash,"VND",ordinary)
        val effects=planInvestmentFundUsage(cash,"VND",ordinary,usage.consent,"Reserve",device,now)
        assertTrue("ordinary rebuild must retain the purchase consumption without repair",effects.mutations.isEmpty())
    }
    @Test fun preexistingCanonicalDriftDoesNotBecomeAnImplicitRepairDuringNewPurchase() {
        val s=snapshot();val first=planInvestmentPurchase(s,request(),device,now);val after=apply(s,first)
        val ledger=after.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        val corrupt=replace(after,changed(ledger,buildJsonObject{put("amount_minor",69L)}))
        val next=request().let{it.copy(draft=it.draft.copy(id="dddddddd-dddd-dddd-dddd-dddddddddddd",grossMinor=1,accountingMinor=1,fundingMinor=1))}
        assertTrue(runCatching{planInvestmentPurchase(corrupt,next,device,now)}.isFailure)
    }
    @Test fun ackAndUnknownMetadataAreRetainedOnExactNoWriteRetry() {
        val s=snapshot();val r=request();val after=apply(s,planInvestmentPurchase(s,r,device,now)).let{it.copy(rows=it.rows.map{row->changed(row,buildJsonObject{
            put("sync_version",9007199254740993L);put("future_flag","preserve")
        }).copy(syncVersion=9007199254740993L)})}
        val p=planInvestmentPurchase(after,r,device,"2026-10-24T00:00:00Z")
        assertTrue(p.mutations.isEmpty());assertEquals(9007199254740993L,p.trade.syncVersion);assertEquals("preserve",p.trade.payload.financeRawString("future_flag"))
    }

    @Test fun staleFundEffectsFromOtherEventsCannotBeRepairedByANewPurchase() {
        val s=snapshot().let{it.copy(rows=it.rows+reserve(60))};val r=request()
        val review=(runCatching{planInvestmentPurchase(s,r,device,now)}.exceptionOrNull() as InvestmentPurchaseConfirmationRequired).review
        val first=apply(s,planInvestmentPurchase(s,r.copy(consent=review.consent),device,now))
        val consumption=first.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("role_raw_value")=="cashConsumption"}
        val corrupt=replace(first,changed(consumption,buildJsonObject{put("amount_minor",-29L);put("accounting_amount_minor",-29L)}))
        val next=r.copy(draft=r.draft.copy(id="eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",grossMinor=0,accountingMinor=0,fundingWalletId=null,fundingMinor=null),expectedWallet=null)
        assertTrue("unrelated canonical drift must hold before offering consent",runCatching{planInvestmentPurchase(corrupt,next,device,now)}.exceptionOrNull() is InvestmentAssetException)
    }
    @Test fun allSourceVersionsMustBeReadableAndNonNegative() {
        val r=request();val invalid=wallet.copy(syncVersion=-1,payload=JsonObject(wallet.payload+("sync_version" to JsonPrimitive(-1L))))
        assertTrue(runCatching{planInvestmentPurchase(replace(snapshot(),invalid),r,device,now)}.isFailure)
    }

    @Test fun equivalentServerTimestampPrecisionDoesNotBreakKnownResultProof() {
        val s=snapshot();val r=request();val after=apply(s,planInvestmentPurchase(s,r,device,now)).let{it.copy(rows=it.rows.map{row->changed(row,buildJsonObject{
            for(key in listOf("created_at","occurred_at"))row.payload.financeRawString(key)?.let{put(key,it.replace("00Z","00.000Z"))}
        })})}
        assertTrue(planInvestmentPurchase(after,r,device,now).mutations.isEmpty())
    }

}
