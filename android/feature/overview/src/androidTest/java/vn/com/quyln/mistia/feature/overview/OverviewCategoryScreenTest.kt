package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
import java.time.*
import java.time.temporal.ChronoUnit
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
class OverviewCategoryScreenTest {
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
    private val month=YearMonth.from(today)
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private val rateRows=MutableStateFlow(emptyList<ExchangeRateSnapshot>())
    private val rates=object:ExchangeRateRepository {
        override val rates=rateRows
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
    }
    private fun category(name:String,parent:String?=null)=runBlocking {repo.saveCategory(owner,CategoryDraft(name=name,nameLanguage=CategoryNameLanguage.ENGLISH,
        kind=TransactionCategoryKind.EXPENSE,hierarchyRole=if(parent==null) CategoryHierarchyRole.PARENT else CategoryHierarchyRole.CHILD,parentCategoryId=parent),device,time).getOrThrow()}
    private fun row(amount:Long=100,category:String?=null,date:LocalDate=today,code:String="JPY",kind:String="expense"):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Category row")
            put("amount_minor",amount);put("source_currency_code",code);put("occurred_at",date.atStartOfDay(zone).plusHours(12).toInstant().toString());put("created_at",time);put("updated_at",time);put("is_archived",false)
            category?.let {put("category_id",it)}
        },time,null,0)
    }
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.TRANSACTION_CATEGORY,CloudEntity.LEDGER_WALLET).associateWith {repo.observe(it,owner).first() to store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo,primary:String="JPY",dark:Boolean=false) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)
        }}
    }
    private fun openCategory() {
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.chart.mode.category").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick()
    }
    private fun legend(id:String)=compose.onNodeWithTag("overview.category.row.$id")
    private fun value(id:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(id) and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(id,useUnmergedTree=true).assertTextEquals(text)
    }
    private fun amount(id:String,minor:Long,code:String="JPY")=value("overview.category.amount.$id",formatMinorUnits(minor,code))
    private fun tap(id:String)=legend(id).performScrollTo().performTouchInput {click()}
    private fun back()=compose.onNodeWithTag("overview.category.back").performScrollTo().performTouchInput {click()}
    @Test fun realRoomBranchRollupExactLegendBackAndPhysicalPieSelectionNeverWrite() {
        val food=category("Food");val grocery=category("Grocery",food.id);val dining=category("Dining",food.id);val health=category("Health")
        listOf(row(9007199254740993L,grocery.id),row(3000,dining.id),row(1000,food.id),row(2000,health.id)).forEach(::seed)
        val before=snapshot();compose.setContent {Screen()};openCategory();amount("category-${food.id}",9007199254744993L)
        tap("category-${food.id}");amount("category-${grocery.id}",9007199254740993L);amount("category-${dining.id}",3000);amount("category-${food.id}",1000)
        back();amount("category-${food.id}",9007199254744993L)
        compose.onNodeWithTag("overview.category.pie").performScrollTo().performTouchInput {click(androidx.compose.ui.geometry.Offset(width*0.75f,height*0.5f))}
        compose.onNodeWithTag("overview.category.back").assertExists();amount("category-${grocery.id}",9007199254740993L)
        Assert.assertEquals(before,snapshot())
    }
    @Test fun importedNamesWithUnicodeSpacesMergeOnAndroidWithoutRegexRuntimeFailure() {
        val first=category("Ăn uống")
        val text=java.text.Normalizer.normalize(" ăn\u00a0\u0085\u3000 UỐNG ",java.text.Normalizer.Form.NFD)
        val second=first.copy(id=UUID.randomUUID().toString(),name=text,nameEnglish=text)
        seed(second.toCloudRecord());seed(row(5000,first.id));seed(row(3000,second.id))
        val before=snapshot();compose.setContent {Screen()};openCategory()
        val candidates=hasTestTag("overview.category.amount.category-${first.id}") or hasTestTag("overview.category.amount.category-${second.id}")
        compose.waitUntil(5000) {compose.onAllNodes(candidates and hasText(formatMinorUnits(8000,"JPY")),useUnmergedTree=true).fetchSemanticsNodes().size==1}
        compose.onAllNodes(candidates,useUnmergedTree=true).assertCountEquals(1);Assert.assertEquals(before,snapshot())
    }
    @Test fun rootOtherContainsRemainingThreeAndDrilldownRowsHaveNoFurtherClickAction() {
        val cats=(8L downTo 1).map {category("Group $it") to it};cats.forEach {(cat,amount)->seed(row(amount,cat.id))}
        val before=snapshot();compose.setContent {Screen()};openCategory()
        val otherId="other-root-$month";amount(otherId,6);legend(otherId).assertHasClickAction();tap(otherId)
        cats.drop(5).forEach {(cat,n)->amount("category-${cat.id}",n);legend("category-${cat.id}").assert(!hasClickAction())}
        back();amount(otherId,6);Assert.assertEquals(before,snapshot())
    }
    @Test fun historicalMonthControlsCashflowWhileModeSwitchRetainsWeekAndMonthAndPrependedHistory() {
        val food=category("Food");val oldMonday=monday.minusWeeks(5);val oldMonth=YearMonth.from(oldMonday)
        listOf(row(100,food.id,oldMonday),row(200,food.id),row(50,date=oldMonday,kind="income"),row(70,kind="income")).forEach(::seed)
        compose.setContent {Screen()}
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and hasContentDescription(formatMinorUnits(200,"JPY"),substring=true)).fetchSemanticsNodes().isNotEmpty()}
        repeat(5) {compose.onNodeWithTag("overview.chart.pager").performScrollTo().performTouchInput {swipeRight()}}
        compose.onNodeWithTag("overview.chart.day.$oldMonday").performScrollTo().performClick();compose.onNodeWithTag("overview.chart.selection").assertExists()
        openCategory();compose.onNodeWithTag("overview.chart.selection").assertDoesNotExist()
        repeat(ChronoUnit.MONTHS.between(oldMonth,month).toInt()) {compose.onNodeWithTag("overview.category.pager").performScrollTo().performTouchInput {swipeRight()}}
        amount("category-${food.id}",100);value("overview.monthly.expense",formatMinorUnits(100,"JPY"));value("overview.monthly.income",formatMinorUnits(50,"JPY"))
        compose.onNodeWithTag("overview.chart.mode.day").performScrollTo().performClick()
        compose.onNodeWithTag("overview.chart.day.$oldMonday").assertIsDisplayed();value("overview.monthly.expense",formatMinorUnits(200,"JPY"));value("overview.monthly.income",formatMinorUnits(70,"JPY"))
        openCategory();amount("category-${food.id}",100)
        seed(row(10,food.id,oldMonth.minusMonths(1).atDay(15)));amount("category-${food.id}",100);value("overview.monthly.income",formatMinorUnits(50,"JPY"))
    }
    @Test fun removedHistoricalMonthResetsCurrentAndReappearingHistoryDoesNotRestoreStaleDrilldown() {
        val food=category("Food");val old=row(100,food.id,month.minusMonths(1).atDay(15));val current=row(200,food.id)
        val raw=MutableStateFlow(listOf(old,current))
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) raw else repo.observe(entity,ownerUserId)}
        val before=snapshot();compose.setContent {Screen(source=source)};openCategory();amount("category-${food.id}",200)
        compose.onNodeWithTag("overview.category.pager").performScrollTo().performTouchInput {swipeRight()};amount("category-${food.id}",100);tap("category-${food.id}")
        compose.runOnIdle {raw.value=listOf(current)};amount("category-${food.id}",200);compose.onNodeWithTag("overview.category.back").assertDoesNotExist()
        compose.runOnIdle {raw.value=listOf(old,current)};amount("category-${food.id}",200);value("overview.monthly.expense",formatMinorUnits(200,"JPY"));Assert.assertEquals(before,snapshot())
    }
    @Test fun livePrimaryRatesMissingConversionAndCategoryArchiveUpdatesNeverLeaveStaleDrilldown() {
        val food=category("Food");val original=row(3,food.id).with("reporting_currency_code" to JsonPrimitive("VND"),"reporting_amount_minor" to JsonPrimitive(999));seed(original)
        var primary by mutableStateOf("JPY");val before=snapshot();compose.setContent {Screen(primary=primary)};openCategory();amount("category-${food.id}",3);tap("category-${food.id}")
        compose.runOnIdle {primary="VND"};compose.onNodeWithTag("overview.category.unavailable").assertExists();compose.onNodeWithTag("overview.category.pie").assertDoesNotExist();compose.onNodeWithTag("overview.category.back").assertDoesNotExist()
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null))};amount("category-${food.id}",8,"VND");Assert.assertEquals(before,snapshot())
        runBlocking {repo.saveCategory(owner,CategoryDraft(id=food.id,name="Updated",nameLanguage=CategoryNameLanguage.ENGLISH,kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()}
        compose.waitUntil(5000) {compose.onAllNodesWithText("Updated").fetchSemanticsNodes().isNotEmpty()}
        seed(original.with("is_archived" to JsonPrimitive(true)));compose.waitUntil(5000) {compose.onAllNodesWithText(context.getString(R.string.core_ui_mistiacategoryspendingchart_no_spending_yet)).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.category.pie").assertDoesNotExist()
    }
    @Test fun ownerReplacementBeforeNextFlowEmitsClearsPrivateBranchAndDrilldown() {
        val food=category("Private Branch");seed(row(123456789,food.id));var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        val before=snapshot();compose.setContent {Screen(subject,source)};openCategory();amount("category-${food.id}",123456789);tap("category-${food.id}")
        compose.runOnIdle {subject=other};compose.onAllNodesWithText("Private Branch").assertCountEquals(0);compose.onNodeWithTag("overview.category.back").assertDoesNotExist();legend("category-${food.id}").assertDoesNotExist();Assert.assertEquals(before,snapshot())
    }
    @Test fun categoryModeLabelsAndSystemNameFallbackFollowEnglishVietnameseJapanese() {
        val catalog=SystemCategoryCatalog.parse(context.assets.open("MistiaSystemCategories.json").bufferedReader().use {it.readText()})
        val definition=catalog.activeDefinitions.first {it.parentKey==null && it.kind==TransactionCategoryKind.EXPENSE}
        val system=category("Tên gốc").copy(systemKey=definition.key,isSystem=true,nameEnglish=null,nameJapanese=null);seed(system.toCloudRecord());seed(row(100,system.id));var language by mutableStateOf("en")
        compose.setContent {val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {Screen()}}
        for(code in listOf("en","vi","ja")) {
            compose.runOnIdle {language=code};openCategory();amount("category-${system.id}",100)
            val expected=if(code=="vi") "Tên gốc" else definition.translations.getValue(code)
            compose.onNodeWithText(expected).assertExists();compose.onNodeWithTag("overview.category.month").assert(hasText(month.year.toString(),substring=true))
        }
    }
    @Test fun sixLegendsAndDrilldownKeepExactBeyondLongValuesAtActualFont130LightDarkWithoutWrites() {
        val palette=listOf("#F45C7E","#2DAA9E","#5B7BFF","#FF8A4C","#9A67FF","#7C85A3","#FFB347")
        val cats=(1..7).map {index ->category("Branch $index").copy(iconColorHex=palette[index-1]).also {seed(it.toCloudRecord())}}
        cats.forEach {seed(row(Long.MAX_VALUE,it.id,code="VND"))};val child=category("Child",cats.first().id);seed(row(100,child.id,code="VND"))
        val before=snapshot();var dark by mutableStateOf(false)
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}}
        openCategory();val otherId="other-root-$month";val exactOther=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"};value("overview.category.amount.$otherId",formatMinorUnits(exactOther,"VND"))
            revealCategory("overview.category.amount.$otherId")
            cats.take(5).forEach {cat ->assertExact("overview.category.amount.category-${cat.id}")}
            assertExact("overview.category.amount.$otherId");capture("overview-category-$theme-font130.png")
            revealCategory("overview.category.row.category-${cats.first().id}")
            legend("category-${cats.first().id}").performTouchInput {click()};amount("category-${cats.first().id}",Long.MAX_VALUE,"VND")
            revealCategory("overview.category.amount.category-${cats.first().id}")
            assertExact("overview.category.amount.category-${cats.first().id}")
            assertExact("overview.category.amount.category-${child.id}")
            revealCategory("overview.category.amount.category-${child.id}")
            capture("overview-category-drill-$theme-font130.png");back()
        }
        Assert.assertEquals(before,snapshot())
    }
    @Test fun narrowNormalFontKeepsBeyondLongLegendMoneyComplete() {
        val food=category("Food");val child=category("Child",food.id);val others=(1..6).map {category("Group $it")}
        listOf(row(Long.MAX_VALUE,food.id,code="VND"),row(Long.MAX_VALUE,child.id,code="VND")).forEach(::seed)
        others.forEach {seed(row(Long.MAX_VALUE,it.id,code="VND"))}
        val before=snapshot()
        compose.setContent {androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.width(364.dp)) {Screen(primary="VND")}}
        openCategory();value("overview.category.amount.category-${food.id}",formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"VND"))
        assertExact("overview.category.amount.category-${food.id}",1f)
        assertExact("overview.category.amount.other-root-$month",1f);Assert.assertEquals(before,snapshot())
    }
    @Test fun removedAndReappearingMonthWhileDayModeDoesNotRestoreHistoricalMonth() {
        val food=category("Food");val old=row(100,food.id,month.minusMonths(1).atDay(15));val current=row(200,food.id)
        val raw=MutableStateFlow(listOf(old,current))
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) raw else repo.observe(entity,ownerUserId)}
        val before=snapshot();compose.setContent {Screen(source=source)};openCategory()
        compose.onNodeWithTag("overview.category.pager").performScrollTo().performTouchInput {swipeRight()};amount("category-${food.id}",100)
        compose.onNodeWithTag("overview.chart.mode.day").performScrollTo().performClick()
        compose.runOnIdle {raw.value=listOf(current.with("amount_minor" to JsonPrimitive(201)))};value("overview.monthly.expense",formatMinorUnits(201,"JPY"))
        compose.runOnIdle {raw.value=listOf(old,current)};value("overview.monthly.expense",formatMinorUnits(200,"JPY"))
        openCategory();amount("category-${food.id}",200);Assert.assertEquals(before,snapshot())
    }
    @Test fun removedAndReappearingWeekWhileCategoryModeDoesNotRestoreHistoricalWeek() {
        val food=category("Food");val oldMonday=monday.minusWeeks(5);val old=row(100,food.id,oldMonday);val current=row(200,food.id)
        val raw=MutableStateFlow(listOf(old,current))
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) raw else repo.observe(entity,ownerUserId)}
        val before=snapshot();compose.setContent {Screen(source=source)}
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and hasContentDescription(formatMinorUnits(200,"JPY"),substring=true)).fetchSemanticsNodes().isNotEmpty()}
        repeat(5) {compose.onNodeWithTag("overview.chart.pager").performScrollTo().performTouchInput {swipeRight()}}
        compose.onNodeWithTag("overview.chart.day.$oldMonday").assertIsDisplayed();openCategory();amount("category-${food.id}",200)
        compose.runOnIdle {raw.value=listOf(current.with("amount_minor" to JsonPrimitive(201)))};value("overview.monthly.expense",formatMinorUnits(201,"JPY"))
        compose.runOnIdle {raw.value=listOf(old,current)};value("overview.monthly.expense",formatMinorUnits(200,"JPY"))
        compose.onNodeWithTag("overview.chart.mode.day").performScrollTo().performClick()
        compose.onNodeWithTag("overview.chart.day.$today").assertIsDisplayed();Assert.assertEquals(before,snapshot())
    }
    private fun revealCategory(tag:String) {
        // performScrollTo stops at the horizontal pager; scroll the outer list vertically.
        val scroll=compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange))
        scroll.performScrollToIndex(1)
        repeat(8) {
            val target=compose.onNodeWithTag(tag,useUnmergedTree=true)
            if(runCatching {target.assertIsDisplayed()}.isSuccess) return
            scroll.performTouchInput {swipe(androidx.compose.ui.geometry.Offset(centerX,height*0.65f),androidx.compose.ui.geometry.Offset(centerX,height*0.45f),durationMillis=1000)}
        }
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()
    }
    private fun assertExact(tag:String,expectedFontScale:Float=1.3f) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals(expectedFontScale,layout.layoutInput.density.fontScale,0.0001f);Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("$tag glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
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
