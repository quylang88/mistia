package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.ZoneId
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Actual DAO/transaction fixtures; compile-only until Android execution is available. */
@RunWith(AndroidJUnit4::class)
class InstallmentCycleRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-02-14T00:00:00Z"
    private val month = YearMonth.of(2026, 2)
    private val ownerNow = AtomicReference<UserId?>(owner)
    private val flip = AtomicBoolean(false)
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 9007199254740993, 31, null, 1, null, "JPY",
        false, created, created, null, Long.MAX_VALUE, device)
    @Before fun setup() {
        ownerNow.set(owner); flip.set(false)
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java)
            .allowMainThreadQueries().setQueryCallback(RoomDatabase.QueryCallback { sql, _ ->
                if (flip.get() && sql.contains("insert", true) && sql.contains("sync_outbox")) ownerNow.set(UserId(device))
            }, Executor { it.run() }).build()
        store = RoomLocalStore(db, currentBillOwner = { ownerNow.get() }); repo = OfflineFirstFinanceRepository(store, ZoneId.of("Asia/Tokyo"))
    }
    @After fun close() { db.close() }
    private fun entity(r: CloudRecord) = CloudRecordEntity(r.ownerUserId, r.entity, r.id, r.payload.toString(), r.updatedAt, r.deletedAt, r.syncVersion, receivedAtEpochMillis = 0)
    private suspend fun seed() { db.cloudRecordDao().upsert(listOf(entity(plan.toCloudRecord()))) }
    @Test fun skipUndoCoalescesOutboxAndKeepsSourceAndLedgerUntouched() = runTest {
        seed(); val skipped = repo.skipInstallment(owner, plan, month, device, now).getOrThrow()
        repo.undoInstallmentSkip(owner, plan, month, device, now).getOrThrow()
        assertNotNull(store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, skipped.id)!!.deletedAt)
        assertEquals("delete", db.syncOutboxDao().rows(owner.value).single().kind)
        assertEquals(plan.toCloudRecord(), store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertTrue(store.recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table).isEmpty())
    }
    @Test fun outboxTriggerFailureRollsBackCreatedOccurrence() = runTest {
        seed()
        db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_installment_cycle BEFORE INSERT ON sync_outbox
            WHEN NEW.entity = 'due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
        assertTrue(repo.skipInstallment(owner, plan, month, device, now).isFailure)
        assertTrue(store.recordsIncludingDeleted(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table).isEmpty())
        assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty())
    }
    @Test fun currentOwnerFlipDuringSqlCancelsAndRollsBackBothTables() = runTest {
        seed(); flip.set(true)
        try { repo.skipInstallment(owner, plan, month, device, now); fail("Cancellation expected") }
        catch (_: CancellationException) {
            assertTrue(store.recordsIncludingDeleted(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table).isEmpty())
            assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty())
        }
    }
    @Test fun concurrentCycleInsertMakesCapturedIntentStaleBeforeAnyWrite() = runTest {
        seed(); val base = store.installmentMutationSnapshot(owner, id)
        val intent = InstallmentCycleSnapshot(base, plan, month, ZoneId.of("Asia/Tokyo"), InstallmentCycleAction.SKIP)
        val writes = intent.buildMutations(device, device, now)
        val paid = DueOccurrenceRecord(owner.value, owner.value, "installment", id, month.toString(), now, 9007199254740993,
            "paid", now, device, created, now, null, Long.MAX_VALUE, device).toCloudRecord()
        db.cloudRecordDao().upsert(listOf(entity(paid)))
        assertFalse(store.commitInstallmentCycleMutations(intent, writes))
        assertNull(store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, device))
        assertEquals(paid, store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, paid.id))
        assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty())
    }
}
