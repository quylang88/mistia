package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*

/** Serial local entry point; owner changes cancel work, token refreshes do not. */
class BillMaintenanceCoordinator(
    private val auth:StateFlow<AuthState>,
    private val repository:BillMaintenanceRepository,
    private val deviceId:()->String,
    private val now:()->String,
) {
    private val mutex=Mutex()
    suspend fun run():Result<BillMaintenanceReport?> = mutex.withLock {
        val owner=currentOwner() ?: return@withLock Result.success(null)
        try {
            coroutineScope {
                val work=async(start=CoroutineStart.LAZY) {
                    ensureOwner(owner)
                    repository.maintainRecurringBills(owner,deviceId(),now()).also {ensureOwner(owner)}
                }
                val watcher=launch(start=CoroutineStart.UNDISPATCHED) {
                    auth.first { (it as? AuthState.SignedIn)?.session?.userId!=owner }
                    work.cancel(CancellationException("Bill maintenance account changed"))
                }
                try {work.start();work.await()} finally {watcher.cancel()}
            }
        } catch(cancelled:CancellationException) {throw cancelled}
          catch(error:Exception) {Result.failure(error)}
    }
    private fun currentOwner()=(auth.value as? AuthState.SignedIn)?.session?.userId
    private fun ensureOwner(owner:UserId) {
        if(currentOwner()!=owner) throw CancellationException("Bill maintenance account changed")
    }
}
