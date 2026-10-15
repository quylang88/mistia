package vn.com.quyln.mistia.feature.management

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class WalletAmountInputTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    @Test fun groupedBalancePersistsExactMinorUnitsThroughWalletEditor() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        val store = RoomLocalStore(db); val repo = OfflineFirstFinanceRepository(store)
        val owner = UserId("11111111-1111-1111-1111-111111111111")
        val device = "22222222-2222-2222-2222-222222222222"
        compose.setContent { MistiaTheme(darkTheme = false) { WalletEditorSheet(owner.value, null, 0, onDismiss = {},
            onSave = { repo.saveWallet(owner, it, device, Instant.now().toString()) }, onArchive = { Result.success(Unit) }) } }
        compose.onNodeWithTag("wallet.name").performScrollTo().performTextReplacement("Cash")
        compose.onNodeWithTag("wallet.openingBalance").performScrollTo().performTextReplacement("9007199254740993")
        compose.onNodeWithTag("wallet.openingBalance").assertTextContains("9,007,199,254,740,993")
        Assert.assertTrue(runBlocking { repo.observeWallets(owner).first().isEmpty() })
        compose.onNodeWithTag("wallet.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeWallets(owner).first().size == 1 } }
        Assert.assertEquals(9007199254740993L, runBlocking { repo.observeWallets(owner).first().single().openingBalanceMinor })
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).size })
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
    }
}
