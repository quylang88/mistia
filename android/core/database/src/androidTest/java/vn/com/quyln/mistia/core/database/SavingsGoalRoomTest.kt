package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class SavingsGoalRoomTest {
    @Test fun goalAndOutboxSurviveDatabaseReopenThenDeleteTogether() = runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="savings-test-${UUID.randomUUID()}.db"
        val owner=UserId("11111111-1111-1111-1111-111111111111")
        val other=UserId("44444444-4444-4444-4444-444444444444")
        val device="22222222-2222-2222-2222-222222222222"
        val now="2026-10-13T00:00:00Z"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
        try {
            val first=OfflineFirstFinanceRepository(RoomLocalStore(db))
            val saved=first.saveSavingsGoal(owner,SavingsGoalDraft("Travel",9007199254740993L,123,"2027-01-01T00:00:00Z","JPY"),device,now).getOrThrow()
            db.close()
            db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
            val store=RoomLocalStore(db)
            val restored=OfflineFirstFinanceRepository(store)
            assertEquals(saved,restored.observeSavingsGoals(owner).first().single())
            assertEquals(saved.toPayload(),store.pendingMutations(owner,CloudEntity.SAVINGS_GOAL,Long.MAX_VALUE).single().mutation.payload)
            assertTrue(restored.observeSavingsGoals(other).first().isEmpty())
            restored.deleteSavingsGoal(owner,RecordId(saved.id),device,now).getOrThrow()
            assertTrue(restored.observeSavingsGoals(owner).first().isEmpty())
            assertEquals(now,store.record(owner,CloudEntity.SAVINGS_GOAL.table,saved.id)!!.deletedAt)
            assertEquals(MutationKind.DELETE,store.pendingMutations(owner,CloudEntity.SAVINGS_GOAL,Long.MAX_VALUE).single().mutation.kind)
        } finally { db.close();context.deleteDatabase(name) }
    }
}
