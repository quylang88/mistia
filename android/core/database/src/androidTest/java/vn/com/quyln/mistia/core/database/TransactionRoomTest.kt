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
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionDraft
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

@RunWith(AndroidJUnit4::class)
class TransactionRoomTest {
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
    fun transactionAndOutboxCommitForOneOwner() = runTest {
        repository.saveWallet(
            UserId(OWNER_A),
            WalletDraft(
                id = WALLET_ID,
                name = "Cash",
                kind = WalletKind.CASH,
                currencyCode = "JPY",
            ),
            DEVICE,
            NOW,
        ).getOrThrow()
        repository.saveCategory(
            UserId(OWNER_A),
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
            UserId(OWNER_A),
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

        repository.saveTransaction(
            UserId(OWNER_A),
            TransactionDraft(
                id = TRANSACTION_ID,
                primaryKind = TransactionPrimaryKind.EXPENSE,
                title = "Lunch",
                amountMinor = 1_250,
                occurredAt = NOW,
                sourceWalletId = WALLET_ID,
                categoryId = CATEGORY_ID,
            ),
            DEVICE,
            NOW,
        ).getOrThrow()

        assertEquals(1, repository.observeTransactions(UserId(OWNER_A)).first().size)
        assertTrue(repository.observeTransactions(UserId(OWNER_B)).first().isEmpty())
        assertEquals(
            TRANSACTION_ID,
            localStore.pendingMutations(UserId(OWNER_A), CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE)
                .single().mutation.recordId,
        )
    }

    private companion object {
        const val OWNER_A = "11111111-1111-1111-1111-111111111111"
        const val OWNER_B = "77777777-7777-7777-7777-777777777777"
        const val TRANSACTION_ID = "22222222-2222-2222-2222-222222222222"
        const val WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val CATEGORY_ID = "55555555-5555-5555-5555-555555555555"
        const val PARENT_CATEGORY_ID = "88888888-8888-8888-8888-888888888888"
        const val DEVICE = "66666666-6666-6666-6666-666666666666"
        const val NOW = "2026-09-23T12:00:00.000Z"
    }
}
