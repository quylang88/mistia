package vn.com.quyln.mistia.feature.management

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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class WalletAmountCalculatorTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
    }
    @Composable private fun Editor(subject: UserId = owner, original: LedgerWalletRecord? = null) {
        MistiaTheme(darkTheme = false) { WalletEditorSheet(subject.value, original, 0, onDismiss = {},
            onSave = { repo.saveWallet(subject, it, device, Instant.now().toString()) }, onArchive = { Result.success(Unit) }) }
    }
    private fun key(text: String) { compose.onNodeWithTag("amountCalculator.key.$text").performClick() }
    private fun amount(text: String) { compose.onNodeWithTag("wallet.openingBalance").performScrollTo().performTextReplacement(text) }
    private fun open() { compose.onNodeWithTag("wallet.openingBalance.calculator").performScrollTo().performClick() }
    private fun assertInput(text: String) { compose.onNodeWithTag("wallet.openingBalance").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(text))) }
    @Test fun calculatedVndBalancePersistsExactlyOnlyAfterExplicitWalletSave() {
        compose.setContent { Editor() }
        compose.onNodeWithTag("wallet.name").performScrollTo().performTextReplacement("Cash")
        compose.onNodeWithText("VND").performScrollTo().performClick()
        amount("9007199254740993"); open(); key("+"); key("2"); key("OK")
        assertInput("9,007,199,254,740,995")
        Assert.assertTrue(runBlocking { repo.observeWallets(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).isEmpty() })
        compose.onNodeWithTag("wallet.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeWallets(owner).first().size == 1 } }
        val saved = runBlocking { repo.observeWallets(owner).first().single() }
        Assert.assertEquals("VND", saved.currencyCode); Assert.assertEquals(9007199254740995L, saved.openingBalanceMinor)
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).size })
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
    }
    @Test fun invalidCalculationAndCancelPreserveSignedOpeningBalance() {
        compose.setContent { Editor() }; amount("-250"); open()
        compose.onNodeWithTag("amountCalculator.result").assertTextEquals("250")
        key("C"); key("1"); key("÷"); key("0"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists(); compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick(); assertInput("-250")
        Assert.assertTrue(runBlocking { repo.observeWallets(owner).first().isEmpty() })
    }
    @Test fun savedExpressionRestoresExactlyButOwnerChangeClearsDraftAndTool() {
        val restore = StateRestorationTester(compose); var subject by mutableStateOf(owner)
        restore.setContent { Editor(subject) }
        amount("9007199254740993"); open(); key("+"); key("2")
        restore.emulateSavedInstanceStateRestore(); compose.onNodeWithTag("amountCalculator.result").assertTextEquals("9,007,199,254,740,995"); key("OK")
        assertInput("9,007,199,254,740,995"); open()
        compose.runOnIdle { subject = other }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist(); assertInput("")
        Assert.assertTrue(runBlocking { repo.observeWallets(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { repo.observeWallets(other).first().isEmpty() })
    }
    @Test fun existingOpeningBalanceStaysReadOnlyAndForeignWalletIsNeverShown() {
        val original = runBlocking { repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 1375), device, Instant.now().toString()).getOrThrow() }
        var subject by mutableStateOf(owner)
        compose.setContent { Editor(subject, original) }
        compose.onNodeWithTag("wallet.openingBalance").assertDoesNotExist(); compose.onNodeWithTag("wallet.openingBalance.calculator").assertDoesNotExist()
        compose.runOnIdle { subject = other }
        compose.onNodeWithTag("wallet.name").assertDoesNotExist()
        Assert.assertEquals(original, runBlocking { repo.observeWallets(owner).first().single() })
        Assert.assertTrue(runBlocking { repo.observeWallets(other).first().isEmpty() })
    }
    @Test fun lateNonCancellableSaveCannotDismissNewOwnersWalletDraft() {
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>(); val finished = CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner); var visible by mutableStateOf(true)
        compose.setContent { MistiaTheme(darkTheme = false) {
            if (visible) {
                val capturedOwner = subject
                WalletEditorSheet(capturedOwner.value, null, 0, onDismiss = { visible = false }, onSave = { draft ->
                    val result = repo.saveWallet(capturedOwner, draft, device, Instant.now().toString())
                    started.complete(Unit)
                    withContext(NonCancellable) { release.await() }
                    finished.complete(Unit); result
                }, onArchive = { Result.success(Unit) })
            }
        } }
        compose.onNodeWithTag("wallet.name").performScrollTo().performTextReplacement("Old draft"); amount("123")
        compose.onNodeWithTag("wallet.save").performScrollTo().performClick()
        compose.waitUntil(5000) { started.isCompleted }
        compose.runOnIdle { subject = other }
        compose.onNodeWithTag("wallet.name").performScrollTo().performTextReplacement("New draft")
        compose.runOnIdle { release.complete(Unit) }
        compose.waitUntil(5000) { finished.isCompleted }
        compose.waitForIdle(); compose.onNodeWithTag("wallet.name").assertTextContains("New draft")
        Assert.assertEquals(123L, runBlocking { repo.observeWallets(owner).first().single().openingBalanceMinor })
        Assert.assertTrue(runBlocking { repo.observeWallets(other).first().isEmpty() })
    }
}
