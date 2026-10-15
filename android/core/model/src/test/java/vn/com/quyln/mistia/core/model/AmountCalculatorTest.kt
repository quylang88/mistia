package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class AmountCalculatorTest {
    @Test fun `same 36 actual Swift decimal and error vectors preserve exact calculator behavior`() {
        val document = javaClass.classLoader!!.getResourceAsStream("amount-calculator-v1.json")!!.bufferedReader().use { Json.parseToJsonElement(it.readText()).jsonObject }
        assertEquals(1, document["version"]!!.jsonPrimitive.int)
        val cases = document["cases"]!!.jsonArray; assertEquals(36, cases.size)
        for (item in cases) {
            val c = item.jsonObject; val name = c["name"]!!.jsonPrimitive.content
            val evaluation = AmountCalculator.evaluate(c["tokens"]!!.jsonArray.map { it.jsonPrimitive.content })
            val integer = c["expectedInteger"]!!.jsonPrimitive.contentOrNull?.toLong()
            assertEquals(name, integer, evaluation.integerResult)
            assertEquals(name, c["expectedError"]!!.jsonPrimitive.contentOrNull, evaluation.error?.wire)
            val text = c["expectedDecimal"]!!.jsonPrimitive.contentOrNull
            assertEquals(name, text == "NaN", evaluation.decimalIsNaN)
            val decimal = text?.takeUnless { it == "NaN" }?.toBigDecimal()
            assertEquals(name, decimal?.stripTrailingZeros(), evaluation.decimalResult?.stripTrailingZeros())
            assertEquals(name, integer != null && evaluation.error == null, evaluation.canCommit)
        }
    }
}
