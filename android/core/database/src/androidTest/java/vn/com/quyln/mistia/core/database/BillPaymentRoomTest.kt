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
    private fun automaticRepo(store:LocalStore)=OfflineFirstFinanceRepository(store,zone,catalog) {bill,amount ->
        BillAutomaticPaymentText("Auto-paid ${bill.name}","Complete","Paid $amount")
    }
    private suspend fun automaticBill(repo:OfflineFirstFinanceRepository,store:LocalStore):RecurringBillPlanRecord {
        val bill=prepare(repo).copy(autoPayEnabled=true,paymentStartDay=10,dueDay=20,hasExplicitDueDate=true,autoPayDay=13)
        store.commitMutation(bill.toCloudRecord(),bill.pendingMutation())
        return bill
    }
    @Test fun accountChangeBeforeOrDuringMoneyCommitRollsBackAllFinancialAndNotificationWrites()=runTest {
        for(changeAfterWrites in listOf(false,true)) {
            val context=ApplicationProvider.getApplicationContext<Context>()
            val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
            try {
                val initial=RoomLocalStore(db);val bill=automaticBill(automaticRepo(initial),initial)
                val before=CloudEntity.entries.associateWith {initial.recordsIncludingDeleted(owner,it.table)}
                val outbox=CloudEntity.entries.associateWith {initial.pendingMutations(owner,it,Long.MAX_VALUE)}
                var checks=0
                val guarded=RoomLocalStore(db,currentBillOwner={
                    checks++
                    if(changeAfterWrites && checks==1) owner else UserId("33333333-3333-3333-3333-333333333333")
                })
                val error=runCatching {
                    automaticRepo(guarded).payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,automatic=true),device,now)
                }.exceptionOrNull()
                assertTrue(error is kotlinx.coroutines.CancellationException)
                assertEquals(if(changeAfterWrites) 2 else 1,checks)
                assertEquals(before,CloudEntity.entries.associateWith {initial.recordsIncludingDeleted(owner,it.table)})
                assertEquals(outbox,CloudEntity.entries.associateWith {initial.pendingMutations(owner,it,Long.MAX_VALUE)})
                assertTrue(initial.localNotifications(owner).isEmpty())
            } finally {db.close()}
        }
    }
    @Test fun automaticMoneyAndNotificationReopenTogetherAndRepeatedAttemptDoesNotDuplicate()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="auto-notification-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store:LocalStore=RoomLocalStore(db);var repo=automaticRepo(store)
            val bill=automaticBill(repo,store)
            val paid=repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,automatic=true),device,now).getOrThrow()
            db.close();db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build();store=RoomLocalStore(db);repo=automaticRepo(store)
            assertEquals("Auto-paid Internet",repo.observeTransactions(owner).first().single().title)
            val notification=store.localNotifications(owner).single()
            assertEquals("mistia.bill.autopay.success.${bill.id}.2026-10",notification.key)
            assertEquals("Paid 9007199254740993",notification.body)
            assertEquals(paid.occurrences,repo.observeDueOccurrences(owner).first())
            assertTrue(repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,automatic=true),device,now).isFailure)
            assertEquals(listOf(notification),store.localNotifications(owner))
            assertEquals(1,repo.observeTransactions(owner).first().size)
        } finally {db.close();context.deleteDatabase(name)}
    }
    @Test fun notificationFailureRollsBackExpenseOccurrenceAndBothOutboxWrites()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val repo=automaticRepo(store);val bill=automaticBill(repo,store)
            val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)}
            val outbox=CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_auto_notification BEFORE INSERT ON local_app_notifications
                BEGIN SELECT RAISE(ABORT,'simulated notification failure'); END""")
            assertTrue(repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,automatic=true),device,now).isFailure)
            assertEquals(before,CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)})
            assertEquals(outbox,CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)})
            assertTrue(store.localNotifications(owner).isEmpty())
        } finally {db.close()}
    }
    private fun reminder(bill:RecurringBillPlanRecord,cycle:String="2026-10",kind:String="billPaymentRequired")=AppNotificationRecord(owner.value,
        "mistia.bill.payment.deadline.${bill.id}.$cycle",kind,"Body",kind,resourceType="bill",resourceId=bill.id,createdAt=now,updatedAt=now,
        metadata=kotlinx.serialization.json.buildJsonObject {put("dueMonthKey",kotlinx.serialization.json.JsonPrimitive(cycle))})
    @Test fun paySkipAndPauseResolveNotificationsInsideTheMutationTransaction()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        for(operation in listOf("pay","skip","pause")) {
            val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
            try {
                val store=RoomLocalStore(db);val repo=OfflineFirstFinanceRepository(store,zone,catalog);val bill=prepare(repo)
                val success=reminder(bill,kind="billAutoPaymentSucceeded").copy(key="success")
                val initial=listOf(reminder(bill),reminder(bill,"2026-09"),success)
                assertTrue(store.commitLocalNotifications(owner,emptyList(),initial))
                when(operation) {
                    "pay" -> repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).getOrThrow()
                    "skip" -> repo.skipRecurringBill(owner,RecordId(bill.id),month,device,now).getOrThrow()
                    else -> repo.pauseRecurringBill(owner,RecordId(bill.id),device,now).getOrThrow()
                }
                val rows=store.localNotifications(owner)
                assertEquals("resolved",rows.single {it.key==initial.first().key}.actionState)
                assertTrue(rows.single {it.key==initial.first().key}.isRead)
                assertEquals(operation=="pause",rows.single {it.key==initial[1].key}.isRead)
                assertEquals(success,rows.single {it.key=="success"})
            } finally {db.close()}
        }
    }
    @Test fun resolutionFailureRollsBackPaidSkippedAndPausedStateWithOutbox()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        for(operation in listOf("pay","skip","pause")) {
            val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
            try {
                val store=RoomLocalStore(db);val repo=OfflineFirstFinanceRepository(store,zone,catalog);val bill=prepare(repo)
                val initial=listOf(reminder(bill))
                assertTrue(store.commitLocalNotifications(owner,emptyList(),initial))
                val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)}
                val outbox=CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
                db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_resolution BEFORE INSERT ON local_app_notifications
                    BEGIN SELECT RAISE(ABORT,'simulated resolution failure'); END""")
                val result=when(operation) {
                    "pay" -> repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now)
                    "skip" -> repo.skipRecurringBill(owner,RecordId(bill.id),month,device,now)
                    else -> repo.pauseRecurringBill(owner,RecordId(bill.id),device,now)
                }
                assertTrue(result.isFailure)
                assertEquals(before,CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)})
                assertEquals(outbox,CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)})
                assertEquals(initial,store.localNotifications(owner))
            } finally {db.close()}
        }
    }
    @Test fun latestReminderPreferenceAtMoneyCommitDoesNotCancelAutomaticPayment()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        for(finalEnabled in listOf(false,true)) {
            val db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).build()
            try {
                var enabled=!finalEnabled
                val store=RoomLocalStore(db,billRemindersEnabled={enabled})
                val repo=OfflineFirstFinanceRepository(store,zone,catalog,automaticBillText={bill,amount ->
                    enabled=finalEnabled
                    BillAutomaticPaymentText("Auto-paid ${bill.name}","Complete","Paid $amount")
                })
                val bill=automaticBill(repo,store)
                repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,automatic=true),device,now).getOrThrow()
                assertEquals(1,repo.observeTransactions(owner).first().size)
                assertEquals(DueStatus.PAID,repo.observeDueOccurrences(owner).first().single().status)
                assertEquals(if(finalEnabled) 1 else 0,store.localNotifications(owner).size)
            } finally {db.close()}
        }
    }
    @Test fun payReopenUndoPreservesExactLedgerOccurrenceAndDeleteOutbox()=runTest {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val name="bill-money-${UUID.randomUUID()}.db"
        var db=Room.databaseBuilder(context,MistiaDatabase::class.java,name).build()
        try {
            var store=RoomLocalStore(db)
            var repo=OfflineFirstFinanceRepository(store,zone,catalog)
            val bill=prepare(repo)
            val paid=repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).getOrThrow()
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
            val sentUndo=store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).single()
            val repayment=repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).getOrThrow()
            assertEquals(paid.transaction.id,repayment.transaction.id)
            assertEquals(paid.occurrences.single().id,repayment.occurrences.single().id)
            assertFalse(store.acknowledgeMutation(sentUndo,LedgerTransactionRecord.fromCloudRecord(
                store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).single()
            ).copy(deletedAt=now,syncVersion=1).toCloudRecord()))
            assertFalse(store.recordMutationFailure(sentUndo,Long.MAX_VALUE,"stale_undo"))
            assertEquals(listOf(repayment.transaction),repo.observeTransactions(owner).first())
            assertEquals(MutationKind.UPSERT,store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).single().mutation.kind)
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
            assertTrue(repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).isFailure)
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
            assertTrue(OfflineFirstFinanceRepository(racing,zone,catalog).payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).isFailure)
            assertTrue(repo.observeTransactions(owner).first().isEmpty())
            assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        } finally {db.close()}
    }
}
