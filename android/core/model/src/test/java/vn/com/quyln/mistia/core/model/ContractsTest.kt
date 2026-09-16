package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ContractsTest {
    @Test
    fun cloudEntitiesHaveStableDependencyOrder() {
        assertEquals(15, CloudEntity.entries.size)
        assertEquals(CloudEntity.TRANSACTION_CATEGORY, CloudEntity.pullOrder.first())
        assertTrue(
            CloudEntity.pullOrder.indexOf(CloudEntity.LEDGER_WALLET) <
                CloudEntity.pullOrder.indexOf(CloudEntity.LEDGER_TRANSACTION)
        )
        assertTrue(
            CloudEntity.pullOrder.indexOf(CloudEntity.INVESTMENT_ASSET) <
                CloudEntity.pullOrder.indexOf(CloudEntity.INVESTMENT_TRADE)
        )
    }

    @Test
    fun decimalStringDoesNotRoundThroughDouble() {
        val value = DecimalString("0.100000000000000001")
        assertEquals(BigDecimal("0.100000000000000001"), value.asBigDecimal())
    }

    @Test
    fun int64MoneyKeepsValuesBeyondJavaScriptSafeInteger() {
        assertEquals(9_007_199_254_740_993L, Money(9_007_199_254_740_993L, "JPY").minor)
    }
}
