package vn.com.quyln.mistia.core.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Entity(tableName="local_app_notifications",primaryKeys=["owner_user_id","notification_key"])
data class LocalNotificationEntity(
    @ColumnInfo(name="owner_user_id") val ownerUserId:String,
    @ColumnInfo(name="notification_key") val notificationKey:String,
    @ColumnInfo(name="payload_json") val payloadJson:String,
)
@Dao
interface LocalNotificationDao {
    @Query("SELECT * FROM local_app_notifications WHERE owner_user_id = :ownerUserId ORDER BY notification_key")
    suspend fun rows(ownerUserId:String):List<LocalNotificationEntity>
    @Query("SELECT * FROM local_app_notifications WHERE owner_user_id = :ownerUserId ORDER BY notification_key")
    fun observe(ownerUserId:String):Flow<List<LocalNotificationEntity>>
    @Insert(onConflict=OnConflictStrategy.REPLACE)
    suspend fun upsert(rows:List<LocalNotificationEntity>)
    @Query("DELETE FROM local_app_notifications WHERE owner_user_id = :ownerUserId")
    suspend fun deleteAccount(ownerUserId:String)
}
