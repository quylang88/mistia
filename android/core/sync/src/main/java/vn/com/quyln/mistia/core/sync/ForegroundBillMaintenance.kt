package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive

/** Runs only while the caller's foreground lifecycle scope remains active. */
suspend fun runForegroundBillMaintenance(
    synchronize:suspend ()->Result<Int>,
    maintain:suspend ()->Unit,
    intervalMillis:Long=60_000L,
) {
    require(intervalMillis>0)
    try {synchronize()} catch(cancelled:CancellationException) {throw cancelled}
        catch(_:Exception) { /* Cached local maintenance remains available offline. */ }
    while(true) {
        currentCoroutineContext().ensureActive()
        try {maintain()} catch(cancelled:CancellationException) {throw cancelled}
            catch(_:Exception) { /* A failed local pass can retry at the next tick. */ }
        delay(intervalMillis)
    }
}
