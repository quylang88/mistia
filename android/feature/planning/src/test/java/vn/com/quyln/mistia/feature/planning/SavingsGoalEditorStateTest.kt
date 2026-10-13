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
}
