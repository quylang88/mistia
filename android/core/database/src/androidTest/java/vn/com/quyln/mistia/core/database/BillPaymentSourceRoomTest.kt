package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class BillPaymentSourceRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val now="2026-10-13T00:00:00Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val month=YearMonth.of(2026,10)
    private val catalog=SystemCategoryCatalog.parse("""[
      {"id":"parent_expense_home_bills","kind":"expense","active":true,"icon":"mistia.category.parent.expense.home_bills","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Nhà","en":"Home","ja":"住まい"},"aliases":[],"children":[
        {"id":"internet","active":true,"icon":"mistia.category.expense.home_bills.internet","fallbackIcon":"wifi","color":"#5B7BFF","translations":{"vi":"Internet","en":"Internet","ja":"インターネット"},"aliases":[]}
      ]}
    ]""")
    private suspend fun prepare(repo:OfflineFirstFinanceRepository):RecurringBillPlanRecord {
        repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        val category=repo.observeCategories(owner).first().single {it.systemKey=="internet"}
        val wallet=repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=9007199254740993L),device,now).getOrThrow()
        return repo.saveRecurringBill(owner,RecurringBillDraft("Internet",category.id,9007199254740993L,wallet.id,"JPY",zoneId=zone),device,now).getOrThrow()
    }
    @Test fun changedSourceBeforeRepositoryReadRejectsStaleMoneyWithoutAnyRoomOrOutboxWrite()=runTest {
        val db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val repo=OfflineFirstFinanceRepository(store,zone,catalog);val visible=prepare(repo)
            val changed=visible.copy(amountMinor=6000)
            store.commitMutation(changed.toCloudRecord(),changed.pendingMutation())
            val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)}
            val queue=CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
            val result=repo.payRecurringBill(owner,BillPaymentRequest(RecordId(visible.id),month,amountMinorOverride=5000,expectedBill=visible),device,now)
            assertEquals("paid=${result.getOrNull()?.transaction?.amountMinor}",BillPaymentError.SOURCE_CHANGED,(result.exceptionOrNull() as? BillPaymentException)?.reason)
            assertEquals(before,CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)})
            assertEquals(queue,CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)})
        } finally {db.close()}
    }
    @Test fun changedPendingCycleAmountCannotBePaidUnderAnUnchangedSourceBaseline()=runTest {
        val db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val repo=OfflineFirstFinanceRepository(store,zone,catalog);val visible=prepare(repo)
            val pending=DueOccurrenceRecord(UUID.randomUUID().toString(),owner.value,"recurringBill",visible.id,month.toString(),now,6000,"pending",null,null,now,now,null,0,device)
            val prior=pending.copy(amountMinorSnapshot=5000)
            store.commitMutation(prior.toCloudRecord(),prior.pendingMutation())
            val visibleDue=recurringBillDueRows(owner,listOf(visible),repo.observeDueOccurrences(owner).first(),month,zone).single()
            assertEquals(5000L,visibleDue.amountMinor)
            store.commitMutation(pending.toCloudRecord(),pending.pendingMutation())
            val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)}
            val queue=CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
            val stale=BillPaymentRequest(RecordId(visible.id),month,amountMinorOverride=5000,expectedBill=visible,expectedDueAmountMinor=5000)
            val result=repo.payRecurringBill(owner,stale,device,now)
            assertEquals(BillPaymentError.SOURCE_CHANGED,(result.exceptionOrNull() as? BillPaymentException)?.reason)
            assertEquals(before,CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)})
            assertEquals(queue,CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)})
            val fresh=stale.copy(expectedDueAmountMinor=6000,amountMinorOverride=6000)
            assertEquals(6000L,repo.payRecurringBill(owner,fresh,device,now).getOrThrow().transaction.amountMinor)
        } finally {db.close()}
    }
    @Test fun unchangedVisibleSourcePaysExactlyOnceAndReopensItsOccurrence()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>();val name="bill-source-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store:LocalStore=RoomLocalStore(db);var repo=OfflineFirstFinanceRepository(store,zone,catalog);val visible=prepare(repo)
            val request=BillPaymentRequest(RecordId(visible.id),month,amountMinorOverride=9007199254740993L,expectedBill=visible)
            val saved=repo.payRecurringBill(owner,request,device,now).getOrThrow()
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store,zone,catalog)
            assertEquals(9007199254740993L,repo.observeTransactions(owner).first().single().amountMinor)
            assertEquals(saved.occurrences,repo.observeDueOccurrences(owner).first())
            assertTrue(repo.payRecurringBill(owner,request,device,now).isFailure)
            assertEquals(1,repo.observeTransactions(owner).first().size)
        } finally {db.close();context.deleteDatabase(name)}
    }
}
