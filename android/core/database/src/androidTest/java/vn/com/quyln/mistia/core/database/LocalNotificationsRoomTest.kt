package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class LocalNotificationsRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("22222222-2222-2222-2222-222222222222")
    private val now="2026-10-14T00:00:00Z"
    private fun row(user:UserId=owner,key:String="same-key")=AppNotificationRecord(user.value,key,"Due","Body","billOverdue",
        createdAt=now,updatedAt=now,metadata=buildJsonObject {put("minor",9007199254740993L);put("nullable",JsonNull)})
    @Test fun notificationsReopenKeepReadMetadataAndPartitionWithoutCloudWrites()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="notifications-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store:LocalStore=RoomLocalStore(db)
            val read=markLocalNotificationRead(row(),now)
            assertTrue(store.commitLocalNotifications(owner,emptyList(),listOf(read)))
            assertTrue(store.commitLocalNotifications(other,emptyList(),listOf(row(other))))
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db)
            assertEquals(listOf(read),store.localNotifications(owner))
            assertEquals(listOf(row(other)),store.localNotifications(other))
            assertTrue(store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).isEmpty())
            store.clearAccount(owner)
            assertTrue(store.localNotifications(owner).isEmpty())
            assertEquals(listOf(row(other)),store.localNotifications(other))
        } finally {db.close();context.deleteDatabase(name)}
    }
    @Test fun billBatchRejectsPaidCycleAndReadRacesBeforeChangingNotificationRows()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store:LocalStore=RoomLocalStore(db)
            val bill=CloudRecord(CloudEntity.RECURRING_BILL_PLAN.table,other.value,owner.value,buildJsonObject {
                put("id",other.value);put("user_id",owner.value);put("updated_at",now);put("unknown_minor",9007199254740993L)
            },now,null,0)
            store.replacePullSnapshot(owner,CloudEntity.RECURRING_BILL_PLAN.table,listOf(bill))
            val initial=store.billNotificationSnapshot(owner)
            assertTrue(store.commitBillNotifications(initial,listOf(row())))
            val expected=store.billNotificationSnapshot(owner)
            val occurrence=CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table,other.value,owner.value,buildJsonObject {
                put("id",other.value);put("user_id",owner.value);put("status_raw_value","paid");put("updated_at",now)
            },now,null,0)
            store.replacePullSnapshot(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,listOf(occurrence))
            assertFalse(store.commitBillNotifications(expected,emptyList()))
            assertEquals(listOf(row()),store.localNotifications(owner))
            val beforeRead=store.billNotificationSnapshot(owner)
            val read=listOf(markLocalNotificationRead(row(),now))
            assertTrue(store.commitLocalNotifications(owner,beforeRead.notifications,read))
            assertFalse(store.commitBillNotifications(beforeRead,emptyList()))
            assertEquals(read,store.localNotifications(owner))
        } finally {db.close()}
    }
    @Test fun disabledBillPreferencePreservesHistoryAndOnlyAppliesResolution()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store:LocalStore=RoomLocalStore(db,billRemindersEnabled={false})
            val old=row()
            assertTrue(store.commitLocalNotifications(owner,emptyList(),listOf(old)))
            val expected=store.billNotificationSnapshot(owner)
            assertTrue(store.commitBillNotifications(expected,listOf(old.copy(title="New copy"),row(key="new"))))
            assertEquals(listOf(old),store.localNotifications(owner))
            val current=store.billNotificationSnapshot(owner)
            assertTrue(store.commitBillNotifications(current,listOf(markLocalNotificationRead(old,now).copy(title="New copy",actionState="resolved"))))
            val resolved=store.localNotifications(owner).single()
            assertEquals(old.title,resolved.title);assertTrue(resolved.isRead);assertEquals("resolved",resolved.actionState)
        } finally {db.close()}
    }
    @Test fun staleBatchCannotOverwriteReadStateAndFailedBatchRollsBack()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store:LocalStore=RoomLocalStore(db)
            val initial=listOf(row())
            assertTrue(store.commitLocalNotifications(owner,emptyList(),initial))
            val read=listOf(markLocalNotificationRead(row(),now))
            assertTrue(store.commitLocalNotifications(owner,initial,read))
            assertFalse(store.commitLocalNotifications(owner,initial,listOf(row().copy(title="Stale"))))
            assertEquals(read,store.localNotifications(owner))
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_notification BEFORE INSERT ON local_app_notifications
                WHEN NEW.notification_key='bad' BEGIN SELECT RAISE(ABORT,'simulated notification failure'); END""")
            assertTrue(runCatching {store.commitLocalNotifications(owner,read,read+row(key="bad"))}.isFailure)
            assertEquals(read,store.localNotifications(owner))
            assertTrue(runCatching {store.commitLocalNotifications(owner,read,listOf(row(other)))}.isFailure)
            assertEquals(read,store.localNotifications(owner))
        } finally {db.close()}
    }
}
