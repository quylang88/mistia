package vn.com.quyln.mistia

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.*
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import vn.com.quyln.mistia.core.model.NativeWalletReminder
import vn.com.quyln.mistia.core.sync.NativeWalletReminderCoordinator
import vn.com.quyln.mistia.core.sync.SessionRestorationCoordinator

@EntryPoint
@InstallIn(SingletonComponent::class)
interface WalletReminderDeliveryEntryPoint {
    fun nativeWalletReminderCoordinator():NativeWalletReminderCoordinator
    fun sessionRestoration():SessionRestorationCoordinator
}
class WalletReminderAlarmReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val raw=intent.getStringExtra(WalletReminderDeliveryWorker.TICKET) ?: return
        val ticket=runCatching {Json.decodeFromString<NativeWalletReminder>(raw)}.getOrNull() ?: return
        val work=OneTimeWorkRequestBuilder<WalletReminderDeliveryWorker>().setInputData(workDataOf(WalletReminderDeliveryWorker.TICKET to raw)).build()
        WorkManager.getInstance(context).enqueueUniqueWork("${ticket.tag}.${ticket.fireAt}",ExistingWorkPolicy.KEEP,work)
    }
}
class WalletReminderClockReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        WorkManager.getInstance(context).enqueueUniqueWork("mistia-local-wallet-clock-change",ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<BillMaintenanceWorker>().build())
    }
}
class WalletReminderDeliveryWorker(context:Context,parameters:WorkerParameters):CoroutineWorker(context,parameters) {
    override suspend fun doWork():Result {
        val ticket=runCatching {Json.decodeFromString<NativeWalletReminder>(inputData.getString(TICKET) ?: return Result.failure())}.getOrNull()
            ?: return Result.failure()
        return try {
            val dependencies=EntryPointAccessors.fromApplication(applicationContext,WalletReminderDeliveryEntryPoint::class.java)
            dependencies.sessionRestoration().ensureRestored()
            dependencies.nativeWalletReminderCoordinator().deliver(ticket)
            Result.success()
        } catch(cancelled:CancellationException) {throw cancelled}
          catch(_:Exception) {Result.retry()}
    }
    companion object {const val TICKET="nativeWalletReminder"}
}
