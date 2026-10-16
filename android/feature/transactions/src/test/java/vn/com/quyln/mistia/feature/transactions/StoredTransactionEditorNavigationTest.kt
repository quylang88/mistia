package vn.com.quyln.mistia.feature.transactions

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.*
import org.junit.Test

class StoredTransactionEditorNavigationTest {
    private val owner="11111111-1111-1111-1111-111111111111"
    private val other="99999999-9999-9999-9999-999999999999"
    private val id="22222222-2222-2222-2222-222222222222"
    @Test fun `closed and open targets restore only in the same owner scope`() {
        val saver=StoredTransactionEditorNavigation.saver(owner)
        for(target in listOf(StoredTransactionEditorNavigation(owner,null),StoredTransactionEditorNavigation(owner,id))) {
            val raw=with(saver) {SaverScope {true}.save(target)}!!
            assertEquals(target,saver.restore(raw));assertNull(StoredTransactionEditorNavigation.saver(other).restore(raw))
        }
    }
    @Test fun `saving foreign or malformed identities refuses navigation envelope`() {
        val saver=StoredTransactionEditorNavigation.saver(owner)
        for(target in listOf(StoredTransactionEditorNavigation(other,id),StoredTransactionEditorNavigation(owner,"private payload"),StoredTransactionEditorNavigation(owner,"not-a-uuid")))
            assertNull(with(saver) {SaverScope {true}.save(target)})
    }
    @Test fun `corrupted or extra navigation slots fail safely without creating a draft`() {
        val saver=StoredTransactionEditorNavigation.saver(owner)
        for(raw in listOf<Any>("bad",emptyList<Any>(),listOf(owner),listOf(owner,123),listOf(owner,"bad"),listOf(owner,id,"extra"))) assertNull(saver.restore(raw))
    }
}
