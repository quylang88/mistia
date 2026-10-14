package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class WalletReminderRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val now="2026-10-14T00:00:00Z"
    private fun row(key:String="mistia.reminder.wallet.$id")=AppNotificationRecord(owner.value,key,"Old","Body","lowWallet",
        source="localReminder",resourceType="wallet",resourceId=id,createdAt=now,updatedAt=now)
    @Test fun walletTransactionAndSettlementChangesRejectStaleNotificationBatch()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        for(entity in WalletReminderSnapshot.entities) {
            val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
            try {
                val store=RoomLocalStore(db);val original=row()
                assertTrue(store.commitLocalNotifications(owner,emptyList(),listOf(original)))
                val snapshot=store.walletReminderSnapshot(owner)
                val record=CloudRecord(entity.table,id,owner.value,buildJsonObject {
                    put("id",id);put("user_id",owner.value);put("updated_at",now);put("minor",9007199254740993L)
                },now,null,0)
                store.replacePullSnapshot(owner,entity.table,listOf(record))
                assertFalse(store.commitWalletReminders(snapshot,listOf(original.copy(title="Stale"))))
                assertEquals(listOf(original),store.localNotifications(owner))
            } finally {db.close()}
        }
    }
    @Test fun disabledPreferenceAtCommitKeepsWalletHistoryAndOnlyCleansObsoleteRows()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db,walletRemindersEnabled={false});val original=row()
            val obsolete=original.copy(key="mistia.reminder.due.old",kind="dueSoon")
            assertTrue(store.commitLocalNotifications(owner,emptyList(),listOf(original,obsolete)))
            val snapshot=store.walletReminderSnapshot(owner)
            assertTrue(store.commitWalletReminders(snapshot,listOf(original.copy(title="New"),row("new"))))
            assertEquals(listOf(original),store.localNotifications(owner))
        } finally {db.close()}
    }
    @Test fun accountChangeAfterRowsWrittenRollsBackWalletNotificationBatch()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val initial=RoomLocalStore(db);val original=row()
            assertTrue(initial.commitLocalNotifications(owner,emptyList(),listOf(original)))
            var checks=0
            val store=RoomLocalStore(db,currentBillOwner={checks++;if(checks==1) owner else null})
            val snapshot=store.walletReminderSnapshot(owner)
            val error=runCatching {store.commitWalletReminders(snapshot,listOf(original.copy(title="Changed"),row("new")))}.exceptionOrNull()
            assertTrue(error is CancellationException);assertEquals(2,checks)
            assertEquals(listOf(original),initial.localNotifications(owner))
        } finally {db.close()}
    }
}
