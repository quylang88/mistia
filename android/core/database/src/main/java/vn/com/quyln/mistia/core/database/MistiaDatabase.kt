package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.UserId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

@Entity(
    tableName = "cloud_records",
    primaryKeys = ["owner_user_id", "entity", "record_id"],
    indices = [
        Index(value = ["owner_user_id", "entity", "deleted_at"]),
        Index(value = ["owner_user_id", "updated_at"]),
    ],
)
data class CloudRecordEntity(
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    val entity: String,
    @ColumnInfo(name = "record_id") val recordId: String,
    @ColumnInfo(name = "payload_json") val payloadJson: String,
    @ColumnInfo(name = "updated_at") val updatedAt: String?,
    @ColumnInfo(name = "deleted_at") val deletedAt: String?,
    @ColumnInfo(name = "sync_version") val syncVersion: Long,
    @ColumnInfo(name = "has_pending_mutation") val hasPendingMutation: Boolean = false,
    @ColumnInfo(name = "received_at_epoch_millis") val receivedAtEpochMillis: Long,
)

@Entity(
    tableName = "sync_outbox",
    primaryKeys = ["owner_user_id", "entity", "record_id"],
    indices = [Index(value = ["owner_user_id", "next_attempt_at_epoch_millis"])],
)
data class SyncOutboxEntity(
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    val entity: String,
    @ColumnInfo(name = "record_id") val recordId: String,
    val kind: String,
    @ColumnInfo(name = "payload_json") val payloadJson: String?,
    @ColumnInfo(name = "modified_at") val modifiedAt: String,
    @ColumnInfo(name = "base_version") val baseVersion: Long,
    @ColumnInfo(name = "device_id") val deviceId: String,
    @ColumnInfo(name = "attempt_count") val attemptCount: Int = 0,
    @ColumnInfo(name = "next_attempt_at_epoch_millis") val nextAttemptAtEpochMillis: Long = 0,
    @ColumnInfo(name = "last_error") val lastError: String? = null,
)

@Entity(
    tableName = "sync_cursors",
    primaryKeys = ["owner_user_id", "entity"],
)
data class SyncCursorEntity(
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    val entity: String,
    @ColumnInfo(name = "last_full_pull_epoch_millis") val lastFullPullEpochMillis: Long,
    @ColumnInfo(name = "last_record_count") val lastRecordCount: Int,
)

data class EntityCountProjection(
    val entity: String,
    val count: Int,
)

@Dao
interface CloudRecordDao {
    @Query(
        """
        SELECT * FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND entity = :entity AND deleted_at IS NULL
        ORDER BY updated_at DESC, record_id ASC
        """
    )
    fun observeActive(ownerUserId: String, entity: String): Flow<List<CloudRecordEntity>>

    @Query(
        """
        SELECT entity, COUNT(*) AS count FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND deleted_at IS NULL
        GROUP BY entity ORDER BY entity
        """
    )
    fun observeCounts(ownerUserId: String): Flow<List<EntityCountProjection>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(records: List<CloudRecordEntity>)

    @Query(
        """
        DELETE FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND entity = :entity AND has_pending_mutation = 0
        """
    )
    suspend fun deleteCleanSnapshot(ownerUserId: String, entity: String)

    @Query("DELETE FROM cloud_records WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface SyncOutboxDao {
    @Query("SELECT record_id FROM sync_outbox WHERE owner_user_id = :ownerUserId AND entity = :entity")
    suspend fun recordIds(ownerUserId: String, entity: String): List<String>

    @Query("DELETE FROM sync_outbox WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface SyncCursorDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(cursor: SyncCursorEntity)

    @Query("DELETE FROM sync_cursors WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Database(
    entities = [CloudRecordEntity::class, SyncOutboxEntity::class, SyncCursorEntity::class],
    version = 1,
    exportSchema = true,
)
abstract class MistiaDatabase : RoomDatabase() {
    abstract fun cloudRecordDao(): CloudRecordDao
    abstract fun syncOutboxDao(): SyncOutboxDao
    abstract fun syncCursorDao(): SyncCursorDao

    companion object {
        fun create(context: Context): MistiaDatabase =
            Room.databaseBuilder(context, MistiaDatabase::class.java, "mistia-android.db")
                .build()
    }
}

class RoomLocalStore(
    private val database: MistiaDatabase,
    private val json: Json = Json { ignoreUnknownKeys = true },
) : LocalStore {
    override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
        database.cloudRecordDao().observeActive(ownerUserId.value, entity).map { rows ->
            rows.map { row ->
                CloudRecord(
                    entity = row.entity,
                    id = row.recordId,
                    ownerUserId = row.ownerUserId,
                    payload = json.parseToJsonElement(row.payloadJson) as JsonObject,
                    updatedAt = row.updatedAt,
                    deletedAt = row.deletedAt,
                    syncVersion = row.syncVersion,
                )
            }
        }

    override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
        database.cloudRecordDao().observeCounts(ownerUserId.value).map { rows ->
            rows.map { EntityCount(entity = it.entity, count = it.count) }
        }

    override suspend fun replacePullSnapshot(
        ownerUserId: UserId,
        entity: String,
        records: List<CloudRecord>,
    ) {
        database.withTransaction {
            val pendingIds = database.syncOutboxDao().recordIds(ownerUserId.value, entity).toSet()
            database.cloudRecordDao().deleteCleanSnapshot(ownerUserId.value, entity)
            val now = System.currentTimeMillis()
            database.cloudRecordDao().upsert(
                records.asSequence()
                    .filterNot { it.id in pendingIds }
                    .map {
                        CloudRecordEntity(
                            ownerUserId = ownerUserId.value,
                            entity = entity,
                            recordId = it.id,
                            payloadJson = it.payload.toString(),
                            updatedAt = it.updatedAt,
                            deletedAt = it.deletedAt,
                            syncVersion = it.syncVersion,
                            receivedAtEpochMillis = now,
                        )
                    }
                    .toList()
            )
            database.syncCursorDao().upsert(
                SyncCursorEntity(
                    ownerUserId = ownerUserId.value,
                    entity = entity,
                    lastFullPullEpochMillis = now,
                    lastRecordCount = records.size,
                )
            )
        }
    }

    override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String): Set<String> =
        database.syncOutboxDao().recordIds(ownerUserId.value, entity).toSet()

    override suspend fun clearAccount(ownerUserId: UserId) {
        database.withTransaction {
            database.cloudRecordDao().deleteAccount(ownerUserId.value)
            database.syncOutboxDao().deleteAccount(ownerUserId.value)
            database.syncCursorDao().deleteAccount(ownerUserId.value)
        }
    }
}
