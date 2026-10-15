package vn.com.quyln.mistia.core.database

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

/** Local-only intent, committed with source/cycle tombstones and their outbox rows. */
@Entity(tableName = "installment_delete_batches", primaryKeys = ["owner_user_id", "plan_id"],
    indices = [Index(value = ["owner_user_id", "batch_id"], unique = true)])
data class InstallmentDeletionBatchEntity(
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    @ColumnInfo(name = "plan_id") val planId: String,
    @ColumnInfo(name = "batch_id") val batchId: String,
    @ColumnInfo(name = "payload_json") val payloadJson: String,
)

@Entity(tableName = "installment_delete_chunks", primaryKeys = ["owner_user_id", "plan_id", "chunk_index"],
    indices = [Index(value = ["owner_user_id", "plan_id"])],
    foreignKeys = [ForeignKey(entity = InstallmentDeletionBatchEntity::class, parentColumns = ["owner_user_id", "plan_id"],
        childColumns = ["owner_user_id", "plan_id"], onDelete = ForeignKey.CASCADE)])
data class InstallmentDeletionChunkEntity(
    @ColumnInfo(name = "owner_user_id") val ownerUserId: String,
    @ColumnInfo(name = "plan_id") val planId: String,
    @ColumnInfo(name = "batch_id") val batchId: String,
    @ColumnInfo(name = "chunk_index") val chunkIndex: Int,
    val payload: ByteArray,
)

@Dao
interface InstallmentDeletionDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(row: InstallmentDeletionBatchEntity)
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertChunks(rows: List<InstallmentDeletionChunkEntity>)
    @Query("SELECT * FROM installment_delete_chunks WHERE owner_user_id = :ownerUserId AND plan_id = :planId AND batch_id = :batchId ORDER BY chunk_index")
    suspend fun chunks(ownerUserId: String, planId: String, batchId: String): List<InstallmentDeletionChunkEntity>
    @Query("SELECT * FROM installment_delete_batches WHERE owner_user_id = :ownerUserId AND plan_id = :planId")
    suspend fun record(ownerUserId: String, planId: String): InstallmentDeletionBatchEntity?
    @Query("SELECT * FROM installment_delete_batches WHERE owner_user_id = :ownerUserId ORDER BY plan_id")
    suspend fun rows(ownerUserId: String): List<InstallmentDeletionBatchEntity>
    @Query("DELETE FROM installment_delete_batches WHERE owner_user_id = :ownerUserId AND plan_id = :planId AND batch_id = :batchId")
    suspend fun deleteExact(ownerUserId: String, planId: String, batchId: String): Int
    @Query("DELETE FROM installment_delete_batches WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId: String)
}
