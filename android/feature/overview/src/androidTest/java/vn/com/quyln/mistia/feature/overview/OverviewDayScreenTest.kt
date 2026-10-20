package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
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
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewDayScreenTest {
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
    private val monday=today.minusDays(today.dayOfWeek.value.toLong()-1)
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private val rateRows=MutableStateFlow(emptyList<ExchangeRateSnapshot>())
    private val rates=object:ExchangeRateRepository {
        override val rates=rateRows
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    private var overlay by mutableStateOf(false)
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
    }
    private fun row(amount:Long=100,code:String="JPY",hour:Long=12,kind:String="expense"):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Day row $hour")
            put("amount_minor",amount);put("source_currency_code",code);put("occurred_at",monday.atStartOfDay(zone).plusHours(hour).toInstant().toString());put("created_at",time);put("updated_at",time);put("is_archived",false)
        },time,null,0)
    }
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.LEDGER_TRANSACTION,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun rows()=runBlocking {repo.observe(CloudEntity.LEDGER_TRANSACTION,owner).first()}
    private fun pending()=runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE)}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo,primary:String="JPY",dark:Boolean=false,onOpen:(String)->Unit={}) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates,overlayPresented=overlay,onOpenTransaction=onOpen)
        }}
    }
    private fun bar()=compose.onNodeWithTag("overview.chart.day.$monday")
    private fun awaitBar(amount:Long,code:String)=awaitBar(java.math.BigInteger.valueOf(amount),code)
    private fun awaitBar(amount:java.math.BigInteger,code:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$monday") and hasContentDescription(formatMinorUnits(amount,code),substring=true)).fetchSemanticsNodes().isNotEmpty()}
    }
    private fun holdDay(amount:Long=100,code:String="JPY")=holdDay(java.math.BigInteger.valueOf(amount),code)
    private fun holdDay(amount:java.math.BigInteger,code:String) {
        awaitBar(amount,code);bar().performScrollTo().performTouchInput {down(center);advanceEventTime(400);up()}
    }
    private fun openDay(amount:Long=100,code:String="JPY")=openDay(java.math.BigInteger.valueOf(amount),code)
    private fun openDay(amount:java.math.BigInteger,code:String="JPY") {
        holdDay(amount,code);compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.day.sheet").fetchSemanticsNodes().isNotEmpty()}
    }
    private fun total(amount:Long?,code:String)=totalExact(amount?.let(java.math.BigInteger::valueOf),code)
    private fun totalExact(amount:java.math.BigInteger?,code:String) {
        val text=amount?.let {formatMinorUnits(it,code)} ?: "—"
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.day.total") and hasText(text)).fetchSemanticsNodes().size==1}
        compose.onNodeWithTag("overview.day.total").assertTextEquals(text)
    }
    @Test fun physicalHoldAt400msShowsAllSevenOwnedRowsAndExactSummaryThenRoutesWithoutWrites() {
        val exact=row(9007199254740993L,"VND",1);val records=listOf(exact)+(2L..7).map {row(1,"VND",it)}
        records.forEach(::seed);seed(row(999,"VND",8,"income"));seed(row(999,"VND",9).with("is_archived" to JsonPrimitive(true)))
        val before=rows();val queue=pending();var opened:String?=null
        compose.setContent {Screen(primary="VND",onOpen={opened=it})}
        awaitBar(9007199254740999L,"VND");bar().performScrollTo().performClick();compose.onNodeWithTag("overview.chart.selection").assertExists()
        openDay(9007199254740999L,"VND");compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        total(9007199254740999L,"VND");compose.onNodeWithTag("overview.day.count").assertTextEquals("7")
        for(record in records) compose.onNodeWithTag("overview.day.row.${record.id}").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("overview.day.amount.${exact.id}",useUnmergedTree=true).assertTextEquals("-"+formatMinorUnits(9007199254740993L,"VND"))
        compose.onNodeWithTag("overview.day.row.${exact.id}").performScrollTo().performTouchInput {click()};compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()
        Assert.assertEquals(exact.id,opened);Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
    }
    @Test fun livePrimaryAndRatesKeepOriginalRowsAndMissingTotalUntilRateThenArchiveUpdatesEmptyDay() {
        val original=row(3).with("reporting_currency_code" to JsonPrimitive("VND"),"reporting_amount_minor" to JsonPrimitive(999));seed(original)
        var primary by mutableStateOf("JPY");compose.setContent {Screen(primary=primary)};openDay(3);total(3,"JPY")
        compose.runOnIdle {primary="VND"};total(null,"VND");compose.onNodeWithTag("overview.day.amount.${original.id}",useUnmergedTree=true).assertTextEquals("-"+formatMinorUnits(3,"JPY"))
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null))};total(8,"VND")
        seed(original.with("is_archived" to JsonPrimitive(true)));total(0,"VND")
        compose.onNodeWithTag("overview.day.count").assertTextEquals("0");compose.onNodeWithTag("overview.day.row.${original.id}").assertDoesNotExist()
        compose.onNodeWithText(context.getString(R.string.transactions_transactions_no_transactions_yet)).assertExists()
    }
    @Test fun ownerReplacementBeforeNextFlowEmitsClosesPrivateDayAndRemovesRows() {
        val original=row(123456789);seed(original);var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        compose.setContent {Screen(subject,source)};openDay(123456789);total(123456789,"JPY")
        compose.runOnIdle {subject=other};compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist();compose.onNodeWithTag("overview.day.row.${original.id}").assertDoesNotExist()
        awaitBar(0,"JPY")
    }
    @Test fun externalOverlayClosesDayBeforeOpeningAnotherOwnedRoute() {
        seed(row());compose.setContent {Screen()};openDay();compose.runOnIdle {overlay=true};compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()
    }
    @Test fun reportingOnlyPositiveBarAndZeroDaysNeverOpenUnrelatedEmptyDetails() {
        seed(row(kind="income").with("reporting_expense_minor" to JsonPrimitive(100)))
        compose.setContent {Screen()};awaitBar(100,"JPY");bar().performScrollTo().performClick();compose.onNodeWithTag("overview.chart.selection").assertExists()
        holdDay();compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist();compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        compose.onNodeWithTag("overview.chart.day.${monday.plusDays(1)}").performTouchInput {down(center);advanceEventTime(400);up()}
        compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()
    }
    @Test fun localizedDayDateSummaryAndCloseFollowEnglishVietnameseJapanese() {
        seed(row());var language by mutableStateOf("en")
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {Screen()}
        }
        for(code in listOf("en","vi","ja")) {
            compose.runOnIdle {language=code};openDay()
            val locale=java.util.Locale.forLanguageTag(code);val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply {setLocale(locale)})
            try {compose.onNodeWithText(localized.getString(R.string.overview_overview_day_details)).assertExists()} catch(failure:AssertionError) {throw AssertionError("Locale $code: ${compose.onNodeWithTag("overview.day.sheet",useUnmergedTree=true).printToString()}",failure)}
            compose.onNodeWithTag("overview.day.date").assertTextEquals(monday.format(java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.FULL).withLocale(locale)))
            compose.onNodeWithText(localized.getString(R.string.overview_overview_total_spent)).assertExists()
            compose.onNodeWithContentDescription(localized.getString(R.string.common_close)).performClick();compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()
        }
    }
    @Test fun exactDaySummaryAndSourceRowRenderLightDarkAtFont130WithoutWrites() {
        val original=row(Long.MAX_VALUE,"VND",1);seed(original);seed(row(100,"VND",2));val before=rows();val queue=pending();var dark by mutableStateOf(false)
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}
        }
        val exact=java.math.BigInteger.valueOf(Long.MAX_VALUE)+java.math.BigInteger.valueOf(100)
        openDay(exact,"VND");totalExact(exact,"VND")
        val dateLayouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithTag("overview.day.date").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(dateLayouts)}
        val dateLayout=dateLayouts.single()
        val fontPixels=with(dateLayout.layoutInput.density) {dateLayout.layoutInput.style.fontSize.toPx()}
        for(line in 1 until dateLayout.lineCount) Assert.assertTrue("Full date baselines overlap: ${dateLayout.getLineBaseline(line)-dateLayout.getLineBaseline(line-1)} < $fontPixels",
            dateLayout.getLineBaseline(line)-dateLayout.getLineBaseline(line-1)+0.5f>=fontPixels)
        // performScrollTo cannot expand a partially opened sheet when its content fits the large detent.
        val travel=compose.onAllNodes(isRoot()).fetchSemanticsNodes().maxOf {it.boundsInRoot.height}*0.35f
        compose.onNodeWithText(context.getString(R.string.overview_overview_day_details)).performTouchInput {
            swipe(start=center,end=center+androidx.compose.ui.geometry.Offset(0f,-travel),durationMillis=500)
        }
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"};compose.onNodeWithTag("overview.day.total").performScrollTo();assertExactLayout("overview.day.total");capture("overview-day-$theme-font130.png")
            compose.onNodeWithTag("overview.day.amount.${original.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed().assertTextEquals("-"+formatMinorUnits(Long.MAX_VALUE,"VND"));assertExactLayout("overview.day.amount.${original.id}");capture("overview-day-row-$theme-font130.png")
        }
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
    }
    @Test fun signedSourceRowsShowExpenseDirectionOnceIncludingZeroAndLongMinimumWithoutOverflow() {
        val positive=row(100,hour=1);val negative=row(-3,hour=2);val zero=row(0,hour=3);val minimum=row(Long.MIN_VALUE,hour=4)
        listOf(positive,negative,zero,minimum,row(Long.MAX_VALUE,hour=5),row(Long.MAX_VALUE,hour=6)).forEach(::seed)
        val before=rows();val queue=pending();compose.setContent {Screen()}
        val exact=java.math.BigInteger.valueOf(Long.MAX_VALUE)+java.math.BigInteger.valueOf(96)
        openDay(exact);totalExact(exact,"JPY")
        val expected=mapOf(positive.id to "-"+formatMinorUnits(100,"JPY"),negative.id to "+"+formatMinorUnits(3,"JPY"),zero.id to "-"+formatMinorUnits(0,"JPY"),
            minimum.id to "+"+formatMinorUnits(Long.MAX_VALUE,"JPY").replace("807","808"))
        for((id,text) in expected) compose.onNodeWithTag("overview.day.amount.$id",useUnmergedTree=true).performScrollTo().assertTextEquals(text)
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
    }
    private fun assertExactLayout(tag:String) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals("Actual sheet font scale",1.3f,layout.layoutInput.density.fontScale,0.0001f);Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("$tag glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {
            val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}
        }
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable) {"Unsettled screenshot:$name"}
        java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
