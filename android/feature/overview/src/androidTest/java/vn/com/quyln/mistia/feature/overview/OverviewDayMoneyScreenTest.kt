package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
import vn.com.quyln.mistia.core.designsystem.formatMinorUnitsMagnitude
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewDayMoneyScreenTest {
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
    private val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    @Before fun setup() {db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun row(amount:Long,code:String?="JPY",wallet:String?=null):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("title","Original day")
            put("amount_minor",amount);code?.let {put("source_currency_code",it)};wallet?.let {put("source_wallet_id",it)}
            put("occurred_at",today.atStartOfDay(zone).plusHours(12).toInstant().toString());put("created_at",time);put("updated_at",time);put("is_archived",false)
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,owner).first() to store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Composable private fun Screen(subject:UserId=owner,primary:String="JPY",dark:Boolean=false,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)}}
    }
    private fun value(tag:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertTextEquals(text)
    }
    private fun bar()=compose.onNodeWithTag("overview.chart.day.$today")
    private fun awaitAmount(minor:BigInteger,code:String="JPY") {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and hasContentDescription(formatMinorUnits(minor,code),substring=true)).fetchSemanticsNodes().isNotEmpty()}
    }
    private fun reveal(tag:String) {
        val scroll=compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange))
        scroll.performScrollToIndex(1)
        repeat(5) {
            if(runCatching {compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()}.isSuccess) return
            scroll.performTouchInput {swipe(androidx.compose.ui.geometry.Offset(centerX,height*0.65f),androidx.compose.ui.geometry.Offset(centerX,height*0.45f),durationMillis=1000)}
        }
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()
    }
    private fun holdAvailableDay() {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.OnLongClick)).fetchSemanticsNodes().isNotEmpty()}
        reveal("overview.chart.day.$today");bar().performTouchInput {down(center);advanceEventTime(400);up()}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.day.sheet").fetchSemanticsNodes().isNotEmpty()}
    }
    private fun expand() {
        val travel=compose.onAllNodes(isRoot()).fetchSemanticsNodes().maxOf {it.boundsInRoot.height}*0.35f
        compose.onNodeWithText(context.getString(R.string.overview_overview_day_details)).performTouchInput {
            swipe(start=center,end=center+androidx.compose.ui.geometry.Offset(0f,-travel),durationMillis=500)
        }
    }
    @Test fun realRoomDailyBarAndSelectedCalloutRetainTwiceLongMaximumWithoutWrites() {
        repeat(2) {seed(row(Long.MAX_VALUE))};val before=snapshot();compose.setContent {Screen()}
        val exact=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO;awaitAmount(exact);reveal("overview.chart.day.$today");bar().performTouchInput {click()}
        value("overview.chart.selection",formatMinorUnits(exact,"JPY"));assertText("overview.chart.selection",1f);Assert.assertEquals(before,snapshot())
    }
    @Test fun positiveDayHoldRetainsExactTwiceMaximumHeaderAndOriginalSourceRowsWithoutWrites() {
        val rows=listOf(row(Long.MAX_VALUE),row(Long.MAX_VALUE));rows.forEach(::seed);val before=snapshot();compose.setContent {Screen()};holdAvailableDay()
        value("overview.day.total",formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"JPY"));value("overview.day.count","2");expand()
        for(row in rows) compose.onNodeWithTag("overview.day.amount.${row.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed().assertTextEquals("-"+formatMinorUnits(Long.MAX_VALUE,"JPY"))
        Assert.assertEquals(before,snapshot())
    }
    @Test fun missingFxHoldsWholeWeekAndRateRepairThenRemovalClearsTheSelectedAmount() {
        seed(row(3));seed(row(500,"VND"));val before=snapshot();compose.setContent {Screen(primary="VND")}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.chart.unavailable").fetchSemanticsNodes().isNotEmpty()}
        bar().assertDoesNotExist();compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(rate)};awaitAmount(BigInteger.valueOf(508),"VND");reveal("overview.chart.day.$today");bar().performClick();value("overview.chart.selection",formatMinorUnits(508,"VND"))
        compose.runOnIdle {rateRows.value=emptyList()};compose.onNodeWithTag("overview.chart.unavailable").assertExists();compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist();bar().assertDoesNotExist()
        Assert.assertEquals(before,snapshot())
    }
    @Test fun ownedWalletFallbackLiveCurrencyAndOwnerReplacementNeverReuseStaleBarOrCallout() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Private VND",kind=WalletKind.CASH,currencyCode="VND"),device,time).getOrThrow()}
        seed(row(100,code=null,wallet=wallet.id));var primary by mutableStateOf("VND");var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        val before=snapshot();compose.setContent {Screen(subject,primary=primary,source=source)};awaitAmount(BigInteger.valueOf(100),"VND");reveal("overview.chart.day.$today");bar().performClick();value("overview.chart.selection",formatMinorUnits(100,"VND"));Assert.assertEquals(before,snapshot())
        seed(wallet.copy(currencyCode="JPY").toCloudRecord());val changed=snapshot()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.chart.unavailable").fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(rate)};awaitAmount(BigInteger.valueOf(250),"VND")
        compose.runOnIdle {primary="JPY"};awaitAmount(BigInteger.valueOf(100));compose.runOnIdle {subject=other}
        compose.onNodeWithTag("overview.chart.unavailable").assertExists();compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist();compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist();Assert.assertEquals(changed,snapshot())
    }
    @Test fun legacyMissingOriginalSourceKeepsJPYAmountAndConvertedDayTotalConsistentWithBar() {
        val original=row(100,code=null);seed(original);rateRows.value=listOf(rate);val before=snapshot();compose.setContent {Screen(primary="VND")};awaitAmount(BigInteger.valueOf(250),"VND");holdAvailableDay()
        value("overview.day.total",formatMinorUnits(250,"VND"));expand()
        compose.onNodeWithTag("overview.day.amount.${original.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed().assertTextEquals("-"+formatMinorUnits(100,"JPY"));Assert.assertEquals(before,snapshot())
    }
    @Test fun malformedOriginalCurrencyRowRemainsCountableUnknownAndSelectableWithoutPartialTotal() {
        val malformed=row(1375,"??");val valid=row(100);listOf(malformed,valid).forEach(::seed)
        val day=runBlocking {overviewExpenseDay(owner,repo.observe(CloudEntity.LEDGER_TRANSACTION,owner).first().map(LedgerTransactionRecord::fromCloudRecord),emptyList(),today,"JPY",zone=zone)}
        val before=snapshot();var selected:String?=null
        compose.setContent {MistiaTheme(darkTheme=false) {OverviewDayTransactionsSheet(day,emptyMap(),emptyMap(),zone,onDismiss={},onSelect={selected=it})}}
        value("overview.day.count","2");value("overview.day.total","—");compose.onNodeWithTag("overview.day.total.unavailable").assertExists();expand()
        compose.onNodeWithTag("overview.day.amount.${malformed.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed().assertTextEquals("—")
        compose.onNodeWithTag("overview.day.row.${malformed.id}").performScrollTo().performTouchInput {click()};Assert.assertEquals(malformed.id,selected);Assert.assertEquals(before,snapshot())
    }
    @Test fun chartAxisCalloutAndExpandedDayMoneyStayCompleteAtActualFont130LightDark() {
        val rows=listOf(row(Long.MAX_VALUE,"VND"),row(Long.MAX_VALUE,"VND"));rows.forEach(::seed)
        val before=snapshot();var dark by mutableStateOf(false);var primary by mutableStateOf("VND")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary=primary,dark=dark)}}
        val exact=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark";primary="VND"};awaitAmount(exact,"VND");reveal("overview.chart.day.$today");bar().performTouchInput {click()};value("overview.chart.selection",formatMinorUnits(exact,"VND"));assertText("overview.chart.selection",1.3f)
            for(label in listOf("22136092888451M","11068046444225M","Mon","Tue","Wed","Thu","Fri","Sat","Sun")) assertTextNode(compose.onNodeWithText(label),1.3f)
            capture("overview-day-exact-chart-$theme-font130.png");holdAvailableDay();value("overview.day.total",formatMinorUnits(exact,"VND"));expand()
            compose.onNodeWithTag("overview.day.total").performScrollTo().assertIsDisplayed();assertText("overview.day.total",1.3f)
            for(row in rows) {compose.onNodeWithTag("overview.day.amount.${row.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed();assertText("overview.day.amount.${row.id}",1.3f)}
            capture("overview-day-exact-sheet-$theme-font130.png")
            compose.runOnIdle {primary="JPY"};value("overview.day.total","—");compose.onNodeWithTag("overview.day.total.unavailable").performScrollTo().assertIsDisplayed();assertText("overview.day.total.unavailable",1.3f,single=false)
            capture("overview-day-exact-unavailable-sheet-$theme-font130.png")
            compose.onNodeWithContentDescription(context.getString(R.string.common_close)).performClick()
            compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.chart.unavailable").fetchSemanticsNodes().isNotEmpty()};reveal("overview.chart.unavailable");assertText("overview.chart.unavailable",1.3f,single=false);capture("overview-day-exact-unavailable-week-$theme-font130.png")
        }
        Assert.assertEquals(before,snapshot())
    }
    @Test fun reportedPositiveHoldOpensExactNegativeOriginalTotalAtActualFont130() {
        val rows=listOf(row(Long.MIN_VALUE,"VND"),row(Long.MIN_VALUE,"VND")).map {it.with("reporting_expense_minor",JsonPrimitive(100))};rows.forEach(::seed)
        val before=snapshot();var dark by mutableStateOf(false)
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}}
        awaitAmount(BigInteger.valueOf(200),"VND");holdAvailableDay();value("overview.day.total",formatMinorUnits(BigInteger.valueOf(Long.MIN_VALUE)*BigInteger.TWO,"VND"));expand()
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"};compose.onNodeWithTag("overview.day.total").performScrollTo().assertIsDisplayed();assertText("overview.day.total",1.3f)
            for(row in rows) {compose.onNodeWithTag("overview.day.amount.${row.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed().assertTextEquals("+"+formatMinorUnitsMagnitude(Long.MIN_VALUE,"VND"));assertText("overview.day.amount.${row.id}",1.3f)}
            capture("overview-day-exact-negative-sheet-$theme-font130.png")
        }
        Assert.assertEquals(before,snapshot())
    }
    @Test fun selectedWideCalloutLeavesTopAxisPhysicallyReadableAtActualFont130() {
        repeat(2) {seed(row(Long.MAX_VALUE,"VND"))};val before=snapshot()
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND")}}
        val exact=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO
        awaitAmount(exact,"VND");reveal("overview.chart.day.$today");bar().performTouchInput {click()};value("overview.chart.selection",formatMinorUnits(exact,"VND"))
        val selection=compose.onNodeWithTag("overview.chart.selection").fetchSemanticsNode().boundsInRoot
        val axis=compose.onNodeWithText("22136092888451M").fetchSemanticsNode().boundsInRoot
        val padding=7*context.resources.displayMetrics.density
        Assert.assertTrue("Selected callout $selection covers top axis $axis",selection.bottom+padding<=axis.top)
        Assert.assertEquals(before,snapshot())
    }
    private fun assertText(tag:String,scale:Float,single:Boolean=true)=assertTextNode(compose.onNodeWithTag(tag,useUnmergedTree=true),scale,single)
    private fun assertTextNode(node:SemanticsNodeInteraction,scale:Float,single:Boolean=true) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals(scale,layout.layoutInput.density.fontScale,0.0001f);if(single) Assert.assertEquals(1,layout.lineCount)
        Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
        for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
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
