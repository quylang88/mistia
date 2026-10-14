package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class AppNotificationRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val now="2026-10-14T00:00:00Z"
    private fun row(key:String)=AppNotificationRecord(owner.value,key,key,"Body","billOverdue",createdAt=now,updatedAt=now)
    private class Store:LocalStore by BudgetMemoryStore() {
        var rows=emptyList<AppNotificationRecord>()
        var onCommit:(()->Unit)?=null
        override suspend fun localNotifications(owner:UserId)=rows.filter {it.ownerUserId==owner.value}
        override suspend fun commitLocalNotifications(owner:UserId,expected:List<AppNotificationRecord>,replacement:List<AppNotificationRecord>):Boolean {
            onCommit?.let {onCommit=null;it()}
            if(localNotifications(owner)!=expected) return false
            rows=rows.filter {it.ownerUserId!=owner.value}+replacement;return true
        }
    }
    @Test fun `mark all reads only visible current owner notifications`()=runTest {
        val store=Store().apply {rows=listOf(row("visible"),row("future").copy(createdAt="2026-10-15T00:00:00Z"),row("due").copy(kind="dueSoon"),
            row("foreign").copy(ownerUserId="22222222-2222-2222-2222-222222222222"))}
        OfflineAppNotificationRepository(store).markNotificationsRead(owner,null,now).getOrThrow()
        assertTrue(store.rows.single {it.key=="visible"}.isRead)
        assertTrue(store.rows.filter {it.key!="visible"}.none {it.isRead})
    }
    @Test fun `new notification arriving during read retry stays unread`()=runTest {
        val store=Store().apply {rows=listOf(row("visible"));onCommit={rows=rows+row("new")}}
        OfflineAppNotificationRepository(store).markNotificationsRead(owner,null,now).getOrThrow()
        assertTrue(store.rows.single {it.key=="visible"}.isRead)
        assertFalse(store.rows.single {it.key=="new"}.isRead)
    }
    @Test fun `same key replacement arriving during read retry stays unread`()=runTest {
        val store=Store().apply {rows=listOf(row("visible"),row("other"));onCommit={rows=rows.map {if(it.key=="visible") it.copy(body="New content") else it}}}
        OfflineAppNotificationRepository(store).markNotificationsRead(owner,null,now).getOrThrow()
        assertFalse(store.rows.single {it.key=="visible"}.isRead)
        assertTrue(store.rows.single {it.key=="other"}.isRead)
    }
}
