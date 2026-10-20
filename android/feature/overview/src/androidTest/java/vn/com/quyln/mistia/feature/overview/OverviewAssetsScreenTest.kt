package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
class OverviewAssetsScreenTest {
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
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.entries.single {it.table==record.entity},record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun rows(subject:UserId=owner)=runBlocking {repo.observe(CloudEntity.LEDGER_TRANSACTION,subject).first()}
    private fun pending()=runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE)}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo,primary:String="JPY",dark:Boolean=false) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)
        }}
    }
    private fun wallet(id:String=UUID.randomUUID().toString(),opening:Long=3,code:String="JPY",kind:String="cash")=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("name","Owned wallet");put("kind_raw_value",kind);put("currency_code",code);put("opening_balance_minor",opening)
        put("created_at",time);put("updated_at",time);put("is_archived",false)
    },time,null,0)
    private fun investment(entity:CloudEntity,fields:JsonObject=JsonObject(emptyMap())):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("is_archived",false);put("created_at",time);put("occurred_at",time)}+fields),time,null,0)
    }
    private fun pendingAll()=runBlocking {CloudEntity.entries.flatMap {store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    private fun assets(amount:Long?,code:String) {
        compose.onNodeWithTag("overview.assets").performScrollTo().assertTextEquals(amount?.let {formatMinorUnits(it,code)} ?: "\u2014")
        if(amount==null) compose.onNodeWithTag("overview.assets.unavailable").assertExists()
    }
    @Test fun realRoomWalletCashAndRemainingInventoryAppearTogetherWithoutChangingStoredRowsOrOutbox() {
        val cash=wallet(opening=9007199254740993L,code="VND");seed(cash)
        seed(wallet(opening=Long.MAX_VALUE,kind="creditCard"));seed(wallet(opening=99999).with("is_archived" to JsonPrimitive(true)))
        seed(wallet(investmentSystemWalletId(owner),0,"VND","investment"))
        seed(row(3).with("source_currency_code" to JsonPrimitive("VND"),"source_wallet_id" to JsonPrimitive(cash.id)))
        val channel=investment(CloudEntity.INVESTMENT_CHANNEL);val asset=investment(CloudEntity.INVESTMENT_ASSET,buildJsonObject {put("channel_id",channel.id)})
        val trade=investment(CloudEntity.INVESTMENT_TRADE,buildJsonObject {put("channel_id",channel.id);put("asset_id",asset.id);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",5)})
        listOf(channel,asset,trade).forEach(::seed)
        val before=rows();val queue=pendingAll();compose.setContent {Screen(primary="VND")};assets(9007199254740995L,"VND")
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,pendingAll())
    }
    @Test fun livePrimaryAndRatesRecomputeWalletAssetsFromOriginalBalances() {
        seed(wallet());var primary by mutableStateOf("JPY");compose.setContent {Screen(primary=primary)};assets(3,"JPY")
        compose.runOnIdle {primary="VND"};assets(null,"VND")
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null))};assets(8,"VND")
        compose.runOnIdle {rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","3","test",0,null))};assets(9,"VND")
        compose.runOnIdle {primary="JPY"};assets(3,"JPY")
    }
    @Test fun accountReplacementClearsWalletAndInventoryTotalsWhileNextOwnersFlowsHaveNotEmitted() {
        var subject by mutableStateOf(owner);val owned=MutableStateFlow(listOf(wallet(opening=123456789)))
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(ownerUserId!=owner) emptyFlow()
                else if(entity==CloudEntity.LEDGER_WALLET) owned else repo.observe(entity,ownerUserId)
        }
        compose.setContent {Screen(subject,source)};assets(123456789,"JPY");compose.runOnIdle {subject=other};assets(0,"JPY")
        Assert.assertTrue(rows().isEmpty());Assert.assertTrue(rows(other).isEmpty())
    }
    @Test fun unreadableCashHoldsWhileUnusedDestinationDoesNotDiscardKnownLegs() {
        val good=wallet(opening=10)
        val wallets=MutableStateFlow(listOf(good,wallet(opening=1000).copy(ownerUserId=other.value),wallet(opening=1000).with("user_id" to JsonPrimitive(other.value)),
            wallet(opening=1000).with("opening_balance_minor" to JsonPrimitive("broken")),wallet(opening=1000).with("is_archived" to JsonPrimitive("broken"))))
        val tx=MutableStateFlow(listOf(row(3).with("source_wallet_id" to JsonPrimitive(good.id)),row(100).with("source_wallet_id" to JsonPrimitive(good.id),"destination_amount_minor" to JsonPrimitive("broken"))))
        val source=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = when(entity) {
                CloudEntity.LEDGER_WALLET -> wallets;CloudEntity.LEDGER_TRANSACTION -> tx;else -> repo.observe(entity,ownerUserId)
            }
        }
        compose.setContent {Screen(source=source)};assets(null,"JPY")
        compose.runOnIdle {wallets.value=listOf(good)};assets(-93,"JPY")
        compose.runOnIdle {tx.value=tx.value.take(1)};assets(7,"JPY")
        Assert.assertTrue(rows().isEmpty());Assert.assertTrue(pendingAll().isEmpty())
    }
    @Test fun liveLatestInventoryPositionAndArchivedChannelRecomputeWithoutResurrectingPriorSnapshot() {
        seed(wallet(opening=9));val channel=investment(CloudEntity.INVESTMENT_CHANNEL);val asset=investment(CloudEntity.INVESTMENT_ASSET,buildJsonObject {put("channel_id",channel.id)})
        val old=investment(CloudEntity.INVESTMENT_TRADE,buildJsonObject {put("channel_id",channel.id);put("asset_id",asset.id);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",100);put("occurred_at","2026-01-01T00:00:00Z")})
        val latest=investment(CloudEntity.INVESTMENT_TRADE,buildJsonObject {put("channel_id",channel.id);put("asset_id",asset.id);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",7)})
        listOf(channel,asset,old,latest).forEach(::seed);compose.setContent {Screen()};assets(16,"JPY")
        seed(latest.with("position_quantity_after_decimal_string" to JsonPrimitive("0")));assets(9,"JPY")
        seed(latest);assets(16,"JPY");seed(channel.with("is_archived" to JsonPrimitive(true)));assets(9,"JPY")
        val queue=pendingAll();compose.waitForIdle();Assert.assertEquals(queue,pendingAll())
    }
    @Test fun availableAssetsAndMonthlyMetricsKeepCompleteLongBoundsLightDarkAtFont130() {
        seed(wallet(opening=Long.MAX_VALUE,code="VND"));var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(primary="VND",dark=dark)}
        }
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"};assets(Long.MAX_VALUE,"VND")
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("overview.assets").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
            for(i in layout.layoutInput.text.indices) {val box=layout.getBoundingBox(i);Assert.assertTrue("Asset glyph $i outside $box / ${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
            capture("overview-assets-$theme-font130.png")
        }
    }
    @Test fun inventoryAccountingCurrencyDoesNotDependOnParsingUnrelatedWalletOpeningAmount() {
        val system=wallet(investmentSystemWalletId(owner),0,"VND","investment")
        seed(system.with("opening_balance_minor" to JsonPrimitive("broken")))
        val channel=investment(CloudEntity.INVESTMENT_CHANNEL);val asset=investment(CloudEntity.INVESTMENT_ASSET,buildJsonObject {put("channel_id",channel.id)})
        val trade=investment(CloudEntity.INVESTMENT_TRADE,buildJsonObject {put("channel_id",channel.id);put("asset_id",asset.id);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",7)})
        listOf(channel,asset,trade).forEach(::seed)
        rateRows.value=listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null))
        val queue=pendingAll();compose.setContent {Screen()};assets(null,"JPY");Assert.assertEquals(queue,pendingAll())
        seed(system);val repaired=pendingAll();assets(3,"JPY");Assert.assertEquals(repaired,pendingAll())
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
