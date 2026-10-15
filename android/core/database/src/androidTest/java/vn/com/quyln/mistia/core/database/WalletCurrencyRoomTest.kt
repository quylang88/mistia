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
class WalletCurrencyRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private fun draft(code: String = "JPY") = WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = code, openingBalanceMinor = 1000)
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
    }
    @After fun close() { db.close() }
    private fun ledger(subject: UserId = owner, source: String? = walletId, destination: String? = null, archived: Boolean = false, deleted: String? = null): CloudRecord {
        val id = "44444444-4444-4444-4444-444444444444"
        val payload = buildJsonObject {
            put("id", id); put("user_id", subject.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("title", "History"); put("amount_minor", 100); put("source_currency_code", "JPY"); put("destination_currency_code", "JPY")
            put("source_wallet_id", source?.let(::JsonPrimitive) ?: JsonNull); put("destination_wallet_id", destination?.let(::JsonPrimitive) ?: JsonNull)
            put("occurred_at", now); put("created_at", now); put("updated_at", now); put("created_by_user_id", subject.value); put("last_modified_by_user_id", subject.value)
            put("is_archived", archived); put("deleted_at", deleted?.let(::JsonPrimitive) ?: JsonNull); put("sync_version", 0)
        }
        return LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, id, subject.value, payload, now, deleted, 0)).toCloudRecord()
    }
    @Test fun sourceHistoryBlocksCurrencyChangeWithoutChangingRecordOrOutbox() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val record = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)
        val queue = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE)
        Assert.assertTrue(repo.saveWallet(owner, draft("VND"), device, later).isFailure)
        Assert.assertEquals(record, store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId))
        Assert.assertEquals(queue, store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE))
    }
    @Test fun destinationHistoryAlsoBlocksCurrencyChange() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger(source = null, destination = walletId)))
        Assert.assertTrue(repo.saveWallet(owner, draft("VND"), device, later).isFailure)
        Assert.assertEquals("JPY", LedgerWalletRecord.fromCloudRecord(store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)!!).currencyCode)
    }
    @Test fun sameCurrencyMetadataEditRemainsAllowedWithLiveHistory() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val changed = repo.saveWallet(owner, draft().copy(name = "Renamed"), device, later).getOrThrow()
        Assert.assertEquals("Renamed", changed.name); Assert.assertEquals("JPY", changed.currencyCode)
    }
    @Test fun archivedDeletedUnrelatedOrOtherOwnerHistoryDoesNotLockCurrency() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        for (history in listOf(ledger(archived = true), ledger(deleted = later), ledger(source = "55555555-5555-5555-5555-555555555555"))) {
            store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(history))
            repo.saveWallet(owner, draft("VND"), device, later).getOrThrow()
            repo.saveWallet(owner, draft(), device, later).getOrThrow()
        }
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, emptyList())
        store.replacePullSnapshot(other, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger(subject = other)))
        Assert.assertEquals("VND", repo.saveWallet(owner, draft("VND"), device, later).getOrThrow().currencyCode)
    }
    @Test fun historyArrivingAfterWalletReadStillBlocksAtomicCurrencyCommit() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        val before = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)!!
        val change = draft("VND").toMutation(owner, LedgerWalletRecord.fromCloudRecord(before), device, later)
        val queue = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE)
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val result = runCatching { store.commitWalletCurrencyMutation(before, change.record, change.pending) }
        Assert.assertEquals(WalletValidationError.CURRENCY_IN_USE, (result.exceptionOrNull() as? WalletValidationException)?.reason)
        Assert.assertEquals(before, store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId))
        Assert.assertEquals(queue, store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE))
    }
    @Test fun newerWalletSnapshotCannotBeOverwrittenByAnOlderCurrencyRequest() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        val before = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)!!
        val change = draft("VND").toMutation(owner, LedgerWalletRecord.fromCloudRecord(before), device, later)
        repo.saveWallet(owner, draft().copy(name = "Newer metadata"), device, later).getOrThrow()
        val newer = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)
        val queue = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE)
        val result = runCatching { store.commitWalletCurrencyMutation(before, change.record, change.pending) }
        Assert.assertEquals(WalletValidationError.STALE_EDIT, (result.exceptionOrNull() as? WalletValidationException)?.reason)
        Assert.assertEquals(newer, store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId))
        Assert.assertEquals(queue, store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE))
    }
    @Test fun ownerChangingInsideCommitRollsBackWalletAndOutboxTogether() = runTest {
        repo.saveWallet(owner, draft(), device, now).getOrThrow()
        val before = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)!!
        val change = draft("VND").toMutation(owner, LedgerWalletRecord.fromCloudRecord(before), device, later)
        val queue = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE)
        var checks = 0
        val fenced = RoomLocalStore(db, currentBillOwner = { if (++checks == 1) owner else other })
        val result = runCatching { fenced.commitWalletCurrencyMutation(before, change.record, change.pending) }
        Assert.assertTrue(result.exceptionOrNull() is kotlinx.coroutines.CancellationException)
        Assert.assertEquals(before, store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId))
        Assert.assertEquals(queue, store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE))
    }
    @Test fun malformedMoneyOrDisagreeingSyncClockCannotBeRewrittenDuringCurrencyEdit() = runTest {
        for (mode in listOf("invalidMoney", "missingMoney", "wireClock")) {
            db.clearAllTables()
            repo.saveWallet(owner, draft(), device, now).getOrThrow()
            val row = db.cloudRecordDao().record(owner.value, CloudEntity.LEDGER_WALLET.table, walletId)!!
            val payload = Json.parseToJsonElement(row.payloadJson).jsonObject
            val corrupted = when (mode) {
                "invalidMoney" -> JsonObject(payload + ("opening_balance_minor" to JsonPrimitive("not-money")))
                "missingMoney" -> JsonObject(payload - "opening_balance_minor")
                else -> JsonObject(payload + ("sync_version" to JsonPrimitive(99)))
            }
            db.cloudRecordDao().upsert(listOf(row.copy(payloadJson = corrupted.toString())))
            val before = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)
            val queue = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE)
            Assert.assertTrue(mode, repo.saveWallet(owner, draft("VND"), device, later).isFailure)
            Assert.assertEquals(mode, before, store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId))
            Assert.assertEquals(mode, queue, store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE))
        }
    }
}
