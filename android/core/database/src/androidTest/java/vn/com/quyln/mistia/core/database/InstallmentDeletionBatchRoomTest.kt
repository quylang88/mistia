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
    private val flipAck = AtomicBoolean(false)
    private val flipPull = AtomicBoolean(false)
    private fun open() {
        db = Room.databaseBuilder(context, MistiaDatabase::class.java, databaseName).allowMainThreadQueries()
            .setQueryCallback(RoomDatabase.QueryCallback { sql, _ ->
                if (flip.get() && sql.contains("INSERT", true) && sql.contains("installment_delete_batches")) active.set(other)
                if (flipAck.get() && sql.contains("DELETE", true) && sql.contains("sync_outbox")) active.set(other)
                if (flipPull.get() && sql.contains("DELETE", true) && sql.contains("cloud_records")) active.set(other)
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

    private fun payment(amount: Long = 9007199254740993) = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, wallet, owner.value,
        buildJsonObject { put("id", wallet); put("user_id", owner.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("title", "Recorded payment"); put("amount_minor", amount); put("source_currency_code", "JPY"); put("source_wallet_id", wallet)
            put("occurred_at", created); put("created_at", created); put("updated_at", created); put("deleted_at", JsonNull); put("is_archived", false)
            put("sync_version", 3); put("created_by_user_id", owner.value); put("last_modified_by_user_id", owner.value); put("last_modified_by_device_id", device) }, created, null, 3)
    private suspend fun deletionSnapshot(): InstallmentAcknowledgementSnapshot {
        seed(); db.cloudRecordDao().upsert(entity(payment()))
        repo.deleteInstallment(owner, plan(), device, now).getOrThrow()
        return store.installmentAcknowledgementSnapshot(owner, id)
    }
    private fun rootQueue(s: InstallmentAcknowledgementSnapshot) = s.queues.single { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN }
    private fun serverSource() = plan().copy(name = "Remote edit", updatedAt = "2026-10-16T00:00:00Z", syncVersion = 9007199254740996).toCloudRecord()
    private suspend fun acknowledge(s: InstallmentAcknowledgementSnapshot, remote: CloudRecord = serverSource()) =
        store.commitInstallmentSourceAcknowledgement(s, rootQueue(s), s.batch?.batchId, remote,
            if (remote.deletedAt == null) mapOf(due(1).id to due(1)) else emptyMap(),
            if (remote.deletedAt == null) mapOf(wallet to payment()) else emptyMap(), "2026-10-17T00:00:00Z")

    @Test fun sourceAckRestoresPaidCycleAndClearsOnlyExactBatchChunksInOneTransaction() = runTest {
        val s = deletionSnapshot(); val batchId = s.batch!!.batchId
        assertTrue(acknowledge(s)); assertEquals(serverSource(), store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertEquals(due(1), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, due(1).id))
        assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
        assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty()); assertNull(store.installmentDeletionBatch(owner, id))
        assertTrue(db.installmentDeletionDao().chunks(owner.value, id, batchId).isEmpty())
        db.close(); open(); assertEquals(due(1), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, due(1).id))
    }
    @Test fun sourceAckChildWriteFailureRollsBackSourceQueueHistoryAndBatchCleanup() = runTest {
        val s = deletionSnapshot()
        db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_restore BEFORE INSERT ON cloud_records
            WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
        assertTrue(runCatching { acknowledge(s) }.isFailure)
        s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
    }
    @Test fun sourceAckOwnerFlipDuringQueueRemovalRollsBackAllChanges() = runTest {
        val s = deletionSnapshot(); flipAck.set(true)
        try { acknowledge(s); fail("Cancellation expected") } catch (_: CancellationException) {
            flipAck.set(false); active.set(owner); s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        }
    }
    @Test fun sourceAckStaleLedgerSnapshotCannotOverwriteAnyQueueOrSource() = runTest {
        val s = deletionSnapshot(); db.cloudRecordDao().upsert(entity(payment(900)))
        val fresh = store.installmentAcknowledgementSnapshot(owner, id)
        assertFalse(acknowledge(s)); fresh.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
    }
    @Test fun sourceAckQueueRetryMetadataAndRequestBatchIdentityAreCASFenced() = runTest {
        val s = deletionSnapshot()
        assertFalse(store.commitInstallmentSourceAcknowledgement(s, rootQueue(s), other.value, serverSource(), mapOf(due(1).id to due(1)), mapOf(wallet to payment()), "2026-10-17T00:00:00Z"))
        val child = db.syncOutboxDao().record(owner.value, CloudEntity.DUE_OCCURRENCE_RECORD.table, due(1).id)!!
        db.syncOutboxDao().upsert(child.copy(nextAttemptAtEpochMillis = Long.MAX_VALUE, lastError = "http_503"))
        val fresh = store.installmentAcknowledgementSnapshot(owner, id)
        assertFalse(acknowledge(s)); fresh.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
    }
    @Test fun deletedSourceAckKeepsChildTombstoneQueueBatchAndExpenseForDedicatedCleanup() = runTest {
        val s = deletionSnapshot(); val deleted = s.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single()
        assertTrue(acknowledge(s, deleted))
        assertEquals(s.batch, store.installmentDeletionBatch(owner, id))
        assertEquals(listOf(s.queues.single { it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD }),
            store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE))
        assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
    }

    @Test fun sourceAckRestoresPriorChildRetryAndRemoteIdentityExactly() = runTest {
        seed(); val before = due(1); db.cloudRecordDao().upsert(entity(payment()))
        db.syncOutboxDao().upsert(SyncOutboxEntity(owner.value, before.entity, before.id, "upsert", before.payload.toString(), created,
            before.syncVersion, device, 7, Long.MAX_VALUE, "http_503", true))
        val prior = store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE).single()
        repo.deleteInstallment(owner, plan(), device, now).getOrThrow(); val s = store.installmentAcknowledgementSnapshot(owner, id)
        assertTrue(store.commitInstallmentSourceAcknowledgement(s, rootQueue(s), s.batch!!.batchId, serverSource(),
            mapOf(before.id to null), mapOf(wallet to payment()), "2026-10-17T00:00:00Z"))
        assertEquals(before, store.record(owner, before.entity, before.id))
        assertEquals(listOf(prior), store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE))
        assertTrue(db.cloudRecordDao().record(owner.value, before.entity, before.id)!!.hasPendingMutation)
    }
    @Test fun sourceAckLeavesNewerChildMutationAndItsRawDataUntouched() = runTest {
        val s = deletionSnapshot(); val before = DueOccurrenceRecord.fromCloudRecord(due(1)).copy(updatedAt = "2026-10-16T00:00:00Z").toCloudRecord()
        store.commitMutation(before, PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD, before.id, owner.value, MutationKind.UPSERT, before.payload, before.updatedAt!!, before.syncVersion, device))
        val fresh = store.installmentAcknowledgementSnapshot(owner, id)
        val child = fresh.queues.single { it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD }
        assertTrue(store.commitInstallmentSourceAcknowledgement(fresh, rootQueue(s), s.batch!!.batchId, serverSource(), emptyMap(), emptyMap(), "2026-10-17T00:00:00Z"))
        assertEquals(before, store.record(owner, before.entity, before.id)); assertNull(store.installmentDeletionBatch(owner, id))
        assertEquals(listOf(child), store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE))
    }
    @Test fun missingRemoteCycleRestoresPaidFrozenHistoryWithMetadataRepairQueue() = runTest {
        val s = deletionSnapshot()
        assertTrue(store.commitInstallmentSourceAcknowledgement(s, rootQueue(s), s.batch!!.batchId, serverSource(), mapOf(due(1).id to null), mapOf(wallet to payment()), "2026-10-17T00:00:00Z"))
        val repaired = DueOccurrenceRecord.fromCloudRecord(store.record(owner, due(1).entity, due(1).id)!!)
        assertEquals(DueStatus.PAID, repaired.status); assertEquals(9007199254740993L, repaired.amountMinorSnapshot); assertEquals(wallet, repaired.linkedTransactionId)
        val q = store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE).single()
        assertEquals(MutationKind.UPSERT, q.mutation.kind); assertTrue(q.remoteIdentityObserved)
        assertEquals(9007199254740997L, q.mutation.baseVersion); assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
    }
    @Test fun sourceFailureRequiresOriginalBatchAndFullCurrentQueue() = runTest {
        val s = deletionSnapshot(); val q = rootQueue(s)
        assertFalse(store.recordInstallmentSourceFailure(q, other.value, 100, "network_io"))
        s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        assertTrue(store.recordInstallmentSourceFailure(q, s.batch!!.batchId, 100, "network_io"))
        assertFalse(store.recordInstallmentSourceFailure(q, s.batch!!.batchId, 200, "network_io"))
        val current = store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).single()
        assertEquals(1, current.attemptCount); assertEquals(100L, current.nextAttemptAtEpochMillis)
    }

    private suspend fun acknowledgedDeletion(): InstallmentAcknowledgementSnapshot {
        val s = deletionSnapshot(); val source = s.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single()
        assertTrue(acknowledge(s, source))
        return store.installmentAcknowledgementSnapshot(owner, id)
    }
    @Test fun pullCannotResurrectRemoveOrReplaceAcknowledgedSourceWhileBatchChildrenRemain() = runTest {
        val s = acknowledgedDeletion()
        val source = store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!
        assertFalse(db.cloudRecordDao().record(owner.value, source.entity, id)!!.hasPendingMutation)
        for (incoming in listOf(listOf(serverSource()), emptyList(), listOf(source.copy(syncVersion = 99, payload = JsonObject(source.payload + ("sync_version" to JsonPrimitive(99))))))) {
            repeat(3) { store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, incoming) }
            s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        }
        db.close(); open()
        store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, listOf(serverSource()))
        s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
    }
    @Test fun normalPullResumesAsSoonAsTheExactBatchHasBeenCleared() = runTest {
        val s = deletionSnapshot(); assertTrue(acknowledge(s)); assertNull(store.installmentDeletionBatch(owner, id))
        val edited = plan().copy(name = "Subsequent remote edit", updatedAt = "2026-10-17T00:00:00Z", syncVersion = 9007199254740999).toCloudRecord()
        store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, listOf(edited))
        assertEquals(edited, store.record(owner, edited.entity, id))
        store.replacePullSnapshot(owner, edited.entity, emptyList()); assertNull(store.record(owner, edited.entity, id))
    }
    @Test fun causalPullPinDoesNotSuppressOtherPlansOrOtherOwnersWithSameID() = runTest {
        val s = acknowledgedDeletion(); val another = plan().copy(id = other.value, name = "Other plan").toCloudRecord()
        store.replacePullSnapshot(owner, another.entity, listOf(serverSource(), another))
        assertEquals(another, store.record(owner, another.entity, another.id))
        assertEquals(s.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single(), store.record(owner, another.entity, id))
        active.set(other)
        val foreign = plan(other).toCloudRecord()
        store.replacePullSnapshot(other, foreign.entity, listOf(foreign)); assertEquals(foreign, store.record(other, foreign.entity, id))
        active.set(owner); assertEquals(s.batch, store.installmentDeletionBatch(owner, id))
    }
    private fun pullCursor(): Pair<Long, Int>? = db.openHelper.readableDatabase.query(
        "SELECT last_full_pull_epoch_millis,last_record_count FROM sync_cursors WHERE owner_user_id=? AND entity=?",
        arrayOf<Any>(owner.value, CloudEntity.INSTALLMENT_PLAN.table)).use { cursor ->
        if (cursor.moveToFirst()) cursor.getLong(0) to cursor.getInt(1) else null
    }
    @Test fun pullOwnerFlipRollsBackSnapshotAndCursorWithoutReleasingBatch() = runTest {
        val s = acknowledgedDeletion(); val cursorBefore = pullCursor()
        flipPull.set(true)
        try { store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, listOf(serverSource())); fail("Cancellation expected") }
        catch (_: CancellationException) {
            flipPull.set(false); active.set(owner)
            s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
            assertEquals(cursorBefore, pullCursor())
        }
    }
    @Test fun foreignInstallmentPullEnvelopeFailsBeforeAnyLocalSnapshotChange() = runTest {
        val s = acknowledgedDeletion()
        assertTrue(runCatching { store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, listOf(plan(other).toCloudRecord())) }.isFailure)
        assertTrue(runCatching { store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, listOf(due(1))) }.isFailure)
        s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
    }
    @Test fun malformedBatchStorageRemainsPinnedUntilExplicitRecoveryRatherThanBeingDroppedByPull() = runTest {
        val s = acknowledgedDeletion(); val source = store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)
        db.openHelper.writableDatabase.execSQL("UPDATE installment_delete_batches SET payload_json='{}' WHERE owner_user_id=?", arrayOf<Any>(owner.value))
        store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, listOf(serverSource()))
        assertEquals(source, store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertEquals(1, db.installmentDeletionDao().rows(owner.value).size)
        assertTrue(runCatching { store.installmentDeletionBatch(owner, id) }.isFailure)
    }

    private fun completedChild(s: InstallmentAcknowledgementSnapshot): CloudRecord = s.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single { it.id == due(1).id }.let {
        it.copy(syncVersion = it.syncVersion + 1, payload = JsonObject(it.payload + ("sync_version" to JsonPrimitive(it.syncVersion + 1))))
    }
    private suspend fun complete(s: InstallmentAcknowledgementSnapshot, requestBatchId: String = s.batch!!.batchId): Boolean =
        store.commitInstallmentDeletionCompletion(s, requestBatchId, s.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single(),
            mapOf(due(1).id to completedChild(s)), java.time.Instant.parse("2026-10-17T00:00:00Z").toEpochMilli())
    @Test fun completedChildBatchClearsAllQueuesHeadersChunksAndRetainsExactExpenseAcrossReopen() = runTest {
        val s = acknowledgedDeletion(); val batchId = s.batch!!.batchId
        assertEquals(setOf(id), store.installmentDeletionPlanIds(owner)); assertTrue(complete(s))
        assertTrue(store.installmentDeletionPlanIds(owner).isEmpty()); assertTrue(db.syncOutboxDao().rows(owner.value).isEmpty())
        assertTrue(db.installmentDeletionDao().chunks(owner.value, id, batchId).isEmpty())
        assertEquals(completedChild(s), store.record(owner, due(1).entity, due(1).id)); assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
        db.close(); open(); assertTrue(store.installmentDeletionPlanIds(owner).isEmpty()); assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
    }
    @Test fun completionWriteFailureRollsBackChildACKQueueAndCascadingBatchDeletion() = runTest {
        val s = acknowledgedDeletion()
        db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_completion BEFORE INSERT ON cloud_records
            WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
        assertTrue(runCatching { complete(s) }.isFailure); s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
    }
    @Test fun completionOwnerFlipDuringChildQueueRemovalRollsBackEveryTable() = runTest {
        val s = acknowledgedDeletion(); flipAck.set(true)
        try { complete(s); fail("Cancellation expected") } catch (_: CancellationException) {
            flipAck.set(false); active.set(owner); s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        }
    }
    @Test fun completionRejectsStaleLedgerAndDifferentRequestBatchWithoutAnyACK() = runTest {
        val s = acknowledgedDeletion(); assertFalse(complete(s, other.value)); s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        db.cloudRecordDao().upsert(entity(payment(800))); val current = store.installmentAcknowledgementSnapshot(owner, id)
        assertFalse(complete(s)); current.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
    }
    @Test fun completionWithFreshSnapshotPreservesSupersedingChildMutationAndClearsOnlyOldBatch() = runTest {
        val s = acknowledgedDeletion(); val newer = DueOccurrenceRecord.fromCloudRecord(due(1)).copy(updatedAt = "2026-10-16T00:00:00Z").toCloudRecord()
        store.commitMutation(newer, PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD, newer.id, owner.value, MutationKind.UPSERT, newer.payload, newer.updatedAt!!, newer.syncVersion, device))
        val fresh = store.installmentAcknowledgementSnapshot(owner, id); val q = fresh.queues.single()
        assertTrue(store.commitInstallmentDeletionCompletion(fresh, s.batch!!.batchId, fresh.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single(), emptyMap(), java.time.Instant.parse("2026-10-17T00:00:00Z").toEpochMilli()))
        assertEquals(newer, store.record(owner, newer.entity, newer.id)); assertEquals(listOf(q), store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE)); assertNull(store.installmentDeletionBatch(owner, id))
    }
    @Test fun completionFailurePersistenceUsesFullSnapshotAndExactBatchWithoutWritingFinancialRows() = runTest {
        val s = acknowledgedDeletion(); val q = s.queues.single()
        assertFalse(store.recordInstallmentDeletionFailure(s, other.value, q, 99, "network_io"))
        assertTrue(store.recordInstallmentDeletionFailure(s, s.batch!!.batchId, q, 99, "network_io"))
        assertFalse(store.recordInstallmentDeletionFailure(s, s.batch!!.batchId, q, 199, "network_io"))
        assertEquals(payment(), store.record(owner, CloudEntity.LEDGER_TRANSACTION.table, wallet))
        val retry = store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE).single()
        assertEquals(1, retry.attemptCount); assertEquals(99L, retry.nextAttemptAtEpochMillis)
    }
    @Test fun activeSourceCannotCompleteDeletedChildBatchAndForeignOwnerCannotListIt() = runTest {
        val s = acknowledgedDeletion()
        assertTrue(runCatching { store.commitInstallmentDeletionCompletion(s, s.batch!!.batchId, serverSource(), emptyMap(), 0) }.isFailure)
        s.requireUnchanged(store.installmentAcknowledgementSnapshot(owner, id))
        active.set(other); assertTrue(store.installmentDeletionPlanIds(other).isEmpty())
        try { store.installmentDeletionPlanIds(owner); fail("Cancellation expected") } catch (_: CancellationException) { }
    }

}
