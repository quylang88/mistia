package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class RecurringBillRoomTest {
    @Test fun pauseReopenResumeAndArchiveKeepPaidHistoryAndCoalescedOutbox()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="bill-test-${UUID.randomUUID()}.db"
        val owner=UserId("11111111-1111-1111-1111-111111111111")
        val device="22222222-2222-2222-2222-222222222222"
        val zone=ZoneId.of("Asia/Tokyo")
        val now="2026-10-13T00:00:00Z"
        val later="2026-11-13T00:00:00Z"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
        try {
            var store=RoomLocalStore(db)
            var repo=OfflineFirstFinanceRepository(store,zone)
            val parent=repo.saveCategory(owner,CategoryDraft(name="Home",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
            val child=repo.saveCategory(owner,CategoryDraft(name="Internet",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
            val wallet=repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
            val saved=repo.saveRecurringBill(owner,RecurringBillDraft("Internet",child.id,5000,wallet.id,"JPY",zoneId=zone),device,now).getOrThrow()
            val skipped=repo.skipRecurringBill(owner,RecordId(saved.id),java.time.YearMonth.of(2026,10),device,now).getOrThrow()
            db.close()
            db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
            store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store,zone)
            assertEquals(listOf(skipped),repo.observeDueOccurrences(owner).first())
            repo.undoRecurringBillSkip(owner,RecordId(saved.id),java.time.YearMonth.of(2026,10),device,later).getOrThrow()
            assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
            assertEquals(MutationKind.DELETE,store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single().mutation.kind)
            val paid=DueOccurrenceRecord(UUID.randomUUID().toString(),owner.value,"recurringBill",saved.id,"2026-10",now,5000,"paid",now,null,now,now,null,0,device)
            store.commitMutation(paid.toCloudRecord(),paid.pendingMutation())
            repo.pauseRecurringBill(owner,RecordId(saved.id),device,now).getOrThrow()
            db.close()
            db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).allowMainThreadQueries().build()
            store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store,zone)
            assertTrue(repo.observeRecurringBills(owner).first().single().isPaused)
            assertEquals(listOf(paid),repo.observeDueOccurrences(owner).first())
            repo.resumeRecurringBill(owner,RecordId(saved.id),device,later).getOrThrow()
            assertEquals("2026-10-31T15:00:00Z",repo.observeRecurringBills(owner).first().single().resumeStartMonth)
            assertTrue(repo.archiveRecurringBill(owner,RecordId(saved.id),device,later).isFailure)
            val next=paid.copy(id=UUID.randomUUID().toString(),selectedMonthKey="2026-11",scheduledDate=later,paidAt=later)
            store.commitMutation(next.toCloudRecord(),next.pendingMutation())
            repo.archiveRecurringBill(owner,RecordId(saved.id),device,later).getOrThrow()
            assertTrue(repo.observeRecurringBills(owner).first().single().isArchived)
            assertEquals(2,repo.observeDueOccurrences(owner).first().size)
            val outbox=store.pendingMutations(owner,CloudEntity.RECURRING_BILL_PLAN,Long.MAX_VALUE).single().mutation
            assertEquals(MutationKind.UPSERT,outbox.kind);assertEquals(0,outbox.baseVersion)
            assertTrue(repo.observeRecurringBills(UserId("99999999-9999-9999-9999-999999999999")).first().isEmpty())
        } finally {db.close();context.deleteDatabase(name)}
    }
}
