package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.LocalDate
import org.junit.Assert.*
import org.junit.Test

class OwnedBillEditorStateTest {
    private val owner="owner"
    private val id="11111111-1111-1111-1111-111111111111"
    private val state=RecurringBillEditorState.fresh(LocalDate.of(2026,10,16),"VND").copy(id=id,name="Draft",amountText="9,007,199,254,740,993",frequencyMonths=24)
    private fun saved()=with(RecurringBillEditorState.scopedSaver(owner,id,"VND")) {SaverScope {true}.save(state)}!!
    @Test fun `matching draft restores exact money and legacy frequency while wrong scope rejects`() {
        val raw=saved();val saver=RecurringBillEditorState.scopedSaver(owner,id,"VND")
        assertEquals(state,saver.restore(raw));assertEquals(24,saver.restore(raw)!!.frequencyMonths)
        assertNull(RecurringBillEditorState.scopedSaver("other",id,"VND").restore(raw))
        assertNull(RecurringBillEditorState.scopedSaver(owner,null,"VND").restore(raw))
        assertNull(RecurringBillEditorState.scopedSaver(owner,"other","VND").restore(raw))
        assertNull(RecurringBillEditorState.scopedSaver(owner,id,"JPY").restore(raw))
    }
    @Test fun `outer scope cannot restore different inner identity or currency`() {
        val envelope=(saved() as List<*>).toMutableList();val raw=(envelope[3] as List<*>).toMutableList()
        val saver=RecurringBillEditorState.scopedSaver(owner,id,"VND")
        raw[1]="other";envelope[3]=raw;assertNull(saver.restore(envelope))
        raw[1]=id;raw[6]="JPY";assertNull(saver.restore(envelope))
    }
    @Test fun `invalid restored dates and day ranges reject without calendar crashes`() {
        val saver=RecurringBillEditorState.scopedSaver(owner,id,"VND")
        for(index in listOf(11,12,15,8,9,14,16)) {
            val envelope=(saved() as List<*>).toMutableList();val raw=(envelope[3] as List<*>).toMutableList()
            raw[index]=if(index in listOf(11,12,15)) "invalid" else 0
            envelope[3]=raw;assertNull("Invalid restored slot $index",saver.restore(envelope))
        }
    }
    @Test fun `malformed envelope rejects and create only identity cannot restore as edit`() {
        val saver=RecurringBillEditorState.scopedSaver(owner,id,"VND")
        for(value in listOf<Any>("bad",emptyList<Any>(),listOf(owner,id,"VND",123),listOf(owner,id,"VND",listOf(owner,123)))) assertNull(saver.restore(value))
        val creating=RecurringBillEditorState.scopedSaver(owner,null,"VND");val draft=state.copy(id=null)
        val raw=with(creating) {SaverScope {true}.save(draft)}!!
        assertEquals(draft,creating.restore(raw));assertNull(saver.restore(raw))
    }
}
