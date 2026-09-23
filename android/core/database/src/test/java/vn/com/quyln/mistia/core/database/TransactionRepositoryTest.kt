package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.CurrencyConversionMode
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionDraft
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionTransferSubtype
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

class TransactionRepositoryTest {
    @Test
    fun `save creates owner scoped transaction and coalesced outbox`() = runTest {
        val store = TransactionMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        seedExpenseDependencies(repository, OWNER)

        val saved = repository.saveTransaction(UserId(OWNER), expenseDraft(), DEVICE, NOW).getOrThrow()

        assertEquals(TRANSACTION_ID, saved.id)
        assertEquals(1, repository.observeTransactions(UserId(OWNER)).first().size)
        assertTrue(repository.observeTransactions(UserId(OTHER_OWNER)).first().isEmpty())
        val mutation = store.outbox.getValue(key(OWNER, CloudEntity.LEDGER_TRANSACTION, TRANSACTION_ID))
        assertEquals(0L, mutation.baseVersion)
        assertEquals(CATEGORY_ID, mutation.payload?.get("category_id")?.toString()?.trim('"'))
    }

    @Test
    fun `edit preserves base version and clears same currency fx fields`() = runTest {
        val store = TransactionMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        repository.saveWallet(UserId(OWNER), walletDraft(SOURCE_WALLET_ID, "JPY"), DEVICE, NOW).getOrThrow()
        repository.saveWallet(UserId(OWNER), walletDraft(DESTINATION_WALLET_ID, "VND"), DEVICE, NOW).getOrThrow()
        val original = repository.saveTransaction(
            UserId(OWNER),
            transferDraft(destinationAmountMinor = 1_650_000, rate = "165"),
            DEVICE,
            NOW,
        ).getOrThrow()
        store.seed(original.copy(syncVersion = 9).toCloudRecord())
        store.seed(
            repository.observeWallets(UserId(OWNER)).first()
                .first { it.id == DESTINATION_WALLET_ID }
                .copy(currencyCode = "JPY")
                .toCloudRecord()
        )

        repository.saveTransaction(
            UserId(OWNER),
            transferDraft(destinationAmountMinor = 99, rate = "99"),
            DEVICE,
            LATER,
        ).getOrThrow()

        val mutation = store.outbox.getValue(key(OWNER, CloudEntity.LEDGER_TRANSACTION, TRANSACTION_ID))
        assertEquals(9L, mutation.baseVersion)
        assertEquals(JsonNull, mutation.payload?.get("destination_amount_minor"))
        assertEquals(JsonNull, mutation.payload?.get("exchange_rate_decimal_string"))
    }

    @Test
    fun `dependency lookup cannot cross account boundary`() = runTest {
        val store = TransactionMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        seedExpenseDependencies(repository, OTHER_OWNER)

        val result = repository.saveTransaction(UserId(OWNER), expenseDraft(), DEVICE, NOW)

        assertTrue(result.isFailure)
        assertTrue(repository.observeTransactions(UserId(OWNER)).first().isEmpty())
    }

    private suspend fun seedExpenseDependencies(repository: OfflineFirstFinanceRepository, owner: String) {
        repository.saveWallet(UserId(owner), walletDraft(SOURCE_WALLET_ID, "JPY"), DEVICE, NOW).getOrThrow()
        repository.saveCategory(
            UserId(owner),
            CategoryDraft(
                id = PARENT_CATEGORY_ID,
                name = "Food",
                kind = TransactionCategoryKind.EXPENSE,
                hierarchyRole = CategoryHierarchyRole.PARENT,
            ),
            DEVICE,
            NOW,
        ).getOrThrow()
        repository.saveCategory(
            UserId(owner),
            CategoryDraft(
                id = CATEGORY_ID,
                name = "Lunch",
                kind = TransactionCategoryKind.EXPENSE,
                hierarchyRole = CategoryHierarchyRole.CHILD,
                parentCategoryId = PARENT_CATEGORY_ID,
            ),
            DEVICE,
            NOW,
        ).getOrThrow()
    }

    private fun expenseDraft() = TransactionDraft(
        id = TRANSACTION_ID,
        primaryKind = TransactionPrimaryKind.EXPENSE,
        title = "Lunch",
        amountMinor = 1_250,
        occurredAt = OCCURRED_AT,
        sourceWalletId = SOURCE_WALLET_ID,
        categoryId = CATEGORY_ID,
    )

    private fun transferDraft(destinationAmountMinor: Long, rate: String) = TransactionDraft(
        id = TRANSACTION_ID,
        primaryKind = TransactionPrimaryKind.TRANSFER,
        transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
        title = "Exchange",
        amountMinor = 10_000,
        occurredAt = OCCURRED_AT,
        sourceWalletId = SOURCE_WALLET_ID,
        destinationWalletId = DESTINATION_WALLET_ID,
        destinationAmountMinor = destinationAmountMinor,
        conversionMode = CurrencyConversionMode.MANUAL,
        exchangeRateDecimalString = rate,
    )

    private fun walletDraft(id: String, currency: String) = WalletDraft(
        id = id,
        name = "Wallet",
        kind = WalletKind.BANK,
        currencyCode = currency,
        institutionDisplayName = "Bank",
    )

    private class TransactionMemoryStore : LocalStore {
        private val records = MutableStateFlow<Map<Triple<String, String, String>, CloudRecord>>(emptyMap())
        val outbox = linkedMapOf<Triple<String, String, String>, PendingMutation>()

        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> = records.map { rows ->
            rows.values.filter { it.ownerUserId == ownerUserId.value && it.entity == entity && it.deletedAt == null }
        }
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> = MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) =
            records.value[Triple(ownerUserId.value, entity, recordId)]
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
            seed(record)
            outbox[key(mutation.subjectUserId, mutation.entity, mutation.recordId)] = mutation
        }
        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ): List<QueuedMutation> = emptyList()
        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord) = false
        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ) = false
        override suspend fun replacePullSnapshot(
            ownerUserId: UserId,
            entity: String,
            records: List<CloudRecord>,
        ) = Unit
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = emptySet<String>()
        override suspend fun clearAccount(ownerUserId: UserId) = Unit

        fun seed(record: CloudRecord) {
            records.value = records.value + (Triple(record.ownerUserId, record.entity, record.id) to record)
        }
    }

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val OTHER_OWNER = "77777777-7777-7777-7777-777777777777"
        const val TRANSACTION_ID = "22222222-2222-2222-2222-222222222222"
        const val SOURCE_WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val DESTINATION_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val CATEGORY_ID = "55555555-5555-5555-5555-555555555555"
        const val PARENT_CATEGORY_ID = "88888888-8888-8888-8888-888888888888"
        const val DEVICE = "66666666-6666-6666-6666-666666666666"
        const val OCCURRED_AT = "2026-09-23T09:30:00.000Z"
        const val NOW = "2026-09-23T12:00:00.000Z"
        const val LATER = "2026-09-23T13:00:00.000Z"

        fun key(owner: String, entity: CloudEntity, id: String) = Triple(owner, entity.table, id)
    }
}
