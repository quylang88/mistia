package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*

class OfflineWalletReminderRepository(private val store:LocalStore,private val zone:()->ZoneId,
    private val enabled:()->Boolean,private val currentOwner:()->UserId?,
    private val text:(LedgerWalletRecord,Long)->WalletReminderText):WalletReminderRepository {
    private val mutex=Mutex()
    private fun ensureOwner(owner:UserId) {
        if(currentOwner()!=owner) throw CancellationException("Wallet reminder account changed")
    }
    override suspend fun maintainWalletReminders(owner:UserId,now:String):Result<WalletReminderPlan> = try {
        Result.success(mutex.withLock {
            val reference=Instant.parse(now)
            val calendar=zone()
            var saved:WalletReminderPlan?=null
            for(attempt in 0 until 3) {
                currentCoroutineContext().ensureActive();ensureOwner(owner)
                val snapshot=store.walletReminderSnapshot(owner)
                ensureOwner(owner)
                val plan=snapshot.plan(reference,calendar,enabled(),text)
                if(store.commitWalletReminders(snapshot,plan.inbox)) {
                    val rows=store.localNotifications(owner)
                    ensureOwner(owner)
                    saved=WalletReminderPlan(rows,if(enabled()) plan.scheduled.filter {it in rows} else emptyList())
                    break
                }
            }
            checkNotNull(saved) {"Wallet reminder dependencies changed during maintenance"}
        })
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(error:Exception) {Result.failure(error)}
}
