package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
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

@RunWith(AndroidJUnit4::class)
class OwnedBudgetEditorTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var categories:List<TransactionCategoryRecord>
    private lateinit var parent:TransactionCategoryRecord
    private lateinit var child:TransactionCategoryRecord
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val month=YearMonth.now()
    private val zone=ZoneId.systemDefault()
    private val exchange=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    private fun now()=Instant.now().toString()
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        parent=repo.saveCategory(owner,CategoryDraft(name="Home",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now()).getOrThrow()
        child=repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now()).getOrThrow()
        categories=repo.observeBudgetCategories(owner).first()
    }
    private fun plans(subject:UserId=owner)=runBlocking {repo.observeBudgets(subject).first()}
    private fun seed(code:String="JPY",amount:Long=9007199254740993L,category:TransactionCategoryRecord=child,selected:YearMonth=month)=runBlocking {
        repo.saveBudget(UserId(category.ownerUserId),BudgetDraft(category.id,selected.atDay(1).atStartOfDay(zone).toInstant().toString(),amount,code,zoneId=zone),device,now()).getOrThrow()
    }
    @Composable private fun Screen(primary:String,dark:Boolean=false) {MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
        PlanningScreen(owner,repo,modifier=Modifier.padding(padding),deviceIdProvider={device},exchangeRateRepository=exchange,primaryCurrencyCode=primary)
    }}}
    @Composable private fun Editor(subject:UserId=owner,original:BudgetPlanRecord?=null,selected:YearMonth=month,
        save:suspend (BudgetDraft)->Result<BudgetPlanRecord> = {repo.saveBudget(subject,it,device,now())},
        delete:suspend (String)->Result<Unit> = {repo.deleteBudget(subject,RecordId(it),device,now())},dismiss:()->Unit={},
    ) {MistiaTheme(darkTheme=false) {BudgetEditorSheet(subject.value,original,selected,categories,plans(subject),emptyList(),CategoryNameLanguage.ENGLISH,
        onSave=save,onArchive={repo.archiveBudget(subject,RecordId(it),device,now())},onDelete=delete,onDismiss=dismiss)}}
    private fun tag(name:String)=compose.onNodeWithTag(name)
    private fun openBudget(id:String) {
        val node="budget.edit.$id"
        // Room emissions are outside Compose idling; wait for the actual merged action.
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(node) and hasClickAction()).fetchSemanticsNodes().size==1}
        tag(node).performScrollTo().performClick()
    }
    private fun saveBudget() {
        // These cases assert exact financial persistence; physical IME hit testing is separate.
        tag("budget.save").performScrollTo().assertIsEnabled().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick) {it()}
    }
    private fun amount(text:String) {tag("budget.amount").performScrollTo().performTextReplacement(text)}
    private fun currency(code:String) {compose.onNode(hasText(code) and hasAnyAncestor(hasTestTag("budget.amount")),useUnmergedTree=true).assertExists()}
    private fun choose(category:TransactionCategoryRecord=child) {tag("budget.category").performScrollTo().performClick();tag("budget.category.${category.id}").performClick()}
    private fun key(value:String) {tag("amountCalculator.key.$value").performClick()}
    @Test fun realPlanningCreatesExactVndBudgetAndMatchingOutbox() {
        compose.setContent {Screen(" vnd ")};tag("budget.add").performScrollTo().performClick()
        choose();amount("9007199254740993");currency("VND");tag("budget.amount").assertTextContains("9,007,199,254,740,993");saveBudget()
        compose.waitUntil(5000) {plans().size==1};val saved=plans().single()
        Assert.assertEquals("VND",saved.currencyCode);Assert.assertEquals(9007199254740993L,saved.limitMinor)
        Assert.assertEquals(saved.toPayload(),runBlocking {store.pendingMutations(owner,CloudEntity.BUDGET_PLAN,Long.MAX_VALUE).single()}.mutation.payload)
        Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()});Assert.assertTrue(runBlocking {repo.observeWallets(owner).first().isEmpty()})
    }
    @Test fun branchCurrencyOverridesPrimaryAndClearsOldMoneyThenLocksOtherChip() {
        seed("VND",10000,parent)
        compose.setContent {Screen("JPY")};tag("budget.add").performScrollTo().performClick()
        amount("9007199254740993");currency("JPY");choose();compose.onNodeWithText("VND").assertIsSelected()
        tag("budget.amount").assert(hasText("9,007,199,254,740,993",substring=true).not())
        compose.onNodeWithText("JPY").assertIsNotEnabled();amount("100");currency("VND");tag("budget.amount").assertTextContains("100");saveBudget()
        compose.waitUntil(5000) {plans().size==2};Assert.assertTrue(plans().all {it.currencyCode=="VND"})
        Assert.assertEquals(100L,plans().single {it.categoryId==child.id}.limitMinor)
    }
    @Test fun existingJpyBudgetKeepsMoneyIdentityAndUnsavedDraftAcrossPrimaryChange() {
        val original=seed();var primary by mutableStateOf("VND")
        compose.setContent {Screen(primary)};openBudget(original.id)
        currency("JPY");tag("budget.amount").assertTextContains("9,007,199,254,740,993")
        amount("9007199254740995");compose.runOnIdle {primary="JPY"};tag("budget.amount").assertTextContains("9,007,199,254,740,995")
        tag("budget.save").performScrollTo().performClick();compose.waitUntil(5000) {plans().single().limitMinor==9007199254740995L}
        val saved=plans().single();Assert.assertEquals("JPY",saved.currencyCode);Assert.assertEquals(original.id,saved.id);Assert.assertEquals(original.createdAt,saved.createdAt)
    }
    @Test fun importedUsdBudgetRetainsDecimalMinorMeaningUnderVndPrimary() {
        val original=seed("USD",1375)
        compose.setContent {Screen("VND")};openBudget(original.id)
        currency("USD");tag("budget.amount").assertTextContains("13.75");amount("14.25");tag("budget.save").performScrollTo().performClick()
        compose.waitUntil(5000) {plans().single().limitMinor==1425L};Assert.assertEquals("USD",plans().single().currencyCode)
    }
    @Test fun foreignOriginalNeverExposesBudgetEditor() {
        val foreignCategory=runBlocking {repo.saveCategory(other,CategoryDraft(name="Private",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now()).getOrThrow()}
        val foreign=seed(category=foreignCategory);val before=plans(other)
        compose.setContent {Editor(original=foreign)};tag("budget.editor").assertDoesNotExist()
        Assert.assertEquals(before,plans(other));Assert.assertTrue(plans().isEmpty())
    }
    @Test fun switchingRecordClosesOldCategoryPicker() {
        val first=seed(category=parent);val second=seed(amount=100)
        var selected by mutableStateOf(first)
        compose.setContent {Editor(original=selected)};tag("budget.category").performScrollTo().performClick()
        compose.runOnIdle {selected=second}
        tag("budget.category.${child.id}").assertDoesNotExist();tag("budget.amount").assertTextContains("100")
    }
    @Test fun switchingMonthClosesOldPickerAndResetsUnsavedAmount() {
        var selected by mutableStateOf(month)
        compose.setContent {Editor(selected=selected)};amount("123");tag("budget.category").performScrollTo().performClick()
        compose.runOnIdle {selected=month.plusMonths(1)}
        tag("budget.category.${child.id}").assertDoesNotExist();tag("budget.amount").assert(hasText("123",substring=true).not())
    }
    @Test fun livePrimaryResetsFreshDraftAndCalculator() {
        var primary by mutableStateOf("JPY")
        compose.setContent {Screen(primary)};tag("budget.add").performScrollTo().performClick();choose();amount("9007199254740993")
        tag("budget.amount.calculator").performScrollTo().performClick();key("+");key("2");compose.runOnIdle {primary="VND"}
        tag("amountCalculator.dialog").assertDoesNotExist();amount("1");currency("VND");Assert.assertTrue(plans().isEmpty())
    }
    @Test fun cancelledSaveCannotDismissReplacementOwnersEditor() {
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner);var dismissed=false
        compose.setContent {val captured=subject;Editor(captured,save={draft ->
            val result=repo.saveBudget(captured,draft,device,now());started.complete(Unit)
            withContext(NonCancellable) {release.await()};finished.complete(Unit);result
        },dismiss={dismissed=true})}
        choose();amount("123")
        try {
            tag("budget.save").performScrollTo().performClick();compose.waitUntil(5000) {started.isCompleted}
            compose.runOnIdle {subject=other};tag("budget.amount").assertIsEnabled();amount("456")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            tag("budget.amount").assertTextContains("456");compose.runOnIdle {Assert.assertFalse(dismissed)}
            Assert.assertEquals(123L,plans().single().limitMinor);Assert.assertTrue(plans(other).isEmpty())
        } finally {release.complete(Unit)}
    }
    @Test fun cancelledDeleteCannotDismissReplacementMonthDraft() {
        val original=seed();val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var selected by mutableStateOf(month);var dismissed=false
        compose.setContent {Editor(original=if(selected==month) original else null,selected=selected,delete={id ->
            val result=repo.deleteBudget(owner,RecordId(id),device,now());started.complete(Unit)
            withContext(NonCancellable) {release.await()};finished.complete(Unit);result
        },dismiss={dismissed=true})}
        try {
            tag("budget.destructive").performScrollTo().performClick();tag("budget.confirmDestructive").performClick()
            compose.waitUntil(5000) {started.isCompleted};compose.runOnIdle {selected=month.plusMonths(1)}
            tag("budget.amount").assertIsEnabled();amount("456")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            tag("budget.amount").assertTextContains("456");compose.runOnIdle {Assert.assertFalse(dismissed)};Assert.assertTrue(plans().isEmpty())
        } finally {release.complete(Unit)}
    }
    @Test fun primaryVndBudgetAndCalculatorRenderLightDarkAtFont130() {
        var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen("VND",dark=dark)}
        }
        tag("budget.add").performScrollTo().performClick();choose();amount("9007199254740993")
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            currency("VND");tag("budget.amount").performScrollTo().assertTextContains("9,007,199,254,740,993")
            capture("owned-budget-editor-$theme-font130.png")
            tag("budget.amount.calculator").performScrollTo().performClick()
            tag("amountCalculator.result").assertTextEquals("9,007,199,254,740,993")
            capture("owned-budget-calculator-$theme-font130.png")
            tag("amountCalculator.cancel").performClick()
        }
        Assert.assertTrue(plans().isEmpty());Assert.assertTrue(runBlocking {store.pendingMutations(owner,CloudEntity.BUDGET_PLAN,Long.MAX_VALUE).isEmpty()})
    }
    private fun capture(name:String) {
        compose.waitForIdle()
        val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000
        var previous:android.graphics.Bitmap?=null
        var stableFrames=0
        var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {
            val frame=checkNotNull(automation.takeScreenshot())
            stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame
            if(stableFrames>=3) {stable=frame;break}
        }
        if(stable==null) previous?.recycle()
        val bitmap=checkNotNull(stable) {"Screenshot did not reach stable compositor frames: $name"}
        java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        bitmap.recycle()
    }
}
