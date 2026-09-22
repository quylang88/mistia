package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

class WalletRepositoryTest {
    @Test
    fun `save writes owner scoped record and outbox together`() = runTest {
        val store = InMemoryLocalStore()
        val repository = OfflineFirstFinanceRepository(store)

        repository.saveWallet(UserId(OWNER_A), cashDraft("Tokyo cash"), DEVICE, NOW).getOrThrow()

        assertEquals(
            listOf("Tokyo cash"),
            repository.observeWallets(UserId(OWNER_A)).first().map(LedgerWalletRecord::name),
        )
        assertTrue(repository.observeWallets(UserId(OWNER_B)).first().isEmpty())
        assertEquals(listOf(WALLET_ID), store.outboxRows(OWNER_A).map(PendingMutation::recordId))
        assertTrue(store.outboxRows(OWNER_B).isEmpty())
    }

    @Test
    fun `editing coalesces one outbox row and keeps remote base version`() = runTest {
        val store = InMemoryLocalStore()
        val repository = OfflineFirstFinanceRepository(store)
        store.replacePullSnapshot(
            UserId(OWNER_A),
            CloudEntity.LEDGER_WALLET.table,
            listOf(remoteWallet(syncVersion = 4)),
        )

        repository.saveWallet(UserId(OWNER_A), cashDraft("Renamed"), DEVICE, NOW).getOrThrow()
        repository.saveWallet(UserId(OWNER_A), cashDraft("Final"), DEVICE, LATER).getOrThrow()

        val outbox = store.outboxRows(OWNER_A)
        assertEquals(1, outbox.size)
        assertEquals(4, outbox.single().baseVersion)
        assertEquals("Final", repository.observeWallets(UserId(OWNER_A)).first().single().name)
    }

    @Test
    fun `archive is an upsert and disappears from active wallet flow`() = runTest {
        val store = InMemoryLocalStore()
        val repository = OfflineFirstFinanceRepository(store)
        val saved = repository.saveWallet(UserId(OWNER_A), cashDraft("Cash"), DEVICE, NOW).getOrThrow()

        repository.archiveWallet(UserId(OWNER_A), RecordId(saved.id), DEVICE, LATER).getOrThrow()

        assertTrue(repository.observeWallets(UserId(OWNER_A)).first().isEmpty())
        assertEquals("UPSERT", store.outboxRows(OWNER_A).single().kind.name)
    }

    private fun cashDraft(name: String) = WalletDraft(
        id = WALLET_ID,
        name = name,
        kind = WalletKind.CASH,
        currencyCode = "JPY",
        openingBalanceMinor = 10_000,
    )

    private fun remoteWallet(syncVersion: Long): CloudRecord {
        val local = cashDraft("Remote")
            .toMutation(UserId(OWNER_A), null, DEVICE, CREATED_AT)
            .record
        return local.copy(
            payload = JsonObject(local.payload + ("sync_version" to JsonPrimitive(syncVersion))),
            syncVersion = syncVersion,
        )
    }

    private class InMemoryLocalStore : LocalStore {
        private val records = MutableStateFlow<Map<Triple<String, String, String>, CloudRecord>>(emptyMap())
        private val outbox = linkedMapOf<Triple<String, String, String>, PendingMutation>()

        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            records.map { values ->
                values.values.filter {
                    it.ownerUserId == ownerUserId.value && it.entity == entity && it.deletedAt == null
                }
            }

        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            records.map { values ->
                values.values
                    .filter { it.ownerUserId == ownerUserId.value && it.deletedAt == null }
                    .groupingBy(CloudRecord::entity)
                    .eachCount()
                    .map { EntityCount(it.key, it.value) }
            }

        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord? =
            records.value[Triple(ownerUserId.value, entity, recordId)]

        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
            val key = Triple(record.ownerUserId, record.entity, record.id)
            require(key == Triple(mutation.subjectUserId, mutation.entity.table, mutation.recordId))
            records.value = records.value + (key to record)
            outbox[key] = mutation
        }

        override suspend fun replacePullSnapshot(
            ownerUserId: UserId,
            entity: String,
            records: List<CloudRecord>,
        ) {
            val retained = this.records.value.filterKeys { key ->
                key.first != ownerUserId.value || key.second != entity || outbox.containsKey(key)
            }
            this.records.value = retained + records.associateBy {
                Triple(ownerUserId.value, entity, it.id)
            }
        }

        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String): Set<String> =
            outbox.keys.filter { it.first == ownerUserId.value && it.second == entity }.mapTo(mutableSetOf()) { it.third }

        override suspend fun clearAccount(ownerUserId: UserId) {
            records.value = records.value.filterKeys { it.first != ownerUserId.value }
            outbox.keys.removeAll { it.first == ownerUserId.value }
        }

        fun outboxRows(ownerUserId: String): List<PendingMutation> =
            outbox.filterKeys { it.first == ownerUserId }.values.toList()
    }

    private companion object {
        const val OWNER_A = "11111111-1111-1111-1111-111111111111"
        const val OWNER_B = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val CREATED_AT = "2026-01-01T00:00:00.000Z"
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
    }
}
