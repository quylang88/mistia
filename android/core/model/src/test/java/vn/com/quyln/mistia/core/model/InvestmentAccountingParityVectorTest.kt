package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Test

class InvestmentAccountingParityVectorTest {
    @Test fun sameGoldensAsActualSwiftAccountingEngine() {
        val source=requireNotNull(javaClass.classLoader?.getResourceAsStream("investment-accounting-v1.json"))
            .bufferedReader().use { it.readText() }
        InvestmentAccountingVectorAssertions.check(Json.parseToJsonElement(source).jsonObject)
    }
}
