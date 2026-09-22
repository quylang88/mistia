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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

@RunWith(AndroidJUnit4::class)
class WalletRoomTest {
    private lateinit var database: MistiaDatabase
    private lateinit var repository: OfflineFirstFinanceRepository

    @Before
    fun createDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = OfflineFirstFinanceRepository(RoomLocalStore(database))
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
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
        const val LAST = "2026-09-22T12:00:00.000Z"
    }
}
