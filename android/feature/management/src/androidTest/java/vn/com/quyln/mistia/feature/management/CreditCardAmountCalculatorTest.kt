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
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardAmountCalculatorTest {
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
    @Composable private fun Editor(card: CreditCardAccount? = null) {
        MistiaTheme(darkTheme = false) { CreditCardEditorSheet(owner.value, card?.wallet, card?.profile, emptyList(), 0, onDismiss = {},
            onSave = { repo.saveCreditCard(owner, it, device, Instant.now().toString()) }) }
    }
    @Composable private fun Management(subject: UserId, repository: FinanceRepository = repo) {
        MistiaTheme(darkTheme = false) { ManagementScreen(subject, repository, deviceIdProvider = { device },
            onTranslatePendingCategories = {}, onSyncNow = {}, onSignOut = {}, onOpenFamily = {}, onOpenInvestment = {}, onOpenCreditCardStatements = {}) }
    }
    private fun addCard() {
        val title = ApplicationProvider.getApplicationContext<Context>().getString(R.string.planning_planning_add_credit_card)
        compose.onNodeWithText(title).performScrollTo().performClick()
    }
    private fun key(text: String) { compose.onNodeWithTag("amountCalculator.key.$text").performClick() }
    private fun amount(text: String) { compose.onNodeWithTag("card.creditLimit").performScrollTo().performTextReplacement(text) }
    private fun open() { compose.onNodeWithTag("card.creditLimit.calculator").performScrollTo().performClick() }
    private fun assertInput(text: String) { compose.onNodeWithTag("card.creditLimit").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(text))) }
    @Test fun exactVndCalculationOnlyPersistsAfterExplicitCardSave() {
        compose.setContent { Editor() }
        compose.onNodeWithTag("card.name").performScrollTo().performTextReplacement("Card")
        compose.onNodeWithText("VND").performScrollTo().performClick()
        amount("9007199254740993"); open(); key("+"); key("2"); key("OK")
        assertInput("9,007,199,254,740,995")
        Assert.assertTrue(runBlocking { repo.observeWallets(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE).isEmpty() })
        compose.onNodeWithTag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeCreditCardProfiles(owner).first().size == 1 } }
        Assert.assertEquals(9007199254740995L, runBlocking { repo.observeCreditCardProfiles(owner).first().single().creditLimitMinor })
        Assert.assertEquals("VND", runBlocking { repo.observeWallets(owner).first().single().currencyCode })
        Assert.assertEquals(0L, runBlocking { repo.observeWallets(owner).first().single().openingBalanceMinor })
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE).size })
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).size })
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
    }
    @Test fun invalidCalculationAndCancelPreserveBlankOrSignedLimit() {
        compose.setContent { Editor() }; open(); key("C"); key("1"); key("÷"); key("0"); key("OK")
        compose.onNodeWithTag("amountCalculator.error").assertExists(); compose.onNodeWithTag("amountCalculator.dismissError").performClick()
        compose.onNodeWithTag("amountCalculator.cancel").performClick(); assertInput("")
        amount("-250"); open(); compose.onNodeWithTag("amountCalculator.result").assertTextEquals("250")
        compose.onNodeWithTag("amountCalculator.cancel").performClick(); assertInput("-250")
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(owner).first().isEmpty() })
    }
    @Test fun expressionRestoresButChangingCardClearsToolAndUsesNewLimit() {
        val first = runBlocking { repo.saveCreditCard(owner, CreditCardDraft(name = "First", creditLimitMinor = 9007199254740993L), device, Instant.now().toString()).getOrThrow() }
        val second = runBlocking { repo.saveCreditCard(owner, CreditCardDraft(name = "Second", creditLimitMinor = 1375), device, Instant.now().toString()).getOrThrow() }
        val restoration = StateRestorationTester(compose); var card by mutableStateOf(first)
        restoration.setContent { Editor(card) }
        open(); key("+"); key("2"); restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("amountCalculator.result").assertTextEquals("9,007,199,254,740,995"); key("OK")
        assertInput("9,007,199,254,740,995"); open()
        compose.runOnIdle { card = second }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist(); assertInput("1,375")
        Assert.assertEquals(9007199254740993L, runBlocking { repo.observeCreditCardProfiles(owner).first().first { it.id == first.profile.id }.creditLimitMinor })
    }
    @Test fun foreignSuppliedCardIsNeverShown() {
        val foreign = runBlocking { repo.saveCreditCard(other, CreditCardDraft(name = "Foreign card", creditLimitMinor = 1375), device, Instant.now().toString()).getOrThrow() }
        compose.setContent { Editor(foreign) }
        compose.onNodeWithTag("card.name").assertDoesNotExist()
        compose.onNodeWithTag("card.creditLimit.calculator").assertDoesNotExist()
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(owner).first().isEmpty() })
    }
    @Test fun managementOwnerChangeClearsPrivateCardDraft() {
        var subject by mutableStateOf(owner)
        compose.setContent { Management(subject) }; addCard()
        compose.onNodeWithTag("card.name").performScrollTo().performTextReplacement("Private draft"); amount("1375"); open(); key("+"); key("2")
        compose.runOnIdle { subject = other }
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist()
        compose.waitUntil(5000) { compose.onAllNodesWithTag("card.name").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("card.name").performScrollTo().assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
        assertInput("")
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(other).first().isEmpty() })
    }
    @Test fun lateNonCancellableSaveCannotDismissNewOwnersCardDraft() {
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>(); val finished = CompletableDeferred<Unit>()
        val delayed = object : FinanceRepository by repo {
            override suspend fun saveCreditCard(ownerUserId: UserId, draft: CreditCardDraft, deviceId: String, now: String): Result<CreditCardAccount> {
                val result = repo.saveCreditCard(ownerUserId, draft, deviceId, now); started.complete(Unit)
                withContext(NonCancellable) { release.await() }; finished.complete(Unit); return result
            }
        }
        var subject by mutableStateOf(owner)
        compose.setContent { Management(subject, delayed) }; addCard()
        compose.onNodeWithTag("card.name").performScrollTo().performTextReplacement("Old draft"); amount("123")
        compose.onNodeWithTag("card.save").performScrollTo().performClick(); compose.waitUntil(5000) { started.isCompleted }
        compose.runOnIdle { subject = other }
        compose.waitUntil(5000) { compose.onAllNodesWithTag("card.name").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("card.name").performScrollTo().performTextReplacement("New draft")
        compose.runOnIdle { release.complete(Unit) }; compose.waitUntil(5000) { finished.isCompleted }
        compose.waitForIdle(); compose.onNodeWithTag("card.name").assertTextContains("New draft")
        Assert.assertEquals(123L, runBlocking { repo.observeCreditCardProfiles(owner).first().single().creditLimitMinor })
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(other).first().isEmpty() })
    }
}
