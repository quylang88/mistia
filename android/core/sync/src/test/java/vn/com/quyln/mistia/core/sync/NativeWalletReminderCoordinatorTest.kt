package vn.com.quyln.mistia.core.sync

import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito
import vn.com.quyln.mistia.core.model.*

class NativeWalletReminderCoordinatorTest {
    private val account=UserId("11111111-1111-1111-1111-111111111111")
    private val walletId="22222222-2222-2222-2222-222222222222"
    private val zone=ZoneId.of("Asia/Tokyo")
    private var current:UserId?=account
    private var enabled=true
    private var time=Instant.parse("2026-10-13T23:00:00Z")
    private var wallet=LedgerWalletRecord(walletId,account.value,"Cash","cash","wallet","#000000","JPY",0,null,null,0,false,null,
        "2026-10-13T00:00:00Z","2026-10-13T00:00:00Z",null,0,null,null,null)
    private fun snapshot()=WalletReminderSnapshot(account,WalletReminderSnapshot.entities.associateWith {entity ->
        if(entity==CloudEntity.LEDGER_WALLET) listOf(wallet.toCloudRecord()) else emptyList()
    },emptyList())
    private fun plan()=snapshot().plan(time,zone,true) {w,b ->WalletReminderText("Low","${w.name} $b")}
    private class Platform:NativeWalletReminderPlatform {
        override var permissionGranted=true
        var state=NativeWalletReminderState();val schedules=mutableListOf<NativeWalletReminder>();val cancelled=mutableListOf<NativeWalletReminder>()
        val posts=mutableListOf<Pair<NativeWalletReminder,AppNotificationRecord>>();val dismissed=mutableListOf<String>();var retained=emptySet<String>()
        var onPost:(()->Unit)?=null;var onSchedule:(()->Unit)?=null;var onCancel:(()->Unit)?=null;var failPost=false
        override fun readState()=state
        override fun writeState(state:NativeWalletReminderState) {this.state=state}
        override fun schedule(ticket:NativeWalletReminder) {onSchedule?.invoke();schedules+=ticket}
        override fun cancel(ticket:NativeWalletReminder) {onCancel?.invoke();cancelled+=ticket}
        override fun post(ticket:NativeWalletReminder,record:AppNotificationRecord) {if(failPost) throw java.io.IOException("OS unavailable");posts+=ticket to record;onPost?.invoke()}
        override fun dismiss(tag:String) {dismissed+=tag}
        override fun retainDisplayed(tags:Set<String>) {retained=tags}
    }
    private suspend fun coordinator(platform:Platform):NativeWalletReminderCoordinator {
        val store=Mockito.mock(LocalStore::class.java)
        Mockito.`when`(store.walletReminderSnapshot(account)).thenAnswer {snapshot()}
        return NativeWalletReminderCoordinator(store,platform,{current},{enabled},{time},{zone}) {w,b ->WalletReminderText("Low","${w.name} $b")}
    }
    @Test fun `reconcile durably tracks and schedules next local morning without posting early`()=runTest {
        val platform=Platform();val service=coordinator(platform)
        service.reconcile(account,plan())
        assertEquals(1,platform.state.pending.size);assertEquals(platform.state.pending,platform.schedules);assertTrue(platform.posts.isEmpty())
    }
    @Test fun `due delivery reads fresh wallet copy and ledger prevents replay`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan())
        val ticket=platform.state.pending.single();time=Instant.parse(ticket.fireAt).plusSeconds(5);wallet=wallet.copy(name="Renamed",openingBalanceMinor=-1)
        service.deliver(ticket);service.deliver(ticket)
        assertEquals(1,platform.posts.size);assertEquals("Renamed -1",platform.posts.single().second.body)
        assertEquals(ticket.fireAt,platform.state.delivered[ticket.tag])
    }
    @Test fun `funding wallet before delivery suppresses stale notification`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt).plusSeconds(5);wallet=wallet.copy(openingBalanceMinor=1);service.deliver(ticket)
        assertTrue(platform.posts.isEmpty());assertTrue(platform.state.delivered.isEmpty())
    }
    @Test fun `disable or revoke permission cancels pending and displayed native reminders`()=runTest {
        for(permissionRevoked in listOf(false,true)) {
            enabled=true;val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
            if(permissionRevoked) platform.permissionGranted=false else enabled=false
            service.reconcile(account,plan())
            assertTrue(platform.state.pending.isEmpty());assertEquals(listOf(ticket),platform.cancelled);assertTrue(platform.retained.isEmpty())
        }
    }
    @Test fun `sign out clears pending and displayed reminders but keeps daily delivery history`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        platform.state=platform.state.copy(delivered=mapOf(ticket.tag to ticket.fireAt));current=null;service.clear()
        assertTrue(platform.state.pending.isEmpty());assertEquals(ticket.fireAt,platform.state.delivered[ticket.tag]);assertEquals(listOf(ticket),platform.cancelled)
    }
    @Test fun `account flip during platform post immediately dismisses old owner notification`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.onPost={current=null}
        assertTrue(runCatching {service.deliver(ticket)}.exceptionOrNull() is CancellationException)
        assertEquals(listOf(ticket.tag),platform.dismissed);assertTrue(platform.state.delivered.isEmpty())
    }
    @Test fun `scheduling failure leaves durable alarm intent for later cleanup`()=runTest {
        val platform=Platform();val service=coordinator(platform)
        platform.onSchedule={throw java.io.IOException("OS unavailable")}
        assertTrue(runCatching {service.reconcile(account,plan())}.isFailure)
        assertEquals(1,platform.state.pending.size)
        service.clear();assertTrue(platform.state.pending.isEmpty());assertEquals(1,platform.cancelled.size)
    }
    @Test fun `failed OS post does not mark delivery and can retry once platform recovers`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.failPost=true
        assertTrue(runCatching {service.deliver(ticket)}.isFailure);assertTrue(platform.state.delivered.isEmpty())
        platform.failPost=false;service.deliver(ticket);assertEquals(1,platform.posts.size)
    }
    @Test fun `funding during native post dismisses stale copy and preserves retry history`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.onPost={wallet=wallet.copy(openingBalanceMinor=1)}
        service.deliver(ticket);assertEquals(listOf(ticket.tag),platform.dismissed);assertTrue(platform.state.delivered.isEmpty())
    }
    @Test fun `suppressed funded wallet alarm is consumed and cannot replay when balance later falls`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);wallet=wallet.copy(openingBalanceMinor=1);service.deliver(ticket)
        wallet=wallet.copy(openingBalanceMinor=0);time=time.plusSeconds(3600);service.reconcile(account,plan())
        service.deliver(ticket)
        assertTrue(platform.posts.isEmpty());assertEquals("2026-10-15T00:00:00Z",platform.state.pending.single().fireAt)
    }
    @Test fun `permission denied at delivery consumes alarm instead of replaying after later grant`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.permissionGranted=false;service.deliver(ticket)
        platform.permissionGranted=true;time=time.plusSeconds(3600);service.reconcile(account,plan());service.deliver(ticket)
        assertTrue(platform.posts.isEmpty())
    }
    @Test fun `failed alarm cancellation keeps tracked intent and delivery nonce for safe cleanup retry`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.onCancel={throw java.io.IOException("OS cancellation unavailable")}
        assertTrue(runCatching {service.deliver(ticket)}.isFailure)
        assertEquals(listOf(ticket),platform.state.pending);assertEquals(ticket.fireAt,platform.state.delivered[ticket.tag])
        platform.onCancel=null;service.deliver(ticket)
        assertEquals(1,platform.posts.size);assertTrue(platform.state.pending.isEmpty());assertEquals(listOf(ticket),platform.cancelled)
    }
    @Test fun `unrelated wallet metadata change during post does not cancel unchanged eligible content`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.onPost={wallet=wallet.copy(updatedAt="2026-10-14T00:00:01Z")}
        service.deliver(ticket);assertTrue(platform.dismissed.isEmpty());assertEquals(ticket.fireAt,platform.state.delivered[ticket.tag])
    }
    @Test fun `preference disabled during native post dismisses without marking delivered`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val ticket=platform.state.pending.single()
        time=Instant.parse(ticket.fireAt);platform.onPost={enabled=false}
        service.deliver(ticket);assertEquals(listOf(ticket.tag),platform.dismissed);assertTrue(platform.state.delivered.isEmpty())
    }
    @Test fun `periodic reconcile delivers a due persisted alarm before moving schedule to tomorrow`()=runTest {
        val platform=Platform();val service=coordinator(platform);service.reconcile(account,plan());val old=platform.state.pending.single()
        time=Instant.parse(old.fireAt).plusSeconds(3600);service.reconcile(account,plan())
        assertEquals(1,platform.posts.size);assertEquals(old.fireAt,platform.state.delivered[old.tag])
        assertEquals("2026-10-15T00:00:00Z",platform.state.pending.single().fireAt)
    }
}
