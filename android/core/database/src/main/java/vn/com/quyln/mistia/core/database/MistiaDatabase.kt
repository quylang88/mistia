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
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.model.CategoryReferenceSnapshot
import vn.com.quyln.mistia.core.model.categoryReferenceEntities
import vn.com.quyln.mistia.core.model.planCategoryReferenceRepairs
import vn.com.quyln.mistia.core.model.billCycleRecords
import vn.com.quyln.mistia.core.model.BillMoneySnapshot
import vn.com.quyln.mistia.core.model.requireValidMutations
import vn.com.quyln.mistia.core.model.requireUnchanged
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
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
        nextAttemptAtEpochMillis: Long,
        errorCode: String,
    ): Int

    @Query("DELETE FROM sync_outbox WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}

@Dao
interface CategoryTranslationOutboxDao {
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
    ],
    version = 3,
    exportSchema = true,
)
abstract class MistiaDatabase : RoomDatabase() {
    abstract fun cloudRecordDao(): CloudRecordDao
    abstract fun syncOutboxDao(): SyncOutboxDao
    abstract fun categoryTranslationOutboxDao(): CategoryTranslationOutboxDao
    abstract fun syncCursorDao(): SyncCursorDao
    abstract fun transactionReceiptImageDao(): TransactionReceiptImageDao

    companion object {
        fun create(context: Context): MistiaDatabase =
            Room.databaseBuilder(context, MistiaDatabase::class.java, "mistia-android.db")
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                .build()

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
    private val dao: TransactionReceiptImageDao,
) : TransactionReceiptMetadataStore {
    override suspend fun receipt(transactionId: String): TransactionReceiptImageRecord? =
        dao.receipt(transactionId)?.toRecord()

    override suspend fun replace(record: TransactionReceiptImageRecord) {
        dao.replace(record.toEntity())
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
) : LocalStore {
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

    override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
        database.withTransaction {
            commitMutationRows(record, mutation)
        }
    }

    override suspend fun commitMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        require(mutations.isNotEmpty())
        require(mutations.map { it.first.ownerUserId }.distinct().size == 1)
        require(mutations.map { it.first.entity to it.first.id }.distinct().size == mutations.size)
        database.withTransaction {
            mutations.forEach { (record, mutation) -> commitMutationRows(record, mutation) }
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
        }
    }

    override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
        snapshot.requireValidMutations(mutations)
        database.withTransaction {
            snapshot.requireUnchanged(CloudEntity.entries.associateWith {
                recordsIncludingDeleted(snapshot.owner, it.table)
            })
            require(snapshot.receiptTransactionIds==billMoneyReceiptTransactionIds(snapshot.owner)) { "Receipt dependencies changed during bill payment" }
            commitMutations(mutations)
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

    override suspend fun commitCreditCardMutation(
        walletRecord: CloudRecord,
        walletMutation: PendingMutation,
        profileRecord: CloudRecord,
        profileMutation: PendingMutation,
    ) {
        require(walletRecord.entity == CloudEntity.LEDGER_WALLET.table)
        require(profileRecord.entity == CloudEntity.CREDIT_CARD_PROFILE.table)
        require(walletRecord.ownerUserId == profileRecord.ownerUserId)
        require((profileRecord.payload["wallet_id"] as? JsonPrimitive)?.contentOrNull == walletRecord.id)
        database.withTransaction {
            commitMutationRows(walletRecord, walletMutation)
            commitMutationRows(profileRecord, profileMutation)
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
            val removed = database.syncOutboxDao().deleteExact(
                ownerUserId = pending.subjectUserId,
                entity = pending.entity.table,
                recordId = pending.recordId,
                modifiedAt = pending.modifiedAt,
                baseVersion = pending.baseVersion,
                deviceId = pending.deviceId,
                attemptCount = mutation.attemptCount,
                kind = pending.kind.name.lowercase(),
                payloadJson = pending.payload?.toString(),
            ) == 1
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
            database.categoryTranslationOutboxDao().deleteAccount(ownerUserId.value)
        }
    }

    private suspend fun commitMutationRows(record: CloudRecord, mutation: PendingMutation) {
        require(record.ownerUserId == mutation.subjectUserId) { "Mutation owner does not match record owner" }
        require(record.entity == mutation.entity.table) { "Mutation entity does not match record entity" }
        require(record.id == mutation.recordId) { "Mutation record ID does not match record" }
        require(record.payload == mutation.payload) { "Mutation payload does not match local record" }
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
            )
        )
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
