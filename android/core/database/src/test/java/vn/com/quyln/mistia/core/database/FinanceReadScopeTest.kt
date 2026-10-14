package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import vn.com.quyln.mistia.core.model.*

/** Deliberately inconsistent cached envelopes; no network/authenticated account fixture. */
internal class FinanceReadStore : LocalStore by BudgetMemoryStore() {
    val rows = MutableStateFlow<Map<CloudEntity, List<CloudRecord>>>(emptyMap())
    override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> = rows.map {
        it[CloudEntity.fromTable(entity)].orEmpty()
    }
    override suspend fun recordsIncludingDeleted(ownerUserId: UserId, entity: String): List<CloudRecord> =
        rows.value[CloudEntity.fromTable(entity)].orEmpty()
    override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> = rows.map { data ->
        data.map { (entity, values) -> EntityCount(entity.table, values.count { it.deletedAt == null && it.ownerUserId == ownerUserId.value }) }
    }
}
private val scopeOwner = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
private const val scopeOther = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
private const val scopeDevice = "cccccccc-cccc-cccc-cccc-cccccccccccc"
private const val scopeNow = "2026-10-14T00:00:00Z"
private fun identityRecord(entity: CloudEntity): CloudRecord = CloudRecord(entity.table, scopeDevice, scopeOwner.value, buildJsonObject {
    put("id", scopeDevice); put("user_id", scopeOwner.value); put("created_at", scopeNow); put("updated_at", scopeNow); put("deleted_at", JsonNull)
}, scopeNow, null, 0)
private fun inconsistent(record: CloudRecord): List<CloudRecord> = listOf(
    record.copy(ownerUserId = scopeOther),
    record.copy(entity = "foreign_table"),
    record.copy(payload = JsonObject(record.payload + ("user_id" to JsonPrimitive(scopeOther)))),
    record.copy(payload = JsonObject(record.payload - "user_id")),
    record.copy(payload = JsonObject(record.payload + ("id" to JsonPrimitive(scopeOther)))),
    record.copy(payload = JsonObject(record.payload - "id")),
    record.copy(payload = JsonObject(record.payload + ("user_id" to JsonNull))),
    record.copy(payload = JsonObject(record.payload + ("id" to JsonNull))),
    record.copy(payload = JsonObject(record.payload + ("id" to JsonPrimitive(123)))),
    record.copy(payload = JsonObject(record.payload + ("id" to JsonPrimitive("c-c-c-c-c")))),
    record.copy(deletedAt = scopeNow),
    record.copy(payload = JsonObject(record.payload + ("deleted_at" to JsonPrimitive(scopeNow)))),
)

@RunWith(Parameterized::class)
class FinanceRawReadScopeTest(private val entity: CloudEntity) {
    companion object { @JvmStatic @Parameterized.Parameters(name = "{0}") fun cases() = CloudEntity.entries.map { arrayOf(it) } }
    @Test fun `raw financial collection rejects mismatched owner identity entity and tombstones`() = runTest {
        val store = FinanceReadStore(); val valid = identityRecord(entity)
        store.rows.value = mapOf(entity to (inconsistent(valid) + valid))
        assertEquals(listOf(valid), OfflineFirstFinanceRepository(store).observe(entity, scopeOwner).first())
    }
}

