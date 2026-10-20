package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.getOrNull
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
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class BudgetExactReadScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var parent:TransactionCategoryRecord
    private lateinit var child:TransactionCategoryRecord
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time=Instant.now().toString()
    private val zone=ZoneId.systemDefault()
    private val month=YearMonth.now(zone)
    private val rateRows=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        parent=repo.saveCategory(owner,CategoryDraft(name="Living",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()
        child=repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,time).getOrThrow()
    }
    private fun plan(code:String="JPY",limit:Long=1000)=runBlocking {
        repo.saveBudget(owner,BudgetDraft(child.id,month.atDay(1).atStartOfDay(zone).toInstant().toString(),limit,code,zoneId=zone),device,time).getOrThrow()
    }
    private fun row(amount:Long=7,code:String?="JPY",wallet:String?=null):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("title","Budget exact read");put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code",code?.let(::JsonPrimitive) ?: JsonNull);put("category_id",child.id);wallet?.let {put("source_wallet_id",it)}
            put("is_archived",false);put("occurred_at",time);put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.BUDGET_PLAN,CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    @Composable private fun Screen(subject:UserId=owner,primary:String="JPY",source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=false) {PlanningScreen(subject,source,deviceIdProvider={device},exchangeRateRepository=rates,primaryCurrencyCode=primary)}
    }
    private fun contains(tag:String,text:String) {
        val exact=SemanticsMatcher("exact complete budget amount") {node ->
            node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Text)?.singleOrNull()?.text?.let {it==text || it.endsWith(": $text")}==true
        }
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and exact,useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assert(exact)
    }
    @Test fun missingExpenseFxNeverShowsZeroSpentAndRateRepairOrRemovalIsReadOnly() {
        plan("VND",2000);seed(row())
        withoutWrites {compose.setContent {Screen(primary="VND")};contains("budget.summary.spent","\u2014");contains("budget.summary.remaining","\u2014")
            compose.onAllNodesWithText(context.getString(R.string.shared_corelogic_planning_stable)).assertCountEquals(0)}
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null))}
        withoutWrites {contains("budget.summary.spent",formatMinorUnits(1155,"VND"));contains("budget.summary.remaining",formatMinorUnits(845,"VND"))}
        compose.runOnIdle {rateRows.value=emptyList()};withoutWrites {contains("budget.summary.spent","\u2014");contains("budget.summary.remaining","\u2014")}
    }
    @Test fun twiceMaximumPostedExpenseRetainsExactSummaryAndStoredRowsWithoutWrites() {
        plan(limit=Long.MAX_VALUE);repeat(2) {seed(row(Long.MAX_VALUE))}
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent",formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"JPY"));contains("budget.summary.remaining",formatMinorUnits(0,"JPY"))}
    }
    @Test fun importedChildAllocationsAboveLongRetainExactDerivedBranchLimitAndSummary() {
        val first=plan(limit=Long.MAX_VALUE)
        val secondChild=runBlocking {repo.saveCategory(owner,CategoryDraft(name="Travel",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,time).getOrThrow()}
        seed(first.copy(id=UUID.randomUUID().toString(),categoryId=secondChild.id,categoryIdSnapshot=secondChild.id,categoryNameSnapshot="Travel",categoryNameEnglishSnapshot="Travel").toCloudRecord())
        withoutWrites {compose.setContent {Screen()};val exact=formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"JPY");contains("budget.summary.limit",exact);contains("budget.summary.remaining",exact)}
    }
    @Test fun ownedWalletSourceCurrencyIsNotLostAndOwnerReplacementCannotExposeOldBudget() {
        plan("VND")
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Private VND",kind=WalletKind.CASH,currencyCode="VND"),device,time).getOrThrow()}
        seed(row(165,code=null,wallet=wallet.id));var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,primary="VND",source=source)};contains("budget.summary.spent",formatMinorUnits(165,"VND"))
            compose.runOnIdle {subject=other};contains("budget.summary.limit",formatMinorUnits(0,"VND"));contains("budget.summary.spent",formatMinorUnits(0,"VND"))
            compose.onNodeWithText("Food").assertDoesNotExist()}
    }    @Test fun unknownRequiredTransferClassificationCannotPublishZeroAndRepairIsReadOnly() {
        plan();val original=row().let {it.copy(payload=JsonObject(it.payload+mapOf("primary_kind_raw_value" to JsonPrimitive("transfer"),"transfer_subtype_raw_value" to JsonPrimitive("futureSubtype"),"debt_intent_raw_value" to JsonPrimitive("borrow"))))};seed(original)
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent","\u2014");contains("budget.summary.remaining","\u2014")}
        seed(original.copy(payload=JsonObject(original.payload+("transfer_subtype_raw_value" to JsonPrimitive("debt")))))
        withoutWrites {contains("budget.summary.spent",formatMinorUnits(7,"JPY"));contains("budget.summary.remaining",formatMinorUnits(993,"JPY"))}
    }
    @Test fun budgetExactAndUnavailableReadRemainCompleteAndLocalizedAtActual130LightDark() {
        val original=plan(limit=Long.MAX_VALUE).copy(categoryNameSnapshot="\u0102n u\u1ed1ng",categoryNameEnglishSnapshot="Food",categoryNameJapaneseSnapshot="\u98df\u8cbb")
        seed(original.toCloudRecord());repeat(2) {seed(row(Long.MAX_VALUE))}
        var language by mutableStateOf("en");var dark by mutableStateOf(false);var primary by mutableStateOf("JPY")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=dark) {androidx.compose.material3.Surface {PlanningScreen(owner,repo,deviceIdProvider={device},exchangeRateRepository=rates,primaryCurrencyCode=primary)}}
            }}
        val names=mapOf("en" to "Food","vi" to "\u0102n u\u1ed1ng","ja" to "\u98df\u8cbb")
        val exact=formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"JPY")
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) withoutWrites {
            compose.runOnIdle {language=code;dark=theme;primary="JPY"};contains("budget.summary.spent",exact)
            compose.onNodeWithTag("budget.edit.${original.id}").performScrollTo().assertIsDisplayed()
            compose.onNodeWithText(names.getValue(code)).assertExists()
            assertComplete("budget.money.branch-${parent.id}")
            compose.onNodeWithTag("budget.summary.spent").performScrollTo().assertIsDisplayed();assertComplete("budget.summary.spent");assertComplete("budget.summary.limit");assertComplete("budget.summary.remaining")
            compose.onNodeWithTag("budget.screen").performScrollToIndex(0)
            capture("budget-exact-read-$code-${if(theme) "dark" else "light"}-font130.png")
            compose.runOnIdle {primary="VND"};contains("budget.summary.spent","\u2014");contains("budget.summary.limit","\u2014");contains("budget.summary.remaining","\u2014")
            compose.onNodeWithTag("budget.summary.unavailable").performScrollTo().assertIsDisplayed();assertComplete("budget.summary.unavailable")
            compose.onNodeWithTag("budget.screen").performScrollToIndex(0)
            capture("budget-exact-unavailable-$code-${if(theme) "dark" else "light"}-font130.png")
        }
    }
    @Test fun archivedWalletStillSuppliesHistoricalCurrencyForLegacyBudgetSpending() {
        plan("VND")
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Historical VND",kind=WalletKind.CASH,currencyCode="VND"),device,time).getOrThrow()}
        seed(wallet.copy(isArchived=true).toCloudRecord());seed(row(165,code=null,wallet=wallet.id))
        withoutWrites {compose.setContent {Screen(primary="VND")};contains("budget.summary.spent",formatMinorUnits(165,"VND"));contains("budget.summary.remaining",formatMinorUnits(835,"VND"))}
    }
    @Test fun archivedCreditKindStillClassifiesItsOriginalExpenseCardTitleCorrectly() {
        plan();val id=UUID.randomUUID().toString()
        seed(CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("name","Historical card");put("kind_raw_value","creditCard");put("currency_code","JPY");put("opening_balance_minor",0);put("is_archived",true)
        },time,null,0))
        val original=row(100,wallet=id);seed(original.copy(payload=JsonObject(original.payload+("title" to JsonPrimitive("Card payment")))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent",formatMinorUnits(100,"JPY"));contains("budget.summary.remaining",formatMinorUnits(900,"JPY"))}
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
