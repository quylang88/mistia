package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class SavingsGoalEditorStateTest {
    private val zone=ZoneId.of("Asia/Tokyo")
    private val goal=SavingsGoalRecord("11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222",
        "Travel","mistia.goal.travel",9007199254740993L,-25,"2026-12-31T15:00:00Z",null,"JPY",0,false,
        "2026-10-13T00:00:00Z","2026-10-13T00:00:00Z",null,0,null)
    @Test fun `exact signed amounts round trip and invalid target overflow reject`() {
        val state=SavingsGoalEditorState.from(goal,zone)
        assertEquals(goal.targetMinor,state.toDraft(zone).targetMinor)
        assertEquals(-25,state.toDraft(zone).currentSavedMinor)
        assertTrue(state.toDraft(zone).editingExisting)
        listOf("","0","-1","9223372036854775808","1.1").forEach { value ->
            assertThrows(IllegalArgumentException::class.java) { state.copy(targetText=value).toDraft(zone) }
        }
        assertEquals(0,state.copy(currentText="").toDraft(zone).currentSavedMinor)
        assertThrows(IllegalArgumentException::class.java) { state.copy(currentText="invalid").toDraft(zone) }
    }
    @Test fun `unchanged target instant preserved and new date uses local calendar`() {
        val state=SavingsGoalEditorState.from(goal,zone)
        assertEquals("2027-01-01",state.targetDate)
        assertEquals(goal.targetDate,state.toDraft(zone).targetDate)
        assertEquals("2027-01-01T15:00:00Z",state.copy(targetDate="2027-01-02").toDraft(zone).targetDate)
    }
    @Test fun `saveable draft keeps edits and refuses a different account`() {
        val state=SavingsGoalEditorState.from(goal,zone).copy(name="Pending",targetText="9,007,199,254,740,993")
        val saver=SavingsGoalEditorState.saver(goal.ownerUserId)
        val saved=with(saver) { SaverScope { true }.save(state) }!!
        assertEquals(state,saver.restore(saved))
        assertNull(SavingsGoalEditorState.saver("other").restore(saved))
        assertEquals(9007199254740993L,state.toDraft(zone).targetMinor)
    }
    @Test fun `fresh draft starts without edit identity and with local target date`() {
        val fresh=SavingsGoalEditorState.fresh(LocalDate.of(2026,10,13),"VND").copy(name="Home",targetText="1000000")
        assertFalse(fresh.toDraft(zone).editingExisting)
        assertNull(fresh.id)
        assertEquals("2026-10-12T15:00:00Z",fresh.toDraft(zone).targetDate)
    }
    @Test fun `navigation restores original edit snapshot only for its owner`() {
        val navigation=SavingsGoalNavigationState(goal.ownerUserId,true,goal.toPayload().toString())
        val saver=SavingsGoalNavigationState.saver(goal.ownerUserId)
        val saved=with(saver) { SaverScope { true }.save(navigation) }!!
        assertEquals(goal,saver.restore(saved)!!.goal())
        assertNull(SavingsGoalNavigationState.saver("other").restore(saved))
        assertNull(navigation.copy(owner="other").goal())
        assertNull(navigation.copy(payload="invalid").goal())
    }
    @Test fun `target and current group exact supported amounts with signed current value`() {
        for (currency in listOf("JPY", "VND")) {
            val state = SavingsGoalEditorState.fresh(LocalDate.of(2026,10,13), currency).copy(name = "Home")
                .withTarget("9007199254740993").withCurrent("-123456")
            assertEquals("9,007,199,254,740,993", state.targetText); assertEquals("-123,456", state.currentText)
            assertEquals(9007199254740993L, state.toDraft(zone).targetMinor); assertEquals(-123456L, state.toDraft(zone).currentSavedMinor)
        }
    }
    @Test fun `existing goal opens grouped without changing original date identity or amounts`() {
        val state = SavingsGoalEditorState.from(goal.copy(currentSavedMinor = 123456), zone)
        assertEquals("9,007,199,254,740,993", state.targetText); assertEquals("123,456", state.currentText)
        assertEquals(goal.targetDate, state.toDraft(zone).targetDate); assertEquals(goal.id, state.toDraft(zone).id)
    }
    @Test fun `grouped current and target survive owner scoped restore and blank current remains zero`() {
        val state = SavingsGoalEditorState.from(goal,zone).withTarget("123456").withCurrent("1234")
        val saver = SavingsGoalEditorState.saver(goal.ownerUserId); val saved = with(saver) { SaverScope { true }.save(state) }!!
        assertEquals("123,456", saver.restore(saved)!!.targetText); assertEquals("1,234", saver.restore(saved)!!.currentText)
        assertNull(SavingsGoalEditorState.saver("another-owner").restore(saved))
        assertEquals(0L, saver.restore(saved)!!.withCurrent("").toDraft(zone).currentSavedMinor)
    }
    @Test fun `invalid target current and overflow are preserved and rejected without changing unit`() {
        val state = SavingsGoalEditorState.from(goal,zone)
        for (text in listOf("1.5", "1x23", "9223372036854775808")) {
            assertThrows(IllegalArgumentException::class.java) { state.withTarget(text).toDraft(zone) }
            assertThrows(IllegalArgumentException::class.java) { state.withCurrent(text).toDraft(zone) }
        }
        assertEquals("1x23", state.withCurrent("1x23").currentText)
        assertEquals(1375L, state.copy(currencyCode = "USD").withTarget("13.75").withCurrent("12.50").toDraft(zone).targetMinor)
    }

}
