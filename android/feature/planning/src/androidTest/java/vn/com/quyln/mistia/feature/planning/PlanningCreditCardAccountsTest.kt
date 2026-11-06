package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class PlanningCreditCardAccountsTest {
    private val compose = createComposeRule()
    @get:org.junit.Rule val rules = RuleChain.outerRule(object : ExternalResource() {
        override fun after() { if (::database.isInitialized) database.close() }
    }).around(compose)
    private lateinit var database: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repository: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val exchange = object : ExchangeRateRepository {
        override val rates = MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis: Long) = Result.success(Unit)
    }

    @Before fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(database)
        repository = OfflineFirstFinanceRepository(store)
    }

    private fun seed(who: UserId = owner, name: String = "Planning Card", amount: Long = 70, limit: Long = 1000): LedgerWalletRecord = runBlocking {
            val now = Instant.now().toString()
            val cash = repository.saveWallet(who, WalletDraft(name = "Linked cash", kind = WalletKind.CASH,
                currencyCode = "JPY", openingBalanceMinor = 1000), device, now).getOrThrow()
            val saved = repository.saveCreditCard(who, CreditCardDraft(name = name, issuerName = "Issuer",
                last4 = "1234", creditLimitMinor = limit, currencyCode = "JPY", paymentSourceWalletId = cash.id), device, now).getOrThrow()
            val parent = repository.saveCategory(who, CategoryDraft(name = "Card parent", kind = TransactionCategoryKind.EXPENSE,
                hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
            val child = repository.saveCategory(who, CategoryDraft(name = "Card spending", kind = TransactionCategoryKind.EXPENSE,
                hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
            repository.saveTransaction(who, TransactionDraft(primaryKind = TransactionPrimaryKind.EXPENSE, title = "Card charge",
                amountMinor = amount, occurredAt = now, sourceWalletId = saved.wallet.id, categoryId = child.id), device, now).getOrThrow()
            assertEquals(amount, TransactionWalletBalanceIndex(repository.observeWallets(who).first(),
                repository.observeTransactions(who).first()).balance(saved.wallet.id))
            saved.wallet
    }
    private fun state() = runBlocking { listOf(owner, other).associateWith { who -> CloudEntity.entries.associateWith {
        store.recordsIncludingDeleted(who, it.table) to store.pendingMutations(who, it, Long.MAX_VALUE)
    } } }
    @Composable private fun Screen(who: UserId = owner, source: FinanceRepository = repository, dark: Boolean = false,
        primary: String = "JPY", onOpen: (String) -> Unit = {}, onEdit: (String) -> Unit = {}, onAdd: () -> Unit = {}) {
        MistiaTheme(darkTheme = dark) { Scaffold { padding ->
            PlanningScreen(who, source, Modifier.padding(padding), deviceIdProvider = { device }, exchangeRateRepository = exchange,
                primaryCurrencyCode = primary, onOpenCreditCardStatements = onOpen, onAddCreditCard = onAdd, onEditCreditCard = onEdit)
        } } }
    private fun openCards() {
        compose.onNodeWithTag("planning.tab.1").performClick()
        compose.onNodeWithTag("planning.due.1").performClick().assertIsSelected()
    }
    private fun waitCard(name: String = "Planning Card") = compose.waitUntil(5000) {
        compose.onAllNodesWithText(name).fetchSemanticsNodes().isNotEmpty()
    }
    private fun waitTag(tag: String) = compose.waitUntil(5000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    @Test fun realPlanningCardAccountDisplaysPostedDebtAndAvailableCredit() {
        val card = seed(); val before = state()
        compose.setContent { Screen() }; openCards()
        waitCard()
        compose.onNodeWithText("Planning Card").assertIsDisplayed()
        compose.onNodeWithTag("planning.card.debt.${card.id}", useUnmergedTree = true).assertTextEquals(formatMinorUnits(70, "JPY"))
        compose.onNodeWithTag("planning.card.available.${card.id}", useUnmergedTree = true).assertTextEquals(formatMinorUnits(930, "JPY"))
        assertEquals(before, state())
    }

    @Test fun emptyStateOffersAddAfterTheRealEmptyQuery() {
        var added = 0; val before = state()
        compose.setContent { Screen(onAdd = { added++ }) }; openCards(); waitTag("planning.cards.empty")
        compose.onNodeWithTag("planning.card.add").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, added) }; assertEquals(before, state())
    }

    @Test fun statementTouchDoesNotAlsoEditAndCardTapUsesTheWalletIdentity() {
        val card = seed(); seed(other, "Other account card"); val before = state()
        val opened = mutableListOf<String>(); val edited = mutableListOf<String>()
        compose.setContent { Screen(onOpen = { opened += it }, onEdit = { edited += it }) }; openCards(); waitCard()
        compose.onNodeWithText("Other account card").assertDoesNotExist()
        compose.onNodeWithTag("planning.card.statement.${card.id}").performScrollTo().performTouchInput { click() }
        compose.runOnIdle { assertEquals(listOf(card.id), opened); assertTrue(edited.isEmpty()) }
        compose.onNodeWithTag("planning.card.${card.id}").performClick()
        compose.runOnIdle { assertEquals(listOf(card.id), opened); assertEquals(listOf(card.id), edited) }
        assertEquals(before, state())
    }

    @Test fun retryAfterReadFailureReattachesTheRealOwnedRepository() {
        seed(); val before = state(); val reads = AtomicInteger()
        val failing = object : FinanceRepository by repository {
            override fun observeCreditCardAccountReadSnapshot(owner: UserId) = flow {
                if (reads.incrementAndGet() == 1) throw IOException("synthetic read failure")
                emitAll(repository.observeCreditCardAccountReadSnapshot(owner))
            }
        }
        compose.setContent { Screen(source = failing) }; openCards(); waitTag("planning.cards.error")
        compose.onNodeWithTag("planning.cards.retry").performClick(); waitCard()
        compose.onNodeWithTag("planning.cards.error").assertDoesNotExist()
        assertEquals(2, reads.get()); assertEquals(before, state())
    }

    @Test fun ownerRotationClearsOldCardWhileTheNewOwnerReadIsPending() {
        seed(); seed(other, "Other account card"); val before = state()
        var current by mutableStateOf(owner); val release = CompletableDeferred<Unit>()
        val delayed = object : FinanceRepository by repository {
            override fun observeCreditCardAccountReadSnapshot(owner: UserId) = flow {
                if (owner == other) release.await()
                emitAll(repository.observeCreditCardAccountReadSnapshot(owner))
            }
        }
        compose.setContent { Screen(who = current, source = delayed) }; openCards(); waitCard()
        compose.runOnIdle { current = other }; openCards(); waitTag("planning.cards.loading")
        compose.onNodeWithText("Planning Card").assertDoesNotExist()
        compose.runOnIdle { release.complete(Unit) }; waitCard("Other account card")
        compose.onNodeWithText("Planning Card").assertDoesNotExist(); assertEquals(before, state())
    }

    @Test fun largeMoneyStaysExactAndUnclippedInLightDarkAtFont130RegardlessOfPrimary() {
        val amount = 9007199254740993L; val card = seed(amount = amount, limit = Long.MAX_VALUE); val before = state()
        var dark by mutableStateOf(false); var primary by mutableStateOf("JPY")
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.3f)) { Screen(dark = dark, primary = primary) }
        }
        openCards(); waitCard()
        for (theme in listOf("light", "dark")) {
            compose.runOnIdle { dark = theme == "dark"; primary = "VND" }
            try {
                for ((part, value) in listOf("debt" to amount, "available" to Long.MAX_VALUE - amount)) {
                    val node = compose.onNodeWithTag("planning.card.$part.${card.id}", useUnmergedTree = true)
                    node.performScrollTo().assertTextEquals(formatMinorUnits(value, "JPY"))
                    val layouts = mutableListOf<TextLayoutResult>()
                    node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                    val layout = layouts.single(); assertEquals(1, layout.lineCount)
                    assertFalse("$part overflowWidth=${layout.didOverflowWidth}, overflowHeight=${layout.didOverflowHeight}, " +
                        "size=${layout.size}, paragraph=${layout.multiParagraph.width}x${layout.multiParagraph.height}, " +
                        "intrinsic=${layout.multiParagraph.maxIntrinsicWidth}, style=${layout.layoutInput.style}, constraints=${layout.layoutInput.constraints}",
                        layout.hasVisualOverflow)
                }
            } finally {
                val file = File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null), "planning-cards-$theme-font130.png")
                file.outputStream().use { compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
        assertEquals(before, state())
    }
    @Test fun allSixNetworkMarksRenderInTheRealPlanningPane() {
        val card = seed(); val profile = runBlocking { repository.observeCreditCardProfiles(owner).first().single() }
        compose.setContent { Screen() }; openCards(); waitCard()
        for (network in CreditCardNetwork.entries) {
            runBlocking { repository.saveCreditCard(owner, CreditCardDraft(walletId = card.id, profileId = profile.id,
                name = "Planning Card", issuerName = "Issuer", network = network, last4 = "1234", creditLimitMinor = 1000,
                paymentSourceWalletId = profile.paymentSourceWalletId), device, Instant.now().toString()).getOrThrow() }
            val expected = if (network == CreditCardNetwork.OTHER) ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.shared_corelogic_financeenums_other_wallet)
                else planningCreditCardNetworkName(network)
            compose.waitUntil(5000) { compose.onAllNodes(hasTestTag("planning.card.network.${card.id}") and hasContentDescription(expected), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
            val before = state()
            compose.onNodeWithTag("planning.card.statement.${card.id}").performScrollTo().assertIsDisplayed()
            val file = File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null), "planning-card-mark-${network.wireValue}-en.png")
            file.outputStream().use { compose.onNodeWithTag("planning.card.${card.id}").captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            assertEquals(before, state())
        }
    }
    @Test fun japaneseLargeMoneyAndFooterRemainVisibleAtFont130() = localizedLargeMoney("ja", false)
    @Test fun vietnameseLargeMoneyAndFooterRemainVisibleAtFont130() = localizedLargeMoney("vi", true)
    private fun localizedLargeMoney(language: String, dark: Boolean) {
        val amount = 9007199254740993L; val card = seed(amount = amount, limit = Long.MAX_VALUE); val before = state()
        compose.setContent {
            val context = androidx.compose.ui.platform.LocalContext.current
            val configuration = android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(language)) }
            val density = LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(configuration),
                androidx.compose.ui.platform.LocalConfiguration provides configuration, LocalDensity provides Density(density.density, 1.3f)) { Screen(dark = dark) }
        }
        openCards(); waitCard()
        for ((part, value) in listOf("debt" to amount, "available" to Long.MAX_VALUE - amount)) {
            val node = compose.onNodeWithTag("planning.card.$part.${card.id}", useUnmergedTree = true)
            node.performScrollTo().assertTextEquals(formatMinorUnits(value, "JPY"))
            val layouts = mutableListOf<TextLayoutResult>(); node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertFalse(layouts.single().hasVisualOverflow)
        }
        val node = compose.onNodeWithTag("planning.card.statement.${card.id}").performScrollTo().assertIsDisplayed()
        val configuration = android.content.res.Configuration(ApplicationProvider.getApplicationContext<Context>().resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(language)) }
        val localized = ApplicationProvider.getApplicationContext<Context>().createConfigurationContext(configuration)
        node.assertTextContains(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.planning_planning_statement))
        val file = File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null), "planning-card-$language-font130.png")
        file.outputStream().use { compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        assertEquals(before, state())
    }

}
