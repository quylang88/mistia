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
class CreditCardCurrencyWorkflowTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var card: CreditCardAccount
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        val now = Instant.now().toString()
        card = repo.saveCreditCard(owner, CreditCardDraft(name = "Card", currencyCode = "JPY", creditLimitMinor = 1375), device, now).getOrThrow()
        val id = "33333333-3333-3333-3333-333333333333"
        val raw = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, id, owner.value, buildJsonObject {
            put("id", id); put("user_id", owner.value); put("source_wallet_id", card.wallet.id); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("amount_minor", 100); put("source_currency_code", "JPY"); put("title", "Card history"); put("created_at", now); put("updated_at", now); put("occurred_at", now)
            put("created_by_user_id", owner.value); put("last_modified_by_user_id", owner.value); put("deleted_at", JsonNull); put("is_archived", false)
        }, now, null, 0)
        store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(LedgerTransactionRecord.fromCloudRecord(raw).toCloudRecord()))
    }
    private fun records() = runBlocking { listOf(store.record(owner, CloudEntity.LEDGER_WALLET.table, card.wallet.id), store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, card.profile.id)) }
    private fun queues() = runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE) + store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE) }
    @Test fun managementLocksCardCurrencyThenUnlocksAfterHistoryIsRemoved() {
        compose.setContent { MistiaTheme(darkTheme = false) { ManagementScreen(owner, repo, deviceIdProvider = { device },
            onTranslatePendingCategories = {}, onSyncNow = {}, onSignOut = {}, onOpenFamily = {}, onOpenInvestment = {}, onOpenCreditCardStatements = {}) } }
        compose.waitUntil(5000) { compose.onAllNodesWithTag("management.editCard.${card.wallet.id}").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("management.editCard.${card.wallet.id}").performClick()
        compose.onNodeWithText("VND").performScrollTo().assertIsNotEnabled()
        runBlocking { store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, emptyList()) }
        compose.waitUntil(5000) { compose.onAllNodes(hasText("VND") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("VND").performClick(); compose.onNodeWithTag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) { records().first()?.payload?.get("currency_code") == JsonPrimitive("VND") }
        Assert.assertEquals(1375L, records()[1]!!.payload["credit_limit_minor"]!!.jsonPrimitive.long)
        Assert.assertEquals(2, queues().size)
    }
    @Test fun staleEnabledCardEditorGetsLocalizedRejectionWithoutEitherPartialWrite() {
        val before = records(); val queue = queues()
        compose.setContent { MistiaTheme(darkTheme = false) { CreditCardEditorSheet(card.wallet, card.profile, emptyList(), 0, onDismiss = {},
            onSave = { repo.saveCreditCard(owner, it, device, Instant.now().toString()) }, currencyEditable = true) } }
        compose.onNodeWithText("VND").performScrollTo().performClick(); compose.onNodeWithTag("card.save").performScrollTo().performClick()
        val message = ApplicationProvider.getApplicationContext<Context>().getString(R.string.management_wallet_editor_currency_in_use)
        compose.onNodeWithText(message).assertExists()
        Assert.assertEquals(before, records()); Assert.assertEquals(queue, queues())
    }
}
