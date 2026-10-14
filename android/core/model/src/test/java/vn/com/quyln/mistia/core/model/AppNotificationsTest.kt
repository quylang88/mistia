package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class AppNotificationsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="22222222-2222-2222-2222-222222222222"
    private val bill="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-14T00:00:00Z"
    private val later="2026-10-15T00:00:00Z"
    private fun row(kind:String="billPaymentRequired",month:String="2026-10")=AppNotificationRecord(owner.value,
        "mistia.bill.payment.deadline.$bill.$month","Due","Body",kind,resourceType="bill",resourceId=bill,
        createdAt=now,updatedAt=now,metadata=buildJsonObject {put("dueMonthKey",month);put("amountMinor",9007199254740993L);put("nullable",JsonNull)})
    @Test fun `repeat upsert preserves read state created time and resolved action`() {
        val old=row().copy(isRead=true,readAt=now,actionState="resolved")
        val incoming=row().copy(title="New title",body="New body",createdAt=later,updatedAt=later)
        val result=upsertLocalNotification(old,incoming)
        assertEquals(now,result.createdAt);assertTrue(result.isRead);assertEquals(now,result.readAt)
        assertEquals("resolved",result.actionState);assertEquals("New title",result.title)
        assertEquals(9007199254740993L,result.metadata!!["amountMinor"]!!.jsonPrimitive.long)
    }
    @Test fun `force unread resurfaces existing notification and resets read timestamp`() {
        val old=row().copy(isRead=true,readAt=now,actionState="resolved")
        val result=upsertLocalNotification(old,row().copy(createdAt=later,updatedAt=later),true)
        assertFalse(result.isRead);assertNull(result.readAt);assertEquals(later,result.createdAt)
        assertEquals("resolved",result.actionState)
    }
    @Test fun `mark read retains first read time on repeated tap`() {
        val once=markLocalNotificationRead(row(),now)
        val twice=markLocalNotificationRead(once,later)
        assertTrue(twice.isRead);assertEquals(now,twice.readAt);assertEquals(later,twice.updatedAt)
    }
    @Test fun `resolve bill cycle marks actionable local kinds but preserves success and other scope`() {
        val actionable=listOf(row(),row("billAutoPaymentFailed"),row("billOverdue"))
        val untouched=listOf(row("billAutoPaymentSucceeded"),row(month="2026-09"),row().copy(ownerUserId=other),row().copy(source="family"))
        val result=resolveLocalBillNotifications(owner,actionable+untouched,bill,"2026-10",later)
        assertTrue(result.take(3).all {it.isRead && it.readAt==later && it.actionState=="resolved"})
        assertEquals(untouched,result.drop(3))
    }
    @Test fun `resolve entire bill includes old cycles and keeps original read timestamp`() {
        val original=row(month="2026-09").copy(isRead=true,readAt=now)
        val result=resolveLocalBillNotifications(owner,listOf(original,row()),bill,null,later)
        assertTrue(result.all {it.actionState=="resolved"})
        assertEquals(now,result.first().readAt)
    }
    @Test fun `cross owner or key upsert and malformed timestamps fail closed`() {
        assertThrows(IllegalArgumentException::class.java) {upsertLocalNotification(row(),row().copy(ownerUserId=other))}
        assertThrows(IllegalArgumentException::class.java) {upsertLocalNotification(row(),row(month="2026-09"))}
        assertThrows(java.time.format.DateTimeParseException::class.java) {markLocalNotificationRead(row(),"bad timestamp")}
    }
}
