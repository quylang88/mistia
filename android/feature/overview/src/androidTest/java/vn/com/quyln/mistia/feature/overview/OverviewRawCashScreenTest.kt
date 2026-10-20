package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
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
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewRawCashScreenTest {
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
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private val rateRows=MutableStateFlow(emptyList<ExchangeRateSnapshot>())
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun raw(entity:CloudEntity,fields:JsonObject=JsonObject(emptyMap())):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("is_archived",false);put("occurred_at",time);put("created_at",time);put("updated_at",time)}+fields),time,null,0)
    }
    private fun wallet(amount:Long=10,code:String="JPY")=raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Private raw wallet");put("kind_raw_value","cash");put("opening_balance_minor",amount);put("currency_code",code)
    })
    private fun row(wallet:CloudRecord?,amount:Long=3,kind:String="expense")=raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("title","Raw cash");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_currency_code","JPY")
        wallet?.let {put("source_wallet_id",it.id)}
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION).associateWith {
        repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    @Composable private fun Screen(subject:UserId=owner,primary:String="JPY",dark:Boolean=false,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)}}
    }
    private fun assets(amount:BigInteger,code:String="JPY") {
        val text=formatMinorUnits(amount,code)
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.assets") and hasText(text)).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.assets").performScrollTo().assertIsDisplayed().assertTextEquals(text)
        compose.onNodeWithTag("overview.assets.unavailable").assertDoesNotExist()
    }
    private fun unavailable(){compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.assets") and hasText("\u2014")).fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag("overview.assets.unavailable").performScrollTo().assertIsDisplayed()}
    private fun n(value:Long)=BigInteger.valueOf(value)
    @Test fun unreadableOpeningNeverLeavesPartialAssetsAndRawRepairOrArchiveUpdatesReadOnly() {
        seed(wallet(7));val damaged=wallet();seed(damaged.with("opening_balance_minor",JsonPrimitive("broken")))
        withoutWrites {compose.setContent {Screen()};unavailable()}
        seed(damaged);withoutWrites {assets(n(17))}
        seed(damaged.with("opening_balance_minor",JsonPrimitive("10")));withoutWrites {unavailable()}
        seed(damaged.with("opening_balance_minor",JsonPrimitive("broken")).with("is_archived",JsonPrimitive(true)));withoutWrites {assets(n(7))}
    }
    @Test fun postedUnreadableMoneyHoldsUntilRepairAndDraftOrUnselectedLegCannotPoison() {
        val cash=wallet();seed(cash);val original=row(cash);seed(original.with("amount_minor",JsonPrimitive("broken")))
        withoutWrites {compose.setContent {Screen()};unavailable()}
        seed(original);withoutWrites {assets(n(7))}
        seed(original.with("amount_minor",JsonPrimitive("broken")).with("entry_status_raw_value",JsonPrimitive("draft")));withoutWrites {assets(n(10))}
        seed(row(null).with("amount_minor",JsonPrimitive("broken")));withoutWrites {assets(n(10))}
    }
    @Test fun validCashLegSurvivesUnreadableUnrelatedCalendarReportingAndDestinationFields() {
        val cash=wallet();seed(cash);val original=row(cash);seed(original.with("occurred_at",JsonPrimitive("broken")))
        withoutWrites {compose.setContent {Screen()};assets(n(7))}
        for(key in listOf("created_at","reporting_expense_minor","reporting_income_minor","destination_amount_minor")) {
            seed(original.with(key,JsonPrimitive("broken")));withoutWrites {assets(n(7))}
        }
    }
    @Test fun resaleRequiresItsCostAndDoesNotNeedUnusedOriginalMoneyWhileSharedPrincipalIsNeutral() {
        val cash=wallet();seed(cash)
        val resale=row(cash,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("lend"))
            .with("settlement_role_raw_value",JsonPrimitive("resaleReceivable")).with("reporting_expense_minor",JsonPrimitive(3))
        seed(resale.with("amount_minor",JsonPrimitive("broken")));withoutWrites {compose.setContent {Screen()};assets(n(7))}
        seed(resale.with("reporting_expense_minor",JsonPrimitive("broken")));withoutWrites {unavailable()}
        seed(resale.with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive("broken")).with("settlement_role_raw_value",JsonPrimitive("sharedExpenseReceivable")));withoutWrites {assets(n(10))}
    }
    @Test fun crossCurrencyTransferRequiresPairedDestinationMinorAndSameCurrencyLegacyFallbackStaysExact() {
        val yen=wallet(1000);val dong=wallet(0,"VND");listOf(yen,dong).forEach(::seed);rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null))
        val transfer=row(yen,100,"transfer").with("transfer_subtype_raw_value",JsonPrimitive("internalTransfer")).with("destination_wallet_id",JsonPrimitive(dong.id)).with("destination_currency_code",JsonPrimitive("VND"))
        seed(transfer);withoutWrites {compose.setContent {Screen()};unavailable()}
        seed(transfer.with("destination_amount_minor",JsonPrimitive(16500)));withoutWrites {assets(n(1000))}
        seed(transfer.with("destination_amount_minor",JsonPrimitive("16500")));withoutWrites {unavailable()}
        seed(dong.with("currency_code",JsonPrimitive("JPY")));seed(transfer.with("destination_currency_code",JsonPrimitive("JPY")));withoutWrites {assets(n(1000))}
    }
    @Test fun creditSourceCurrencyRemainsUsableDespiteUnreadableUnusedOpening() {
        val cash=wallet();val credit=wallet().with("kind_raw_value",JsonPrimitive("creditCard")).with("opening_balance_minor",JsonPrimitive("broken"));listOf(cash,credit).forEach(::seed)
        val transfer=row(credit,kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("internalTransfer")).with("source_currency_code",JsonNull).with("destination_wallet_id",JsonPrimitive(cash.id));seed(transfer)
        withoutWrites {compose.setContent {Screen()};assets(n(13))}
        seed(transfer.with("source_currency_code",JsonPrimitive(123)));withoutWrites {unavailable()}
        seed(transfer);withoutWrites {assets(n(13))}
        seed(credit.with("currency_code",JsonPrimitive("VND")));withoutWrites {unavailable()}
        seed(transfer.with("destination_amount_minor",JsonPrimitive(100)));withoutWrites {assets(n(110))}
    }
    @Test fun excludedCorruptWalletsStayNeutralAndOwnerReplacementClearsPrivateUnknownState() {
        val cash=wallet(123456789);seed(cash);val damaged=wallet().with("opening_balance_minor",JsonPrimitive("broken"))
        seed(damaged.with("kind_raw_value",JsonPrimitive("creditCard")))
        seed(damaged.copy(id=UUID.randomUUID().toString(),deletedAt=time))
        var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};assets(n(123456789))}
        seed(cash.with("opening_balance_minor",JsonPrimitive("broken")));withoutWrites {unavailable();compose.runOnIdle {subject=other};assets(BigInteger.ZERO);compose.onAllNodesWithText(formatMinorUnits(123456789,"JPY")).assertCountEquals(0)}
    }
    @Test fun unavailableRawCashHintAndRepairedExactMoneyStayCompleteAtActual130InThreeLanguagesLightDark() {
        val first=wallet(Long.MAX_VALUE,"VND");val second=wallet(Long.MAX_VALUE,"VND");seed(first.with("opening_balance_minor",JsonPrimitive("broken")));seed(second)
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val locale=java.util.Locale.forLanguageTag(language);val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(locale)}
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}
        }
        for(code in listOf("en","vi","ja")) for(theme in listOf("light","dark")) {
            seed(first.with("opening_balance_minor",JsonPrimitive("broken")))
            withoutWrites {compose.runOnIdle {language=code;dark=theme=="dark"};unavailable()
                val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(code))})
                compose.onNodeWithTag("overview.assets.unavailable").assertTextEquals(localized.getString(R.string.overview_overview_assets_unavailable));assertText("overview.assets.unavailable",single=false)
                capture("overview-raw-cash-$code-$theme-font130.png")}
            seed(first);withoutWrites {assets(n(Long.MAX_VALUE)*BigInteger.TWO,"VND");assertText("overview.assets")}
        }
    }
    private fun assertText(tag:String,single:Boolean=true) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f);if(single) Assert.assertEquals(1,layout.lineCount)
        Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true));for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0;previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable){"Unsettled screenshot:$name"};java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
