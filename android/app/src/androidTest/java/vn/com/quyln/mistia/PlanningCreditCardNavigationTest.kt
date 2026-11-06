package vn.com.quyln.mistia

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.feature.planning.PlanningScreen

@RunWith(AndroidJUnit4::class)
class PlanningCreditCardNavigationTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var card: CreditCardAccount
    private lateinit var nav: NavHostController
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = Instant.now().toString()
    private var selected by mutableStateOf(owner)
    private val exchange = object : ExchangeRateRepository {
        override val rates = MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis: Long) = Result.success(Unit)
    }
    @Before fun setup() { runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db, currentBillOwner = { selected }); repo = OfflineFirstFinanceRepository(store)
        val cash = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 1000), device, now).getOrThrow()
        card = repo.saveCreditCard(owner, CreditCardDraft(name = "Planning app card", creditLimitMinor = 1000, paymentSourceWalletId = cash.id), device, now).getOrThrow()
        selected = other
        repo.saveCreditCard(other, CreditCardDraft(name = "Private foreign card", creditLimitMinor = 500), device, now).getOrThrow()
        selected = owner
        val parent = repo.saveCategory(owner, CategoryDraft(name = "Parent", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
        val child = repo.saveCategory(owner, CategoryDraft(name = "Charge", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
        val occurred = YearMonth.now().atDay(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toString()
        repo.saveTransaction(owner, TransactionDraft(primaryKind = TransactionPrimaryKind.EXPENSE, title = "Card charge", amountMinor = 70,
            occurredAt = occurred, sourceWalletId = card.wallet.id, categoryId = child.id), device, now).getOrThrow()
    } }
    private fun state() = runBlocking { listOf(owner, other).associateWith { user -> CloudEntity.entries.associateWith {
        store.recordsIncludingDeleted(user, it.table) to store.pendingMutations(user, it, Long.MAX_VALUE)
    } } }
    private fun open() {
        compose.setContent { MistiaTheme(darkTheme = false) {
            val controller = rememberNavController(); nav = controller
            val currentOwner = selected
            NavHost(controller, "planning") {
                composable("planning") { Scaffold { padding -> PlanningScreen(currentOwner, repo, Modifier.padding(padding),
                    deviceIdProvider = { device }, exchangeRateRepository = exchange, primaryCurrencyCode = "JPY",
                    onOpenCreditCardStatements = { controller.navigate("credit-card-statements/$it") },
                    onAddCreditCard = { controller.navigate("credit-card-editor/new") },
                    onEditCreditCard = { controller.navigate("credit-card-editor/$it") }) } }
                planningCreditCardDestinations(currentOwner, repo, controller, { device }, listOf("JPY", "VND"), "JPY")
            }
        } }
        tabs()
    }
    private fun waitTag(tag: String) { compose.waitUntil(5000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() } }
    private fun tabs() { waitTag("planning.tab.1"); compose.onNodeWithTag("planning.tab.1").performClick(); compose.onNodeWithTag("planning.due.1").performClick() }
    private fun edit() { waitTag("planning.card.${card.wallet.id}"); compose.onNodeWithTag("planning.card.${card.wallet.id}").performClick(); waitTag("card.name") }
    private fun save() { compose.onNodeWithTag("card.save").performScrollTo().performClick() }
    private fun returned() { compose.waitUntil(5000) { nav.currentDestination?.route == "planning" }; tabs() }
    @Test fun statementTouchOpensActualStatementOnceAndBackReturnsToPlanning() {
        val before = state(); open(); waitTag("planning.card.${card.wallet.id}")
        compose.onNodeWithTag("planning.card.statement.${card.wallet.id}").performScrollTo().performTouchInput { click() }
        waitTag("statement.total"); compose.onNodeWithTag("card.name").assertDoesNotExist()
        compose.runOnIdle { assertEquals("credit-card-statements/{walletId}", nav.currentDestination?.route) }
        compose.onNodeWithContentDescription(ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.common_close)).performClick()
        returned(); waitTag("planning.card.${card.wallet.id}"); assertEquals(before, state())
    }
    @Test fun editSaveUpdatesActualProfileAndReturnsWithoutDuplicatingWallet() {
        open(); edit(); compose.onNodeWithTag("card.name").performTextReplacement("App edited card")
        compose.onNodeWithTag("card.creditLimit").performScrollTo().performTextReplacement("2500"); save(); returned()
        compose.waitUntil(5000) { compose.onAllNodesWithText("App edited card").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, runBlocking { repo.observeCreditCardProfiles(owner).first().size })
        assertEquals(2500L, runBlocking { repo.observeCreditCardProfiles(owner).first().single().creditLimitMinor })
        assertEquals(card.profile.id, runBlocking { repo.observeCreditCardProfiles(owner).first().single().id })
    }
    @Test fun cancelEditReturnsWithoutAnyRowOrOutboxChange() {
        val before = state(); open(); edit(); compose.onNodeWithTag("card.name").performTextReplacement("Cancelled draft")
        compose.onNodeWithText(ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.common_cancel)).performScrollTo().performClick()
        returned(); assertEquals(before, state())
    }
    @Test fun populatedAddSavesOneRealNewAccountThenReturns() {
        open(); waitTag("planning.card.${card.wallet.id}"); compose.onNodeWithTag("planning.card.add").performScrollTo().performClick(); waitTag("card.name")
        compose.onNodeWithTag("card.name").performTextReplacement("App new card")
        compose.onNodeWithTag("card.creditLimit").performScrollTo().performTextReplacement("3000"); save(); returned()
        assertEquals(2, runBlocking { repo.observeCreditCardProfiles(owner).first().size })
        compose.onNodeWithTag("card.name").assertDoesNotExist()
    }
    @Test fun emptyAddUsesTheSameActualEditorDestination() {
        runBlocking { db.cloudRecordDao().deleteRecord(owner.value, CloudEntity.LEDGER_WALLET.table, card.wallet.id) }
        open(); waitTag("planning.cards.empty"); compose.onNodeWithTag("planning.card.add").performClick(); waitTag("card.name")
        compose.onNodeWithTag("card.name").performTextReplacement("First visible card")
        compose.onNodeWithTag("card.creditLimit").performScrollTo().performTextReplacement("500"); save(); returned()
        compose.waitUntil(5000) { compose.onAllNodesWithText("First visible card").fetchSemanticsNodes().isNotEmpty() }
    }
    @Test fun missingEditDestinationClosesWithoutCreatingReplacement() {
        val before = state(); open(); waitTag("planning.card.${card.wallet.id}")
        compose.runOnIdle { nav.navigate("credit-card-editor/33333333-3333-3333-3333-333333333333") }
        returned(); compose.onNodeWithTag("card.name").assertDoesNotExist(); assertEquals(before, state())
    }
    @Test fun foreignEditDestinationClosesWithoutExposingOtherAccount() {
        val foreign = runBlocking { repo.observeCreditCardProfiles(other).first().single().walletId }
        val before = state(); open(); waitTag("planning.card.${card.wallet.id}"); compose.runOnIdle { nav.navigate("credit-card-editor/$foreign") }
        returned(); compose.onNodeWithText("Private foreign card").assertDoesNotExist(); assertEquals(before, state())
    }
    @Test fun ownerRotationRevokesTheOpenEditorAndCannotPersistOldDraft() {
        val before = state(); open(); edit(); compose.onNodeWithTag("card.name").performTextReplacement("Old owner draft")
        compose.runOnIdle { selected = other }; returned(); compose.onNodeWithTag("card.name").assertDoesNotExist()
        compose.onNodeWithText("Planning app card").assertDoesNotExist(); assertEquals(before, state())
    }
}
