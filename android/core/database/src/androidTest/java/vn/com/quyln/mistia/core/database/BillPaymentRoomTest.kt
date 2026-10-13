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
class BillPaymentRoomTest {
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
    @Test fun payReopenUndoPreservesExactLedgerOccurrenceAndDeleteOutbox()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="bill-money-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store=RoomLocalStore(db)
            var repo=OfflineFirstFinanceRepository(store,zone,catalog)
            val bill=prepare(repo)
            val paid=repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month),device,now).getOrThrow()
            db.close()
            db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
            store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store,zone,catalog)
            assertEquals(listOf(paid.transaction),repo.observeTransactions(owner).first())
            assertEquals(paid.occurrences,repo.observeDueOccurrences(owner).first())
            repo.undoRecurringBillPayment(owner,RecordId(bill.id),month,device,now).getOrThrow()
            assertTrue(repo.observeTransactions(owner).first().isEmpty())
            assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
            assertEquals(MutationKind.DELETE,store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).single().mutation.kind)
            assertEquals(MutationKind.DELETE,store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single().mutation.kind)
        } finally {db.close();context.deleteDatabase(name)}
    }
    @Test fun occurrenceOutboxFailureRollsBackLedgerRecordAndOutbox()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db)
            val repo=OfflineFirstFinanceRepository(store,zone,catalog)
            val bill=prepare(repo)
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_paid_occurrence BEFORE INSERT ON sync_outbox
                WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT,'simulated occurrence outbox failure'); END""")
            assertTrue(repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month),device,now).isFailure)
            assertTrue(repo.observeTransactions(owner).first().isEmpty())
            assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
            assertTrue(store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).isEmpty())
            assertTrue(store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).isEmpty())
        } finally {db.close()}
    }
    @Test fun walletCurrencyChangeBetweenValidationAndCommitCannotSpendMoney()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db)
            val repo=OfflineFirstFinanceRepository(store,zone,catalog)
            val bill=prepare(repo)
            val racing=object:LocalStore by store {
                override suspend fun commitBillMoneyMutations(snapshot:BillMoneySnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>) {
                    val wallet=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,bill.paymentWalletId!!)!!).copy(currencyCode="VND")
                    store.commitMutation(wallet.toCloudRecord(),PendingMutation(CloudEntity.LEDGER_WALLET,wallet.id,owner.value,MutationKind.UPSERT,wallet.toPayload(),now,wallet.syncVersion,device))
                    store.commitBillMoneyMutations(snapshot,mutations)
                }
            }
            assertTrue(OfflineFirstFinanceRepository(racing,zone,catalog).payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month),device,now).isFailure)
            assertTrue(repo.observeTransactions(owner).first().isEmpty())
            assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        } finally {db.close()}
    }
}
