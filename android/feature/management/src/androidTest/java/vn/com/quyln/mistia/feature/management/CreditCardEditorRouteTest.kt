package vn.com.quyln.mistia.feature.management

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardEditorRouteTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() {
        override fun after() { if (::db.isInitialized) db.close() }
    }).around(compose)
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private lateinit var repo: OfflineFirstFinanceRepository
    private lateinit var card: CreditCardAccount
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-29T00:00:00Z"
    private var activeOwner = owner
    private var dismissed = 0
    private fun id(n: Int) = "33333333-3333-3333-3333-%012d".format(n)
    @Before fun setup() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java).allowMainThreadQueries().build()
        store = RoomLocalStore(db, currentBillOwner = { activeOwner }); repo = OfflineFirstFinanceRepository(store)
        repo.saveWallet(owner, WalletDraft(id = id(1), name = "Owned cash", kind = WalletKind.CASH, currencyCode = "JPY"), device, now).getOrThrow()
        card = repo.saveCreditCard(owner, CreditCardDraft(walletId = id(2), profileId = id(3), name = "Owned card", currencyCode = "JPY", creditLimitMinor = 1375,
            paymentSourceWalletId = id(1)), device, now).getOrThrow()
        activeOwner = other
        repo.saveCreditCard(other, CreditCardDraft(walletId = id(4), profileId = id(5), name = "Private other card", creditLimitMinor = 900), device, now).getOrThrow()
        activeOwner = owner
        Unit
    }
    private fun snapshot() = runBlocking { listOf(owner, other).map { user -> CreditCardAccountReadSnapshot.entities.map { entity ->
        store.recordsIncludingDeleted(user, entity.table) to store.pendingMutations(user, entity, Long.MAX_VALUE)
    } } }
    private fun open(target: String? = card.wallet.id, repository: FinanceRepository = repo,
        selected: () -> UserId = { owner }, deviceProvider: suspend () -> String = { device }, codes: () -> List<String> = { listOf("JPY", "VND") }, restoration: StateRestorationTester? = null) {
        val content: @Composable () -> Unit = {
            var visible by remember { mutableStateOf(true) }
            MistiaTheme(darkTheme = false) { if (visible) CreditCardEditorRoute(selected(), target, repository, deviceProvider, { dismissed++; visible = false }, codes()) }
        }
        if (restoration == null) compose.setContent(content) else restoration.setContent(content)
    }
    private fun waitTag(tag: String) { compose.waitUntil(5000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() } }
    private fun form() { waitTag("card.name") }
    private fun closed() { compose.waitUntil(5000) { dismissed == 1 }; compose.onNodeWithTag("card.name").assertDoesNotExist() }
    private fun save() { compose.onNodeWithTag("card.save").performScrollTo().performClick() }
    private fun cardRows() = runBlocking { store.recordsIncludingDeleted(owner, CloudEntity.LEDGER_WALLET.table).filter { it.payload.financeRawString("kind_raw_value") == "creditCard" } }
    @Test fun editSavesSameWalletAndProfileWithoutDuplicatingAccount() {
        open(); form(); compose.onNodeWithTag("card.name").assertTextContains("Owned card").performTextReplacement("Edited card"); save(); closed()
        assertEquals(1, cardRows().size)
        assertEquals("Edited card", cardRows().single().payload.financeRawString("name"))
        assertEquals(card.profile.id, runBlocking { store.recordsIncludingDeleted(owner, CloudEntity.CREDIT_CARD_PROFILE.table).single().id })
        assertEquals("Private other card", runBlocking { store.recordsIncludingDeleted(other, CloudEntity.LEDGER_WALLET.table).single().payload.financeRawString("name") })
    }
    @Test fun createWaitsForCompleteReadThenSavesOneOwnedPair() {
        val gate = CompletableDeferred<Unit>(); val entered = CompletableDeferred<Unit>()
        val delayed = object : FinanceRepository by repo {
            override fun observeCreditCardAccountReadSnapshot(owner: UserId) = flow { entered.complete(Unit); gate.await(); emitAll(repo.observeCreditCardAccountReadSnapshot(owner)) }
        }
        open(null, delayed); waitTag("card.route.loading"); assertTrue(entered.isCompleted)
        compose.onNodeWithTag("card.name").assertDoesNotExist(); gate.complete(Unit); form()
        compose.onNodeWithTag("card.name").performTextReplacement("New card")
        compose.onNodeWithTag("card.creditLimit").performScrollTo().performTextReplacement("1000"); save(); closed()
        assertEquals(2, cardRows().size)
        assertEquals(2, runBlocking { store.recordsIncludingDeleted(owner, CloudEntity.CREDIT_CARD_PROFILE.table).size })
    }
    @Test fun missingEditTargetClosesWithoutCreatingOrWriting() {
        val before = snapshot(); open(id(80)); closed(); assertEquals(before, snapshot())
    }
    @Test fun foreignEditTargetClosesWithoutShowingOtherAccount() {
        val before = snapshot(); open(id(4)); closed()
        compose.onNodeWithText("Private other card").assertDoesNotExist(); assertEquals(before, snapshot())
    }
    @Test fun archivedTargetClosesWithoutFallingBackToNewCard() {
        runBlocking {
            val row = card.wallet.copy(isArchived = true, archivedAt = now).toCloudRecord()
            db.cloudRecordDao().upsert(CloudRecordEntity(row.ownerUserId, row.entity, row.id, row.payload.toString(), row.updatedAt, row.deletedAt, row.syncVersion, true, 0))
            assertTrue(LedgerWalletRecord.fromCloudRecord(store.record(owner, row.entity, row.id)!!).isArchived)
        }
        val before = snapshot(); open(); closed(); assertEquals(before, snapshot())
    }
    @Test fun disappearingTargetRevokesOpenDraftAndDoesNotCreateReplacement() {
        open(); form(); compose.onNodeWithTag("card.name").performTextReplacement("Unsaved")
        runBlocking { assertEquals(1, db.cloudRecordDao().deleteRecord(owner.value, CloudEntity.CREDIT_CARD_PROFILE.table, card.profile.id)); assertNull(store.record(owner, CloudEntity.CREDIT_CARD_PROFILE.table, card.profile.id)) }
        closed(); assertEquals(1, cardRows().size); assertEquals("Owned card", cardRows().single().payload.financeRawString("name"))
    }
    @Test fun ownerRotationCancelsDeviceAwaitAndCannotSaveOldDraft() {
        var selected by mutableStateOf(owner); val entered = CompletableDeferred<Unit>(); val cancelled = CompletableDeferred<Unit>(); val gate = CompletableDeferred<Unit>()
        var writes = 0
        val observed = object : FinanceRepository by repo {
            override suspend fun saveCreditCard(ownerUserId: UserId, draft: CreditCardDraft, deviceId: String, now: String): Result<CreditCardAccount> {
                writes++; return repo.saveCreditCard(ownerUserId, draft, deviceId, now)
            }
        }
        val before = snapshot()
        open(repository = observed, selected = { selected }, deviceProvider = { entered.complete(Unit); try { gate.await(); device } finally { cancelled.complete(Unit) } })
        form(); compose.onNodeWithTag("card.name").performTextReplacement("Old draft"); save()
        compose.waitUntil(5000) { entered.isCompleted }; compose.runOnIdle { activeOwner = other; selected = other }
        compose.waitUntil(5000) { cancelled.isCompleted }; gate.complete(Unit); closed()
        assertEquals(0, writes); assertEquals(before, snapshot())
    }
    @Test fun cancellationIgnoringDeviceProviderStillCannotPersistAfterOwnerRotation() {
        var selected by mutableStateOf(owner); val entered = CompletableDeferred<Unit>(); val finished = CompletableDeferred<Unit>(); val gate = CompletableDeferred<Unit>()
        val before = snapshot()
        open(selected = { selected }, deviceProvider = { entered.complete(Unit); withContext(NonCancellable) { gate.await() }; finished.complete(Unit); device })
        form(); save(); compose.waitUntil(5000) { entered.isCompleted }; compose.runOnIdle { activeOwner = other; selected = other }; gate.complete(Unit)
        compose.waitUntil(5000) { finished.isCompleted }; closed(); assertEquals(before, snapshot())
    }
    @Test fun deviceFailureIsRecoverableAndRetrySavesOnce() {
        var calls = 0
        open(deviceProvider = { calls++; if (calls == 1) throw IOException("private device failure"); device })
        form(); save()
        compose.waitUntil(5000) { calls == 1 && compose.onAllNodesWithTag("card.save").fetchSemanticsNodes().any { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.Disabled).not() } }
        compose.onNodeWithText("private device failure").assertDoesNotExist(); save(); closed(); assertEquals(2, calls); assertEquals(1, cardRows().size)
    }
    @Test fun failedReadCanRetryAndNeverPresentsAnEmptyCreationForm() {
        var reads = 0
        val failing = object : FinanceRepository by repo {
            override fun observeCreditCardAccountReadSnapshot(owner: UserId): Flow<CreditCardAccountReadSnapshot> {
                reads++; return if (reads == 1) flow { throw IOException("private query") } else repo.observeCreditCardAccountReadSnapshot(owner)
            }
        }
        val before = snapshot(); open(null, failing); waitTag("card.route.error")
        compose.onNodeWithTag("card.name").assertDoesNotExist(); compose.onNodeWithText("private query").assertDoesNotExist()
        compose.onNodeWithTag("card.route.retry").performClick(); form(); assertEquals(2, reads); assertEquals(before, snapshot())
    }
    @Test fun tombstonedArchivedHistoryLocksCurrencyUntilRawReferencesAreRemoved() {
        runBlocking {
            val raw = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, id(10), owner.value, buildJsonObject {
                put("id", id(10)); put("user_id", owner.value); put("source_wallet_id", card.wallet.id); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
                put("amount_minor", 100); put("source_currency_code", "JPY"); put("created_at", now); put("updated_at", now); put("occurred_at", now)
                put("created_by_user_id", owner.value); put("last_modified_by_user_id", owner.value); put("deleted_at", now); put("is_archived", true); put("sync_version", 0)
            }, now, now, 0)
            store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, listOf(LedgerTransactionRecord.fromCloudRecord(raw).toCloudRecord()))
        }
        open(); form(); compose.onNodeWithTag("card.currency.VND").performScrollTo().assertIsNotEnabled()
        runBlocking { store.replacePullSnapshot(owner, CloudEntity.LEDGER_TRANSACTION.table, emptyList()) }
        compose.waitUntil(5000) { compose.onAllNodes(hasTestTag("card.currency.VND") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("card.currency.VND").performClick(); save(); closed(); assertEquals("VND", cardRows().single().payload.financeRawString("currency_code"))
    }
    @Test fun newerProfileReadCannotBeOverwrittenByTheOpenOldDraft() {
        open(); form(); compose.onNodeWithTag("card.name").performTextReplacement("Old draft")
        runBlocking { repo.saveCreditCard(owner, CreditCardDraft(walletId = card.wallet.id, profileId = card.profile.id,
            name = "Newer remote card", issuerName = "New issuer", creditLimitMinor = 5000), device, now).getOrThrow() }
        val before = snapshot(); save()
        compose.waitUntil(5000) { compose.onAllNodes(hasTestTag("card.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("card.name").assertExists(); assertEquals(0, dismissed); assertEquals(before, snapshot())
    }
    @Test fun repositoryReadGapCannotRebaseTheOldDraftOntoNewerData() {
        val observed = object : FinanceRepository by repo {
            override suspend fun saveCreditCard(ownerUserId: UserId, draft: CreditCardDraft, deviceId: String, now: String): Result<CreditCardAccount> {
                repo.saveCreditCard(ownerUserId, CreditCardDraft(walletId = card.wallet.id, profileId = card.profile.id,
                    name = "Won before repository read", creditLimitMinor = 7000), deviceId, now).getOrThrow()
                return repo.saveCreditCard(ownerUserId, draft, deviceId, now)
            }
        }
        open(repository = observed); form(); save()
        compose.waitUntil(5000) { cardRows().single().payload.financeRawString("name") == "Won before repository read" }
        compose.onNodeWithTag("card.save").assertIsEnabled(); assertEquals(0, dismissed)
        assertEquals(7000L, runBlocking { store.recordsIncludingDeleted(owner, CloudEntity.CREDIT_CARD_PROFILE.table).single().payload.financeRawLong("credit_limit_minor") })
    }
    @Test fun restoredDraftRetainsItsOriginalComparisonGeneration() {
        val restoration = StateRestorationTester(compose)
        open(restoration = restoration); form(); compose.onNodeWithTag("card.name").performTextReplacement("Restored old draft")
        runBlocking { repo.saveCreditCard(owner, CreditCardDraft(walletId = card.wallet.id, profileId = card.profile.id,
            name = "Newer after restore", creditLimitMinor = 6000), device, now).getOrThrow() }
        val before = snapshot(); restoration.emulateSavedInstanceStateRestore(); form()
        compose.onNodeWithTag("card.name").assertTextContains("Restored old draft"); save()
        compose.onNodeWithTag("card.save").assertIsEnabled(); assertEquals(0, dismissed); assertEquals(before, snapshot())
    }
    @Test fun retryAfterCommittedResultWasLostDoesNotDuplicateANewCard() {
        var calls = 0
        val observed = object : FinanceRepository by repo {
            override suspend fun saveCreditCard(ownerUserId: UserId, draft: CreditCardDraft, deviceId: String, now: String): Result<CreditCardAccount> {
                val saved = repo.saveCreditCard(ownerUserId, draft, deviceId, now); calls++
                return if (calls == 1 && saved.isSuccess) Result.failure(IOException("lost result")) else saved
            }
        }
        open(null, observed); form(); compose.onNodeWithTag("card.name").performTextReplacement("Retry card")
        compose.onNodeWithTag("card.creditLimit").performScrollTo().performTextReplacement("1000"); save()
        compose.waitUntil(5000) { calls == 1 }; compose.onNodeWithTag("card.save").assertIsEnabled(); assertEquals(2, cardRows().size)
        save(); closed(); assertEquals(2, calls); assertEquals(2, cardRows().size)
        assertEquals(2, runBlocking { store.recordsIncludingDeleted(owner, CloudEntity.CREDIT_CARD_PROFILE.table).size })
    }
    @Test fun enabledCurrenciesUpdateWithoutDiscardingTheCurrentDraft() {
        var codes by mutableStateOf(listOf("JPY", "VND"))
        open(codes = { codes }); form(); compose.onNodeWithTag("card.name").performTextReplacement("Kept draft")
        compose.runOnIdle { codes = listOf("VND") }
        compose.onNodeWithTag("card.currency.JPY").assertDoesNotExist(); compose.onNodeWithTag("card.currentCurrency").performScrollTo().assertTextEquals("JPY")
        compose.onNodeWithTag("card.name").performScrollTo().assertTextContains("Kept draft")
        save(); closed(); assertEquals("JPY", cardRows().single().payload.financeRawString("currency_code"))
    }
}
