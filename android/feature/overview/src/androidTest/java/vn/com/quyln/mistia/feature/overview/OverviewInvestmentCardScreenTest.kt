package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.math.BigInteger
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
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
class OverviewInvestmentCardScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val now=Instant.now().toString()
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    private var opens=0
    private var overlay by mutableStateOf(false)
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)}
    private fun raw(entity:CloudEntity)=UUID.randomUUID().toString().let {id ->CloudRecord(entity.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("created_at",now);put("occurred_at",now);put("updated_at",now);put("is_archived",false)
    },now,null,0)}
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private fun rows(capital:Long=1375,profit:Long=-25,code:String="USD"):List<CloudRecord> {
        val channel=raw(CloudEntity.INVESTMENT_CHANNEL);val asset=raw(CloudEntity.INVESTMENT_ASSET).with("channel_id" to JsonPrimitive(channel.id))
        val trade=raw(CloudEntity.INVESTMENT_TRADE).with("channel_id" to JsonPrimitive(channel.id),"asset_id" to JsonPrimitive(asset.id),
            "accounting_currency_code" to JsonPrimitive(code),"position_quantity_after_decimal_string" to JsonPrimitive("1"),"position_cost_basis_after_minor" to JsonPrimitive(capital),"realized_profit_loss_minor" to JsonPrimitive(profit))
        val wallet=raw(CloudEntity.LEDGER_WALLET).copy(id=investmentSystemWalletId(owner)).with("id" to JsonPrimitive(investmentSystemWalletId(owner)),
            "currency_code" to JsonPrimitive(code),"is_archived" to JsonPrimitive(true),"opening_balance_minor" to JsonPrimitive("unused"))
        return listOf(channel,asset,trade,wallet)
    }
    private fun seed(rows:List<CloudRecord>)=runBlocking {store.commitMutations(rows.map {it to PendingMutation(CloudEntity.fromTable(it.entity)!!,it.id,it.ownerUserId,MutationKind.UPSERT,it.payload,now,0,device)})}
    private fun read()=runBlocking {repo.observeOverviewFinancialReadSnapshot(owner).first()}
    private fun queue()=runBlocking {OverviewFinancialReadSnapshot.entities.associateWith {store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo,dark:Boolean=false,primary:String="JPY") {
        MistiaTheme(darkTheme=dark){androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,overlayPresented=overlay,onOpenInvestment={opens++})
        }}
    }
    private fun money(kind:String,value:String){
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasTestTag("overview.investment.card"))
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("overview.investment.$kind") and hasText(value),useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.investment.$kind",useUnmergedTree=true).performScrollTo().assertTextEquals(value)
    }
    @Test fun realRoomCardShowsSourceCentsAndPersistedProfitWithoutWritesAndOpensOnlyWhenAvailable(){
        seed(rows());val before=read();val pending=queue()
        compose.setContent{Screen()};money("capital",formatMinorUnits(1375,"USD"));money("profit",formatMinorUnits(-25,"USD"))
        compose.onNodeWithTag("overview.investment.card").performScrollTo().performClick();Assert.assertEquals(1,opens)
        compose.runOnIdle{overlay=true};compose.onNodeWithTag("overview.investment.card").assertIsNotEnabled()
        Assert.assertEquals(before,read());Assert.assertEquals(pending,queue())
    }
    @Test fun actuallyLoadedEmptyUsesPrimaryAndPositiveZeroProfit(){
        compose.setContent{Screen(primary="VND")};money("capital",formatMinorUnits(0,"VND"));money("profit","+"+formatMinorUnits(0,"VND"))
        compose.onNodeWithTag("overview.investment.card").assertIsEnabled();Assert.assertTrue(read().rows.isEmpty());Assert.assertTrue(queue().values.all {it.isEmpty()})
    }
    @Test fun withheldOwnerReplacementCannotShowZeroOrPrivateMoneyAndLateForeignSourceIsRejected(){
        var subject by mutableStateOf(owner)
        val first=MutableStateFlow<OverviewFinancialReadSnapshot?>(null);val next=MutableStateFlow<OverviewFinancialReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=if(owner==this@OverviewInvestmentCardScreenTest.owner) first.filterNotNull() else next.filterNotNull()}
        compose.setContent{Screen(subject,source)};money("capital","—");money("profit","—");compose.onNodeWithTag("overview.investment.card").assertIsNotEnabled()
        compose.runOnIdle{first.value=OverviewFinancialReadSnapshot(owner,rows())};money("capital",formatMinorUnits(1375,"USD"))
        compose.runOnIdle{subject=other};money("capital","—");money("profit","—")
        compose.runOnIdle{next.value=OverviewFinancialReadSnapshot(owner,rows())};money("capital","—");compose.onNodeWithTag("overview.investment.card").assertIsNotEnabled()
        Assert.assertEquals(0,opens)
    }
    @Test fun failedReadRetriesTheSameSharedFinancialSourceAndRepairsBothAmounts(){
        val complete=OverviewFinancialReadSnapshot(owner,rows());var attempts=0
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId):Flow<OverviewFinancialReadSnapshot> = flow {
            attempts++;if(attempts==1) throw IllegalStateException("read unavailable")
            emit(complete);awaitCancellation()
        }}
        compose.setContent{Screen(source=source)};money("capital","—");money("profit","—")
        compose.onNodeWithTag("overview.investment.retry").performScrollTo().performClick()
        money("capital",formatMinorUnits(1375,"USD"));money("profit",formatMinorUnits(-25,"USD"));Assert.assertEquals(2,attempts)
    }
    @Test fun unreadableProfitPositionOrDenominationNeverContaminatesTheOtherIndependentAmount(){
        val original=rows();val trade=original.single {it.entity==CloudEntity.INVESTMENT_TRADE.table}
        val sourceRows=MutableStateFlow(OverviewFinancialReadSnapshot(owner,original))
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=sourceRows}
        fun replace(vararg fields:Pair<String,JsonElement>){sourceRows.value=OverviewFinancialReadSnapshot(owner,original.map {if(it==trade) it.with(*fields) else it})}
        compose.setContent{Screen(source=source)};money("capital",formatMinorUnits(1375,"USD"));money("profit",formatMinorUnits(-25,"USD"))
        compose.runOnIdle{replace("realized_profit_loss_minor" to JsonPrimitive("bad"))};money("capital",formatMinorUnits(1375,"USD"));money("profit","—")
        compose.runOnIdle{replace("position_cost_basis_after_minor" to JsonPrimitive("bad"))};money("capital","—");money("profit",formatMinorUnits(-25,"USD"))
        compose.runOnIdle{replace("accounting_currency_code" to JsonPrimitive("JPY"))};money("capital","—");money("profit","—")
        compose.runOnIdle{sourceRows.value=OverviewFinancialReadSnapshot(owner,original)};money("capital",formatMinorUnits(1375,"USD"));money("profit",formatMinorUnits(-25,"USD"))
        Assert.assertTrue(queue().values.all {it.isEmpty()})
    }
    @Test fun sectionGeometryAndNormalValuesKeepTheSwiftHeaderIconAndGroupedRows(){
        seed(rows(capital=7,profit=0,code="JPY"));compose.setContent{Screen()};money("capital",formatMinorUnits(7,"JPY"));money("profit","+"+formatMinorUnits(0,"JPY"))
        val header=compose.onNodeWithText(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_title).uppercase(),useUnmergedTree=true)
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();header.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
        Assert.assertEquals(13f,layouts.single().layoutInput.style.fontSize.value,0.0001f)
        val headerBounds=header.getUnclippedBoundsInRoot();val card=compose.onNodeWithTag("overview.investment.card").getUnclippedBoundsInRoot()
        Assert.assertEquals(8f,(card.top-headerBounds.bottom).value,0.75f)
        val icon=compose.onNodeWithTag("overview.investment.icon.capital",useUnmergedTree=true).getUnclippedBoundsInRoot()
        Assert.assertEquals(30f,(icon.right-icon.left).value,0.75f);Assert.assertEquals(30f,(icon.bottom-icon.top).value,0.75f);Assert.assertEquals(14f,(icon.left-card.left).value,0.75f)
    }
    @Test fun exactHugeSourceMoneyAndSignedProfitFitAtActual130InThreeLanguagesLightDark(){
        fun portfolio(code:String,profit:Long):OverviewFinancialReadSnapshot {
            val first=rows(Long.MAX_VALUE,profit,code);val second=rows(Long.MAX_VALUE,profit,code).filterNot {it.entity==CloudEntity.LEDGER_WALLET.table}
            return OverviewFinancialReadSnapshot(owner,first+second)
        }
        val values=MutableStateFlow(portfolio("VND",Long.MAX_VALUE))
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=values}
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)){Screen(source=source,dark=dark)}
        }
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) for(currency in listOf("VND","USD")) {
            val profit=if(currency=="VND") Long.MAX_VALUE else Long.MIN_VALUE
            compose.runOnIdle{language=code;dark=theme;values.value=portfolio(currency,profit)}
            val capital=BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO;val totalProfit=BigInteger.valueOf(profit)*BigInteger.TWO
            money("capital",formatMinorUnits(capital,currency));money("profit",(if(profit>=0) "+" else "")+formatMinorUnits(totalProfit,currency))
            for(kind in listOf("capital","profit")) {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag("overview.investment.$kind",useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
                val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
                Assert.assertEquals(1,layout.lineCount);Assert.assertFalse(layout.isLineEllipsized(0));Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(0,true))
                for(i in layout.layoutInput.text.indices){val box=layout.getBoundingBox(i);Assert.assertTrue("$kind glyph$i outside $box / ${layout.size}",box.left>=-1 && box.right<=layout.size.width+1 && box.top>=-1 && box.bottom<=layout.size.height+1)}
                if(kind=="profit") Assert.assertEquals(if(profit>=0) androidx.compose.ui.graphics.Color(0.18f,0.67f,0.62f) else androidx.compose.ui.graphics.Color(0.96f,0.36f,0.49f),layout.layoutInput.style.color)
            }
            val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
            compose.onNodeWithText(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_hub_realized_profit_loss),useUnmergedTree=true).assertExists()
            compose.onNodeWithTag("overview.investment.section").performScrollTo()
            val image=compose.onNodeWithTag("overview.investment.section").captureToImage()
            val bitmap=image.asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"overview-investment-$currency-$code-${if(theme) "dark" else "light"}-font130.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        }
        Assert.assertTrue(queue().values.all {it.isEmpty()})
    }

    @Test fun hugeSignedVndKeepsEveryGlyphOnA320dpWindowAtActual130(){
        val first=rows(Long.MAX_VALUE,Long.MAX_VALUE,"VND");val second=rows(Long.MAX_VALUE,Long.MAX_VALUE,"VND").filterNot{it.entity==CloudEntity.LEDGER_WALLET.table}
        val snapshot=OverviewFinancialReadSnapshot(owner,first+second)
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=flowOf(snapshot)}
        compose.setContent{
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)){
                Box(androidx.compose.ui.Modifier.width(320.dp)){Screen(source=source,dark=true)}
            }
        }
        money("capital",formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"VND"));money("profit","+"+formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"VND"))
        for(kind in listOf("capital","profit")){
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("overview.investment.$kind",useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertFalse("$kind overflows at320dp: ${layout.size}, font=${layout.layoutInput.style.fontSize}, value=${layout.layoutInput.text}",layout.hasVisualOverflow)
            for(i in layout.layoutInput.text.indices){val box=layout.getBoundingBox(i);Assert.assertTrue("$kind glyph$i clipped $box / ${layout.size}",box.right<=layout.size.width+1 && box.bottom<=layout.size.height+1)}
        }
        compose.onNodeWithTag("overview.investment.section").performScrollTo()
        val bitmap=compose.onNodeWithTag("overview.investment.section").captureToImage().asAndroidBitmap()
        java.io.File(context.getExternalFilesDir(null),"overview-investment-VND-narrow320-dark-font130.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
    }

}
