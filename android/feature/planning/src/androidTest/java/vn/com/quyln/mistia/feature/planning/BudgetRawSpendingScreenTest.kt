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
class BudgetRawSpendingScreenTest {
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
        try {compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and exact,useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}}
        catch(error:Throwable) {
            val actual=compose.onAllNodesWithTag(tag,useUnmergedTree=true).fetchSemanticsNodes().map {it.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Text)}
            throw AssertionError("Expected$tag=$text; actual=$actual",error)
        }
        compose.onNodeWithTag(tag,useUnmergedTree=true).assert(exact)
    }
    @Test fun requiredQuotedOriginalNeverBecomesKnownMoneyAndRepairIsReadOnly() {
        plan();val raw=row();seed(raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive("7")))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit",formatMinorUnits(1000,"JPY"));contains("budget.summary.spent","\u2014");contains("budget.summary.remaining","\u2014")}
        seed(raw);withoutWrites {contains("budget.summary.spent",formatMinorUnits(7,"JPY"));contains("budget.summary.remaining",formatMinorUnits(993,"JPY"))}
    }
    @Test fun rawDeletionAndArchiveUncertaintyCannotVanishFromTheBudget() {
        plan();val raw=row();seed(raw)
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent",formatMinorUnits(7,"JPY"))}
        for((key,value) in listOf("deleted_at" to buildJsonObject {put("bad",true)},"deleted_at" to JsonPrimitive("broken"),"is_archived" to JsonPrimitive("false"),"entry_status_raw_value" to buildJsonObject {})) {
            seed(raw.copy(payload=JsonObject(raw.payload+(key to value))))
            withoutWrites {contains("budget.summary.spent","\u2014");contains("budget.summary.limit",formatMinorUnits(1000,"JPY"))}
        }
        seed(raw);withoutWrites {contains("budget.summary.spent",formatMinorUnits(7,"JPY"))}
    }
    @Test fun requiredOverrideDoesNotFallBackAndValidOverrideIgnoresUnusedOriginal() {
        plan();val raw=row();seed(raw.copy(payload=JsonObject(raw.payload+("reporting_expense_minor" to JsonPrimitive("2")))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent","\u2014")}
        val fixed=raw.copy(payload=JsonObject(raw.payload+mapOf("amount_minor" to buildJsonObject {},"reporting_expense_minor" to JsonPrimitive(2),"reporting_income_minor" to buildJsonObject {},"created_at" to buildJsonObject {})))
        seed(fixed);withoutWrites {contains("budget.summary.spent",formatMinorUnits(2,"JPY"));contains("budget.summary.remaining",formatMinorUnits(998,"JPY"))}
    }
    @Test fun requiredUnreadableTitleAndExplicitCurrencyDoNotTurnIntoOrdinaryOrLegacyMoney() {
        plan();val raw=row();seed(raw.copy(payload=JsonObject(raw.payload+("title" to buildJsonObject {}))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent","\u2014")}
        seed(raw.copy(payload=JsonObject(raw.payload+("source_currency_code" to buildJsonObject {}))))
        withoutWrites {contains("budget.summary.spent","\u2014")}
        seed(raw);withoutWrites {contains("budget.summary.spent",formatMinorUnits(7,"JPY"))}
    }
    @Test fun unusedFieldsAndProvedNeutralRecordsNeverEraseKnownSpending() {
        plan();val raw=row().let {it.copy(payload=JsonObject(it.payload+mapOf("created_at" to buildJsonObject {},"destination_amount_minor" to buildJsonObject {},"reporting_income_minor" to buildJsonObject {})))};seed(raw)
        val neutral=row().let {it.copy(payload=JsonObject(it.payload+mapOf("primary_kind_raw_value" to JsonPrimitive("income"),"amount_minor" to JsonPrimitive("broken"),"occurred_at" to buildJsonObject {})))};seed(neutral)
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent",formatMinorUnits(7,"JPY"));contains("budget.summary.remaining",formatMinorUnits(993,"JPY"))}
    }
    @Test fun canonicalEquivalentLegacyFrozenNameFindsItsOwnedExpense() {
        val original=plan();seed(child.copy(name="Café",nameEnglish="Café").toCloudRecord())
        seed(original.copy(categoryId=null,categoryIdSnapshot=null,categoryNameSnapshot="CAFE\u0301",categoryNameEnglishSnapshot="CAFE\u0301").toCloudRecord());seed(row())
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent",formatMinorUnits(7,"JPY"));contains("budget.summary.remaining",formatMinorUnits(993,"JPY"))}
    }
    @Test fun snapshotMustLoadBeforeAnExistingPlanCanPublishKnownMoney() {
        plan();seed(row());val complete=runBlocking {repo.observeBudgetReadSnapshot(owner).first()}
        val values=MutableStateFlow<BudgetReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = values.filterNotNull()}
        withoutWrites {compose.setContent {Screen(source=source)};contains("budget.summary.limit","\u2014");contains("budget.summary.spent","\u2014")}
        compose.runOnIdle {values.value=complete}
        withoutWrites {contains("budget.summary.limit",formatMinorUnits(1000,"JPY"));contains("budget.summary.spent",formatMinorUnits(7,"JPY"))}
    }
    @Test fun failedSnapshotClearsKnownMoneyAndRetryReadsTheCurrentRoomSnapshot() {
        plan();seed(row());val fail=java.util.concurrent.atomic.AtomicBoolean(true)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = flow {
            if(fail.getAndSet(false)) throw IllegalStateException("test storage unavailable")
            emitAll(repo.observeBudgetReadSnapshot(owner))
        }}
        withoutWrites {compose.setContent {Screen(source=source)};contains("budget.summary.limit","\u2014");contains("budget.summary.spent","\u2014")
            compose.onNodeWithTag("budget.retry").performScrollTo().performClick()
            contains("budget.summary.limit",formatMinorUnits(1000,"JPY"));contains("budget.summary.spent",formatMinorUnits(7,"JPY"))}
    }
    @Test fun ownerReplacementAndLateOldSnapshotCannotResurrectPrivateTotals() {
        plan();seed(row());val first=runBlocking {repo.observeBudgetReadSnapshot(owner).first()}
        val oldValues=MutableStateFlow<BudgetReadSnapshot?>(first);val nextValues=MutableStateFlow<BudgetReadSnapshot?>(null)
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = if(owner==this@BudgetRawSpendingScreenTest.owner) oldValues.filterNotNull() else nextValues.filterNotNull()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};contains("budget.summary.spent",formatMinorUnits(7,"JPY"))
            compose.runOnIdle {subject=other};contains("budget.summary.limit","\u2014")
            compose.runOnIdle {oldValues.value=first.copy(rows=first.rows.reversed());nextValues.value=first}
            contains("budget.summary.spent","\u2014");compose.onNodeWithText("Food").assertDoesNotExist()
            compose.runOnIdle {nextValues.value=BudgetReadSnapshot(other,emptyList())}
            contains("budget.summary.limit",formatMinorUnits(0,"JPY"));contains("budget.summary.spent",formatMinorUnits(0,"JPY"));compose.onNodeWithText("Food").assertDoesNotExist()}
    }
    @Test fun damagedParentRelationshipHoldsParentButPreservesTheDirectChildMoney() {
        val original=plan();runBlocking {repo.saveBudget(owner,BudgetDraft(parent.id,month.atDay(1).atStartOfDay(zone).toInstant().toString(),2000,"JPY",zoneId=zone),device,time).getOrThrow()}
        seed(row());val metadata=child.toCloudRecord();seed(metadata.copy(payload=JsonObject(metadata.payload+("parent_category_id" to buildJsonObject {}))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.limit",formatMinorUnits(2000,"JPY"));contains("budget.summary.spent","\u2014")
            contains("budget.money.budget-${original.id}","${formatMinorUnits(7,"JPY")} / ${formatMinorUnits(1000,"JPY")}")}
    }
    @Test fun decomposedCardAndGeneratedTitlesRemainNeutralAndNeverRewriteTheirOriginalText() {
        plan();val raw=row();val card=java.text.Normalizer.normalize("Thanh toán thẻ",java.text.Normalizer.Form.NFD)
        seed(raw.copy(payload=JsonObject(raw.payload+("title" to JsonPrimitive(card)))))
        withoutWrites {compose.setContent {Screen()};contains("budget.summary.spent",formatMinorUnits(0,"JPY"))}
        val vi=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag("vi"))})
        val adjustment=java.text.Normalizer.normalize(vi.getString(R.string.transactions_generated_title_balance_adjustment),java.text.Normalizer.Form.NFD)
        seed(raw.copy(payload=JsonObject(raw.payload+("title" to JsonPrimitive(adjustment)))))
        withoutWrites {contains("budget.summary.spent",formatMinorUnits(0,"JPY"))}
    }

    @Test fun failureAfterLoadedSnapshotClearsItsTotalsAndRetryUsesTheRepairedCurrentRows() {
        plan();val raw=row();seed(raw);val complete=runBlocking {repo.observeBudgetReadSnapshot(owner).first()}
        val release=kotlinx.coroutines.CompletableDeferred<Unit>();val first=java.util.concurrent.atomic.AtomicBoolean(true)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = flow {
            if(first.getAndSet(false)){emit(complete);release.await();throw IllegalStateException("test read failed after valid snapshot")}
            emitAll(repo.observeBudgetReadSnapshot(owner))
        }}
        withoutWrites {compose.setContent {Screen(source=source)};contains("budget.summary.spent",formatMinorUnits(7,"JPY"))
            compose.runOnIdle {release.complete(Unit)};contains("budget.summary.spent","\u2014");contains("budget.summary.limit","\u2014")}
        seed(raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive(9)))))
        withoutWrites {compose.onNodeWithTag("budget.retry").performScrollTo().performClick();contains("budget.summary.spent",formatMinorUnits(9,"JPY"));contains("budget.summary.remaining",formatMinorUnits(991,"JPY"))}
    }

}
