package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import vn.com.quyln.mistia.core.model.*

internal class OfflineAppNotificationRepository(private val store:LocalStore):AppNotificationRepository {
    override fun observeAppNotifications(owner:UserId):Flow<List<AppNotificationRecord>> = store.observeLocalNotifications(owner)
    override suspend fun markNotificationsRead(owner:UserId,keys:Set<String>?,now:String):Result<Unit> = try {
        UUID.fromString(owner.value)
        val reference=Instant.parse(now)
        val initial=store.localNotifications(owner)
        val targets=notificationGroups(owner,initial,reference).flatMap {it.rows}.filter {keys==null || it.key in keys}.associateBy {it.key}
        var committed=false
        for(attempt in 0 until 3) {
            currentCoroutineContext().ensureActive()
            val current=if(attempt==0) initial else store.localNotifications(owner)
            val replacement=current.map {row -> if(targets[row.key]==row && !row.isRead) markLocalNotificationRead(row,now) else row}
            if(current==replacement || store.commitLocalNotifications(owner,current,replacement)) {committed=true;break}
        }
        check(committed) {"Notifications changed during read update"}
        Result.success(Unit)
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(error:Exception) {Result.failure(error)}
}
