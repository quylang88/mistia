package vn.com.quyln.mistia.core.database

import vn.com.quyln.mistia.core.model.InstallmentPaymentAcknowledgementSnapshot
import vn.com.quyln.mistia.core.model.InstallmentPaymentAcknowledgement
import vn.com.quyln.mistia.core.model.planInstallmentPaymentAcknowledgement
import vn.com.quyln.mistia.core.model.planInstallmentSkipSync
import vn.com.quyln.mistia.core.model.InstallmentSkipSyncDecision

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
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.model.WalletReminderSnapshot
import vn.com.quyln.mistia.core.model.applyBillReminderPreference
import vn.com.quyln.mistia.core.model.resolveLocalBillNotifications
import vn.com.quyln.mistia.core.model.resolveTerminalBillWriteNotifications
import vn.com.quyln.mistia.core.model.BillNotificationSnapshot
import vn.com.quyln.mistia.core.model.requireUnchangedBillNotifications
import vn.com.quyln.mistia.core.model.upsertLocalNotification
import vn.com.quyln.mistia.core.model.AppNotificationRecord
import vn.com.quyln.mistia.core.model.requireValidLocalNotification
import vn.com.quyln.mistia.core.model.SystemCategoryIdentityMigration
import vn.com.quyln.mistia.core.model.planObservedSystemCategoryMaintenance
import vn.com.quyln.mistia.core.model.SystemCategoryCatalog
import vn.com.quyln.mistia.core.model.planSystemCategoryIdentityMigration
import vn.com.quyln.mistia.core.model.CategoryReferenceSnapshot
import vn.com.quyln.mistia.core.model.categoryReferenceEntities
import vn.com.quyln.mistia.core.model.planCategoryReferenceRepairs
import vn.com.quyln.mistia.core.model.billCycleRecords
import vn.com.quyln.mistia.core.model.InstallmentDeletionCompletion
import vn.com.quyln.mistia.core.model.planInstallmentDeletionCompletion
import vn.com.quyln.mistia.core.model.InstallmentAcknowledgementSnapshot
import vn.com.quyln.mistia.core.model.InstallmentSourceAckDecision
import vn.com.quyln.mistia.core.model.planInstallmentSourceAcknowledgement
import vn.com.quyln.mistia.core.model.InstallmentDeletionStorage
import vn.com.quyln.mistia.core.model.InstallmentDeletionBlob
import vn.com.quyln.mistia.core.model.InstallmentDeletionChunk
import vn.com.quyln.mistia.core.model.InstallmentDeletionBatch
import vn.com.quyln.mistia.core.model.InstallmentCycleSnapshot
import vn.com.quyln.mistia.core.model.InstallmentMutationSnapshot
import vn.com.quyln.mistia.core.model.TransactionSaveSnapshot
import vn.com.quyln.mistia.core.model.BillMoneySnapshot
import vn.com.quyln.mistia.core.model.requireValidMutations
import vn.com.quyln.mistia.core.model.requireUnchanged
import vn.com.quyln.mistia.core.model.financeRawReference
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.isConsistentlyDeleted
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.PendingCategoryTranslation
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedCategoryTranslation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRecord
import vn.com.quyln.mistia.core.model.UserId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

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
    @ColumnInfo(name = "remote_identity_observed", defaultValue = "0") val remoteIdentityObserved: Boolean = false,
)

@Entity(
    tableName = "category_translation_outbox",
    primaryKeys = ["owner_user_id", "category_id"],
    indices = [Index(value = ["owner_user_id", "next_attempt_at_epoch_millis"])],
)
data class CategoryTranslationOutboxEntity(
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    @ColumnInfo(name = "category_id") val categoryId: String,
    @ColumnInfo(name = "input_name") val inputName: String,
    @ColumnInfo(name = "source_language") val sourceLanguage: String,
    @ColumnInfo(name = "saved_updated_at") val savedUpdatedAt: String,
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

@Entity(
    tableName = "transaction_receipt_images",
    indices = [
        Index(value = ["owner_user_id"]),
        Index(value = ["transaction_id"], unique = true),
    ],
)
data class TransactionReceiptImageEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    @ColumnInfo(name = "transaction_id") val transactionId: String,
    @ColumnInfo(name = "image_file_name") val imageFileName: String,
    @ColumnInfo(name = "thumbnail_file_name") val thumbnailFileName: String,
    @ColumnInfo(name = "content_type") val contentType: String,
    @ColumnInfo(name = "byte_count") val byteCount: Int,
    @ColumnInfo(name = "created_at") val createdAt: String,
    @ColumnInfo(name = "updated_at") val updatedAt: String,
)

data class EntityCountProjection(
    val entity: String,
    val count: Int,
)

@Dao
interface CloudRecordDao {
    @Query("DELETE FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity = :entity AND record_id = :recordId")
    suspend fun deleteRecord(ownerUserId:String,entity:String,recordId:String):Int

    @Query("SELECT * FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity = :entity ORDER BY record_id ASC")
    suspend fun recordsIncludingDeleted(ownerUserId: String, entity: String): List<CloudRecordEntity>

    @Query(
        """
        SELECT * FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND entity = :entity AND deleted_at IS NULL
        ORDER BY updated_at DESC, record_id ASC
        """
    )
    fun observeActive(ownerUserId: String, entity: String): Flow<List<CloudRecordEntity>>

    @Query("SELECT * FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity IN (:entities) ORDER BY entity ASC, record_id ASC")
    fun observeInvestmentChannelRows(ownerUserId:String,entities:List<String>):Flow<List<CloudRecordEntity>>

    @Query("SELECT * FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity IN (:entities) ORDER BY entity ASC, record_id ASC")
    suspend fun investmentChannelRows(ownerUserId:String,entities:List<String>):List<CloudRecordEntity>

    @Query("SELECT * FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity IN (:entities) ORDER BY entity ASC, record_id ASC")
    fun observeOverviewFinancialRows(ownerUserId:String,entities:List<String>):Flow<List<CloudRecordEntity>>

    @Query("SELECT * FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity IN (:entities) ORDER BY entity ASC, record_id ASC")
    fun observeBudgetRows(ownerUserId:String,entities:List<String>):Flow<List<CloudRecordEntity>>

