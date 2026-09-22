package vn.com.quyln.mistia.core.sync

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.IOException
import java.time.Duration
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.model.AuthState
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.ReadOnlyCloudCollection
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.SyncEngine
import vn.com.quyln.mistia.core.model.SyncStatus
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class PullOnlySyncEngine(
    private val appContext: Context,
    private val authRepository: AuthRepository,
    private val localStore: LocalStore,
    private val remoteStore: RemoteStore,
    private val walletPushCoordinator: WalletPushCoordinator,
) : SyncEngine {
    private val mutex = Mutex()
    private val mutableStatus = MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    override val status: StateFlow<SyncStatus> = mutableStatus.asStateFlow()

    override suspend fun syncNow(): Result<Int> = mutex.withLock {
        runCatching {
            val session = signedInSession()
            mutableStatus.value = SyncStatus.Pushing(CloudEntity.LEDGER_WALLET.table)
            val push = walletPushCoordinator.pushPending(session.userId, session.accessToken)
            val totalRecords = pullAllTables(session.accessToken, session.userId)
            when {
                push.retryableFailures > 0 -> throw WalletPushRetryException(push.retryableFailures)
                push.conflicts + push.permanentFailures > 0 -> {
                    mutableStatus.value = SyncStatus.Failed(
                        message = "wallet_push_needs_attention",
                        retryable = false,
                    )
                }
                else -> mutableStatus.value = SyncStatus.Success(totalRecords, System.currentTimeMillis())
            }
            totalRecords
        }.onFailure { error ->
            mutableStatus.value = SyncStatus.Failed(
                message = error.message ?: error::class.java.simpleName,
                retryable = error.isRetryableSyncFailure(),
            )
        }
    }

    override suspend fun pullAll(): Result<Int> = mutex.withLock {
        runCatching {
            val session = signedInSession()
            pullAllTables(session.accessToken, session.userId).also { totalRecords ->
                mutableStatus.value = SyncStatus.Success(totalRecords, System.currentTimeMillis())
            }
        }.onFailure { error ->
            mutableStatus.value = SyncStatus.Failed(
                message = error.message ?: error::class.java.simpleName,
                retryable = error.isRetryableSyncFailure(),
            )
        }
    }

    override fun scheduleBackgroundSync() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val periodic = PeriodicWorkRequestBuilder<MistiaSyncWorker>(Duration.ofHours(6))
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(appContext).enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            periodic,
        )
    }

    private suspend fun pullTable(
        table: String,
        accessToken: String,
        ownerUserId: UserId,
    ): List<CloudRecord> {
        val result = mutableListOf<CloudRecord>()
        var offset: Int? = 0
        while (offset != null) {
            val page = remoteStore.pullPage(
                table = table,
                accessToken = accessToken,
                ownerUserId = ownerUserId,
                offset = offset,
                limit = PAGE_SIZE,
            )
            page.records.mapNotNullTo(result) { it.toCloudRecord(table, ownerUserId) }
            offset = page.nextOffset
        }
        return result
    }

    private suspend fun signedInSession() = authRepository.refreshIfNeeded().getOrThrow()
        ?: (authRepository.state.value as? AuthState.SignedIn)?.session
        ?: error("Sign in before syncing")

    private suspend fun pullAllTables(accessToken: String, ownerUserId: UserId): Int {
        val requiredTables = CloudEntity.pullOrder.map(CloudEntity::table)
        val optionalTables = ReadOnlyCloudCollection.entries.map(ReadOnlyCloudCollection::table)
        val allTables = requiredTables + optionalTables
        var totalRecords = 0
        allTables.forEachIndexed { index, table ->
            mutableStatus.value = SyncStatus.Pulling(table, index, allTables.size)
            val rows = try {
                pullTable(table, accessToken, ownerUserId)
            } catch (error: SupabaseHttpException) {
                if (table in optionalTables && error.statusCode in setOf(400, 404)) emptyList()
                else throw error
            }
            localStore.replacePullSnapshot(ownerUserId, table, rows)
            totalRecords += rows.size
        }
        return totalRecords
    }

    private fun JsonObject.toCloudRecord(entity: String, ownerUserId: UserId): CloudRecord? {
        val id = string("id") ?: string("user_id") ?: string("device_id") ?: return null
        return CloudRecord(
            entity = entity,
            id = id,
            ownerUserId = ownerUserId.value,
            payload = this,
            updatedAt = string("updated_at"),
            deletedAt = string("deleted_at"),
            syncVersion = long("sync_version"),
        )
    }

    private fun JsonObject.string(key: String): String? =
        (get(key) as? JsonPrimitive)?.contentOrNull

    private fun JsonObject.long(key: String): Long =
        (get(key) as? JsonPrimitive)?.longOrNull ?: 0

    private companion object {
        const val PAGE_SIZE = 500
        const val PERIODIC_WORK_NAME = "mistia-cloud-periodic-pull"
    }
}

object SyncRuntime {
    @Volatile
    var engine: SyncEngine? = null
}

class MistiaSyncWorker(
    appContext: Context,
    workerParameters: WorkerParameters,
) : CoroutineWorker(appContext, workerParameters) {
    override suspend fun doWork(): Result {
        val engine = SyncRuntime.engine ?: return Result.retry()
        return engine.syncNow().fold(
            onSuccess = { Result.success() },
            onFailure = { error ->
                if (error.isRetryableSyncFailure()) {
                    Result.retry()
                } else {
                    Result.failure()
                }
            },
        )
    }
}

private class WalletPushRetryException(failureCount: Int) :
    IOException("$failureCount wallet mutation(s) are waiting to retry")

internal fun Throwable.isRetryableSyncFailure(): Boolean = when (this) {
    is SupabaseHttpException -> statusCode >= 500 || statusCode == 408 || statusCode == 429
    is IOException -> true
    else -> false
}
