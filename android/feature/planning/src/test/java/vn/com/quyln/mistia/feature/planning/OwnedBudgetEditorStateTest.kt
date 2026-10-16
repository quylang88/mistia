package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.*
import org.junit.Test

class OwnedBudgetEditorStateTest {
    private val owner="owner-A"
    private val id="11111111-1111-1111-1111-111111111111"
    private val month="2026-10"
    private val state=BudgetEditorState.fresh(java.time.YearMonth.parse(month),"VND").copy(categoryId=id,amountText="9,007,199,254,740,993",rolloverEnabled=true)
    private fun saver(recordId:String?=null,currency:String="JPY")=BudgetEditorState.scopedSaver(owner,recordId,month,currency)
    private fun saved()=with(saver()) {SaverScope {true}.save(state)}!!
    @Test fun `branch currency override and exact draft restore only in matching initial scope`() {
        val raw=saved();assertEquals(state,saver().restore(raw))
        assertNull(BudgetEditorState.scopedSaver("owner-B",null,month,"JPY").restore(raw))
        assertNull(BudgetEditorState.scopedSaver(owner,id,month,"JPY").restore(raw))
        assertNull(BudgetEditorState.scopedSaver(owner,null,"2026-11","JPY").restore(raw))
        assertNull(saver(currency="VND").restore(raw))
        val imported=state.copy(currencyCode="USD",amountText="13.75")
        val rawUsd=with(saver()) {SaverScope {true}.save(imported)}!!
        assertEquals(imported,saver().restore(rawUsd))
    }
    @Test fun `matching outer context cannot restore wrong inner identity month mode or edit currency`() {
        val envelope=(saved() as List<*>).toMutableList();val raw=(envelope[4] as List<*>).toMutableList()
        for((slot,value) in listOf(0 to id,1 to "2026-09",2 to "2026-11",5 to "BAD!")) {
            val changed=raw.toMutableList();changed[slot]=value;envelope[4]=changed
            assertNull(saver().restore(envelope))
        }
        val edit=state.copy(id=id,sourceMonth="2026-09",currencyCode="USD",amountText="13.75")
        val editSaver=saver(id,"USD");val savedEdit=with(editSaver) {SaverScope {true}.save(edit)}!!
        assertEquals(edit,editSaver.restore(savedEdit))
        val editEnvelope=(savedEdit as List<*>).toMutableList();val editRaw=(editEnvelope[4] as List<*>).toMutableList();editRaw[5]="JPY";editEnvelope[4]=editRaw
        assertNull(editSaver.restore(editEnvelope))
    }
    @Test fun `malformed envelope and calendar reject safely while legacy saver remains compatible`() {
        for(value in listOf<Any>("bad",emptyList<Any>(),listOf(owner,"",month,"JPY",123))) assertNull(saver().restore(value))
        val envelope=(saved() as List<*>).toMutableList()
        for(slot in listOf(1,2)) {
            val raw=(saved() as List<*>)[4] as List<*>;val changed=raw.toMutableList();changed[slot]="2026-99";envelope[4]=changed
            assertNull(saver().restore(envelope))
        }
        val old=BudgetEditorState.scopedSaver(owner);val oldRaw=with(old) {SaverScope {true}.save(state)}!!
        assertEquals(state,old.restore(oldRaw));assertNull(saver().restore(oldRaw))
    }
    @Test fun `saving another record month or stored currency refuses envelope`() {
        fun save(value:BudgetEditorState)=with(saver()) {SaverScope {true}.save(value)}
        assertNull(save(state.copy(id=id,sourceMonth="2026-09")))
        assertNull(save(state.copy(selectedMonth="2026-11")))
        val editSaver=saver(id,"JPY")
        assertNull(with(editSaver) {SaverScope {true}.save(state.copy(id=id,sourceMonth="2026-09"))})
    }
}
