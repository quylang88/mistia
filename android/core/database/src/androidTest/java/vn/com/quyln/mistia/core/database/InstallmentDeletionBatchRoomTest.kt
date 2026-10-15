package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Disk Room/transaction fixtures. Compiled only until an Android device is available. */
@RunWith(AndroidJUnit4::class)
class InstallmentDeletionBatchRoomTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val databaseName = "mistia-delete-batch-${UUID.randomUUID()}.db"
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val wallet = "44444444-4444-4444-4444-444444444444"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-10-15T00:00:00Z"
    private val active = AtomicReference<UserId?>(owner)
    private val flip = AtomicBoolean(false)
    private fun open() {
        db = Room.databaseBuilder(context, MistiaDatabase::class.java, databaseName).allowMainThreadQueries()
            .setQueryCallback(RoomDatabase.QueryCallback { sql, _ ->
                if (flip.get() && sql.contains("INSERT", true) && sql.contains("installment_delete_batches")) active.set(other)
            }, Executor { it.run() }).build()
        store = RoomLocalStore(db, currentBillOwner = { active.get() }); repo = OfflineFirstFinanceRepository(store)
    }
    @Before fun setup() { active.set(owner); flip.set(false); open() }
    @After fun close() { db.close(); context.deleteDatabase(databaseName) }
    private fun plan(user: UserId = owner) = InstallmentPlanRecord(id, user.value, "Loan", "mistia.plan.loan", 9007199254740993, 31, null, 1,
        wallet, "JPY", false, created, created, null, 9007199254740995, device)
    private fun due(index: Int, user: UserId = owner, tombstone: Boolean = false) = DueOccurrenceRecord("70000000-0000-0000-0000-${index.toString().padStart(12, '0')}",
        user.value, "installment", id, "2026-01", created, 9007199254740993, "paid", created, wallet, created,
        if (tombstone) now else created, if (tombstone) now else null, 9007199254740997, device).toCloudRecord()
    private fun entity(r: CloudRecord) = CloudRecordEntity(r.ownerUserId, r.entity, r.id, r.payload.toString(), r.updatedAt, r.deletedAt, r.syncVersion, receivedAtEpochMillis = 0)
    private suspend fun seed(user: UserId = owner, cycle: Boolean = true) {
        val source = plan(user).toCloudRecord().let { it.copy(payload = JsonObject(it.payload + ("future" to JsonPrimitive("keep")))) }
        val cash = WalletDraft(id = wallet, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY").toMutation(user, null, device, created).record
        db.cloudRecordDao().upsert((listOf(source, cash) + if (cycle) listOf(due(1, user), due(2, user, true)) else emptyList()).map(::entity))
    }
    @Test fun nativeDeleteCapturesOnlyLiveCycleAndExactPriorQueueWithoutTouchingPaidFields() = runTest {
        seed()
        val saved = repo.saveInstallment(owner, InstallmentDraft(id, "Edited", 9007199254740993, 31, 1, null, wallet, "JPY", expected = plan()), device, created).getOrThrow()
        val oldQueue = db.syncOutboxDao().record(owner.value, CloudEntity.INSTALLMENT_PLAN.table, id)!!
        db.syncOutboxDao().upsert(oldQueue.copy(attemptCount = 7, nextAttemptAtEpochMillis = Long.MAX_VALUE, lastError = "http_503", remoteIdentityObserved = true))
        val previous = store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).single()
        repo.deleteInstallment(owner, saved, device, now).getOrThrow()
        val batch = store.installmentDeletionBatch(owner, id)!!
        assertEquals(previous, batch.source.pendingBefore); assertEquals(listOf(due(1).id), batch.cycles.map { it.before.id })
        assertEquals(due(1), batch.cycles.single().before); assertEquals(JsonPrimitive("keep"), batch.source.before.payload["future"])
        assertEquals(due(2, tombstone = true), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, due(2).id))
        assertEquals(2, db.syncOutboxDao().rows(owner.value).size)
        assertTrue(store.recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table).isEmpty())
    }
    @Test fun outboxFailureRollsBackBatchSourceAndCyclesTogether() = runTest {
        seed()
        db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_batch_outbox BEFORE INSERT ON sync_outbox
            WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
        assertTrue(repo.deleteInstallment(owner, plan(), device, now).isFailure)
        assertNull(store.installmentDeletionBatch(owner, id)); assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty())
        assertNull(store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!.deletedAt)
        assertEquals(due(1), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, due(1).id))
    }
    @Test fun ownerFlipDuringBatchInsertCancelsAndRollsBackEveryTable() = runTest {
        seed(); flip.set(true)
        try { repo.deleteInstallment(owner, plan(), device, now); fail("Cancellation expected") }
        catch (_: CancellationException) {
            active.set(owner)
            assertNull(store.installmentDeletionBatch(owner, id)); assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty())
            assertNull(store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!.deletedAt)
        }
    }
    @Test fun ownerReadGuardPreventsReturningPreviousAccountsIntent() = runTest {
        seed(); repo.deleteInstallment(owner, plan(), device, now).getOrThrow(); active.set(other)
        try { store.installmentDeletionBatch(owner, id); fail("Cancellation expected") }
        catch (_: CancellationException) { assertNull(store.installmentDeletionBatch(other, id)) }
    }
    @Test fun diskReopenRetainsExactCausalMembershipAndLongMetadata() = runTest {
        seed(); repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        val before = store.installmentDeletionBatch(owner, id)!!
        db.close(); open()
        assertEquals(before, store.installmentDeletionBatch(owner, id))
        repo.deleteInstallment(owner, plan(), device, "2026-10-15T01:00:00Z").getOrThrow()
        assertEquals(before, store.installmentDeletionBatch(owner, id))
        assertEquals(9007199254740997L, before.cycles.single().deletion.baseVersion)
    }
    @Test fun clearAccountRemovesOnlyThatOwnersCausalBatch() = runTest {
        seed(); repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        val firstBatchId = store.installmentDeletionBatch(owner, id)!!.batchId
        active.set(other); seed(other); repo.deleteInstallment(other, plan(other), device, now).getOrThrow()
        store.clearAccount(owner)
        assertTrue(db.installmentDeletionDao().rows(owner.value).isEmpty())
        assertTrue(db.installmentDeletionDao().chunks(owner.value, id, firstBatchId).isEmpty())
        assertEquals(1, db.installmentDeletionDao().rows(other.value).size)
        assertNotNull(store.installmentDeletionBatch(other, id))
    }
    @Test fun existingUnresolvedBatchCannotBeOverwrittenByAnotherDelete() = runTest {
        seed(); repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        val existing = store.installmentDeletionBatch(owner, id)!!
        // Simulate an unresolved legacy repair returning the source/cycle to live storage.
        seed()
        db.openHelper.writableDatabase.execSQL("DELETE FROM sync_outbox WHERE owner_user_id=?", arrayOf<Any>(owner.value))
        assertTrue(repo.deleteInstallment(owner, plan(), device, now).isFailure)
        assertEquals(existing, store.installmentDeletionBatch(owner, id))
        assertNull(store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!.deletedAt)
    }
    @Test fun malformedPersistedIntentFailsClosedRatherThanBecomingMissing() = runTest {
        seed(); repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        val valid = store.installmentDeletionBatch(owner, id)!!.toJson()
        for (invalid in listOf(JsonObject(valid + ("format_version" to JsonPrimitive(99))), JsonObject(valid + ("batch_id" to JsonPrimitive(other.value))))) {
            db.openHelper.writableDatabase.execSQL("UPDATE installment_delete_batches SET payload_json=?", arrayOf<Any>(invalid.toString()))
            assertTrue(runCatching { store.installmentDeletionBatch(owner, id) }.isFailure)
        }
    }
    @Test fun independentPlanDeleteDoesNotCreateAnEmptyBatch() = runTest {
        seed(cycle = false); repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        assertNull(store.installmentDeletionBatch(owner, id)); assertEquals(1, db.syncOutboxDao().rows(owner.value).size)
    }
    @Test fun largeCausalDocumentUsesBoundedBlobRowsAndReadsBackExactUnicode() = runTest {
        seed()
        val original = due(1).let { it.copy(payload = JsonObject(it.payload + ("future" to JsonPrimitive("界".repeat(250000))))) }
        db.cloudRecordDao().upsert(listOf(entity(original).copy(hasPendingMutation = true)))
        db.syncOutboxDao().upsert(SyncOutboxEntity(owner.value, original.entity, original.id, "upsert", original.payload.toString(), created,
            original.syncVersion, device, remoteIdentityObserved = true))
        repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        val batch = store.installmentDeletionBatch(owner, id)!!
        val chunks = db.installmentDeletionDao().chunks(owner.value, id, batch.batchId)
        assertTrue(chunks.sumOf { it.payload.size } > 2 * 1024 * 1024)
        assertTrue(chunks.all { it.payload.size in 1..InstallmentDeletionStorage.CHUNK_BYTES })
        assertEquals(original, batch.cycles.single().before)
    }

}
