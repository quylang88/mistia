package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Actual transaction/DAO fixtures. Compilation is not device execution evidence. */
@RunWith(AndroidJUnit4::class)
class InstallmentRoomTest {
    private lateinit var database: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repository: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val wallet = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-10-14T01:00:00Z"
    private val active = AtomicReference<UserId?>(owner)
    private val flipDuringWrite = AtomicBoolean(false)
    @Before fun setup() {
        active.set(owner); flipDuringWrite.set(false)
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java)
            .allowMainThreadQueries().setQueryCallback(RoomDatabase.QueryCallback { sql, _ ->
                if (flipDuringWrite.get() && sql.contains("insert", ignoreCase = true) && sql.contains("sync_outbox")) active.set(UserId(other))
            }, Executor { it.run() }).build()
        store = RoomLocalStore(database, currentBillOwner = { active.get() })
        repository = OfflineFirstFinanceRepository(store)
    }
    @After fun close() { database.close() }
    private fun entity(record: CloudRecord) = CloudRecordEntity(record.ownerUserId, record.entity, record.id, record.payload.toString(),
        record.updatedAt, record.deletedAt, record.syncVersion, receivedAtEpochMillis = 0)
    private fun source() = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.installment", 5000, 15, 12, 1, wallet, "JPY", false,
        created, created, null, 9007199254740993L, device)
    private fun due() = DueOccurrenceRecord(other, owner.value, "installment", id, "2026-01", created, 5000, "paid", created, wallet,
        created, created, null, 9007199254740995L, device)
    private fun draft(expected: InstallmentPlanRecord? = null) = InstallmentDraft(id, "Edited", 9007199254740993L, 31, 2, null, wallet, "JPY", expected = expected)
    private suspend fun seedWallet() {
        val record = WalletDraft(id = wallet, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY").toMutation(owner, null, device, created).record
        database.cloudRecordDao().upsert(listOf(entity(record)))
    }
    @Test fun editThenDeleteCoalescesLongBasesAndLeavesPostedTransactionUntouched() = runTest {
        seedWallet(); val original = source(); val occurrence = due()
        val ledger = WalletDraft(id = wallet, name = "Ledger fixture", kind = WalletKind.CASH, currencyCode = "JPY")
            .toMutation(owner, null, device, created).record.copy(entity = CloudEntity.LEDGER_TRANSACTION.table)
        database.cloudRecordDao().upsert(listOf(original.toCloudRecord(), occurrence.toCloudRecord(), ledger).map(::entity))
        val saved = repository.saveInstallment(owner, draft(original), device, now).getOrThrow()
        repository.deleteInstallment(owner, saved, device, "2026-10-14T02:00:00Z").getOrThrow()
        val outbox = database.syncOutboxDao().rows(owner.value)
        assertEquals(2, outbox.size); assertTrue(outbox.all { it.kind == "delete" })
        assertEquals(original.syncVersion, outbox.single { it.entity == CloudEntity.INSTALLMENT_PLAN.table }.baseVersion)
        assertEquals(occurrence.syncVersion, outbox.single { it.entity == CloudEntity.DUE_OCCURRENCE_RECORD.table }.baseVersion)
        assertEquals(ledger, store.record(owner, ledger.entity, ledger.id))
        assertNotNull(store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, occurrence.id)!!.deletedAt)
    }
    @Test fun outboxFailureRollsBackSourceAndEveryOccurrence() = runTest {
        seedWallet(); val original = source(); val occurrence = due()
        database.cloudRecordDao().upsert(listOf(original.toCloudRecord(), occurrence.toCloudRecord()).map(::entity))
        database.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_installment_delete BEFORE INSERT ON sync_outbox
            WHEN NEW.entity = 'due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'simulated'); END""")
        assertTrue(repository.deleteInstallment(owner, original, device, now).isFailure)
        assertEquals(original.toCloudRecord(), store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertEquals(occurrence.toCloudRecord(), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, occurrence.id))
        assertTrue(database.syncOutboxDao().rows(owner.value).isEmpty())
    }
    @Test fun ownerChangeDuringSqlWriteCancelsAndRollsBackRecordAndOutbox() = runTest {
        seedWallet(); flipDuringWrite.set(true)
        try { repository.saveInstallment(owner, draft(), device, now); fail("Cancellation expected") }
        catch (_: CancellationException) {
            assertNull(store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
            assertTrue(database.syncOutboxDao().rows(owner.value).isEmpty())
        }
    }
    @Test fun ownerChangeBeforeSnapshotCannotBeginAStaleAccountWrite() = runTest {
        seedWallet(); active.set(UserId(other))
        try { repository.saveInstallment(owner, draft(), device, now); fail("Cancellation expected") }
        catch (_: CancellationException) { assertTrue(database.syncOutboxDao().rows(owner.value).isEmpty()) }
    }
}
