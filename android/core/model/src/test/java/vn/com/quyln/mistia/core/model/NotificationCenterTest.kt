package vn.com.quyln.mistia.core.model

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class NotificationCenterTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val now="2026-10-14T00:00:00Z"
    private fun row(key:String,kind:String,time:String=now)=AppNotificationRecord(owner.value,key,key,"Body",kind,createdAt=time,updatedAt=time)
    private fun groups(rows:List<AppNotificationRecord>)=notificationGroups(owner,rows,Instant.parse(now))
    @Test fun `visible groups exclude dueSoon foreign and future rows`() {
        val valid=row("bill","billOverdue")
        val rows=listOf(valid,row("hidden","dueSoon"),valid.copy(key="foreign",ownerUserId="22222222-2222-2222-2222-222222222222"),
            valid.copy(key="future",createdAt="2026-10-15T00:00:00Z"))
        assertEquals(listOf(valid),groups(rows).single().rows)
    }
    @Test fun `group preview is newest while detail rows and unread count preserve read state`() {
        val old=row("old","billOverdue","2026-10-13T00:00:00Z")
        val recent=row("new","billAutoPaymentSucceeded").copy(isRead=true,readAt=now)
        val group=groups(listOf(recent,old)).single()
        assertEquals(NotificationGroupId.BILLS,group.id)
        assertEquals(listOf(old,recent),group.rows)
        assertEquals(recent,group.latest);assertEquals(1,group.unreadCount)
    }
    @Test fun `groups are ordered by newest preview not enum declaration`() {
        val bill=row("bill","billOverdue","2026-10-13T00:00:00Z")
        val wallet=row("wallet","lowWallet")
        assertEquals(listOf(NotificationGroupId.WALLETS,NotificationGroupId.BILLS),groups(listOf(bill,wallet)).map {it.id})
    }
    @Test fun `request group depends on pending action and family activity resource`() {
        val pending=row("pending","permissionRequestReceived").copy(actionState="pending")
        val resolved=pending.copy(key="resolved",actionState="approved")
        val cash=row("cash","familyActivity").copy(resourceType="transaction")
        val data=row("data","familyActivity").copy(resourceType="category")
        assertEquals(setOf(NotificationGroupId.ACTION_REQUESTS,NotificationGroupId.ACCESS,NotificationGroupId.FAMILY_CASHFLOW,NotificationGroupId.FAMILY_DATA),groups(listOf(pending,resolved,cash,data)).map {it.id}.toSet())
    }
}
