package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.feature.overview.OverviewScreen

/** Test-only cross-feature composition mirrors MainActivity with actual local Room payments. */
@RunWith(AndroidJUnit4::class)
class OverviewDuePaymentRouteTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var category:TransactionCategoryRecord
    private lateinit var wallet:LedgerWalletRecord
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val zone=ZoneId.systemDefault()
    private val month=YearMonth.now(zone)
    private val today=LocalDate.now(zone)
    private val now=Instant.now().toString()
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    @Before fun setup()=runBlocking<Unit> {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db)
        val catalog=systemCategoryCatalog(context);repo=OfflineFirstFinanceRepository(store,zone,catalog)
        repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        category=repo.observeCategories(owner).first().first {it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.CHILD}
        wallet=repo.saveWallet(owner,WalletDraft(name="Dollar cash",kind=WalletKind.CASH,currencyCode="USD",openingBalanceMinor=10000),device,now).getOrThrow()
        repo.saveWallet(owner,WalletDraft(name="Wrong currency",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=10000),device,now).getOrThrow()
    }
    private fun bill(amount:Long?=1375)=runBlocking {repo.saveRecurringBill(owner,RecurringBillDraft("Internet",category.id,amount,wallet.id,"USD",paymentStartDay=today.dayOfMonth,zoneId=zone),device,now).getOrThrow()}
    private fun installment()=runBlocking {repo.saveInstallment(owner,InstallmentDraft("33333333-3333-3333-3333-333333333333","Loan",1375,today.dayOfMonth,1,12,wallet.id,"USD"),device,now).getOrThrow()}
    @Composable private fun Screen(source:FinanceRepository=repo) {
        var token by rememberSaveable(owner.value) {mutableStateOf<String?>(null)}
        val target=UpcomingDuePaymentTarget.restore(owner,token)
        MistiaTheme(darkTheme=false) {
            OverviewScreen(owner,source,sync,onOpenRecurringDue={token=it.navigationToken()},overlayPresented=target!=null)
            if(target!=null) UpcomingRecurringPaymentSheet(owner,target,source,{device},onDismiss={token=null})
        }
    }
    private fun open(kind:DueSourceKind,id:String,prefix:String) {
        val tag="overview.due.row.${kind.wireValue}-$id-$month"
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasTestTag("overview.due.section"))
        compose.waitUntil(5000) {compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag).performScrollTo().performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("$prefix.paymentSheet").fetchSemanticsNodes().isNotEmpty()}
    }
    private fun pay(prefix:String) {
        compose.onNodeWithTag("$prefix.submitPayment").performScrollTo().performClick()
        Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()})
        compose.onNodeWithTag("$prefix.confirmPayment").performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeDueOccurrences(owner).first().singleOrNull()?.status==DueStatus.PAID}}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("$prefix.paymentSheet").fetchSemanticsNodes().isEmpty()}
    }
    private fun assertPaid(kind:DueSourceKind,id:String) =runBlocking {
        val tx=repo.observeTransactions(owner).first().single();val cycle=repo.observeDueOccurrences(owner).first().single()
        Assert.assertEquals(1375L,tx.amountMinor);Assert.assertEquals("USD",tx.sourceCurrencyCode)
        Assert.assertEquals(kind,cycle.sourceKind);Assert.assertEquals(id,cycle.sourceId);Assert.assertEquals(month.toString(),cycle.selectedMonthKey)
        Assert.assertEquals(1375L,cycle.amountMinorSnapshot);Assert.assertEquals(tx.id,cycle.linkedTransactionId)
        val fresh=repo.observeWallets(owner).first().single {it.id==wallet.id}
        Assert.assertEquals(10000L,fresh.openingBalanceMinor)
        Assert.assertEquals(8625L,TransactionWalletBalanceIndex(listOf(fresh),listOf(tx)).balance(fresh.id))
        Assert.assertEquals(1,store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).size)
        Assert.assertEquals(1,store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).size)
    }
    private fun seed(row:CloudRecord)=runBlocking {store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))}
    private fun rowsAndQueue()=runBlocking {CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Test fun billTapPaysTheOriginalCycleAndUsesOnlyItsOwnCurrency() {
        val bill=bill();compose.setContent {Screen()};open(DueSourceKind.RECURRING_BILL,bill.id,"bill")
        compose.onNodeWithTag("bill.paymentWallet").performScrollTo().performClick()
        compose.onNodeWithTag("bill.payWallet.${wallet.id}").assertExists();compose.onNodeWithText("Wrong currency · JPY").assertDoesNotExist()
        compose.onNodeWithTag("bill.payWallet.${wallet.id}").performClick();pay("bill");assertPaid(DueSourceKind.RECURRING_BILL,bill.id)
    }
    @Test fun variableBillDraftAndIdentifierRouteSurviveRestoreAndPayExactEnteredMinor() {
        val bill=bill(null);val restoration=StateRestorationTester(compose)
        restoration.setContent {Screen()};open(DueSourceKind.RECURRING_BILL,bill.id,"bill")
        compose.onNodeWithTag("bill.paymentAmount").performTextInput("13.75")
        restoration.emulateSavedInstanceStateRestore()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.paymentAmount").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("bill.paymentAmount").assertTextContains("13.75");pay("bill");assertPaid(DueSourceKind.RECURRING_BILL,bill.id)
    }
    @Test fun installmentTapPaysTheOriginalPlanWithoutRewritingOpeningBalance() {
        val plan=installment();compose.setContent {Screen()};open(DueSourceKind.INSTALLMENT,plan.id,"installment")
        compose.onNodeWithTag("installment.paymentWallet").performScrollTo().performClick()
        compose.onNodeWithTag("installment.payWallet.${wallet.id}").assertExists();compose.onNodeWithText("Wrong currency · JPY").assertDoesNotExist()
        compose.onNodeWithTag("installment.payWallet.${wallet.id}").performClick();pay("installment");assertPaid(DueSourceKind.INSTALLMENT,plan.id)
    }
    @Test fun aBillPaidElsewhereWhileConfirmationIsOpenCannotTurnIntoUndoOrPayAgain() {
        val bill=bill();compose.setContent {Screen()};open(DueSourceKind.RECURRING_BILL,bill.id,"bill")
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick()
        runBlocking {repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).getOrThrow()}
        val before=rowsAndQueue()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.paymentStale").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("bill.confirmPayment").assertIsNotEnabled()
        compose.onNodeWithTag("bill.confirmationAmount").assertTextEquals("—")
        Assert.assertEquals(before,rowsAndQueue())
    }
    @Test fun anInstallmentPaidElsewhereCannotTurnTheOriginalPayTargetIntoUndo() {
        val plan=installment();compose.setContent {Screen()};open(DueSourceKind.INSTALLMENT,plan.id,"installment")
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick()
        runBlocking {repo.payInstallment(owner,InstallmentPaymentRequest(plan,month,RecordId(wallet.id)),device,now).getOrThrow()}
        val before=rowsAndQueue()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("installment.paymentStale").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("installment.confirmPayment").assertIsNotEnabled()
        compose.onNodeWithTag("installment.undoAmount").assertDoesNotExist()
        Assert.assertEquals(before,rowsAndQueue())
    }
    @Test fun loadedReadFailureDisablesVariableBillDraftAndRetryKeepsTheEnteredAmount() {
        val bill=bill(null);val release=kotlinx.coroutines.CompletableDeferred<Unit>()
        val reads=java.util.concurrent.atomic.AtomicInteger()
        val source=object:FinanceRepository by repo {
            override fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<UpcomingDueReadSnapshot> = flow {
                if(reads.incrementAndGet()<=2) {emit(repo.observeUpcomingDueReadSnapshot(owner).first());release.await();error("test read failed")}
                emitAll(repo.observeUpcomingDueReadSnapshot(owner))
            }
        }
        compose.setContent {Screen(source)};open(DueSourceKind.RECURRING_BILL,bill.id,"bill")
        compose.onNodeWithTag("bill.paymentAmount").performTextInput("13.75")
        val before=rowsAndQueue();compose.runOnIdle {release.complete(Unit)}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.paymentRetry").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("bill.submitPayment").assertIsNotEnabled()
        compose.onNodeWithTag("bill.paymentAmount").assertTextContains("13.75").assertIsNotEnabled()
        Assert.assertEquals(before,rowsAndQueue())
        compose.onNodeWithTag("bill.paymentRetry").performScrollTo().performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.paymentRetry").fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithTag("bill.paymentAmount").assertTextContains("13.75").assertIsEnabled()
        pay("bill");assertPaid(DueSourceKind.RECURRING_BILL,bill.id)
    }
    @Test fun restoredPaidOrMissingSourceHasAnExplicitUnavailableDialogAndNoPaymentOrCreateSheet() {
        val bill=bill();runBlocking {repo.payRecurringBill(owner,BillPaymentRequest(RecordId(bill.id),month,expectedBill=bill),device,now).getOrThrow()}
        val before=rowsAndQueue();var id by mutableStateOf(bill.id)
        compose.setContent {MistiaTheme(darkTheme=false) {UpcomingRecurringPaymentSheet(owner,UpcomingDuePaymentTarget(owner.value,DueSourceKind.RECURRING_BILL,id,month),repo,{device},{})}}
        compose.waitUntil(5000) {compose.onAllNodesWithText(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.planning_duepayment_could_not_find_the_due_item)).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("bill.paymentSheet").assertDoesNotExist()
        compose.runOnIdle {id="44444444-4444-4444-4444-444444444444"}
        compose.waitUntil(5000) {compose.onAllNodesWithText(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.planning_duepayment_could_not_find_the_due_item)).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("bill.paymentSheet").assertDoesNotExist();Assert.assertEquals(before,rowsAndQueue())
    }
    @Test fun unreadableWalletCurrencyHoldsPaymentInsteadOfInventingEligibility() {
        val bill=bill();seed(wallet.toCloudRecord().let {it.copy(payload=JsonObject(it.payload+("currency_code" to JsonPrimitive(1375))))})
        val before=rowsAndQueue();compose.setContent {Screen()}
        val tag="overview.due.row.recurringBill-${bill.id}-$month"
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasTestTag("overview.due.section"))
        compose.waitUntil(5000) {compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag).performScrollTo().performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("upcoming.paymentRetry").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("bill.paymentSheet").assertDoesNotExist();Assert.assertEquals(before,rowsAndQueue())
    }

}
