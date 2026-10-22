package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentFundUsageTimelineTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun time(second:Int)="2026-10-22T00:00:"+second.toString().padStart(2,'0')+"Z"
    private fun wallet(key:Int=1,opening:Long=100,kind:WalletKind=WalletKind.CASH,code:String="VND")=
        WalletDraft(id=id(key),name="Wallet",kind=WalletKind.CASH,currencyCode=code,openingBalanceMinor=opening).toMutation(owner,null,device,time(0)).record
            .let{it.copy(payload=JsonObject(it.payload+("kind_raw_value" to JsonPrimitive(kind.wireValue))))}
    private fun row(entity:CloudEntity,key:Int,fields:JsonObject)=CloudRecord(entity.table,id(key),owner.value,JsonObject(buildJsonObject {
        put("id",id(key));put("user_id",owner.value);put("created_at",time(0));put("updated_at",time(0));put("deleted_at",JsonNull);put("sync_version",0L)
    }+fields),time(0),null,0)
    private fun ledger(key:Int,kind:String="expense",amount:Long=70,second:Int=2,from:Int=1,to:Int?=null,subtype:String?=null,role:String?=null)=row(CloudEntity.LEDGER_TRANSACTION,key,buildJsonObject {
        put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_currency_code","VND")
        put("source_wallet_id",id(from));put("destination_wallet_id",to?.let{JsonPrimitive(id(it))} ?: JsonNull)
        put("transfer_subtype_raw_value",subtype?.let(::JsonPrimitive) ?: JsonNull);put("settlement_role_raw_value",role?.let(::JsonPrimitive) ?: JsonNull)
        put("occurred_at",time(second));put("created_at",time(second));put("is_archived",false)
    })
    private fun cash(key:Int=101,amount:Long=60,bucket:String="booked",role:String="cashAccrual",origin:String="derived",wallet:Int=1,event:Int=10,second:Int=1)=row(CloudEntity.INVESTMENT_POSTING,key,buildJsonObject {
        put("wallet_id",id(wallet));put("event_id",id(event));put("ledger_transaction_id",id(event));put("role_raw_value",role)
        put("cash_bucket_raw_value",bucket);put("cash_origin_raw_value",origin);put("amount_minor",amount);put("accounting_amount_minor",amount)
        put("currency_code","VND");put("accounting_currency_code","VND");put("occurred_at",time(second));put("created_at",time(second))
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun snapshot(vararg rows:CloudRecord)=InvestmentCashReadSnapshot(owner,rows.toList())
    private fun read(vararg rows:CloudRecord)=investmentFundUsageTimeline(snapshot(*rows),"VND")
    private fun usage(result:InvestmentFundTimeline,event:Int=20)=result.usages.getValue(id(event))

    @Test fun ordinaryThenBookedThenUnreconciledUsesHistoricalCashAndNeverCountsDerivedUsageTwice() {
        val base=listOf(wallet(),cash(),ledger(20))
        val result=read(*base.toTypedArray());val use=usage(result)
        assertEquals(n(40),use.ordinaryAvailableMinor);assertEquals(n(30),use.bookedToUseMinor);assertEquals(n(0),use.unreconciledToUseMinor)
        assertEquals(n(30),result.availableByWalletId[id(1)]);assertEquals(n(30),result.actualByWalletId[id(1)])
        assertEquals(result,read(*(base+cash(102,-30,role="cashConsumption",event=20,second=2)).toTypedArray()))
        assertEquals(result,read(*(base+cash(103,-30,role="cashTransfer",event=20,second=2)).toTypedArray()))
    }
    @Test fun laterIncomeDoesNotEraseEarlierUsageAndChangingItsDateRestoresDownstreamInvestment() {
        val income=ledger(30,"income",943,4)
        val source=snapshot(wallet(opening=2090),ledger(10,"income",4290,1,role="investmentCapitalReturn"),cash(amount=3399),ledger(20,amount=4000,second=3),income)
        val result=compareInvestmentFundUsageTimeline(source,"VND",income.id,income.with("occurred_at",JsonPrimitive(time(2))))
        assertEquals(n(1019),usage(result.current).investmentToUseMinor);assertEquals(n(76),usage(result.proposed).investmentToUseMinor)
        val change=result.primaryChange!!;assertEquals(id(1),change.walletId);assertEquals(n(943),change.restoreMinor);assertEquals(n(3323),change.remainingInvestmentMinor)
        assertEquals(n(1019),change.previousMinor);assertEquals(n(76),change.proposedMinor)
    }
    @Test fun deletingIncomeOrAnExpenseReplaysAllLaterOutflowsWithoutUsingSavedConsumption() {
        val income=ledger(11,"income",40,1);val expense=ledger(20);val later=ledger(30,amount=20,second=3)
        val source=snapshot(wallet(),cash(),income,expense,later)
        val removed=compareInvestmentFundUsageTimeline(source,"VND",income.id,null)
        assertEquals(n(10),removed.primaryChange!!.previousMinor);assertEquals(n(50),removed.primaryChange!!.proposedMinor)
        val deleted=compareInvestmentFundUsageTimeline(source,"VND",expense.id,null)
        assertEquals(n(10),deleted.primaryChange!!.restoreMinor);assertEquals(n(120),deleted.proposed.actualByWalletId[id(1)])
    }
    @Test fun manualTransferAllocationIsRetainedAndInternalRealCashMovementCarriesReservedFundsToOwnedDestination() {
        val result=read(wallet(),wallet(2,0),cash(role="cashTransfer",origin="manual"),ledger(20,"transfer",70,to=2,subtype="internalTransfer"),ledger(30,amount=20,second=3,from=2))
        assertEquals(n(30),usage(result).investmentToUseMinor);assertFalse(result.usages.containsKey(id(30)))
        assertEquals(n(30),result.availableByWalletId[id(1)]);assertEquals(n(30),result.availableByWalletId[id(2)])
        assertEquals(n(50),result.actualByWalletId[id(2)])
    }
    @Test fun creditCardDestinationConsumesInsteadOfMovingAllocationAndSelfTransferHasZeroNetEffect() {
        val card=read(wallet(),wallet(2,999,WalletKind.CREDIT_CARD),cash(),ledger(20,"transfer",70,to=2,subtype="internalTransfer"))
        assertEquals(n(30),usage(card).investmentToUseMinor);assertFalse(card.availableByWalletId.containsKey(id(2)))
        val self=read(wallet(),cash(),ledger(20,"transfer",70,to=1,subtype="internalTransfer"))
        assertTrue(self.usages.isEmpty());assertEquals(n(100),self.actualByWalletId[id(1)]);assertEquals(n(60),self.availableByWalletId[id(1)])
    }
    @Test fun ordinaryDebtResaleFamilyAndNoncashSharedObligationsUseTheSharedActualCashRules() {
        val repay=ledger(20,"transfer",70,subtype="debt").with("debt_intent_raw_value",JsonPrimitive("repay"))
        assertEquals(n(30),usage(read(wallet(),cash(),repay)).investmentToUseMinor)
        val resale=repay.with("debt_intent_raw_value",JsonPrimitive("lend")).with("settlement_role_raw_value",JsonPrimitive("resaleReceivable")).with("reporting_expense_minor",JsonPrimitive(50L))
        assertEquals(n(10),usage(read(wallet(),cash(),resale)).investmentToUseMinor)
        val shared=repay.with("settlement_role_raw_value",JsonPrimitive("sharedExpensePayable"))
        assertTrue(read(wallet(),cash(),shared).usages.isEmpty())
        val family=ledger(20,"transfer",70,to=2,subtype="familyTransfer")
        assertEquals(n(30),usage(read(wallet(),wallet(2,0),cash(),family)).investmentToUseMinor)
    }
    @Test fun unreconciledUsageAddsVirtualSourceCashAndDebitsSystemExactlyOnceIgnoringOldAdjustment() {
        val system=wallet().copy(id=investmentSystemWalletId(owner)).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("id",it.id);put("kind_raw_value","investment");put("opening_balance_minor",100L);put("system_purpose_raw_value","investmentProfit")}))}
        val adjustment=ledger(40,"transfer",20,to=1,subtype="internalTransfer",role="investmentReserveUse").with("source_wallet_id",JsonPrimitive(system.id))
        val result=read(wallet(opening=40),system,cash(amount=60,bucket="unreconciled"),ledger(20,amount=60),adjustment)
        assertEquals(n(20),usage(result).unreconciledToUseMinor);assertEquals(n(0),result.actualByWalletId[id(1)])
        assertEquals(n(80),result.actualByWalletId[system.id]);assertEquals(n(40),result.availableByWalletId[id(1)])
    }
    @Test fun postingPriorityThenCreationThenUnsignedUuidDeterministicallyAtTheSameOccurrence() {
        val expense=ledger(20,second=1);val laterCreatedCash=cash().with("created_at",JsonPrimitive(time(2)))
        assertTrue(read(wallet(),laterCreatedCash,expense).usages.isEmpty())
        assertEquals(n(30),usage(read(wallet(),cash(),expense)).investmentToUseMinor)
        val a=ledger(20,amount=40,second=2);val b=ledger(30,amount=50,second=2)
        val one=read(wallet(),cash(),b,a);val two=read(a,cash(),wallet(),b)
        assertEquals(one,two);assertEquals(n(50),usage(one,30).investmentToUseMinor);assertFalse(one.usages.containsKey(id(20)))
    }
    @Test fun aggregateUsageBeyondLongAndNegativeIncomeMinimumKeepEveryMinorUnit() {
        val result=read(wallet(opening=0),cash(amount=Long.MAX_VALUE),cash(102,Long.MAX_VALUE),ledger(20,"income",Long.MIN_VALUE),ledger(30,amount=Long.MAX_VALUE,second=3))
        assertEquals(n(Long.MIN_VALUE).negate(),usage(result).requestedMinor)
        assertEquals(n(Long.MAX_VALUE)*BigInteger.TWO,result.usages.values.fold(BigInteger.ZERO){sum,it->sum+it.investmentToUseMinor})
        assertEquals(BigInteger.ZERO,result.availableByWalletId[id(1)])
    }
    @Test fun allChangedWalletsAreRetainedWhilePrimaryUsesLargestMagnitudeAndStableUuidTie() {
        val old=ledger(20);val replacement=old.with("source_wallet_id",JsonPrimitive(id(2)))
        val result=compareInvestmentFundUsageTimeline(snapshot(wallet(),wallet(2,100),cash(),cash(102,wallet=2),old),"VND",old.id,replacement)
        assertEquals(listOf(id(2),id(1)),result.changes.map{it.walletId})
        assertEquals(n(30),result.changes.first().proposedMinor);assertEquals(n(30),result.changes.last().restoreMinor)
    }
    @Test fun validFxWithNoReservedUseRetainsBothOriginalLegsButNeededConversionIsAnExplicitHold() {
        val transfer=ledger(20,"transfer",70,to=2,subtype="internalTransfer").with("destination_amount_minor",JsonPrimitive(9L))
        val ordinary=read(wallet(),wallet(2,0,code="JPY"),transfer)
        assertEquals(n(30),ordinary.actualByWalletId[id(1)]);assertEquals(n(9),ordinary.actualByWalletId[id(2)])
        try{read(wallet(),wallet(2,0,code="JPY"),cash(),transfer);fail("must not relabel VND as JPY")}
        catch(error:InvestmentFundTimelineException){assertEquals(InvestmentFundTimelineError.UNSUPPORTED_CURRENCY_CONVERSION,error.reason)}
    }
    @Test fun ownerMalformedAndOccupiedReplacementCannotBecomeAZeroPreviewOrMutateAnyInput() {
        val base=snapshot(wallet(),cash(),ledger(20));val original=base.copy(rows=base.rows.toList())
        val changed=ledger(20,amount=80)
        assertEquals(n(40),compareInvestmentFundUsageTimeline(base,"VND",id(20),changed).primaryChange!!.proposedMinor)
        assertEquals(original,base)
        val malformed=listOf(ledger(20).with("amount_minor",JsonPrimitive("70")),ledger(20).with("occurred_at",JsonPrimitive("bad")),ledger(20).with("user_id",JsonPrimitive(id(99))))
        for(row in malformed)assertTrue(runCatching{read(wallet(),cash(),row)}.isFailure)
        assertTrue(runCatching{compareInvestmentFundUsageTimeline(base,"VND",id(99),changed)}.isFailure)
        assertTrue(runCatching{compareInvestmentFundUsageTimeline(base,"VND",null,changed)}.isFailure)
    }
    @Test fun anExplicitConsumedSourceCurrencyCannotDisagreeWithTheWalletOrBecomeANumericFallback() {
        for(currency in listOf(JsonPrimitive("JPY"),JsonPrimitive(123L))) {
            val error=runCatching{read(wallet(),cash(),ledger(20).with("source_currency_code",currency))}.exceptionOrNull()
            assertTrue("consumed currency contradiction: $currency",error is InvestmentFundTimelineException)
        }
        val legacy=ledger(20).with("source_currency_code",JsonNull)
        assertEquals(n(30),usage(read(wallet(),cash(),legacy)).investmentToUseMinor)
    }
    @Test fun draftArchivedDeletedAndDedicatedInvestmentLegsNeverConsumeAnOrdinaryReserve() {
        val expense=ledger(20)
        for(ignored in listOf(expense.with("entry_status_raw_value",JsonPrimitive("draft")),expense.with("is_archived",JsonPrimitive(true)),
            expense.copy(deletedAt=time(0)).with("deleted_at",JsonPrimitive(time(0))).with("occurred_at",JsonNull))) {
            val result=read(wallet(),cash(),ignored);assertTrue(result.usages.isEmpty());assertEquals(n(100),result.actualByWalletId[id(1)])
        }
        val dedicated=expense.with("settlement_role_raw_value",JsonPrimitive("investmentBuy"))
        val result=read(wallet(),cash(),dedicated);assertTrue(result.usages.isEmpty());assertEquals(n(30),result.actualByWalletId[id(1)]);assertEquals(n(60),result.availableByWalletId[id(1)])
    }
    @Test fun tombstonesAndWrongReplacementIdentityCannotOccupyANewOrExistingEvent() {
        val expense=ledger(20);val tombstone=expense.copy(deletedAt=time(0)).with("deleted_at",JsonPrimitive(time(0)))
        assertTrue(runCatching{compareInvestmentFundUsageTimeline(snapshot(wallet(),tombstone),"VND",null,expense)}.isFailure)
        assertTrue(runCatching{compareInvestmentFundUsageTimeline(snapshot(wallet(),tombstone),"VND",expense.id,expense)}.isFailure)
        assertTrue(runCatching{compareInvestmentFundUsageTimeline(snapshot(wallet(),expense),"VND",expense.id,ledger(30))}.isFailure)
        assertTrue(runCatching{read(wallet(),cash(),expense,expense)}.isFailure)
        assertTrue(runCatching{compareInvestmentFundUsageTimeline(snapshot(wallet()),"VND",null,null)}.isFailure)
    }
    @Test fun retiredWalletNoncashAndDeletedPostingDoNotRequireUnusedMoneyOrDates() {
        val retired=wallet(2).with("is_archived",JsonPrimitive(true))
        val oldCash=cash(wallet=2).with("amount_minor",JsonPrimitive("bad")).with("occurred_at",JsonNull)
        val noncash=cash(102,role="funding").with("cash_bucket_raw_value",JsonNull).with("cash_origin_raw_value",JsonNull).with("occurred_at",JsonNull)
        val deleted=cash(103).copy(deletedAt=time(0)).with("deleted_at",JsonPrimitive(time(0))).with("role_raw_value",JsonNull)
        val result=read(wallet(),retired,oldCash,noncash,deleted)
        assertTrue(result.usages.isEmpty());assertEquals(n(0),result.availableByWalletId[id(1)]);assertFalse(result.actualByWalletId.containsKey(id(2)))
    }
    @Test fun malformedRelevantPostingBucketOriginAccountingCurrencyAndSystemAdjustmentCannotYieldAReadProof() {
        for(row in listOf(cash().with("cash_bucket_raw_value",JsonPrimitive("unknown")),cash().with("cash_origin_raw_value",JsonPrimitive("unknown")),
            cash().with("accounting_currency_code",JsonPrimitive("JPY")),cash().with("amount_minor",JsonPrimitive("60")),cash().with("occurred_at",JsonNull)))
            assertTrue(runCatching{read(wallet(),row,ledger(20))}.isFailure)
        assertTrue(runCatching{read(wallet(opening=40),cash(amount=60,bucket="unreconciled"),ledger(20,amount=60))}.isFailure)
    }
    @Test fun uuidOrderingCrossesTheSignedBoundaryAsUnsignedCanonicalText() {
        val first=ledger(20,amount=40).let{it.copy(id="7fffffff-ffff-4fff-8fff-ffffffffffff",payload=JsonObject(it.payload+("id" to JsonPrimitive("7fffffff-ffff-4fff-8fff-ffffffffffff"))))}
        val last=ledger(30,amount=50).let{it.copy(id="80000000-0000-4000-8000-000000000000",payload=JsonObject(it.payload+("id" to JsonPrimitive("80000000-0000-4000-8000-000000000000"))))}
        val result=read(wallet(),cash(),last,first)
        assertFalse(result.usages.containsKey(first.id));assertEquals(n(50),result.usages.getValue(last.id).investmentToUseMinor)
    }
}
