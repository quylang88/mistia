package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
class BillAmountCalculatorTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var categories: List<TransactionCategoryRecord>
    private lateinit var wallet: LedgerWalletRecord
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val category = "33333333-3333-3333-3333-333333333333"
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        val now = Instant.now().toString()
        val parent = repo.saveCategory(owner, CategoryDraft(name = "Home", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
        repo.saveCategory(owner, CategoryDraft(id = category, name = "Rent", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
        categories = repo.observeBudgetCategories(owner).first().map { if (it.id == category) it.copy(systemKey = "rent") else it }
        wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY"), device, now).getOrThrow()
    }
    @Composable private fun Editor(subject: UserId = owner) {
        MistiaTheme(darkTheme = false) { RecurringBillEditorSheet(subject.value, null, categories, listOf(wallet), CategoryNameLanguage.ENGLISH,
            onSave = { repo.saveRecurringBill(subject, it, device, Instant.now().toString()) }, onPause = { Result.success(Unit) },
            onResume = { Result.success(Unit) }, onArchive = { Result.success(Unit) }, onDismiss = {}) }
    }
    private fun key(text: String) { compose.onNodeWithTag("amountCalculator.key.$text").performClick() }
    private fun details() {
        compose.onNodeWithTag("bill.name").performTextReplacement("Rent")
        compose.onNodeWithTag("bill.category").performClick(); compose.onNodeWithTag("bill.category.$category").performClick()
        compose.onNodeWithTag("bill.wallet").performScrollTo().performClick(); compose.onNodeWithTag("bill.wallet.${wallet.id}").performClick()
    }
    @Test fun exactCalculatedAmountPersistsOnlyAfterExplicitBillSave() {
        compose.setContent { Editor() }; details()
        compose.onNodeWithTag("bill.amount").performScrollTo().performTextReplacement("9007199254740993")
        compose.onNodeWithTag("bill.amount.calculator").performClick(); key("+"); key("2"); key("OK")
        compose.onNodeWithTag("bill.amount").assertTextContains("9,007,199,254,740,995")
        Assert.assertTrue(runBlocking { repo.observeRecurringBills(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.RECURRING_BILL_PLAN, Long.MAX_VALUE).isEmpty() })
        compose.onNodeWithTag("bill.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeRecurringBills(owner).first().size == 1 } }
        Assert.assertEquals(9007199254740995L, runBlocking { repo.observeRecurringBills(owner).first().single().amountMinor })
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.RECURRING_BILL_PLAN, Long.MAX_VALUE).size })
    }
    @Test fun invalidCalculationAndCancelPreserveOptionalBlankAmount() {
        compose.setContent { Editor() }; details()
        compose.onNodeWithTag("bill.amount.calculator").performScrollTo().performClick(); key("1"); key("÷"); key("3"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists(); compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick()
        compose.onNodeWithTag("bill.amount").assert(hasText("1", substring = true).not())
        compose.onNodeWithTag("bill.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeRecurringBills(owner).first().size == 1 } }
        Assert.assertNull(runBlocking { repo.observeRecurringBills(owner).first().single().amountMinor })
    }
    @Test fun restoredExpressionKeepsLargeAmountButOwnerChangeClearsToolAndDraft() {
        val restore = StateRestorationTester(compose); var subject by mutableStateOf(owner)
        restore.setContent { Editor(subject) }
        compose.onNodeWithTag("bill.amount").performTextReplacement("9007199254740993")
        compose.onNodeWithTag("bill.amount.calculator").performClick(); key("+"); key("2")
        restore.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("amountCalculator.result").assertTextEquals("9,007,199,254,740,995")
        compose.runOnIdle { subject = UserId("99999999-9999-9999-9999-999999999999") }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist()
        compose.onNodeWithTag("bill.amount").assert(hasText("9,007,199,254,740,993", substring = true).not())
        Assert.assertTrue(runBlocking { repo.observeRecurringBills(owner).first().isEmpty() })
    }
}
