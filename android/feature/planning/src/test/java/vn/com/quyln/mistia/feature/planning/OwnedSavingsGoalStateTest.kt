package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.LocalDate
import org.junit.Assert.*
import org.junit.Test

class OwnedSavingsGoalStateTest {
    private val owner="owner"
    private val id="11111111-1111-1111-1111-111111111111"
    private val state=SavingsGoalEditorState.fresh(LocalDate.of(2026,10,16),"VND").copy(id=id,name="Draft",targetText="9,007,199,254,740,993",currentText="-25")
    private fun saved()=with(SavingsGoalEditorState.scopedSaver(owner,id,"VND")) {SaverScope {true}.save(state)}!!
    @Test fun `matching envelope restores exact draft but owner record or currency changes reject`() {
        val raw=saved()
        assertEquals(state,SavingsGoalEditorState.scopedSaver(owner,id,"VND").restore(raw))
        assertNull(SavingsGoalEditorState.scopedSaver("other",id,"VND").restore(raw))
        assertNull(SavingsGoalEditorState.scopedSaver(owner,null,"VND").restore(raw))
        assertNull(SavingsGoalEditorState.scopedSaver(owner,"other","VND").restore(raw))
        assertNull(SavingsGoalEditorState.scopedSaver(owner,id,"JPY").restore(raw))
    }
    @Test fun `matching outer envelope cannot restore a different payload identity or currency`() {
        val envelope=(saved() as List<*>).toMutableList()
        val raw=(envelope[3] as List<*>).toMutableList()
        raw[1]="other";envelope[3]=raw
        assertNull(SavingsGoalEditorState.scopedSaver(owner,id,"VND").restore(envelope))
        raw[1]=id;raw[7]="JPY";envelope[3]=raw
        assertNull(SavingsGoalEditorState.scopedSaver(owner,id,"VND").restore(envelope))
    }
    @Test fun `malformed restored values reject without crashing and fresh drafts stay create only`() {
        val saver=SavingsGoalEditorState.scopedSaver(owner,id,"VND")
        for(value in listOf<Any>("broken",emptyList<Any>(),listOf(owner,id,"VND",listOf(owner,123)),listOf(owner,id,"VND",123))) assertNull(saver.restore(value))
        val fresh=state.copy(id=null)
        val creating=SavingsGoalEditorState.scopedSaver(owner,null,"VND")
        val raw=with(creating) {SaverScope {true}.save(fresh)}!!
        assertEquals(fresh,creating.restore(raw));assertNull(saver.restore(raw))
    }
    @Test fun `invalid restored dates reject before editor calendar rendering`() {
        val envelope=(saved() as List<*>).toMutableList();val raw=(envelope[3] as List<*>).toMutableList()
        val saver=SavingsGoalEditorState.scopedSaver(owner,id,"VND")
        raw[5]="invalid";envelope[3]=raw;assertNull(saver.restore(envelope))
        raw[5]="2026-10-16";raw[6]="invalid";envelope[3]=raw;assertNull(saver.restore(envelope))
    }

}