@RunWith(Parameterized::class)
class FinanceTypedReadScopeTest(private val entity: CloudEntity) {
    companion object { @JvmStatic @Parameterized.Parameters(name = "{0}") fun cases() = listOf(
        CloudEntity.LEDGER_WALLET, CloudEntity.TRANSACTION_CATEGORY, CloudEntity.CREDIT_CARD_PROFILE, CloudEntity.LEDGER_TRANSACTION).map { arrayOf(it) } }
    private fun valid(): CloudRecord {
        val card = CreditCardDraft(name = "Card", creditLimitMinor = 10000).toMutation(scopeOwner, null, null, null, scopeDevice, scopeNow)
        return when (entity) {
            CloudEntity.LEDGER_WALLET -> card.wallet.record.toCloudRecord()
            CloudEntity.CREDIT_CARD_PROFILE -> card.profile.record.toCloudRecord()
            CloudEntity.TRANSACTION_CATEGORY -> CategoryDraft(name = "Category", kind = TransactionCategoryKind.EXPENSE,
                hierarchyRole = CategoryHierarchyRole.PARENT).toMutation(scopeOwner, null, null, scopeDevice, scopeNow).record.toCloudRecord()
            else -> TransactionDraft(primaryKind = TransactionPrimaryKind.TRANSFER, transferSubtype = TransactionTransferSubtype.DEBT,
                debtIntent = TransactionDebtIntent.LEND, title = "Loan", amountMinor = 5000, occurredAt = scopeNow,
                sourceWalletId = card.wallet.record.id, counterpartyName = "A")
                .toMutation(scopeOwner, null, card.wallet.record, null, null, scopeDevice, scopeNow).record.toCloudRecord()
        }
    }
    @Test fun `typed financial collection cannot accept a validly decoded foreign or aliased payload`() = runTest {
        val store = FinanceReadStore(); val valid = valid(); val repository = OfflineFirstFinanceRepository(store)
        store.rows.value = mapOf(entity to (inconsistent(valid) + valid))
        val ids = when (entity) {
            CloudEntity.LEDGER_WALLET -> repository.observeWallets(scopeOwner).first().map { it.id }
            CloudEntity.CREDIT_CARD_PROFILE -> repository.observeCreditCardProfiles(scopeOwner).first().map { it.id }
            CloudEntity.TRANSACTION_CATEGORY -> repository.observeCategories(scopeOwner).first().map { it.id }
            else -> repository.observeTransactions(scopeOwner).first().map { it.id }
        }
        assertEquals(listOf(valid.id), ids)
    }
}

class FinanceReadCountAndMetadataTest {
    @Test fun `financial counts use the same validated live records as raw reads`() = runTest {
        val store = FinanceReadStore()
        store.rows.value = CloudEntity.entries.associateWith { entity -> val valid = identityRecord(entity); inconsistent(valid) + valid }
        val counts = OfflineFirstFinanceRepository(store).observeEntityCounts(scopeOwner).first()
        assertEquals(CloudEntity.entries.size, counts.size)
        assertTrue(counts.all { it.count == 1 })
    }
    @Test fun `historical category metadata preserves owned tombstones but rejects identity aliases`() = runTest {
        val store = FinanceReadStore()
        val category = CategoryDraft(name = "Old category", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.PARENT)
            .toMutation(scopeOwner, null, null, scopeDevice, scopeNow).record.copy(isArchived = true, deletedAt = scopeNow).toCloudRecord()
        store.rows.value = mapOf(CloudEntity.TRANSACTION_CATEGORY to listOf(category,
            category.copy(payload = JsonObject(category.payload + ("id" to JsonPrimitive(scopeOther))))))
        val rows = OfflineFirstFinanceRepository(store).observeBudgetCategoryMetadata(scopeOwner).first()
        assertEquals(listOf(category.id), rows.map { it.id }); assertEquals(scopeNow, rows.single().deletedAt)
    }
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test fun `counts react to owner payload changes even when storage row count is unchanged`() = runTest {
        val store = FinanceReadStore(); val entity = CloudEntity.LEDGER_WALLET; val valid = identityRecord(entity)
        store.rows.value = mapOf(entity to listOf(valid))
        val seen = mutableListOf<List<EntityCount>>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            OfflineFirstFinanceRepository(store).observeEntityCounts(scopeOwner).collect { seen += it }
        }
        runCurrent(); assertEquals(listOf(EntityCount(entity.table, 1)), seen.last())
        store.rows.value = mapOf(entity to listOf(valid.copy(payload = JsonObject(valid.payload + ("user_id" to JsonPrimitive(scopeOther))))))
        runCurrent(); assertTrue(seen.last().isEmpty())
        store.rows.value = mapOf(entity to listOf(valid))
        runCurrent(); assertEquals(listOf(EntityCount(entity.table, 1)), seen.last())
    }
    @Test fun `UUID case differences remain readable without changing stored records`() = runTest {
        val store = FinanceReadStore(); val valid = identityRecord(CloudEntity.LEDGER_WALLET)
        val upper = valid.copy(payload = JsonObject(valid.payload + mapOf("id" to JsonPrimitive(valid.id.uppercase()), "user_id" to JsonPrimitive(scopeOwner.value.uppercase()))))
        store.rows.value = mapOf(CloudEntity.LEDGER_WALLET to listOf(upper))
        assertEquals(listOf(upper), OfflineFirstFinanceRepository(store).observe(CloudEntity.LEDGER_WALLET, scopeOwner).first())
        assertEquals(upper, store.rows.value.getValue(CloudEntity.LEDGER_WALLET).single())
    }
}
