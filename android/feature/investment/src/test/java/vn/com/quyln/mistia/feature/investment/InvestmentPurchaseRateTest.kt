package vn.com.quyln.mistia.feature.investment

import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.ExchangeRateSnapshot

class InvestmentPurchaseRateTest {
    @Test fun inverseSnapshotsRetainTheActualSwiftFoundationDecimalPrecision() {
        val vectors=mapOf("3" to "0.33333333333333333333333333333333333333","165" to "0.0060606060606060606060606060606060606", "0.000012345678901234567890123456789" to "81000.000729000006633900060368571549353")
        for((rate,expected) in vectors)assertEquals(expected,purchaseRate("VND","JPY",listOf(ExchangeRateSnapshot("JPY","VND",rate,"manual",0,null)))?.first)
    }
}
