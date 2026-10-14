package vn.com.quyln.mistia.core.database

import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class WalletReminderRepositoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val now="2026-10-14T00:00:00Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val data=BudgetMemoryStore()
    private val finance=OfflineFirstFinanceRepository(data,zone)
    private var active:UserId?=owner
    private var enabled=true
    private suspend fun fixture():LedgerWalletRecord=finance.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=0),
        "22222222-2222-2222-2222-222222222222",now).getOrThrow()
    private class Store(private val data:LocalStore,private val owner:UserId):LocalStore by data {
        var rows=emptyList<AppNotificationRecord>();var commits=0;var beforeCommit:(suspend ()->Unit)?=null
        override suspend fun localNotifications(owner:UserId)=rows
        override suspend fun walletReminderSnapshot(owner:UserId)=WalletReminderSnapshot(owner,WalletReminderSnapshot.entities.associateWith {data.recordsIncludingDeleted(owner,it.table)},rows)
        override suspend fun commitWalletReminders(expected:WalletReminderSnapshot,replacement:List<AppNotificationRecord>):Boolean {
            commits++;beforeCommit?.invoke()
            try {expected.requireUnchanged(walletReminderSnapshot(owner))} catch(_:IllegalArgumentException) {return false}
            rows=replacement;return true
        }
    }
    private fun repo(store:LocalStore)=OfflineWalletReminderRepository(store,{zone},{enabled},{active}) {wallet,balance ->WalletReminderText("Low", "${wallet.name} $balance")}
    @Test fun `local reminder persists future copy without financial or cloud outbox mutation`()=runTest {
        val wallet=fixture();val store=Store(data,owner)
        val before=data.outboxRows(owner.value)
        val result=repo(store).maintainWalletReminders(owner,now).getOrThrow()
        assertEquals(wallet.id,result.scheduled.single().resourceId);assertEquals(result.inbox,store.rows)
        assertEquals(before,data.outboxRows(owner.value))
    }
    @Test fun `balance dependency race retries fresh data instead of inserting stale low wallet reminder`()=runTest {
        val wallet=fixture();val store=Store(data,owner)
        store.beforeCommit={store.beforeCommit=null
            val funded=wallet.copy(openingBalanceMinor=1)
            data.replacePullSnapshot(owner,CloudEntity.LEDGER_WALLET.table,listOf(funded.toCloudRecord()))
        }
        val result=repo(store).maintainWalletReminders(owner,now).getOrThrow()
        assertEquals(2,store.commits);assertTrue(result.scheduled.isEmpty());assertTrue(store.rows.isEmpty())
    }
    @Test fun `read race retries and preserves new read history`()=runTest {
        fixture();val store=Store(data,owner);val repository=repo(store)
        repository.maintainWalletReminders(owner,now).getOrThrow()
        store.beforeCommit={store.beforeCommit=null;store.rows=store.rows.map {markLocalNotificationRead(it,now)}}
        val result=repository.maintainWalletReminders(owner,"2026-10-14T01:00:00Z").getOrThrow()
        assertTrue(result.inbox.single().isRead);assertEquals(now,result.inbox.single().readAt)
    }
    @Test fun `account switch during snapshot cancels before commit`()=runTest {
        fixture();val store=Store(data,owner)
        val raced=object:LocalStore by store {
            override suspend fun walletReminderSnapshot(owner:UserId)=store.walletReminderSnapshot(owner).also {active=null}
        }
        assertTrue(runCatching {repo(raced).maintainWalletReminders(owner,now)}.exceptionOrNull() is CancellationException)
        assertEquals(0,store.commits);assertTrue(store.rows.isEmpty())
    }
    @Test fun `exhausted CAS retries return failure without inserting notification`()=runTest {
        fixture();val store=Store(data,owner)
        val raced=object:LocalStore by store {
            override suspend fun commitWalletReminders(expected:WalletReminderSnapshot,replacement:List<AppNotificationRecord>)=false
        }
        assertTrue(repo(raced).maintainWalletReminders(owner,now).isFailure);assertTrue(store.rows.isEmpty())
    }
}
