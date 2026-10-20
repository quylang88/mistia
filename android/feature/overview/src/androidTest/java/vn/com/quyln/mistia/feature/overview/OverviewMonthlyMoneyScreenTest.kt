package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewMonthlyMoneyScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time=Instant.now().toString()
    private val zone=ZoneId.systemDefault()
    private val today=Instant.parse(time).atZone(zone).toLocalDate()
    private val rateRows=MutableStateFlow(emptyList<ExchangeRateSnapshot>())
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
    @Before fun setup() {db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun row(amount:Long,kind:String="expense",code:String?="JPY",date:LocalDate=today,category:String?=null,wallet:String?=null):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Monthly money")
            put("amount_minor",amount);code?.let {put("source_currency_code",it)};put("occurred_at",date.atStartOfDay(zone).plusHours(12).toInstant().toString())
            put("created_at",time);put("updated_at",time);put("is_archived",false);category?.let {put("category_id",it)};wallet?.let {put("source_wallet_id",it)}
        },time,null,0)
    }
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,owner).first() to store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Composable private fun Screen(subject:UserId=owner,primary:String="JPY",dark:Boolean=false,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)}}
    }
    private fun value(kind:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.monthly.$kind") and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.monthly.$kind",useUnmergedTree=true).assertTextEquals(text)
    }
    private fun amount(kind:String,minor:Long,code:String="JPY")=value(kind,formatMinorUnits(minor,code))
    private fun unavailable(kind:String) {value(kind,"—");compose.onNodeWithTag("overview.monthly.$kind.unavailable").assertExists()}
    @Test fun currentIncomeAndExpenseKeepExactTwiceLongMaximumWithoutWrites() {
        for(kind in listOf("income","expense")) repeat(2) {seed(row(Long.MAX_VALUE,kind))}
        val before=snapshot();compose.setContent {Screen()}
        val expected=formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"JPY")
        value("income",expected);value("expense",expected);Assert.assertEquals(before,snapshot())
    }
    @Test fun missingExpenseConversionHoldsWholeDirectionAndLiveRateRepairsIt() {
        listOf(row(3),row(500,code="VND"),row(70,"income","VND")).forEach(::seed)
        val before=snapshot();compose.setContent {Screen(primary="VND")}
        unavailable("expense");amount("income",70,"VND");compose.onNodeWithTag("overview.monthly.income.unavailable").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(rate)};amount("expense",508,"VND");amount("income",70,"VND")
        compose.onNodeWithTag("overview.monthly.expense.unavailable").assertDoesNotExist();Assert.assertEquals(before,snapshot())
    }
    @Test fun missingIncomePreservesExpenseAndCurrencyRateChangesRepairBothDirections() {
        listOf(row(3,"income"),row(500,"income","VND"),row(90,code="VND")).forEach(::seed)
        var primary by mutableStateOf("VND");val before=snapshot();compose.setContent {Screen(primary=primary)}
        unavailable("income");amount("expense",90,"VND");compose.onNodeWithTag("overview.monthly.expense.unavailable").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(rate)};amount("income",508,"VND")
        compose.runOnIdle {primary="JPY"};amount("income",203);amount("expense",36)
        compose.onNodeWithTag("overview.monthly.income.unavailable").assertDoesNotExist();Assert.assertEquals(before,snapshot())
    }
    @Test fun nullSourceUsesOwnedWalletCurrencyAndLiveWalletChangeDoesNotReuseStaleTotal() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="VND wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=0),device,time).getOrThrow()}
        seed(row(100,code=null,wallet=wallet.id));val before=snapshot();compose.setContent {Screen(primary="VND")};amount("expense",100,"VND");Assert.assertEquals(before,snapshot())
        seed(wallet.copy(currencyCode="JPY").toCloudRecord());val changed=snapshot();unavailable("expense")
        compose.runOnIdle {rateRows.value=listOf(rate)};amount("expense",250,"VND");Assert.assertEquals(changed,snapshot())
    }
    @Test fun historicalCategorySummaryUsesUnavailableMonthAndDayRestoresCurrentThenOwnerClears() {
        val cat=runBlocking {repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()}
        val old=YearMonth.from(today).minusMonths(1).atDay(15)
        listOf(row(3,date=old,category=cat.id),row(70,"income","VND",old),row(20,code="VND",category=cat.id)).forEach(::seed)
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        val before=snapshot();compose.setContent {Screen(subject,primary="VND",source=source)};amount("expense",20,"VND")
        compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick()
        compose.onNodeWithTag("overview.category.pager").performScrollTo().performTouchInput {swipeRight()};unavailable("expense");amount("income",70,"VND")
        compose.onNodeWithTag("overview.chart.mode.day").performScrollTo().performClick();amount("expense",20,"VND");compose.onNodeWithTag("overview.monthly.expense.unavailable").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(rate)}
        compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick();amount("expense",8,"VND")
        compose.runOnIdle {subject=other};amount("expense",0,"VND");amount("income",0,"VND");compose.onNodeWithTag("overview.monthly.expense.unavailable").assertDoesNotExist();Assert.assertEquals(before,snapshot())
    }
    @Test fun unsupportedPrimaryUsesOneValidatedDisplayCurrencyAndNeverRelabelsImportedMoney() {
        seed(row(1375,code="USD"));seed(row(100,"income","JPY"))
        var primary by mutableStateOf("USD");val before=snapshot();compose.setContent {Screen(primary=primary)}
        unavailable("expense");amount("income",100)
        compose.runOnIdle {primary="??"};unavailable("expense");amount("income",100)
        compose.runOnIdle {primary=" jpy "};unavailable("expense");amount("income",100)
        Assert.assertEquals(before,snapshot())
    }
    @Test fun exactBothDirectionsRenderCompleteLightDarkAtActualFont130WithoutWrites() {
        for(kind in listOf("income","expense")) repeat(2) {seed(row(Long.MAX_VALUE,kind,"VND"))}
        val before=snapshot();var dark by mutableStateOf(false);var primary by mutableStateOf("VND")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary=primary,dark=dark)}}
        val expected=formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"VND")
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark";primary="VND"};value("income",expected);value("expense",expected)
            for(kind in listOf("income","expense")) {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag("overview.monthly.$kind",useUnmergedTree=true).performScrollTo().assertIsDisplayed()
                    .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
                val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
                Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
                for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("$kind glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            }
            capture("overview-monthly-exact-$theme-font130.png")
            compose.runOnIdle {primary="JPY"};unavailable("income");unavailable("expense")
            for(kind in listOf("income","expense")) {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag("overview.monthly.$kind.unavailable").performScrollTo().assertIsDisplayed()
                    .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
                val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
                Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
                for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("$kind hint glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            }
            capture("overview-monthly-unavailable-$theme-font130.png")
        }
        Assert.assertEquals(before,snapshot())
    }
    @Test fun negativeBeyondLongIncomeAndExpenseRemainCompleteAtNormalAndActualFont130() {
        for(kind in listOf("income","expense")) repeat(2) {seed(row(Long.MIN_VALUE,kind,"VND"))}
        val before=snapshot();var font by mutableFloatStateOf(1f);var dark by mutableStateOf(false)
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,font)) {Screen(primary="VND",dark=dark)}}
        val expected=formatMinorUnits(BigInteger.valueOf(Long.MIN_VALUE)*BigInteger.TWO,"VND")
        for(scale in listOf(1f,1.3f)) for(theme in listOf("light","dark")) {
            compose.runOnIdle {font=scale;dark=theme=="dark"};value("income",expected);value("expense",expected)
            for(kind in listOf("income","expense")) {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag("overview.monthly.$kind",useUnmergedTree=true).performScrollTo().assertIsDisplayed()
                    .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
                val layout=layouts.single();Assert.assertEquals(scale,layout.layoutInput.density.fontScale,0.0001f)
                Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
                for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("$kind negative glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            }
            if(scale==1.3f) capture("overview-monthly-negative-$theme-font130.png")
        }
        Assert.assertEquals(before,snapshot())
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable) {"Unsettled screenshot:$name"}
        java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
