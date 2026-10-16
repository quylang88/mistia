package vn.com.quyln.mistia.feature.planning

import android.content.Context
import android.graphics.Bitmap
import java.io.File
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.YearMonth
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
class BudgetAmountCalculatorTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var categories: List<TransactionCategoryRecord>
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val category = "33333333-3333-3333-3333-333333333333"
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        repo = OfflineFirstFinanceRepository(RoomLocalStore(db))
        val now = Instant.now().toString()
        val parent = repo.saveCategory(owner, CategoryDraft(name = "Home", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
        repo.saveCategory(owner, CategoryDraft(id = category, name = "Food", kind = TransactionCategoryKind.EXPENSE, hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
        categories = repo.observeBudgetCategories(owner).first()
    }
    @Composable private fun Editor(subject: UserId = owner, dark: Boolean = false) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, if (dark) 1.3f else density.fontScale)) { MistiaTheme(darkTheme = dark) { BudgetEditorSheet(subject.value, null, YearMonth.now(), categories, emptyList(), emptyList(), CategoryNameLanguage.ENGLISH,
            onSave = { repo.saveBudget(subject, it, device, Instant.now().toString()) }, onArchive = { Result.success(Unit) }, onDelete = { Result.success(Unit) }, onDismiss = {}) } }
    }
    private fun key(text: String) { compose.onNodeWithTag("amountCalculator.key.$text").performClick() }
    private fun start(amount: String) {
        compose.onNodeWithTag("budget.amount").performTextReplacement(amount)
        val bounds=compose.onNodeWithTag("budget.amount.calculator").fetchSemanticsNode().boundsInRoot
        compose.onNodeWithTag("budget.amount.calculator").performClick()
        try {compose.onNodeWithTag("amountCalculator.dialog").assertExists()} catch(failure:Throwable) {
            android.util.Log.e("MistiaBudgetDiagnostic","calculator click bounds=$bounds")
            val roots=compose.onAllNodes(isRoot()).fetchSemanticsNodes()
            for(index in roots.indices) runCatching {android.util.Log.e("MistiaBudgetDiagnostic",compose.onAllNodes(isRoot())[index].printToString())}
            val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            bitmap?.let { java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),"budget-calculator-open-failure.png").outputStream().use {output -> it.compress(android.graphics.Bitmap.CompressFormat.PNG,100,output)};it.recycle() }
            throw failure
        }
    }
    @Test fun keypadPrecedenceOnlyChangesDraftUntilExplicitBudgetSave() {
        compose.setContent { Editor() }
        compose.onNodeWithTag("budget.category").performClick(); compose.onNodeWithTag("budget.category.$category").performClick()
        start("1375"); key("C"); key("1"); key("+"); key("2"); key("×"); key("3"); key("=")
        compose.onNodeWithTag("amountCalculator.result").assertTextEquals("7")
        capture("calculator-budget-light.png")
        key("OK"); compose.onNodeWithTag("budget.amount").assertTextContains("7")
        Assert.assertTrue(runBlocking { repo.observeBudgets(owner).first().isEmpty() })
        compose.onNodeWithTag("budget.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeBudgets(owner).first().size == 1 } }
        Assert.assertEquals(7L, runBlocking { repo.observeBudgets(owner).first().single().limitMinor })
    }
    @Test fun calculatorReleasesAmountFocusAndPreservesExactBudgetDraft() {
        compose.setContent {Editor()}
        compose.onNodeWithTag("budget.amount").performTextReplacement("9007199254740993")
        compose.onNodeWithTag("budget.amount").assertIsFocused()
        compose.onNodeWithTag("budget.amount.calculator").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick) {it()}
        key("+");key("2");key("OK")
        compose.onNodeWithTag("budget.amount").assertIsNotFocused().assertTextContains("9,007,199,254,740,995")
        Assert.assertTrue(runBlocking {repo.observeBudgets(owner).first().isEmpty()})
    }
    @Test fun fractionalAndDivisionZeroCannotCommitAndCancelKeepsOriginalDraft() {
        compose.setContent { Editor(dark = true) }
        start("1000"); key("C"); key("1"); key("÷"); key("3"); capture("calculator-budget-dark-font.png"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists()
        compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        key("C"); key("1"); key("÷"); key("0"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists()
        compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick()
        compose.onNodeWithTag("budget.amount").assertTextContains("1,000")
        Assert.assertTrue(runBlocking { repo.observeBudgets(owner).first().isEmpty() })
    }
    @Test fun calculationRestoresExactLargeExpressionButOwnerChangeRemovesIt() {
        val restore = StateRestorationTester(compose); var subject by mutableStateOf(owner)
        restore.setContent { Editor(subject) }
        start("9007199254740993"); key("+"); key("2")
        restore.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("amountCalculator.result").assertTextEquals("9,007,199,254,740,995")
        key("OK"); compose.onNodeWithTag("budget.amount").assertTextContains("9,007,199,254,740,995")
        compose.onNodeWithTag("budget.amount.calculator").performClick()
        compose.runOnIdle { subject = UserId("99999999-9999-9999-9999-999999999999") }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist()
        compose.onNodeWithTag("budget.amount").assert(hasText("9,007,199,254,740,995", substring = true).not())
    }
    private fun capture(name: String) {
        val bitmap = compose.onNodeWithTag("amountCalculator.dialog").captureToImage().asAndroidBitmap()
        File(ApplicationProvider.getApplicationContext<Context>().filesDir, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

}
