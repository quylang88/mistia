package vn.com.quyln.mistia

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.sync.BackgroundBillMaintenanceTask

@EntryPoint
@InstallIn(SingletonComponent::class)
interface BillMaintenanceWorkerEntryPoint {
    fun backgroundBillMaintenance():BackgroundBillMaintenanceTask
}

/** Resolves real application dependencies even when WorkManager starts a fresh process. */
class BillMaintenanceWorker(context:Context,parameters:WorkerParameters):CoroutineWorker(context,parameters) {
    override suspend fun doWork():Result = try {
        val task=EntryPointAccessors.fromApplication(applicationContext,BillMaintenanceWorkerEntryPoint::class.java).backgroundBillMaintenance()
        task.run().fold(onSuccess={Result.success()},onFailure={Result.retry()})
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(_:Exception) {Result.retry()}

    companion object {
        const val UNIQUE_WORK_NAME="mistia-local-bill-maintenance"
        fun schedule(context:Context) {
            val request=PeriodicWorkRequestBuilder<BillMaintenanceWorker>(1,TimeUnit.HOURS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL,1,TimeUnit.MINUTES)
                .build()
            // No network/notification-permission constraint: local automatic payment works offline.
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(UNIQUE_WORK_NAME,ExistingPeriodicWorkPolicy.KEEP,request)
        }
    }
}
