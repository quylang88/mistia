package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class PlanningReportingCurrencyTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var preferences:LocalCurrencyPreferencesStore
    private lateinit var prefName:String
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val zone=ZoneId.systemDefault()
    private val month=YearMonth.now(zone)
    private val now=Instant.now().toString()
    private val anchor=month.atDay(1).atStartOfDay(zone).toInstant().toString()
    private val snapshots=MutableStateFlow(listOf(ExchangeRateSnapshot("JPY","VND","2","manual",0,null)))
    private val exchange=object:ExchangeRateRepository {
        override val rates=snapshots
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        prefName="planning-currency-${java.util.UUID.randomUUID()}";preferences=LocalCurrencyPreferencesStore(context,prefName)
        preferences.setEnabled("VND",true);preferences.setPrimary("VND")
    }
    @After fun cleanup() {preferences.close();context.getSharedPreferences(prefName,Context.MODE_PRIVATE).edit().clear().commit()}
    private fun seed(large:Boolean=false)=runBlocking {
        for(code in if(large) listOf("JPY") else listOf("JPY","VND")) {
            val parent=repo.saveCategory(owner,CategoryDraft(name="Parent $code",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
            val child=repo.saveCategory(owner,CategoryDraft(name="Child $code",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
            repo.saveBudget(owner,BudgetDraft(child.id,anchor,if(large) 9007199254740993L else if(code == "JPY") 150 else 1000,code,zoneId=zone),device,now).getOrThrow()
            val wallet=repo.saveWallet(owner,WalletDraft(name=code,kind=WalletKind.CASH,currencyCode=code,openingBalanceMinor=100000),device,now).getOrThrow()
            if(!large) repo.saveTransaction(owner,TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense $code",amountMinor=if(code == "JPY") 100 else 300,
                occurredAt=month.atDay(5).atStartOfDay(zone).toInstant().toString(),sourceWalletId=wallet.id,categoryId=child.id),device,now).getOrThrow()
            repo.saveSavingsGoal(owner,SavingsGoalDraft("Goal $code",Long.MAX_VALUE,if(large) 9007199254740993L else if(code == "JPY") 100 else 300,
                month.plusMonths(2).atDay(1).atStartOfDay(zone).toInstant().toString(),code),device,now).getOrThrow()
        }
        repo.saveSavingsGoal(other,SavingsGoalDraft("Other owner",100000,99999,month.plusMonths(2).atDay(1).atStartOfDay(zone).toInstant().toString(),"VND"),device,now).getOrThrow()
    }
    private fun snapshot()=runBlocking {
        val entities=listOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.TRANSACTION_CATEGORY,CloudEntity.BUDGET_PLAN,CloudEntity.SAVINGS_GOAL)
        entities.associateWith {repo.observe(it,owner).first().sortedBy {row -> row.id}} to
            entities.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE).sortedBy {row -> row.mutation.recordId}}
    }
    @Composable private fun Screen(dark:Boolean=false) {
        val selected by preferences.state.collectAsState()
        MistiaTheme(darkTheme=dark) { androidx.compose.material3.Scaffold { padding ->
            PlanningScreen(owner,repo,modifier=androidx.compose.ui.Modifier.padding(padding),deviceIdProvider={device},exchangeRateRepository=exchange,primaryCurrencyCode=selected.primaryCurrencyCode)
        } }
    }
    private fun tag(name:String)=compose.onNodeWithTag(name)
    private fun waitBudget()=compose.waitUntil(5000) {compose.onAllNodesWithText("Child JPY").fetchSemanticsNodes().isNotEmpty()}
    private fun budget(limit:Long,spent:Long,remaining:Long,code:String) {
        tag("budget.summary.limit").performScrollTo().assertTextEquals(formatMinorUnits(limit,code))
        tag("budget.summary.spent").assertTextEquals("${context.getString(R.string.planning_planning_spent)}: ${formatMinorUnits(spent,code)}")
        tag("budget.summary.remaining").assertTextEquals("${context.getString(R.string.planning_planning_remaining)}: ${formatMinorUnits(remaining,code)}")
    }
    private fun saved(amount:Long,code:String) {
        tag("goal.summary.saved").performScrollTo().assertTextEquals("${context.getString(R.string.planning_planning_saved)}: ${formatMinorUnits(amount,code)}")
    }
    @Test fun budgetTotalsUseSelectedPrimaryAndInverseWithoutChangingBranchMoneyOrOutboxes() {
        seed();val before=snapshot();compose.setContent {Screen()};waitBudget()
        budget(1300,500,800,"VND")
        compose.runOnIdle {preferences.setPrimary("JPY")};budget(650,250,400,"JPY")
        compose.onNodeWithText("${formatMinorUnits(100,"JPY")} / ${formatMinorUnits(150,"JPY")}").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("${formatMinorUnits(300,"VND")} / ${formatMinorUnits(1000,"VND")}").performScrollTo().assertIsDisplayed()
        Assert.assertEquals(before,snapshot())
    }
    @Test fun savingsTotalTracksPrimaryAndLiveRatesWhileEachGoalKeepsItsCurrency() {
        seed();val before=snapshot();compose.setContent {Screen()};waitBudget()
        tag("planning.tab.2").performClick();saved(500,"VND")
        compose.runOnIdle {preferences.setPrimary("JPY")};saved(250,"JPY")
        compose.runOnIdle {snapshots.value=listOf(snapshots.value.single().copy(rateDecimalString="3"))};saved(200,"JPY")
        compose.onNodeWithText("${formatMinorUnits(100,"JPY")} / ${formatMinorUnits(Long.MAX_VALUE,"JPY")}").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Other owner").assertDoesNotExist()
        Assert.assertEquals(before,snapshot())
    }
    @Test fun missingAutomaticRatesNeverSumUnconvertedMinorAsPrimaryMoney() {
        seed();snapshots.value=emptyList();val before=snapshot();compose.setContent {Screen()};waitBudget()
        budget(1000,300,700,"VND")
        tag("planning.tab.2").performClick();saved(300,"VND")
        Assert.assertEquals(before,snapshot())
    }
    @Test fun largePrimarySummariesRenderLightDarkAtFont130() {
        seed(large=true);val before=snapshot();var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(dark)}
        }
        waitBudget()
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme == "dark"}
            tag("planning.tab.0").performScrollTo().performClick()
            budget(18014398509481986L,0,18014398509481986L,"VND")
            capture("planning-budget-$theme-font130.png")
            tag("planning.tab.2").performScrollTo().performClick();saved(18014398509481986L,"VND")
            val goalId=runBlocking {repo.observeSavingsGoals(owner).first().single().id}
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("goal.monthly.$goalId",useUnmergedTree=true).performScrollTo().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout=layouts.single();val text=layout.layoutInput.text.text
            val money=formatMinorUnits(3071454945866678272L,"JPY")
            val start=text.indexOf(money);Assert.assertTrue(start >= 0)
            for(line in 0 until layout.lineCount) {
                Assert.assertFalse("Monthly money split at line $line: $text",layout.getLineEnd(line) in (start+1) until (start+money.length))
            }
            capture("planning-goal-$theme-font130.png")
        }
        Assert.assertEquals(before,snapshot())
    }
    private fun capture(name:String) {
        compose.waitForIdle()
        val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
        java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        bitmap.recycle()
    }
    @Test fun largeConvertedSummaryPreservesEveryMinorUnitAboveDoublePrecision() {
        seed(large=true);val before=snapshot();compose.setContent {Screen()};waitBudget()
        budget(18014398509481986L,0,18014398509481986L,"VND")
        tag("planning.tab.2").performClick();saved(18014398509481986L,"VND")
        Assert.assertEquals(before,snapshot())
    }
}
