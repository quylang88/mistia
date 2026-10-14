package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.BillMaintenanceReport

/** Cold-process pipeline; does not need Activity state, notification permission or HTTP sync. */
class BackgroundBillMaintenanceTask(private val restoration:SessionRestorationCoordinator,private val maintenance:BillMaintenanceCoordinator) {
    suspend fun run():Result<BillMaintenanceReport?> = try {
        restoration.ensureRestored()
        maintenance.run()
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(error:Exception) {Result.failure(error)}
}
