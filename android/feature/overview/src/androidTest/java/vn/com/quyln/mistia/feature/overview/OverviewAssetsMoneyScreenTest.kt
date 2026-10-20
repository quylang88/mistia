package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewAssetsMoneyScreenTest {
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
    private val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun raw(entity:CloudEntity,fields:JsonObject=JsonObject(emptyMap()),id:String=UUID.randomUUID().toString())=CloudRecord(entity.table,id,owner.value,
        JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("is_archived",false);put("occurred_at",time);put("created_at",time);put("updated_at",time)}+fields),time,null,0)
    private fun wallet(amount:Long=0,code:String="JPY",id:String=UUID.randomUUID().toString())=raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Private asset wallet");put("kind_raw_value","cash");put("opening_balance_minor",amount);put("currency_code",code)
    },id)
    private data class Position(val channel:CloudRecord,val asset:CloudRecord,val latest:CloudRecord)
    private fun position(cost:Long=7):Position {
        val channel=raw(CloudEntity.INVESTMENT_CHANNEL)
        val asset=raw(CloudEntity.INVESTMENT_ASSET,buildJsonObject {put("channel_id",channel.id)})
        val latest=raw(CloudEntity.INVESTMENT_TRADE,buildJsonObject {put("channel_id",channel.id);put("asset_id",asset.id);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",cost)})
        listOf(channel,asset,latest).forEach(::seed);return Position(channel,asset,latest)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.TRANSACTION_CATEGORY,CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE)
        .associateWith {repo.observe(it,owner).first() to store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Composable private fun Screen(subject:UserId=owner,primary:String="JPY",dark:Boolean=false,source:FinanceRepository=repo) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)}}
    }
    private fun assets(amount:BigInteger,code:String="JPY") {
        val text=formatMinorUnits(amount,code)
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.assets") and hasText(text)).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.assets").performScrollTo().assertIsDisplayed().assertTextEquals(text)
        compose.onNodeWithTag("overview.assets.unavailable").assertDoesNotExist()
    }
    private fun unavailable() {
        compose.waitUntil(5000) {compose.onAllNodes(hasTestTag("overview.assets") and hasText("\u2014")).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.assets.unavailable").performScrollTo().assertIsDisplayed()
    }
    private fun withoutWrites(action:()->Unit) {val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    private fun n(value:Long)=BigInteger.valueOf(value)
    @Test fun realRoomCashPlusInventoryKeepsExactTwiceMaximumAndOriginalRecordsWithoutWrites() {
        repeat(2){seed(wallet(Long.MAX_VALUE,"VND"))};seed(wallet(0,"VND",investmentSystemWalletId(owner)));position(5)
        withoutWrites {compose.setContent {Screen(primary="VND")};assets(n(Long.MAX_VALUE)*BigInteger.TWO+n(5),"VND")}
    }
    @Test fun missingFxNeverShowsPartialAssetsAndLiveRatePrimaryRepairStaysReadOnly() {
        seed(wallet(3));seed(wallet(70,"VND"));var primary by mutableStateOf("VND")
        withoutWrites {compose.setContent {Screen(primary=primary)};unavailable()
            compose.runOnIdle {rateRows.value=listOf(rate)};assets(n(78),"VND")
            compose.runOnIdle {rateRows.value=emptyList()};unavailable()
            compose.runOnIdle {primary="JPY";rateRows.value=listOf(rate)};assets(n(31))
            compose.runOnIdle {rateRows.value=listOf(rate.copy(rateDecimalString="broken"))};unavailable()}
    }
    @Test fun ownedWalletCurrencyChangesRepairOrHoldAndArchivingRemovesUnavailableComponent() {
        val original=wallet(100,"VND");seed(original);var primary by mutableStateOf("VND")
        withoutWrites {compose.setContent {Screen(primary=primary)};assets(n(100),"VND")}
        seed(original.with("currency_code",JsonPrimitive("JPY")));withoutWrites {unavailable();compose.runOnIdle {rateRows.value=listOf(rate)};assets(n(250),"VND");compose.runOnIdle {primary="JPY"};assets(n(100))}
        seed(original.with("currency_code",JsonPrimitive("USD")));withoutWrites {unavailable()}
        seed(original.with("is_archived",JsonPrimitive(true)));withoutWrites {assets(BigInteger.ZERO)}
    }
    @Test fun invalidInventoryAccountingMetadataCannotSilentlyDropCostAndZeroNeedsNoCurrency() {
        seed(wallet(9));val system=wallet(0,"??",investmentSystemWalletId(owner));seed(system);val position=position()
        withoutWrites {compose.setContent {Screen()};unavailable()}
        seed(system.with("currency_code",JsonPrimitive("JPY")));withoutWrites {assets(n(16))}
        seed(system.with("currency_code",JsonPrimitive("VND")));withoutWrites {unavailable();compose.runOnIdle {rateRows.value=listOf(rate)};assets(n(12));compose.runOnIdle {rateRows.value=emptyList()};unavailable()}
        seed(position.latest.with("position_quantity_after_decimal_string",JsonPrimitive("0")));seed(system.with("currency_code",JsonNull));withoutWrites {assets(n(9))}
    }
    @Test fun malformedLatestPositionHoldsWholeAssetsUntilRepairSoldOrArchivedChannel() {
        seed(wallet(9));val position=position();val old=position.latest.copy(id=UUID.randomUUID().toString()).with("occurred_at",JsonPrimitive("2026-01-01T00:00:00Z"))
        seed(old.with("id",JsonPrimitive(old.id)));withoutWrites {compose.setContent {Screen()};assets(n(16))}
        seed(position.latest.with("position_quantity_after_decimal_string",JsonPrimitive("broken")));withoutWrites {unavailable()}
        seed(position.latest);withoutWrites {assets(n(16))}
        seed(position.latest.with("position_cost_basis_after_minor",JsonPrimitive("7")));withoutWrites {unavailable()}
        seed(position.latest.with("position_quantity_after_decimal_string",JsonPrimitive("0")).with("position_cost_basis_after_minor",JsonPrimitive("broken")));withoutWrites {assets(n(9))}
        seed(position.latest.with("created_at",JsonPrimitive("broken")));withoutWrites {unavailable()}
        seed(position.channel.with("is_archived",JsonPrimitive(true)));withoutWrites {assets(n(9))}
    }
    @Test fun ownerReplacementBeforeNewFlowsEmitClearsCashAndInventoryAndUnavailableState() {
        seed(wallet(123456789));position();var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId==owner) repo.observe(entity,ownerUserId) else emptyFlow()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};assets(n(123456796));compose.runOnIdle {subject=other};assets(BigInteger.ZERO)
            compose.onAllNodesWithText(formatMinorUnits(123456796,"JPY")).assertCountEquals(0)}
    }
    @Test fun unsupportedImportedWalletCurrencyNeverBecomesJPYEvenWithUnsupportedRequestedPrimary() {
        val imported=wallet(1375,"USD");seed(imported)
        withoutWrites {compose.setContent {Screen(primary="USD")};unavailable();compose.onAllNodesWithText(formatMinorUnits(1375,"JPY")).assertCountEquals(0)}
        seed(imported.with("opening_balance_minor",JsonPrimitive(0)));withoutWrites {assets(BigInteger.ZERO)}
    }
    @Test fun exactPositiveNegativeAndUnavailableAssetsRemainCompleteAtActualNormalAndFont130LightDark() {
        val wallets=listOf(wallet(Long.MAX_VALUE,"VND"),wallet(Long.MAX_VALUE,"VND"));wallets.forEach(::seed)
        var dark by mutableStateOf(false);var scale by mutableFloatStateOf(1f);var primary by mutableStateOf("VND")
        compose.setContent {val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,scale)) {Screen(primary=primary,dark=dark)}}
        for((sign,value) in listOf("positive" to Long.MAX_VALUE,"negative" to Long.MIN_VALUE)) {
            wallets.forEach {seed(it.with("opening_balance_minor",JsonPrimitive(value)))}
            withoutWrites {for(font in listOf(1f,1.3f)) for(theme in listOf("light","dark")) {
                compose.runOnIdle {scale=font;dark=theme=="dark"};assets(n(value)*BigInteger.TWO,"VND");assertText("overview.assets",font)
                if(font==1.3f) capture("overview-assets-exact-$sign-$theme-font130.png")
            }}
        }
        withoutWrites {compose.runOnIdle {primary="JPY"}
            for(theme in listOf("light","dark")) {compose.runOnIdle {dark=theme=="dark"};unavailable();assertText("overview.assets.unavailable",1.3f,single=false);capture("overview-assets-exact-unavailable-$theme-font130.png")}}
    }
    private fun assertText(tag:String,font:Float,single:Boolean=true) {
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single();Assert.assertEquals(font,layout.layoutInput.density.fontScale,0.0001f);if(single) Assert.assertEquals(1,layout.lineCount)
        Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
        for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
        for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("glyph$i outside$box/${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
    }
    private fun capture(name:String) {
        compose.waitForIdle();val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000;var previous:android.graphics.Bitmap?=null;var stableFrames=0;var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {val frame=checkNotNull(automation.takeScreenshot());stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame;if(stableFrames>=3) {stable=frame;break}}
        if(stable==null) previous?.recycle();val bitmap=checkNotNull(stable){"Unsettled screenshot:$name"}
        java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
    }
}
