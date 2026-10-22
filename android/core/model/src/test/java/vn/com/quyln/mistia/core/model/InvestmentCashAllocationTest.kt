package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashAllocationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val first="7fffffff-ffff-4fff-8fff-ffffffffffff"
    private val second="80000000-0000-4000-8000-000000000000"
    private val now="2026-10-22T00:00:00Z"
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun cash(id:Int,wallet:String=first,local:Long,accounting:Long=local,bucket:String="booked",code:String="VND",accountCode:String="VND",deleted:Boolean=false):CloudRecord {
        val uuid="00000000-0000-4000-8000-"+id.toString().padStart(12,'0')
        return CloudRecord(CloudEntity.INVESTMENT_POSTING.table,uuid,owner.value,buildJsonObject {
            put("id",uuid);put("user_id",owner.value);put("wallet_id",wallet);put("role_raw_value","cashAccrual")
            put("cash_bucket_raw_value",bucket);put("cash_origin_raw_value","derived");put("amount_minor",local);put("currency_code",code)
            put("accounting_amount_minor",accounting);put("accounting_currency_code",accountCode);put("created_at",now);put("updated_at",now)
            put("deleted_at",if(deleted)JsonPrimitive(now) else JsonNull)
        },now,if(deleted)now else null,0)
    }
    private fun source(vararg rows:CloudRecord)=InvestmentWalletSnapshot(owner,rows.toList())
    private fun allocation(vararg rows:CloudRecord)=investmentCashAllocation(source(*rows),"VND")
    private fun location(booked:Long=0,unreconciled:Long=0,localBooked:Long=booked,localUnreconciled:Long=unreconciled,code:String="VND")=
        InvestmentCashLocation(first,code,n(booked),n(unreconciled),n(localBooked),n(localUnreconciled))
    private fun fail(expected:InvestmentCashReadError,action:()->Unit) {
        val result=runCatching(action);assertEquals(expected,(result.exceptionOrNull() as? InvestmentCashReadException)?.reason)
    }
    @Test fun bookedAndUnreconciledCashRemainSeparateAndWalletOrderIsUnsignedStable() {
        val result=allocation(cash(1,first,50),cash(2,second,30,bucket="unreconciled"),cash(3,second,-10,bucket="unreconciled"))
        assertEquals(n(50),result.bookedMinor);assertEquals(n(20),result.unreconciledMinor);assertEquals(n(70),result.totalMinor)
        assertEquals(listOf(first,second),result.locations.map{it.walletId});assertEquals(n(20),result.locations.last().originalUnreconciledMinor)
    }
    @Test fun localAndAccountingCashAmountsKeepTheirDifferentCurrenciesWithoutFxRelabelling() {
        val result=allocation(cash(1,local=50,accounting=12500,code="JPY"),cash(2,second,10,2500,"unreconciled","JPY"))
        assertEquals(n(15000),result.totalMinor);assertEquals("VND",result.accountingCurrencyCode)
        assertEquals("JPY",result.locations.first().currencyCode);assertEquals(n(50),result.locations.first().originalTotalMinor)
        assertEquals(n(12500),result.locations.first().totalMinor)
    }
    @Test fun knownNoncashRolesAndDeletedCashCannotChangeTheAllocation() {
        val noncash=listOf("funding","capitalReturn","realizedProfit","transferOut","transferIn").mapIndexed{index,role ->
            cash(index+2,local=999).let{it.copy(payload=JsonObject(it.payload+mapOf("cash_bucket_raw_value" to JsonNull,"role_raw_value" to JsonPrimitive(role))))}
        }
        assertEquals(n(50),allocation(*(noncash+listOf(cash(1,local=50),cash(20,local=999,deleted=true))).toTypedArray()).totalMinor)
    }
    @Test fun aZeroNetLocationWithOppositeBucketsRemainsVisible() {
        val result=allocation(cash(1,local=50),cash(2,local=-50,bucket="unreconciled"))
        assertEquals(BigInteger.ZERO,result.totalMinor);assertEquals(1,result.locations.size)
        assertEquals(n(50),result.locations.single().bookedMinor);assertEquals(n(-50),result.locations.single().unreconciledMinor)
    }
    @Test fun knownEmptyAndCompletelyCancelledCashHaveNoLocations() {
        assertEquals(BigInteger.ZERO,allocation().totalMinor);assertTrue(allocation().locations.isEmpty())
        assertTrue(allocation(cash(1,local=50),cash(2,local=-50)).locations.isEmpty())
    }
    @Test fun exactTotalsCanExceedLongAndCancelWithoutAnyIntermediateSaturation() {
        val max=Long.MAX_VALUE
        assertEquals(n(max)*n(2),allocation(cash(1,local=max),cash(2,local=max)).totalMinor)
        assertEquals(n(max),allocation(cash(1,local=max),cash(2,local=max),cash(3,local=-max)).totalMinor)
        assertEquals(n(9007199254740993L),allocation(cash(1,local=9007199254740993L)).totalMinor)
    }
    @Test fun foreignIdentityAndDuplicateSourceCannotInventOwnedCash() {
        val good=cash(1,local=50)
        fail(InvestmentCashReadError.UNREADABLE_SOURCE){allocation(good.copy(ownerUserId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))}
        fail(InvestmentCashReadError.UNREADABLE_SOURCE){allocation(good.copy(payload=JsonObject(good.payload+("user_id" to JsonPrimitive("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")))))}
        fail(InvestmentCashReadError.UNREADABLE_SOURCE){allocation(good,good)}
    }
    @Test fun damagedCashAndMixedCurrencyRowsNeverBecomeAZeroOrCombinedMinorCount() {
        val good=cash(1,local=50)
        for(fields in listOf(buildJsonObject{put("amount_minor",JsonNull)},buildJsonObject{put("wallet_id",JsonNull)},buildJsonObject{put("cash_bucket_raw_value","unknown")},buildJsonObject{put("accounting_amount_minor",51L)}))
            fail(InvestmentCashReadError.UNREADABLE_CASH){allocation(good.copy(payload=JsonObject(good.payload+fields)))}
        fail(InvestmentCashReadError.MIXED_ACCOUNTING_CURRENCY){allocation(cash(1,local=50,accountCode="USD"))}
        fail(InvestmentCashReadError.MIXED_WALLET_CURRENCY){allocation(good,cash(2,local=1,code="JPY"))}
    }
    @Test fun usageConsumesOrdinaryThenBookedThenUnreconciledInTheWalletUnit() {
        val result=investmentFundUsagePreview(120,n(100),location(40,30),"VND")
        assertEquals(n(60),result.ordinaryAvailableMinor);assertEquals(n(40),result.bookedToUseMinor);assertEquals(n(20),result.unreconciledToUseMinor)
        assertEquals(n(10),result.remainingInvestmentInWalletMinor);assertEquals(InvestmentFundUsageOutcome.REQUIRES_CONFIRMATION,result.outcome)
    }
    @Test fun sourceWalletSpendingExampleRetainsTheCorrectInvestmentRemainder() {
        val result=investmentFundUsagePreview(2500,n(3000),location(2000),"VND")
        assertEquals(n(1000),result.ordinaryAvailableMinor);assertEquals(n(1500),result.investmentToUseMinor);assertEquals(n(500),result.remainingInvestmentInWalletMinor)
    }
    @Test fun requestedCashBeyondTheAvailableLayersIsInsufficient() {
        assertEquals(InvestmentFundUsageOutcome.INSUFFICIENT_FUNDS,investmentFundUsagePreview(101,n(80),location(30,20),"VND").outcome)
    }
    @Test fun datedAttributionKeepsCurrentAffordabilityIndependentFromHistoricalCash() {
        assertEquals(InvestmentFundUsageOutcome.ORDINARY_FUNDS_ONLY,investmentFundUsagePreview(1800,n(360),null,"VND",n(9340)).outcome)
        assertEquals(InvestmentFundUsageOutcome.INSUFFICIENT_FUNDS,investmentFundUsagePreview(1800,n(9340),null,"VND",n(360)).outcome)
        val result=investmentFundUsagePreview(4000,n(6380),location(3399),"VND",n(7323))
        assertEquals(n(1019),result.bookedToUseMinor);assertEquals(n(2380),result.remainingInvestmentInWalletMinor)
    }
    @Test fun localFundingPreviewCannotConsumeAccountingAmountsAsWalletMinorUnits() {
        val local=location(booked=12500,localBooked=50,code="JPY")
        val result=investmentFundUsagePreview(60,n(80),local,"JPY")
        assertEquals(n(30),result.ordinaryAvailableMinor);assertEquals(n(30),result.bookedToUseMinor);assertEquals(n(20),result.remainingInvestmentInWalletMinor)
        fail(InvestmentCashReadError.MIXED_WALLET_CURRENCY){investmentFundUsagePreview(60,n(80),local,"VND")}
    }
    @Test fun previewPreservesLargeExactBalancesAndClampsNegativeRequestWithoutOverflow() {
        val actual=n(Long.MAX_VALUE)*n(2)
        val result=investmentFundUsagePreview(Long.MAX_VALUE,actual,null,"VND")
        assertEquals(actual,result.ordinaryAvailableMinor);assertEquals(InvestmentFundUsageOutcome.ORDINARY_FUNDS_ONLY,result.outcome)
        assertEquals(0L,investmentFundUsagePreview(Long.MIN_VALUE,BigInteger.ZERO,null,"VND").requestedMinor)
    }
    @Test fun linkedWalletActualCashDoesNotAddInvestmentAllocationTwice() {
        val result=investmentLinkedWalletBalances(n(150),n(50))
        assertEquals(n(150),result.actualMinor);assertEquals(n(100),result.ordinaryMinor);assertEquals(n(50),result.investmentMinor)
        assertEquals(n(150),investmentLinkedWalletBalances(n(150),n(-20)).ordinaryMinor)
        assertEquals(n(Long.MAX_VALUE),investmentLinkedWalletBalances(n(Long.MAX_VALUE)*n(2),n(Long.MAX_VALUE)).ordinaryMinor)
    }
    @Test fun aKnownAuthoritativeTombstoneCannotTurnDamagedCashFieldsIntoAnActiveUnknown() {
        val dead=cash(2,local=999,deleted=true).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("cash_bucket_raw_value","unknown");put("amount_minor",JsonNull);put("wallet_id",JsonNull)}))}
        assertEquals(n(50),allocation(cash(1,local=50),dead).totalMinor)
    }

    private fun profit(amount:JsonElement=JsonPrimitive(80L))=cash(100,local=0).let{it.copy(entity=CloudEntity.INVESTMENT_TRADE.table,payload=JsonObject(it.payload+buildJsonObject{put("realized_profit_loss_minor",amount)}))}
    private fun financial(vararg rows:CloudRecord)=investmentCashFinancialView(InvestmentCashReadSnapshot(owner,rows.toList()),"VND")
    @Test fun summaryUsesPersistedProfitAndCashWithExactNonnegativeShortfall() {
        val result=financial(profit(),cash(1,local=50))
        assertEquals(n(80),result.realizedProfitMinor);assertEquals(n(50),result.availableMinor);assertEquals(n(30),result.shortfallMinor)
        assertEquals(BigInteger.ZERO,financial(profit(JsonPrimitive(-20L)),cash(1,local=-5)).shortfallMinor)
    }
    @Test fun failedProfitAndFailedCashRemainIndependentInsteadOfShowingFabricatedZero() {
        val badProfit=financial(profit(JsonPrimitive("broken")),cash(1,local=50))
        assertNull(badProfit.realizedProfitMinor);assertEquals(n(50),badProfit.availableMinor);assertNull(badProfit.shortfallMinor)
        val badCash=cash(1,local=50).let{it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonNull)))}
        val result=financial(profit(),badCash);assertEquals(n(80),result.realizedProfitMinor);assertNull(result.allocation);assertNull(result.availableMinor)
        assertEquals(BigInteger.ZERO,financial().availableMinor)
    }
    @Test fun sourceContradictionHoldsTheWholeFinancialPresentation() {
        fail(InvestmentCashReadError.UNREADABLE_SOURCE){financial(profit().copy(ownerUserId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))}
    }

}
