package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Synthetic local Room financial mutations; no cloud writes. */
@RunWith(AndroidJUnit4::class)
class InstallmentPaymentRoomTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val month = YearMonth.of(2026, 10)
    private val zone = ZoneId.of("Asia/Tokyo")
    private val catalog get() = SystemCategoryCatalog.parse(context.assets.open("MistiaSystemCategories.json").bufferedReader().use { it.readText() })
    private suspend fun prepare(repo: OfflineFirstFinanceRepository): InstallmentPlanRecord {
        val wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 9007199254740993), device, now).getOrThrow()
        return repo.saveInstallment(owner, InstallmentDraft(id, "Loan", 9007199254740993, 15, 1, 12, wallet.id, "JPY"), device, now).getOrThrow()
    }
    @Test fun diskReopenKeepsPaidExpenseAndCycleThenUndoRepayCoalesceTheirIdentities() = runTest {
        val name = "installment-payment-${UUID.randomUUID()}.db"
        var db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).build()
        try {
            var store = RoomLocalStore(db); var repo = OfflineFirstFinanceRepository(store, zone, catalog)
            val plan = prepare(repo); val paid = repo.payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now).getOrThrow()
            db.close(); db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).build()
            store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store, zone, catalog)
            assertEquals(paid.transaction, repo.observeTransactions(owner).first().single()); assertEquals(paid.occurrences, repo.observeDueOccurrences(owner).first())
            repo.undoInstallmentPayment(owner, plan, month, device, later).getOrThrow()
            assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
            val again = repo.payInstallment(owner, InstallmentPaymentRequest(plan, month), device, later).getOrThrow()
            assertEquals(paid.transaction.id, again.transaction.id); assertEquals(paid.occurrences.single().id, again.occurrences.single().id)
            assertEquals(9007199254740993L, again.transaction.amountMinor)
            assertEquals(1, store.recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table).size)
        } finally { db.close(); context.deleteDatabase(name) }
    }
    @Test fun occurrenceOutboxFailureRollsBackExpenseCategoriesAndPaidMarkerTogether() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store = RoomLocalStore(db); val repo = OfflineFirstFinanceRepository(store, zone, catalog); val plan = prepare(repo)
            val before = CloudEntity.entries.associateWith { store.recordsIncludingDeleted(owner, it.table) }
            val outbox = CloudEntity.entries.associateWith { store.pendingMutations(owner, it, Long.MAX_VALUE) }
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_installment_payment BEFORE INSERT ON sync_outbox
                WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
            assertTrue(repo.payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now).isFailure)
            assertEquals(before, CloudEntity.entries.associateWith { store.recordsIncludingDeleted(owner, it.table) })
            assertEquals(outbox, CloudEntity.entries.associateWith { store.pendingMutations(owner, it, Long.MAX_VALUE) })
        } finally { db.close() }
    }
    @Test fun ownerChangeBeforeOrAfterPaymentWritesCancelsAndRollsBackAllTables() = runTest {
        for (afterWrites in listOf(false, true)) {
            val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
            try {
                val initial = RoomLocalStore(db); val plan = prepare(OfflineFirstFinanceRepository(initial, zone, catalog))
                val before = CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) }
                val outbox = CloudEntity.entries.associateWith { initial.pendingMutations(owner, it, Long.MAX_VALUE) }
                var checks = 0
                val guarded = RoomLocalStore(db, currentBillOwner = { checks++; if (afterWrites && checks == 1) owner else UserId(device) })
                var cancelled = false
                try { OfflineFirstFinanceRepository(guarded, zone, catalog).payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now) }
                catch (_: CancellationException) { cancelled = true }
                assertTrue(cancelled); assertEquals(before, CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) })
                assertEquals(outbox, CloudEntity.entries.associateWith { initial.pendingMutations(owner, it, Long.MAX_VALUE) })
            } finally { db.close() }
        }
    }
    @Test fun walletCurrencyChangeAtMoneyCommitInvalidatesSnapshotWithoutPartialSpending() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val initial = RoomLocalStore(db); val plan = prepare(OfflineFirstFinanceRepository(initial, zone, catalog))
            val racing = object : LocalStore by initial {
                override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                    val wallet = LedgerWalletRecord.fromCloudRecord(initial.record(owner, CloudEntity.LEDGER_WALLET.table, plan.paymentWalletId!!)!!).copy(currencyCode = "VND")
                    initial.commitMutation(wallet.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_WALLET, wallet.id, owner.value, MutationKind.UPSERT, wallet.toPayload(), later, wallet.syncVersion, device))
                    initial.commitBillMoneyMutations(snapshot, mutations)
                }
            }
            assertTrue(OfflineFirstFinanceRepository(racing, zone, catalog).payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now).isFailure)
            assertTrue(initial.recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table).isEmpty())
            assertTrue(initial.recordsIncludingDeleted(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table).isEmpty())
            assertTrue(initial.recordsIncludingDeleted(owner, CloudEntity.TRANSACTION_CATEGORY.table).isEmpty())
        } finally { db.close() }
    }
    @Test fun mismatchedPaidSnapshotAtAtomicBoundaryRejectsEntireExpenseCategoryAndCycleBatch() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val initial = RoomLocalStore(db); val plan = prepare(OfflineFirstFinanceRepository(initial, zone, catalog))
            val before = CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) }
            val queues = CloudEntity.entries.associateWith { initial.pendingMutations(owner, it, Long.MAX_VALUE) }
            val corrupting = object : LocalStore by initial {
                override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                    val changed = mutations.map { (row, q) -> if (q.entity == CloudEntity.DUE_OCCURRENCE_RECORD) {
                        val payload = JsonObject(row.payload + ("amount_minor_snapshot" to JsonPrimitive(1375)))
                        row.copy(payload = payload) to q.copy(payload = payload)
                    } else row to q }
                    initial.commitBillMoneyMutations(snapshot, changed)
                }
            }
            assertTrue(OfflineFirstFinanceRepository(corrupting, zone, catalog).payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now).isFailure)
            assertEquals(before, CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) })
            assertEquals(queues, CloudEntity.entries.associateWith { initial.pendingMutations(owner, it, Long.MAX_VALUE) })
        } finally { db.close() }
    }
    @Test fun undoCannotTombstonePaidMarkerWithoutItsLiveExpenseAtAtomicBoundary() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val initial = RoomLocalStore(db); val real = OfflineFirstFinanceRepository(initial, zone, catalog); val plan = prepare(real)
            real.payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now).getOrThrow()
            val before = CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) }
            val queues = CloudEntity.entries.associateWith { initial.pendingMutations(owner, it, Long.MAX_VALUE) }
            val incomplete = object : LocalStore by initial {
                override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                    initial.commitBillMoneyMutations(snapshot, mutations.filterNot { it.second.entity == CloudEntity.LEDGER_TRANSACTION })
                }
            }
            assertTrue(OfflineFirstFinanceRepository(incomplete, zone, catalog).undoInstallmentPayment(owner, plan, month, device, later).isFailure)
            assertEquals(before, CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) })
            assertEquals(queues, CloudEntity.entries.associateWith { initial.pendingMutations(owner, it, Long.MAX_VALUE) })
        } finally { db.close() }
    }
    @Test fun undoCannotLeaveAnotherLivePaidDuplicateWhileDeletingSharedExpense() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val initial = RoomLocalStore(db); val real = OfflineFirstFinanceRepository(initial, zone, catalog); val plan = prepare(real)
            val saved = real.payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now).getOrThrow()
            val duplicate = saved.occurrences.single().copy(id = device)
            initial.commitMutation(duplicate.toCloudRecord(), duplicate.pendingMutation())
            val before = CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) }
            val incomplete = object : LocalStore by initial {
                override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                    initial.commitBillMoneyMutations(snapshot, mutations.filterNot { it.second.entity == CloudEntity.DUE_OCCURRENCE_RECORD && it.first.id == duplicate.id })
                }
            }
            assertTrue(OfflineFirstFinanceRepository(incomplete, zone, catalog).undoInstallmentPayment(owner, plan, month, device, later).isFailure)
            assertEquals(before, CloudEntity.entries.associateWith { initial.recordsIncludingDeleted(owner, it.table) })
        } finally { db.close() }
    }

    @Test fun changedPendingAmountBeforeRepositoryReadRequiresTheFreshVisibleCycleBaseline() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store=RoomLocalStore(db);val repo=OfflineFirstFinanceRepository(store,zone,catalog);val plan=prepare(repo)
            val pending=DueOccurrenceRecord(UUID.randomUUID().toString(),owner.value,"installment",plan.id,month.toString(),now,6000,"pending",null,null,now,now,null,0,device)
            store.commitMutation(pending.toCloudRecord(),pending.pendingMutation())
            val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)}
            val queue=CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}
            val stale=repo.payInstallment(owner,InstallmentPaymentRequest(plan,month,amountMinorOverride=5000,expectedDueAmountMinor=5000),device,now)
            assertEquals(BillPaymentError.SOURCE_CHANGED,(stale.exceptionOrNull() as? BillPaymentException)?.reason)
            assertEquals(before,CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)})
            assertEquals(queue,CloudEntity.entries.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)})
            val fresh=repo.payInstallment(owner,InstallmentPaymentRequest(plan,month,amountMinorOverride=6000,expectedDueAmountMinor=6000),device,now).getOrThrow()
            assertEquals(6000L,fresh.transaction.amountMinor);assertEquals(6000L,fresh.occurrences.single().amountMinorSnapshot)
        } finally {db.close()}
    }

}
