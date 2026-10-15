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
class CreditCardCurrencyRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val profileId = "44444444-4444-4444-4444-444444444444"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private fun draft(code: String = "JPY") = CreditCardDraft(walletId = walletId, profileId = profileId, name = "Card", currencyCode = code, creditLimitMinor = 9007199254740993L)
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
    }
    @After fun close() { db.close() }
    private suspend fun records() = listOf(store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId), store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, profileId))
    private suspend fun queues() = store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) + store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE)
    private data class Change(val wallet: CloudRecord, val profile: CloudRecord, val mutation: CreditCardAggregateMutation)
    private suspend fun change(): Change {
        val wallet = store.record(owner, CloudEntity.LEDGER_WALLET.table, walletId)!!
        val profile = store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, profileId)!!
        return Change(wallet, profile, draft("VND").toMutation(owner, LedgerWalletRecord.fromCloudRecord(wallet), CreditCardProfileRecord.fromCloudRecord(profile), null, device, later))
    }
    private suspend fun apply(change: Change, target: RoomLocalStore = store) = target.commitCreditCardEdit(change.wallet, change.profile,
        change.mutation.wallet.record.toCloudRecord(), change.mutation.wallet.pending, change.mutation.profile.record.toCloudRecord(), change.mutation.profile.pending)
    private fun ledger(subject: UserId = owner, source: String? = walletId, destination: String? = null, archived: Boolean = false, deleted: String? = null): CloudRecord {
        val id = "55555555-5555-5555-5555-555555555555"
        val payload = buildJsonObject {
            put("id", id); put("user_id", subject.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("title", "Card history"); put("amount_minor", 100); put("source_currency_code", "JPY"); put("destination_currency_code", "JPY")
            put("source_wallet_id", source?.let(::JsonPrimitive) ?: JsonNull); put("destination_wallet_id", destination?.let(::JsonPrimitive) ?: JsonNull)
            put("occurred_at", now); put("created_at", now); put("updated_at", now); put("created_by_user_id", subject.value); put("last_modified_by_user_id", subject.value)
            put("is_archived", archived); put("deleted_at", deleted?.let(::JsonPrimitive) ?: JsonNull); put("sync_version", 0)
        }
        return LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, id, subject.value, payload, now, deleted, 0)).toCloudRecord()
    }
    @Test fun sourceHistoryRejectsBothWalletCurrencyAndProfileChangesAtomically() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val before = records(); val queue = queues()
        Assert.assertTrue(repo.saveCreditCard(owner, draft("VND").copy(creditLimitMinor = 1234), device, later).isFailure)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun destinationHistoryAlsoRejectsCurrencyAndKeepsBothRecordsAndQueues() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger(source = null, destination = walletId)))
        val before = records(); val queue = queues()
        Assert.assertTrue(repo.saveCreditCard(owner, draft("VND"), device, later).isFailure)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun sameCurrencyLimitAndMetadataChangesRemainAllowedWithHistory() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val changed = repo.saveCreditCard(owner, draft().copy(name = "Renamed", creditLimitMinor = 9007199254740995L), device, later).getOrThrow()
        Assert.assertEquals("Renamed", changed.wallet.name); Assert.assertEquals("JPY", changed.wallet.currencyCode)
        Assert.assertEquals(9007199254740995L, changed.profile.creditLimitMinor)
    }
    @Test fun archivedDeletedUnrelatedAndOtherOwnerHistoryDoNotLockCurrency() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        for (row in listOf(ledger(archived = true), ledger(deleted = later), ledger(source = "66666666-6666-6666-6666-666666666666"))) {
            store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(row))
            repo.saveCreditCard(owner, draft("VND"), device, later).getOrThrow()
            repo.saveCreditCard(owner, draft(), device, later).getOrThrow()
        }
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, emptyList())
        store.replacePullSnapshot(other, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger(subject = other)))
        val changed = repo.saveCreditCard(owner, draft("VND"), device, later).getOrThrow()
        Assert.assertEquals("VND", changed.wallet.currencyCode); Assert.assertEquals(9007199254740993L, changed.profile.creditLimitMinor)
    }
    @Test fun incompleteDeletedOrCorruptAggregateCannotBeRewrittenAsACurrencyEdit() = runTest {
        for (mode in listOf("profileDeleted", "profileMissing", "walletClock", "profileClock", "profileMoney")) {
            db.clearAllTables(); repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
            val entity = if (mode == "walletClock") CloudEntity.LEDGER_WALLET else CloudEntity.CREDIT_CARD_PROFILE
            val id = if (mode == "walletClock") walletId else profileId
            val row = db.cloudRecordDao().record(owner.value, entity.table, id)!!
            val payload = Json.parseToJsonElement(row.payloadJson).jsonObject
            when (mode) {
                "profileMissing" -> db.cloudRecordDao().deleteRecord(owner.value, entity.table, id)
                "profileDeleted" -> db.cloudRecordDao().upsert(listOf(row.copy(deletedAt = later, payloadJson = JsonObject(payload + ("deleted_at" to JsonPrimitive(later))).toString())))
                "profileMoney" -> db.cloudRecordDao().upsert(listOf(row.copy(payloadJson = JsonObject(payload + ("credit_limit_minor" to JsonPrimitive("not-money"))).toString())))
                else -> db.cloudRecordDao().upsert(listOf(row.copy(payloadJson = JsonObject(payload + ("sync_version" to JsonPrimitive(99))).toString())))
            }
            val before = records(); val queue = queues()
            Assert.assertTrue(mode, repo.saveCreditCard(owner, draft("VND"), device, later).isFailure)
            Assert.assertEquals(mode, before, records()); Assert.assertEquals(mode, queue, queues())
        }
    }
    @Test fun historyArrivingAfterBothReadsStillRejectsBothWrites() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        val change = change(); val before = records(); val queue = queues()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val result = runCatching { apply(change) }
        Assert.assertEquals(WalletValidationError.CURRENCY_IN_USE, (result.exceptionOrNull() as? WalletValidationException)?.reason)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun newerWalletAloneIsNotOverwrittenByCapturedCardEdit() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow(); val change = change()
        val newer = LedgerWalletRecord.fromCloudRecord(change.wallet).copy(name = "Concurrent wallet", updatedAt = later).toCloudRecord()
        store.commitMutation(newer, PendingMutation(CloudEntity.LEDGER_WALLET, walletId, owner.value, MutationKind.UPSERT, newer.payload, later, newer.syncVersion, device))
        val before = records(); val queue = queues(); val result = runCatching { apply(change) }
        Assert.assertEquals(WalletValidationError.STALE_EDIT, (result.exceptionOrNull() as? WalletValidationException)?.reason)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun newerProfileAloneIsNotOverwrittenByCapturedCardEdit() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow(); val change = change()
        val newer = CreditCardProfileRecord.fromCloudRecord(change.profile).copy(notes = "Concurrent profile", updatedAt = later).toCloudRecord()
        store.commitMutation(newer, PendingMutation(CloudEntity.CREDIT_CARD_PROFILE, profileId, owner.value, MutationKind.UPSERT, newer.payload, later, newer.syncVersion, device))
        val before = records(); val queue = queues(); val result = runCatching { apply(change) }
        Assert.assertEquals(WalletValidationError.STALE_EDIT, (result.exceptionOrNull() as? WalletValidationException)?.reason)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun ownerChangeAfterBothWritesRollsBackTheWholeAggregate() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow(); val change = change()
        val before = records(); val queue = queues(); var checks = 0
        val fenced = RoomLocalStore(db, currentBillOwner = { if (++checks == 1) owner else other })
        val result = runCatching { apply(change, fenced) }
        Assert.assertTrue(result.exceptionOrNull() is kotlinx.coroutines.CancellationException)
        Assert.assertEquals(2, checks); Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun independentVersionsAboveDoublePrecisionStayExactOnBothOutboxes() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        val versions = listOf(Triple(CloudEntity.LEDGER_WALLET, walletId, 9007199254740993L), Triple(CloudEntity.CREDIT_CARD_PROFILE, profileId, 9007199254740995L))
        versions.forEach { (entity, id, version) ->
            val row = db.cloudRecordDao().record(owner.value, entity.table, id)!!
            val payload = Json.parseToJsonElement(row.payloadJson).jsonObject
            db.cloudRecordDao().upsert(listOf(row.copy(syncVersion = version, payloadJson = JsonObject(payload + ("sync_version" to JsonPrimitive(version))).toString())))
        }
        repo.saveCreditCard(owner, draft("VND"), device, later).getOrThrow()
        versions.forEach { (entity, id, version) ->
            Assert.assertEquals(version, store.record(owner, entity.table, id)!!.syncVersion)
            Assert.assertEquals(version, store.pendingMutations(owner, entity, Long.MAX_VALUE).single().mutation.baseVersion)
        }
    }
    @Test fun lateDuplicateProfileIdentityHoldsCurrencyWithoutPickingOneArbitrarily() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow(); val change = change()
        val duplicate = CreditCardProfileRecord.fromCloudRecord(change.profile).copy(id = "77777777-7777-7777-7777-777777777777").toCloudRecord()
        store.replacePullSnapshot(owner, CloudEntity.CREDIT_CARD_PROFILE.table, listOf(change.profile, duplicate))
        val before = records(); val queue = queues(); val result = runCatching { apply(change) }
        Assert.assertEquals(WalletValidationError.STALE_EDIT, (result.exceptionOrNull() as? WalletValidationException)?.reason)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
        Assert.assertEquals(duplicate, store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, duplicate.id))
    }
    @Test fun identifierWhitespaceCannotTreatExistingCardAsANewAggregate() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val before = records(); val queue = queues()
        Assert.assertTrue(repo.saveCreditCard(owner, draft("VND").copy(walletId = " $walletId ", profileId = " $profileId "), device, later).isFailure)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
    @Test fun noncanonicalOwnerCannotTreatExistingCardAsANewAggregate() = runTest {
        repo.saveCreditCard(owner, draft(), device, now).getOrThrow()
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(ledger()))
        val before = records(); val queue = queues()
        Assert.assertTrue(repo.saveCreditCard(UserId(" ${owner.value} "), draft("VND"), device, later).isFailure)
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
}
