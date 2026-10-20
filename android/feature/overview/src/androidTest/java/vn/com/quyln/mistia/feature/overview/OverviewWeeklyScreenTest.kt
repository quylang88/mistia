package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
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
class OverviewWeeklyScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time=Instant.now().toString()
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private val rateRows=MutableStateFlow(emptyList<ExchangeRateSnapshot>())
    private var refreshes=0
    private val rates=object:ExchangeRateRepository {
        override val rates=rateRows
        override suspend fun refreshIfStale(nowEpochMillis:Long):Result<Unit> {refreshes++;return Result.success(Unit)}
    }
    private var overlay by mutableStateOf(false)
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
    }
    private fun row(amount:Long=100,kind:String="expense"):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Monthly row")
            put("amount_minor",amount);put("source_currency_code","JPY");put("occurred_at",time);put("created_at",time);put("updated_at",time);put("is_archived",false)
        },time,null,0)
    }
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.LEDGER_TRANSACTION,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun rows(subject:UserId=owner)=runBlocking {repo.observe(CloudEntity.LEDGER_TRANSACTION,subject).first()}
    private fun pending()=runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE)}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo,primary:String="JPY",dark:Boolean=false) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates,overlayPresented=overlay)
        }}
    }
    private val zone=java.time.ZoneId.systemDefault()
    private val today=Instant.parse(time).atZone(zone).toLocalDate()
    private val monday=today.minusDays(today.dayOfWeek.value.toLong()-1)
    private fun expense(amount:Long=100,date:java.time.LocalDate=monday,code:String="JPY")=row(amount).with(
        "occurred_at" to JsonPrimitive(date.atStartOfDay(zone).plusHours(12).toInstant().toString()),"source_currency_code" to JsonPrimitive(code))
    private fun bar(date:java.time.LocalDate)=compose.onNodeWithTag("overview.chart.day.$date")
    private fun select(date:java.time.LocalDate)=bar(date).performScrollTo().performClick()
    private fun selected(amount:Long,code:String)=compose.onNodeWithTag("overview.chart.selection").assertTextEquals(formatMinorUnits(amount,code))
    @Test fun realRoomDailyBarShowsExactMoneyTogglesAndZeroDayClearsWithoutWrites() {
        seed(expense(9007199254740993L));val before=rows();val queue=pending()
        compose.setContent {Screen()}
        bar(monday).assert(hasContentDescription(formatMinorUnits(9007199254740993L,"JPY"),substring=true))
        select(monday);selected(9007199254740993L,"JPY");select(monday);compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        select(monday);select(monday.plusDays(1));compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
    }
    @Test fun historicalSwipeClearsSelectionAndPrependingOlderHistoryRetainsSelectedWeek() {
        seed(expense(100,monday.minusWeeks(2)));seed(expense(200))
        compose.setContent {Screen()};select(monday);selected(200,"JPY")
        compose.onNodeWithTag("overview.chart.pager").performTouchInput {swipeRight()}
        compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.onNodeWithTag("overview.chart.pager").performTouchInput {swipeRight()}
        select(monday.minusWeeks(2));selected(100,"JPY")
        seed(expense(50,monday.minusWeeks(3)))
        val range="${monday.minusWeeks(2).format(java.time.format.DateTimeFormatter.ofPattern("dd/MM"))} - ${monday.minusWeeks(2).plusDays(6).format(java.time.format.DateTimeFormatter.ofPattern("dd/MM"))}"
        compose.onNodeWithTag("overview.chart.range").assertTextEquals(range)
        bar(monday.minusWeeks(2)).assertIsDisplayed()
    }
    @Test fun livePrimaryRatesAndRemovedSelectedDayNeverShowStaleSourceOrSnapshotAmounts() {
        val original=expense(3).with("reporting_currency_code" to JsonPrimitive("VND"),"reporting_amount_minor" to JsonPrimitive(999));seed(original)
        var primary by mutableStateOf("JPY");compose.setContent {Screen(primary=primary)};select(monday);selected(3,"JPY")
        compose.runOnIdle {primary="VND"};compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null))};select(monday);selected(8,"VND")
        seed(original.with("is_archived" to JsonPrimitive(true)))
        // Room invalidation/query delivery runs outside Compose's idling resources.
        // Wait for the new projection before asserting its selection was removed.
        compose.waitUntil(5000) {
            compose.onAllNodes(hasTestTag("overview.chart.day.$monday") and hasContentDescription(formatMinorUnits(0,"VND"),substring=true)).fetchSemanticsNodes().size==1
        }
        compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        bar(monday).assert(hasContentDescription(formatMinorUnits(0,"VND"),substring=true))
    }
    @Test fun ownerReplacementBeforeNextFlowEmitsClearsPrivateSelectionAndBarAmounts() {
        seed(expense(123456789));var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()
        }
        compose.setContent {Screen(subject,source)};select(monday);selected(123456789,"JPY")
        compose.runOnIdle {subject=other};compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist();bar(monday).assert(hasContentDescription(formatMinorUnits(0,"JPY"),substring=true))
        Assert.assertTrue(rows(other).isEmpty())
    }
    @Test fun overlayPauseAndHeroHeadingTapClearPrivateSelectedCallout() {
        seed(expense(100))
        val lifecycleOwner=object:androidx.lifecycle.LifecycleOwner {
            val registry=androidx.lifecycle.LifecycleRegistry.createUnsafe(this)
            override val lifecycle:androidx.lifecycle.Lifecycle get()=registry
        };lifecycleOwner.registry.currentState=androidx.lifecycle.Lifecycle.State.RESUMED
        compose.setContent {CompositionLocalProvider(androidx.lifecycle.compose.LocalLifecycleOwner provides lifecycleOwner) {Screen()}}
        select(monday);selected(100,"JPY");compose.runOnIdle {overlay=true};compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.runOnIdle {overlay=false};select(monday);selected(100,"JPY")
        compose.runOnIdle {lifecycleOwner.registry.currentState=androidx.lifecycle.Lifecycle.State.STARTED};compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.runOnIdle {lifecycleOwner.registry.currentState=androidx.lifecycle.Lifecycle.State.RESUMED};select(monday);selected(100,"JPY")
        val label=ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.overview_overview_available_assets)
        compose.onNodeWithText(label).performTouchInput {click()};compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
    }
    @Test fun weekdayAndWeekRangeFollowEnglishVietnameseJapaneseWhileMoneyStaysExact() {
        var language by mutableStateOf("en")
        val start=java.time.LocalDate.of(2026,4,6)
        val pages=listOf(OverviewWeekSpending(start,true,(0L..6).map {OverviewDailySpending(start.plusDays(it),100,0.5)}))
        compose.setContent {
            val context=ApplicationProvider.getApplicationContext<Context>()
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {
                MistiaTheme(darkTheme=false) {OverviewWeeklyChart(pages,"VND")}
            }
        }
        for((code,labels,range) in listOf(Triple("en",listOf("Mon","Sun"),"This week • 06/04 - 12/04"),Triple("vi",listOf("T2","CN"),"Tuần này • 06/04 - 12/04"),Triple("ja",listOf("月","日"),"今週 • 06/04 - 12/04"))) {
            compose.runOnIdle {language=code};compose.onNodeWithText(labels[0]).assertExists();compose.onNodeWithText(labels[1]).assertExists()
            compose.onNodeWithTag("overview.chart.range").assertTextEquals(range)
        }
    }
    @Test fun dailyChartAndExactCalloutRenderLightDarkAtFont130WithUnchangedFinancialRows() {
        seed(expense(Long.MAX_VALUE,code="VND"));seed(expense(100,monday.plusDays(1),"VND"))
        val before=rows();val queue=pending();var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}
        }
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"};bar(monday).performScrollTo();capture("overview-weekly-$theme-font130.png")
            select(monday);selected(Long.MAX_VALUE,"VND")
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("overview.chart.selection").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
            for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("Callout glyph $i outside $box / ${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            capture("overview-weekly-selected-$theme-font130.png");select(monday)
        }
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
    }
    @Test fun largeAxisLabelsRetainEveryDigitAndMagnitudeSuffixAtFont130() {
        seed(expense(Long.MAX_VALUE,code="VND"))
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND")}
        }
        for(text in listOf("11068046444225M","5534023222112M")) {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText(text).performScrollTo().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals("$text complete visible end",text.length,layout.getLineEnd(0,true));Assert.assertFalse(layout.isLineEllipsized(0))
            for(i in text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("Axis $text glyph $i outside $box / ${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
        }
    }
    @Test fun physicalTapOnCalloutClearsSelectionAndDayRemainsSelectable() {
        seed(expense(100));compose.setContent {Screen()};select(monday);selected(100,"JPY")
        compose.onNodeWithTag("overview.chart.selection").performTouchInput {click()}
        compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        select(monday);selected(100,"JPY")
    }
    @Test fun wideExtremeAxisKeepsAllSevenWeekdayLabelsCompleteAtFont130() {
        seed(expense(Long.MAX_VALUE,code="VND"))
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND")}
        }
        for(text in listOf("Mon","Tue","Wed","Thu","Fri","Sat","Sun")) {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText(text).performScrollTo().performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals("$text complete visible end",text.length,layout.getLineEnd(0,true));Assert.assertFalse(layout.isLineEllipsized(0))
            for(i in text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("Weekday $text glyph $i outside $box / ${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
        }
    }
    @Test fun removedHistoricalSelectionResetsToCurrentAndDoesNotReturnWhenHistoryReappears() {
        val old=expense(100,monday.minusWeeks(2));val current=expense(200)
        val raw=MutableStateFlow(listOf(old,current))
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) raw else repo.observe(entity,ownerUserId)
        }
        compose.setContent {Screen(source=source)}
        repeat(2) {compose.onNodeWithTag("overview.chart.pager").performTouchInput {swipeRight()}}
        select(monday.minusWeeks(2));selected(100,"JPY")
        val range="${monday.format(java.time.format.DateTimeFormatter.ofPattern("dd/MM"))} - ${monday.plusDays(6).format(java.time.format.DateTimeFormatter.ofPattern("dd/MM"))}"
        compose.runOnIdle {raw.value=listOf(current)}
        compose.onNodeWithTag("overview.chart.range").assert(hasText(range,substring=true));compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.runOnIdle {raw.value=listOf(old,current)}
        compose.onNodeWithTag("overview.chart.range").assert(hasText(range,substring=true));bar(monday).assertIsDisplayed()
        Assert.assertTrue(rows().isEmpty());Assert.assertTrue(pending().isEmpty())
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {
            val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}
        }
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable) {"Unsettled screenshot: $name"}
        java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
