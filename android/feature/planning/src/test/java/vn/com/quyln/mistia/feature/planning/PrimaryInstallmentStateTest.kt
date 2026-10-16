package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class PrimaryInstallmentStateTest {
    private val owner="11111111-1111-1111-1111-111111111111"
    private val id="22222222-2222-2222-2222-222222222222"
    private val wallet="33333333-3333-3333-3333-333333333333"
    private val state=InstallmentEditorState.fresh(owner,id,"VND").copy(name="Draft",amountText="9,007,199,254,740,993")
    private fun saved()=with(InstallmentEditorState.scopedSaver(owner,id,"VND",false)) {SaverScope {true}.save(state)}!!
    @Test fun `exact creation draft restores only in matching currency and route mode`() {
        val raw=saved();assertEquals(state,InstallmentEditorState.scopedSaver(owner,id,"VND",false).restore(raw))
        assertNull(InstallmentEditorState.scopedSaver(owner,id,"JPY",false).restore(raw))
        assertNull(InstallmentEditorState.scopedSaver(owner,id,"VND",true).restore(raw))
        assertNull(InstallmentEditorState.scopedSaver(wallet,id,"VND",false).restore(raw))
        assertNull(InstallmentEditorState.scopedSaver(owner,wallet,"VND",false).restore(raw))
    }
    @Test fun `matching outer scope cannot restore mismatched inner code or an edit baseline in a create route`() {
        val envelope=(saved() as List<*>).toMutableList();val raw=(envelope[4] as List<*>).toMutableList()
        raw[9]="JPY";envelope[4]=raw
        assertNull(InstallmentEditorState.scopedSaver(owner,id,"VND",false).restore(envelope))
        raw[9]="VND";raw[2]=plan().toPayload().toString()
        assertNull(InstallmentEditorState.scopedSaver(owner,id,"VND",false).restore(envelope))
    }
    private fun plan()=InstallmentPlanRecord(id,owner,"Original","mistia.plan.loan",9007199254740993L,31,24,12,wallet,"VND",false,
        "2026-10-16T00:00:00Z","2026-10-16T00:00:00Z",null,9007199254740995L,wallet)
    @Test fun `frozen legacy edit baseline and exact Long version survive while dropped baseline rejects`() {
        val initial=InstallmentEditorState.from(owner,plan());val saver=InstallmentEditorState.scopedSaver(owner,id,"VND",true)
        val saved=with(saver) {SaverScope {true}.save(initial)}!!
        assertEquals(initial,saver.restore(saved));assertEquals(plan(),saver.restore(saved)!!.baseline())
        val envelope=(saved as List<*>).toMutableList();val raw=(envelope[4] as List<*>).toMutableList();raw[2]="";envelope[4]=raw
        assertNull(saver.restore(envelope))
    }
    @Test fun `malformed envelope rejects without changing the raw saver compatibility contract`() {
        val saver=InstallmentEditorState.scopedSaver(owner,id,"VND",false)
        for(value in listOf<Any>("bad",emptyList<Any>(),listOf(owner,id,"VND",false,123))) assertNull(saver.restore(value))
        val rawSaver=InstallmentEditorState.saver(owner,id);val raw=with(rawSaver) {SaverScope {true}.save(state)}!!
        assertEquals(state,rawSaver.restore(raw));assertNull(saver.restore(raw))
    }
}
