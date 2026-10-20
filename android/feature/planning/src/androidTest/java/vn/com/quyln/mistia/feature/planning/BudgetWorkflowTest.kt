package vn.com.quyln.mistia.feature.planning

import android.content.Context
import android.graphics.Bitmap
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import java.io.File
import java.time.Instant
import java.time.YearMonth
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

/** Synthetic owner, in-memory Room and no network client or authentication session. */
@RunWith(AndroidJUnit4::class)
class BudgetWorkflowTest {
    private val compose = createComposeRule()
    // Room collectors belong to the Compose rule; dispose it before closing its database.
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() {
        override fun after() { if (::db.isInitialized) db.close() }
    }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var categories: List<TransactionCategoryRecord>
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val childId="33333333-3333-3333-3333-333333333333"
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private val rates=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        val now=Instant.now().toString()
        val parent=repo.saveCategory(owner,CategoryDraft(name="Living",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        repo.saveCategory(owner,CategoryDraft(id=childId,name="Food",kind=TransactionCategoryKind.EXPENSE,
            hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        categories=repo.observeBudgetCategories(owner).first()
    }


    @Test fun createEditAndDeletePersistThroughNativeBudgetWorkflow() {
        compose.setContent { MistiaTheme(darkTheme=false) { PlanningScreen(owner,repo,deviceIdProvider={device},exchangeRateRepository=rates) } }
        compose.onNodeWithTag("budget.add").performScrollTo().performClick()
        compose.onNodeWithTag("budget.category").performClick()
        compose.onNodeWithTag("budget.category.$childId").performClick()
        compose.onNodeWithTag("budget.amount").performTextReplacement("9007199254740993")
        compose.onNodeWithTag("budget.amount").assertTextContains("9,007,199,254,740,993")
        capture("budget.editor","budget-editor-light.png")
        compose.onNodeWithTag("budget.save").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeBudgets(owner).first().size==1 } }
        val budget=runBlocking { repo.observeBudgets(owner).first().single() }
        Assert.assertEquals(9007199254740993L,budget.limitMinor)
        compose.onNodeWithTag("budget.edit.${budget.id}").performScrollTo().performClick()
        compose.onNodeWithTag("budget.amount").assertTextContains("9,007,199,254,740,993")
        compose.onNodeWithTag("budget.amount").performTextReplacement("600")
        compose.onNodeWithTag("budget.save").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeBudgets(owner).first().single().limitMinor==600L } }
        compose.onNodeWithText("¥600.00", substring = true).assertDoesNotExist()
        Assert.assertTrue(compose.onAllNodesWithText("￥600", substring = true).fetchSemanticsNodes().isNotEmpty())
        capture("budget.screen","budget-list-light.png")
        compose.onNodeWithTag("budget.edit.${budget.id}").performScrollTo().performClick()
        compose.onNodeWithTag("budget.destructive").performScrollTo().performClick()
        compose.onNodeWithTag("budget.confirmDestructive").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeBudgets(owner).first().isEmpty() } }
        val mutation=runBlocking { store.pendingMutations(owner,CloudEntity.BUDGET_PLAN,Long.MAX_VALUE).single() }
        Assert.assertEquals(MutationKind.DELETE,mutation.mutation.kind)
        Assert.assertNotNull(runBlocking { store.record(owner,CloudEntity.BUDGET_PLAN.table,budget.id) }!!.deletedAt)
    }

    @Test fun saveFailureRetainsDraftAndDiscardRequiresConfirmationInDarkLargeFont() {
        var dismissed=false
        compose.setContent {
            val density=LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=true) {
                    BudgetEditorSheet(owner.value,null,YearMonth.now(),categories,emptyList(),emptyList(),CategoryNameLanguage.ENGLISH,
                        onSave={Result.failure(IllegalStateException("storage failure"))},onArchive={Result.success(Unit)},
                        onDelete={Result.success(Unit)},onDismiss={dismissed=true})
                }
            }
        }
        compose.onNodeWithTag("budget.category").performClick()
        compose.onNodeWithTag("budget.category.$childId").performClick()
        compose.onNodeWithTag("budget.amount").performTextReplacement("123")
        compose.onNodeWithTag("budget.save").performScrollTo().performClick()
        compose.onNodeWithTag("budget.amount").assertTextContains("123")
        Assert.assertFalse(dismissed)
        capture("budget.editor","budget-editor-dark-font.png")
        compose.onNodeWithTag("budget.close").performScrollTo().performClick()
        Assert.assertFalse(dismissed)
        compose.onNodeWithTag("budget.discard").performClick()
        compose.runOnIdle { Assert.assertTrue(dismissed) }
    }

    @Test fun walletPickerReleasesAmountFocusAndPreservesExactUnsavedDraft() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,Instant.now().toString()).getOrThrow()}
        compose.setContent {MistiaTheme(darkTheme=false) {
            RecurringBillEditorSheet(owner.value,null,categories,listOf(wallet),CategoryNameLanguage.ENGLISH,
                onSave={error("Save was not requested")},onPause={Result.success(Unit)},onResume={Result.success(Unit)},onArchive={Result.success(Unit)},onDismiss={})
        }}
        compose.onNodeWithTag("bill.name").performTextReplacement("Draft")
        compose.onNodeWithTag("bill.amount").performScrollTo().performTextReplacement("9007199254740993")
        compose.onNodeWithTag("bill.amount").assertIsFocused()
        // Exercise the picker action independently of the IME scroll/touch race; the physical workflow is tested separately.
        compose.onNodeWithTag("bill.wallet").performScrollTo().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick) {it()}
        compose.onNodeWithTag("bill.wallet.${wallet.id}").performClick()
        compose.onNodeWithTag("bill.amount").assertIsNotFocused().assertTextContains("9,007,199,254,740,993")
        compose.onNodeWithTag("bill.name").assertTextContains("Draft")
        Assert.assertTrue(runBlocking {repo.observeRecurringBills(owner).first().isEmpty()})
        Assert.assertTrue(runBlocking {store.pendingMutations(owner,CloudEntity.RECURRING_BILL_PLAN,Long.MAX_VALUE).isEmpty()})
    }

    @Test fun billFormPersistsExactAmountWithNativeControls() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,Instant.now().toString()).getOrThrow()}
        var bill by mutableStateOf<RecurringBillPlanRecord?>(null)
        var dismissed=false
        compose.setContent {MistiaTheme(darkTheme=false) {
            RecurringBillEditorSheet(owner.value,bill,categories.map {if(it.id==childId) it.copy(systemKey="rent") else it},listOf(wallet),CategoryNameLanguage.ENGLISH,
                onSave={draft -> repo.saveRecurringBill(owner,draft,device,Instant.now().toString()).also {it.onSuccess {saved -> bill=saved}}},
                onPause={repo.pauseRecurringBill(owner,RecordId(it),device,Instant.now().toString())},
                onResume={repo.resumeRecurringBill(owner,RecordId(it),device,Instant.now().toString())},
                onArchive={repo.archiveRecurringBill(owner,RecordId(it),device,Instant.now().toString())},onDismiss={dismissed=true})
        }}
        compose.onNodeWithTag("bill.name").performTextReplacement("Rent")
        compose.onNodeWithTag("bill.category").performClick()
        compose.onNodeWithTag("bill.category.$childId").performClick()
        try {
            compose.onNodeWithTag("bill.name").assertIsNotFocused()
            compose.onNodeWithTag("bill.wallet").performScrollTo().performClick()
            compose.onNodeWithTag("bill.wallet.${wallet.id}").performClick()
        } catch (failure: Throwable) {
            android.util.Log.e("MistiaBillPicker", "Expected synthetic wallet=$wallet")
            runCatching {
                val roots=compose.onAllNodes(isRoot(),useUnmergedTree=true)
                for(index in roots.fetchSemanticsNodes().indices) android.util.Log.e("MistiaBillPicker",roots[index].printToString())
            }.onFailure {android.util.Log.e("MistiaBillPicker","Semantics diagnostic unavailable",it)}
            runCatching {
                val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                File(context.getExternalFilesDir(null),"bill-picker-failure.png").outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
                bitmap.recycle()
            }
            throw failure
        }
        compose.onNodeWithTag("bill.amount").performScrollTo().performTextReplacement("9007199254740993")
        compose.onNodeWithTag("bill.amount").assertTextContains("9,007,199,254,740,993")
        compose.onNodeWithTag("bill.save").performScrollTo().performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeRecurringBills(owner).first().size==1}}
        Assert.assertEquals(9007199254740993L,runBlocking {repo.observeRecurringBills(owner).first().single().amountMinor})
        compose.waitUntil(5000) {dismissed}
        capture("bill.editor","bill-editor-light.png")
    }

    @Test fun billSaveFailureKeepsDraftAndRequiresDiscardInDarkLargeFont() {
        var dismissed=false
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,Instant.now().toString()).getOrThrow()}
        compose.setContent {
            val density=LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density,1.3f)) {MistiaTheme(darkTheme=true) {
                RecurringBillEditorSheet(owner.value,null,categories.map {if(it.id==childId) it.copy(systemKey="rent") else it},listOf(wallet),CategoryNameLanguage.ENGLISH,
                    onSave={Result.failure(IllegalStateException("storage failure"))},onPause={Result.success(Unit)},onResume={Result.success(Unit)},onArchive={Result.success(Unit)},onDismiss={dismissed=true})
            }}
        }
        compose.onNodeWithTag("bill.name").performTextReplacement("Rent")
        compose.onNodeWithTag("bill.category").performClick()
        compose.onNodeWithTag("bill.category.$childId").performClick()
        try {
            compose.onNodeWithTag("bill.wallet").performScrollTo().performClick()
            compose.onNodeWithTag("bill.wallet.${wallet.id}").performClick()
        } catch (failure: Throwable) {
            android.util.Log.e("MistiaBillPicker", "Expected synthetic wallet=$wallet")
            runCatching {
                val roots=compose.onAllNodes(isRoot(),useUnmergedTree=true)
                for(index in roots.fetchSemanticsNodes().indices) android.util.Log.e("MistiaBillPicker",roots[index].printToString())
            }.onFailure {android.util.Log.e("MistiaBillPicker","Semantics diagnostic unavailable",it)}
            runCatching {
                val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                File(context.getExternalFilesDir(null),"bill-picker-failure.png").outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
                bitmap.recycle()
            }
            throw failure
        }
        compose.onNodeWithTag("bill.amount").performScrollTo().performTextReplacement("123")
        compose.onNodeWithTag("bill.save").performScrollTo().performClick()
        compose.onNodeWithTag("bill.amount").assertTextContains("123")
        Assert.assertFalse(dismissed)
        compose.onNodeWithTag("bill.close").performScrollTo().performClick()
        compose.onNodeWithTag("bill.discard").performClick()
        compose.runOnIdle {Assert.assertTrue(dismissed)}
    }

    @Test fun skipAndUndoKeepLedgerEmptyThroughPlanningConfirmation() {
        val bill=runBlocking {
            val wallet=repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY"),device,Instant.now().toString()).getOrThrow()
            repo.saveRecurringBill(owner,RecurringBillDraft("Rent",childId,500,wallet.id,"JPY"),device,Instant.now().toString()).getOrThrow()
        }
        compose.setContent {MistiaTheme(darkTheme=false) {PlanningScreen(owner,repo,deviceIdProvider={device},exchangeRateRepository=rates)}}
        compose.onNodeWithTag("planning.tab.1").performClick()
        compose.onNodeWithTag("bill.skip.${bill.id}").performScrollTo().performClick()
        compose.onNodeWithTag("bill.confirmSkip").performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeDueOccurrences(owner).first().any {it.status==DueStatus.SKIPPED}}}
        Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()})
        compose.onNodeWithTag("bill.skip.${bill.id}").performScrollTo().performClick()
        compose.onNodeWithTag("bill.confirmSkip").performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeDueOccurrences(owner).first().isEmpty()}}
        Assert.assertEquals(MutationKind.DELETE,runBlocking {store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single().mutation.kind})
    }

    private fun capture(tag:String,name:String) {
        val image=compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
        File(context.filesDir,name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG,100,it) }
    }

    @Test fun savingsGoalCreateEditAndDeleteKeepWalletAndOutboxConsistent() {
        compose.setContent { MistiaTheme(darkTheme=false) { PlanningScreen(owner,repo,deviceIdProvider={device},exchangeRateRepository=rates) } }
        compose.onNodeWithTag("planning.tab.2").performClick()
        compose.onNodeWithTag("goal.add").performScrollTo().performClick()
        compose.onNodeWithTag("goal.name").performTextReplacement("Travel")
        compose.onNodeWithTag("goal.target").performTextReplacement("1000")
        compose.onNodeWithTag("goal.target").assertTextContains("1,000")
        compose.onNodeWithTag("goal.current").performTextReplacement("123456")
        compose.onNodeWithTag("goal.current").assertTextContains("123,456")
        capture("goal.editor","goal-editor-light.png")
        compose.onNodeWithTag("goal.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeSavingsGoals(owner).first().size==1 } }
        val goal=runBlocking { repo.observeSavingsGoals(owner).first().single() }
        Assert.assertEquals(1000,goal.targetMinor)
        Assert.assertEquals(123456L, goal.currentSavedMinor)
        compose.onNodeWithTag("goal.edit.${goal.id}").performScrollTo().performClick()
        compose.onNodeWithTag("goal.target").assertTextContains("1,000")
        compose.onNodeWithTag("goal.current").assertTextContains("123,456")
        compose.onNodeWithTag("goal.current").performTextReplacement("200")
        compose.onNodeWithTag("goal.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeSavingsGoals(owner).first().single().currentSavedMinor==200L } }
        capture("budget.screen","goal-list-light.png")
        compose.onNodeWithTag("goal.edit.${goal.id}").performScrollTo().performClick()
        compose.onNodeWithTag("goal.delete").performScrollTo().performClick()
        compose.onNodeWithTag("goal.confirmDelete").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeSavingsGoals(owner).first().isEmpty() } }
        Assert.assertTrue(runBlocking { repo.observeWallets(owner).first().isEmpty() })
        Assert.assertEquals(MutationKind.DELETE,runBlocking { store.pendingMutations(owner,CloudEntity.SAVINGS_GOAL,Long.MAX_VALUE).single().mutation.kind })
    }

    @Test fun savingsFailedSaveRetainsDraftAndRequiresDiscardInDarkLargeFont() {
        var dismissed=false
        compose.setContent {
            val density=LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=true) { SavingsGoalEditorSheet(owner.value,null,emptyList(),
                    onSave={Result.failure(IllegalStateException("storage failure"))},onDelete={Result.success(Unit)},onDismiss={dismissed=true}) }
            }
        }
        compose.onNodeWithTag("goal.name").performTextReplacement("Pending")
        compose.onNodeWithTag("goal.target").performTextReplacement("1000")
        compose.onNodeWithTag("goal.target").assertTextContains("1,000")
        compose.onNodeWithTag("goal.save").performScrollTo().performClick()
        compose.onNodeWithTag("goal.name").assertTextContains("Pending")
        Assert.assertFalse(dismissed)
        capture("goal.editor","goal-editor-dark-font.png")
        compose.onNodeWithTag("goal.close").performScrollTo().performClick()
        Assert.assertFalse(dismissed)
        compose.onNodeWithTag("goal.discard").performClick()
        compose.runOnIdle { Assert.assertTrue(dismissed) }
    }
}
