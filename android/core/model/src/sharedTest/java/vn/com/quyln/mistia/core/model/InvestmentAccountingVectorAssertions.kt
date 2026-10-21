package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*

internal object InvestmentAccountingVectorAssertions {
    private fun JsonObject.text(key: String): String? = get(key)?.takeUnless { it == JsonNull }?.jsonPrimitive?.content
    private fun decimal(expected: String, actual: BigDecimal, message: String) =
        assertEquals(message,0,BigDecimal(expected).compareTo(actual))

    fun check(document: JsonObject) {
        assertEquals(1,document.getValue("version").jsonPrimitive.int)
        val units=document.getValue("units").jsonArray
        assertEquals(32,units.size)
        for(element in units) {
            val unit=element.jsonObject
            assertEquals(unit.text("display"),InvestmentUnitLabel.normalizedDisplay(unit.text("input")))
            assertEquals(unit.text("key"),InvestmentUnitLabel.comparisonKey(unit.text("input")))
        }
        val cases=document.getValue("cases").jsonArray
        assertEquals(147,cases.size)
        for(element in cases) {
            val vector=element.jsonObject
            val name=vector.getValue("name").jsonPrimitive.content
            val trades=vector.getValue("trades").jsonArray.map { item ->
                val trade=item.jsonObject
                InvestmentTradeInput(UUID.fromString(trade.text("id")),
                    InvestmentTradeKind.valueOf(trade.text("kind")!!.uppercase(java.util.Locale.ROOT)),
                    BigDecimal(trade.text("quantity")),trade.text("unitLabel"),trade.text("gross")!!.toLong(),
                    Instant.parse(trade.text("occurredAt")),Instant.parse(trade.text("createdAt")))
            }
            val expected=vector.getValue("expected").jsonObject
            val result=runCatching { InvestmentAccountingEngine.projection(trades) }
            val error=expected.text("error")
            if(error!=null) {
                val reason=(result.exceptionOrNull() as? InvestmentAccountingException)?.reason
                val wire=when(reason) {
                    InvestmentAccountingError.INVALID_QUANTITY -> "invalidQuantity"
                    InvestmentAccountingError.INVALID_AMOUNT -> "invalidAmount"
                    InvestmentAccountingError.INSUFFICIENT_POSITION -> "insufficientPosition"
                    InvestmentAccountingError.ARITHMETIC_OVERFLOW -> "arithmeticOverflow"
                    null -> null
                }
                assertEquals(name,error,wire)
                continue
            }
            val actual=result.getOrElse { throw AssertionError(name,it) }
            val calculations=expected.getValue("calculations").jsonArray
            assertEquals(name,calculations.size,actual.calculations.size)
            for((item,value) in calculations.zip(actual.calculations)) {
                val e=item.jsonObject
                assertEquals(name,e.text("id"),value.id.toString())
                assertEquals(name,e.text("released")!!.toLong(),value.releasedCostBasisMinor)
                assertEquals(name,e.text("profit")!!.toLong(),value.realizedProfitLossMinor)
                decimal(e.text("quantity")!!,value.positionQuantityAfter,name)
                assertEquals(name,e.text("basis")!!.toLong(),value.positionCostBasisAfterMinor)
                assertEquals(name,e.getValue("lots").jsonPrimitive.int,value.openLotCountAfter)
            }
            val positions=expected.getValue("positions").jsonArray.map { it.jsonObject }.associateBy { it.text("key")!! }
            val actualPositions=actual.unitPositions.associateBy { it.unitKey }
            assertEquals(name,positions.keys,actualPositions.keys)
            for((key,e) in positions) {
                val position=actualPositions.getValue(key)
                assertEquals(name,e.text("label"),position.unitLabel)
                decimal(e.text("quantity")!!,position.quantity,name)
            }
        }
    }
}
