package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class NativeWalletRemindersTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val wallet="22222222-2222-2222-2222-222222222222"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val ticket=NativeWalletReminder(owner.value,"mistia.reminder.wallet.$wallet",wallet,"2026-10-14T00:00:00Z",zone.id)
    private val row=AppNotificationRecord(owner.value,ticket.key,"Low","Current balance: -1 JPY","lowWallet",source="localReminder",
        resourceType="wallet",resourceId=wallet,createdAt="2026-10-15T00:00:00Z",updatedAt="2026-10-14T00:01:00Z")
    private val plan=WalletReminderPlan(listOf(row),listOf(row))
    private fun deliver(now:String="2026-10-14T00:01:00Z",active:UserId?=owner,enabled:Boolean=true,permission:Boolean=true,
        calendar:ZoneId=zone,last:String?=null,current:WalletReminderPlan=plan,target:NativeWalletReminder=ticket)=
        nativeWalletReminderDelivery(target,active,current,Instant.parse(now),calendar,enabled,permission,last)
    @Test fun `native targets require active preference permission and exact owned schedule records`() {
        assertEquals(listOf(ticket.copy(fireAt=row.createdAt)),nativeWalletReminderTargets(owner,plan,zone,true,true))
        assertTrue(nativeWalletReminderTargets(owner,plan,zone,false,true).isEmpty())
        assertTrue(nativeWalletReminderTargets(owner,plan,zone,true,false).isEmpty())
        val foreign=row.copy(ownerUserId="33333333-3333-3333-3333-333333333333")
        assertTrue(nativeWalletReminderTargets(owner,plan.copy(scheduled=listOf(foreign)),zone,true,true).isEmpty())
    }
    @Test fun `delivery uses fresh eligible content even when inbox already moved to next morning`() {
        assertEquals(row,deliver())
    }
    @Test fun `early previous day and next day late deliveries are ignored`() {
        assertNull(deliver(now="2026-10-13T23:59:59Z"))
        assertNull(deliver(now="2026-10-15T00:01:00Z"))
        assertEquals(row,deliver(now="2026-10-14T00:00:00Z"))
    }
    @Test fun `signed out foreign account disabled preference and denied permission suppress delivery`() {
        assertNull(deliver(active=null));assertNull(deliver(active=UserId("33333333-3333-3333-3333-333333333333")))
        assertNull(deliver(enabled=false));assertNull(deliver(permission=false))
    }
    @Test fun `device zone change invalidates old civil morning alarm`() {
        assertNull(deliver(calendar=ZoneId.of("UTC")))
    }
    @Test fun `recovered deleted archived and missing wallet schedule targets cannot deliver old copy`() {
        assertNull(deliver(current=plan.copy(scheduled=emptyList())))
        assertNull(deliver(current=plan.copy(scheduled=listOf(row.copy(kind="billOverdue")))))
    }
    @Test fun `same or newer durable delivery prevents replay while yesterday does not`() {
        assertNull(deliver(last=ticket.fireAt));assertNull(deliver(last="2026-10-15T00:00:00Z"))
        assertEquals(row,deliver(last="2026-10-13T00:00:00Z"))
    }
    @Test fun `read inbox history does not suppress next daily OS reminder matching Swift`() {
        val read=row.copy(isRead=true,readAt="2026-10-13T00:00:00Z")
        assertEquals(read,deliver(current=plan.copy(scheduled=listOf(read))))
    }
    @Test fun `invalid alarm wallet key or non morning timestamp is rejected`() {
        assertNull(deliver(target=ticket.copy(key="different")))
        assertNull(deliver(target=ticket.copy(fireAt="2026-10-13T23:00:00Z")))
        assertNull(deliver(target=ticket.copy(walletId="invalid")))
    }
}
