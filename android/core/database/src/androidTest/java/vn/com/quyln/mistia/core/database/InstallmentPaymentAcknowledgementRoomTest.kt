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
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Synthetic fixtures: compile/package only until an Android device is available. */
@RunWith(AndroidJUnit4::class)
class InstallmentPaymentAcknowledgementRoomTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val version = 9007199254740995L
    private suspend fun prepare(store: RoomLocalStore): Triple<InstallmentPaymentAcknowledgementSnapshot, QueuedMutation, CloudRecord> {
        val catalog = SystemCategoryCatalog.parse(context.assets.open("MistiaSystemCategories.json").bufferedReader().use { it.readText() })
        val repo = OfflineFirstFinanceRepository(store, ZoneId.of("Asia/Tokyo"), catalog)
        val wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 9007199254740993), device, now).getOrThrow()
        val plan = repo.saveInstallment(owner, InstallmentDraft(id, "Loan", 9007199254740993, 15, 1, 12, wallet.id, "JPY"), device, now).getOrThrow()
        val saved = repo.payInstallment(owner, InstallmentPaymentRequest(plan, YearMonth.of(2026, 10)), device, now).getOrThrow()
        for (entity in listOf(CloudEntity.TRANSACTION_CATEGORY, CloudEntity.LEDGER_WALLET, CloudEntity.INSTALLMENT_PLAN, CloudEntity.LEDGER_TRANSACTION)) {
            for (q in store.pendingMutations(owner, entity, Long.MAX_VALUE)) {
                val current = store.record(owner, entity.table, q.mutation.recordId)!!
                val remote = current.copy(syncVersion = version, payload = JsonObject(current.payload + ("sync_version" to JsonPrimitive(version))))
                assertTrue(store.acknowledgeMutation(q, remote))
            }
        }
        val snapshot = store.installmentPaymentAcknowledgementSnapshot(owner, id)
        val remote = saved.occurrences.single().copy(updatedAt = later, syncVersion = version + 1).toCloudRecord()
        return Triple(snapshot, snapshot.queues.single(), remote)
    }
    private suspend fun ack(store: RoomLocalStore, s: InstallmentPaymentAcknowledgementSnapshot, q: QueuedMutation, remote: CloudRecord) =
        store.commitInstallmentPaymentAcknowledgement(s, q, s.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single(), remote,
            s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).associateBy { it.id }, s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).associateBy { it.id })
    @Test fun diskACKSurvivesReopenWithExactVersionAndUnchangedExpenseWalletPlan() = runTest {
        val name = "installment-paid-ack-${UUID.randomUUID()}.db"
        var db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).build()
        try {
            var store = RoomLocalStore(db); val (s, q, remote) = prepare(store)
            assertTrue(ack(store, s, q, remote))
            db.close(); db = Room.databaseBuilder(context, MistiaDatabase::class.java, name).build(); store = RoomLocalStore(db)
            val current = store.installmentPaymentAcknowledgementSnapshot(owner, id)
            assertTrue(current.queues.isEmpty()); assertEquals(remote, current.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single())
            assertEquals(s.recordsByEntity.filterKeys { it != CloudEntity.DUE_OCCURRENCE_RECORD }, current.recordsByEntity.filterKeys { it != CloudEntity.DUE_OCCURRENCE_RECORD })
        } finally { db.close(); context.deleteDatabase(name) }
    }
    @Test fun newerWalletLedgerSourceOrQueueBlocksOldACKAndFailureTogether() = runTest {
        for (entity in listOf(CloudEntity.LEDGER_WALLET, CloudEntity.LEDGER_TRANSACTION, CloudEntity.INSTALLMENT_PLAN, CloudEntity.DUE_OCCURRENCE_RECORD)) {
            val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
            try {
                val store = RoomLocalStore(db); val (s, q, remote) = prepare(store)
                if (entity == CloudEntity.DUE_OCCURRENCE_RECORD) store.recordMutationFailure(q, 123456, "fixture") else {
                    val before = s.recordsByEntity.getValue(entity).single()
                    val changed = before.copy(updatedAt = later, payload = JsonObject(before.payload + ("updated_at" to JsonPrimitive(later))))
                    store.commitMutation(changed, PendingMutation(entity, changed.id, owner.value, MutationKind.UPSERT, changed.payload, later, changed.syncVersion, device))
                }
                val expected = store.installmentPaymentAcknowledgementSnapshot(owner, id)
                assertFalse(ack(store, s, q, remote)); assertFalse(store.recordInstallmentPaymentAcknowledgementFailure(s, q, 456, "fixture"))
                assertEquals(expected, store.installmentPaymentAcknowledgementSnapshot(owner, id))
            } finally { db.close() }
        }
    }
    @Test fun ACKRecordFailureRollsBackQueueRemovalAndAllFinancialRecords() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store = RoomLocalStore(db); val (s, q, remote) = prepare(store)
            db.openHelper.writableDatabase.execSQL("""CREATE TRIGGER reject_paid_ack BEFORE INSERT ON cloud_records
                WHEN NEW.entity='due_occurrence_records' BEGIN SELECT RAISE(ABORT, 'fixture'); END""")
            assertTrue(runCatching { ack(store, s, q, remote) }.isFailure)
            assertEquals(s, store.installmentPaymentAcknowledgementSnapshot(owner, id))
        } finally { db.close() }
    }
    @Test fun ownerChangeBeforeAndAfterActualQueueRemovalCancelsAndRollsBack() = runTest {
        for (after in listOf(false, true)) {
            val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
            try {
                val initial = RoomLocalStore(db); val (s, q, remote) = prepare(initial)
                var sawRemoval = false
                val guarded = RoomLocalStore(db, currentBillOwner = {
                    val exists = db.openHelper.writableDatabase.query("SELECT COUNT(*) FROM sync_outbox WHERE owner_user_id=? AND entity=? AND record_id=?", arrayOf(owner.value, q.mutation.entity.table, q.mutation.recordId)).use { it.moveToFirst(); it.getInt(0) > 0 }
                    if (!exists) sawRemoval = true
                    if (after && exists) owner else UserId(other)
                })
                var cancelled = false
                try { ack(guarded, s, q, remote) } catch (_: CancellationException) { cancelled = true }
                assertTrue(cancelled); if (after) assertTrue(sawRemoval)
                assertEquals(s, initial.installmentPaymentAcknowledgementSnapshot(owner, id))
            } finally { db.close() }
        }
    }
    @Test fun sourceDeletionBatchCreatedDuringReadCannotBeClearedByOldPaidACK() = runTest {
        val db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).build()
        try {
            val store = RoomLocalStore(db); val (s, q, remote) = prepare(store)
            val source = InstallmentPlanRecord.fromCloudRecord(s.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single())
            OfflineFirstFinanceRepository(store).deleteInstallment(owner, source, device, later).getOrThrow()
            val before = store.installmentPaymentAcknowledgementSnapshot(owner, id)
            assertNotNull(before.batch); assertFalse(ack(store, s, q, remote)); assertFalse(store.recordInstallmentPaymentAcknowledgementFailure(s, q, 1, "fixture"))
            assertEquals(before, store.installmentPaymentAcknowledgementSnapshot(owner, id))
        } finally { db.close() }
    }
}