    @Query("SELECT * FROM cloud_records WHERE owner_user_id = :ownerUserId AND entity IN (:entities) ORDER BY entity ASC, record_id ASC")
    fun observeUpcomingDueRows(ownerUserId:String,entities:List<String>):Flow<List<CloudRecordEntity>>

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

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: CloudRecordEntity)

    @Query(
        """
        SELECT * FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND entity = :entity AND record_id = :recordId
        LIMIT 1
        """
    )
    suspend fun record(ownerUserId: String, entity: String, recordId: String): CloudRecordEntity?

    @Query(
        """
        SELECT * FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND entity = :entity AND deleted_at IS NULL
        ORDER BY updated_at DESC, record_id ASC
        LIMIT :limit
        """
    )
    suspend fun activeRecords(ownerUserId: String, entity: String, limit: Int): List<CloudRecordEntity>

    @Query(
        """
        DELETE FROM cloud_records
        WHERE owner_user_id = :ownerUserId AND entity = :entity AND has_pending_mutation = 0
          AND NOT (entity = 'installment_plans' AND EXISTS (
            SELECT 1 FROM installment_delete_batches AS batch
            WHERE batch.owner_user_id = cloud_records.owner_user_id
              AND batch.plan_id = cloud_records.record_id
          ))
        """
    )
    suspend fun deleteCleanSnapshot(ownerUserId: String, entity: String)

    @Query("DELETE FROM cloud_records WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface SyncOutboxDao {
    @Query("SELECT * FROM sync_outbox WHERE owner_user_id = :ownerUserId AND entity = :entity AND record_id = :recordId")
    suspend fun record(ownerUserId:String,entity:String,recordId:String):SyncOutboxEntity?

    @Query("SELECT record_id FROM sync_outbox WHERE owner_user_id = :ownerUserId AND entity = :entity")
    suspend fun recordIds(ownerUserId: String, entity: String): List<String>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(row: SyncOutboxEntity)

    @Query(
        """
        SELECT * FROM sync_outbox
        WHERE owner_user_id = :ownerUserId
        ORDER BY modified_at ASC, entity ASC, record_id ASC
        """
    )
    suspend fun rows(ownerUserId: String): List<SyncOutboxEntity>

    @Query(
        """
        SELECT * FROM sync_outbox
        WHERE owner_user_id = :ownerUserId
          AND entity = :entity
          AND next_attempt_at_epoch_millis <= :dueAtEpochMillis
        ORDER BY modified_at ASC, record_id ASC
        LIMIT :limit
        """
    )
    suspend fun dueRows(
        ownerUserId: String,
        entity: String,
        dueAtEpochMillis: Long,
        limit: Int,
    ): List<SyncOutboxEntity>

    @Query(
        """
        DELETE FROM sync_outbox
        WHERE owner_user_id = :ownerUserId
          AND entity = :entity
          AND record_id = :recordId
          AND modified_at = :modifiedAt
          AND base_version = :baseVersion
          AND device_id = :deviceId
          AND attempt_count = :attemptCount
          AND kind = :kind
          AND payload_json IS :payloadJson
          AND remote_identity_observed = :remoteIdentityObserved
        """
    )
    suspend fun deleteExact(
        ownerUserId: String,
        entity: String,
        recordId: String,
        modifiedAt: String,
        baseVersion: Long,
        deviceId: String,
        attemptCount: Int,
        kind: String,
        payloadJson: String?,
        remoteIdentityObserved: Boolean,
    ): Int

    @Query(
        """
        UPDATE sync_outbox
        SET attempt_count = attempt_count + 1,
            next_attempt_at_epoch_millis = :nextAttemptAtEpochMillis,
            last_error = :errorCode
        WHERE owner_user_id = :ownerUserId
          AND entity = :entity
          AND record_id = :recordId
          AND modified_at = :modifiedAt
          AND base_version = :baseVersion
          AND device_id = :deviceId
          AND attempt_count = :attemptCount
          AND kind = :kind
          AND payload_json IS :payloadJson
          AND remote_identity_observed = :remoteIdentityObserved
        """
    )
    suspend fun markFailureExact(
        ownerUserId: String,
        entity: String,
        recordId: String,
        modifiedAt: String,
        baseVersion: Long,
        deviceId: String,
        attemptCount: Int,
        kind: String,
        payloadJson: String?,
        remoteIdentityObserved: Boolean,
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Int

    @Query("DELETE FROM sync_outbox WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface CategoryTranslationOutboxDao {
    @Query("DELETE FROM category_translation_outbox WHERE owner_user_id = :ownerUserId AND category_id = :categoryId")
    suspend fun deleteCategory(ownerUserId:String,categoryId:String):Int

    @Query("SELECT * FROM category_translation_outbox WHERE owner_user_id = :ownerUserId ORDER BY category_id ASC")
    suspend fun rows(ownerUserId: String): List<CategoryTranslationOutboxEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(row: CategoryTranslationOutboxEntity)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(row: CategoryTranslationOutboxEntity): Long

    @Query(
        """
        SELECT * FROM category_translation_outbox
        WHERE owner_user_id = :ownerUserId
          AND next_attempt_at_epoch_millis <= :dueAtEpochMillis
        ORDER BY saved_updated_at ASC, category_id ASC
        LIMIT :limit
        """
    )
    suspend fun dueRows(
        ownerUserId: String,
        dueAtEpochMillis: Long,
        limit: Int,
    ): List<CategoryTranslationOutboxEntity>

    @Query(
        """
        DELETE FROM category_translation_outbox
        WHERE owner_user_id = :ownerUserId
          AND category_id = :categoryId
          AND input_name = :inputName
          AND source_language = :sourceLanguage
          AND saved_updated_at = :savedUpdatedAt
          AND attempt_count = :attemptCount
          AND device_id = :deviceId
        """
    )
    suspend fun deleteExact(
        ownerUserId: String,
        categoryId: String,
        inputName: String,
        sourceLanguage: String,
        savedUpdatedAt: String,
        attemptCount: Int,
        deviceId: String,
    ): Int

    @Query(
        """
        UPDATE category_translation_outbox
        SET attempt_count = attempt_count + 1,
            next_attempt_at_epoch_millis = :nextAttemptAtEpochMillis,
            last_error = :errorCode
        WHERE owner_user_id = :ownerUserId
          AND category_id = :categoryId
          AND input_name = :inputName
          AND source_language = :sourceLanguage
          AND saved_updated_at = :savedUpdatedAt
          AND attempt_count = :attemptCount
          AND device_id = :deviceId
        """
    )
    suspend fun markFailureExact(
        ownerUserId: String,
        categoryId: String,
        inputName: String,
        sourceLanguage: String,
        savedUpdatedAt: String,
        attemptCount: Int,
        deviceId: String,
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Int

    @Query("DELETE FROM category_translation_outbox WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface SyncCursorDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(cursor: SyncCursorEntity)

    @Query("DELETE FROM sync_cursors WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface TransactionReceiptImageDao {
    @Query("SELECT * FROM transaction_receipt_images WHERE id = :id LIMIT 1")
    suspend fun receiptById(id:String):TransactionReceiptImageEntity?
    @Query(
        """
        SELECT * FROM transaction_receipt_images
        WHERE transaction_id = :transactionId
        LIMIT 1
        """
    )
    suspend fun receipt(transactionId: String): TransactionReceiptImageEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun replace(receipt: TransactionReceiptImageEntity)

    @Query("DELETE FROM transaction_receipt_images WHERE transaction_id = :transactionId")
    suspend fun delete(transactionId: String)

    @Query("SELECT * FROM transaction_receipt_images WHERE owner_user_id = :ownerUserId")
    suspend fun receipts(ownerUserId: String): List<TransactionReceiptImageEntity>

    @Query("DELETE FROM transaction_receipt_images WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Database(
    entities = [
        CloudRecordEntity::class,
        SyncOutboxEntity::class,
        SyncCursorEntity::class,
        CategoryTranslationOutboxEntity::class,
        TransactionReceiptImageEntity::class,
        LocalNotificationEntity::class,
        InstallmentDeletionBatchEntity::class,
        InstallmentDeletionChunkEntity::class,
    ],
    version = 6,
    exportSchema = true,
)
abstract class MistiaDatabase : RoomDatabase() {
    abstract fun installmentDeletionDao(): InstallmentDeletionDao
    abstract fun localNotificationDao(): LocalNotificationDao
    abstract fun cloudRecordDao(): CloudRecordDao
    abstract fun syncOutboxDao(): SyncOutboxDao
    abstract fun categoryTranslationOutboxDao(): CategoryTranslationOutboxDao
    abstract fun syncCursorDao(): SyncCursorDao
    abstract fun transactionReceiptImageDao(): TransactionReceiptImageDao

    companion object {
        fun create(context: Context): MistiaDatabase =
            Room.databaseBuilder(context, MistiaDatabase::class.java, "mistia-android.db")
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6)
                .build()

        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS installment_delete_batches (owner_user_id TEXT NOT NULL, plan_id TEXT NOT NULL, batch_id TEXT NOT NULL, payload_json TEXT NOT NULL, PRIMARY KEY(owner_user_id, plan_id))")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS index_installment_delete_batches_owner_user_id_batch_id ON installment_delete_batches (owner_user_id, batch_id)")
                db.execSQL("CREATE TABLE IF NOT EXISTS installment_delete_chunks (owner_user_id TEXT NOT NULL, plan_id TEXT NOT NULL, batch_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(owner_user_id, plan_id, chunk_index), FOREIGN KEY(owner_user_id, plan_id) REFERENCES installment_delete_batches(owner_user_id, plan_id) ON UPDATE NO ACTION ON DELETE CASCADE)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_installment_delete_chunks_owner_user_id_plan_id ON installment_delete_chunks (owner_user_id, plan_id)")
            }
        }

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS local_app_notifications (owner_user_id TEXT NOT NULL, notification_key TEXT NOT NULL, payload_json TEXT NOT NULL, PRIMARY KEY(owner_user_id, notification_key))")
            }
        }

        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE sync_outbox ADD COLUMN remote_identity_observed INTEGER NOT NULL DEFAULT 0")
                db.execSQL("UPDATE sync_outbox SET remote_identity_observed = 1 WHERE base_version > 0")
            }
        }

        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `category_translation_outbox` (
                        `owner_user_id` TEXT NOT NULL,
                        `category_id` TEXT NOT NULL,
                        `input_name` TEXT NOT NULL,
                        `source_language` TEXT NOT NULL,
                        `saved_updated_at` TEXT NOT NULL,
                        `device_id` TEXT NOT NULL,
                        `attempt_count` INTEGER NOT NULL,
                        `next_attempt_at_epoch_millis` INTEGER NOT NULL,
                        `last_error` TEXT,
                        PRIMARY KEY(`owner_user_id`, `category_id`)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_category_translation_outbox_owner_user_id_next_attempt_at_epoch_millis` " +
                        "ON `category_translation_outbox` (`owner_user_id`, `next_attempt_at_epoch_millis`)"
                )
            }
        }

        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `transaction_receipt_images` (
                        `id` TEXT NOT NULL,
                        `owner_user_id` TEXT NOT NULL,
                        `transaction_id` TEXT NOT NULL,
                        `image_file_name` TEXT NOT NULL,
                        `thumbnail_file_name` TEXT NOT NULL,
                        `content_type` TEXT NOT NULL,
                        `byte_count` INTEGER NOT NULL,
                        `created_at` TEXT NOT NULL,
                        `updated_at` TEXT NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_transaction_receipt_images_owner_user_id` " +
                        "ON `transaction_receipt_images` (`owner_user_id`)"
                )
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_transaction_receipt_images_transaction_id` " +
                        "ON `transaction_receipt_images` (`transaction_id`)"
                )
            }
        }
    }
}

internal class RoomTransactionReceiptMetadataStore(
    private val database:MistiaDatabase,
) : TransactionReceiptMetadataStore {
    private val dao=database.transactionReceiptImageDao()
    override suspend fun receipt(transactionId: String): TransactionReceiptImageRecord? =
        dao.receipt(transactionId)?.toRecord()

    override suspend fun replace(record: TransactionReceiptImageRecord) {
        dao.replace(record.toEntity())
    }

    override suspend fun replaceIfCurrent(expected:TransactionReceiptImageRecord?,record:TransactionReceiptImageRecord):Boolean {
        val caller=kotlinx.coroutines.currentCoroutineContext();caller.ensureActive()
        return database.withTransaction {
            if(expected!=null && (expected.ownerUserId!=record.ownerUserId || expected.transactionId!=record.transactionId))return@withTransaction false
            if(dao.receipt(record.transactionId)?.toRecord()!=expected)return@withTransaction false
            val occupied=dao.receiptById(record.id)?.toRecord()
            if(occupied!=null && occupied!=expected)return@withTransaction false
            dao.replace(record.toEntity())
            caller.ensureActive();kotlinx.coroutines.currentCoroutineContext().ensureActive()
            true
        }
    }

    override suspend fun deleteIfCurrent(expected:TransactionReceiptImageRecord):Boolean {
        val caller=kotlinx.coroutines.currentCoroutineContext();caller.ensureActive()
        return database.withTransaction {
            if(dao.receipt(expected.transactionId)?.toRecord()!=expected)return@withTransaction false
            dao.delete(expected.transactionId)
            caller.ensureActive();kotlinx.coroutines.currentCoroutineContext().ensureActive()
            true
        }
    }

    override suspend fun delete(transactionId: String) {
        dao.delete(transactionId)
    }

    override suspend fun receipts(ownerUserId: String): List<TransactionReceiptImageRecord> =
        dao.receipts(ownerUserId).map(TransactionReceiptImageEntity::toRecord)

    override suspend fun deleteAccount(ownerUserId: String) {
        dao.deleteAccount(ownerUserId)
    }
}

private fun TransactionReceiptImageEntity.toRecord() = TransactionReceiptImageRecord(
    id = id,
    ownerUserId = ownerUserId,
    transactionId = transactionId,
    imageFileName = imageFileName,
    thumbnailFileName = thumbnailFileName,
    contentType = contentType,
    byteCount = byteCount,
    createdAt = createdAt,
    updatedAt = updatedAt,
)

private fun TransactionReceiptImageRecord.toEntity() = TransactionReceiptImageEntity(
    id = id,
    ownerUserId = ownerUserId,
    transactionId = transactionId,
    imageFileName = imageFileName,
    thumbnailFileName = thumbnailFileName,
    contentType = contentType,
    byteCount = byteCount,
    createdAt = createdAt,
    updatedAt = updatedAt,
)

class RoomLocalStore(
    private val database: MistiaDatabase,
    private val json: Json = Json { ignoreUnknownKeys = true },
    private val billRemindersEnabled:()->Boolean = {true},
    private val walletRemindersEnabled:()->Boolean = {true},
    private val currentBillOwner:(()->UserId?)? = null,
) : LocalStore {
    private fun ensureCurrentFinanceOwner(owner:UserId) {
        if(currentBillOwner!=null && currentBillOwner.invoke()!=owner)
            throw kotlinx.coroutines.CancellationException("Finance operation account changed")
    }

    override suspend fun walletReminderSnapshot(owner:UserId):WalletReminderSnapshot = database.withTransaction {
        WalletReminderSnapshot(owner,WalletReminderSnapshot.entities.associateWith {recordsIncludingDeleted(owner,it.table)},localNotifications(owner))
    }
    override suspend fun commitWalletReminders(expected:WalletReminderSnapshot,replacement:List<AppNotificationRecord>):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        try {expected.requireUnchanged(walletReminderSnapshot(expected.owner))} catch(_:IllegalArgumentException) {return@withTransaction false}
        replacement.forEach {it.requireValidLocalNotification();require(it.ownerUserId==expected.owner.value)}
        require(replacement.map {it.key}.distinct().size==replacement.size)
        val rows=if(walletRemindersEnabled()) replacement else expected.notifications.filterNot {it.kind=="dueSoon" || it.key.startsWith("mistia.reminder.due.")}
        val committed=commitLocalNotifications(expected.owner,expected.notifications,rows)
        ensureCurrentFinanceOwner(expected.owner)
        committed
    }

    override suspend fun billNotificationSnapshot(owner:UserId):BillNotificationSnapshot = database.withTransaction {
        BillNotificationSnapshot(owner,recordsIncludingDeleted(owner,CloudEntity.RECURRING_BILL_PLAN.table),
            recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table),localNotifications(owner))
    }

    override suspend fun commitBillNotifications(expected:BillNotificationSnapshot,replacement:List<AppNotificationRecord>):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=billNotificationSnapshot(expected.owner)
        try {expected.requireUnchangedBillNotifications(current)} catch (_:IllegalArgumentException) {return@withTransaction false}
        replacement.forEach {it.requireValidLocalNotification();require(it.ownerUserId==expected.owner.value)}
        require(replacement.map {it.key}.distinct().size==replacement.size)
        val committed=commitLocalNotifications(expected.owner,expected.notifications,
            applyBillReminderPreference(expected.notifications,replacement,billRemindersEnabled()))
        ensureCurrentFinanceOwner(expected.owner)
        committed
    }

    override fun observeLocalNotifications(owner:UserId):Flow<List<AppNotificationRecord>> =
        database.localNotificationDao().observe(owner.value).map {rows -> rows.map {decodeNotification(owner,it)}}

    override suspend fun localNotifications(owner:UserId):List<AppNotificationRecord> =
        database.localNotificationDao().rows(owner.value).map {decodeNotification(owner,it)}

    private fun decodeNotification(owner:UserId,row:LocalNotificationEntity):AppNotificationRecord =
        json.decodeFromString<AppNotificationRecord>(row.payloadJson).also {
            it.requireValidLocalNotification()
            require(it.ownerUserId==owner.value && row.ownerUserId==owner.value && row.notificationKey==it.key)
        }

    override suspend fun commitLocalNotifications(owner:UserId,expected:List<AppNotificationRecord>,replacement:List<AppNotificationRecord>):Boolean = database.withTransaction {
        (expected+replacement).forEach {it.requireValidLocalNotification();require(it.ownerUserId==owner.value)}
        require(expected.map {it.key}.distinct().size==expected.size && replacement.map {it.key}.distinct().size==replacement.size)
        if(localNotifications(owner).associateBy {it.key}!=expected.associateBy {it.key}) return@withTransaction false
        database.localNotificationDao().deleteAccount(owner.value)
        database.localNotificationDao().upsert(replacement.map {LocalNotificationEntity(owner.value,it.key,json.encodeToString(AppNotificationRecord.serializer(),it))})
        true
    }

    override suspend fun commitSystemCategoryIdentityMigration(expected:CategoryReferenceSnapshot,queued:QueuedMutation,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean = database.withTransaction {
        val current=readCategoryReferenceSnapshot(expected.owner)
        try {expected.requireUnchanged(current)} catch (_:IllegalArgumentException) {return@withTransaction false}
        val plan=planSystemCategoryIdentityMigration(expected,queued,remote,catalog,deviceId,now)
        val adoption=plan.adoption
        val pending=queued.mutation
        check(database.syncOutboxDao().deleteExact(pending.subjectUserId,pending.entity.table,pending.recordId,pending.modifiedAt,
            pending.baseVersion,pending.deviceId,queued.attemptCount,pending.kind.name.lowercase(),pending.payload?.toString(),queued.remoteIdentityObserved)==1)
        database.categoryTranslationOutboxDao().deleteCategory(expected.owner.value,adoption.source.id)
        if(plan.removesSourceIdentity) check(database.cloudRecordDao().deleteRecord(expected.owner.value,CloudEntity.TRANSACTION_CATEGORY.table,adoption.source.id)==1)
        installCategoryIdentityPlan(plan)
        true
    }

    override suspend fun commitObservedSystemCategoryMaintenance(expected:CategoryReferenceSnapshot,key:String,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):Boolean = database.withTransaction {
        val current=readCategoryReferenceSnapshot(expected.owner)
        try {expected.requireUnchanged(current)} catch (_:IllegalArgumentException) {return@withTransaction false}
        val plan=planObservedSystemCategoryMaintenance(current,key,remote,catalog,deviceId,now) ?: return@withTransaction true
        check(!plan.removesSourceIdentity)
        installCategoryIdentityPlan(plan)
        true
    }

    private suspend fun installCategoryIdentityPlan(plan:SystemCategoryIdentityMigration) {
        val adoption=plan.adoption
        plan.retainedCategories.forEach {database.cloudRecordDao().upsert(it.toEntity(false,System.currentTimeMillis()))}
        val targetMutation=adoption.mutation
        if(targetMutation==null) database.cloudRecordDao().upsert(adoption.target.toEntity(false,System.currentTimeMillis()))
        else commitMutationRows(adoption.target,targetMutation,remoteIdentityObserved=true)
        plan.references.mutations.forEach {commitMutationRows(it.record,it.mutation)}
        (plan.references.translations+listOfNotNull(adoption.translation)).forEach {database.categoryTranslationOutboxDao().upsert(it.toEntity())}
    }

    override suspend fun categoryReferenceSnapshot(owner: UserId): CategoryReferenceSnapshot = database.withTransaction {
        readCategoryReferenceSnapshot(owner)
    }

    private suspend fun readCategoryReferenceSnapshot(owner: UserId) = CategoryReferenceSnapshot(
        owner,
        categoryReferenceEntities.associateWith { entity ->
            database.cloudRecordDao().recordsIncludingDeleted(owner.value, entity.table).map {it.toCloudRecord()}
        },
        database.syncOutboxDao().rows(owner.value)
            .filter {CloudEntity.fromTable(it.entity) in categoryReferenceEntities}.map {it.toQueuedMutation()},
        database.categoryTranslationOutboxDao().rows(owner.value).map {it.toQueuedTranslation()},
    )

    override suspend fun commitCategoryReferenceRepairs(expected: CategoryReferenceSnapshot, oldId: String, newId: String, deviceId: String, now: String): Boolean = database.withTransaction {
        val current = readCategoryReferenceSnapshot(expected.owner)
        try { expected.requireUnchanged(current) } catch (_: IllegalArgumentException) { return@withTransaction false }
        val plan = planCategoryReferenceRepairs(expected, oldId, newId, deviceId, now)
        plan.mutations.forEach {commitMutationRows(it.record, it.mutation)}
        plan.translations.forEach {database.categoryTranslationOutboxDao().upsert(it.toEntity())}
        true
    }

    override suspend fun recordsIncludingDeleted(ownerUserId: UserId, entity: String): List<CloudRecord> =
        database.cloudRecordDao().recordsIncludingDeleted(ownerUserId.value, entity).map { it.toCloudRecord() }

    override suspend fun commitInvestmentCashTransferLifecycle(expected:vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot,
        request:vn.com.quyln.mistia.core.model.InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=investmentCashSnapshot(expected.owner)
        val order=compareBy<CloudRecord>({it.entity},{it.id})
        if(expected.owner!=current.owner || expected.rows.sortedWith(order)!=current.rows.sortedWith(order))return@withTransaction false
        val plan=vn.com.quyln.mistia.core.model.planInvestmentCashTransferLifecycle(current,request,deviceId,now)
        plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
        ensureCurrentFinanceOwner(expected.owner)
        true
    }

    override suspend fun commitInvestmentCashTransfer(expected:vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot,
        request:vn.com.quyln.mistia.core.model.InvestmentCashTransferRequest,deviceId:String,now:String):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=investmentCashSnapshot(expected.owner)
        val order=compareBy<CloudRecord>({it.entity},{it.id})
        if(expected.owner!=current.owner || expected.rows.sortedWith(order)!=current.rows.sortedWith(order))return@withTransaction false
        val plan=vn.com.quyln.mistia.core.model.planInvestmentCashTransfer(current,request,deviceId,now)
        if(plan.mutations.any{(row,_) ->current.rows.none{it.entity==row.entity && it.id==row.id} &&
            database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)!=null})return@withTransaction false
        plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
        ensureCurrentFinanceOwner(expected.owner)
        true
    }

    override suspend fun commitInvestmentCashReconciliation(expected:vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot,
        request:vn.com.quyln.mistia.core.model.InvestmentCashReconciliationRequest,deviceId:String,now:String):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=investmentCashSnapshot(expected.owner)
        val order=compareBy<CloudRecord>({it.entity},{it.id})
        if(expected.owner!=current.owner || expected.rows.sortedWith(order)!=current.rows.sortedWith(order))return@withTransaction false
        val plan=vn.com.quyln.mistia.core.model.planInvestmentCashReconciliation(current,request,deviceId,now)
        if(plan.mutations.any{(row,_) ->current.rows.none{it.entity==row.entity && it.id==row.id} &&
            database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)!=null})return@withTransaction false
        plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
        ensureCurrentFinanceOwner(expected.owner)
        true
    }

    override fun observeInvestmentCashSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot> =
        database.cloudRecordDao().observeInvestmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot.entities.map{it.table})
            .map{rows ->vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot(owner,rows.map{it.toCloudRecord()})}

    override suspend fun investmentCashSnapshot(owner:UserId):vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val rows=database.cloudRecordDao().investmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot.entities.map{it.table})
        ensureCurrentFinanceOwner(owner)
        vn.com.quyln.mistia.core.model.InvestmentCashReadSnapshot(owner,rows.map{it.toCloudRecord()})
    }

    override fun observeInvestmentWalletSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot> =
        database.cloudRecordDao().observeInvestmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot.entities.map{it.table})
            .map{rows ->vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot(owner,rows.map{it.toCloudRecord()})}

    override suspend fun investmentWalletSnapshot(owner:UserId):vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val rows=database.cloudRecordDao().investmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot.entities.map{it.table})
        ensureCurrentFinanceOwner(owner)
        vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot(owner,rows.map{it.toCloudRecord()})
    }

    override suspend fun commitInvestmentWalletLink(expected:vn.com.quyln.mistia.core.model.InvestmentWalletSnapshot,
        request:vn.com.quyln.mistia.core.model.InvestmentWalletLinkRequest,deviceId:String,now:String):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=investmentWalletSnapshot(expected.owner)
        if(runCatching{expected.requireUnchanged(current)}.isFailure)return@withTransaction false
        val plan=vn.com.quyln.mistia.core.model.planInvestmentWalletLink(current,request,deviceId,now)
        if(plan.mutations.any{(row,_) ->current.rows.none{it.entity==row.entity && it.id==row.id} &&
            database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)!=null})return@withTransaction false
        plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
        ensureCurrentFinanceOwner(expected.owner)
        true
    }

    override fun observeInvestmentPurchaseSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot> =
        database.cloudRecordDao().observeInvestmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot.entities.map{it.table})
            .map{rows->vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot(owner,rows.map{it.toCloudRecord()})}

    override suspend fun investmentPurchaseSnapshot(owner:UserId):vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot {
        val caller=kotlinx.coroutines.currentCoroutineContext();caller.ensureActive()
        return database.withTransaction {
            ensureCurrentFinanceOwner(owner)
            val rows=database.cloudRecordDao().investmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot.entities.map{it.table})
            ensureCurrentFinanceOwner(owner);caller.ensureActive()
            vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot(owner,rows.map{it.toCloudRecord()})
        }
    }

    override suspend fun commitInvestmentPurchase(expected:vn.com.quyln.mistia.core.model.InvestmentPurchaseSnapshot,
        request:vn.com.quyln.mistia.core.model.InvestmentPurchaseRequest,deviceId:String,now:String):Boolean {
        val caller=kotlinx.coroutines.currentCoroutineContext();caller.ensureActive()
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current=investmentPurchaseSnapshot(expected.owner)
            if(expected.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id))!=current.rows.sortedWith(compareBy(CloudRecord::entity,CloudRecord::id)))return@withTransaction false
            val plan=vn.com.quyln.mistia.core.model.planInvestmentPurchase(current,request,deviceId,now)
            val historyIds=current.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawReference("asset_id").id==request.draft.assetId}.map{it.id}.toSet()
            val historyLedgerIds=historyIds.flatMap{id->listOf("funding","capital-return","profit-loss").map{component->vn.com.quyln.mistia.core.model.investmentLedgerIdentity(id,component)}}.toSet()
            val protectedRows=current.rows.filter{row->
                (row.entity==CloudEntity.INVESTMENT_TRADE.table && row.id in historyIds) ||
                    (row.entity==CloudEntity.LEDGER_TRANSACTION.table && (row.id in historyLedgerIds || row.payload["settlement_role_raw_value"]==JsonPrimitive("investmentReserveUse"))) ||
                    (row.entity==CloudEntity.INVESTMENT_POSTING.table && (row.payload.financeRawReference("trade_id").id in historyIds ||
                        (row.payload["cash_origin_raw_value"]==JsonPrimitive("derived") && row.payload["role_raw_value"] in setOf(JsonPrimitive("cashConsumption"),JsonPrimitive("cashTransfer"))))) ||
                    plan.mutations.any{it.first.entity==row.entity && it.first.id==row.id}
            }
            for(row in protectedRows) {
                val queued=database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)
                val stored=database.cloudRecordDao().record(expected.owner.value,row.entity,row.id)!!
                require(!stored.hasPendingMutation || queued!=null){"Purchase pending record has no outbox"}
                if(queued!=null)require(stored.hasPendingMutation && queued.baseVersion==row.syncVersion &&
                    queued.kind==(if(row.deletedAt==null)"upsert" else "delete") && queued.modifiedAt==row.updatedAt &&
                    queued.payloadJson?.let{json.parseToJsonElement(it)}==row.payload){"Purchase outbox differs from current source"}
            }
            for((row,_) in plan.mutations) {
                require(current.rows.any{it.entity==row.entity && it.id==row.id} || database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)==null){"Purchase identity has orphan outbox"}
            }
            plan.mutations.forEach{(row,mutation)->commitMutationRows(row,mutation)}
            ensureCurrentFinanceOwner(expected.owner);caller.ensureActive();kotlinx.coroutines.currentCoroutineContext().ensureActive()
            true
        }
    }

    override fun observeInvestmentAssetSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot> =
        database.cloudRecordDao().observeInvestmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot.entities.map{it.table})
            .map{rows ->vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot(owner,rows.map{it.toCloudRecord()})}

    override suspend fun investmentAssetSnapshot(owner:UserId):vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val rows=database.cloudRecordDao().investmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot.entities.map{it.table})
        ensureCurrentFinanceOwner(owner)
        vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot(owner,rows.map{it.toCloudRecord()})
    }

    override suspend fun commitInvestmentAssetMutation(expected:vn.com.quyln.mistia.core.model.InvestmentAssetSnapshot,
        request:vn.com.quyln.mistia.core.model.InvestmentAssetRequest,deviceId:String,now:String):Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=investmentAssetSnapshot(expected.owner)
        if(runCatching{expected.requireUnchanged(current)}.isFailure)return@withTransaction false
        val plan=vn.com.quyln.mistia.core.model.planInvestmentAssetMutation(current,request,deviceId,now)
        if(plan.mutations.any{(row,_) ->current.rows.none{it.entity==row.entity && it.id==row.id} &&
            database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)!=null})return@withTransaction false
        plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
        ensureCurrentFinanceOwner(expected.owner)
        true
    }

    override fun observeInvestmentChannelSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot> =
        database.cloudRecordDao().observeInvestmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot.entities.map {it.table})
            .map {rows ->vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot(owner,rows.map {it.toCloudRecord()})}

    override suspend fun investmentChannelSnapshot(owner:UserId):vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val rows=database.cloudRecordDao().investmentChannelRows(owner.value,vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot.entities.map {it.table})
        ensureCurrentFinanceOwner(owner)
        vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot(owner,rows.map {it.toCloudRecord()})
    }

    override suspend fun commitInvestmentChannels(expected:vn.com.quyln.mistia.core.model.InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean {
        expected.requireValidMutations(mutations)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current=investmentChannelSnapshot(expected.owner)
            if(runCatching {expected.requireUnchanged(current)}.isFailure) return@withTransaction false
            if(mutations.any {(row,_) ->expected.rows.none {it.entity==row.entity && it.id==row.id} &&
                database.syncOutboxDao().record(expected.owner.value,row.entity,row.id)!=null}) return@withTransaction false
            mutations.forEach {(record,mutation) ->commitMutationRows(record,mutation)}
            ensureCurrentFinanceOwner(expected.owner)
            true
        }
    }

    override fun observeBudgetReadSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.BudgetReadSnapshot> =
        database.cloudRecordDao().observeBudgetRows(owner.value,vn.com.quyln.mistia.core.model.BudgetReadSnapshot.entities.map {it.table})
            .map {rows ->vn.com.quyln.mistia.core.model.BudgetReadSnapshot(owner,rows.map {it.toCloudRecord()})}

    override fun observeOverviewFinancialReadSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.OverviewFinancialReadSnapshot> =
        database.cloudRecordDao().observeOverviewFinancialRows(owner.value,vn.com.quyln.mistia.core.model.OverviewFinancialReadSnapshot.entities.map {it.table})
            .map {rows ->vn.com.quyln.mistia.core.model.OverviewFinancialReadSnapshot(owner,rows.map {it.toCloudRecord()})}

    override fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<vn.com.quyln.mistia.core.model.UpcomingDueReadSnapshot> =
        database.cloudRecordDao().observeUpcomingDueRows(owner.value,vn.com.quyln.mistia.core.model.UpcomingDueReadSnapshot.entities.map {it.table})
            .map {rows ->vn.com.quyln.mistia.core.model.UpcomingDueReadSnapshot(owner,rows.map {it.toCloudRecord()})}

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

    override suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord? =
        database.cloudRecordDao().record(ownerUserId.value, entity, recordId)?.toCloudRecord()

    override suspend fun transactionInvestmentSaveSnapshot(owner:UserId):vn.com.quyln.mistia.core.model.TransactionInvestmentSaveSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val snapshot=vn.com.quyln.mistia.core.model.TransactionInvestmentSaveSnapshot(owner,
            vn.com.quyln.mistia.core.model.TransactionInvestmentSaveSnapshot.entities.associateWith{recordsIncludingDeleted(owner,it.table)})
        snapshot.requireValid()
        ensureCurrentFinanceOwner(owner)
        snapshot
    }

    override suspend fun transactionSaveSnapshot(owner: UserId): TransactionSaveSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val snapshot = TransactionSaveSnapshot(owner, TransactionSaveSnapshot.entities.associateWith { recordsIncludingDeleted(owner, it.table) })
        snapshot.requireValid()
        ensureCurrentFinanceOwner(owner)
        snapshot
    }

    override suspend fun commitTransactionInvestmentLifecycle(expected:vn.com.quyln.mistia.core.model.TransactionInvestmentSaveSnapshot,
        request:vn.com.quyln.mistia.core.model.TransactionInvestmentLifecycleRequest,deviceId:String,now:String,
        statementZone:java.time.ZoneId):vn.com.quyln.mistia.core.model.LedgerTransactionRecord {
        val caller=kotlinx.coroutines.currentCoroutineContext()
        caller.ensureActive()
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current=transactionInvestmentSaveSnapshot(expected.owner)
            expected.requireUnchanged(current)
            val plan=vn.com.quyln.mistia.core.model.planTransactionInvestmentLifecycle(current,request,deviceId,now,statementZone)
            for((record,_) in plan.mutations) {
                val previous=current.recordsByEntity.values.flatten().singleOrNull{it.entity==record.entity && it.id==record.id}
                require(previous!=null || database.syncOutboxDao().record(expected.owner.value,record.entity,record.id)==null) {"Transaction lifecycle identity has an orphan queue"}
            }
            plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
            ensureCurrentFinanceOwner(expected.owner)
            caller.ensureActive()
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            plan.record
        }
    }

    override suspend fun commitTransactionInvestmentSave(expected:vn.com.quyln.mistia.core.model.TransactionInvestmentSaveSnapshot,
        request:vn.com.quyln.mistia.core.model.TransactionInvestmentSaveRequest,deviceId:String,now:String,
        statementZone:java.time.ZoneId):vn.com.quyln.mistia.core.model.LedgerTransactionRecord {
        val caller=kotlinx.coroutines.currentCoroutineContext()
        caller.ensureActive()
        return database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        val current=transactionInvestmentSaveSnapshot(expected.owner)
        expected.requireUnchanged(current)
        val plan=vn.com.quyln.mistia.core.model.planTransactionInvestmentSave(current,request,deviceId,now,statementZone)
        for((record,_) in plan.mutations) {
            val previous=current.recordsByEntity.values.flatten().singleOrNull{it.entity==record.entity && it.id==record.id}
            require(previous!=null || database.syncOutboxDao().record(expected.owner.value,record.entity,record.id)==null) {"Ordinary/investment identity has an orphan queue"}
        }
        plan.mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
        ensureCurrentFinanceOwner(expected.owner)
        caller.ensureActive()
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        plan.record
        }
    }

    override suspend fun commitTransactionMutation(expected: TransactionSaveSnapshot, record: CloudRecord, mutation: PendingMutation) {
        expected.requireValidMutation(record, mutation)
        database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            expected.requireUnchanged(transactionSaveSnapshot(expected.owner))
            val previous = expected.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull { it.id == record.id }
            val queue = database.syncOutboxDao().record(expected.owner.value, record.entity, record.id)
            require(previous != null || queue == null) { "Transaction identity has an orphan queue" }
            commitMutationRows(record, mutation)
            ensureCurrentFinanceOwner(expected.owner)
        }
    }

    override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
        database.withTransaction {
            commitMutationRows(record, mutation)
        }
    }

    override suspend fun commitWalletCurrencyMutation(expectedWallet: CloudRecord, record: CloudRecord, mutation: PendingMutation) {
        requireWalletMetadataMutation(expectedWallet, record, mutation)
        val owner = UserId(record.ownerUserId)
        database.withTransaction {
            ensureCurrentFinanceOwner(owner)
            if (record(owner, expectedWallet.entity, expectedWallet.id) != expectedWallet)
                throw vn.com.quyln.mistia.core.model.WalletValidationException(vn.com.quyln.mistia.core.model.WalletValidationError.STALE_EDIT)
            if (vn.com.quyln.mistia.core.model.walletHasLiveLedgerHistory(owner, record.id, recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table)))
                throw vn.com.quyln.mistia.core.model.WalletValidationException(vn.com.quyln.mistia.core.model.WalletValidationError.CURRENCY_IN_USE)
            commitMutationRows(record, mutation)
            ensureCurrentFinanceOwner(owner)
        }
    }

    private fun requireWalletMetadataMutation(expectedWallet: CloudRecord, record: CloudRecord, mutation: PendingMutation) {
        require(expectedWallet.entity == CloudEntity.LEDGER_WALLET.table && record.entity == expectedWallet.entity)
        require(expectedWallet.ownerUserId == record.ownerUserId && expectedWallet.id == record.id)
        require(expectedWallet.deletedAt == null && record.deletedAt == null && mutation.kind == MutationKind.UPSERT)
        require(record.payload["user_id"] == JsonPrimitive(record.ownerUserId) && record.payload["id"] == JsonPrimitive(record.id))
        require(record.payload["opening_balance_minor"] == expectedWallet.payload["opening_balance_minor"]) { "Currency edit cannot rewrite opening money" }
        require(mutation.baseVersion == expectedWallet.syncVersion && record.syncVersion == expectedWallet.syncVersion &&
            record.payload["sync_version"] == JsonPrimitive(expectedWallet.syncVersion)) { "Wallet version envelope disagrees" }
    }

    override suspend fun commitMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        require(mutations.isNotEmpty())
        require(mutations.map { it.first.ownerUserId }.distinct().size == 1)
        require(mutations.map { it.first.entity to it.first.id }.distinct().size == mutations.size)
        database.withTransaction {
            mutations.forEach { (record, mutation) -> commitMutationRows(record, mutation) }
        }
    }

    override suspend fun installmentMutationSnapshot(owner: UserId, planId: String): InstallmentMutationSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val snapshot = InstallmentMutationSnapshot(owner, planId, InstallmentMutationSnapshot.entities.associateWith {
            recordsIncludingDeleted(owner, it.table)
        })
        ensureCurrentFinanceOwner(owner)
        snapshot
    }

    override suspend fun commitInstallmentCycleMutations(expected: InstallmentCycleSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean {
        expected.requireValidMutations(mutations)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.base.owner)
            val current = InstallmentMutationSnapshot.entities.associateWith { recordsIncludingDeleted(expected.base.owner, it.table) }
            if (runCatching { expected.base.requireUnchanged(current) }.isFailure) return@withTransaction false
            mutations.forEach { (record, mutation) -> commitMutationRows(record, mutation) }
            ensureCurrentFinanceOwner(expected.base.owner)
            true
        }
    }

    override suspend fun installmentPaymentAcknowledgementSnapshot(owner: UserId, planId: String): InstallmentPaymentAcknowledgementSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val snapshot = readInstallmentPaymentAcknowledgementSnapshot(owner, planId)
        ensureCurrentFinanceOwner(owner)
        snapshot
    }
    private suspend fun readInstallmentPaymentAcknowledgementSnapshot(owner: UserId, planId: String) = InstallmentPaymentAcknowledgementSnapshot(
        owner, planId, installmentDeletionBatch(owner, planId), InstallmentPaymentAcknowledgementSnapshot.entities.associateWith { recordsIncludingDeleted(owner, it.table) },
        database.syncOutboxDao().rows(owner.value).filter { CloudEntity.fromTable(it.entity) in InstallmentPaymentAcknowledgementSnapshot.entities }.map { it.toQueuedMutation() })

    override suspend fun commitInstallmentPaymentAcknowledgement(expected: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation,
        remotePlan: CloudRecord, remoteCycle: CloudRecord?, remoteLedger: Map<String, CloudRecord?>, remoteWallets: Map<String, CloudRecord?>): Boolean {
        val decision = planInstallmentPaymentAcknowledgement(expected, queued, remotePlan, remoteCycle, remoteLedger, remoteWallets)
        require(decision is InstallmentPaymentAcknowledgement.Acknowledge)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current = readInstallmentPaymentAcknowledgementSnapshot(expected.owner, expected.planId)
            if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
            check(removeQueuedMutationExact(queued))
            database.cloudRecordDao().upsert(decision.record.toEntity(false, System.currentTimeMillis()))
            ensureCurrentFinanceOwner(expected.owner)
            true
        }
    }
    override suspend fun recordInstallmentPaymentAcknowledgementFailure(expected: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation,
        nextAttemptAtEpochMillis: Long, errorCode: String): Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        require(expected.batch == null && queued in expected.queues && queued.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD && queued.mutation.subjectUserId == expected.owner.value)
        val current = readInstallmentPaymentAcknowledgementSnapshot(expected.owner, expected.planId)
        if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
        val recorded = recordMutationFailure(queued, nextAttemptAtEpochMillis, errorCode)
        ensureCurrentFinanceOwner(expected.owner)
        recorded
    }

    override suspend fun commitInstallmentSkipAcknowledgement(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation,
        remotePlan: CloudRecord, remoteCycle: CloudRecord, zone: java.time.ZoneId): Boolean {
        val decision = planInstallmentSkipSync(expected, queued, remotePlan, remoteCycle, zone)
        require(decision is InstallmentSkipSyncDecision.Acknowledge && decision.record == remoteCycle)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current = readInstallmentAcknowledgementSnapshot(expected.owner, expected.planId)
            if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
            check(removeQueuedMutationExact(queued))
            database.cloudRecordDao().upsert(remoteCycle.toEntity(false, System.currentTimeMillis()))
            ensureCurrentFinanceOwner(expected.owner)
            true
        }
    }

    override suspend fun recordInstallmentSkipFailure(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation,
        nextAttemptAtEpochMillis: Long, errorCode: String): Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        require(expected.batch == null && queued in expected.queues && queued.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD &&
            queued.mutation.subjectUserId == expected.owner.value)
        val current = readInstallmentAcknowledgementSnapshot(expected.owner, expected.planId)
        if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
        val recorded = recordMutationFailure(queued, nextAttemptAtEpochMillis, errorCode)
        ensureCurrentFinanceOwner(expected.owner)
        recorded
    }

    override suspend fun installmentDeletionPlanIds(owner: UserId): Set<String> = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val ids = database.installmentDeletionDao().rows(owner.value).map { it.planId }.toSet()
        ensureCurrentFinanceOwner(owner)
        ids
    }

    override suspend fun commitInstallmentDeletionCompletion(expected: InstallmentAcknowledgementSnapshot, requestBatchId: String,
        remoteSource: CloudRecord?, remoteCycles: Map<String, CloudRecord?>, nowEpochMillis: Long): Boolean {
        if (expected.batch?.batchId != requestBatchId) return false
        val decision = planInstallmentDeletionCompletion(expected, remoteSource, remoteCycles, nowEpochMillis)
        require(decision is InstallmentDeletionCompletion.Ready)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current = readInstallmentAcknowledgementSnapshot(expected.owner, expected.planId)
            if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
            decision.cycles.forEach { record ->
                val queued = expected.queues.single { it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.recordId == record.id }
                check(removeQueuedMutationExact(queued))
                database.cloudRecordDao().upsert(record.toEntity(false, System.currentTimeMillis()))
            }
            database.cloudRecordDao().upsert(decision.source.toEntity(false, System.currentTimeMillis()))
            check(database.installmentDeletionDao().deleteExact(expected.owner.value, expected.planId, requestBatchId) == 1)
            ensureCurrentFinanceOwner(expected.owner)
            true
        }
    }

    override suspend fun recordInstallmentDeletionFailure(expected: InstallmentAcknowledgementSnapshot, requestBatchId: String,
        queued: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean = database.withTransaction {
        ensureCurrentFinanceOwner(expected.owner)
        if (expected.batch?.batchId != requestBatchId) return@withTransaction false
        require(queued in expected.queues && queued.mutation.subjectUserId == expected.owner.value && queued.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD)
        require(requireNotNull(expected.batch).cycles.any { it.deletion == queued.mutation })
        val current = readInstallmentAcknowledgementSnapshot(expected.owner, expected.planId)
        if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
        val recorded = recordMutationFailure(queued, nextAttemptAtEpochMillis, errorCode)
        ensureCurrentFinanceOwner(expected.owner)
        recorded
    }

    override suspend fun recordInstallmentSourceFailure(queued: QueuedMutation, requestBatchId: String?, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean = database.withTransaction {
        val owner = UserId(queued.mutation.subjectUserId)
        ensureCurrentFinanceOwner(owner)
        require(queued.mutation.entity == CloudEntity.INSTALLMENT_PLAN && queued.mutation.kind == MutationKind.DELETE)
        if (installmentDeletionBatch(owner, queued.mutation.recordId)?.batchId != requestBatchId) return@withTransaction false
        val current = database.syncOutboxDao().record(owner.value, CloudEntity.INSTALLMENT_PLAN.table, queued.mutation.recordId)?.toQueuedMutation()
        if (current != queued) return@withTransaction false
        val recorded = recordMutationFailure(queued, nextAttemptAtEpochMillis, errorCode)
        ensureCurrentFinanceOwner(owner)
        recorded
    }

    override suspend fun installmentAcknowledgementSnapshot(owner: UserId, planId: String): InstallmentAcknowledgementSnapshot = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val snapshot = readInstallmentAcknowledgementSnapshot(owner, planId)
        ensureCurrentFinanceOwner(owner)
        snapshot
    }

    private suspend fun readInstallmentAcknowledgementSnapshot(owner: UserId, planId: String) = InstallmentAcknowledgementSnapshot(
        owner, planId, installmentDeletionBatch(owner, planId), InstallmentAcknowledgementSnapshot.entities.associateWith { recordsIncludingDeleted(owner, it.table) },
        database.syncOutboxDao().rows(owner.value).filter { CloudEntity.fromTable(it.entity) in InstallmentAcknowledgementSnapshot.entities }.map { it.toQueuedMutation() })

    override suspend fun commitInstallmentSourceAcknowledgement(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, requestBatchId: String?,
        remote: CloudRecord, remoteCycles: Map<String, CloudRecord?>, remoteLedger: Map<String, CloudRecord?>, now: String): Boolean {
        if (expected.batch?.batchId != requestBatchId) return false
        val decision = planInstallmentSourceAcknowledgement(expected, queued, remote, remoteCycles, remoteLedger, now)
        require(decision is InstallmentSourceAckDecision.Ready)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current = readInstallmentAcknowledgementSnapshot(expected.owner, expected.planId)
            if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
            check(removeQueuedMutationExact(queued))
            decision.cycles.forEach { action ->
                val original = expected.queues.single { it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.recordId == action.record.id }
                check(removeQueuedMutationExact(original))
                database.cloudRecordDao().upsert(action.record.toEntity(action.queue != null, System.currentTimeMillis()))
                action.queue?.let { restored ->
                    val q = restored.mutation
                    database.syncOutboxDao().upsert(SyncOutboxEntity(q.subjectUserId, q.entity.table, q.recordId, q.kind.name.lowercase(), q.payload?.toString(),
                        q.modifiedAt, q.baseVersion, q.deviceId, restored.attemptCount, restored.nextAttemptAtEpochMillis, restored.lastError, restored.remoteIdentityObserved))
                }
            }
            database.cloudRecordDao().upsert(decision.source.toEntity(false, System.currentTimeMillis()))
            if (decision.clearBatch) check(database.installmentDeletionDao().deleteExact(expected.owner.value, expected.planId, requireNotNull(expected.batch).batchId) == 1)
            ensureCurrentFinanceOwner(expected.owner)
            true
        }
    }

    override suspend fun installmentDeletionBatch(owner: UserId, planId: String): InstallmentDeletionBatch? = database.withTransaction {
        ensureCurrentFinanceOwner(owner)
        val row = database.installmentDeletionDao().record(owner.value, planId)
        val batch = row?.let {
            require(it.ownerUserId == owner.value && it.planId == planId)
            val chunks = database.installmentDeletionDao().chunks(owner.value, planId, it.batchId)
            require(chunks.all { chunk -> chunk.ownerUserId == owner.value && chunk.planId == planId && chunk.batchId == it.batchId })
            InstallmentDeletionStorage.unpack(owner, planId, it.batchId, InstallmentDeletionBlob(json.parseToJsonElement(it.payloadJson) as JsonObject,
                chunks.map { chunk -> InstallmentDeletionChunk(chunk.chunkIndex, chunk.payload) }))
        }
        ensureCurrentFinanceOwner(owner)
        batch
    }

    override suspend fun commitInstallmentMutations(expected: InstallmentMutationSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean {
        expected.requireValidMutations(mutations)
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current = InstallmentMutationSnapshot.entities.associateWith { recordsIncludingDeleted(expected.owner, it.table) }
            if (runCatching { expected.requireUnchanged(current) }.isFailure) return@withTransaction false
            if (mutations.any { it.second.entity == CloudEntity.INSTALLMENT_PLAN && it.second.kind == MutationKind.DELETE } && mutations.size > 1) {
                val oldQueues = mutations.mapNotNull { (record, _) -> database.syncOutboxDao().record(record.ownerUserId, record.entity, record.id)?.toQueuedMutation() }
                val known = mutations.mapNotNull { (record, pending) ->
                    if (database.cloudRecordDao().record(record.ownerUserId, record.entity, record.id)?.hasPendingMutation == false) pending.entity to record.id else null
                }.toSet()
                val batch = requireNotNull(InstallmentDeletionBatch.capture(expected, mutations, oldQueues, java.util.UUID.randomUUID().toString(), known))
                val blob = InstallmentDeletionStorage.pack(batch)
                database.installmentDeletionDao().insert(InstallmentDeletionBatchEntity(expected.owner.value, expected.planId, batch.batchId, blob.header.toString()))
                database.installmentDeletionDao().insertChunks(blob.chunks.map { chunk -> InstallmentDeletionChunkEntity(expected.owner.value, expected.planId, batch.batchId, chunk.index, chunk.bytes) })
            }
            mutations.forEach { (record, mutation) -> commitMutationRows(record, mutation) }
            ensureCurrentFinanceOwner(expected.owner)
            true
        }
    }

    override suspend fun commitBillCycleMutations(bill:CloudRecord,monthKey:String,expectedOccurrences:List<CloudRecord>,mutations:List<Pair<CloudRecord,PendingMutation>>) {
        require(bill.entity==CloudEntity.RECURRING_BILL_PLAN.table)
        java.time.YearMonth.parse(monthKey)
        require(mutations.isNotEmpty() && mutations.all {pair ->
            pair.first.entity==CloudEntity.DUE_OCCURRENCE_RECORD.table && pair.first.ownerUserId==bill.ownerUserId &&
                (pair.first.payload["user_id"] as? JsonPrimitive)?.content==bill.ownerUserId &&
                billCycleRecords(listOf(pair.first),bill,monthKey).size==1
        })
        database.withTransaction {
            require(record(UserId(bill.ownerUserId),bill.entity,bill.id)==bill) {"Bill changed during cycle operation"}
            val current=billCycleRecords(recordsIncludingDeleted(UserId(bill.ownerUserId),CloudEntity.DUE_OCCURRENCE_RECORD.table),bill,monthKey)
            require(current==expectedOccurrences.sortedBy {it.id}) {"Bill cycle changed during operation"}
            require(mutations.all {pair ->
                val existing=expectedOccurrences.firstOrNull {it.id==pair.first.id}
                if(existing!=null) (existing.payload["user_id"] as? JsonPrimitive)?.content==bill.ownerUserId
                else record(UserId(bill.ownerUserId),pair.first.entity,pair.first.id)==null
            }) {"Occurrence identity occupied"}
            commitMutations(mutations)
            resolveBillNotificationsInTransaction(bill,monthKey,mutations.map {it.first})
        }
    }

    override suspend fun billInvestmentMoneySnapshot(owner:UserId,billId:vn.com.quyln.mistia.core.model.RecordId,month:java.time.YearMonth):BillMoneySnapshot =
        scheduledInvestmentMoneySnapshot(owner,billId,month,vn.com.quyln.mistia.core.model.DueSourceKind.RECURRING_BILL)

    override suspend fun installmentInvestmentMoneySnapshot(owner:UserId,planId:vn.com.quyln.mistia.core.model.RecordId,month:java.time.YearMonth):BillMoneySnapshot =
        scheduledInvestmentMoneySnapshot(owner,planId,month,vn.com.quyln.mistia.core.model.DueSourceKind.INSTALLMENT)

    private suspend fun scheduledInvestmentMoneySnapshot(owner:UserId,billId:vn.com.quyln.mistia.core.model.RecordId,month:java.time.YearMonth,
        kind:vn.com.quyln.mistia.core.model.DueSourceKind):BillMoneySnapshot {
        val caller=kotlinx.coroutines.currentCoroutineContext()
        caller.ensureActive()
        return database.withTransaction {
            ensureCurrentFinanceOwner(owner)
            val records=CloudEntity.entries.associateWith{recordsIncludingDeleted(owner,it.table)}
            val sourceEntity=if(kind==vn.com.quyln.mistia.core.model.DueSourceKind.INSTALLMENT)CloudEntity.INSTALLMENT_PLAN else CloudEntity.RECURRING_BILL_PLAN
            val bill=records.getValue(sourceEntity).singleOrNull{it.id==billId.value}
                ?: throw vn.com.quyln.mistia.core.model.BillPaymentException(vn.com.quyln.mistia.core.model.BillPaymentError.NOT_FOUND)
            val snapshot=BillMoneySnapshot(owner,bill,month,records,billMoneyReceiptTransactionIds(owner),sourceKind=kind)
            ensureCurrentFinanceOwner(owner)
            caller.ensureActive()
            snapshot
        }
    }

    override suspend fun commitBillInvestmentMoney(expected:BillMoneySnapshot,operation:vn.com.quyln.mistia.core.model.BillInvestmentMoneyOperation,
        catalog:vn.com.quyln.mistia.core.model.SystemCategoryCatalog,deviceId:String,now:String,zone:java.time.ZoneId):vn.com.quyln.mistia.core.model.BillInvestmentMoneyPlan {
        require(expected.sourceKind==vn.com.quyln.mistia.core.model.DueSourceKind.RECURRING_BILL)
        return commitScheduledInvestmentMoney(expected,{vn.com.quyln.mistia.core.model.planBillInvestmentMoney(it,operation,catalog,deviceId,now,zone)},{it.mutations})
    }

    override suspend fun commitInstallmentInvestmentMoney(expected:BillMoneySnapshot,operation:vn.com.quyln.mistia.core.model.InstallmentInvestmentMoneyOperation,
        catalog:vn.com.quyln.mistia.core.model.SystemCategoryCatalog,deviceId:String,now:String,zone:java.time.ZoneId):vn.com.quyln.mistia.core.model.InstallmentInvestmentMoneyPlan {
        require(expected.sourceKind==vn.com.quyln.mistia.core.model.DueSourceKind.INSTALLMENT)
        return commitScheduledInvestmentMoney(expected,{vn.com.quyln.mistia.core.model.planInstallmentInvestmentMoney(it,operation,catalog,deviceId,now,zone)},{it.mutations})
    }

    private suspend fun <T> commitScheduledInvestmentMoney(expected:BillMoneySnapshot,prepare:(BillMoneySnapshot)->T,
        writes:(T)->List<Pair<CloudRecord,PendingMutation>>):T {
        val caller=kotlinx.coroutines.currentCoroutineContext()
        caller.ensureActive()
        return database.withTransaction {
            ensureCurrentFinanceOwner(expected.owner)
            val current=scheduledInvestmentMoneySnapshot(expected.owner,vn.com.quyln.mistia.core.model.RecordId(expected.bill.id),expected.month,expected.sourceKind)
            expected.requireUnchanged(current.recordsByEntity)
            require(expected.bill==current.bill && expected.sourceKind==current.sourceKind && expected.receiptTransactionIds==current.receiptTransactionIds){"Bill investment source changed"}
            val planning=current.copy(automaticPaymentNotification=expected.automaticPaymentNotification)
            val plan=prepare(planning)
            val mutations=writes(plan)
            for((record,_) in mutations) {
                val old=current.recordsByEntity.values.flatten().singleOrNull{it.entity==record.entity && it.id==record.id}
                require(old!=null || database.syncOutboxDao().record(expected.owner.value,record.entity,record.id)==null){"Bill investment identity has an orphan queue"}
            }
            mutations.forEach{(record,mutation)->commitMutationRows(record,mutation)}
            if(mutations.isNotEmpty()) {
                if(current.sourceKind==vn.com.quyln.mistia.core.model.DueSourceKind.RECURRING_BILL)
                    resolveBillNotificationsInTransaction(current.bill,current.month.toString(),mutations.map{it.first})
                planning.automaticPaymentNotification?.takeIf{billRemindersEnabled()}?.let{incoming->
                    val existing=localNotifications(current.owner).singleOrNull{it.key==incoming.key}
                    val notification=upsertLocalNotification(existing,incoming)
                    database.localNotificationDao().upsert(listOf(LocalNotificationEntity(current.owner.value,notification.key,
                        json.encodeToString(AppNotificationRecord.serializer(),notification))))
                }
            }
            ensureCurrentFinanceOwner(expected.owner)
            caller.ensureActive()
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            plan
        }
    }

    override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
        snapshot.requireValidMutations(mutations)
        database.withTransaction {
            ensureCurrentFinanceOwner(snapshot.owner)
            snapshot.requireUnchanged(CloudEntity.entries.associateWith {
                recordsIncludingDeleted(snapshot.owner, it.table)
            })
            require(snapshot.receiptTransactionIds==billMoneyReceiptTransactionIds(snapshot.owner)) { "Receipt dependencies changed during bill payment" }
            commitMutations(mutations)
            if (snapshot.sourceKind == vn.com.quyln.mistia.core.model.DueSourceKind.RECURRING_BILL)
                resolveBillNotificationsInTransaction(snapshot.bill,snapshot.month.toString(),mutations.map {it.first})
            snapshot.automaticPaymentNotification?.takeIf {billRemindersEnabled()}?.let {incoming ->
                val existing=localNotifications(snapshot.owner).singleOrNull {it.key==incoming.key}
                val notification=upsertLocalNotification(existing,incoming)
                database.localNotificationDao().upsert(listOf(LocalNotificationEntity(snapshot.owner.value,notification.key,
                    json.encodeToString(AppNotificationRecord.serializer(),notification))))
            }
            ensureCurrentFinanceOwner(snapshot.owner)
        }
    }

    override suspend fun billMoneyReceiptTransactionIds(owner: UserId): Set<String> =
        database.transactionReceiptImageDao().receipts(owner.value).map { it.transactionId }.toSet()

    override suspend fun commitMissingSystemCategories(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        require(mutations.isNotEmpty())
        val owner=mutations.first().first.ownerUserId
        require(mutations.all {it.first.ownerUserId==owner && it.first.entity==CloudEntity.TRANSACTION_CATEGORY.table})
        val ids=mutations.map {it.first.id}.toSet()
        val keys=mutations.map {requireNotNull(TransactionCategoryRecord.fromCloudRecord(it.first).systemKey)}.toSet()
        require(ids.size==mutations.size && keys.size==mutations.size)
        database.withTransaction {
            val existing=database.cloudRecordDao().recordsIncludingDeleted(owner,CloudEntity.TRANSACTION_CATEGORY.table)
            require(existing.none {row ->
                val record=row.toCloudRecord()
                record.id in ids || ((record.payload["user_id"] as? JsonPrimitive)?.content?.equals(owner,ignoreCase=true)==true &&
                    (record.payload["system_key"] as? JsonPrimitive)?.content in keys)
            }) {"Category bootstrap snapshot changed"}
            commitMutations(mutations)
        }
    }

    private suspend fun requireCurrentCardPaymentSource(profile: CloudRecord, cardWalletId: String) {
        val raw = profile.payload["payment_source_wallet_id"]
        if (raw == null || raw == kotlinx.serialization.json.JsonNull) return
        fun invalid(): Nothing = throw vn.com.quyln.mistia.core.model.CreditCardValidationException(vn.com.quyln.mistia.core.model.CreditCardValidationError.INVALID_PAYMENT_SOURCE)
        val id = (raw as? JsonPrimitive)?.takeIf { it.isString }?.content ?: invalid()
        if (id == cardWalletId || runCatching { java.util.UUID.fromString(id).toString() }.getOrNull() != id) invalid()
        val owner = UserId(profile.ownerUserId)
        val source = record(owner, CloudEntity.LEDGER_WALLET.table, id) ?: invalid()
        if (!source.matchesFinanceReadScope(owner, CloudEntity.LEDGER_WALLET) || source.payload["is_archived"] != JsonPrimitive(false)) invalid()
        val kind = vn.com.quyln.mistia.core.model.LedgerWalletRecord.fromCloudRecord(source).kind
        if (kind == null || kind == vn.com.quyln.mistia.core.model.WalletKind.CREDIT_CARD) invalid()
    }

    override suspend fun commitCreditCardMutation(
        walletRecord: CloudRecord,
        walletMutation: PendingMutation,
        profileRecord: CloudRecord,
        profileMutation: PendingMutation,
    ) {
        val owner = UserId(walletRecord.ownerUserId)
        require(java.util.UUID.fromString(owner.value).toString() == owner.value)
        for ((record, mutation, entity) in listOf(
            Triple(walletRecord, walletMutation, CloudEntity.LEDGER_WALLET),
            Triple(profileRecord, profileMutation, CloudEntity.CREDIT_CARD_PROFILE),
        )) {
            require(record.matchesFinanceReadScope(owner, entity))
            require(java.util.UUID.fromString(record.id).toString() == record.id)
            require(record.payload["id"] == JsonPrimitive(record.id) && record.payload["user_id"] == JsonPrimitive(owner.value))
            require(record.syncVersion == 0L && record.payload["sync_version"] == JsonPrimitive(0) &&
                mutation.baseVersion == 0L && mutation.kind == MutationKind.UPSERT) { "New card must start at version zero" }
        }
        require(profileRecord.payload["wallet_id"] == JsonPrimitive(walletRecord.id))
        database.withTransaction {
            ensureCurrentFinanceOwner(owner)
            val claimed = listOf(walletRecord, profileRecord).any { record ->
                database.cloudRecordDao().record(owner.value, record.entity, record.id) != null ||
                    database.syncOutboxDao().record(owner.value, record.entity, record.id) != null
            }
            val linkedProfile = recordsIncludingDeleted(owner, CloudEntity.CREDIT_CARD_PROFILE.table).any {
                (it.payload["wallet_id"] as? JsonPrimitive)?.takeIf { value -> value.isString }?.content?.trim()?.equals(walletRecord.id, ignoreCase = true) == true
            }
            if (claimed || linkedProfile)
                throw vn.com.quyln.mistia.core.model.WalletValidationException(vn.com.quyln.mistia.core.model.WalletValidationError.STALE_EDIT)
            requireCurrentCardPaymentSource(profileRecord, walletRecord.id)
            commitMutationRows(walletRecord, walletMutation)
            commitMutationRows(profileRecord, profileMutation)
            ensureCurrentFinanceOwner(owner)
        }
    }

    override suspend fun commitCreditCardEdit(
        expectedWallet: CloudRecord, expectedProfile: CloudRecord,
        walletRecord: CloudRecord, walletMutation: PendingMutation,
        profileRecord: CloudRecord, profileMutation: PendingMutation,
    ) {
        requireWalletMetadataMutation(expectedWallet, walletRecord, walletMutation)
        val owner = UserId(walletRecord.ownerUserId)
        require(expectedWallet.matchesFinanceReadScope(owner, CloudEntity.LEDGER_WALLET) && expectedProfile.matchesFinanceReadScope(owner, CloudEntity.CREDIT_CARD_PROFILE))
        require(profileRecord.entity == expectedProfile.entity && profileRecord.id == expectedProfile.id && profileRecord.ownerUserId == owner.value && profileRecord.deletedAt == null)
        require(profileRecord.payload["id"] == JsonPrimitive(profileRecord.id) && profileRecord.payload["user_id"] == JsonPrimitive(owner.value))
        require(expectedProfile.payload["wallet_id"] == JsonPrimitive(walletRecord.id) && profileRecord.payload["wallet_id"] == JsonPrimitive(walletRecord.id))
        require(profileMutation.kind == MutationKind.UPSERT && profileMutation.baseVersion == expectedProfile.syncVersion && profileRecord.syncVersion == expectedProfile.syncVersion &&
            profileRecord.payload["sync_version"] == JsonPrimitive(expectedProfile.syncVersion)) { "Card profile version envelope disagrees" }
        val oldLimit = expectedProfile.payload["credit_limit_minor"] as? JsonPrimitive
        require(oldLimit?.isString == false && oldLimit.longOrNull?.let { it >= 0 } == true) { "Card profile limit is malformed" }
        val oldCurrency = vn.com.quyln.mistia.core.model.LedgerWalletRecord.fromCloudRecord(expectedWallet).currencyCode.trim().uppercase(java.util.Locale.ROOT)
        val newCurrency = vn.com.quyln.mistia.core.model.LedgerWalletRecord.fromCloudRecord(walletRecord).currencyCode.trim().uppercase(java.util.Locale.ROOT)
        database.withTransaction {
            ensureCurrentFinanceOwner(owner)
            val profiles = recordsIncludingDeleted(owner, CloudEntity.CREDIT_CARD_PROFILE.table).filter {
                (it.payload["wallet_id"] as? JsonPrimitive)?.takeIf { value -> value.isString }?.content?.trim()?.equals(walletRecord.id, ignoreCase = true) == true && !it.isConsistentlyDeleted()
            }
            if (record(owner, expectedWallet.entity, expectedWallet.id) != expectedWallet || record(owner, expectedProfile.entity, expectedProfile.id) != expectedProfile ||
                profiles.map { it.id } != listOf(expectedProfile.id))
                throw vn.com.quyln.mistia.core.model.WalletValidationException(vn.com.quyln.mistia.core.model.WalletValidationError.STALE_EDIT)
            if (oldCurrency != newCurrency && vn.com.quyln.mistia.core.model.walletHasLiveLedgerHistory(owner, walletRecord.id, recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table)))
                throw vn.com.quyln.mistia.core.model.WalletValidationException(vn.com.quyln.mistia.core.model.WalletValidationError.CURRENCY_IN_USE)
            requireCurrentCardPaymentSource(profileRecord, walletRecord.id)
            commitMutationRows(walletRecord, walletMutation)
            commitMutationRows(profileRecord, profileMutation)
            ensureCurrentFinanceOwner(owner)
        }
    }

    override suspend fun commitCategoryMutation(
        record: CloudRecord,
        mutation: PendingMutation,
        translation: PendingCategoryTranslation,
    ) {
        require(translation.ownerUserId == record.ownerUserId)
        require(translation.categoryId == record.id)
        require(translation.savedUpdatedAt == record.updatedAt)
        database.withTransaction {
            commitMutationRows(record, mutation)
            database.categoryTranslationOutboxDao().upsert(translation.toEntity())
        }
    }

    override suspend fun pendingMutations(
        ownerUserId: UserId,
        entity: CloudEntity,
        dueAtEpochMillis: Long,
        limit: Int,
    ): List<QueuedMutation> {
        require(limit in 1..1_000) { "Outbox batch limit must be between 1 and 1000" }
        return database.syncOutboxDao().dueRows(
            ownerUserId = ownerUserId.value,
            entity = entity.table,
            dueAtEpochMillis = dueAtEpochMillis,
            limit = limit,
        ).map { it.toQueuedMutation() }
    }

    override suspend fun acknowledgeMutation(
        mutation: QueuedMutation,
        remoteRecord: CloudRecord,
    ): Boolean {
        val pending = mutation.mutation
        require(remoteRecord.ownerUserId == pending.subjectUserId) { "Remote owner does not match mutation" }
        require(remoteRecord.entity == pending.entity.table) { "Remote entity does not match mutation" }
        require(remoteRecord.id == pending.recordId) { "Remote record ID does not match mutation" }
        return database.withTransaction {
            val removed = removeQueuedMutationExact(mutation)
            if (removed) {
                database.cloudRecordDao().upsert(
                    remoteRecord.toEntity(
                        hasPendingMutation = false,
                        receivedAtEpochMillis = System.currentTimeMillis(),
                    )
                )
            }
            removed
        }
    }

    private suspend fun removeQueuedMutationExact(queued: QueuedMutation): Boolean {
        val q = queued.mutation
        return database.syncOutboxDao().deleteExact(q.subjectUserId, q.entity.table, q.recordId, q.modifiedAt, q.baseVersion, q.deviceId,
            queued.attemptCount, q.kind.name.lowercase(), q.payload?.toString(), queued.remoteIdentityObserved) == 1
    }

    override suspend fun recordMutationFailure(
        mutation: QueuedMutation,
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Boolean {
        val pending = mutation.mutation
        require(nextAttemptAtEpochMillis >= 0) { "Retry time cannot be negative" }
        val safeErrorCode = errorCode.trim().take(160)
        require(safeErrorCode.isNotEmpty()) { "Failure code cannot be empty" }
        return database.syncOutboxDao().markFailureExact(
            ownerUserId = pending.subjectUserId,
            entity = pending.entity.table,
            recordId = pending.recordId,
            modifiedAt = pending.modifiedAt,
            baseVersion = pending.baseVersion,
            deviceId = pending.deviceId,
            attemptCount = mutation.attemptCount,
            kind = pending.kind.name.lowercase(),
            payloadJson = pending.payload?.toString(),
            remoteIdentityObserved = mutation.remoteIdentityObserved,
            nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
            errorCode = safeErrorCode,
        ) == 1
    }

    override suspend fun pendingCategoryTranslations(
        ownerUserId: UserId,
        dueAtEpochMillis: Long,
        limit: Int,
    ): List<QueuedCategoryTranslation> {
        require(limit in 1..200) { "Translation batch limit must be between 1 and 200" }
        return database.categoryTranslationOutboxDao()
            .dueRows(ownerUserId.value, dueAtEpochMillis, limit)
            .map { it.toQueuedTranslation() }
    }

    override suspend fun enqueueMissingCategoryTranslations(
        ownerUserId: UserId,
        deviceId: String,
        limit: Int,
    ): Int {
        require(limit in 1..200) { "Translation maintenance limit must be between 1 and 200" }
        require(deviceId.isNotBlank()) { "Device ID cannot be blank" }
        return database.withTransaction {
            database.cloudRecordDao()
                .activeRecords(ownerUserId.value, CloudEntity.TRANSACTION_CATEGORY.table, limit)
                .map { TransactionCategoryRecord.fromCloudRecord(it.toCloudRecord()) }
                .mapNotNull { category ->
                    category.translationRetrySource()?.let { source ->
                        PendingCategoryTranslation(
                            ownerUserId = ownerUserId.value,
                            categoryId = category.id,
                            inputName = source.inputName,
                            sourceLanguage = source.language,
                            savedUpdatedAt = category.updatedAt,
                            deviceId = deviceId,
                        )
                    }
                }
                .count { pending ->
                    database.categoryTranslationOutboxDao().insertIfAbsent(pending.toEntity()) != -1L
                }
        }
    }

    override suspend fun applyCategoryTranslation(
        task: QueuedCategoryTranslation,
        expectedRecord: CloudRecord,
        record: CloudRecord,
        mutation: PendingMutation,
    ): Boolean = database.withTransaction {
        val pending = task.translation
        val current = database.cloudRecordDao().record(
            pending.ownerUserId,
            CloudEntity.TRANSACTION_CATEGORY.table,
            pending.categoryId,
        )
        if (current?.toCloudRecord() != expectedRecord || expectedRecord.updatedAt != pending.savedUpdatedAt) return@withTransaction false
        require(expectedRecord.entity==CloudEntity.TRANSACTION_CATEGORY.table && expectedRecord.id==pending.categoryId && expectedRecord.ownerUserId==pending.ownerUserId && expectedRecord.deletedAt==null)
        require(record.entity==expectedRecord.entity && record.id==expectedRecord.id && record.ownerUserId==expectedRecord.ownerUserId && record.deletedAt==null)
        require(record.syncVersion==expectedRecord.syncVersion && mutation.entity==CloudEntity.TRANSACTION_CATEGORY && mutation.recordId==record.id && mutation.subjectUserId==record.ownerUserId && mutation.payload==record.payload && mutation.kind==MutationKind.UPSERT && mutation.baseVersion==record.syncVersion)
        val removed = database.categoryTranslationOutboxDao().deleteExact(
            pending.ownerUserId,
            pending.categoryId,
            pending.inputName,
            pending.sourceLanguage.wireValue,
            pending.savedUpdatedAt,
            task.attemptCount,
            pending.deviceId,
        ) == 1
        if (removed) commitMutationRows(record, mutation)
        removed
    }

    override suspend fun discardCategoryTranslation(task: QueuedCategoryTranslation): Boolean {
        val pending = task.translation
        return database.categoryTranslationOutboxDao().deleteExact(
            pending.ownerUserId,
            pending.categoryId,
            pending.inputName,
            pending.sourceLanguage.wireValue,
            pending.savedUpdatedAt,
            task.attemptCount,
            pending.deviceId,
        ) == 1
    }

    override suspend fun recordCategoryTranslationFailure(
        task: QueuedCategoryTranslation,
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Boolean {
        val pending = task.translation
        val safeErrorCode = errorCode.trim().take(160)
        require(nextAttemptAtEpochMillis >= 0 && safeErrorCode.isNotEmpty())
        return database.categoryTranslationOutboxDao().markFailureExact(
            pending.ownerUserId,
            pending.categoryId,
            pending.inputName,
            pending.sourceLanguage.wireValue,
            pending.savedUpdatedAt,
            task.attemptCount,
            pending.deviceId,
            nextAttemptAtEpochMillis,
            safeErrorCode,
        ) == 1
    }

    override suspend fun replacePullSnapshot(
        ownerUserId: UserId,
        entity: String,
        records: List<CloudRecord>,
    ) {
        database.withTransaction {
            val installmentPull = entity == CloudEntity.INSTALLMENT_PLAN.table
            if (installmentPull) {
                ensureCurrentFinanceOwner(ownerUserId)
                require(records.all { it.ownerUserId == ownerUserId.value && it.entity == entity })
            }
            // Source ACK can finish before its child batch. Keep that local source fenced
            // until the dedicated reconciler resolves/clears the exact causal batch.
            val protectedIds = if (installmentPull) database.installmentDeletionDao().rows(ownerUserId.value).map { it.planId }.toSet() else emptySet()
            val pendingIds = database.syncOutboxDao().recordIds(ownerUserId.value, entity).toSet() + protectedIds
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
            if (installmentPull) ensureCurrentFinanceOwner(ownerUserId)
        }
    }

    override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String): Set<String> =
        database.syncOutboxDao().recordIds(ownerUserId.value, entity).toSet()

    override suspend fun clearAccount(ownerUserId: UserId) {
        database.withTransaction {
            database.installmentDeletionDao().deleteAccount(ownerUserId.value)
            database.localNotificationDao().deleteAccount(ownerUserId.value)
            database.cloudRecordDao().deleteAccount(ownerUserId.value)
            database.syncOutboxDao().deleteAccount(ownerUserId.value)
            database.syncCursorDao().deleteAccount(ownerUserId.value)
            database.categoryTranslationOutboxDao().deleteAccount(ownerUserId.value)
        }
    }

    private suspend fun resolveBillNotificationsInTransaction(bill:CloudRecord,month:String?,writes:List<CloudRecord>?=null) {
        val owner=UserId(bill.ownerUserId)
        val current=localNotifications(owner)
        val now=java.time.Instant.now().toString()
        val resolved=if(writes==null) resolveLocalBillNotifications(owner,current,bill.id,month,now)
            else resolveTerminalBillWriteNotifications(bill,requireNotNull(month),writes,current,now)
        val changed=resolved.filterIndexed {index,row -> row!=current[index]}
        database.localNotificationDao().upsert(changed.map {LocalNotificationEntity(owner.value,it.key,json.encodeToString(AppNotificationRecord.serializer(),it))})
    }

    private suspend fun commitMutationRows(record: CloudRecord, mutation: PendingMutation, remoteIdentityObserved:Boolean=false) {
        require(record.ownerUserId == mutation.subjectUserId) { "Mutation owner does not match record owner" }
        require(record.entity == mutation.entity.table) { "Mutation entity does not match record entity" }
        require(record.id == mutation.recordId) { "Mutation record ID does not match record" }
        require(record.payload == mutation.payload) { "Mutation payload does not match local record" }
        val previousRecord=database.cloudRecordDao().record(record.ownerUserId,record.entity,record.id)
        val previousQueue=database.syncOutboxDao().record(record.ownerUserId,record.entity,record.id)
        val observed=remoteIdentityObserved || mutation.baseVersion>0 || record.syncVersion>0 || previousQueue?.remoteIdentityObserved==true || previousRecord?.hasPendingMutation==false
        database.cloudRecordDao().upsert(
            record.toEntity(
                hasPendingMutation = true,
                receivedAtEpochMillis = System.currentTimeMillis(),
            )
        )
        database.syncOutboxDao().upsert(
            SyncOutboxEntity(
                ownerUserId = mutation.subjectUserId,
                entity = mutation.entity.table,
                recordId = mutation.recordId,
                kind = mutation.kind.name.lowercase(),
                payloadJson = mutation.payload?.toString(),
                modifiedAt = mutation.modifiedAt,
                baseVersion = mutation.baseVersion,
                deviceId = mutation.deviceId,
                remoteIdentityObserved = observed,
            )
        )
        if(record.entity==CloudEntity.RECURRING_BILL_PLAN.table && record.payload["user_id"]==JsonPrimitive(record.ownerUserId) &&
            record.payload["id"]==JsonPrimitive(record.id) &&
            (record.deletedAt!=null || record.payload["is_paused"]==JsonPrimitive(true) || record.payload["is_archived"]==JsonPrimitive(true)))
            resolveBillNotificationsInTransaction(record,null)
    }

    private fun CloudRecordEntity.toCloudRecord(): CloudRecord = CloudRecord(
        entity = entity,
        id = recordId,
        ownerUserId = ownerUserId,
        payload = json.parseToJsonElement(payloadJson) as JsonObject,
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
    )

    private fun CloudRecord.toEntity(
        hasPendingMutation: Boolean,
        receivedAtEpochMillis: Long,
    ): CloudRecordEntity = CloudRecordEntity(
        ownerUserId = ownerUserId,
        entity = entity,
        recordId = id,
        payloadJson = payload.toString(),
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
        hasPendingMutation = hasPendingMutation,
        receivedAtEpochMillis = receivedAtEpochMillis,
    )

    private fun SyncOutboxEntity.toQueuedMutation(): QueuedMutation {
        val cloudEntity = requireNotNull(CloudEntity.fromTable(entity)) { "Unknown outbox entity: $entity" }
        return QueuedMutation(
            mutation = PendingMutation(
                entity = cloudEntity,
                recordId = recordId,
                subjectUserId = ownerUserId,
                kind = MutationKind.valueOf(kind.uppercase()),
                payload = payloadJson?.let { json.parseToJsonElement(it) as JsonObject },
                modifiedAt = modifiedAt,
                baseVersion = baseVersion,
                deviceId = deviceId,
            ),
            attemptCount = attemptCount,
            nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
            lastError = lastError,
            remoteIdentityObserved = remoteIdentityObserved,
        )
    }

    private fun PendingCategoryTranslation.toEntity() = CategoryTranslationOutboxEntity(
        ownerUserId = ownerUserId,
        categoryId = categoryId,
        inputName = inputName,
        sourceLanguage = sourceLanguage.wireValue,
        savedUpdatedAt = savedUpdatedAt,
        deviceId = deviceId,
    )

    private fun CategoryTranslationOutboxEntity.toQueuedTranslation() = QueuedCategoryTranslation(
        translation = PendingCategoryTranslation(
            ownerUserId = ownerUserId,
            categoryId = categoryId,
            inputName = inputName,
            sourceLanguage = requireNotNull(CategoryNameLanguage.fromWireValue(sourceLanguage)),
            savedUpdatedAt = savedUpdatedAt,
            deviceId = deviceId,
        ),
        attemptCount = attemptCount,
        nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
        lastError = lastError,
    )
}
