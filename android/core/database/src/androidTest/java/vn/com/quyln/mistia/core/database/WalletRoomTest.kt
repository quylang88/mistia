package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.IOException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.LocalStore

@RunWith(AndroidJUnit4::class)
class WalletRoomTest {
    private lateinit var database: MistiaDatabase
    private lateinit var repository: OfflineFirstFinanceRepository
    private lateinit var localStore: LocalStore

    @Before
    fun createDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        localStore = RoomLocalStore(database)
        repository = OfflineFirstFinanceRepository(localStore)
    }

    @After
    @Throws(IOException::class)
    fun closeDatabase() {
        database.close()
    }

    @Test
    fun recordAndOutboxArePersistedForOnlyTheMutationOwner() = runTest {
        repository.saveWallet(UserId(OWNER_A), cashDraft(), DEVICE, NOW).getOrThrow()

        assertEquals(
            listOf("Device cash"),
            repository.observeWallets(UserId(OWNER_A)).first().map { it.name },
        )
        assertTrue(repository.observeWallets(UserId(OWNER_B)).first().isEmpty())
        assertEquals(listOf(WALLET_ID), database.syncOutboxDao().recordIds(OWNER_A, "ledger_wallets"))
        assertTrue(database.syncOutboxDao().recordIds(OWNER_B, "ledger_wallets").isEmpty())
    }

    @Test
    fun editThenArchiveCoalescesOneUpsertAndHidesWallet() = runTest {
        val saved = repository.saveWallet(UserId(OWNER_A), cashDraft(), DEVICE, NOW).getOrThrow()
        repository.saveWallet(
            UserId(OWNER_A),
            cashDraft().copy(name = "Renamed"),
            DEVICE,
            LATER,
        ).getOrThrow()
        repository.archiveWallet(UserId(OWNER_A), RecordId(saved.id), DEVICE, LAST).getOrThrow()

        assertTrue(repository.observeWallets(UserId(OWNER_A)).first().isEmpty())
        val rows = database.syncOutboxDao().rows(OWNER_A)
        assertEquals(1, rows.size)
        assertEquals("upsert", rows.single().kind)
    }

    @Test
    fun dueWalletMutationsAreOwnerScopedAndOrderedOldestFirst() = runTest {
        repository.saveWallet(UserId(OWNER_A), cashDraft().copy(id = WALLET_ID_2, name = "Later"), DEVICE, LATER)
            .getOrThrow()
        repository.saveWallet(UserId(OWNER_A), cashDraft().copy(name = "Earlier"), DEVICE, NOW)
            .getOrThrow()
        repository.saveWallet(UserId(OWNER_B), cashDraft().copy(name = "Other owner"), DEVICE, NOW)
            .getOrThrow()

        val due = localStore.pendingMutations(
            UserId(OWNER_A),
            CloudEntity.LEDGER_WALLET,
            dueAtEpochMillis = 0,
        )

        assertEquals(listOf(WALLET_ID, WALLET_ID_2), due.map { it.mutation.recordId })
    }

    @Test
    fun exactAcknowledgementInstallsRemoteRowAndClearsPendingMutation() = runTest {
        repository.saveWallet(UserId(OWNER_A), cashDraft(), DEVICE, NOW).getOrThrow()
        val queued = localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, 0).single()
        val remote = LedgerWalletRecord.fromCloudRecord(queued.mutation.payloadRecord()).copy(
            syncVersion = 1,
        ).toCloudRecord().withSyncVersion(1)

        assertTrue(localStore.acknowledgeMutation(queued, remote))

        assertTrue(localStore.pendingMutationRecordIds(UserId(OWNER_A), CloudEntity.LEDGER_WALLET.table).isEmpty())
        assertEquals(1L, localStore.record(UserId(OWNER_A), CloudEntity.LEDGER_WALLET.table, WALLET_ID)?.syncVersion)
    }

    @Test
    fun staleAcknowledgementCannotEraseConcurrentEdit() = runTest {
        repository.saveWallet(UserId(OWNER_A), cashDraft(), DEVICE, NOW).getOrThrow()
        val sent = localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, 0).single()
        repository.saveWallet(UserId(OWNER_A), cashDraft().copy(name = "Edited while sending"), DEVICE, LATER)
            .getOrThrow()
        val remote = LedgerWalletRecord.fromCloudRecord(sent.mutation.payloadRecord()).copy(syncVersion = 1)
            .toCloudRecord().withSyncVersion(1)

        assertFalse(localStore.acknowledgeMutation(sent, remote))

        assertEquals("Edited while sending", repository.observeWallets(UserId(OWNER_A)).first().single().name)
        assertEquals(1, localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, 0).size)
    }

    @Test
    fun failureMetadataUpdatesOnlyTheExactQueuedMutation() = runTest {
        repository.saveWallet(UserId(OWNER_A), cashDraft(), DEVICE, NOW).getOrThrow()
        val queued = localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, 0).single()

        assertTrue(localStore.recordMutationFailure(queued, 30_000, "http_503"))
        assertTrue(localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, 29_999).isEmpty())
        val retry = localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, 30_000).single()
        assertEquals(1, retry.attemptCount)
        assertEquals("http_503", retry.lastError)
    }

    private fun vn.com.quyln.mistia.core.model.PendingMutation.payloadRecord() =
        vn.com.quyln.mistia.core.model.CloudRecord(
            entity = entity.table,
            id = recordId,
            ownerUserId = subjectUserId,
            payload = requireNotNull(payload),
            updatedAt = modifiedAt,
            deletedAt = null,
            syncVersion = baseVersion,
        )

    private fun vn.com.quyln.mistia.core.model.CloudRecord.withSyncVersion(version: Long) = copy(
        payload = kotlinx.serialization.json.JsonObject(
            payload + ("sync_version" to kotlinx.serialization.json.JsonPrimitive(version))
        ),
        syncVersion = version,
    )

    private fun cashDraft() = WalletDraft(
        id = WALLET_ID,
        name = "Device cash",
        kind = WalletKind.CASH,
        currencyCode = "JPY",
        openingBalanceMinor = 5_000,
    )

    private companion object {
        const val OWNER_A = "11111111-1111-1111-1111-111111111111"
        const val OWNER_B = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val WALLET_ID_2 = "55555555-5555-5555-5555-555555555555"
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
        const val LAST = "2026-09-22T12:00:00.000Z"
    }
}
