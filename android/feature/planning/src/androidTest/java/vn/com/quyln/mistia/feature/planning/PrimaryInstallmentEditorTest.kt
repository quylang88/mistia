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
class PrimaryInstallmentEditorTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var wallets:List<LedgerWalletRecord>
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val identity="33333333-3333-3333-3333-333333333333"
    private val alternate="44444444-4444-4444-4444-444444444444"
    private val exchange=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    private fun now()=Instant.now().toString()
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        wallets=listOf("JPY","VND","USD").map {code -> repo.saveWallet(owner,WalletDraft(name="Cash $code",kind=WalletKind.CASH,currencyCode=code),device,now()).getOrThrow()}
    }
    private fun wallet(code:String)=wallets.single {it.currencyCode==code}
    private fun plans(subject:UserId=owner)=runBlocking {repo.observeInstallments(subject).first()}
    private fun seed(subject:UserId=owner,code:String="JPY",amount:Long=9007199254740993L)=runBlocking {
        val w=if(subject==owner) wallet(code) else repo.saveWallet(subject,WalletDraft(name="Foreign cash",kind=WalletKind.CASH,currencyCode=code),device,now()).getOrThrow()
        repo.saveInstallment(subject,InstallmentDraft(identity,"Original",amount,15,1,12,w.id,code),device,now()).getOrThrow()
    }
    @Composable private fun Screen(primary:String,repository:FinanceRepository=repo,dark:Boolean=false) {MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
        PlanningScreen(owner,repository,modifier=Modifier.padding(padding),deviceIdProvider={device},exchangeRateRepository=exchange,primaryCurrencyCode=primary)
    }}}
    @Composable private fun Editor(currency:String="JPY",original:InstallmentPlanRecord?=null,id:String=identity) {MistiaTheme(darkTheme=false) {
        InstallmentEditorSheet(owner.value,id,original,currency,wallets,onSave={repo.saveInstallment(owner,it,device,now())},
            onDelete={repo.deleteInstallment(owner,it,device,now())},onDismiss={})
    }}
    private fun tag(name:String)=compose.onNodeWithTag(name)
    private fun pane() {
        tag("planning.tab.1").performClick();tag("planning.due.2").performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("installment.add").fetchSemanticsNodes().isNotEmpty()}
    }
    private fun newPlan() {pane();tag("installment.add").performScrollTo().performClick()}
    private fun amount(text:String) {tag("installment.amountInput").performScrollTo().performTextReplacement(text)}
    private fun currency(code:String) {compose.onAllNodesWithText(code,useUnmergedTree=true).assertCountEquals(1)}
    private fun chooseWallet(code:String) {tag("installment.wallet").performScrollTo().performClick();tag("installment.pickWallet.${wallet(code).id}").performClick()}
    private fun key(value:String) {tag("amountCalculator.key.$value").performClick()}
    private fun emptyName() {tag("installment.name").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))}
    @Test fun realPlanningCreatesExactVndInstallmentWithSameCurrencyWalletAndOutbox() {
        val beforeWallets=runBlocking {repo.observeWallets(owner).first()}
        compose.setContent {Screen(" vnd ")};newPlan()
        tag("installment.name").performTextReplacement("Loan");amount("9007199254740993");currency("VND")
        tag("installment.wallet").performScrollTo().performClick()
        tag("installment.pickWallet.${wallet("JPY").id}").assertDoesNotExist();tag("installment.pickWallet.${wallet("USD").id}").assertDoesNotExist()
        tag("installment.pickWallet.${wallet("VND").id}").performClick()
        tag("installment.save").performScrollTo().performClick();compose.waitUntil(5000) {plans().size==1}
        val saved=plans().single();Assert.assertEquals("VND",saved.currencyCode);Assert.assertEquals(9007199254740993L,saved.amountPerCycleMinor)
        Assert.assertEquals(wallet("VND").id,saved.paymentWalletId)
        Assert.assertEquals(saved.toPayload(),runBlocking {store.pendingMutations(owner,CloudEntity.INSTALLMENT_PLAN,Long.MAX_VALUE).single()}.mutation.payload)
        Assert.assertEquals(beforeWallets,runBlocking {repo.observeWallets(owner).first()});Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()})
    }
    @Test fun existingJpyEditKeepsBaselineAndUnsavedNameAcrossPrimaryChange() {
        val original=seed();var primary by mutableStateOf("VND")
        compose.setContent {Screen(primary)};pane();tag("installment.edit.${original.id}").performScrollTo().performClick()
        currency("JPY");tag("installment.amountInput").assertTextContains("9,007,199,254,740,993")
        tag("installment.name").performTextReplacement("Edited");compose.runOnIdle {primary="JPY"}
        tag("installment.name").assertTextContains("Edited");tag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) {plans().single().name=="Edited"};val saved=plans().single()
        Assert.assertEquals(original.currencyCode,saved.currencyCode);Assert.assertEquals(original.amountPerCycleMinor,saved.amountPerCycleMinor)
        Assert.assertEquals(original.createdAt,saved.createdAt);Assert.assertEquals(original.paymentWalletId,saved.paymentWalletId);Assert.assertEquals(original.id,saved.id)
    }
    @Test fun importedUsdRetainsRawMinorIntegerCalculationUnderVndPrimary() {
        val original=seed(code="USD",amount=1375)
        compose.setContent {Screen("VND")};pane();tag("installment.edit.${original.id}").performScrollTo().performClick()
        currency("USD");tag("installment.amountInput").assertTextContains("1,375")
        tag("installment.amount.calculator").performScrollTo().performClick();key("÷");key("5");key("OK")
        tag("installment.amountInput").assertTextContains("275");tag("installment.save").performScrollTo().performClick()
        compose.waitUntil(5000) {plans().single().amountPerCycleMinor==275L}
        Assert.assertEquals("USD",plans().single().currencyCode);Assert.assertEquals(original.paymentWalletId,plans().single().paymentWalletId)
    }
    @Test fun directCreationCurrencyChangeClearsDraftAndCalculatorAtSameRouteId() {
        var code by mutableStateOf("JPY")
        compose.setContent {Editor(code)};tag("installment.name").performTextReplacement("Private");amount("9007199254740993")
        tag("installment.amount.calculator").performScrollTo().performClick();key("+");key("2")
        compose.runOnIdle {code="VND"}
        tag("amountCalculator.dialog").assertDoesNotExist();emptyName()
        tag("installment.amountInput").assert(hasText("9,007,199,254,740,993",substring=true).not());amount("1");currency("VND")
        Assert.assertTrue(plans().isEmpty())
    }
    @Test fun livePrimaryResetsUnsavedCreateDraftAndWalletWithoutRetaggingMoney() {
        var primary by mutableStateOf("JPY")
        compose.setContent {Screen(primary)};newPlan();tag("installment.name").performTextReplacement("Private");amount("9007199254740993");chooseWallet("JPY")
        tag("installment.amount.calculator").performScrollTo().performClick();key("+");key("2")
        compose.runOnIdle {primary="VND"}
        tag("amountCalculator.dialog").assertDoesNotExist();emptyName();amount("1");currency("VND")
        tag("installment.wallet").assert(hasText("Cash JPY",substring=true).not())
        Assert.assertTrue(plans().isEmpty())
    }
    @Test fun foreignOriginalIsHiddenBeforeStateInitialization() {
        val foreign=seed(other);val before=plans(other)
        compose.setContent {Editor(original=foreign)}
        tag("installment.editor").assertDoesNotExist();compose.onNodeWithText("Original").assertDoesNotExist()
        Assert.assertTrue(plans().isEmpty());Assert.assertEquals(before,plans(other))
    }
    @Test fun mismatchedOriginalRouteIdNeverExposesAnotherOwnedPlan() {
        val original=seed();compose.setContent {Editor(original=original,id=alternate)}
        tag("installment.editor").assertDoesNotExist();Assert.assertEquals(original,plans().single())
    }
    @Test fun primaryVndInstallmentAndCalculatorRenderLightDarkAtFont130() {
        var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen("VND",dark=dark)}
        }
        newPlan();tag("installment.name").performTextReplacement("Exact VND loan");chooseWallet("VND");amount("9007199254740993")
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            currency("VND");tag("installment.amountInput").performScrollTo().assertTextContains("9,007,199,254,740,993")
            capture("installment-editor-$theme-font130.png")
            tag("installment.amount.calculator").performScrollTo().performClick()
            tag("amountCalculator.result").assertTextEquals("9,007,199,254,740,993")
            capture("installment-calculator-$theme-font130.png")
            tag("amountCalculator.cancel").performClick()
        }
        Assert.assertTrue(plans().isEmpty());Assert.assertTrue(runBlocking {store.pendingMutations(owner,CloudEntity.INSTALLMENT_PLAN,Long.MAX_VALUE).isEmpty()})
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
    @Test fun changedPrimaryDuringPendingCreateUsesFreshIdAndOldResponseCannotCloseNextDraft() {
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        val guarded=object:FinanceRepository by repo {
            override suspend fun saveInstallment(owner:UserId,draft:InstallmentDraft,deviceId:String,now:String):Result<InstallmentPlanRecord> {
                val result=repo.saveInstallment(owner,draft,deviceId,now)
                if(!started.isCompleted) {started.complete(Unit);withContext(NonCancellable) {release.await()};finished.complete(Unit)}
                return result
            }
        }
        var primary by mutableStateOf("JPY")
        compose.setContent {Screen(primary,guarded)};newPlan();tag("installment.name").performTextReplacement("Old");amount("123");chooseWallet("JPY")
        try {
            tag("installment.save").performScrollTo().performClick();compose.waitUntil(5000) {started.isCompleted};compose.runOnIdle {primary="VND"}
            tag("installment.name").performScrollTo().assertIsEnabled().performTextReplacement("New");amount("200");currency("VND");chooseWallet("VND")
            tag("installment.save").performScrollTo().performClick();compose.waitUntil(5000) {plans().size==2}
            val saved=plans().associateBy {it.name};Assert.assertNotEquals(saved.getValue("Old").id,saved.getValue("New").id)
            Assert.assertEquals("JPY",saved.getValue("Old").currencyCode);Assert.assertEquals(123L,saved.getValue("Old").amountPerCycleMinor)
            Assert.assertEquals("VND",saved.getValue("New").currencyCode);Assert.assertEquals(200L,saved.getValue("New").amountPerCycleMinor)
            compose.waitUntil(5000) {compose.onAllNodesWithTag("installment.editor").fetchSemanticsNodes().isEmpty()}
            tag("installment.add").performScrollTo().performClick();tag("installment.name").performTextReplacement("Next draft")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            tag("installment.name").assertTextContains("Next draft")
        } finally {release.complete(Unit)}
    }
}
