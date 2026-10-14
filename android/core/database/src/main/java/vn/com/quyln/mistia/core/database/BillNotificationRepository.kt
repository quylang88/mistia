package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

internal class OfflineBillNotificationRepository(private val store:LocalStore,private val zone:ZoneId,
    private val text:(BillNotificationMessage)->BillNotificationText) {
    suspend fun persist(owner:UserId,report:BillMaintenanceReport,reference:Instant) {
        repeat(3) {
            currentCoroutineContext().ensureActive()
            val snapshot=store.billNotificationSnapshot(owner)
            val rows=planBillNotifications(snapshot,report,reference,zone,text)
            if(store.commitBillNotifications(snapshot,rows)) return
        }
        error("Bill notifications changed during maintenance")
    }
}
