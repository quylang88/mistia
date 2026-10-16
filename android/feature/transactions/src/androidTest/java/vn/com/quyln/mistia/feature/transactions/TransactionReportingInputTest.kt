package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
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
class TransactionReportingInputTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallets: List<LedgerWalletRecord>
    private lateinit var categories: List<TransactionCategoryRecord>
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-16T00:00:00Z"
    private val rates = listOf(ExchangeRateSnapshot("JPY", "VND", "2", "fixture", 1L, "2026-10-16"))
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        wallets = listOf(owner, other).flatMap { subject -> listOf("JPY", "VND").map { code -> repo.saveWallet(subject,
            WalletDraft(name = code, kind = WalletKind.CASH, currencyCode = code, openingBalanceMinor = if (code == "JPY") 9007199254741000L else 10000), device, now).getOrThrow() } }
        categories = listOf(owner, other).flatMap { subject -> TransactionCategoryKind.entries.map { kind ->
            val parent = repo.saveCategory(subject, CategoryDraft(name = kind.name, kind = kind, hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
            repo.saveCategory(subject, CategoryDraft(name = kind.name + " child", kind = kind, hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
        } }
    }
    private fun initial(subject: UserId = owner, kind: TransactionPrimaryKind = TransactionPrimaryKind.EXPENSE, currency: String = "JPY", mode: CurrencyConversionMode = CurrencyConversionMode.MANUAL) =
        TransactionEditorState.new(now).copy(primaryKind = kind, title = "Report", amountText = "1000", conversionMode = mode,
            sourceWalletId = wallets.first { it.ownerUserId == subject.value && it.currencyCode == currency }.id,
            categoryId = categories.first { it.ownerUserId == subject.value && it.kind == if (kind == TransactionPrimaryKind.INCOME) TransactionCategoryKind.INCOME else TransactionCategoryKind.EXPENSE }.id)
    @Composable private fun Editor(subject: UserId = owner, primary: String = "VND", record: LedgerTransactionRecord? = null, seed: TransactionEditorState? = initial(subject), snapshots: List<ExchangeRateSnapshot> = rates, dark: Boolean = false, candidates: List<LedgerWalletRecord> = wallets) {
        MistiaTheme(darkTheme = dark) { TransactionEditorSheet(subject.value, record, candidates, categories, snapshots, now,
            primaryCurrencyCode = primary, initialState = if (record == null) seed else null, onDismiss = {}, onSave = { repo.saveTransaction(subject, it, device, now) }) }
    }
    private fun reporting() = compose.onNodeWithTag("transaction.reportingAmount")
    private fun source() = compose.onNodeWithTag("transaction.amount")
    private fun open() = compose.onNodeWithTag("transaction.reportingAmount.calculator").performScrollTo().performClick()
    private fun key(value: String) = compose.onNodeWithTag("amountCalculator.key.$value").performClick()
    private fun save() = compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick()
    private fun awaitSaved() = compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().size == 1 } }
    private fun assertNoWrites() {
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).isEmpty() })
    }
    private fun record(): LedgerTransactionRecord = runBlocking { repo.saveTransaction(owner,
        TransactionDraft(primaryKind = TransactionPrimaryKind.EXPENSE, title = "Stored", amountMinor = 100, occurredAt = now,
            sourceWalletId = initial().sourceWalletId, categoryId = initial().categoryId, reportingCurrencyCode = "VND", reportingAmountMinor = 200, conversionMode = CurrencyConversionMode.MANUAL), device, now).getOrThrow() }
    private fun capture(name: String) {
        compose.waitForIdle()
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val bitmap = checkNotNull(automation.takeScreenshot())
        java.io.File(context.getExternalFilesDir(null), name).outputStream().use { output ->
            Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output))
        }
        bitmap.recycle()
    }
    @Test fun reportingControlsRenderInLightDarkWithLargeFont() {
        var dark by mutableStateOf(false)
        compose.setContent {
            val density = androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density, 1.3f)) {
                Editor(seed = initial().copy(amountText = "9,007,199,254,740,993").withReportingAmount("18,014,398,509,481,986", "VND"), dark = dark)
            }
        }
        for (theme in listOf("light", "dark")) {
            compose.runOnIdle { dark = theme == "dark" }
            reporting().performScrollTo().assertTextContains("18,014,398,509,481,986"); capture("reporting-$theme-font130.png")
            open(); key("+"); key("1"); compose.onNodeWithTag("amountCalculator.result").assertTextEquals("18,014,398,509,481,987")
            compose.onNodeWithTag("amountCalculator.key.OK").assertIsDisplayed(); capture("reporting-calculator-$theme-font130.png")
            compose.onNodeWithTag("amountCalculator.cancel").performClick(); assertNoWrites()
        }
    }

    @Test fun importedManualReportingTargetCannotBeReinterpretedAsAnotherCurrency() {
        val source = wallets.first { it.ownerUserId == owner.value && it.currencyCode == "VND" }
        val existing = runBlocking { repo.saveTransaction(owner, TransactionDraft(primaryKind = TransactionPrimaryKind.EXPENSE, title = "Imported", amountMinor = 1000,
            occurredAt = now, sourceWalletId = source.id, categoryId = initial().categoryId, reportingCurrencyCode = "USD", reportingAmountMinor = 200,
            conversionMode = CurrencyConversionMode.MANUAL), device, now).getOrThrow() }
        compose.setContent { Editor(primary = "JPY", record = existing) }
        reporting().performScrollTo().assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText, androidx.compose.ui.text.AnnotatedString("")))
        save(); compose.waitForIdle(); Assert.assertEquals(existing, runBlocking { repo.observeTransactions(owner).first().single() })
        reporting().performScrollTo().performTextReplacement("500"); save()
        compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().single().reportingCurrencyCode == "JPY" } }
        val edited = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(1000L, edited.amountMinor); Assert.assertEquals(500L, edited.reportingAmountMinor)
        Assert.assertEquals("VND", edited.sourceCurrencyCode)
    }
    @Test fun currencyCodesAreCanonicalForLabelsAndCalculatorActions() {
        val candidates = wallets.map { if (it.ownerUserId == owner.value && it.currencyCode == "JPY") it.copy(currencyCode = " jpy ") else it }
        compose.setContent { Editor(primary = " vnd ", seed = initial().withReportingAmount("2000", "VND"), candidates = candidates) }
        compose.onNodeWithTag("transaction.reportingAmount.calculator").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("transaction.amount.calculator").performScrollTo().assertIsEnabled()
        reporting().performScrollTo().assertTextContains(context.getString(R.string.transactions_transactioneditor_converted_amount) + " (VND)"); save(); awaitSaved()
        Assert.assertEquals("VND", runBlocking { repo.observeTransactions(owner).first().single().reportingCurrencyCode })
    }

    @Test fun manualExpenseCalculatorSavesExactReportingPairOnlyAfterSave() {
        compose.setContent { Editor(seed = initial().copy(amountText = "9,007,199,254,740,993")) }
        reporting().performScrollTo().performTextReplacement("18014398509481985"); reporting().assertTextContains("18,014,398,509,481,985")
        open(); key("+"); key("1"); key("OK"); reporting().assertTextContains("18,014,398,509,481,986"); assertNoWrites()
        save(); awaitSaved()
        val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(9007199254740993L, saved.amountMinor); Assert.assertEquals(18014398509481986L, saved.reportingAmountMinor)
        Assert.assertEquals("JPY", saved.sourceCurrencyCode); Assert.assertEquals("VND", saved.reportingCurrencyCode)
        Assert.assertNull(saved.exchangeRateDecimalString); Assert.assertEquals("manual", saved.exchangeRateProvider)
        val pending = runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_TRANSACTION, Long.MAX_VALUE).single().mutation }
        Assert.assertEquals(JsonPrimitive(18014398509481986L), pending.payload!!["reporting_amount_minor"])
        Assert.assertEquals(wallets.filter { it.ownerUserId == owner.value }.associateBy { it.id }, runBlocking { repo.observeWallets(owner).first() }.associateBy { it.id })
    }
    @Test fun automaticIncomeUsesInverseRateWithoutEditableConvertedOrRateFields() {
        compose.setContent { Editor(primary = "JPY", seed = initial(kind = TransactionPrimaryKind.INCOME, currency = "VND", mode = CurrencyConversionMode.APP_RATE).copy(amountText = "1000")) }
        compose.onNodeWithTag("transaction.amount.calculator").performScrollTo().performClick(); key("+"); key("1"); key("OK")
        source().performScrollTo().assertTextContains("1,001")
        reporting().assertDoesNotExist(); compose.onNodeWithText(context.getString(R.string.settings_currency_rate_value)).assertDoesNotExist()
        save(); awaitSaved()
        val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(1001L, saved.amountMinor); Assert.assertEquals(501L, saved.reportingAmountMinor)
        Assert.assertEquals("JPY", saved.reportingCurrencyCode); Assert.assertEquals("2", saved.exchangeRateDecimalString)
        Assert.assertEquals("fixture", saved.exchangeRateProvider); Assert.assertEquals("2026-10-16", saved.exchangeRateDate)
    }
    @Test fun reportingExpressionRestoresAndEditSavesBothUpdatedDraftAmounts() {
        val existing = record(); val restore = StateRestorationTester(compose)
        restore.setContent { Editor(record = existing) }
        reporting().performScrollTo().assertTextContains("200"); open(); key("+"); key("2")
        restore.emulateSavedInstanceStateRestore(); compose.onNodeWithTag("amountCalculator.expression").assertTextEquals("200 + 2"); key("OK")
        source().performScrollTo().performTextReplacement("101"); reporting().performScrollTo().assertTextContains("202")
        Assert.assertEquals(existing, runBlocking { repo.observeTransactions(owner).first().single() })
        save(); compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().single().amountMinor == 101L } }
        val edited = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(existing.id, edited.id); Assert.assertEquals(202L, edited.reportingAmountMinor)
    }
    @Test fun primaryCurrencyChangeClosesOldExpressionAndClearsConversionOnSave() {
        val existing = record(); var primary by mutableStateOf("VND")
        compose.setContent { Editor(primary = primary, record = existing) }; open(); key("+"); key("9")
        compose.runOnIdle { primary = "JPY" }; compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist(); reporting().assertDoesNotExist()
        source().performScrollTo().assertTextContains("100"); save()
        compose.waitUntil(5000) { runBlocking { repo.observeTransactions(owner).first().single().reportingAmountMinor == null } }
        val edited = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertNull(edited.reportingCurrencyCode); Assert.assertNull(edited.conversionMode); Assert.assertNull(edited.exchangeRateProvider)
        Assert.assertEquals(100L, edited.amountMinor)
    }
    @Test fun ownerChangeDropsPrivateReportingDraftAndExpression() {
        var subject by mutableStateOf(owner)
        compose.setContent { Editor(subject, seed = initial(subject).withReportingAmount(if (subject == owner) "111" else "222", "VND")) }
        open(); key("+"); key("9"); compose.runOnIdle { subject = other }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist(); reporting().performScrollTo().assertTextContains("222")
        open(); compose.onNodeWithTag("amountCalculator.expression").assertTextEquals("222"); compose.onNodeWithTag("amountCalculator.cancel").performClick()
        assertNoWrites(); Assert.assertTrue(runBlocking { repo.observeTransactions(other).first().isEmpty() })
    }
    @Test fun missingAutomaticRateCannotSaveUntilManualConvertedAmountIsEntered() {
        compose.setContent { Editor(seed = initial(mode = CurrencyConversionMode.APP_RATE), snapshots = emptyList()) }
        save(); compose.waitForIdle(); assertNoWrites()
        compose.onNodeWithText(context.getString(R.string.transactions_transactioneditor_enter_manually)).performScrollTo().performClick()
        reporting().performScrollTo().performTextReplacement("2000"); save(); awaitSaved()
        Assert.assertEquals(2000L, runBlocking { repo.observeTransactions(owner).first().single().reportingAmountMinor })
    }
    @Test fun automaticInternalTransferAlsoHidesConvertedAndRateFields() {
        val seed = initial(mode = CurrencyConversionMode.APP_RATE).selectKind(TransactionPrimaryKind.TRANSFER).copy(conversionMode = CurrencyConversionMode.APP_RATE,
            destinationWalletId = wallets.first { it.ownerUserId == owner.value && it.currencyCode == "VND" }.id)
        compose.setContent { Editor(seed = seed) }
        compose.onNodeWithTag("transaction.destinationAmount").assertDoesNotExist(); compose.onNodeWithText(context.getString(R.string.settings_currency_rate_value)).assertDoesNotExist()
        save(); awaitSaved(); val saved = runBlocking { repo.observeTransactions(owner).first().single() }
        Assert.assertEquals(1000L, saved.amountMinor); Assert.assertEquals(2000L, saved.destinationAmountMinor)
    }
    @Test fun reportingCalculatorIsDisabledWhileSaving() {
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        compose.setContent { MistiaTheme(darkTheme = false) { TransactionEditorSheet(owner.value, null, wallets, categories, rates, now, primaryCurrencyCode = "VND",
            initialState = initial().withReportingAmount("2000", "VND"), onDismiss = {}, onSave = { draft -> started.complete(Unit); release.await(); repo.saveTransaction(owner, draft, device, now) }) } }
        save(); compose.waitUntil(5000) { started.isCompleted }
        compose.onNodeWithTag("transaction.reportingAmount.calculator").performScrollTo().assertIsNotEnabled(); assertNoWrites()
        compose.runOnIdle { release.complete(Unit) }; awaitSaved()
    }
}
