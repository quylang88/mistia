package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentPurchaseScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="purchaseAndFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
        val font=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
        val size=Regex("Override size: ([0-9]+x[0-9]+)").find(shell("wm size"))?.groupValues?.get(1)
        val metrics=instrumentation.targetContext.resources.displayMetrics
        try {
            shell("wm size "+kotlin.math.round(320*metrics.density).toInt()+"x"+metrics.heightPixels);shell("settings put system font_scale 1.3")
            val end=android.os.SystemClock.uptimeMillis()+5000
            while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<end)android.os.SystemClock.sleep(20)
            Assert.assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f);base.evaluate()
        }finally{shell("settings put system font_scale "+font);shell(if(size==null)"wm size reset" else "wm size "+size)}
    }}}).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-23T00:00:00Z"
    @Before fun setup(){
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstInvestmentRepository(store)
        runBlocking {
            repo.saveChannel(owner,InvestmentChannelDraft(channel,"Shop"),"VND",device,now).getOrThrow()
            repo.saveAsset(owner,InvestmentAssetDraft(assetId,channel,"Cards","VND","box"),device,now).getOrThrow()
            val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now)
            store.commitMutation(wallet.record,wallet.pending)
        }
    }
    @Composable private fun Screen(source:InvestmentRepository=repo,dark:Boolean=false,rates:List<ExchangeRateSnapshot> = emptyList()){MistiaTheme(darkTheme=dark){Scaffold{padding->InvestmentScreen(owner,source,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("VND","JPY"),exchangeRates=rates)}}}
    private fun open(){
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.purchase.add"));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.purchase.add").assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.purchase.quantity").fetchSemanticsNodes().isNotEmpty()}
    }
    @Test fun actualNewPurchaseFormStoresTheTotalOrderAndShowsNewStockAndActivity(){
        compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().performTextInput("2.5")
        compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextInput("70")
        compose.onNodeWithTag("investment.purchase.save").assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.purchase.sheet").fetchSemanticsNodes().isEmpty()}
        val saved=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_TRADE.table)}.single()
        Assert.assertEquals(70L,saved.payload.financeRawLong("gross_amount_minor"));Assert.assertEquals("2.5",saved.payload.financeRawString("quantity_decimal_string"))
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.asset.stock."+assetId))
        compose.onNodeWithTag("investment.asset.stock."+assetId).assertTextContains("2.5",substring=true)
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.trade."+saved.id))
        compose.onNodeWithTag("investment.trade."+saved.id).assertExists()
    }
    private fun rows()=runBlocking{store.investmentPurchaseSnapshot(owner)}
    private fun queue()=runBlocking{InvestmentPurchaseSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    private fun seedReserve()=runBlocking {
        val raw=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,"77777777-7777-7777-7777-777777777777",owner.value,buildJsonObject {
            put("id","77777777-7777-7777-7777-777777777777");put("user_id",owner.value);put("event_id","88888888-8888-8888-8888-888888888888")
            put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId);put("ledger_transaction_id",JsonNull)
            put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
            put("amount_minor",60L);put("currency_code","VND");put("accounting_amount_minor",60L);put("accounting_currency_code","VND")
            put("occurred_at","2026-10-22T00:00:00Z");put("created_at","2026-10-22T00:00:00Z");put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
        },now,null,0)
        store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_POSTING,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
    }
    private fun fill(){compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().performTextInput("2.5");compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextInput("70")}
    private fun save(){compose.onNodeWithTag("investment.purchase.save").assertIsEnabled().performClick()}
    private fun await(tag:String){compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
    private fun closed(){compose.waitUntil(5000){compose.onAllNodesWithTag("investment.purchase.sheet").fetchSemanticsNodes().isEmpty()}}
    @Test fun reservedPurchaseRequiresExplicitConsentAndCancelDoesNotWrite(){
        seedReserve();val before=rows();val pending=queue();compose.setContent{Screen()};open();fill();save();await("investment.purchase.funds.review")
        compose.onNodeWithTag("investment.purchase.funds.message."+walletId).assertTextContains("30",substring=true)
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
        compose.onNodeWithTag("investment.purchase.funds.cancel").performClick();Assert.assertEquals(before,rows())
        save();await("investment.purchase.funds.review");compose.onNodeWithTag("investment.purchase.funds.confirm").performClick();closed()
        val cash=InvestmentCashReadSnapshot(owner,rows().rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        Assert.assertEquals(30.toBigInteger(),investmentCashAllocation(cash.walletSnapshot(),"VND").locations.single{it.walletId==walletId}.originalBookedMinor)
    }
    @Test fun freeStockHasNoFundingControlsAndCreatesNoMoneyRows(){
        val before=rows();compose.setContent{Screen()};open();compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().performTextInput("3")
        compose.onNodeWithTag("investment.purchase.free").performScrollTo().performClick()
        compose.onNodeWithTag("investment.purchase.amount").assertDoesNotExist();compose.onNodeWithTag("investment.purchase.wallet").assertDoesNotExist()
        save();closed();val after=rows()
        Assert.assertEquals(1,after.rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
        Assert.assertEquals(ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_trade_promotional_free_badge),after.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.payload.financeRawString("note"))
        Assert.assertEquals(before.rows.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table},after.rows.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table})
    }
    @Test fun restoreKeepsFieldsAndIdentityButDropsConsentAndNeverReplays(){
        seedReserve();val before=rows();val restoration=StateRestorationTester(compose);restoration.setContent{Screen()}
        open();fill();save();await("investment.purchase.funds.review");restoration.emulateSavedInstanceStateRestore()
        await("investment.purchase.quantity");compose.onNodeWithTag("investment.purchase.quantity").assertTextContains("2.5",substring=true)
        compose.onNodeWithTag("investment.purchase.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows())
        save();await("investment.purchase.funds.review");compose.onNodeWithTag("investment.purchase.funds.confirm").performClick();closed()
        Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }
    @Test fun actualCommittedLostResponseRetriesTheSameCompleteResultWithoutWrites(){
        seedReserve();var calls=0;var committed:InvestmentPurchaseSnapshot?=null;var pending:Map<CloudEntity,List<QueuedMutation>>?=null
        val source=object:InvestmentRepository by repo {
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{
                val result=repo.savePurchase(owner,request,deviceId,now)
                if(result.isSuccess && calls++==0){committed=store.investmentPurchaseSnapshot(owner);pending=InvestmentPurchaseSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)};return Result.failure(IllegalStateException("lost response"))}
                return result
            }
        }
        compose.setContent{Screen(source)};open();fill();save();await("investment.purchase.funds.review");compose.onNodeWithTag("investment.purchase.funds.confirm").performClick();await("investment.purchase.retry")
        Assert.assertEquals(committed,rows());compose.onNodeWithTag("investment.purchase.retry").performScrollTo().assertIsEnabled().performClick();closed()
        Assert.assertEquals(2,calls);Assert.assertEquals(committed,rows());Assert.assertEquals(pending,queue())
    }
    @Test fun changedHiddenBalanceRequiresANewReviewWithTheNewExactAmount(){
        seedReserve();compose.setContent{Screen()};open();fill();save();await("investment.purchase.funds.review")
        runBlocking {
            val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,walletId)!!
            val changed=old.copy(payload=JsonObject(old.payload+("opening_balance_minor" to JsonPrimitive(101L))))
            store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,walletId,owner.value,MutationKind.UPSERT,changed.payload,now,0,device))
        }
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.purchase.funds.confirm") and isNotEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.purchase.funds.cancel").performClick();save();await("investment.purchase.funds.review")
        compose.onNodeWithTag("investment.purchase.funds.message."+walletId).assertTextContains("29",substring=true)
        compose.onNodeWithTag("investment.purchase.funds.confirm").performClick();closed()
    }
    @Test fun replacingRepositoryCancelsOldDependencyAndDropsItsReview(){
        seedReserve();val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>();var source by mutableStateOf<InvestmentRepository>(object:InvestmentRepository by repo {
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord> = withContext(NonCancellable){entered.complete(Unit);finish.await();Result.failure(IllegalStateException("old dependency"))}
        })
        compose.setContent{Screen(source)};open();fill();save();runBlocking{withTimeout(5000){entered.await()}}
        compose.runOnIdle{source=repo};compose.waitForIdle();compose.onNodeWithTag("investment.purchase.save").assertIsEnabled()
        finish.complete(Unit);compose.waitForIdle();compose.onNodeWithTag("investment.purchase.error").assertDoesNotExist()
        save();await("investment.purchase.funds.review")
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }

    @Test fun purchaseAndFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp(){
        seedReserve();val context=ApplicationProvider.getApplicationContext<Context>()
        runBlocking{for(row in rows().rows.filter{it.id==walletId || it.entity==CloudEntity.INVESTMENT_POSTING.table}){
            val raw=row.copy(payload=JsonObject(row.payload+buildJsonObject {
                if(row.id==walletId)put("opening_balance_minor",Long.MAX_VALUE) else {put("amount_minor",Long.MAX_VALUE);put("accounting_amount_minor",Long.MAX_VALUE)}
            }));store.commitMutation(raw,PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))
        }}
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config){Screen(dark=dark)}
        }
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String){
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            };windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        fun layout(tag:String,editable:Boolean=false){
            val node=compose.onNodeWithTag(tag,useUnmergedTree=true);val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val result=layouts.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true));Assert.assertFalse(result.didOverflowHeight)
            val width=if(editable)node.fetchSemanticsNode().boundsInRoot.width-32*context.resources.displayMetrics.density else result.size.width.toFloat()
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue("Clipped "+tag+": "+result.getLineRight(line)+" > "+width,result.getLineRight(line)<=width+1f);Assert.assertTrue(result.getLineLeft(line)>=-1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{c->if(!Character.isWhitespace(c))Assert.assertTrue("Missing glyph "+c,paint.hasGlyph(String(Character.toChars(c))))}
        }
        fun capture(kind:String,tag:String){val bitmap=compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-purchase-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}}
        val before=rows();val pending=queue()
        try{for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)){
            compose.runOnIdle{configure(code);language=code;dark=theme};open();compose.runOnIdle{configure(code)}
            compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().performTextInput("2.5")
            compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextInput(Long.MAX_VALUE.toString());layout("investment.purchase.amount",true)
            compose.onNodeWithTag("investment.purchase.asset").performScrollTo();capture("top","investment.purchase.sheet")
            compose.onNodeWithTag("investment.purchase.accounting").performScrollTo();layout("investment.purchase.accounting")
            compose.onNodeWithTag("investment.purchase.note").performScrollTo();capture("bottom","investment.purchase.sheet")
            compose.onNodeWithTag("investment.purchase.save").assertIsDisplayed();compose.onNodeWithTag("investment.purchase.cancel").assertIsDisplayed()
            val left=compose.onNodeWithTag("investment.purchase.cancel").fetchSemanticsNode().boundsInRoot;val right=compose.onNodeWithTag("investment.purchase.save").fetchSemanticsNode().boundsInRoot
            Assert.assertTrue(left.right<=right.left);Assert.assertTrue(left.height>=48*context.resources.displayMetrics.density);Assert.assertTrue(right.height>=48*context.resources.displayMetrics.density)
            save();await("investment.purchase.funds.review");compose.runOnIdle{configure(code)}
            layout("investment.purchase.funds.message."+walletId);layout("investment.purchase.funds.confirm.text");capture("review","investment.purchase.funds.review")
            compose.onNodeWithTag("investment.purchase.funds.cancel").performClick();compose.onNodeWithTag("investment.purchase.cancel").performClick();closed()
            Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
        }}finally{compose.runOnIdle{originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)};android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}}}
    }

    @Test fun foreignAssetShowsMissingRateThenPersistsPairedTotalWithTheEffectiveRate(){
        runBlocking {
            val old=store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!
            val raw=old.copy(payload=JsonObject(old.payload+("currency_code" to JsonPrimitive("JPY"))))
            store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_ASSET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        }
        var rates by mutableStateOf<List<ExchangeRateSnapshot>>(emptyList())
        compose.setContent{Screen(rates=rates)};open()
        compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().performTextInput("2")
        compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextInput("7")
        compose.onNodeWithTag("investment.purchase.input.error").performScrollTo().assertExists();compose.onNodeWithTag("investment.purchase.save").assertIsNotEnabled()
        compose.runOnIdle{rates=listOf(ExchangeRateSnapshot("JPY","VND","10","manual",0,null))}
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.purchase.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        save();closed();val trade=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}
        Assert.assertEquals(7L,trade.payload.financeRawLong("gross_amount_minor"));Assert.assertEquals(70L,trade.payload.financeRawLong("accounting_gross_amount_minor"))
        Assert.assertEquals("10",trade.payload.financeRawString("exchange_rate_decimal_string"));Assert.assertEquals("manual",trade.payload.financeRawString("exchange_rate_provider"))
    }
    @Test fun foreignPurchaseReadCannotExposeAnotherOwnersAssetsOrSubmit(){
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = repo.observePurchaseSnapshot(owner).map{it.copy(owner=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))}
        }
        compose.setContent{Screen(source)};open();compose.onNodeWithTag("investment.purchase.asset").assertIsNotEnabled()
        compose.onNodeWithTag("investment.purchase.save").assertIsNotEnabled();Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }

    @Test fun failedObservedReadDisablesSubmissionUntilExplicitReload(){
        val fail=CompletableDeferred<Unit>();var subscriptions=0
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = flow {
                val first=subscriptions++==0;emit(repo.observePurchaseSnapshot(owner).first())
                if(first){fail.await();throw IllegalStateException("read failed")}
                awaitCancellation()
            }
        }
        compose.setContent{Screen(source)};open();fill();compose.onNodeWithTag("investment.purchase.save").assertIsEnabled()
        fail.complete(Unit);await("investment.purchase.error");compose.onNodeWithTag("investment.purchase.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.purchase.reload").performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.purchase.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().assertTextContains("2.5",substring=true)
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }

    @Test fun decimalCommaQuantityMatchesSwiftAndStoresAnExactDecimalString(){
        compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.purchase.quantity").performScrollTo().performTextInput("2,5")
        compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextInput("70")
        save();closed();val trade=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}
        Assert.assertEquals("2.5",trade.payload.financeRawString("quantity_decimal_string"));Assert.assertEquals(70L,trade.payload.financeRawLong("gross_amount_minor"))
    }

    @Test fun anIncomeThatRemovesFundUsageDoesNotTrapThePurchaseInAnEmptyReview(){
        seedReserve();compose.setContent{Screen()};open();fill();save();await("investment.purchase.funds.review")
        runBlocking {
            val id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";val at="2026-10-22T12:00:00Z"
            val raw=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
                put("id",id);put("user_id",owner.value);put("created_at",at);put("updated_at",now);put("occurred_at",at);put("deleted_at",JsonNull);put("sync_version",0L)
                put("primary_kind_raw_value","income");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Income");put("is_archived",false)
                put("amount_minor",30L);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull)
                put("reporting_currency_code","VND");put("reporting_amount_minor",30L);put("reporting_income_minor",30L);put("reporting_expense_minor",0L)
            },now,null,0)
            store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_TRANSACTION,id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        }
        val before=rows();val pending=queue();compose.onNodeWithTag("investment.purchase.funds.confirm").performClick()
        try{await("investment.purchase.error")}catch(failure:Throwable){throw AssertionError(compose.onNodeWithTag("investment.purchase.funds.review").printToString(),failure)}
        compose.onNodeWithTag("investment.purchase.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
        save();closed();Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }


    @Test fun cancellingFundConsentRevokesQueuedCallbacksEvenAfterAnIdenticalReopen() {
        seedReserve();var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{
                calls++;return if(request.consent==null)repo.savePurchase(owner,request,deviceId,now) else Result.failure(IllegalStateException("Canceled presentation must not submit consent"))
            }
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill();save();await("investment.purchase.funds.review")
        var oldConfirm:(()->Boolean)?=null;var oldCancel:(()->Boolean)?=null
        compose.onNodeWithTag("investment.purchase.funds.confirm").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){oldConfirm=it}
        compose.onNodeWithTag("investment.purchase.funds.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){oldCancel=it}
        compose.runOnIdle{oldCancel!!.invoke();oldConfirm!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(1,calls)}
        save();await("investment.purchase.funds.review")
        compose.runOnIdle{oldConfirm!!.invoke();oldCancel!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(2,calls)}
        compose.onNodeWithTag("investment.purchase.funds.review").assertIsDisplayed()
        compose.onNodeWithTag("investment.purchase.funds.confirm").performClick();await("investment.purchase.retry");compose.runOnIdle{Assert.assertEquals(3,calls)}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }

    @Test fun closingTheFormRevokesAnAlreadyQueuedSaveCallbackBeforeCompositionDisposal() {
        var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Closed form must not submit"))}
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill()
        var saveClick:(()->Boolean)?=null;var cancelClick:(()->Boolean)?=null
        compose.onNodeWithTag("investment.purchase.save").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){saveClick=it}
        compose.onNodeWithTag("investment.purchase.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){cancelClick=it}
        compose.runOnIdle{cancelClick!!.invoke();saveClick!!.invoke()};compose.waitForIdle()
        compose.runOnIdle{Assert.assertEquals(0,calls)};closed();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }
    @Test fun editingAndRestoringTheSameValuesDoesNotReviveAnOldFailureRetryCallback() {
        var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Explicit failure"))}
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill();save();await("investment.purchase.retry")
        var retryClick:(()->Boolean)?=null
        compose.onNodeWithTag("investment.purchase.retry").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){retryClick=it}
        compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextReplacement("80")
        compose.onNodeWithTag("investment.purchase.amount").performScrollTo().performTextReplacement("70")
        compose.runOnIdle{retryClick!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(1,calls)}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }

    @Test fun readFailureRevokesAnOpenFinancialReview() {
        seedReserve();val failure=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = flow{emit(repo.observePurchaseSnapshot(owner).first());failure.await();throw java.io.IOException("Form observer lost")}
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill();save();await("investment.purchase.funds.review")
        compose.runOnIdle{failure.complete(Unit)};await("investment.purchase.reload")
        compose.onNodeWithTag("investment.purchase.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }
    @Test fun lateUncancellablePreflightCannotPresentConsentAfterTheReadFailed() {
        seedReserve();val failure=CompletableDeferred<Unit>();val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val returned=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = flow{emit(repo.observePurchaseSnapshot(owner).first());failure.await();throw java.io.IOException("Form observer lost")}
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord> = withContext(NonCancellable){entered.complete(Unit);release.await();repo.savePurchase(owner,request,deviceId,now).also{returned.complete(Unit)}}
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill();save()
        try {
            compose.waitUntil(5000){entered.isCompleted};compose.runOnIdle{failure.complete(Unit)};await("investment.purchase.reload")
            compose.runOnIdle{release.complete(Unit)}
            compose.waitUntil(5000){returned.isCompleted && compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo)).fetchSemanticsNodes().isEmpty()}
            compose.onNodeWithTag("investment.purchase.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
        }finally{release.complete(Unit);failure.complete(Unit)}
    }


    @Test fun reloadingAfterReadFailureDoesNotReviveTheOldPreflight() {
        seedReserve();var reads=0;var calls=0
        val failure=CompletableDeferred<Unit>();val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val returned=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = if(reads++==0)flow{emit(repo.observePurchaseSnapshot(owner).first());failure.await();throw java.io.IOException("Read lost before recovery")} else repo.observePurchaseSnapshot(owner)
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord> = if(calls++==0)withContext(NonCancellable){entered.complete(Unit);release.await();repo.savePurchase(owner,request,deviceId,now).also{returned.complete(Unit)}} else repo.savePurchase(owner,request,deviceId,now)
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill();save()
        try {
            compose.waitUntil(5000){entered.isCompleted};compose.runOnIdle{failure.complete(Unit)};await("investment.purchase.reload")
            compose.onNodeWithTag("investment.purchase.reload").performScrollTo().performClick()
            compose.waitUntil(5000){reads>=2 && compose.onAllNodesWithTag("investment.purchase.reload").fetchSemanticsNodes().isEmpty()}
            compose.runOnIdle{release.complete(Unit)}
            compose.waitUntil(5000){returned.isCompleted && compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo)).fetchSemanticsNodes().isEmpty()}
            compose.onNodeWithTag("investment.purchase.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
            save();await("investment.purchase.funds.review");compose.runOnIdle{Assert.assertEquals(2,calls)}
            compose.onNodeWithTag("investment.purchase.funds.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
        }finally{release.complete(Unit);failure.complete(Unit)}
    }


    @Test fun aCurrentCommittedRetrySurvivesMetadataOnlyAssetAndWalletAcks() {
        seedReserve();var successes=0
        val frozen=CompletableDeferred<InvestmentPurchaseRequest>();val observed=CompletableDeferred<Unit>();val version=Long.MAX_VALUE-9
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = repo.observePurchaseSnapshot(owner).onEach{snapshot->if(snapshot.rows.any{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==assetId && it.syncVersion==version})observed.complete(Unit)}
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{
                val result=repo.savePurchase(owner,request,deviceId,now)
                if(result.isSuccess && successes++==0){frozen.complete(request);return Result.failure(IllegalStateException("Committed response lost"))};return result
            }
        }
        compose.setContent{Screen(source)};open();fill();save();await("investment.purchase.funds.review")
        compose.onNodeWithTag("investment.purchase.funds.confirm").performClick();await("investment.purchase.retry")
        runBlocking {
            val ackAt=java.time.Instant.now().toString()
            val changes=listOf(CloudEntity.INVESTMENT_ASSET to assetId,CloudEntity.LEDGER_WALLET to walletId).map{(entity,id)->
                val raw=store.record(owner,entity.table,id)!!
                val ack=raw.copy(payload=JsonObject(raw.payload+buildJsonObject{put("sync_version",version);put("updated_at",ackAt)}),syncVersion=version,updatedAt=ackAt)
                ack to PendingMutation(entity,id,owner.value,MutationKind.UPSERT,ack.payload,ackAt,version,device)
            };store.commitMutations(changes)
        }
        compose.waitUntil(5000){observed.isCompleted};compose.waitForIdle()
        val afterAck=rows();val pending=queue()
        Assert.assertTrue(planInvestmentPurchase(afterAck,runBlocking{frozen.await()},device,now).mutations.isEmpty())
        // This case tests metadata ACK/retry authority. Activate its real accessibility
        // action so an IME/reflow between scroll and pointer injection cannot miss it.
        compose.onNodeWithTag("investment.purchase.retry").performScrollTo().assertIsEnabled()
            .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){Assert.assertTrue(it())}
        closed();Assert.assertEquals(2,successes)
        Assert.assertEquals(2,successes);Assert.assertEquals(afterAck,rows());Assert.assertEquals(pending,queue())
    }


    @Test fun aFailedReadAndRecoveryRevokesThePreviousRetryCallback() {
        var reads=0;var calls=0;val failure=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = if(reads++==0)flow{emit(repo.observePurchaseSnapshot(owner).first());failure.await();throw java.io.IOException("Retry read lost")} else repo.observePurchaseSnapshot(owner)
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Explicit retry failure"))}
        }
        val before=rows();val pending=queue();compose.setContent{Screen(source)};open();fill();save();await("investment.purchase.retry")
        var oldRetry:(()->Boolean)?=null
        compose.onNodeWithTag("investment.purchase.retry").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){oldRetry=it}
        compose.runOnIdle{failure.complete(Unit)};await("investment.purchase.reload")
        compose.onNodeWithTag("investment.purchase.reload").performScrollTo().performClick()
        compose.waitUntil(5000){reads>=2 && compose.onAllNodes(hasTestTag("investment.purchase.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.runOnIdle{oldRetry!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(1,calls)}
        compose.onNodeWithTag("investment.purchase.retry").performScrollTo().assertIsEnabled().performClick();compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(2,calls)}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queue())
    }
    @Test fun aQueuedSaveUsesTheCurrentAmountBeforeTheNextComposition() {
        val received=CompletableDeferred<InvestmentPurchaseRequest>()
        val source=object:InvestmentRepository by repo {
            override suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,deviceId:String,now:String):Result<CloudRecord>{received.complete(request);return repo.savePurchase(owner,request,deviceId,now)}
        }
        compose.setContent{Screen(source)};open();fill()
        var saveClick:(()->Boolean)?=null;var replace:((androidx.compose.ui.text.AnnotatedString)->Boolean)?=null
        compose.onNodeWithTag("investment.purchase.save").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){saveClick=it}
        compose.onNodeWithTag("investment.purchase.amount").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetText){replace=it}
        compose.runOnIdle{replace!!.invoke(androidx.compose.ui.text.AnnotatedString("80"));saveClick!!.invoke()};closed()
        val request=runBlocking{received.await()};Assert.assertEquals(80L,request.draft.grossMinor)
        Assert.assertEquals(80L,rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==request.draft.id}.payload.financeRawLong("gross_amount_minor"))
    }

}
