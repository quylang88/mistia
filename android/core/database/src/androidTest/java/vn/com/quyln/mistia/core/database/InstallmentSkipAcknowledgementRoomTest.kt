package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Compile/package only until a device is available. No remote or production access. */
@RunWith(AndroidJUnit4::class)
class InstallmentSkipAcknowledgementRoomTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val zone = ZoneId.of("Asia/Tokyo")
    private suspend fun prepare(store: RoomLocalStore): Triple<InstallmentAcknowledgementSnapshot, QueuedMutation, CloudRecord> {
        val repo = OfflineFirstFinanceRepository(store, zone)
        val plan = repo.saveInstallment(owner, InstallmentDraft(id, "Loan", 1375, 15, 1, 12, null, "USD"), device, now).getOrThrow()
        val root = store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).single()
        store.acknowledgeMutation(root, plan.toCloudRecord())
        val cycle = repo.skipInstallment(owner, plan, YearMonth.of(2026, 10), device, now).getOrThrow()
        val snapshot = store.installmentAcknowledgementSnapshot(owner, id)
        return Triple(snapshot, snapshot.queues.single(), cycle.copy(syncVersion = 9007199254740996, updatedAt = later).toCloudRecord())
    }
    private fun source(snapshot: InstallmentAcknowledgementSnapshot) = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single()
    @Test fun diskACKKeepsExactVersionNullsAndOtherTablesThenSurvivesReopen() = runTest {
        val name = "installment-skip-ack-${UUID.randomUUID()}.db"
        var db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).build()
        try {
            var store = RoomLocalStore(db); val (snapshot, queued, remote) = prepare(store)
            val before = CloudEntity.entries.filter { it != CloudEntity.DUE_OCCURRENCE_RECORD }.associateWith { store.recordsIncludingDeleted(owner, it.table) }
            assertTrue(store.commitInstallmentSkipAcknowledgement(snapshot, queued, source(snapshot), remote, zone))
            db.close(); db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).build(); store = RoomLocalStore(db)
            assertEquals(remote, store.record(owner, remote.entity, remote.id)); assertTrue(store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE).isEmpty())
            assertEquals(before, before.keys.associateWith { store.recordsIncludingDeleted(owner, it.table) })
            assertEquals(9007199254740996, DueOccurrenceRecord.fromCloudRecord(store.record(owner, remote.entity, remote.id)!!).syncVersion)
        } finally { db.close(); context.deleteDatabase(name) }
    }
    @Test fun newerQueueOrSourceMutationInvalidatesACKAndScopedFailureTogether() = runTest {
        for (root in listOf(false, true)) {
            val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
            try {
                val store = RoomLocalStore(db); val (snapshot, queued, remote) = prepare(store)
                if (root) {
                    val p = InstallmentPlanRecord.fromCloudRecord(source(snapshot)).copy(name = "Changed", updatedAt = later)
                    store.commitMutation(p.toCloudRecord(), PendingMutation(CloudEntity.INSTALLMENT_PLAN, p.id, owner.value, MutationKind.UPSERT, p.toPayload(), later, p.syncVersion, device))
                } else store.recordMutationFailure(queued, 123, "fixture")
                val before = store.installmentAcknowledgementSnapshot(owner, id)
                assertFalse(store.commitInstallmentSkipAcknowledgement(snapshot, queued, source(snapshot), remote, zone))
                assertFalse(store.recordInstallmentSkipFailure(snapshot, queued, 456, "fixture"))
                assertEquals(before, store.installmentAcknowledgementSnapshot(owner, id))
            } finally { db.close() }
        }
    }
    @Test fun ACKWriteFailureRollsBackExactOutboxRemoval() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store = RoomLocalStore(db); val (snapshot, queued, remote) = prepare(store)
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_skip_ack BEFORE INSERT ON cloud_records
                WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
            assertTrue(runCatching { store.commitInstallmentSkipAcknowledgement(snapshot, queued, source(snapshot), remote, zone) }.isFailure)
            assertEquals(snapshot, store.installmentAcknowledgementSnapshot(owner, id))
        } finally { db.close() }
    }
    @Test fun ownerChangeBeforeOrAfterACKWritesRollsBackQueueAndRecord() = runTest {
        for (after in listOf(false, true)) {
            val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
            try {
                val initial = RoomLocalStore(db); val (snapshot, queued, remote) = prepare(initial)
                var sawRemoval = false
                val guarded = RoomLocalStore(db, currentBillOwner = {
                    val exists = db.openHelper.writableDatabase.query("SELECT COUNT(*) FROM sync_outbox WHERE owner_user_id=? AND entity=? AND record_id=?", arrayOf(owner.value, queued.mutation.entity.table, queued.mutation.recordId)).use { it.moveToFirst(); it.getInt(0) > 0 }
                    if (!exists) sawRemoval = true
                    if (after && exists) owner else UserId(other)
                })
                var cancelled = false
                try { guarded.commitInstallmentSkipAcknowledgement(snapshot, queued, source(snapshot), remote, zone) } catch (_: CancellationException) { cancelled = true }
                assertTrue(cancelled); if (after) assertTrue(sawRemoval)
                assertEquals(snapshot, initial.installmentAcknowledgementSnapshot(owner, id))
            } finally { db.close() }
        }
    }
    @Test fun paidRemoteAndChangedSourceCannotBeAcknowledgedAsSkipMetadata() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store = RoomLocalStore(db); val (snapshot, queued, remote) = prepare(store)
            val paid = DueOccurrenceRecord.fromCloudRecord(remote).copy(statusWireValue = "paid", amountMinorSnapshot = 1375, paidAt = now, linkedTransactionId = other).toCloudRecord()
            assertTrue(runCatching { store.commitInstallmentSkipAcknowledgement(snapshot, queued, source(snapshot), paid, zone) }.isFailure)
            val changed = InstallmentPlanRecord.fromCloudRecord(source(snapshot)).copy(currencyCode = "VND").toCloudRecord()
            assertTrue(runCatching { store.commitInstallmentSkipAcknowledgement(snapshot, queued, changed, remote, zone) }.isFailure)
            assertEquals(snapshot, store.installmentAcknowledgementSnapshot(owner, id))
        } finally { db.close() }
    }
    @Test fun scopedRetryPersistsOnlyTheExpectedQueueWithoutChangingMetadataRecords() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store = RoomLocalStore(db); val (snapshot, queued) = prepare(store)
            assertTrue(store.recordInstallmentSkipFailure(snapshot, queued, 123456, "network_io"))
            val current = store.installmentAcknowledgementSnapshot(owner, id)
            assertEquals(snapshot.recordsByEntity, current.recordsByEntity); assertEquals(1, current.queues.single().attemptCount)
            assertEquals(123456L, current.queues.single().nextAttemptAtEpochMillis)
            assertFalse(store.recordInstallmentSkipFailure(snapshot, queued, 1, "stale"))
        } finally { db.close() }
    }
}
