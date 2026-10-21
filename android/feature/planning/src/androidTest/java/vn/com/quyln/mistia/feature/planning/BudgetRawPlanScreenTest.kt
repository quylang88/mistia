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
class BudgetRawPlanScreenTest {
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
    @Test fun unreadableOnlyPlanCannotBecomeZeroAndRepairNeverWritesFromRead() {
        val original=plan(limit=9007199254740993L);val raw=original.toCloudRecord()
        seed(raw.copy(payload=JsonObject(raw.payload+("limit_minor" to JsonPrimitive("9007199254740993")))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit","\u2014");contains("budget.summary.spent","\u2014")
            compose.onNodeWithText(context.getString(R.string.planning_planning_no_budgets_yet)).assertDoesNotExist()}
        seed(raw);withoutWrites {contains("budget.summary.limit",formatMinorUnits(original.limitMinor,"JPY"));contains("budget.summary.spent",formatMinorUnits(0,"JPY"))}
        seed(raw.copy(payload=JsonObject(raw.payload+("limit_minor" to JsonNull))))
        withoutWrites {contains("budget.summary.limit","\u2014");contains("budget.summary.remaining","\u2014")}
    }
    @Test fun invalidNewestMonthCannotReviveAnOlderHealthyBudget() {
        val original=plan(limit=1000);val raw=original.toCloudRecord()
        val old=original.copy(id=UUID.randomUUID().toString(),monthAnchor=month.minusMonths(1).atDay(1).atStartOfDay(zone).toInstant().toString(),limitMinor=500)
        seed(old.toCloudRecord());seed(raw.copy(payload=JsonObject(raw.payload+("month_anchor" to JsonPrimitive("broken")))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit","\u2014");compose.onAllNodesWithText(context.getString(R.string.shared_corelogic_planning_stable)).assertCountEquals(0)}
        seed(raw);withoutWrites {contains("budget.summary.limit",formatMinorUnits(1000,"JPY"))}
    }
    @Test fun uncertainArchiveOrDeletionReachesTheRealRoomReadAndKnownArchiveRepairsIt() {
        val original=plan();val raw=original.toCloudRecord()
        seed(raw.copy(payload=JsonObject(raw.payload+("is_archived" to JsonPrimitive("false")))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit","\u2014")}
        seed(raw.copy(payload=JsonObject(raw.payload+("deleted_at" to buildJsonObject {put("bad",true)}))))
        withoutWrites {contains("budget.summary.limit","\u2014");contains("budget.summary.remaining","\u2014")}
        seed(original.copy(isArchived=true).toCloudRecord())
        withoutWrites {contains("budget.summary.limit",formatMinorUnits(0,"JPY"));contains("budget.summary.spent",formatMinorUnits(0,"JPY"))}
    }
    @Test fun missingAllocationCannotBecomeNoBudgetsAndRepairRemainsReadOnly() {
        val original=plan();seed(original.copy(categoryId=null,categoryIdSnapshot=null,categoryParentIdSnapshot=null).toCloudRecord())
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit","\u2014");compose.onNodeWithText(context.getString(R.string.planning_planning_no_budgets_yet)).assertDoesNotExist()}
        seed(original.toCloudRecord());withoutWrites {contains("budget.summary.limit",formatMinorUnits(1000,"JPY"))}
    }
    @Test fun nonpositiveSavedLimitCannotClaimStableOrNegativeBudgetMoney() {
        val original=plan();seed(original.copy(limitMinor=-1).toCloudRecord())
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit","\u2014");compose.onAllNodesWithText(context.getString(R.string.shared_corelogic_planning_stable)).assertCountEquals(0)}
        seed(original.toCloudRecord());withoutWrites {contains("budget.summary.limit",formatMinorUnits(1000,"JPY"))}
    }
    @Test fun rawRowTapStillOpensStoredPlanWhenTheTypedEditorStreamHasNotEmitted() {
        val original=plan()
        val source=object:FinanceRepository by repo {override fun observeBudgets(ownerUserId:UserId):Flow<List<BudgetPlanRecord>> = emptyFlow()}
        withoutWrites {compose.setContent {Screen(source=source)};contains("budget.summary.limit",formatMinorUnits(1000,"JPY"))
            compose.onNodeWithTag("budget.edit.${original.id}").performScrollTo().performClick()
            compose.onNodeWithTag("budget.amount").assertTextContains("1,000")}
    }

}
