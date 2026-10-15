package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardCreationRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val profileId = "44444444-4444-4444-4444-444444444444"
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-15T00:00:00Z"
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db)
    }
    @After fun close() { db.close() }
    private fun mutation(subject: UserId = owner) = CreditCardDraft(walletId = walletId, profileId = profileId, name = "Card", creditLimitMinor = 9007199254740993L)
        .toMutation(subject, null, null, null, device, now)
    private fun pairs(value: CreditCardAggregateMutation) = listOf(value.wallet.record.toCloudRecord() to value.wallet.pending, value.profile.record.toCloudRecord() to value.profile.pending)
    private suspend fun apply(value: CreditCardAggregateMutation = mutation(), target: RoomLocalStore = store) = target.commitCreditCardMutation(
        value.wallet.record.toCloudRecord(), value.wallet.pending, value.profile.record.toCloudRecord(), value.profile.pending)
    private suspend fun records() = listOf(store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId), store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, profileId))
    private suspend fun queues() = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) + store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE)
    private suspend fun assertHeld(value: CreditCardAggregateMutation = mutation()) {
        val before = records(); val queue = queues()
        Assert.assertTrue(runCatching { apply(value) }.isFailure)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun createsBothRecordsAndQueuesWithoutLosingLargeMinorUnits() = runTest {
        apply()
        Assert.assertTrue(records().all { it != null }); Assert.assertEquals(2, queues().size)
        Assert.assertEquals(9007199254740993L, records()[1]!!.payload["credit_limit_minor"]!!.jsonPrimitive.long)
        Assert.assertEquals(0L, records()[0]!!.payload["opening_balance_minor"]!!.jsonPrimitive.long)
    }
    @Test fun changedOwnerBeforeCreationWritesNothing() = runTest {
        val fenced = RoomLocalStore(db, currentBillOwner = { other })
        Assert.assertTrue(runCatching { apply(target = fenced) }.exceptionOrNull() is CancellationException)
        Assert.assertTrue(records().all { it == null }); Assert.assertTrue(queues().isEmpty())
    }
    @Test fun ownerChangeAfterWritesRollsBackBothRecordsAndBothQueues() = runTest {
        var checks = 0
        val fenced = RoomLocalStore(db, currentBillOwner = { if (++checks == 1) owner else other })
        Assert.assertTrue(runCatching { apply(target = fenced) }.exceptionOrNull() is CancellationException)
        Assert.assertEquals(2, checks); Assert.assertTrue(records().all { it == null }); Assert.assertTrue(queues().isEmpty())
    }
    @Test fun walletIdentityClaimedAfterDraftCreationIsNeverOverwritten() = runTest {
        val captured = mutation(); val row = captured.wallet.record.copy(name = "Concurrent wallet").toCloudRecord()
        store.commitMutation(row, captured.wallet.pending.copy(payload = row.payload))
        assertHeld(captured)
    }
    @Test fun profileIdentityClaimedAfterDraftCreationIsNeverOverwritten() = runTest {
        val captured = mutation(); val row = captured.profile.record.copy(notes = "Concurrent profile").toCloudRecord()
        store.commitMutation(row, captured.profile.pending.copy(payload = row.payload))
        assertHeld(captured)
    }
    @Test fun tombstonedIdentityCannotBeRecreatedByAnOldDraft() = runTest {
        for ((row, pending) in pairs(mutation())) {
            db.clearAllTables()
            val tombstone = row.copy(deletedAt = now, payload = JsonObject(row.payload + ("deleted_at" to JsonPrimitive(now))))
            store.commitMutation(tombstone, pending.copy(payload = tombstone.payload, kind = MutationKind.DELETE))
            assertHeld()
        }
    }
    @Test fun orphanOutboxAtEitherIdentityIsPreserved() = runTest {
        for ((row, pending) in pairs(mutation())) {
            db.clearAllTables(); store.commitMutation(row, pending)
            db.cloudRecordDao().deleteRecord(owner.value, row.entity, row.id)
            assertHeld()
        }
    }
    @Test fun existingOrphanProfileLinkCannotGainAnotherProfile() = runTest {
        val captured = mutation(); val original = captured.profile.record.copy(id = "77777777-7777-7777-7777-777777777777").toCloudRecord()
        store.commitMutation(original, captured.profile.pending.copy(recordId = original.id, payload = original.payload))
        assertHeld(captured)
        Assert.assertEquals(original, store.record(owner, original.entity, original.id))
    }
    @Test fun otherOwnerRecordsAtTheSameIdentifiersAreNeverReadOrChanged() = runTest {
        apply(mutation(other)); val before = pairs(mutation(other)).map { (row, _) -> store.record(other, row.entity, row.id) }
        val otherQueues = store.pendingMutations(other, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) + store.pendingMutations(other, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE)
        apply(); Assert.assertEquals(2, queues().size)
        Assert.assertEquals(before, pairs(mutation(other)).map { (row, _) -> store.record(other, row.entity, row.id) })
        Assert.assertEquals(otherQueues, store.pendingMutations(other, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) + store.pendingMutations(other, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE))
    }
    @Test fun creationCannotCarryAnExistingCloudVersion() = runTest {
        for (entity in listOf(CloudEntity.LEDGER_WALLET, CloudEntity.CREDIT_CARD_PROFILE)) {
            val value = mutation()
            val changed = if (entity == CloudEntity.LEDGER_WALLET) {
                val row = value.wallet.record.copy(syncVersion = 9007199254740993L)
                value.copy(wallet = CreditCardWalletMutation(row, value.wallet.pending.copy(baseVersion = row.syncVersion, payload = row.toCloudRecord().payload)))
            } else {
                val row = value.profile.record.copy(syncVersion = 9007199254740993L)
                value.copy(profile = CreditCardProfileMutation(row, value.profile.pending.copy(baseVersion = row.syncVersion, payload = row.toCloudRecord().payload)))
            }
            assertHeld(changed)
        }
    }
}
