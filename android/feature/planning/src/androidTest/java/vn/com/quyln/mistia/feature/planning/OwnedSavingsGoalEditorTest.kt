package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
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
class OwnedSavingsGoalEditorTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val exchange=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
    }
    private fun goals(subject:UserId=owner)=runBlocking {repo.observeSavingsGoals(subject).first()}
    private fun seed(subject:UserId=owner,name:String="Original",currency:String="JPY")=runBlocking {
        repo.saveSavingsGoal(subject,SavingsGoalDraft(name,9007199254740993L,-25,"2027-01-01T00:00:00Z",currency),device,Instant.now().toString()).getOrThrow()
    }
    @Composable private fun Screen(primary:String,dark:Boolean=false) {MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
        PlanningScreen(owner,repo,modifier=Modifier.padding(padding),deviceIdProvider={device},exchangeRateRepository=exchange,primaryCurrencyCode=primary)
    }}}
    private fun tag(name:String)=compose.onNodeWithTag(name)
    private fun currency(code:String) {compose.onAllNodesWithText(code,useUnmergedTree=true).assertCountEquals(2)}
    private fun newGoal() {tag("planning.tab.2").performClick();tag("goal.add").performScrollTo().performClick()}
    private fun amount(field:String,text:String) {tag("goal.$field").performScrollTo().performTextReplacement(text)}
    private fun key(value:String) {tag("amountCalculator.key.$value").performClick()}
    @Test fun realPlanningCreatesExactVndGoalAndOutboxFromCurrentPrimary() {
        compose.setContent {Screen(" vnd ")};newGoal()
        tag("goal.name").performTextReplacement("Home")
        amount("target","9007199254740993");amount("current","-25");currency("VND")
        Assert.assertTrue(goals().isEmpty())
        tag("goal.save").performScrollTo().performClick()
        compose.waitUntil(5000) {goals().size==1}
        val saved=goals().single();Assert.assertEquals("VND",saved.currencyCode)
        Assert.assertEquals(9007199254740993L,saved.targetMinor);Assert.assertEquals(-25L,saved.currentSavedMinor)
        val pending=runBlocking {store.pendingMutations(owner,CloudEntity.SAVINGS_GOAL,Long.MAX_VALUE).single()}
        Assert.assertEquals(saved.toPayload(),pending.mutation.payload)
    }
    @Test fun existingGoalRetainsOwnCurrencyWhilePrimaryChanges() {
        val original=seed();var primary by mutableStateOf("VND")
        compose.setContent {Screen(primary)}
        tag("planning.tab.2").performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("goal.edit.${original.id}").fetchSemanticsNodes().isNotEmpty()}
        tag("goal.edit.${original.id}").performScrollTo().performClick()
        currency("JPY");tag("goal.target").assertTextContains("9,007,199,254,740,993")
        tag("goal.name").performTextReplacement("Edited")
        compose.runOnIdle {primary="JPY"}
        tag("goal.name").assertTextContains("Edited")
        tag("goal.save").performScrollTo().performClick()
        compose.waitUntil(5000) {goals().single().name=="Edited"}
        val saved=goals().single();Assert.assertEquals(original.currencyCode,saved.currencyCode)
        Assert.assertEquals(original.targetMinor,saved.targetMinor);Assert.assertEquals(original.currentSavedMinor,saved.currentSavedMinor)
        Assert.assertEquals(original.targetDate,saved.targetDate);Assert.assertEquals(original.id,saved.id)
    }
    @Test fun importedUsdGoalKeepsDecimalMinorMeaningUnderVndPrimary() {
        val seeded=seed(currency="USD")
        val original=runBlocking {repo.saveSavingsGoal(owner,SavingsGoalDraft("Imported",1375,1250,seeded.targetDate,"USD",id=seeded.id,editingExisting=true),device,Instant.now().toString()).getOrThrow()}
        compose.setContent {Screen("VND")};tag("planning.tab.2").performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("goal.edit.${original.id}").fetchSemanticsNodes().isNotEmpty()}
        tag("goal.edit.${original.id}").performScrollTo().performClick()
        currency("USD");tag("goal.target").assertTextContains("13.75")
        amount("target","14.25");tag("goal.save").performScrollTo().performClick()
        compose.waitUntil(5000) {goals().single().targetMinor==1425L}
        val saved=goals().single();Assert.assertEquals("USD",saved.currencyCode);Assert.assertEquals(1250L,saved.currentSavedMinor)
        Assert.assertEquals(original.id,saved.id);Assert.assertEquals(original.targetDate,saved.targetDate)
    }
    @Test fun foreignGoalNeverExposesAnEditorOrWrites() {
        val foreign=seed(other)
        compose.setContent {MistiaTheme(darkTheme=false) {SavingsGoalEditorSheet(owner.value,foreign,emptyList(),onSave={error("Foreign save")},onDelete={error("Foreign delete")},onDismiss={})}}
        tag("goal.editor").assertDoesNotExist();compose.onNodeWithText("Original").assertDoesNotExist()
        Assert.assertTrue(goals().isEmpty());Assert.assertEquals(foreign,goals(other).single())
    }
    @Test fun switchingRecordClosesOldPickerAndLoadsNewDraft() {
        val first=seed(name="First");val second=seed(name="Second");var selected by mutableStateOf(first)
        compose.setContent {MistiaTheme(darkTheme=false) {SavingsGoalEditorSheet(owner.value,selected,emptyList(),onSave={error("No save")},onDelete={error("No delete")},onDismiss={})}}
        tag("goal.wallet").performScrollTo().performClick()
        compose.runOnIdle {selected=second}
        compose.onAllNodesWithText(ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.planning_planning_not_linked)).assertCountEquals(1)
        tag("goal.name").assertTextContains("Second")
        Assert.assertEquals(listOf(first,second),goals())
    }
    @Test fun changedNewGoalPrimaryResetsDraftAndCalculatorWithoutRetaggingMoney() {
        var primary by mutableStateOf("VND")
        compose.setContent {Screen(primary)};newGoal()
        tag("goal.name").performTextReplacement("Private draft");amount("target","9007199254740993")
        tag("goal.target.calculator").performScrollTo().performClick();key("+");key("2")
        compose.runOnIdle {primary="JPY"}
        tag("amountCalculator.dialog").assertDoesNotExist()
        tag("goal.name").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
        tag("goal.target").assert(hasText("9,007,199,254,740,993",substring=true).not())
        amount("target","1");amount("current","0");currency("JPY")
        Assert.assertTrue(goals().isEmpty())
    }
    @Test fun primaryVndEditorAndCalculatorRenderInLightDarkAtFont130() {
        var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen("VND",dark)}
        }
        newGoal();tag("goal.name").performTextReplacement("Exact VND goal")
        amount("target","9007199254740993");amount("current","-25")
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            currency("VND");tag("goal.target").performScrollTo().assertTextContains("9,007,199,254,740,993")
            capture("goal-editor-$theme-font130.png")
            tag("goal.target.calculator").performScrollTo().performClick()
            tag("amountCalculator.result").assertTextEquals("9,007,199,254,740,993")
            capture("goal-calculator-$theme-font130.png")
            tag("amountCalculator.cancel").performClick()
        }
        Assert.assertTrue(goals().isEmpty());Assert.assertTrue(runBlocking {store.pendingMutations(owner,CloudEntity.SAVINGS_GOAL,Long.MAX_VALUE).isEmpty()})
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

    @Test fun lateNonCancellableSaveCannotDismissNextOwnersDraft() {
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner);var visible by mutableStateOf(true)
        compose.setContent {MistiaTheme(darkTheme=false) {if(visible) {
            val captured=subject
            SavingsGoalEditorSheet(captured.value,null,emptyList(),onSave={draft ->
                val result=repo.saveSavingsGoal(captured,draft,device,Instant.now().toString());started.complete(Unit)
                withContext(NonCancellable) {release.await()};finished.complete(Unit);result
            },onDelete={error("No delete")},onDismiss={visible=false})
        }}}
        tag("goal.name").performTextReplacement("Old");amount("target","123")
        try {
        tag("goal.save").performScrollTo().performClick();compose.waitUntil(5000) {started.isCompleted}
        compose.runOnIdle {subject=other}
        tag("goal.name").performScrollTo().assertIsEnabled().performTextReplacement("New")
        compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
        tag("goal.name").assertTextContains("New");Assert.assertEquals(123L,goals().single().targetMinor);Assert.assertTrue(goals(other).isEmpty())
        } finally {release.complete(Unit)}
    }
    @Test fun lateNonCancellableDeleteCannotDismissNextOwnersDraft() {
        val original=seed();val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner);var visible by mutableStateOf(true)
        compose.setContent {MistiaTheme(darkTheme=false) {if(visible) {
            val captured=subject
            SavingsGoalEditorSheet(captured.value,original.takeIf {captured==owner},emptyList(),onSave={error("No save")},onDelete={id ->
                val result=repo.deleteSavingsGoal(captured,RecordId(id),device,Instant.now().toString());started.complete(Unit)
                withContext(NonCancellable) {release.await()};finished.complete(Unit);result
            },onDismiss={visible=false})
        }}}
        try {
        tag("goal.delete").performScrollTo().performClick();tag("goal.confirmDelete").performClick()
        compose.waitUntil(5000) {started.isCompleted};compose.runOnIdle {subject=other}
        tag("goal.name").performScrollTo().assertIsEnabled().performTextReplacement("New")
        compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
        tag("goal.name").assertTextContains("New");Assert.assertTrue(goals().isEmpty());Assert.assertTrue(goals(other).isEmpty())
        } finally {release.complete(Unit)}
    }
}
