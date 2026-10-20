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
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewMonthlyRawScreenTest {
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
    private val month=YearMonth.from(Instant.parse(time).atZone(zone))
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun row(amount:Long=7,kind:String="expense",date:String=time):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("title","Monthly raw");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",date);put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    @Composable private fun Screen(subject:UserId=owner,dark:Boolean=false,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode="JPY")}}
    }
    private fun value(kind:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.monthly.$kind") and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.monthly.$kind",useUnmergedTree=true).assertTextEquals(text)
    }
    private fun amount(kind:String,minor:Long)=value(kind,formatMinorUnits(minor,"JPY"))
    private fun unavailable(kind:String){value(kind,"\u2014");compose.onNodeWithTag("overview.monthly.$kind.unavailable").assertExists()}
    @Test fun requiredUnreadableExpenseHoldsWholeDirectionWhileIncomeStaysKnownUntilRawRepair() {
        val damaged=row();listOf(row(3),row(5,"income"),damaged.with("amount_minor",JsonPrimitive("broken"))).forEach(::seed)
        withoutWrites {compose.setContent {Screen()};unavailable("expense");amount("income",5)}
        seed(damaged);withoutWrites {amount("expense",10);amount("income",5)}
        seed(damaged.with("amount_minor",JsonPrimitive("7")));withoutWrites {unavailable("expense");amount("income",5)}
        seed(damaged.with("entry_status_raw_value",JsonPrimitive("draft")).with("amount_minor",JsonPrimitive("broken")));withoutWrites {amount("expense",3);amount("income",5)}
    }
    @Test fun unusedFieldsAndIndependentOverridesDoNotDropKnownMonthlyMoney() {
        val original=row();seed(original.with("destination_amount_minor",JsonPrimitive("broken")))
        withoutWrites {compose.setContent {Screen()};amount("expense",7);amount("income",0)}
        seed(original.with("created_at",JsonPrimitive("broken")));withoutWrites {amount("expense",7);amount("income",0)}
        seed(original.with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(2)).with("reporting_income_minor",JsonPrimitive(4)))
        withoutWrites {amount("expense",2);amount("income",4)}
        seed(original.with("reporting_income_minor",JsonPrimitive("broken")));withoutWrites {amount("expense",7);unavailable("income")}
    }
    @Test fun unreadableCalendarHoldsCurrentAndHistoricalCategoryMonthSummaryUntilDatedRepair() {
        val old=month.minusMonths(1).atDay(12).atStartOfDay(zone).toInstant().toString()
        val damaged=row();listOf(row(2,date=old),row(5,"income"),damaged.with("occurred_at",JsonPrimitive("broken"))).forEach(::seed)
        withoutWrites {compose.setContent {Screen()};unavailable("expense");amount("income",5)
            compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick();unavailable("expense")
            compose.onNodeWithTag("overview.category.pager").performScrollTo().performTouchInput {swipeRight()};unavailable("expense");amount("income",0)}
        seed(damaged.with("occurred_at",JsonPrimitive(old)));withoutWrites {amount("expense",9);amount("income",0)
            compose.onNodeWithTag("overview.chart.mode.day").performScrollTo().performClick();amount("expense",0);amount("income",5)}
    }
    @Test fun unknownEligibilityAndOwnerReplacementCannotPublishPartialOrPrivateTotals() {
        val original=row();seed(original.with("entry_status_raw_value",JsonPrimitive("broken")))
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};unavailable("expense");amount("income",0)}
        seed(original);withoutWrites {amount("expense",7)}
        seed(original.with("is_archived",JsonPrimitive("false")));withoutWrites {unavailable("expense")}
        seed(original.with("primary_kind_raw_value",JsonPrimitive("futureKind")));withoutWrites {unavailable("expense");unavailable("income")
            compose.runOnIdle {subject=other};amount("expense",0);amount("income",0);compose.onNodeWithTag("overview.monthly.expense.unavailable").assertDoesNotExist()}
    }
    @Test fun rawMonthlyAvailabilityHintsStayCompleteAtActual130LightAndDarkWithoutWrites() {
        listOf(row(),row(kind="income")).map {it.with("amount_minor",JsonPrimitive("broken"))}.forEach(::seed)
        var dark by mutableStateOf(false)
        var language by mutableStateOf("en")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f),
                androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {Screen(dark=dark)}}
        val hints=mapOf("en" to "Some amounts cannot be calculated yet.","vi" to "Chưa thể tính đầy đủ số tiền.","ja" to "一部の金額をまだ計算できません。")
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) withoutWrites {compose.runOnIdle {dark=theme;language=code};for(kind in listOf("income","expense")) {
            unavailable(kind);compose.onNodeWithTag("overview.monthly.$kind.unavailable").assertTextEquals(hints.getValue(code))
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("overview.monthly.$kind.unavailable",useUnmergedTree=true).performScrollTo().assertIsDisplayed()
                .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
        };capture("overview-monthly-raw-$code-${if(theme) "dark" else "light"}-font130.png")}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0;previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable){"Unsettled screenshot:$name"};java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
