package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

/** Synthetic in-memory Room; executed on the isolated API36 emulator. */
@RunWith(AndroidJUnit4::class)
class InstallmentPaymentWorkflowTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallet: LedgerWalletRecord
    private lateinit var plan: InstallmentPlanRecord
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val now = Instant.parse("2026-10-15T00:00:00Z")
    private val month = YearMonth.of(2026, 10)
    private val catalog get() = SystemCategoryCatalog.parse(ApplicationProvider.getApplicationContext<Context>().assets.open("MistiaSystemCategories.json").bufferedReader().use { it.readText() })
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store, systemCategoryCatalog = catalog)
        wallet = repo.saveWallet(owner, WalletDraft(name = "Dollar cash", kind = WalletKind.CASH, currencyCode = "USD", openingBalanceMinor = 10000), device, now.toString()).getOrThrow()
        plan = repo.saveInstallment(owner, InstallmentDraft(id, "Loan", 1375, 15, 1, 12, wallet.id, "USD"), device, now.toString()).getOrThrow()
    }
    @After fun close() { db.close() }
    private fun row() = installmentDueRows(owner, listOf(plan), emptyList(), month, ZoneId.systemDefault()).single()
    private fun cycles() = runBlocking { repo.observeDueOccurrences(owner).first() }
    private fun transactions() = runBlocking { repo.observeTransactions(owner).first() }
    private fun balance() = TransactionWalletBalanceIndex(listOf(wallet), transactions()).balance(wallet.id)
    private fun open() { compose.onNodeWithTag("installment.pay.$id").performScrollTo().performClick() }
    private fun submit() { compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick() }
    private fun confirm() { compose.onNodeWithTag("installment.confirmPayment").performClick() }
    private fun waitClosed() { compose.waitUntil(5000) { compose.onAllNodesWithTag("installment.paymentSheet").fetchSemanticsNodes().isEmpty() } }

    @Test fun realRoomPaymentUndoAndRepayUseExactMinorAmountAndStableIdentities() {
        compose.setContent { MistiaTheme(darkTheme = false) {
            Column(Modifier.verticalScroll(rememberScrollState())) { InstallmentDuePane(owner, repo, month, { device }, now = { now }) }
        } }
        open(); compose.onNodeWithTag("installment.paymentAmount").assertExists()
        submit(); Assert.assertTrue(transactions().isEmpty()); confirm()
        compose.waitUntil(5000) { cycles().singleOrNull()?.status == DueStatus.PAID }; waitClosed()
        val transaction = transactions().single(); val cycle = cycles().single()
        Assert.assertEquals(1375L, transaction.amountMinor); Assert.assertEquals(8625L, balance())
        open(); compose.onNodeWithTag("installment.undoAmount").assertExists(); submit()
        compose.waitUntil(5000) { cycles().isEmpty() && transactions().isEmpty() }; waitClosed()
        Assert.assertEquals(10000L, balance())
        open(); submit(); confirm()
        compose.waitUntil(5000) { cycles().size == 1 }; waitClosed()
        Assert.assertEquals(transaction.id, transactions().single().id); Assert.assertEquals(cycle.id, cycles().single().id)
        Assert.assertEquals(8625L, balance())
        Assert.assertEquals(MutationKind.UPSERT, runBlocking { store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE).single().mutation.kind })
    }

    @Test fun restoredDraftKeepsOriginalBaselineAndRequiresDiscardThenMonthAndOwnerChangesCloseIt() {
        val alternate = runBlocking { repo.saveWallet(owner, WalletDraft(name = "Second cash", kind = WalletKind.CASH, currencyCode = "USD", openingBalanceMinor = 10000), device, now.toString()).getOrThrow() }
        val restoration = StateRestorationTester(compose)
        var selected by mutableStateOf(month); var subject by mutableStateOf(owner)
        restoration.setContent {
            val recreated = remember { OfflineFirstFinanceRepository(store, systemCategoryCatalog = catalog) }
            MistiaTheme(darkTheme = false) { Column(Modifier.verticalScroll(rememberScrollState())) {
                InstallmentDuePane(subject, recreated, selected, { device }, now = { now })
            } }
        }
        open(); compose.onNodeWithTag("installment.paymentWallet").performScrollTo().performClick()
        compose.onNodeWithTag("installment.payWallet.${alternate.id}").performClick()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("installment.paymentWallet").assertTextContains("Second cash", substring = true)
        compose.onNodeWithTag("installment.closePayment").performScrollTo().performClick()
        compose.onNodeWithTag("installment.keepPayment").performClick()
        compose.onNodeWithTag("installment.closePayment").performScrollTo().performClick()
        compose.onNodeWithTag("installment.discardPayment").performClick(); waitClosed()
        open(); compose.runOnIdle { selected = month.plusMonths(1) }
        compose.onNodeWithTag("installment.paymentSheet").assertDoesNotExist()
        open(); compose.runOnIdle { subject = other }
        compose.onNodeWithTag("installment.paymentSheet").assertDoesNotExist()
        Assert.assertTrue(transactions().isEmpty())
    }

    @Test fun pickerExcludesDifferentCurrencyForeignCardsInvestmentsArchivedAndDeletedWallets() {
        val excluded = listOf(wallet.copy(id = device, currencyCode = "JPY"), wallet.copy(id = id, kindWireValue = "creditCard"),
            wallet.copy(id = other.value, ownerUserId = other.value), wallet.copy(id = "44444444-4444-4444-4444-444444444444", kindWireValue = "investment"),
            wallet.copy(id = "55555555-5555-5555-5555-555555555555", isArchived = true), wallet.copy(id = "66666666-6666-6666-6666-666666666666", deletedAt = now.toString()))
        compose.setContent { MistiaTheme(darkTheme = true) {
            InstallmentPaymentSheet(owner.value, row(), excluded + wallet, onPay = { error("Unexpected payment") }, onUndo = { error("Unexpected undo") }, onDismiss = {})
        } }
        compose.onNodeWithTag("installment.paymentWallet").performScrollTo().performClick()
        compose.onNodeWithTag("installment.payWallet.${wallet.id}").assertExists()
        excluded.forEach { compose.onNodeWithTag("installment.payWallet.${it.id}").assertDoesNotExist() }
    }

    @Test fun walletCurrencyChangeInvalidatesOpenConfirmationBeforeAnyCallback() {
        var wallets by mutableStateOf(listOf(wallet)); var payments = 0
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentPaymentSheet(owner.value, row(), wallets, onPay = { payments++; Result.failure(IllegalStateException()) }, onUndo = { Result.success(Unit) }, onDismiss = {})
        } }
        submit(); compose.onNodeWithTag("installment.confirmPayment").assertIsEnabled()
        compose.runOnIdle { wallets = listOf(wallet.copy(currencyCode = "JPY")) }
        compose.onNodeWithTag("installment.confirmPayment").assertIsNotEnabled()
        compose.runOnIdle { Assert.assertEquals(0, payments) }
    }

    @Test fun busyDisablesDuplicateAndCloseThenFailureRetainsSelectedWalletAndAmount() {
        val release = CompletableDeferred<Unit>(); var saves = 0; var dismissed = false; var request: InstallmentPaymentRequest? = null
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentPaymentSheet(owner.value, row(), listOf(wallet), onPay = { request = it; saves++; release.await(); Result.failure(IllegalStateException("fixture")) },
                onUndo = { Result.success(Unit) }, onDismiss = { dismissed = true })
        } }
        submit(); confirm()
        compose.onNodeWithTag("installment.confirmPayment").assertIsNotEnabled()
        compose.runOnIdle { Assert.assertEquals(1, saves); Assert.assertFalse(dismissed); Assert.assertEquals(1375L, request!!.amountMinorOverride); release.complete(Unit) }
        compose.onNodeWithTag("installment.paymentError").assertExists()
        compose.onNodeWithTag("installment.paymentAmount").assertExists()
        compose.onNodeWithTag("installment.submitPayment").assertIsEnabled()
    }

    @Test fun lateNonCancellableUndoAfterMonthChangeCannotDismissNewPaymentSheet() {
        runBlocking { repo.payInstallment(owner, InstallmentPaymentRequest(plan, month), device, now.toString()).getOrThrow() }
        val release = CompletableDeferred<Unit>(); var selected by mutableStateOf(month)
        val controlled = object : FinanceRepository by repo {
            override suspend fun undoInstallmentPayment(owner: UserId, expected: InstallmentPlanRecord, month: YearMonth, deviceId: String, now: String): Result<Unit> =
                withContext(NonCancellable) { release.await(); Result.success(Unit) }
        }
        compose.setContent { MistiaTheme(darkTheme = false) { Column(Modifier.verticalScroll(rememberScrollState())) {
            InstallmentDuePane(owner, controlled, selected, { device }, now = { now })
        } } }
        open(); submit(); compose.onNodeWithTag("installment.submitPayment").assertIsNotEnabled()
        compose.onNodeWithTag("installment.closePayment").assertIsNotEnabled()
        compose.runOnIdle { selected = month.plusMonths(1) }
        compose.onNodeWithTag("installment.paymentSheet").assertDoesNotExist()
        open(); compose.runOnIdle { release.complete(Unit) }
        compose.onNodeWithTag("installment.paymentSheet").assertExists()
        compose.onNodeWithTag("installment.submitPayment").assertIsEnabled()
        Assert.assertEquals(1, transactions().size)
    }

    @Test fun loadingAndChangedOrZeroFrozenAmountCannotReachCallback() {
        var ready by mutableStateOf(false); var payments = 0; var due by mutableStateOf(row())
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentPaymentSheet(owner.value, due, listOf(wallet), dataReady = ready, onPay = { payments++; error("Invalid payment") }, onUndo = { Result.success(Unit) }, onDismiss = {})
        } }
        compose.onNodeWithTag("installment.submitPayment").assertIsNotEnabled()
        compose.runOnIdle { ready = true }
        listOf(0L, 100L).forEach { value ->
            compose.runOnIdle { due = row().copy(amountMinor = value) }
            compose.onNodeWithTag("installment.submitPayment").performScrollTo().assertIsNotEnabled()
        }
        compose.runOnIdle { Assert.assertEquals(0, payments) }
    }

    @Test fun skippedRowHasNoPaymentActionWhilePaidRowOffersUndo() {
        var status by mutableStateOf(DueStatus.SKIPPED)
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentDueContent(listOf(row().copy(status = status)), now, ZoneId.systemDefault(), onPayment = {})
        } }
        compose.onNodeWithTag("installment.pay.$id").assertDoesNotExist()
        compose.runOnIdle { status = DueStatus.PAID }
        compose.onNodeWithTag("installment.pay.$id").assertHasClickAction()
    }
    @Test fun changedPaidCycleDisablesUndoAndKeepsExplicitStaleExplanation() {
        var current by mutableStateOf(true); var undo = 0
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentPaymentSheet(owner.value, row().copy(status = DueStatus.PAID), listOf(wallet), targetCurrent = current,
                onPay = { error("Unexpected payment") }, onUndo = { undo++; Result.success(Unit) }, onDismiss = {})
        } }
        compose.runOnIdle { current = false }
        compose.onNodeWithTag("installment.paymentStale").assertExists()
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { Assert.assertEquals(0, undo) }
    }

}
