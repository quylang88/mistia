package vn.com.quyln.mistia.feature.management

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class WalletCurrencyWorkflowTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallet: LedgerWalletRecord
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        val now = Instant.now().toString()
        wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 1000), device, now).getOrThrow()
        val id = "33333333-3333-3333-3333-333333333333"
        val raw = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, id, owner.value, buildJsonObject {
            put("id", id); put("user_id", owner.value); put("source_wallet_id", wallet.id); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("amount_minor", 100); put("source_currency_code", "JPY"); put("title", "History"); put("created_at", now); put("updated_at", now); put("occurred_at", now)
            put("created_by_user_id", owner.value); put("last_modified_by_user_id", owner.value); put("deleted_at", JsonNull); put("is_archived", false)
        }, now, null, 0)
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(LedgerTransactionRecord.fromCloudRecord(raw).toCloudRecord()))
    }
    @Test fun managementDisablesCurrencyForLinkedHistoryThenUnlocksAfterHistoryRemoval() {
        compose.setContent { MistiaTheme(darkTheme = false) { ManagementScreen(owner, repo, deviceIdProvider = { device },
            onTranslatePendingCategories = {}, onSyncNow = {}, onSignOut = {}, onOpenFamily = {}, onOpenInvestment = {}, onOpenCreditCardStatements = {}) } }
        compose.waitUntil(5000) { compose.onAllNodesWithTag("management.wallet.${wallet.id}").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("management.wallet.${wallet.id}").performClick()
        compose.onNodeWithText("VND").performScrollTo().assertIsNotEnabled()
        runBlocking { store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, emptyList()) }
        compose.waitUntil(5000) { compose.onAllNodes(hasText("VND") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("VND").performClick(); compose.onNodeWithTag("wallet.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { store.record(owner, CloudEntity.LEDGER_WALLET.table, wallet.id)?.payload?.get("currency_code") == JsonPrimitive("VND") } }
        Assert.assertEquals(1000L, runBlocking { store.record(owner, CloudEntity.LEDGER_WALLET.table, wallet.id)!!.payload["opening_balance_minor"]!!.jsonPrimitive.long })
    }
    @Test fun staleEnabledEditorGetsLocalizedRejectionWithoutChangingWalletOrQueue() {
        val before = runBlocking { store.record(owner, CloudEntity.LEDGER_WALLET.table, wallet.id) }
        val queue = runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) }
        compose.setContent { MistiaTheme(darkTheme = false) {
            WalletEditorSheet(owner.value, wallet, 0, onDismiss = {}, onSave = { repo.saveWallet(owner, it, device, Instant.now().toString()) },
                onArchive = { Result.success(Unit) }, currencyEditable = true)
        } }
        compose.onNodeWithText("VND").performScrollTo().performClick(); compose.onNodeWithTag("wallet.save").performScrollTo().performClick()
        val message = ApplicationProvider.getApplicationContext<Context>().getString(R.string.management_wallet_editor_currency_in_use)
        compose.onNodeWithText(message).assertExists()
        Assert.assertEquals(before, runBlocking { store.record(owner, CloudEntity.LEDGER_WALLET.table, wallet.id) })
        Assert.assertEquals(queue, runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) })
    }
}
