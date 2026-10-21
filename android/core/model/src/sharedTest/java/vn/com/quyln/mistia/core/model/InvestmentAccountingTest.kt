package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class InvestmentAccountingTest {
    private val start = Instant.parse("2026-10-21T00:00:00Z")
    private fun trade(kind: InvestmentTradeKind, quantity: String, gross: Long, at: Long = 0,
        unit: String? = null, id: String = "00000000-0000-4000-8000-"+(at+1).toString().padStart(12,'0'),
        created: Long = at) = InvestmentTradeInput(UUID.fromString(id), kind, BigDecimal(quantity), unit, gross,
            start.plusSeconds(at), start.plusSeconds(created))
    private fun buy(q: String, gross: Long, at: Long = 0, unit: String? = null) = trade(InvestmentTradeKind.BUY,q,gross,at,unit)
    private fun sell(q: String, gross: Long, at: Long = 1, unit: String? = null) = trade(InvestmentTradeKind.SELL,q,gross,at,unit)
    private fun projection(vararg trades: InvestmentTradeInput) = InvestmentAccountingEngine.projection(trades.toList())
    private fun quantity(expected: String, actual: BigDecimal) = assertEquals(0,BigDecimal(expected).compareTo(actual))
    private fun failure(error: InvestmentAccountingError, vararg trades: InvestmentTradeInput) {
        val result = runCatching { projection(*trades) }
        assertEquals(error,(result.exceptionOrNull() as? InvestmentAccountingException)?.reason)
    }
    @Test fun fullSaleReleasesAllCapitalAndRealizesProfit() {
        val result = projection(buy("1",100),sell("1",150)).calculations
        assertEquals(listOf(0L,100L),result.map { it.releasedCostBasisMinor })
        assertEquals(50L,result.last().realizedProfitLossMinor);quantity("0",result.last().positionQuantityAfter)
        assertEquals(0L,result.last().positionCostBasisAfterMinor);assertEquals(0,result.last().openLotCountAfter)
    }
    @Test fun lossAndZeroValueSaleRetainExactSignedLoss() {
        for((gross,loss) in listOf(70L to -30L,0L to -100L)) {
            val result=projection(buy("1",100),sell("1",gross)).calculations.last()
            assertEquals(100L,result.releasedCostBasisMinor);assertEquals(loss,result.realizedProfitLossMinor)
            assertEquals(0L,result.positionCostBasisAfterMinor)
        }
    }
    @Test fun partialSaleConsumesOldestLotBeforeNewerCost() {
        val result=projection(buy("2",200),buy("1",150,1),sell("1",160,2)).calculations.last()
        assertEquals(100L,result.releasedCostBasisMinor);assertEquals(60L,result.realizedProfitLossMinor)
        quantity("2",result.positionQuantityAfter);assertEquals(250L,result.positionCostBasisAfterMinor);assertEquals(2,result.openLotCountAfter)
    }
    @Test fun saleCrossesLotsAndRetainsOnlyRemainingBasis() {
        val result=projection(buy("10",1000),buy("10",2000,1),sell("12",1800,2)).calculations.last()
        assertEquals(1400L,result.releasedCostBasisMinor);assertEquals(400L,result.realizedProfitLossMinor)
        quantity("8",result.positionQuantityAfter);assertEquals(1600L,result.positionCostBasisAfterMinor);assertEquals(1,result.openLotCountAfter)
    }
    @Test fun roundingEachPartialLotPreservesEveryResidualMinorAtFinalSale() {
        val results=projection(buy("3",100),sell("1",50),sell("1",50,2),sell("1",50,3)).calculations.drop(1)
        assertEquals(listOf(33L,34L,33L),results.map { it.releasedCostBasisMinor })
        assertEquals(100L,results.sumOf { it.releasedCostBasisMinor });assertEquals(0L,results.last().positionCostBasisAfterMinor)
        assertEquals(0,results.last().openLotCountAfter)
    }
    @Test fun boxSaleNeverConsumesPackInventoryAndPreservesFirstDisplayLabel() {
        val result=projection(buy("30",3000,unit="pack"),buy("2",800,1,"  Gift   Box "),sell("1",600,2,"GIFT BOX"))
        assertEquals(400L,result.calculations.last().releasedCostBasisMinor);assertEquals(3400L,result.calculations.last().positionCostBasisAfterMinor)
        val units=result.unitPositions.associateBy { it.unitKey }
        quantity("30",units.getValue("pack").quantity);quantity("1",units.getValue("gift box").quantity)
        assertEquals("Gift Box",units.getValue("gift box").unitLabel)
    }
    @Test fun unitOversellFailsEvenWhenOtherUnitsHaveEnoughAggregateStock() {
        failure(InvestmentAccountingError.INSUFFICIENT_POSITION,buy("30",3000,unit="pack"),buy("1",800,1,"box"),sell("2",1200,2,"BOX"))
    }
    @Test fun interleavedUnitCursorsAndOpenLotCountStayIndependent() {
        val result=projection(buy("10",100,unit="pack"),buy("1",50,1,"box"),buy("10",200,2,"pack"),
            sell("10",150,3,"pack"),sell("5",125,4,"pack"),sell("1",75,5,"box"))
        assertEquals(listOf(100L,100L,50L),result.calculations.takeLast(3).map { it.releasedCostBasisMinor })
        assertEquals(listOf(2,2,1),result.calculations.takeLast(3).map { it.openLotCountAfter })
        assertEquals(100L,result.calculations.last().positionCostBasisAfterMinor)
    }
    @Test fun backdatedBuyRecalculatesLaterSaleRegardlessOfInputOrder() {
        val result=projection(buy("1",200,2),sell("1",180,3),buy("1",100)).calculations.last()
        assertEquals(100L,result.releasedCostBasisMinor);assertEquals(80L,result.realizedProfitLossMinor);assertEquals(200L,result.positionCostBasisAfterMinor)
    }
    @Test fun equalInstantsUseUnsignedUuidOrderRatherThanSignedJavaUuidComparison() {
        val buy=trade(InvestmentTradeKind.BUY,"1",100,id="7fffffff-ffff-4fff-8fff-ffffffffffff")
        val sell=trade(InvestmentTradeKind.SELL,"1",120,at=0,id="80000000-0000-4000-8000-000000000000")
        val result=projection(sell,buy).calculations
        assertEquals(listOf(buy.id,sell.id),result.map { it.id });assertEquals(20L,result.last().realizedProfitLossMinor)
    }
    @Test fun createdAtBreaksOccurrenceTiesBeforeUuid() {
        val sell=trade(InvestmentTradeKind.SELL,"1",120,at=0,created=1,id="00000000-0000-4000-8000-000000000001")
        val buy=trade(InvestmentTradeKind.BUY,"1",100,id="ffffffff-ffff-4fff-8fff-ffffffffffff")
        assertEquals(20L,projection(sell,buy).calculations.last().realizedProfitLossMinor)
    }
    @Test fun promotionalZeroCostBuyCreatesInventoryWhoseSaleIsAllProfit() {
        val sale=projection(buy("3",0),sell("2",80)).calculations.last()
        assertEquals(0L,sale.releasedCostBasisMinor);assertEquals(80L,sale.realizedProfitLossMinor)
        quantity("1",sale.positionQuantityAfter);assertEquals(0L,sale.positionCostBasisAfterMinor);assertEquals(1,sale.openLotCountAfter)
    }
    @Test fun invalidQuantityAndAmountFailWithBusinessReason() {
        for(q in listOf("0","-0.1"))failure(InvestmentAccountingError.INVALID_QUANTITY,buy(q,10))
        failure(InvestmentAccountingError.INVALID_AMOUNT,buy("1",-1));failure(InvestmentAccountingError.INVALID_AMOUNT,sell("1",-1))
    }
    @Test fun longMaximumRoundingIsExactAndOverflowIsRejected() {
        val results=projection(buy("2",Long.MAX_VALUE),sell("1",0),sell("1",0,2)).calculations
        assertEquals(4611686018427387904L,results[1].releasedCostBasisMinor);assertEquals(4611686018427387903L,results[2].releasedCostBasisMinor)
        assertEquals(-4611686018427387904L,results[1].realizedProfitLossMinor);assertEquals(0L,results.last().positionCostBasisAfterMinor)
        failure(InvestmentAccountingError.ARITHMETIC_OVERFLOW,buy("1",Long.MAX_VALUE),buy("1",1,1))
    }
    @Test fun failedEvaluationNeverLeaksPartialLotsIntoLaterCalls() {
        val input=listOf(buy("1",100),sell("2",200));val original=input.toList()
        failure(InvestmentAccountingError.INSUFFICIENT_POSITION,*input.toTypedArray());assertEquals(original,input)
        assertTrue(projection().calculations.isEmpty());assertTrue(projection().unitPositions.isEmpty())
        failure(InvestmentAccountingError.INSUFFICIENT_POSITION,sell("1",150))
        assertEquals(50L,projection(buy("1",100),sell("1",150)).calculations.last().realizedProfitLossMinor)
    }
    @Test fun unitNormalizationMatchesCaseFoldingAndCanonicalEquivalence() {
        assertEquals("Gift Box",InvestmentUnitLabel.normalizedDisplay("\u0085 Gift \u200b \nBox\u00a0"))
        assertNull(InvestmentUnitLabel.normalizedDisplay("\u0085\u200b "))
        for((a,b) in listOf("Straße" to "STRASSE","ς" to "Σ","İ" to "i\u0307","é" to "e\u0301"))assertTrue("$a / $b",InvestmentUnitLabel.matches(a,b))
        assertFalse(InvestmentUnitLabel.matches("ı","I"));assertFalse(InvestmentUnitLabel.matches("Ａ","A"))
        assertEquals(InvestmentUnitLabel.LEGACY_KEY,InvestmentUnitLabel.comparisonKey(null))
    }
}
