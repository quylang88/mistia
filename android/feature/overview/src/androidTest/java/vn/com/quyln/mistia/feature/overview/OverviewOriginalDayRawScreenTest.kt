package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewOriginalDayRawScreenTest {
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
    private val rateRows=MutableStateFlow(listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)))
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun row(amount:Long=7,kind:String="expense",date:LocalDate=today):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("title","Original raw");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",date.atStartOfDay(zone).plusHours(12).toInstant().toString());put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun wallet():CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("name","Day VND");put("currency_code","VND");put("kind_raw_value","futureKind");put("opening_balance_minor","broken")
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    @Composable private fun Screen(subject:UserId=owner,dark:Boolean=false,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode="JPY",exchangeRates=rates)}}
    }
    private fun reveal(tag:String) {
        val scroll=compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange));scroll.performScrollToIndex(1)
        repeat(5) {if(runCatching {compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()}.isSuccess) return
            scroll.performTouchInput {swipe(androidx.compose.ui.geometry.Offset(centerX,height*0.65f),androidx.compose.ui.geometry.Offset(centerX,height*0.45f),1000)}}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()
    }
    private fun value(tag:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertTextEquals(text)
    }
    private fun hold() {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.OnLongClick)).fetchSemanticsNodes().isNotEmpty()}
        reveal("overview.chart.day.$today");compose.onNodeWithTag("overview.chart.day.$today").performTouchInput {down(center);advanceEventTime(400);up()}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.day.sheet").fetchSemanticsNodes().isNotEmpty()}
    }
    private fun expand(title:String="Day details") {
        val travel=compose.onAllNodes(isRoot()).fetchSemanticsNodes().maxOf {it.boundsInRoot.height}*0.35f
        compose.onNodeWithText(title).performTouchInput {swipe(center,center+androidx.compose.ui.geometry.Offset(0f,-travel),500)}
    }
    @Test fun liveUnreadableOriginalRemainsCountedWithUnknownMoneyAndRepairIsReadOnly() {
        val original=row();seed(original)
        withoutWrites {compose.setContent {Screen()};hold();value("overview.day.count","1")}
        for(value in listOf(JsonPrimitive("broken"),JsonPrimitive("7"),JsonPrimitive(1.5))) {
            seed(original.with("amount_minor",value));withoutWrites {value("overview.day.total","\u2014");value("overview.day.count","1");value("overview.day.amount.${original.id}","\u2014")}
        }
        seed(original);withoutWrites {value("overview.day.total",formatMinorUnits(7,"JPY"));value("overview.day.count","1")}
    }
    @Test fun liveUnknownEligibilityOrDateCannotClaimEmptyDayAndKnownExclusionCan() {
        val original=row();seed(original);withoutWrites {compose.setContent {Screen()};hold()}
        for(key in listOf("occurred_at","entry_status_raw_value","is_archived","primary_kind_raw_value")) {
            seed(original.with(key,JsonPrimitive("broken")));withoutWrites {value("overview.day.total","\u2014");value("overview.day.count","\u2014");compose.onNodeWithTag("overview.day.entries.unavailable").assertExists()}
        }
        for(excluded in listOf(original.with("entry_status_raw_value",JsonPrimitive("draft")),original.with("occurred_at",JsonPrimitive(today.minusDays(1).atStartOfDay(zone).toInstant().toString())))) {
            seed(excluded);withoutWrites {value("overview.day.total",formatMinorUnits(0,"JPY"));value("overview.day.count","0");compose.onNodeWithTag("overview.day.entries.unavailable").assertDoesNotExist()}
        }
        seed(original);withoutWrites {value("overview.day.total",formatMinorUnits(7,"JPY"));value("overview.day.count","1")}
    }
    @Test fun unusedFieldsDoNotRemoveOriginalDayMoneyOrIdentity() {
        val original=row();seed(original);withoutWrites {compose.setContent {Screen()};hold()}
        for(key in listOf("created_at","reporting_expense_minor","reporting_income_minor","destination_amount_minor")) {
            seed(original.with(key,JsonPrimitive("broken")));withoutWrites {value("overview.day.total",formatMinorUnits(7,"JPY"));value("overview.day.count","1");value("overview.day.amount.${original.id}","-"+formatMinorUnits(7,"JPY"))}
        }
    }
    @Test fun reportingOverrideCanOpenUnreadableOriginal() {
        val original=row().with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(3));seed(original)
        withoutWrites {compose.setContent {Screen()};hold();value("overview.day.count","1");value("overview.day.total","\u2014")}
    }
    @Test fun originalCurrencyAndWalletNameSurviveUnusedWalletDamageAndOwnerClosesSheet() {
        val wallet=wallet();val original=row(165).with("source_wallet_id",JsonPrimitive(wallet.id)).with("source_currency_code",JsonNull);listOf(wallet,original).forEach(::seed)
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};hold();value("overview.day.total",formatMinorUnits(1,"JPY"));expand()
            compose.onNodeWithTag("overview.day.amount.${original.id}",useUnmergedTree=true).performScrollTo().assertTextEquals("-"+formatMinorUnits(165,"VND"))
            compose.onNodeWithText("Day VND",substring=true).assertExists();compose.runOnIdle {subject=other};compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()}
    }
    @Test fun reportingOnlyIncomeCannotOpenAnEmptyOriginalDay() {
        seed(row(kind="income").with("reporting_expense_minor",JsonPrimitive(3)))
        withoutWrites {compose.setContent {Screen()}
            compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.OnLongClick)).fetchSemanticsNodes().isNotEmpty()}
            reveal("overview.chart.day.$today");compose.onNodeWithTag("overview.chart.day.$today").performTouchInput {down(center);advanceEventTime(400);up()}
            compose.waitForIdle();compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()}
    }
    @Test fun unknownMoneyAndUnknownCountRemainCompleteAtActual130InThreeLanguagesLightDark() {
        val original=row().with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(3));seed(original)
        var dark by mutableStateOf(false);var language by mutableStateOf("en")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f),
                androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {Screen(dark=dark)}}
        withoutWrites {hold();expand()}
        val moneyHints=mapOf("en" to "Some amounts cannot be calculated yet.","vi" to "Ch\u01b0a th\u1ec3 t\u00ednh \u0111\u1ea7y \u0111\u1ee7 s\u1ed1 ti\u1ec1n.","ja" to "\u4e00\u90e8\u306e\u91d1\u984d\u3092\u307e\u3060\u8a08\u7b97\u3067\u304d\u307e\u305b\u3093\u3002")
        val entryHints=mapOf("en" to "Some expense details are unavailable.","vi" to "Ch\u01b0a c\u00f3 \u0111\u1ee7 th\u00f4ng tin v\u1ec1 m\u1ed9t s\u1ed1 kho\u1ea3n chi.","ja" to "\u4e00\u90e8\u306e\u652f\u51fa\u306e\u8a73\u7d30\u304c\u4e0d\u660e\u3067\u3059\u3002")
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) {
            seed(original)
            withoutWrites {compose.runOnIdle {language=code;dark=theme};value("overview.day.count","1");value("overview.day.total","\u2014")
                value("overview.day.total.unavailable",moneyHints.getValue(code));assertComplete("overview.day.total.unavailable");assertComplete("overview.day.count")
                compose.onNodeWithTag("overview.day.amount.${original.id}",useUnmergedTree=true).performScrollTo().assertIsDisplayed();assertComplete("overview.day.amount.${original.id}")
                capture("overview-day-raw-money-$code-${if(theme) "dark" else "light"}-font130.png")}
            seed(original.with("entry_status_raw_value",JsonPrimitive("unknown")))
            withoutWrites {value("overview.day.count","\u2014");value("overview.day.entries.unavailable",entryHints.getValue(code))
                compose.onNodeWithTag("overview.day.entries.unavailable").performScrollTo().assertIsDisplayed();assertComplete("overview.day.entries.unavailable");assertComplete("overview.day.count")
                capture("overview-day-raw-count-$code-${if(theme) "dark" else "light"}-font130.png")}
        }
    }
    private fun assertComplete(tag:String) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
        Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
        for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0;previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable){"Unsettled screenshot:$name"};java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
