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
class OverviewMonthlyScreenTest {
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
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)
        }}
    }
    private fun metric(kind:String,amount:Long,code:String) {compose.onNodeWithTag("overview.monthly.$kind").performScrollTo().assertTextEquals(formatMinorUnits(amount,code))}
    @Test fun realRoomOverviewMonthlyMetricsUseAllRowsAndRetainExactAmountWithoutWrites() {
        repeat(7) {seed(row(9007199254740993L))};seed(row(42,"income"))
        val before=rows();val queue=pending()
        compose.setContent {Screen()};metric("expense",63050394783186951L,"JPY");metric("income",42,"JPY")
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending());Assert.assertEquals(1,refreshes)
    }
    @Test fun primaryAndLiveRatesRecomputeSourceAmountsRatherThanExplicitReportingPair() {
        seed(row(3).with("reporting_currency_code" to JsonPrimitive("VND"),"reporting_amount_minor" to JsonPrimitive(999)))
        var primary by mutableStateOf("JPY")
        compose.setContent {Screen(primary=primary)};metric("expense",3,"JPY")
        compose.runOnIdle {primary="VND"};compose.onNodeWithTag("overview.monthly.expense").assertTextEquals("—")
        compose.onNodeWithTag("overview.monthly.expense.unavailable").assertExists()
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null))};metric("expense",8,"VND")
        compose.runOnIdle {primary="JPY"};metric("expense",3,"JPY");Assert.assertEquals(3,(rows().single().payload["amount_minor"] as JsonPrimitive).long)
    }
    @Test fun accountReplacementCannotRetainPrivateMonthlyTotalsBeforeReplacementFlowEmits() {
        var subject by mutableStateOf(owner)
        val owned=MutableStateFlow(listOf(row(123456789)))
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity!=CloudEntity.LEDGER_TRANSACTION) repo.observe(entity,ownerUserId)
                else if(ownerUserId==owner) owned else emptyFlow()
        }
        compose.setContent {Screen(subject,source)};metric("expense",123456789,"JPY")
        compose.runOnIdle {subject=other};metric("expense",0,"JPY");metric("income",0,"JPY")
        Assert.assertTrue(rows().isEmpty());Assert.assertTrue(rows(other).isEmpty())
    }
    @Test fun malformedRawAmountsDatesAndOwnerEnvelopesNeverContributeFallbackMoney() {
        val invalid=listOf(row().with("reporting_expense_minor" to JsonPrimitive("broken")),row().with("reporting_income_minor" to JsonPrimitive("broken")),
            row().with("amount_minor" to JsonPrimitive("broken")),row().with("occurred_at" to JsonPrimitive("broken")),row().with("created_at" to JsonPrimitive("broken")),
            row().with("is_archived" to JsonPrimitive("broken")),row().with("user_id" to JsonPrimitive(other.value)),row().with("id" to JsonPrimitive(UUID.randomUUID().toString())),
            row().copy(ownerUserId=other.value),row().with("entry_status_raw_value" to JsonPrimitive("draft")),row().with("is_archived" to JsonPrimitive(true)),row().copy(deletedAt=time))
        val raw=MutableStateFlow(invalid+row(7))
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) raw else repo.observe(entity,ownerUserId)
        }
        compose.setContent {Screen(source=source)};metric("expense",7,"JPY");Assert.assertTrue(rows().isEmpty());Assert.assertTrue(pending().isEmpty())
    }
    @Test fun monthlyMetricsShowCompleteAmountsLightDarkAtFont130WithoutWrites() {
        seed(row().with("source_currency_code" to JsonPrimitive("VND"),"reporting_expense_minor" to JsonPrimitive(Long.MIN_VALUE)));seed(row(Long.MAX_VALUE,"income").with("source_currency_code" to JsonPrimitive("VND")))
        val before=rows();val queue=pending();var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}
        }
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            for((kind,amount) in listOf("income" to Long.MAX_VALUE,"expense" to Long.MIN_VALUE)) {
                metric(kind,amount,"VND")
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag("overview.monthly.$kind").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
                val layout=layouts.single();Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0))
                Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,visibleEnd=true))
                for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("$kind glyph $i outside $box / ${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            }
            capture("overview-monthly-$theme-font130.png")
        }
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
    }
    @Test fun allLanguageGeneratedTitlesAndSettlementOverridesReachRealOverviewClassification() {
        for(title in listOf("Điều chỉnh số dư","Balance adjustment","残高調整")) seed(row().with("title" to JsonPrimitive(title)))
        val known=vn.com.quyln.mistia.core.designsystem.knownTransactionTitles(ApplicationProvider.getApplicationContext<Context>())
        for(kind in listOf(GeneratedTransactionTitle.COLLECT,GeneratedTransactionTitle.BORROW)) for(title in known.getValue(kind)) seed(row(100,"income").with("title" to JsonPrimitive(title)))
        seed(row().with("category_id" to JsonPrimitive(SystemCategoryIdentity.canonicalId("loan_repayment"))))
        seed(row());seed(row().with("reporting_expense_minor" to JsonPrimitive(-25)))
        seed(row(25,"income"));seed(row(100,"transfer").with("transfer_subtype_raw_value" to JsonPrimitive("debt"),"debt_intent_raw_value" to JsonPrimitive("collect"),
            "settlement_role_raw_value" to JsonPrimitive("resaleReceipt"),"reporting_income_minor" to JsonPrimitive(75)))
        val before=rows();val queue=pending();compose.setContent {Screen()};metric("expense",75,"JPY");metric("income",100,"JPY")
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pending())
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
