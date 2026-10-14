package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Actual DAO + repository fixtures; compile-only without a connected Android device. */
@RunWith(AndroidJUnit4::class)
class FinanceReadScopeRoomTest {
    private lateinit var database: MistiaDatabase
    private lateinit var repository: OfflineFirstFinanceRepository
    private val owner = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val other = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private val id = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    private val alias = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    private val now = "2026-10-14T00:00:00Z"
    @Before fun setup() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java)
            .allowMainThreadQueries().build()
        repository = OfflineFirstFinanceRepository(RoomLocalStore(database))
    }
    @After fun close() { database.close() }
    private fun entity(record: CloudRecord) = CloudRecordEntity(record.ownerUserId, record.entity, record.id, record.payload.toString(),
        record.updatedAt, record.deletedAt, record.syncVersion, receivedAtEpochMillis = 0)
    @Test fun rowPartitionAndPayloadOwnerBothConstrainReadAndCountWithoutRepairingStorage() = runTest {
        val valid = WalletDraft(id = id, name = "Owned", kind = WalletKind.CASH, currencyCode = "JPY").toMutation(owner, null, id, now).record
        val forged = valid.copy(id = alias, payload = JsonObject(valid.payload + mapOf("id" to JsonPrimitive(alias), "user_id" to JsonPrimitive(other))))
        val foreign = WalletDraft(id = id, name = "Other", kind = WalletKind.CASH, currencyCode = "JPY").toMutation(UserId(other), null, id, now).record
        database.cloudRecordDao().upsert(listOf(valid, forged, foreign).map(::entity))
        assertEquals(listOf("Owned"), repository.observeWallets(owner).first().map { it.name })
        assertEquals(listOf("Other"), repository.observeWallets(UserId(other)).first().map { it.name })
        assertEquals(listOf(EntityCount(CloudEntity.LEDGER_WALLET.table, 1)), repository.observeEntityCounts(owner).first())
        assertEquals(2, database.cloudRecordDao().recordsIncludingDeleted(owner.value, CloudEntity.LEDGER_WALLET.table).size)
        assertTrue(database.syncOutboxDao().rows(owner.value).isEmpty())
    }
    @Test fun historicalMetadataRetainsOwnedDeletedCategoryAndIgnoresAliasedId() = runTest {
        val valid = CategoryDraft(id = id, name = "Historical", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.PARENT)
            .toMutation(owner, null, null, id, now).record.copy(isArchived = true, deletedAt = now).toCloudRecord()
        val forged = valid.copy(id = alias)
        database.cloudRecordDao().upsert(listOf(valid, forged).map(::entity))
        val metadata = repository.observeBudgetCategoryMetadata(owner).first()
        assertEquals(listOf(id), metadata.map { it.id }); assertEquals(now, metadata.single().deletedAt)
        assertTrue(repository.observeCategories(owner).first().isEmpty())
        assertEquals(2, database.cloudRecordDao().recordsIncludingDeleted(owner.value, CloudEntity.TRANSACTION_CATEGORY.table).size)
    }
}
