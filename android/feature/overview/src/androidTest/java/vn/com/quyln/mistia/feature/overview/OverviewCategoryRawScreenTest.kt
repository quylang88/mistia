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
class OverviewCategoryRawScreenTest {
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
            put("id",id);put("user_id",owner.value);put("title","Category raw");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",date.atStartOfDay(zone).plusHours(12).toInstant().toString());put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun wallet():CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("name","Category VND");put("currency_code","VND");put("kind_raw_value","futureKind");put("opening_balance_minor","broken")
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
    private fun category() {compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick()}
    private fun value(tag:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertTextEquals(text)
    }
    private fun amount(minor:Long)=value("overview.category.amount.uncategorized-expense",formatMinorUnits(minor,"JPY"))
    private fun held() {
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.category.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.category.amount.uncategorized-expense",useUnmergedTree=true).assertDoesNotExist()
        compose.onNodeWithTag("overview.category.back").assertDoesNotExist()
    }
    @Test fun requiredBadExpenseHoldsWholeCategoryAndRepairOrDraftUpdatesWithoutWrites() {
        val damaged=row();listOf(row(3),damaged.with("amount_minor",JsonPrimitive("broken"))).forEach(::seed)
        withoutWrites {compose.setContent {Screen()};category();held()}
        seed(damaged);withoutWrites {amount(10)}
        seed(damaged.with("amount_minor",JsonPrimitive("7")));withoutWrites {held()}
        seed(damaged.with("amount_minor",JsonPrimitive("broken")).with("entry_status_raw_value",JsonPrimitive("draft")));withoutWrites {amount(3)}
    }
    @Test fun unknownOnlyHistoricalExpenseRetainsMonthNavigationAndSelectedSummary() {
        val old=today.minusMonths(2).withDayOfMonth(12);seed(row(date=old).with("amount_minor",JsonPrimitive("broken")))
        val locale=context.resources.configuration.locales[0]
        val label=old.format(java.time.format.DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale,"yMMMM"),locale))
        withoutWrites {compose.setContent {Screen()};category();reveal("overview.category.pager")
            repeat(2) {compose.onNodeWithTag("overview.category.pager").performTouchInput {swipeRight()}}
            value("overview.category.month",label);held();value("overview.monthly.expense","\u2014")}
    }
    @Test fun unusedIncomeDestinationAndCreationDoNotRemoveKnownCategoryMoney() {
        val original=row();seed(original);withoutWrites {compose.setContent {Screen()};category();amount(7)}
        for(key in listOf("reporting_income_minor","destination_amount_minor","created_at")) {
            seed(original.with(key,JsonPrimitive("broken")));withoutWrites {amount(7)}
        }
        seed(original.with("amount_minor",JsonPrimitive("broken")).with("primary_kind_raw_value",JsonPrimitive("futureKind")).with("reporting_expense_minor",JsonPrimitive(3)))
        withoutWrites {amount(3)}
    }
    @Test fun unplaceableExpenseOrUnknownEligibilityCannotLeaveAConfidentPartialCategory() {
        val original=row();listOf(row(3),original).forEach(::seed)
        withoutWrites {compose.setContent {Screen()};category();amount(10)}
        for(key in listOf("occurred_at","entry_status_raw_value","is_archived","primary_kind_raw_value","category_id")) {
            seed(original.with(key,buildJsonObject {}));withoutWrites {held()}
        }
        seed(original);withoutWrites {amount(10)}
    }
    @Test fun walletCurrencyIgnoresUnusedKindOpeningAndOwnerReplacementClearsPrivateChart() {
        val wallet=wallet();val original=row(165).with("source_wallet_id",JsonPrimitive(wallet.id)).with("source_currency_code",JsonNull);listOf(wallet,original).forEach(::seed)
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {
            override fun observeOverviewFinancialReadSnapshot(owner:UserId)=injectedOverviewReadFixture(owner,::observe)
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};category();amount(1)}
        seed(wallet.with("currency_code",JsonPrimitive("???")));withoutWrites {held()}
        seed(wallet);withoutWrites {amount(1);compose.runOnIdle {subject=other};compose.onNodeWithTag("overview.category.amount.uncategorized-expense",useUnmergedTree=true).assertDoesNotExist();compose.onNodeWithTag("overview.monthly.expense").assertTextEquals("—")}
    }
    @Test fun unreadableCategoryRelationshipAndDomainRoleCannotInventANeutralOrOrdinaryChart() {
        val category=runBlocking {repo.saveCategory(owner,CategoryDraft(name="Paid for",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()}
        val original=row(kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("borrow")).with("category_id",buildJsonObject {})
        seed(original);withoutWrites {compose.setContent {Screen()};category();held()}
        seed(original.with("category_id",JsonPrimitive(category.id)))
        withoutWrites {value("overview.category.amount.category-${category.id}",formatMinorUnits(7,"JPY"))}
        seed(original.with("category_id",JsonPrimitive(category.id)).with("primary_kind_raw_value",JsonPrimitive("expense")).with("settlement_role_raw_value",buildJsonObject {}))
        withoutWrites {held()}
    }
    @Test fun rawCategoryHintIsGenericAndCompleteAtActual130InThreeLanguagesLightDark() {
        seed(row().with("amount_minor",JsonPrimitive("broken")))
        var dark by mutableStateOf(false);var language by mutableStateOf("en")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f),
                androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {Screen(dark=dark)}}
        withoutWrites {category();held()}
        val hints=mapOf("en" to "Some amounts cannot be calculated yet.","vi" to "Ch\u01b0a th\u1ec3 t\u00ednh \u0111\u1ea7y \u0111\u1ee7 s\u1ed1 ti\u1ec1n.","ja" to "\u4e00\u90e8\u306e\u91d1\u984d\u3092\u307e\u3060\u8a08\u7b97\u3067\u304d\u307e\u305b\u3093\u3002")
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) withoutWrites {
            compose.runOnIdle {language=code;dark=theme};held();reveal("overview.category.unavailable")
            compose.onNodeWithTag("overview.category.unavailable").assertTextEquals(hints.getValue(code))
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithTag("overview.category.unavailable",useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
            for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            capture("overview-category-raw-$code-${if(theme) "dark" else "light"}-font130.png")
        }
    }
    @Test fun liveUnknownMoneyClosesDrilldownAndRepairReturnsToRootWithoutWrites() {
        val parent=runBlocking {repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()}
        val child=runBlocking {repo.saveCategory(owner,CategoryDraft(name="Grocery",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,time).getOrThrow()}
        val original=row().with("category_id",JsonPrimitive(child.id));seed(original)
        withoutWrites {compose.setContent {Screen()};category();value("overview.category.amount.category-${parent.id}",formatMinorUnits(7,"JPY"))
            compose.onNodeWithTag("overview.category.row.category-${parent.id}").performScrollTo().performTouchInput {click()}
            value("overview.category.amount.category-${child.id}",formatMinorUnits(7,"JPY"));compose.onNodeWithTag("overview.category.back").assertExists()}
        seed(original.with("amount_minor",JsonPrimitive("broken")));withoutWrites {held()}
        seed(original);withoutWrites {value("overview.category.amount.category-${parent.id}",formatMinorUnits(7,"JPY"));compose.onNodeWithTag("overview.category.back").assertDoesNotExist()}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0;previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable){"Unsettled screenshot:$name"};java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
