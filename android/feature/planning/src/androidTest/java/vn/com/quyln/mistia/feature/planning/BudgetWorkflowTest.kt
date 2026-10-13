package vn.com.quyln.mistia.feature.planning

import android.content.Context
import android.graphics.Bitmap
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
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
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

/** Synthetic owner, in-memory Room and no network client or authentication session. */
@RunWith(AndroidJUnit4::class)
class BudgetWorkflowTest {
    @get:Rule val compose = createComposeRule()
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
    @After fun close()=db.close()

    @Test fun createEditAndDeletePersistThroughNativeBudgetWorkflow() {
        compose.setContent { MistiaTheme(darkTheme=false) { PlanningScreen(owner,repo,deviceIdProvider={device},exchangeRateRepository=rates) } }
        compose.onNodeWithTag("budget.add").performScrollTo().performClick()
        compose.onNodeWithTag("budget.category").performClick()
        compose.onNodeWithTag("budget.category.$childId").performClick()
        compose.onNodeWithTag("budget.amount").performTextReplacement("500")
        capture("budget.editor","budget-editor-light.png")
        compose.onNodeWithTag("budget.save").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeBudgets(owner).first().size==1 } }
        val budget=runBlocking { repo.observeBudgets(owner).first().single() }
        Assert.assertEquals(500,budget.limitMinor)
        compose.onNodeWithTag("budget.edit.${budget.id}").performScrollTo().performClick()
        compose.onNodeWithTag("budget.amount").performTextReplacement("600")
        compose.onNodeWithTag("budget.save").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeBudgets(owner).first().single().limitMinor==600L } }
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

    private fun capture(tag:String,name:String) {
        val image=compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
        File(context.filesDir,name).outputStream().use { image.compress(Bitmap.CompressFormat.PNG,100,it) }
    }

    @Test fun savingsGoalCreateEditAndDeleteKeepWalletAndOutboxConsistent() {
        compose.setContent { MistiaTheme(darkTheme=false) { PlanningScreen(owner,repo,deviceIdProvider={device},exchangeRateRepository=rates) } }
        compose.onNodeWithTag("planning.tab.1").performClick()
        compose.onNodeWithTag("goal.add").performScrollTo().performClick()
        compose.onNodeWithTag("goal.name").performTextReplacement("Travel")
        compose.onNodeWithTag("goal.target").performTextReplacement("1000")
        compose.onNodeWithTag("goal.current").performTextReplacement("100")
        capture("goal.editor","goal-editor-light.png")
        compose.onNodeWithTag("goal.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeSavingsGoals(owner).first().size==1 } }
        val goal=runBlocking { repo.observeSavingsGoals(owner).first().single() }
        Assert.assertEquals(1000,goal.targetMinor)
        compose.onNodeWithTag("goal.edit.${goal.id}").performScrollTo().performClick()
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
