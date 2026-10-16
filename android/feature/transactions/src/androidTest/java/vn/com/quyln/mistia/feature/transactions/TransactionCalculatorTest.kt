package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.JsonPrimitive
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionCalculatorTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallets: List<LedgerWalletRecord>
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-15T00:00:00Z"
    private val rates = listOf(ExchangeRateSnapshot("JPY", "VND", "165.5", "fixture", 1L, "2026-10-15"))
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        wallets = listOf(owner, other).flatMap { subject -> listOf("JPY", "VND", "USD").map { code ->
            repo.saveWallet(subject, WalletDraft(name = code, kind = WalletKind.CASH, currencyCode = code,
                openingBalanceMinor = if (code == "JPY") 9007199254741000L else 0L), device, now).getOrThrow()
        } }
    }
    private fun initial(subject: UserId = owner, mode: CurrencyConversionMode = CurrencyConversionMode.MANUAL) = TransactionEditorState.new(now)
        .selectKind(TransactionPrimaryKind.TRANSFER).copy(sourceWalletId = wallets.first { it.ownerUserId == subject.value && it.currencyCode == "JPY" }.id,
            destinationWalletId = wallets.first { it.ownerUserId == subject.value && it.currencyCode == "VND" }.id, conversionMode = mode)
    @Composable private fun Editor(subject: UserId = owner, seed: TransactionEditorState = initial(subject), candidates: List<LedgerWalletRecord> = wallets) {
        MistiaTheme(darkTheme = false) { TransactionEditorSheet(subject.value, null, candidates, emptyList(), rates, now,
            initialState = seed, onDismiss = {}, onSave = { repo.saveTransaction(subject, it, device, now) }) }
    }
    private fun field(destination: Boolean = false) = compose.onNodeWithTag(if (destination) "transaction.destinationAmount" else "transaction.amount")
    private fun open(destination: Boolean = false) = compose.onNodeWithTag(if (destination) "transaction.destinationAmount.calculator" else "transaction.amount.calculator").performScrollTo().performClick()
    private fun key(value: String) = compose.onNodeWithTag("amountCalculator.key.$value").performClick()
    private fun noTransactions() {
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).isEmpty() })
    }
    @Test fun bothCalculatorsKeepExactIndependentDraftAmountsUntilSave() {
        compose.setContent { Editor(seed = initial().copy(amountText = "9,007,199,254,740,992", destinationAmountText = "18,014,398,509,481,985")) }
        open(); key("+"); key("1"); key("OK")
        field().performScrollTo().assertTextContains("9,007,199,254,740,993")
        field(true).performScrollTo().assertTextContains("18,014,398,509,481,985")
        open(true); key("+"); key("1"); key("OK")
        field(true).performScrollTo().assertTextContains("18,014,398,509,481,986"); noTransactions()
        compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().size == 1 } }
        val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(9007199254740993L, saved.amountMinor); Assert.assertEquals(18014398509481986L, saved.destinationAmountMinor)
        val payload = runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).single().mutation.payload!! }
        Assert.assertEquals(JsonPrimitive(9007199254740993L), payload["amount_minor"]); Assert.assertEquals(JsonPrimitive(18014398509481986L), payload["destination_amount_minor"])
        Assert.assertEquals(wallets.filter { it.ownerUserId == owner.value }.associateBy { it.id }, runBlocking { repo.observeWallets(owner).first() }.associateBy { it.id })
    }
    @Test fun sourceCalculatorRecomputesAppRateWithoutEditingDerivedDestination() {
        compose.setContent { Editor(seed = initial(mode = CurrencyConversionMode.APP_RATE).copy(amountText = "1,000")) }
        compose.onNodeWithTag("transaction.destinationAmount.calculator").assertDoesNotExist()
        open(); key("+"); key("1"); key("OK")
        field().performScrollTo().assertTextContains("1,001"); field(true).assertDoesNotExist(); noTransactions()
        compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().size == 1 } }
        val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(1001L, saved.amountMinor); Assert.assertEquals(165666L, saved.destinationAmountMinor)
        Assert.assertEquals("165.5", saved.exchangeRateDecimalString); Assert.assertEquals("fixture", saved.exchangeRateProvider); Assert.assertEquals("2026-10-15", saved.exchangeRateDate)
    }
    @Test fun invalidCalculationAndCancelPreserveBlankAndSignedDrafts() {
        compose.setContent { Editor(seed = initial().copy(destinationAmountText = "-7")) }
        open(); key("OK"); compose.onNodeWithTag("amountCalculator.error").assertExists()
        compose.onNodeWithTag("amountCalculator.dismissError").performClick(); compose.onNodeWithTag("amountCalculator.cancel").performClick()
        field().performScrollTo().assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
        open(true); key("C"); key("9"); key("÷"); key("0"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists(); compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick(); field(true).performScrollTo().assertTextContains("-7"); noTransactions()
    }
    @Test fun destinationExpressionRestoresButCurrencyChangeClosesIt() {
        var candidates by mutableStateOf(wallets); val restore = StateRestorationTester(compose)
        restore.setContent { Editor(seed = initial().copy(amountText = "123", destinationAmountText = "1,000"), candidates = candidates) }
        open(true); key("+"); key("2")
        restore.emulateSavedInstanceStateRestore(); compose.onNodeWithTag("amountCalculator.expression").assertTextContains("1000 + 2")
        key("OK"); field(true).performScrollTo().assertTextContains("1,002"); field().performScrollTo().assertTextContains("123")
        open(); key("+"); key("9")
        compose.runOnIdle { candidates = candidates.map { if (it.id == initial().sourceWalletId) it.copy(currencyCode = "USD") else it } }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist()
        compose.onNodeWithTag("transaction.amount.calculator").assertDoesNotExist(); noTransactions()
    }
    @Test fun ownerChangeDropsPrivateExpression() {
        var subject by mutableStateOf(owner)
        compose.setContent { Editor(subject, initial(subject).copy(amountText = if (subject == owner) "123" else "456")) }
        open(); key("+"); key("9"); compose.runOnIdle { subject = other }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist()
        open(); compose.onNodeWithTag("amountCalculator.expression").assertTextContains("456"); compose.onNodeWithTag("amountCalculator.expression").assertTextEquals("456")
        compose.onNodeWithTag("amountCalculator.cancel").performClick(); noTransactions()
        Assert.assertTrue(runBlocking { repo.observeTransactions(other).first().isEmpty() })
    }
    @Test fun saveInProgressDisablesBothCalculatorActions() {
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        compose.setContent { MistiaTheme(darkTheme = false) { TransactionEditorSheet(owner.value, null, wallets, emptyList(), rates, now,
            initialState = initial().copy(amountText = "123", destinationAmountText = "246"), onDismiss = {}, onSave = { draft ->
                started.complete(Unit); release.await(); repo.saveTransaction(owner, draft, device, now)
            }) } }
        compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick(); compose.waitUntil(5000) { started.isCompleted }
        compose.onNodeWithTag("transaction.amount.calculator").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("transaction.destinationAmount.calculator").performScrollTo().assertIsNotEnabled()
        noTransactions(); compose.runOnIdle { release.complete(Unit) }
        compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().size == 1 } }
    }
}
