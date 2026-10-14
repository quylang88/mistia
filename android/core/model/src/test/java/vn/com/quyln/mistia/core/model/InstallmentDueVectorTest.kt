package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class InstallmentDueVectorTest(private val name: String, private val vector: JsonObject, private val owner: String) {
    private fun JsonObject.string(key: String) = get(key)?.jsonPrimitive?.contentOrNull
    private fun JsonObject.number(key: String) = get(key)?.jsonPrimitive?.longOrNull
    private fun JsonObject.flag(key: String) = get(key)?.jsonPrimitive?.booleanOrNull == true
    @Test fun `shared actual Swift installment calendar and frozen occurrence vector`() {
        val plans = vector.getValue("plans").jsonArray.map { it.jsonObject }.map { p ->
            InstallmentPlanRecord(p.string("id")!!, p.string("owner")!!, p.string("name")!!, p.string("icon")!!,
                p.number("amount")!!, p.number("dueDay")!!.toInt(), p.number("totalCycles")?.toInt(), p.number("frequency")!!.toInt(),
                p.string("paymentWallet"), p.string("currency")!!, p.flag("archived"), p.string("createdAt")!!, p.string("createdAt")!!,
                if (p.flag("deleted")) p.string("createdAt") else null, 0, null)
        }
        val occurrences = vector.getValue("occurrences").jsonArray.mapIndexed { index, item ->
            val p = item.jsonObject; val now = "2035-01-01T00:00:00Z"
            DueOccurrenceRecord("70000000-0000-0000-0000-${(index + 1).toString().padStart(12, '0')}", p.string("owner")!!,
                p.string("sourceKind")!!, p.string("sourceId")!!, p.string("month")!!, now, p.number("amount"), p.string("status")!!,
                null, p.string("linked"), now, now, if (p.flag("deleted")) now else null, 0, null)
        }
        val rows = installmentDueRows(UserId(owner), plans, occurrences, YearMonth.parse(vector.string("month")), ZoneId.of(vector.string("zone")))
        val expected = vector.getValue("expected").jsonArray.map { it.jsonObject }
        assertEquals(name, expected.size, rows.size)
        expected.zip(rows).forEach { (wanted, actual) ->
            assertEquals(name, DueSourceKind.INSTALLMENT, actual.sourceKind); assertEquals(name, "loan_repayment", actual.categorySystemKey)
            assertEquals(name, wanted.string("id"), actual.plan.id); assertEquals(name, wanted.string("name"), actual.plan.name)
            assertEquals(name, wanted.number("amount"), actual.amountMinor); assertEquals(name, wanted.string("currency"), actual.plan.currencyCode)
            assertEquals(name, Instant.parse(wanted.string("due")), actual.dueDate); assertEquals(name, wanted.string("status"), actual.status.wireValue)
            assertEquals(name, wanted.string("linked"), actual.linkedTransactionId); assertEquals(name, wanted.string("paymentWallet"), actual.plan.paymentWalletId)
            assertEquals(name, wanted.number("frequency")?.toInt(), actual.plan.frequencyMonths); assertEquals(name, wanted.number("totalCycles")?.toInt(), actual.plan.totalCycles)
        }
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}") fun vectors(): List<Array<Any>> {
            val raw = InstallmentDueVectorTest::class.java.getResourceAsStream("/installment-due-v1.json")!!.bufferedReader().use { it.readText() }
            val doc = Json.parseToJsonElement(raw).jsonObject
            return doc.getValue("cases").jsonArray.map { item -> val v = item.jsonObject
                arrayOf(v.getValue("name").jsonPrimitive.content, v, doc.getValue("owner").jsonPrimitive.content) }
        }
    }
}
