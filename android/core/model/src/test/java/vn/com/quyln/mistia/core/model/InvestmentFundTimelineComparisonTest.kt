package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import org.junit.Assert.*
import org.junit.Test

class InvestmentFundTimelineComparisonTest {
    private fun use(id:String="a",booked:Long=30,unreconciled:Long=30,ordinary:Long=0)=InvestmentFundTimelineUsage(id,"wallet","JPY",100.toBigInteger(),ordinary.toBigInteger(),booked.toBigInteger(),unreconciled.toBigInteger(),40.toBigInteger(),InvestmentFundUsageOutcome.REQUIRES_CONFIRMATION)
    private fun timeline(vararg usage:InvestmentFundTimelineUsage)=InvestmentFundTimeline(usage.associateBy{it.transactionId},mapOf("wallet" to 40.toBigInteger()),mapOf("wallet" to BigInteger.ZERO))
    @Test fun equalTotalsWithDifferentBookedAndUnreconciledBucketsStillHaveOneWalletChange() {
        val result=compareInvestmentFundTimelines(timeline(use()),timeline(use(booked=60,unreconciled=0))){"JPY"}
        val change=result.changes.single();assertEquals(60.toBigInteger(),change.previousMinor);assertEquals(60.toBigInteger(),change.proposedMinor);assertEquals(40.toBigInteger(),change.remainingInvestmentMinor)
    }
    @Test fun ordinaryAvailabilityChangesDoNotInventAReservedAllocationChange() {
        assertTrue(compareInvestmentFundTimelines(timeline(use(ordinary=0)),timeline(use(ordinary=20))){"JPY"}.changes.isEmpty())
        assertTrue(compareInvestmentFundTimelines(timeline(),timeline(use(booked=0,unreconciled=0))){"JPY"}.changes.isEmpty())
    }
    @Test fun identicalReservedAllocationsRemainANoChangeRegardlessOfMapOrder() {
        val a=use();val b=use("b",booked=10,unreconciled=0)
        assertTrue(compareInvestmentFundTimelines(timeline(a,b),timeline(b,a)){"JPY"}.changes.isEmpty())
    }
}
