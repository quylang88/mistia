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
class InstallmentAmountCalculatorTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallet: LedgerWalletRecord
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY"), device, Instant.now().toString()).getOrThrow()
    }
    @Composable private fun Editor(subject: UserId = owner, identity: String = id, original: InstallmentPlanRecord? = null) {
        MistiaTheme(darkTheme = false) { InstallmentEditorSheet(subject.value, identity, original, original?.currencyCode ?: "JPY", listOf(wallet),
            onSave = { repo.saveInstallment(subject, it, device, Instant.now().toString()) },
            onDelete = { Result.success(Unit) }, onDismiss = {}) }
    }
    private fun key(text: String) { compose.onNodeWithTag("amountCalculator.key.$text").performClick() }
    private fun open() { compose.onNodeWithTag("installment.amount.calculator").performScrollTo().performClick() }
    private fun amount(text: String) { compose.onNodeWithTag("installment.amountInput").performTextReplacement(text) }
    private fun assertInput(text: String) { compose.onNodeWithTag("installment.amountInput").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(text))) }
    private fun plans() = runBlocking { repo.observeInstallments(owner).first() }
    @Test fun exactCalculatedCycleAmountWritesOnlyMetadataAfterExplicitSave() {
        compose.setContent { Editor() }
        compose.onNodeWithTag("installment.name").performTextReplacement("Loan")
        amount("9007199254740993"); open(); key("+"); key("2"); key("OK")
        assertInput("9,007,199,254,740,995")
        Assert.assertTrue(plans().isEmpty())
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).isEmpty() })
        compose.onNodeWithTag("installment.wallet").performScrollTo().performClick(); compose.onNodeWithTag("installment.pickWallet.${wallet.id}").performClick()
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) { plans().size == 1 }
        Assert.assertEquals(9007199254740995L, plans().single().amountPerCycleMinor)
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).size })
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertEquals(wallet, runBlocking { repo.observeWallets(owner).first().single() })
    }
    @Test fun importedUsdCalculatorKeepsRawMinorUnitsAndFormattedPreview() {
        val original = runBlocking {
            wallet = repo.saveWallet(owner, WalletDraft(id = wallet.id, name = "Cash", kind = WalletKind.CASH, currencyCode = "USD"), device, Instant.now().toString()).getOrThrow()
            repo.saveInstallment(owner, InstallmentDraft(id, "Loan", 1375, 15, 1, 12, wallet.id, "USD"), device, Instant.now().toString()).getOrThrow()
        }
        val before = runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE) }
        compose.setContent { Editor(original = original) }
        assertInput("1,375"); open(); key("÷"); key("5"); key("OK")
        assertInput("275"); compose.onNodeWithTag("installment.amountPreview").assertTextContains("$2.75", substring = true)
        Assert.assertEquals(original, plans().single())
        Assert.assertEquals(before, runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE) })
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) { plans().single().amountPerCycleMinor == 275L }
        Assert.assertEquals("USD", plans().single().currencyCode)
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertEquals(wallet, runBlocking { repo.observeWallets(owner).first().single() })
    }
    @Test fun rejectedDivisionAndCancelLeaveOriginalCycleDraftWithoutOutbox() {
        compose.setContent { Editor() }; amount("1375"); open(); key("C"); key("1"); key("÷"); key("0"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists(); compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick(); assertInput("1,375")
        Assert.assertTrue(plans().isEmpty())
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).isEmpty() })
    }
    @Test fun expressionRestoresButIdentityAndOwnerChangesRemoveIt() {
        val restore = StateRestorationTester(compose); var subject by mutableStateOf(owner); var identity by mutableStateOf(id)
        restore.setContent { Editor(subject, identity) }
        amount("1375"); open(); key("+"); key("2"); key("5")
        restore.emulateSavedInstanceStateRestore(); compose.onNodeWithTag("amountCalculator.result").assertTextEquals("1,400"); key("OK")
        assertInput("1,400"); open()
        compose.runOnIdle { identity = "44444444-4444-4444-4444-444444444444" }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist(); assertInput("")
        amount("500"); open()
        compose.runOnIdle { subject = UserId("99999999-9999-9999-9999-999999999999") }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist(); assertInput("")
    }
}
