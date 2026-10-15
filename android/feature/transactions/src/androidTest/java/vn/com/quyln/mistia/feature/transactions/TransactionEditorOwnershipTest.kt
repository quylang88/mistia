package vn.com.quyln.mistia.feature.transactions

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
class TransactionEditorOwnershipTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() { override fun after() { if (::db.isInitialized) db.close() } }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallets: List<LedgerWalletRecord>
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-15T00:00:00Z"
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        repo = OfflineFirstFinanceRepository(RoomLocalStore(db))
        wallets = listOf(owner, other).flatMap { subject -> listOf("source", "destination").map { suffix ->
            repo.saveWallet(subject, WalletDraft(name = (if (subject == owner) "Self " else "Other ") + suffix, kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = 10000), device, now).getOrThrow()
        } }
    }
    private fun transfer(subject: UserId): TransactionEditorState {
        val owned = wallets.filter { it.ownerUserId == subject.value }
        return TransactionEditorState.new(now).selectKind(TransactionPrimaryKind.TRANSFER).copy(sourceWalletId = owned[0].id, destinationWalletId = owned[1].id)
    }
    private suspend fun saved(subject: UserId, amount: Long, title: String = "Record"): LedgerTransactionRecord = repo.saveTransaction(subject,
        transfer(subject).copy(amountText = amount.toString(), title = title).toDraft("JPY", "JPY").draft!!, device, now).getOrThrow()
    @Composable private fun Editor(subject: UserId = owner, record: LedgerTransactionRecord? = null, seed: TransactionEditorState? = null, includeForeign: Boolean = false) {
        MistiaTheme(darkTheme = false) { TransactionEditorSheet(subject.value, record, wallets.filter { includeForeign || it.ownerUserId == subject.value }, emptyList(), emptyList(), now,
            initialState = seed, onDismiss = {}, onSave = { repo.saveTransaction(subject, it, device, now) }) }
    }
    private fun titleField(transfer: Boolean = false) = compose.onNode(hasText(context.getString(if (transfer) R.string.transactions_transactioneditor_transaction_name_optional else R.string.transactions_transactioneditor_expense_name)) and hasSetTextAction())
    private fun amountField(selected: Boolean = false) = compose.onNode(hasText(context.getString(R.string.transactions_transactioneditor_amount) + if (selected) " (JPY)" else "") and hasSetTextAction())
    private fun assertEmpty(node: SemanticsNodeInteraction) = node.assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
    @Test fun ownerChangeClearsUnscopedPrivateDraft() {
        var subject by mutableStateOf(owner)
        compose.setContent { Editor(subject) }
        titleField().performScrollTo().performTextReplacement("Private draft"); amountField().performScrollTo().performTextReplacement("1375")
        compose.runOnIdle { subject = other }
        assertEmpty(titleField().performScrollTo()); assertEmpty(amountField().performScrollTo())
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertTrue(runBlocking { repo.observeTransactions(other).first().isEmpty() })
    }
    @Test fun foreignSuppliedTransactionIsNeverDisplayed() {
        val record = runBlocking { saved(other, 123, "Foreign record") }
        compose.setContent { Editor(record = record) }
        compose.onNodeWithText("Foreign record").assertDoesNotExist()
        compose.onNodeWithText(context.getString(R.string.common_save)).assertDoesNotExist()
    }
    @Test fun foreignWalletCandidatesAreNeverDisplayed() {
        compose.setContent { Editor(includeForeign = true) }
        compose.onAllNodesWithText("Other source · JPY").assertCountEquals(0)
        compose.onAllNodesWithText("Other destination · JPY").assertCountEquals(0)
        compose.onNodeWithText("Self source · JPY").assertExists()
    }
    @Test fun sameOwnerDraftRestoresButChangingRecordUsesItsOwnAmount() {
        val first = runBlocking { saved(owner, 123) }; val second = runBlocking { saved(owner, 456) }
        var record by mutableStateOf(first); val restore = StateRestorationTester(compose)
        restore.setContent { Editor(record = record) }
        amountField(true).performScrollTo().performTextReplacement("1000")
        restore.emulateSavedInstanceStateRestore(); amountField(true).performScrollTo().assertTextContains("1,000")
        compose.runOnIdle { record = second }; amountField(true).performScrollTo().assertTextContains("456")
        Assert.assertEquals(listOf(123L, 456L), runBlocking { repo.observeTransactions(owner).first().map { it.amountMinor }.sorted() })
    }
    @Test fun lateNonCancellableSaveCannotDismissOrAdvanceNewOwnersDraft() {
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>(); val finished = CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner); var visible by mutableStateOf(true); var completions = 0
        compose.setContent { MistiaTheme(darkTheme = false) { if (visible) {
            val captured = subject
            TransactionEditorSheet(captured.value, null, wallets.filter { it.ownerUserId == captured.value }, emptyList(), emptyList(), now,
                initialState = transfer(captured), onDismiss = { visible = false }, onSaveSuccess = { completions++ }, onSave = { draft ->
                    val result = repo.saveTransaction(captured, draft, device, now); started.complete(Unit)
                    withContext(NonCancellable) { release.await() }; finished.complete(Unit); result
                })
        } } }
        titleField(true).performScrollTo().performTextReplacement("Old draft"); amountField(true).performScrollTo().performTextReplacement("123")
        compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick(); compose.waitUntil(5000) { started.isCompleted }
        compose.runOnIdle { subject = other }; titleField(true).performScrollTo().performTextReplacement("New draft")
        compose.runOnIdle { release.complete(Unit) }; compose.waitUntil(5000) { finished.isCompleted }; compose.waitForIdle()
        titleField(true).assertTextContains("New draft"); Assert.assertEquals(0, completions)
        Assert.assertEquals(123L, runBlocking { repo.observeTransactions(owner).first().single().amountMinor })
        Assert.assertTrue(runBlocking { repo.observeTransactions(other).first().isEmpty() })
    }
}
