package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
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
class OwnedBillEditorTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var category:TransactionCategoryRecord
    private lateinit var categories:List<TransactionCategoryRecord>
    private lateinit var wallets:List<LedgerWalletRecord>
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val exchange=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    private fun now()=Instant.now().toString()
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        category=seedCategory(owner);categories=repo.observeBudgetCategories(owner).first()
        wallets=listOf("JPY","VND","USD").map {code -> repo.saveWallet(owner,WalletDraft(name="Cash $code",kind=WalletKind.CASH,currencyCode=code),device,now()).getOrThrow()}
    }
    private suspend fun seedCategory(subject:UserId):TransactionCategoryRecord {
        val parent=repo.saveCategory(subject,CategoryDraft(name="Home",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now()).getOrThrow()
        val child=repo.saveCategory(subject,CategoryDraft(name="Rent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now()).getOrThrow().copy(systemKey="rent")
        store.commitMutation(child.toCloudRecord(),PendingMutation(CloudEntity.TRANSACTION_CATEGORY,child.id,subject.value,MutationKind.UPSERT,child.toPayload(),child.updatedAt,child.syncVersion,device))
        return child
    }
    private fun bills(subject:UserId=owner)=runBlocking {repo.observeRecurringBills(subject).first()}
    private fun wallet(code:String)=wallets.single {it.currencyCode==code}
    private fun seed(subject:UserId=owner,name:String="Original",code:String="JPY",amount:Long=9007199254740993L)=runBlocking {
        val c=if(subject==owner) category else seedCategory(subject)
        val w=if(subject==owner) wallet(code) else repo.saveWallet(subject,WalletDraft(name="Foreign cash",kind=WalletKind.CASH,currencyCode=code),device,now()).getOrThrow()
        repo.saveRecurringBill(subject,RecurringBillDraft(name,c.id,amount,w.id,code),device,now()).getOrThrow()
    }
    @Composable private fun Screen(primary:String,dark:Boolean=false) {MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
        PlanningScreen(owner,repo,modifier=Modifier.padding(padding),deviceIdProvider={device},exchangeRateRepository=exchange,primaryCurrencyCode=primary)
    }}}
    @Composable private fun Editor(subject:UserId=owner,original:RecurringBillPlanRecord?=null,
        save:suspend (RecurringBillDraft)->Result<RecurringBillPlanRecord> = {repo.saveRecurringBill(subject,it,device,now())},
        pause:suspend (String)->Result<Unit> = {repo.pauseRecurringBill(subject,RecordId(it),device,now())},dismiss:()->Unit={},
    ) {MistiaTheme(darkTheme=false) {RecurringBillEditorSheet(subject.value,original,categories,wallets,CategoryNameLanguage.ENGLISH,
        onSave=save,onPause=pause,onResume={repo.resumeRecurringBill(subject,RecordId(it),device,now())},onArchive={repo.archiveRecurringBill(subject,RecordId(it),device,now())},onDismiss=dismiss)}}
    private fun tag(name:String)=compose.onNodeWithTag(name)
    private fun newBill() {tag("planning.tab.1").performClick();tag("bill.add").performScrollTo().performClick()}
    private fun amount(text:String) {tag("bill.amount").performScrollTo().performTextReplacement(text)}
    private fun currency(code:String) {compose.onAllNodesWithText(code,useUnmergedTree=true).assertCountEquals(1)}
    private fun key(value:String) {tag("amountCalculator.key.$value").performClick()}
    private fun details(code:String="JPY") {
        tag("bill.name").performTextReplacement("Rent")
        tag("bill.category").performClick();tag("bill.category.${category.id}").performClick()
        tag("bill.wallet").performScrollTo().performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.wallet.${wallet(code).id}").fetchSemanticsNodes().isNotEmpty()}
        tag("bill.wallet.${wallet(code).id}").performClick()
        tag("bill.wallet").assertTextContains(wallet(code).name,substring=true)
        tag("bill.category").assertTextContains(category.localizedBudgetName(CategoryNameLanguage.ENGLISH),substring=true)
    }
    @Test fun realPlanningCreatesExactVndBillWithSameCurrencyWalletAndOutbox() {
        compose.setContent {Screen(" vnd ")};newBill()
        tag("bill.name").performTextReplacement("Rent");amount("9007199254740993");currency("VND")
        tag("bill.category").performScrollTo().performClick();tag("bill.category.${category.id}").performClick()
        tag("bill.wallet").performScrollTo().performClick()
        tag("bill.wallet.${wallet("JPY").id}").assertDoesNotExist();tag("bill.wallet.${wallet("USD").id}").assertDoesNotExist()
        tag("bill.wallet.${wallet("VND").id}").performClick()
        Assert.assertTrue(bills().isEmpty());tag("bill.save").performScrollTo().performClick()
        compose.waitUntil(5000) {bills().size==1}
        val saved=bills().single();Assert.assertEquals("VND",saved.currencyCode);Assert.assertEquals(9007199254740993L,saved.amountMinor)
        Assert.assertEquals(wallet("VND").id,saved.paymentWalletId)
        Assert.assertEquals(saved.toPayload(),runBlocking {store.pendingMutations(owner,CloudEntity.RECURRING_BILL_PLAN,Long.MAX_VALUE).single()}.mutation.payload)
    }
    private fun edit(original:RecurringBillPlanRecord) {
        tag("planning.tab.1").performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("bill.edit.${original.id}").fetchSemanticsNodes().isNotEmpty()}
        tag("bill.edit.${original.id}").performScrollTo().performClick()
    }
    @Test fun existingJpyBillRetainsMoneyAndWalletAcrossPrimaryChange() {
        val original=seed();var primary by mutableStateOf("VND")
        compose.setContent {Screen(primary)};edit(original)
        currency("JPY");tag("bill.amount").assertTextContains("9,007,199,254,740,993")
        tag("bill.name").performTextReplacement("Edited");compose.runOnIdle {primary="JPY"}
        tag("bill.name").assertTextContains("Edited");tag("bill.save").performScrollTo().performClick()
        compose.waitUntil(5000) {bills().single().name=="Edited"}
        val saved=bills().single();Assert.assertEquals(original.amountMinor,saved.amountMinor);Assert.assertEquals(original.currencyCode,saved.currencyCode)
        Assert.assertEquals(original.paymentWalletId,saved.paymentWalletId);Assert.assertEquals(original.id,saved.id)
    }
    @Test fun importedUsdBillKeepsDecimalMinorMeaningUnderVndPrimary() {
        val original=seed(code="USD",amount=1375)
        compose.setContent {Screen("VND")};edit(original)
        currency("USD");tag("bill.amount").assertTextContains("13.75")
        amount("14.25");tag("bill.save").performScrollTo().performClick();compose.waitUntil(5000) {bills().single().amountMinor==1425L}
        val saved=bills().single();Assert.assertEquals("USD",saved.currencyCode);Assert.assertEquals(original.paymentWalletId,saved.paymentWalletId)
    }
    @Test fun foreignBillNeverExposesEditorOrChangesEitherOwnersRecords() {
        val foreign=seed(other);val before=bills(other)
        compose.setContent {Editor(original=foreign)}
        tag("bill.editor").assertDoesNotExist();compose.onNodeWithText("Original").assertDoesNotExist()
        Assert.assertTrue(bills().isEmpty());Assert.assertEquals(before,bills(other))
    }
    @Test fun switchingRecordClosesOldWalletPickerAndLoadsNewDraft() {
        val first=seed(name="First");val second=seed(name="Second");var selected by mutableStateOf(first)
        val before=bills().associateBy {it.id}
        compose.setContent {Editor(original=selected)}
        tag("bill.wallet").performScrollTo().performClick();compose.runOnIdle {selected=second}
        tag("bill.wallet.${wallet("JPY").id}").assertDoesNotExist();tag("bill.name").assertTextContains("Second")
        Assert.assertEquals(before,bills().associateBy {it.id})
    }
    @Test fun changingPrimaryResetsNewDraftAndCalculatorWithoutRetaggingMoney() {
        var primary by mutableStateOf("VND")
        compose.setContent {Screen(primary)};newBill()
        tag("bill.name").performTextReplacement("Private");amount("9007199254740993")
        tag("bill.amount.calculator").performScrollTo().performClick();key("+");key("2")
        compose.runOnIdle {primary="JPY"}
        tag("amountCalculator.dialog").assertDoesNotExist()
        tag("bill.name").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
        tag("bill.amount").assert(hasText("9,007,199,254,740,993",substring=true).not())
        Assert.assertTrue(bills().isEmpty())
    }
    @Test fun primaryVndBillAndCalculatorRenderInLightDarkAtFont130() {
        var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen("VND",dark)}
        }
        newBill();details("VND");amount("9007199254740993")
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            currency("VND");tag("bill.amount").performScrollTo().assertTextContains("9,007,199,254,740,993")
            capture("bill-editor-$theme-font130.png")
            tag("bill.amount.calculator").performScrollTo().performClick()
            tag("amountCalculator.result").assertTextEquals("9,007,199,254,740,993")
            capture("bill-calculator-$theme-font130.png")
            tag("amountCalculator.cancel").performClick()
        }
        Assert.assertTrue(bills().isEmpty());Assert.assertTrue(runBlocking {store.pendingMutations(owner,CloudEntity.RECURRING_BILL_PLAN,Long.MAX_VALUE).isEmpty()})
    }
    private fun capture(name:String) {
        compose.waitForIdle()
        val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000
        var previous:android.graphics.Bitmap?=null
        var stableFrames=0
        var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {
            val frame=checkNotNull(automation.takeScreenshot())
            stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame
            if(stableFrames>=3) {stable=frame;break}
        }
        if(stable==null) previous?.recycle()
        val bitmap=checkNotNull(stable) {"Screenshot did not reach stable compositor frames: $name"}
        java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        bitmap.recycle()
    }
    @Test fun lateNonCancellableSaveCannotDismissNextOwnersDraft() {
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner);var visible by mutableStateOf(true)
        compose.setContent {if(visible) {val captured=subject;Editor(captured,save={draft ->
            val result=repo.saveRecurringBill(captured,draft,device,now());started.complete(Unit)
            withContext(NonCancellable) {release.await()};finished.complete(Unit);result
        },dismiss={visible=false})}}
        details();amount("123");tag("bill.amount").assertTextContains("123")
        try {
            tag("bill.save").performScrollTo().performClick();compose.waitForIdle()
            compose.waitUntil(5000) {started.isCompleted};compose.runOnIdle {subject=other}
            tag("bill.name").performScrollTo().assertIsEnabled().performTextReplacement("New")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            tag("bill.name").assertTextContains("New");Assert.assertEquals(123L,bills().single().amountMinor);Assert.assertTrue(bills(other).isEmpty())
        } finally {release.complete(Unit)}
    }
    @Test fun lateNonCancellablePauseCannotDismissNextOwnersDraft() {
        val original=seed();val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var subject by mutableStateOf(owner);var visible by mutableStateOf(true)
        compose.setContent {if(visible) {val captured=subject;Editor(captured,original.takeIf {captured==owner},pause={id ->
            val result=repo.pauseRecurringBill(captured,RecordId(id),device,now());started.complete(Unit)
            withContext(NonCancellable) {release.await()};finished.complete(Unit);result
        },dismiss={visible=false})}}
        try {
            tag("bill.pauseResume").performScrollTo().performClick();tag("bill.confirmAction").performClick()
            compose.waitUntil(5000) {started.isCompleted};compose.runOnIdle {subject=other}
            tag("bill.name").performScrollTo().assertIsEnabled().performTextReplacement("New")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            tag("bill.name").assertTextContains("New");Assert.assertTrue(bills().single().isPaused);Assert.assertTrue(bills(other).isEmpty())
        } finally {release.complete(Unit)}
    }
}
