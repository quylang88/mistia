package vn.com.quyln.mistia

import android.app.Application
import kotlinx.coroutines.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.sync.NativeWalletReminderCoordinator
import vn.com.quyln.mistia.core.sync.observeWalletReminderChanges
import vn.com.quyln.mistia.core.sync.observeDueMaintenancePreferenceChanges
import vn.com.quyln.mistia.core.sync.BillMaintenanceCoordinator
import java.time.Instant
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.sync.SyncRuntime

@HiltAndroidApp
class MistiaApplication : Application() {
    @Inject lateinit var syncEngine: SyncEngine
    @Inject lateinit var auth:AuthRepository
    @Inject lateinit var preferences:NotificationPreferencesStore
    @Inject lateinit var localStore:LocalStore
    @Inject lateinit var walletReminders:WalletReminderRepository
    @Inject lateinit var nativeWalletReminders:NativeWalletReminderCoordinator
    @Inject lateinit var bills:BillMaintenanceCoordinator
    private val processScope=CoroutineScope(SupervisorJob()+Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        SyncRuntime.engine = syncEngine
        BillMaintenanceWorker.schedule(this)
        processScope.launch {
            observeDueMaintenancePreferenceChanges(auth.state,preferences.state) {owner ->
                bills.run(expectedOwner=owner).getOrThrow()
            }
        }
        processScope.launch {
            observeWalletReminderChanges(auth.state,preferences.state,localStore,
                refresh={owner -> walletReminders.maintainWalletReminders(owner,Instant.now().toString()).getOrThrow()},
                clear={nativeWalletReminders.clear()})
        }
    }
}
