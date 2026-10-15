package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.BudgetPlanRecord
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.BudgetValidationException

class BudgetEditorStateTest {
    private val zone = ZoneId.of("Asia/Tokyo")
    private val now = Instant.parse("2026-10-13T00:00:00Z")

    @Test fun `draft parses signed long precision and rejects overflow fractional and empty amounts`() {
        val state = BudgetEditorState.fresh(YearMonth.of(2026,10), "JPY").copy(categoryId = CATEGORY, amountText = "9,007,199,254,740,993")
        assertEquals(9007199254740993L,state.toDraft(zone).limitMinor)
        assertEquals("2026-09-30T15:00:00Z",state.toDraft(zone).monthAnchor)
        listOf("9223372036854775808","1.1","","-1","0").forEach {
            assertThrows(BudgetValidationException::class.java) { state.copy(amountText=it).toDraft(zone) }
        }
    }

    @Test fun `past references archive current references delete and carry forward keeps destructive actions hidden`() {
        val past=BudgetEditorState.fresh(YearMonth.of(2026,9),"JPY").copy(id=BUDGET,sourceMonth="2026-09")
        assertTrue(past.isReadOnly(now,zone))
        assertTrue(past.canArchive(now,zone))
        assertFalse(past.canDelete(now,zone))
        val current=past.copy(selectedMonth="2026-10",sourceMonth="2026-10")
        assertFalse(current.isReadOnly(now,zone))
        assertTrue(current.canDelete(now,zone))
        assertFalse(current.canArchive(now,zone))
        val carried=past.copy(selectedMonth="2026-11")
        assertFalse(carried.isReadOnly(now,zone))
        assertFalse(carried.canDelete(now,zone))
        assertFalse(carried.canArchive(now,zone))
    }

    @Test fun `saveable state round trip keeps pending exact input and edit identity`() {
        val state=BudgetEditorState.fresh(YearMonth.of(2026,10),"VND").copy(id=BUDGET,sourceMonth="2026-09",
            categoryId=CATEGORY,amountText="9223372036854775807",rolloverEnabled=true)
        val saved=with(BudgetEditorState.Saver) { SaverScope { true }.save(state) }!!
        assertEquals(state,BudgetEditorState.Saver.restore(saved))
        assertTrue(state.toDraft(zone).editingExisting)
    }
    @Test fun `restoration rejects a different account for draft and navigation state`() {
        val state=BudgetEditorState.fresh(YearMonth.of(2026,10),"JPY").copy(amountText="12345")
        val saved=with(BudgetEditorState.scopedSaver("owner-A")) { SaverScope { true }.save(state) }!!
        assertEquals(state,BudgetEditorState.scopedSaver("owner-A").restore(saved))
        assertNull(BudgetEditorState.scopedSaver("owner-B").restore(saved))
        val navigation=BudgetNavigationState("owner-A","2026-09",true,BUDGET,null)
        val navigationSaved=with(BudgetNavigationState.saver("owner-A")) { SaverScope { true }.save(navigation) }!!
        assertEquals(navigation,BudgetNavigationState.saver("owner-A").restore(navigationSaved))
        assertNull(BudgetNavigationState.saver("owner-B").restore(navigationSaved))
    }

    @Test fun `category selection inherits existing branch currency for new budgets only`() {
        val state=BudgetEditorState.fresh(YearMonth.of(2026,10),"JPY")
        assertEquals("VND",state.selectCategory(CATEGORY,"VND").currencyCode)
        assertEquals("VND",state.copy(id=BUDGET,currencyCode="VND").selectCategory(CATEGORY,"JPY").currencyCode)
        assertEquals(CATEGORY,state.selectCategory(CATEGORY,"VND").categoryId)
    }

    @Test fun `changing branch currency clears input instead of reinterpreting money`() {
        val state=BudgetEditorState.fresh(YearMonth.of(2026,10),"JPY").copy(amountText="1000")
        assertEquals("",state.selectCategory(CATEGORY,"VND").amountText)
        assertEquals("1000",state.selectCategory(CATEGORY,"JPY").amountText)
    }

    @Test fun `supported budget amount groups while typing and keeps exact positive Long`() {
        for (currency in listOf("JPY", "VND")) {
            val state = BudgetEditorState.fresh(YearMonth.of(2026,10), currency).copy(categoryId = CATEGORY).withAmount("9007199254740993")
            assertEquals("9,007,199,254,740,993", state.amountText); assertEquals(9007199254740993L, state.toDraft(zone).limitMinor)
            assertEquals("", state.selectCategory(CATEGORY, if (currency == "JPY") "VND" else "JPY").amountText)
        }
    }
    @Test fun `grouped amount stays scoped during restoration and invalid input is never repaired into a payment`() {
        val state = BudgetEditorState.fresh(YearMonth.of(2026,10), "VND").copy(categoryId = CATEGORY).withAmount("123456")
        val saver = BudgetEditorState.scopedSaver("owner-A"); val saved = with(saver) { SaverScope { true }.save(state) }!!
        assertEquals("123,456", saver.restore(saved)!!.amountText); assertEquals(123456L, saver.restore(saved)!!.toDraft(zone).limitMinor)
        assertNull(BudgetEditorState.scopedSaver("owner-B").restore(saved))
        for (text in listOf("", "0", "-1234", "1.5", "1x23", "9223372036854775808")) assertThrows(BudgetValidationException::class.java) { state.withAmount(text).toDraft(zone) }
        assertEquals("1x23", state.withAmount("1x23").amountText)
    }
    @Test fun `fractional imported currency keeps existing exact decimal input`() {
        val state = BudgetEditorState.fresh(YearMonth.of(2026,10), "USD").copy(categoryId = CATEGORY).withAmount("13.75")
        assertEquals("13.75", state.amountText); assertEquals(1375L, state.toDraft(zone).limitMinor)
    }
    @Test fun `existing budget opens grouped while preserving source month and exact amount`() {
        val payload = buildJsonObject {
            put("id", JsonPrimitive(BUDGET)); put("user_id", JsonPrimitive(CATEGORY)); put("category_id", JsonPrimitive(CATEGORY))
            put("month_anchor", JsonPrimitive("2026-09-30T15:00:00Z")); put("limit_minor", JsonPrimitive(9007199254740993L))
            put("rollover_enabled", JsonPrimitive(false)); put("currency_code", JsonPrimitive("VND")); put("is_archived", JsonPrimitive(false))
            put("created_at", JsonPrimitive("2026-10-13T00:00:00Z")); put("updated_at", JsonPrimitive("2026-10-13T00:00:00Z")); put("sync_version", JsonPrimitive(7))
        }
        val plan = BudgetPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.BUDGET_PLAN.table, BUDGET, CATEGORY, payload, null, null, 7))
        val state = BudgetEditorState.from(plan, YearMonth.of(2026,10), zone)
        assertEquals("9,007,199,254,740,993", state.amountText); assertEquals("2026-10", state.sourceMonth)
        assertEquals(plan.limitMinor, state.toDraft(zone).limitMinor); assertEquals(BUDGET, state.toDraft(zone).id)
    }

    companion object {
        const val CATEGORY="11111111-1111-1111-1111-111111111111"
        const val BUDGET="22222222-2222-2222-2222-222222222222"
    }
}
