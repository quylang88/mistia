package vn.com.quyln.mistia.feature.planning

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
class SavingsAmountCalculatorTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private var saveAttempts=0
    private lateinit var repo: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
    }
    @Composable private fun Editor(subject: UserId = owner) {
        MistiaTheme(darkTheme = false) { SavingsGoalEditorSheet(subject.value, null, emptyList(),
            onSave = { saveAttempts++; repo.saveSavingsGoal(subject, it, device, Instant.now().toString()) },
            onDelete = { Result.success(Unit) }, onDismiss = {}) }
    }
    private fun key(text: String) { compose.onNodeWithTag("amountCalculator.key.$text").performClick() }
    private fun open(field: String) { compose.onNodeWithTag("goal.$field.calculator").performScrollTo().performClick() }
    private fun amount(field: String, text: String) { compose.onNodeWithTag("goal.$field").performScrollTo().performTextReplacement(text) }
    private fun assertInput(field: String, text: String) { compose.onNodeWithTag("goal.$field").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(text))) }
    @Test fun targetAndCurrentCalculateIndependentlyAndPersistOnlyAfterGoalSave() {
        compose.setContent { Editor() }
        compose.onNodeWithTag("goal.name").performTextReplacement("Holiday")
        amount("target", "9007199254740993"); amount("current", "100")
        open("target"); key("+"); key("2"); key("OK")
        assertInput("target", "9,007,199,254,740,995"); assertInput("current", "100")
        open("current"); key("÷"); key("2"); key("OK")
        assertInput("current", "50"); assertInput("target", "9,007,199,254,740,995")
        Assert.assertTrue(runBlocking { repo.observeSavingsGoals(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.SAVINGS_GOAL, Long.MAX_VALUE).isEmpty() })
        compose.onNodeWithTag("goal.save").performScrollTo().performClick()
        try { compose.waitUntil(5000) { runBlocking { repo.observeSavingsGoals(owner).first().size == 1 } } } catch (failure: Throwable) {
            android.util.Log.e("MistiaGoalDiagnostic","save attempts=$saveAttempts")
            val roots=compose.onAllNodes(isRoot()).fetchSemanticsNodes()
            for(index in roots.indices) runCatching {android.util.Log.e("MistiaGoalDiagnostic",compose.onAllNodes(isRoot())[index].printToString())}
            val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            bitmap?.let { java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),"goal-save-failure.png").outputStream().use {output -> it.compress(android.graphics.Bitmap.CompressFormat.PNG,100,output)};it.recycle() }
            throw failure
        }
        val goal = runBlocking { repo.observeSavingsGoals(owner).first().single() }
        Assert.assertEquals(9007199254740995L, goal.targetMinor); Assert.assertEquals(50L, goal.currentSavedMinor)
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.SAVINGS_GOAL, Long.MAX_VALUE).size })
    }
    @Test fun calculatorReleasesAmountFocusAndKeepsExactUnsavedGoal() {
        compose.setContent { Editor() }
        amount("target","9007199254740993")
        compose.onNodeWithTag("goal.target").assertIsFocused()
        compose.onNodeWithTag("goal.target.calculator").performScrollTo().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick) {it()}
        key("+");key("2");key("OK")
        compose.onNodeWithTag("goal.target").assertIsNotFocused()
        assertInput("target","9,007,199,254,740,995")
        Assert.assertTrue(runBlocking {repo.observeSavingsGoals(owner).first().isEmpty()})
        Assert.assertTrue(runBlocking {store.pendingMutations(owner,CloudEntity.SAVINGS_GOAL,Long.MAX_VALUE).isEmpty()})
    }
    @Test fun cancelKeepsSignedCurrentAndRejectedTargetDoesNotAlterEitherField() {
        compose.setContent { Editor() }
        amount("target", "500"); amount("current", "-250")
        open("current"); compose.onNodeWithTag("amountCalculator.result").assertTextEquals("250"); key("+"); key("1")
        compose.onNodeWithTag("amountCalculator.cancel").performClick()
        assertInput("current", "-250"); assertInput("target", "500")
        open("target"); key("C"); key("1"); key("-"); key("2"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists(); compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick()
        assertInput("target", "500"); assertInput("current", "-250")
        Assert.assertTrue(runBlocking { repo.observeSavingsGoals(owner).first().isEmpty() })
    }
    @Test fun restorationRetainsSelectedFieldButChangingFieldOrOwnerDoesNotReuseExpression() {
        val restore = StateRestorationTester(compose); var subject by mutableStateOf(owner)
        restore.setContent { Editor(subject) }
        amount("target", "500"); amount("current", "20"); open("current"); key("+"); key("2")
        restore.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("amountCalculator.result").assertTextEquals("22"); key("OK")
        assertInput("current", "22"); assertInput("target", "500")
        open("target"); compose.onNodeWithTag("amountCalculator.result").assertTextEquals("500")
        compose.runOnIdle { subject = UserId("99999999-9999-9999-9999-999999999999") }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist()
        assertInput("target", ""); assertInput("current", "")
    }
}
