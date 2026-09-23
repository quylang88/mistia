package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CreditCardDraft
import vn.com.quyln.mistia.core.model.CreditCardNetwork
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

@RunWith(AndroidJUnit4::class)
class CreditCardRoomTest {
    private lateinit var database: MistiaDatabase
    private lateinit var localStore: LocalStore
    private lateinit var repository: OfflineFirstFinanceRepository

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
    fun closeDatabase() = database.close()

    @Test
    fun walletProfileAndBothOutboxRowsCommitAtomicallyForOneOwner() = runTest {
        repository.saveWallet(
            UserId(OWNER_A),
            WalletDraft(
                id = PAYMENT_WALLET_ID,
                name = "Bank",
                kind = WalletKind.BANK,
                currencyCode = "JPY",
                institutionDisplayName = "Bank",
            ),
            DEVICE,
            NOW,
        ).getOrThrow()

        repository.saveCreditCard(
            UserId(OWNER_A),
            CreditCardDraft(
                walletId = CARD_WALLET_ID,
                profileId = PROFILE_ID,
                name = "Card",
                network = CreditCardNetwork.VISA,
                last4 = "1234",
                creditLimitMinor = 350_000,
                paymentSourceWalletId = PAYMENT_WALLET_ID,
            ),
            DEVICE,
            NOW,
        ).getOrThrow()

        assertEquals(2, repository.observeWallets(UserId(OWNER_A)).first().size)
        assertEquals(1, repository.observeCreditCardProfiles(UserId(OWNER_A)).first().size)
        assertTrue(repository.observeCreditCardProfiles(UserId(OWNER_B)).first().isEmpty())
        assertEquals(
            CARD_WALLET_ID,
            localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_WALLET, Long.MAX_VALUE)
                .single { it.mutation.recordId == CARD_WALLET_ID }.mutation.recordId,
        )
        assertEquals(
            PROFILE_ID,
            localStore.pendingMutations(UserId(OWNER_A), CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE)
                .single().mutation.recordId,
        )
    }

    private companion object {
        const val OWNER_A = "11111111-1111-1111-1111-111111111111"
        const val OWNER_B = "66666666-6666-6666-6666-666666666666"
        const val CARD_WALLET_ID = "22222222-2222-2222-2222-222222222222"
        const val PROFILE_ID = "33333333-3333-3333-3333-333333333333"
        const val PAYMENT_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val DEVICE = "55555555-5555-5555-5555-555555555555"
        const val NOW = "2026-09-23T10:00:00.000Z"
    }
}
