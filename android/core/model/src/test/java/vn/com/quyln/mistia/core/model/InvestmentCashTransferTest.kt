package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashTransferTest {
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun preview(direction:InvestmentCashTransferDirection=InvestmentCashTransferDirection.DEPOSIT,requested:Long=1800,profit:BigInteger=n(5000),
        available:BigInteger=n(3200),booked:BigInteger=n(2500),actual:BigInteger=n(10000),reserved:BigInteger=n(2000))=
        investmentCashTransferPreview(direction,requested,profit,available,booked,actual,reserved)
    @Test fun depositCapacityIsTheSmallerOfEarnedProfitShortfallAndSourceOrdinaryCash() {
        val result=preview()
        assertEquals(1800L,result.maximumMinor);assertEquals(n(8000),result.sourceOrdinaryMinor);assertEquals(n(1800),result.shortfallMinor);assertTrue(result.isValid)
        assertFalse(preview(requested=1801).isValid)
        assertEquals(1000L,preview(actual=n(3000)).maximumMinor)
    }
    @Test fun depositCannotRefillPastProfitOrConsumeAnExistingInvestmentAllocation() {
        assertEquals(0L,preview(profit=n(3000)).maximumMinor)
        assertEquals(0L,preview(actual=n(1999)).maximumMinor)
        assertFalse(preview(profit=n(-5000)).isValid)
    }
    @Test fun withdrawalCapacityUsesOnlyTheBookedLinkedCashEvenWhenOtherCashExists() {
        val result=preview(InvestmentCashTransferDirection.WITHDRAWAL,2500,available=n(9000))
        assertEquals(2500L,result.maximumMinor);assertTrue(result.isValid)
        assertFalse(preview(InvestmentCashTransferDirection.WITHDRAWAL,2501,available=n(9000)).isValid)
    }
    @Test fun withdrawalFollowsTheSourceBookedLimitIndependentOfSourceOrdinaryCash() {
        val result=preview(InvestmentCashTransferDirection.WITHDRAWAL,2500,profit=n(-100),actual=n(-500),reserved=n(5000))
        assertEquals(2500L,result.maximumMinor);assertEquals(BigInteger.ZERO,result.sourceOrdinaryMinor);assertTrue(result.isValid)
    }
    @Test fun negativeAmountsAreNeutralForLimitsWhileSignedPersistedInputsRemainIntact() {
        val result=preview(requested=Long.MIN_VALUE,available=n(-20),booked=n(-30),reserved=n(-40))
        assertEquals(0L,result.requestedMinor);assertFalse(result.isValid)
        assertEquals(n(-20),result.availableInvestmentMinor);assertEquals(n(-30),result.linkedBookedMinor)
        assertEquals(n(5000),result.shortfallMinor);assertEquals(n(10000),result.sourceOrdinaryMinor)
        assertEquals(0L,preview(InvestmentCashTransferDirection.WITHDRAWAL,1,booked=n(-30)).maximumMinor)
    }
    @Test fun exactReadAmountsBeyondLongNeverBecomeAnOverflowingWireMaximum() {
        val twice=n(Long.MAX_VALUE)*BigInteger.TWO
        val result=preview(requested=Long.MAX_VALUE,profit=twice,available=BigInteger.ZERO,actual=twice,reserved=BigInteger.ZERO)
        assertEquals(Long.MAX_VALUE,result.maximumMinor);assertEquals(twice,result.sourceOrdinaryMinor);assertEquals(twice,result.realizedProfitMinor);assertTrue(result.isValid)
        assertEquals(Long.MAX_VALUE,preview(InvestmentCashTransferDirection.WITHDRAWAL,Long.MAX_VALUE,booked=twice).maximumMinor)
    }
    @Test fun zeroRequestIsNeverAValidTransferAndTwoToThe53BoundaryRemainsExact() {
        assertFalse(preview(requested=0).isValid)
        val precise=n(9007199254740993L)
        assertEquals(9007199254740993L,preview(profit=precise,available=BigInteger.ZERO,actual=precise,reserved=BigInteger.ZERO).maximumMinor)
    }
}
