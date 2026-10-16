package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.time.YearMonth
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

/** Synthetic owner and in-memory Room; no network or authentication session. */
@RunWith(AndroidJUnit4::class)
class InstallmentEditorWorkflowTest {
    private val compose = createComposeRule()
    // Room collectors belong to the Compose rule; dispose it before closing its database.
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() {
        override fun after() { if (::db.isInitialized) db.close() }
    }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var wallet: LedgerWalletRecord
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val now = Instant.parse("2026-10-14T00:00:00Z")
    private val month = YearMonth.of(2026, 10)
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java)
            .allowMainThreadQueries().build()
        store = RoomLocalStore(db); repo = OfflineFirstFinanceRepository(store)
        wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY"), device, now.toString()).getOrThrow()
    }

    private fun plans() = runBlocking { repo.observeInstallments(owner).first() }
    private fun enterDraft(name: String = "Loan", amount: String = "9007199254740993") {
        compose.onNodeWithTag("installment.name").performTextReplacement(name)
        compose.onNodeWithTag("installment.amountInput").performTextReplacement(amount)
        compose.onNodeWithTag("installment.wallet").performScrollTo().performClick()
        compose.onNodeWithTag("installment.pickWallet.${wallet.id}").performClick()
    }
    private fun original() = runBlocking {
        wallet = repo.saveWallet(owner, WalletDraft(id = wallet.id, name = "Cash", kind = WalletKind.CASH, currencyCode = "USD"), device, now.toString()).getOrThrow()
        repo.saveInstallment(owner, InstallmentDraft(id, "Original", 1375, 15, 1, 12, wallet.id, "USD"), device, now.toString()).getOrThrow()
    }

    @Test fun nativeCreateEditDeletePersistExactAmountAndOutboxWithoutLedgerMovement() {
        compose.setContent { MistiaTheme(darkTheme = false) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                InstallmentDuePane(owner, repo, month, { device }, now = { now })
            }
        } }
        compose.onNodeWithTag("installment.add").performScrollTo().performClick()
        enterDraft()
        compose.onNodeWithTag("installment.cycles").performScrollTo().performTextReplacement("12")
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) { plans().size == 1 }
        val plan = plans().single()
        Assert.assertEquals(9007199254740993L, plan.amountPerCycleMinor)
        compose.waitUntil(5000) { compose.onAllNodesWithTag("installment.editor").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("installment.edit.${plan.id}").performScrollTo().performClick()
        compose.onNodeWithTag("installment.name").performTextReplacement("Edited")
        compose.onNodeWithTag("installment.cycles").performScrollTo().performTextClearance()
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) { plans().single().name == "Edited" && plans().single().totalCycles == null }
        compose.waitUntil(5000) { compose.onAllNodesWithTag("installment.editor").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("installment.edit.${plan.id}").performScrollTo().performClick()
        compose.onNodeWithTag("installment.delete").performScrollTo().performClick()
        Assert.assertEquals(1, plans().size)
        compose.onNodeWithTag("installment.confirmDelete").performClick()
        compose.waitUntil(5000) { plans().isEmpty() }
        Assert.assertNotNull(runBlocking { store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, plan.id) }!!.deletedAt)
        Assert.assertEquals(MutationKind.DELETE, runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).single().mutation.kind })
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertEquals(wallet, runBlocking { repo.observeWallets(owner).first().single() })
    }

    @Test fun draftSurvivesRepositoryRecreationAndMonthChangeThenSavesOnce() {
        val restoration = StateRestorationTester(compose)
        var constructions = 0
        var selectedMonth by mutableStateOf(month)
        restoration.setContent {
            val recreatedRepository = remember { constructions++; OfflineFirstFinanceRepository(store) }
            MistiaTheme(darkTheme = false) {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    InstallmentDuePane(owner, recreatedRepository, selectedMonth, { device }, now = { now })
                }
            }
        }
        compose.onNodeWithTag("installment.add").performClick()
        enterDraft("Unsaved")
        compose.runOnIdle { selectedMonth = month.plusMonths(1) }
        compose.onNodeWithTag("installment.name").assertTextContains("Unsaved")
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle { Assert.assertEquals(2, constructions) }
        compose.onNodeWithTag("installment.name").assertTextContains("Unsaved")
        compose.onNodeWithTag("installment.amountInput").assertTextContains("9,007,199,254,740,993")
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) { plans().size == 1 }
        Assert.assertEquals("Unsaved", plans().single().name)
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).size })
    }

    @Test fun switchingOwnerRemovesOldEditorAndUnsavedName() {
        var subject by mutableStateOf(owner)
        compose.setContent { MistiaTheme(darkTheme = false) { InstallmentDuePane(subject, repo, month, { device }, now = { now }) } }
        compose.onNodeWithTag("installment.add").performClick()
        compose.onNodeWithTag("installment.name").performTextReplacement("Private draft")
        compose.runOnIdle { subject = other }
        compose.onNodeWithTag("installment.editor").assertDoesNotExist()
        compose.onNodeWithText("Private draft").assertDoesNotExist()
        Assert.assertTrue(plans().isEmpty())
    }

    @Test fun walletPickerReleasesAmountFocusAndPreservesUnsavedInstallmentDraft() {
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentEditorSheet(owner.value, id, null, "JPY", listOf(wallet),
                onSave = { error("Save was not requested") }, onDelete = { Result.success(Unit) }, onDismiss = {})
        } }
        compose.onNodeWithTag("installment.name").performTextReplacement("Draft")
        compose.onNodeWithTag("installment.amountInput").performScrollTo().performTextReplacement("9007199254740993")
        compose.onNodeWithTag("installment.amountInput").assertIsFocused()
        compose.onNodeWithTag("installment.wallet").performScrollTo().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick) { it() }
        compose.onNodeWithTag("installment.pickWallet.${wallet.id}").performClick()
        compose.onNodeWithTag("installment.amountInput").assertIsNotFocused().assertTextContains("9,007,199,254,740,993")
        compose.onNodeWithTag("installment.name").assertTextContains("Draft")
        Assert.assertTrue(plans().isEmpty())
        Assert.assertTrue(runBlocking { store.pendingMutations(owner, CloudEntity.INSTALLMENT_PLAN, Long.MAX_VALUE).isEmpty() })
    }

    @Test fun failedSaveRetainsDraftAndDirtyCloseRequiresExplicitDiscardInLargeFontDarkMode() {
        var dismissed = false
        var attempts = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.3f)) { MistiaTheme(darkTheme = true) {
                InstallmentEditorSheet(owner.value, id, null, "JPY", listOf(wallet),
                    onSave = { attempts++; Result.failure(IllegalStateException("fixture")) }, onDelete = { Result.success(Unit) }, onDismiss = { dismissed = true })
            } }
        }
        enterDraft()
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        try { compose.onNodeWithTag("installment.editorError").assertExists() } catch (failure: AssertionError) {
            android.util.Log.e("MistiaInstallmentDiagnostic", "save attempts=$attempts")
            val roots=compose.onAllNodes(isRoot()).fetchSemanticsNodes()
            for(index in roots.indices) runCatching { android.util.Log.e("MistiaInstallmentDiagnostic",compose.onAllNodes(isRoot())[index].printToString()) }
            val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),"installment-save-failure.png").outputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}
                bitmap.recycle()
            }
            throw failure
        }
        compose.onNodeWithTag("installment.amountInput").assertTextContains("9,007,199,254,740,993")
        compose.onNodeWithTag("installment.close").performScrollTo().performClick()
        Assert.assertFalse(dismissed)
        compose.onNodeWithTag("installment.keepEditing").performClick()
        compose.onNodeWithTag("installment.name").assertTextContains("Loan")
        compose.onNodeWithTag("installment.close").performScrollTo().performClick()
        compose.onNodeWithTag("installment.discard").performClick()
        compose.runOnIdle { Assert.assertTrue(dismissed) }
    }

    @Test fun deleteConfirmationUsesOriginalBaselineAndDoesNotSaveUnsavedChanges() {
        val original = original()
        var deleted: InstallmentPlanRecord? = null
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentEditorSheet(owner.value, id, original, "USD", listOf(wallet),
                onSave = { error("Delete must not save the draft") }, onDelete = { deleted = it; Result.success(Unit) }, onDismiss = {})
        } }
        compose.onNodeWithTag("installment.name").performTextReplacement("Unsaved rename")
        compose.onNodeWithTag("installment.delete").performScrollTo().performClick()
        compose.runOnIdle { Assert.assertNull(deleted) }
        compose.onNodeWithTag("installment.confirmDelete").performClick()
        compose.runOnIdle { Assert.assertEquals(original, deleted) }
    }

    @Test fun inFlightSaveDisablesDuplicateAndCloseAndKeepsFrozenCurrencyAndExactMinorInput() {
        val original = original()
        val release = CompletableDeferred<Unit>()
        var saves = 0; var dismissed = false; var saved: InstallmentDraft? = null
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentEditorSheet(owner.value, id, original, "USD", listOf(wallet),
                onSave = { saves++; saved = it; release.await(); Result.success(original) },
                onDelete = { Result.success(Unit) }, onDismiss = { dismissed = true })
        } }
        compose.onNodeWithTag("installment.amountInput").performTextReplacement("9007199254740993")
        compose.onNodeWithTag("installment.cycles").performScrollTo().performTextClearance()
        compose.onNodeWithTag("installment.save").performScrollTo().performClick().assertIsNotEnabled()
        compose.onNodeWithTag("installment.close").assertIsNotEnabled()
        compose.runOnIdle {
            Assert.assertEquals(1, saves); Assert.assertFalse(dismissed)
            Assert.assertEquals("USD", saved!!.currencyCode)
            Assert.assertEquals(9007199254740993L, saved!!.amountPerCycleMinor)
            Assert.assertNull(saved!!.totalCycles); Assert.assertEquals(original, saved!!.expected)
            release.complete(Unit)
        }
        compose.waitUntil(5000) { dismissed }
    }

    @Test fun pickerRetainsOriginalArchivedWalletButExcludesCardForeignAndNewArchive() {
        val original = original()
        val records = listOf(wallet.copy(isArchived = true), wallet.copy(id = device, isArchived = true),
            wallet.copy(id = id, kindWireValue = "creditCard"), wallet.copy(id = other.value, ownerUserId = other.value))
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentEditorSheet(owner.value, id, original, "USD", records,
                onSave = { Result.success(original) }, onDelete = { Result.success(Unit) }, onDismiss = {})
        } }
        compose.onNodeWithTag("installment.wallet").performScrollTo().performClick()
        compose.onNodeWithTag("installment.pickWallet.${wallet.id}").assertExists()
        listOf(device, id, other.value).forEach { compose.onNodeWithTag("installment.pickWallet.$it").assertDoesNotExist() }
        compose.onNodeWithTag("installment.pickWallet.${wallet.id}").performClick()
        compose.onNodeWithTag("installment.icon").performScrollTo().performClick()
        compose.onNodeWithTag("installment.pickIcon.mistia.plan.loan").performClick()
    }
    @Test fun skipUndoNativeConfirmationPersistsOnlyOccurrenceAndOutbox() {
        val source = original()
        compose.setContent { MistiaTheme(darkTheme = false) {
            Column(Modifier.verticalScroll(rememberScrollState())) { InstallmentDuePane(owner, repo, month, { device }, now = { now }) }
        } }
        compose.onNodeWithTag("installment.skip.${source.id}").performScrollTo().performClick()
        Assert.assertTrue(runBlocking { repo.observeDueOccurrences(owner).first().isEmpty() })
        compose.onNodeWithTag("installment.confirmCycle").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeDueOccurrences(owner).first().any { it.status == DueStatus.SKIPPED } } }
        compose.waitUntil(5000) { compose.onAllNodesWithTag("installment.confirmCycle").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("installment.status.${source.id}").assertExists()
        compose.onNodeWithTag("installment.skip.${source.id}").performScrollTo().performClick()
        compose.onNodeWithTag("installment.confirmCycle").performClick()
        compose.waitUntil(5000) { runBlocking { repo.observeDueOccurrences(owner).first().isEmpty() } }
        Assert.assertEquals(MutationKind.DELETE, runBlocking { store.pendingMutations(owner, CloudEntity.DUE_OCCURRENCE_RECORD, Long.MAX_VALUE).single().mutation.kind })
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
        Assert.assertEquals(source, plans().single())
    }

    @Test fun paidRowOffersMetadataEditButNoSkipAction() {
        val source = original()
        val paid = installmentDueRows(owner, listOf(source), emptyList(), month, java.time.ZoneId.systemDefault()).single().copy(status = DueStatus.PAID)
        compose.setContent { MistiaTheme(darkTheme = false) {
            InstallmentDueContent(listOf(paid), now, java.time.ZoneId.systemDefault(), onEdit = {}, onCycle = { error("Paid action forbidden") })
        } }
        compose.onNodeWithTag("installment.edit.${source.id}").assertHasClickAction()
        compose.onNodeWithTag("installment.skip.${source.id}").assertDoesNotExist()
    }

    @Test fun lateNonCancellableResultAfterMonthChangeCannotDismissNewConfirmation() {
        val source = original(); val release = CompletableDeferred<Unit>()
        var selected by mutableStateOf(month)
        val controlled = object : FinanceRepository by repo {
            override suspend fun skipInstallment(owner: UserId, expected: InstallmentPlanRecord, month: YearMonth, deviceId: String, now: String): Result<DueOccurrenceRecord> =
                withContext(NonCancellable) {
                    release.await()
                    Result.success(DueOccurrenceRecord(device, owner.value, "installment", expected.id, month.toString(), now, null, "skipped", null, null, now, now, null, 0, deviceId))
                }
        }
        compose.setContent { MistiaTheme(darkTheme = false) {
            Column(Modifier.verticalScroll(rememberScrollState())) { InstallmentDuePane(owner, controlled, selected, { device }, now = { now }) }
        } }
        compose.onNodeWithTag("installment.skip.${source.id}").performScrollTo().performClick()
        compose.onNodeWithTag("installment.confirmCycle").performClick().assertIsNotEnabled()
        compose.onNodeWithTag("installment.cancelCycle").assertIsNotEnabled()
        compose.runOnIdle { selected = month.plusMonths(1) }
        compose.onNodeWithTag("installment.confirmCycle").assertDoesNotExist()
        compose.onNodeWithTag("installment.skip.${source.id}").performScrollTo().performClick()
        compose.runOnIdle { release.complete(Unit) }
        compose.onNodeWithTag("installment.confirmCycle").assertExists().assertIsEnabled()
        compose.onNodeWithTag("installment.cancelCycle").performClick()
        Assert.assertTrue(runBlocking { repo.observeDueOccurrences(owner).first().isEmpty() })
    }

    @Test fun differentlyDenominatedPreferredWalletIsHiddenAndCannotSubmitRestoredEditor() {
        val source = original(); val wrongCurrency = wallet.copy(currencyCode = "JPY")
        var saves = 0
        val restoration = StateRestorationTester(compose)
        restoration.setContent { MistiaTheme(darkTheme = false) {
            InstallmentEditorSheet(owner.value, id, source, "USD", listOf(wrongCurrency), onSave = { saves++; Result.success(source) }, onDelete = { Result.success(Unit) }, onDismiss = {})
        } }
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("installment.wallet").performScrollTo().performClick()
        compose.onNodeWithTag("installment.pickWallet.${wallet.id}").assertDoesNotExist()
        compose.onNodeWithText(ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.planning_planning_choose_wallet)).performClick()
        compose.onNodeWithTag("installment.save").performScrollTo().performClick()
        compose.runOnIdle { Assert.assertEquals(0, saves) }
        compose.onNodeWithTag("installment.editorError").assertExists()
    }

}
