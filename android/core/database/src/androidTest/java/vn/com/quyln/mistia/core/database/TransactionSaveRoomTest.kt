package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionSaveRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var cash: LedgerWalletRecord
    private lateinit var destination: LedgerWalletRecord
    private lateinit var category: TransactionCategoryRecord
    private var activeOwner: UserId? = null
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val targetId = "33333333-3333-3333-3333-333333333333"
    private val now = "2026-10-15T00:00:00Z"
    @Before fun setup() = kotlinx.coroutines.runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        activeOwner = owner; store = RoomLocalStore(db, currentBillOwner = { activeOwner }); repo = OfflineFirstFinanceRepository(store)
        cash = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 10000), device, now).getOrThrow()
        destination = repo.saveWallet(owner, WalletDraft(name = "Destination", kind = WalletKind.CASH, currencyCode = "JPY"), device, now).getOrThrow()
        val parent = repo.saveCategory(owner, CategoryDraft(name = "Parent", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
        category = repo.saveCategory(owner, CategoryDraft(name = "Child", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
    }
    @After fun close() { db.close() }
    private fun expense(id: String = targetId, amount: Long = 2000, wallet: String = cash.id) = TransactionDraft(id = id,
        primaryKind = TransactionPrimaryKind.EXPENSE, title = "Expense", amountMinor = amount, occurredAt = "2026-10-05T00:00:00Z", sourceWalletId = wallet, categoryId = category.id)
    private suspend fun rows(subject: UserId = owner) = CloudEntity.entries.associateWith { store.recordsIncludingDeleted(subject, it.table).sortedBy { row -> row.id } }
    private suspend fun queues(subject: UserId = owner) = CloudEntity.entries.associateWith { store.pendingMutations(subject, it, Long.MAX_VALUE) }
    private suspend fun replace(row: CloudRecord, fields: Map<String, JsonElement>) {
        val changed = row.copy(payload = JsonObject(row.payload + fields))
        store.commitMutation(changed, PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)), row.id, row.ownerUserId, MutationKind.UPSERT, changed.payload, now, row.syncVersion, device))
    }
    private suspend fun race(draft: TransactionDraft = expense(), action: suspend () -> Unit): Result<LedgerTransactionRecord> {
        var calls = 0; var afterRows: Map<CloudEntity,List<CloudRecord>>? = null; var afterQueues: Map<CloudEntity,List<QueuedMutation>>? = null
        val otherRows = rows(other); val otherQueues = queues(other)
        val racing = object : LocalStore by store {
            override suspend fun commitTransactionMutation(expected: TransactionSaveSnapshot, record: CloudRecord, mutation: PendingMutation) {
                if (record.entity == CloudEntity.LEDGER_TRANSACTION.table && record.id == targetId) {
                    calls++; action(); afterRows = rows(); afterQueues = queues()
                }
                store.commitTransactionMutation(expected, record, mutation)
            }
        }
        val result = OfflineFirstFinanceRepository(racing).saveTransaction(owner, draft, device, now)
        Assert.assertEquals(1, calls); Assert.assertTrue("Stale validated save must be rejected", result.isFailure)
        Assert.assertEquals(afterRows, rows()); Assert.assertEquals(afterQueues, queues())
        Assert.assertEquals(otherRows, rows(other)); Assert.assertEquals(otherQueues, queues(other))
        return result
    }
    @Test fun ownerChangeAfterWriteRollsBackRecordAndOutbox() = runTest {
        val expected = store.transactionSaveSnapshot(owner)
        val prepared = expense().toMutation(owner, null, cash, null, category, device, now)
        val before = rows(); val pending = queues(); var reached = false
        val fenced = RoomLocalStore(db, currentBillOwner = {
            if (reached || db.openHelper.readableDatabase.query("SELECT 1 FROM sync_outbox WHERE owner_user_id = ? AND entity = ? AND record_id = ?", arrayOf(owner.value, CloudEntity.LEDGER_TRANSACTION.table, targetId)).use { it.moveToFirst() }) {
                reached = true; other
            } else owner
        })
        Assert.assertTrue(runCatching { fenced.commitTransactionMutation(expected, prepared.record.toCloudRecord(), prepared.pending) }.exceptionOrNull() is CancellationException)
        Assert.assertTrue("Post-write owner fence must run", reached)
        Assert.assertEquals(before, rows()); Assert.assertEquals(pending, queues())
    }
    @Test fun createCannotCarryAnExistingCloudVersion() = runTest {
        val expected = store.transactionSaveSnapshot(owner)
        val prepared = expense().toMutation(owner, null, cash, null, category, device, now)
        val record = prepared.record.copy(syncVersion = 9007199254740993L).toCloudRecord()
        val before = rows(); val pending = queues()
        Assert.assertTrue(runCatching { store.commitTransactionMutation(expected, record, prepared.pending.copy(payload = record.payload, baseVersion = record.syncVersion)) }.isFailure)
        Assert.assertEquals(before, rows()); Assert.assertEquals(pending, queues())
    }
    @Test fun exactManualPairAndLargeVersionSurviveCreateThenEdit() = runTest {
        val funded = cash.copy(openingBalanceMinor = Long.MAX_VALUE).toCloudRecord()
        store.commitMutation(funded, PendingMutation(CloudEntity.LEDGER_WALLET, cash.id, owner.value, MutationKind.UPSERT, funded.payload, now, 0, device))
        replace(destination.toCloudRecord(), mapOf("currency_code" to JsonPrimitive("VND")))
        val draft = TransactionDraft(id = targetId, primaryKind = TransactionPrimaryKind.TRANSFER, transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            title = "Exact pair", amountMinor = 9007199254740993L, occurredAt = now, sourceWalletId = cash.id, destinationWalletId = destination.id,
            destinationAmountMinor = 18014398509481986L, conversionMode = CurrencyConversionMode.MANUAL, exchangeRateProvider = "manual")
        val created = repo.saveTransaction(owner, draft, device, now).getOrThrow()
        Assert.assertEquals(9007199254740993L, created.amountMinor); Assert.assertEquals(18014398509481986L, created.destinationAmountMinor)
        val versioned = created.copy(syncVersion = 9007199254740993L).toCloudRecord()
        store.commitMutation(versioned, PendingMutation(CloudEntity.LEDGER_TRANSACTION, targetId, owner.value, MutationKind.UPSERT, versioned.payload, now, versioned.syncVersion, device))
        val result = repo.saveTransaction(owner, draft.copy(amountMinor = 9007199254740992L), device, "2026-10-15T00:00:01Z").getOrThrow()
        Assert.assertEquals(9007199254740992L, result.amountMinor); Assert.assertEquals(18014398509481986L, result.destinationAmountMinor)
        Assert.assertEquals(9007199254740993L, result.syncVersion)
        val queue = store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).single().mutation
        Assert.assertEquals(9007199254740993L, queue.baseVersion)
        Assert.assertEquals(JsonPrimitive(9007199254740992L), queue.payload!!["amount_minor"])
        Assert.assertEquals(JsonPrimitive(18014398509481986L), queue.payload!!["destination_amount_minor"])
    }
    @Test fun otherOwnersConcurrentChangeDoesNotInvalidateOrReceiveThisSave() = runTest {
        activeOwner = other
        val foreign = repo.saveWallet(other, WalletDraft(id = cash.id, name = "Other cash", kind = WalletKind.CASH, currencyCode = "JPY"), device, now).getOrThrow()
        activeOwner = owner
        var calls = 0; var otherAfter: Map<CloudEntity,List<CloudRecord>>? = null; var queueAfter: Map<CloudEntity,List<QueuedMutation>>? = null
        val racing = object : LocalStore by store {
            override suspend fun commitTransactionMutation(expected: TransactionSaveSnapshot, record: CloudRecord, mutation: PendingMutation) {
                calls++; replace(foreign.toCloudRecord(), mapOf("name" to JsonPrimitive("Other concurrent name")))
                otherAfter = rows(other); queueAfter = queues(other)
                store.commitTransactionMutation(expected, record, mutation)
            }
        }
        val saved = OfflineFirstFinanceRepository(racing).saveTransaction(owner, expense(), device, now).getOrThrow()
        Assert.assertEquals(1, calls); Assert.assertEquals(owner.value, saved.ownerUserId); Assert.assertEquals(2000L, saved.amountMinor)
        Assert.assertEquals(otherAfter, rows(other)); Assert.assertEquals(queueAfter, queues(other))
        Assert.assertTrue(repo.observeTransactions(other).first().isEmpty())
    }

    @Test fun sourceArchivedBetweenValidationAndWriteIsHeld() = runTest {
        race { replace(cash.toCloudRecord(), mapOf("is_archived" to JsonPrimitive(true))) }
    }
    @Test fun sourceCurrencyRetagBetweenValidationAndWriteIsHeld() = runTest {
        race { replace(cash.toCloudRecord(), mapOf("currency_code" to JsonPrimitive("VND"))) }
    }
    @Test fun destinationArchivedBetweenValidationAndWriteIsHeld() = runTest {
        val transfer = TransactionDraft(id = targetId, primaryKind = TransactionPrimaryKind.TRANSFER, transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            title = "Transfer", amountMinor = 2000, occurredAt = now, sourceWalletId = cash.id, destinationWalletId = destination.id)
        race(transfer) { replace(destination.toCloudRecord(), mapOf("is_archived" to JsonPrimitive(true))) }
    }
    @Test fun categoryArchivedBetweenValidationAndWriteIsHeld() = runTest {
        race { replace(category.toCloudRecord(), mapOf("is_archived" to JsonPrimitive(true))) }
    }
    @Test fun competingSpendCannotOverdrawAnEarlierValidatedSave() = runTest {
        race { repo.saveTransaction(owner, expense(id = "44444444-4444-4444-4444-444444444444", amount = 9000), device, now).getOrThrow() }
    }
    @Test fun cardLimitReducedBetweenValidationAndWriteIsHeld() = runTest {
        val card = repo.saveCreditCard(owner, CreditCardDraft(name = "Card", creditLimitMinor = 10000), device, now).getOrThrow()
        race(expense(wallet = card.wallet.id)) { replace(card.profile.toCloudRecord(), mapOf("credit_limit_minor" to JsonPrimitive(1000))) }
    }
    @Test fun newlyPaidStatementCannotBeChangedByAnEarlierValidatedExpense() = runTest {
        val card = repo.saveCreditCard(owner, CreditCardDraft(name = "Card", creditLimitMinor = 10000, statementClosingDay = 10, paymentDueDay = 26), device, "2026-09-01T00:00:00Z").getOrThrow()
        repo.saveTransaction(owner, expense(id = "44444444-4444-4444-4444-444444444444", amount = 1000, wallet = card.wallet.id).copy(occurredAt = "2026-09-05T00:00:00Z"), device, "2026-09-20T00:00:00Z").getOrThrow()
        val requested = expense(wallet = card.wallet.id).copy(occurredAt = "2026-09-06T00:00:00Z")
        race(requested) {
            val payment = repo.saveTransaction(owner, TransactionDraft(primaryKind = TransactionPrimaryKind.TRANSFER, transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
                title = "Pay statement", amountMinor = 1000, occurredAt = now, sourceWalletId = cash.id, destinationWalletId = card.wallet.id), device, now).getOrThrow()
            val occurrence = DueOccurrenceRecord("55555555-5555-5555-5555-555555555555", owner.value, "creditCard", card.wallet.id, "2026-09", "2026-10-26T00:00:00Z",
                1000, "paid", now, payment.id, now, now, null, 0, device).toCloudRecord()
            store.commitMutation(occurrence, PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD, occurrence.id, owner.value, MutationKind.UPSERT, occurrence.payload, now, 0, device))
        }
        val refreshed = repo.saveTransaction(owner, requested, device, now)
        val fresh = refreshed.exceptionOrNull() as? TransactionValidationException
        Assert.assertEquals("Fresh result: $refreshed", TransactionValidationError.PAID_CREDIT_CARD_STATEMENT, fresh?.reason)
    }
    @Test fun concurrentTargetEditPreservesNewerRecordAndQueue() = runTest {
        val existing = repo.saveTransaction(owner, expense(amount = 1000), device, now).getOrThrow()
        race { replace(existing.toCloudRecord(), mapOf("title" to JsonPrimitive("Concurrent title"))) }
    }
    @Test fun changedOwnerBeforeWriteCannotCommitOldOwnersDraft() = runTest {
        Assert.assertTrue(race { activeOwner = other }.exceptionOrNull() is CancellationException)
    }
    @Test fun tombstonedTargetCannotBeResurrectedThroughCreateLookup() = runTest {
        val existing = repo.saveTransaction(owner, expense(), device, now).getOrThrow()
        val deleted = existing.copy(deletedAt = now).toCloudRecord()
        store.commitMutation(deleted, PendingMutation(CloudEntity.LEDGER_TRANSACTION, deleted.id, owner.value, MutationKind.DELETE, deleted.payload, now, deleted.syncVersion, device))
        val before = rows(); val pending = queues()
        Assert.assertTrue(repo.saveTransaction(owner, expense(), device, now).isFailure)
        Assert.assertEquals(before, rows()); Assert.assertEquals(pending, queues())
    }
    @Test fun orphanTargetQueueCannotBeReplacedByAnotherCreate() = runTest {
        repo.saveTransaction(owner, expense(), device, now).getOrThrow(); db.cloudRecordDao().deleteRecord(owner.value, CloudEntity.LEDGER_TRANSACTION.table, targetId)
        val before = rows(); val pending = queues()
        Assert.assertTrue(repo.saveTransaction(owner, expense(), device, now).isFailure)
        Assert.assertEquals(before, rows()); Assert.assertEquals(pending, queues())
    }
}
