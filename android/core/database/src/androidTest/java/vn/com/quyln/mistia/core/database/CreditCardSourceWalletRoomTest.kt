package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardSourceWalletRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val sourceId = "55555555-5555-5555-5555-555555555555"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val profileId = "44444444-4444-4444-4444-444444444444"
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private data class Captured(val wallet: CloudRecord?, val profile: CloudRecord?, val mutation: CreditCardAggregateMutation)
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db)
    }
    @After fun close() { db.close() }
    private suspend fun capture(edit: Boolean): Captured {
        db.clearAllTables()
        val repo = OfflineFirstFinanceRepository(store)
        val source = repo.saveWallet(owner, WalletDraft(id = sourceId, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 10000), device, now).getOrThrow()
        val draft = CreditCardDraft(walletId = walletId, profileId = profileId, name = "Card", creditLimitMinor = 9007199254740993L, paymentSourceWalletId = sourceId)
        val original = if (edit) repo.saveCreditCard(owner, draft, device, now).getOrThrow() else null
        return Captured(original?.wallet?.toCloudRecord(), original?.profile?.toCloudRecord(), draft.toMutation(owner, original?.wallet, original?.profile, source, device, later))
    }
    private suspend fun apply(value: Captured) {
        val change = value.mutation
        if (value.wallet == null) store.commitCreditCardMutation(change.wallet.record.toCloudRecord(), change.wallet.pending, change.profile.record.toCloudRecord(), change.profile.pending)
        else store.commitCreditCardEdit(value.wallet, value.profile!!, change.wallet.record.toCloudRecord(), change.wallet.pending, change.profile.record.toCloudRecord(), change.profile.pending)
    }
    private suspend fun state() = CloudEntity.entries.filter { it in setOf(CloudEntity.LEDGER_WALLET, CloudEntity.CREDIT_CARD_PROFILE) }
        .associateWith { entity -> store.recordsIncludingDeleted(owner, entity.table).sortedBy { it.id } to store.pendingMutations(owner, entity, Long.MAX_VALUE).sortedBy { it.mutation.recordId } }
    private suspend fun changeSource(mode: String) {
        val row = store.record(owner, CloudEntity.LEDGER_WALLET.table, sourceId)!!
        if (mode == "missing") { db.cloudRecordDao().deleteRecord(owner.value, row.entity, row.id); return }
        val patch = when (mode) {
            "archived" -> mapOf("is_archived" to JsonPrimitive(true), "archived_at" to JsonPrimitive(later))
            "deleted" -> mapOf("deleted_at" to JsonPrimitive(later))
            "foreignPayload" -> mapOf("user_id" to JsonPrimitive(other.value))
            "cardKind" -> mapOf("kind_raw_value" to JsonPrimitive(WalletKind.CREDIT_CARD.wireValue))
            "unknownKind" -> mapOf("kind_raw_value" to JsonPrimitive("future_kind"))
            "malformedArchive" -> mapOf("is_archived" to JsonPrimitive("false"))
            else -> mapOf("name" to JsonPrimitive("New source metadata"), "sync_version" to JsonPrimitive(9007199254740993L))
        }
        val changed = row.copy(payload = JsonObject(row.payload + patch), deletedAt = if (mode == "deleted") later else null,
            syncVersion = if (mode == "metadata") 9007199254740993L else row.syncVersion)
        store.commitMutation(changed, PendingMutation(CloudEntity.LEDGER_WALLET, row.id, owner.value, if (mode == "deleted") MutationKind.DELETE else MutationKind.UPSERT,
            changed.payload, later, changed.syncVersion, device))
    }
    private suspend fun rejectsChangedSource(mode: String) {
        for (edit in listOf(false, true)) {
            val captured = capture(edit); changeSource(mode); val before = state()
            val result = runCatching { apply(captured) }
            Assert.assertEquals("mode=$mode edit=$edit", CreditCardValidationError.INVALID_PAYMENT_SOURCE, (result.exceptionOrNull() as? CreditCardValidationException)?.reason)
            Assert.assertEquals(before, state())
        }
    }
    @Test fun sourceArchivedAfterValidationHoldsCreateAndEdit() = runTest { rejectsChangedSource("archived") }
    @Test fun sourceDeletedAfterValidationHoldsCreateAndEdit() = runTest { rejectsChangedSource("deleted") }
    @Test fun sourceMissingAfterValidationHoldsCreateAndEdit() = runTest { rejectsChangedSource("missing") }
    @Test fun sourceWithForeignRawOwnerHoldsCreateAndEdit() = runTest { rejectsChangedSource("foreignPayload") }
    @Test fun sourceChangedToCreditCardHoldsCreateAndEdit() = runTest { rejectsChangedSource("cardKind") }
    @Test fun sourceChangedToUnknownKindHoldsCreateAndEdit() = runTest { rejectsChangedSource("unknownKind") }
    @Test fun malformedSourceArchiveFlagHoldsCreateAndEdit() = runTest { rejectsChangedSource("malformedArchive") }
    @Test fun validSourceMetadataChangesDoNotBlockCardSaveOrOverwriteSource() = runTest {
        for (edit in listOf(false, true)) {
            val captured = capture(edit); changeSource("metadata")
            val before = store.record(owner, CloudEntity.LEDGER_WALLET.table, sourceId)
            val queue = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).single { it.mutation.recordId == sourceId }
            apply(captured)
            Assert.assertEquals(before, store.record(owner, CloudEntity.LEDGER_WALLET.table, sourceId))
            Assert.assertEquals(queue, store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).single { it.mutation.recordId == sourceId })
            Assert.assertEquals(JsonPrimitive(sourceId), store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, profileId)!!.payload["payment_source_wallet_id"])
        }
    }
    @Test fun clearingSourceStillWorksWhenPreviouslySelectedWalletIsArchived() = runTest {
        val captured = capture(true); changeSource("archived")
        val profile = captured.mutation.profile.record.copy(paymentSourceWalletId = null)
        val change = captured.copy(mutation = captured.mutation.copy(profile = CreditCardProfileMutation(profile, captured.mutation.profile.pending.copy(payload = profile.toCloudRecord().payload))))
        apply(change)
        Assert.assertEquals(JsonNull, store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, profileId)!!.payload["payment_source_wallet_id"])
    }
}
