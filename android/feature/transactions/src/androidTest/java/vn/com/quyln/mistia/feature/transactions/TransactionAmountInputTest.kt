package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionAmountInputTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallets: List<LedgerWalletRecord>
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-15T00:00:00Z"
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        wallets = listOf("JPY", "VND", "USD").map { code -> repo.saveWallet(owner, WalletDraft(name = code, kind = WalletKind.CASH, currencyCode = code, openingBalanceMinor = if (code == "JPY") 9007199254741000L else if (code == "USD") 1000000L else 0L), device, now).getOrThrow() }
    }
    private fun initial(mode: CurrencyConversionMode = CurrencyConversionMode.MANUAL) = TransactionEditorState.new(now).selectKind(TransactionPrimaryKind.TRANSFER).copy(
        sourceWalletId = wallets[0].id, destinationWalletId = wallets[1].id, conversionMode = mode, exchangeRateText = "2", exchangeRateProvider = "manual")
    private fun sourceField() = compose.onNode(hasText(context.getString(R.string.transactions_transactioneditor_amount) + " (JPY)") and hasSetTextAction())
    private fun destinationField() = compose.onNodeWithText(context.getString(R.string.transactions_transactioneditor_destination_amount) + " (VND)")
    private fun save() = compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick()
    @Test fun manualFxGroupsBothAmountsAndReopensExactSavedMinorUnits() {
        val visible = mutableStateOf(true); val record = mutableStateOf<LedgerTransactionRecord?>(null)
        compose.setContent { MistiaTheme(darkTheme = false) { if (visible.value) TransactionEditorSheet(owner.value, record.value, wallets, emptyList(), emptyList(), now,
            initialState = initial(), onDismiss = { visible.value = false }, onSave = { draft -> repo.saveTransaction(owner, draft, device, now).onSuccess { record.value = it } }) } }
        sourceField().performScrollTo().performTextReplacement("9007199254740993")
        sourceField().assertTextContains("9,007,199,254,740,993")
        destinationField().performScrollTo().performTextReplacement("18014398509481986")
        destinationField().assertTextContains("18,014,398,509,481,986")
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        save(); compose.waitUntil(5000) { !visible.value }
        val created = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(9007199254740993L, created.amountMinor); Assert.assertEquals(18014398509481986L, created.destinationAmountMinor)
        Assert.assertEquals("JPY", created.sourceCurrencyCode); Assert.assertEquals("VND", created.destinationCurrencyCode)
        compose.runOnIdle { record.value = created; visible.value = true }
        sourceField().performScrollTo().assertTextContains("9,007,199,254,740,993")
        destinationField().performScrollTo().assertTextContains("18,014,398,509,481,986")
        sourceField().performScrollTo().performTextReplacement("1000"); destinationField().performScrollTo().performTextReplacement("2000")
        save(); compose.waitUntil(5000) { !visible.value }
        val edited = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(created.id, edited.id); Assert.assertEquals(1000L, edited.amountMinor); Assert.assertEquals(2000L, edited.destinationAmountMinor)
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).size })
        Assert.assertEquals(wallets.associateBy { it.id }, runBlocking { repo.observeWallets(owner).first() }.associateBy { it.id })
    }
    @Test fun switchingGroupedJpyAmountToImportedUsdPreservesMajorUnitsAndCanSave() {
        compose.setContent { MistiaTheme(darkTheme = false) { TransactionEditorSheet(owner.value, null, wallets, emptyList(), emptyList(), now,
            initialState = initial(), onDismiss = {}, onSave = { repo.saveTransaction(owner, it, device, now) }) } }
        sourceField().performScrollTo().performTextReplacement("1000"); sourceField().assertTextContains("1,000")
        compose.onAllNodesWithText("USD · USD")[0].performScrollTo().performClick()
        val usd = compose.onNode(hasText(context.getString(R.string.transactions_transactioneditor_amount) + " (USD)") and hasSetTextAction())
        usd.performScrollTo().assertTextContains("1000")
        destinationField().performScrollTo().performTextReplacement("2000")
        compose.onNode(hasText(context.getString(R.string.settings_currency_rate_value)) and hasSetTextAction()).performScrollTo().performTextReplacement("2")
        save(); compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().size == 1 } }
        val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(100000L, saved.amountMinor); Assert.assertEquals("USD", saved.sourceCurrencyCode)
        Assert.assertEquals(2000L, saved.destinationAmountMinor)
    }
    @Test fun enteringAmountBeforeChoosingWalletGroupsWhenJpyIsSelected() {
        compose.setContent { MistiaTheme(darkTheme = false) { TransactionEditorSheet(owner.value, null, wallets, emptyList(), emptyList(), now,
            initialState = initial().copy(sourceWalletId = null), onDismiss = {}, onSave = { repo.saveTransaction(owner, it, device, now) }) } }
        compose.onNode(hasText(context.getString(R.string.transactions_transactioneditor_amount)) and hasSetTextAction()).performScrollTo().performTextReplacement("1000")
        compose.onAllNodesWithText("JPY · JPY")[0].performScrollTo().performClick()
        sourceField().performScrollTo().assertTextContains("1,000")
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
    }
    @Test fun appRateGroupsDerivedReadOnlyAmountAndPersistsExactPair() {
        val rates = listOf(ExchangeRateSnapshot("JPY", "VND", "165.5", "fixture", 1L, "2026-10-15"))
        compose.setContent { MistiaTheme(darkTheme = false) { TransactionEditorSheet(owner.value, null, wallets, emptyList(), rates, now,
            initialState = initial(CurrencyConversionMode.APP_RATE), onDismiss = {}, onSave = { repo.saveTransaction(owner, it, device, now) }) } }
        sourceField().performScrollTo().performTextReplacement("1000")
        sourceField().assertTextContains("1,000"); destinationField().performScrollTo().assertTextContains("165,500")
        save(); compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().size == 1 } }
        val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(1000L, saved.amountMinor); Assert.assertEquals(165500L, saved.destinationAmountMinor)
        Assert.assertEquals(CurrencyConversionMode.APP_RATE, saved.conversionMode); Assert.assertEquals("165.5", saved.exchangeRateDecimalString)
        Assert.assertEquals("fixture", saved.exchangeRateProvider); Assert.assertEquals("2026-10-15", saved.exchangeRateDate)
    }
}
