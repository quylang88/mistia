package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
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
class OverviewReportingWalletMetadataScreenTest {
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
    private val today=Instant.parse(time).atZone(ZoneId.systemDefault()).toLocalDate()
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private val rateRows=MutableStateFlow(listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)))
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun raw(entity:CloudEntity,fields:JsonObject):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("is_archived",false);put("occurred_at",time);put("created_at",time);put("updated_at",time)}+fields),time,null,0)
    }
    private fun wallet(code:String="VND",kind:String="cash")=raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Metadata wallet");put("kind_raw_value",kind);put("currency_code",code);put("opening_balance_minor","broken")
    })
    private fun row(wallet:CloudRecord,amount:Long=165,kind:String="expense",title:String="Metadata expense")=raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("title",title);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_wallet_id",wallet.id);put("source_currency_code",JsonNull)
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=false) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode="JPY",exchangeRates=rates)}}
    }
    private fun value(tag:String,text:String) {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and hasText(text),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertTextEquals(text)
    }
    private fun amount(tag:String,minor:Long,code:String="JPY")=value(tag,formatMinorUnits(minor,code))
    private fun bar()=compose.onNodeWithTag("overview.chart.day.$today")
    private fun reveal(tag:String) {
        val scroll=compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange));scroll.performScrollToIndex(1)
        repeat(5) {if(runCatching {compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()}.isSuccess) return
            scroll.performTouchInput {swipe(androidx.compose.ui.geometry.Offset(centerX,height*0.65f),androidx.compose.ui.geometry.Offset(centerX,height*0.45f),1000)}}
        compose.onNodeWithTag(tag,useUnmergedTree=true).assertIsDisplayed()
    }
    @Test fun monthlyBothDirectionsRetainCurrencyWhileAssetsWaitForOpeningRepairAndOwnerClears() {
        val wallet=wallet();listOf(wallet,row(wallet),row(wallet,330,"income")).forEach(::seed)
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,source)};amount("overview.monthly.expense",1);amount("overview.monthly.income",2);value("overview.assets","\u2014")}
        seed(wallet.with("opening_balance_minor",JsonPrimitive(0)))
        withoutWrites {amount("overview.assets",1);amount("overview.monthly.expense",1);amount("overview.monthly.income",2)
            compose.runOnIdle {subject=other};amount("overview.assets",0);amount("overview.monthly.expense",0);amount("overview.monthly.income",0)}
    }
    @Test fun weeklyCalloutAndRealDayHoldKeepConvertedTotalAndOriginalCurrencyAcrossLiveMetadataChanges() {
        val wallet=wallet();val row=row(wallet);listOf(wallet,row).forEach(::seed)
        withoutWrites {compose.setContent {Screen()}
            compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.chart.day.$today") and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.OnLongClick)).fetchSemanticsNodes().isNotEmpty()}
            reveal("overview.chart.day.$today");bar().performTouchInput {click()};amount("overview.chart.selection",1)
            bar().performTouchInput {down(center);advanceEventTime(400);up()};amount("overview.day.total",1)
            value("overview.day.amount.${row.id}","-"+formatMinorUnits(165,"VND"))}
        seed(wallet.with("currency_code",JsonPrimitive("JPY")))
        withoutWrites {amount("overview.day.total",165);value("overview.day.amount.${row.id}","-"+formatMinorUnits(165,"JPY"))}
        seed(wallet.with("currency_code",JsonPrimitive("???")))
        withoutWrites {value("overview.day.total","\u2014");value("overview.day.amount.${row.id}","\u2014")}
        seed(wallet);withoutWrites {amount("overview.day.total",1);value("overview.day.amount.${row.id}","-"+formatMinorUnits(165,"VND"))}
    }
    @Test fun categoryLegendUsesWalletCurrencyAndCreditKindSurvivesUnusedOpeningDamage() {
        val wallet=wallet();val credit=wallet("JPY","creditCard");listOf(wallet,row(wallet),credit,row(credit,3,title="Card payment")).forEach(::seed)
        withoutWrites {compose.setContent {Screen()};amount("overview.monthly.expense",4)
            compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick()
            compose.onNodeWithTag("overview.category.amount.uncategorized-expense",useUnmergedTree=true).performScrollTo();amount("overview.category.amount.uncategorized-expense",4)}
        seed(wallet.with("is_archived",JsonPrimitive(true)));withoutWrites {amount("overview.category.amount.uncategorized-expense",4)}
    }
    @Test fun invalidExistingCurrencyHoldsReportsDespiteUnusedBadOpeningThenMetadataRepairRestoresThem() {
        val wallet=wallet("???");listOf(wallet,row(wallet)).forEach(::seed)
        withoutWrites {compose.setContent {Screen()};value("overview.monthly.expense","\u2014")
            compose.onNodeWithTag("overview.chart.unavailable").performScrollTo().assertIsDisplayed()
            compose.onNodeWithTag("overview.chart.mode.category").performScrollTo().performClick();compose.onNodeWithTag("overview.category.unavailable").performScrollTo().assertIsDisplayed()}
        seed(wallet.with("currency_code",JsonPrimitive("VND")))
        withoutWrites {amount("overview.monthly.expense",1);compose.onNodeWithTag("overview.category.amount.uncategorized-expense",useUnmergedTree=true).performScrollTo();amount("overview.category.amount.uncategorized-expense",1)
            compose.onNodeWithTag("overview.chart.mode.day").performScrollTo().performClick();compose.onNodeWithTag("overview.chart.unavailable").assertDoesNotExist();value("overview.assets","\u2014")}
    }
}
