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
class InvestmentSaleScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="saleLossAndHistoricalFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
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
            val asset=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
            repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft("55555555-5555-5555-5555-555555555555",assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,"2026-10-22T00:00:00Z","2026-10-22T00:00:00Z"),asset,LedgerWalletRecord.fromCloudRecord(wallet.record),null,"Reserve"),device,now).getOrThrow()

        }
    }
    @Composable private fun Screen(source:InvestmentRepository=repo,dark:Boolean=false,rates:List<ExchangeRateSnapshot> = emptyList()){MistiaTheme(darkTheme=dark){Scaffold{padding->InvestmentScreen(owner,source,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("VND","JPY"),exchangeRates=rates)}}}
    private fun open(){
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.sale.add"));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.sale.add").assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.sale.quantity").fetchSemanticsNodes().isNotEmpty()}
    }
    @Test fun actualSaleStoresFifoCapitalAndProfitAndShowsTheReducedStock(){
        compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.sale.available").assertTextContains("2.5",substring=true)
        compose.onNodeWithTag("investment.sale.quantity").performScrollTo().performTextInput("1")
        compose.onNodeWithTag("investment.sale.amount").performScrollTo().performTextInput("50")
        compose.onNodeWithTag("investment.sale.save").assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.sale.sheet").fetchSemanticsNodes().isEmpty()}
        val saved=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_TRADE.table)}.single{it.payload.financeRawString("kind_raw_value")=="sell"}
        Assert.assertEquals(28L,saved.payload.financeRawLong("released_cost_basis_minor"));Assert.assertEquals(22L,saved.payload.financeRawLong("realized_profit_loss_minor"))
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.asset.stock."+assetId));compose.onNodeWithTag("investment.asset.stock."+assetId).assertTextContains("1.5",substring=true)
    }
    private fun finishEntry(){
        compose.runOnIdle{android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{view->
            view.context.getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(view.windowToken,0)
        }}
        compose.waitUntil(5000){android.view.inspector.WindowInspector.getGlobalWindowViews().none{it.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime())==true}}
    }
    private fun await(tag:String){
        try{compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
        catch(error:Throwable){
            val context=ApplicationProvider.getApplicationContext<Context>()
            val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            bitmap?.let{frame->java.io.File(context.getExternalFilesDir(null),"sale-timeout-"+tag+".png").outputStream().use{frame.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};frame.recycle()}
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews().joinToString {view->
                "window="+view.width+"x"+view.height+" scrollY="+view.scrollY+" ime="+view.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime())
            }
            val roots=compose.onAllNodes(isRoot(),useUnmergedTree=true)
            val tree=(0 until roots.fetchSemanticsNodes().size).joinToString("\n"){roots[it].printToString()}
            throw AssertionError("Waiting for "+tag+"\n"+windows+"\n"+tree,error)
        }
    }
    private fun fill(quantity:String="1",gross:String="50"){
        compose.onNodeWithTag("investment.sale.quantity").performScrollTo().performTextInput(quantity)
        compose.onNodeWithTag("investment.sale.amount").performScrollTo().performTextInput(gross)
    }
    private fun save(){compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.sale.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag("investment.sale.save").assertIsEnabled().performClick()}
    private fun closed(){compose.waitUntil(5000){compose.onAllNodesWithTag("investment.sale.sheet").fetchSemanticsNodes().isEmpty()}}
    private fun rows()=runBlocking{store.investmentPurchaseSnapshot(owner)}
    private fun queues()=runBlocking{InvestmentSaleSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    @Test fun linkedWalletSetupFromTheScrolledSaleFormKeepsItsDraftAndCreatesNoSale(){
        compose.setContent{Screen()};open();fill();finishEntry()
        compose.onNodeWithTag("investment.sale.linkedWarning").performScrollTo().assertExists()
        compose.onNodeWithTag("investment.sale.setupLinked").performScrollTo().performClick();await("investment.wallet.link.picker")
        compose.onNodeWithTag("investment.wallet.link.option."+walletId).performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.wallet.link.picker").fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithTag("investment.sale.quantity").performScrollTo().assertTextContains("1",substring=true)
        compose.onNodeWithTag("investment.sale.amount").performScrollTo().assertTextContains("50",substring=true)
        compose.onNodeWithTag("investment.sale.linkedWarning").assertDoesNotExist()
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"})
    }
    @Test fun totalLossHasNoReceiptWalletAndPersistsTheLocalizedLiquidationNote(){
        compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.sale.quantity").performScrollTo().performTextInput("2.5");finishEntry()
        compose.onNodeWithTag("investment.sale.free").performScrollTo().performClick()
        compose.onNodeWithTag("investment.sale.amount").assertDoesNotExist();compose.onNodeWithTag("investment.sale.wallet").assertDoesNotExist()
        save();closed();val sale=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"}
        Assert.assertEquals(70L,sale.payload.financeRawLong("released_cost_basis_minor"));Assert.assertEquals(-70L,sale.payload.financeRawLong("realized_profit_loss_minor"));Assert.assertEquals(JsonNull,sale.payload["capital_return_wallet_id"])
        Assert.assertEquals(ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_trade_total_loss_badge,vn.com.quyln.mistia.core.designsystem.formatMinorUnits(0,"VND")),sale.payload.financeRawString("note"))
    }
    @Test fun invalidUnitOrOversellDisablesSubmission(){
        compose.setContent{Screen()};open();fill(quantity="3")
        compose.onNodeWithTag("investment.sale.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.sale.quantity").performScrollTo().performTextReplacement("1")
        compose.onNodeWithTag("investment.sale.unit").performScrollTo().performTextReplacement("pack")
        compose.onNodeWithTag("investment.sale.available").assertTextContains("0",substring=true);compose.onNodeWithTag("investment.sale.save").assertIsNotEnabled()
        Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }
    @Test fun fullySoldCommittedLostResponseRetriesWithoutNewWritesOrExtraStock(){
        var committed:InvestmentTradeCreationSnapshot?=null;var pending:Map<CloudEntity,List<QueuedMutation>>?=null;var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{
                val result=repo.saveSale(owner,request,deviceId,now)
                if(result.isSuccess && calls++==0){committed=store.investmentPurchaseSnapshot(owner);pending=InvestmentSaleSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)};return Result.failure(IllegalStateException("lost response"))}
                return result
            }
        }
        compose.setContent{Screen(source)};open();fill(quantity="2.5",gross="100");save();await("investment.sale.retry")
        compose.onNodeWithTag("investment.sale.available").performScrollTo().assertTextContains("0",substring=true)
        compose.onNodeWithTag("investment.sale.retry").performScrollTo().assertIsEnabled().performClick();closed()
        Assert.assertEquals(2,calls);Assert.assertEquals(committed,rows());Assert.assertEquals(pending,queues())
    }

    @Test fun foundationQuantityPrecisionIsAppliedBeforeTheAvailableStockLimit(){
        compose.setContent{Screen()};open();fill(quantity="2.50000000000000000000000000000000000000001",gross="100")
        save();closed()
        val sale=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"}
        Assert.assertEquals("2.5",sale.payload.financeRawString("quantity_decimal_string"))
    }
    @Test fun foreignSaleReadCannotExposeStockOrEnableSubmission(){
        val source=object:InvestmentRepository by repo {
            override fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = repo.observeSaleSnapshot(owner).map{it.copy(owner=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))}
        }
        compose.setContent{Screen(source)};open()
        compose.onNodeWithTag("investment.sale.asset").assertIsNotEnabled();compose.onNodeWithTag("investment.sale.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.sale.available").assertTextContains("—",substring=true)
        compose.onNodeWithTag("investment.sale.linkedWarning").assertDoesNotExist()
    }

    private fun futureExpense(amount:Long)=runBlocking {
        // This must remain later than the form's real current-time default across calendar changes.
        val futureAt=java.time.Instant.now().plusSeconds(86_400).toString()
        val source=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).single()
        val id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val raw=source.copy(id=id,payload=JsonObject(source.payload+buildJsonObject {
            put("id",id);put("settlement_role_raw_value",JsonNull);put("amount_minor",amount);put("reporting_amount_minor",amount);put("reporting_expense_minor",amount)
            put("occurred_at",futureAt)
        }))
        store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_TRANSACTION,id,owner.value,MutationKind.UPSERT,raw.payload,raw.updatedAt!!,raw.syncVersion,device))
    }
    @Test fun aBackdatedSaleReviewsTheExactReservedCashUsedByALaterExpenseAndCancelWritesNothing(){
        futureExpense(80);val before=rows();val pending=queues();var submitted:InvestmentSaleRequest?=null
        val source=object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{submitted=request;return repo.saveSale(owner,request,deviceId,now)}
        }
        compose.setContent{Screen(source)};open();fill();save();compose.waitUntil(5000){submitted!=null}
        val later=before.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id=="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}
        Assert.assertTrue("The expense must follow the actual submitted sale",java.time.Instant.parse(submitted!!.draft.occurredAt)<java.time.Instant.parse(later.payload.financeRawString("occurred_at")))
        await("investment.sale.funds.review")
        compose.onNodeWithTag("investment.sale.funds.message."+walletId).assertTextContains("22",substring=true)
        val resources=ApplicationProvider.getApplicationContext<Context>().resources
        compose.onNodeWithTag("investment.sale.funds.message."+walletId).assertTextEquals(resources.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_trade_cash_review_message,
            vn.com.quyln.mistia.core.designsystem.formatMinorUnits(0,"VND"),vn.com.quyln.mistia.core.designsystem.formatMinorUnits(22,"VND"),vn.com.quyln.mistia.core.designsystem.formatMinorUnits(0,"VND")))
        compose.onNodeWithTag("investment.sale.funds.context").assertTextEquals(resources.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_trade_sale_cash_review_context))
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.sale.funds.cancel").performClick();Assert.assertEquals(before,rows())
        save();await("investment.sale.funds.review");compose.onNodeWithTag("investment.sale.funds.confirm").performClick();closed()
        val cash=rows().rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("role_raw_value")=="cashConsumption"}.single()
        Assert.assertEquals(-22L,cash.payload.financeRawLong("amount_minor"))
    }
    @Test fun restorationKeepsTheSaleFieldsButDropsReviewAndDoesNotReplay(){
        futureExpense(80);val before=rows();val restoration=StateRestorationTester(compose);restoration.setContent{Screen()}
        open();fill();save();await("investment.sale.funds.review");restoration.emulateSavedInstanceStateRestore()
        await("investment.sale.quantity");compose.onNodeWithTag("investment.sale.quantity").assertTextContains("1",substring=true)
        compose.onNodeWithTag("investment.sale.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows())
        save();await("investment.sale.funds.review");compose.onNodeWithTag("investment.sale.funds.confirm").performClick();closed()
        Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"})
    }
    @Test fun foreignCapitalReceiptStoresRoundedCostAndTheRemainingProfitInTheWalletCurrency(){
        val foreignId="99999999-9999-9999-9999-999999999999"
        runBlocking{val mutation=WalletDraft(id=foreignId,name="JPY receipt",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now);store.commitMutation(mutation.record,mutation.pending)}
        compose.setContent{Screen(rates=listOf(ExchangeRateSnapshot("JPY","VND","10","manual",0,null)))};open();fill();finishEntry()
        compose.onNodeWithTag("investment.sale.wallet").performScrollTo().performClick();compose.onNodeWithTag("investment.sale.wallet."+foreignId).performClick();save();closed()
        val snapshot=rows();val sale=snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"}
        Assert.assertEquals("0.1",sale.payload.financeRawString("accounting_to_capital_return_rate_decimal_string"));Assert.assertEquals(3L,sale.payload.financeRawLong("capital_return_wallet_amount_minor"))
        val cash=snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("role_raw_value")=="cashAccrual"}
        Assert.assertEquals(2L,cash.payload.financeRawLong("amount_minor"));Assert.assertEquals(22L,cash.payload.financeRawLong("accounting_amount_minor"))
    }
    @Test fun replacingTheRepositoryDiscardsAnOldUncancellableSaleResponse(){
        val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>()
        var source by mutableStateOf<InvestmentRepository>(object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord> = withContext(NonCancellable){entered.complete(Unit);finish.await();Result.failure(IllegalStateException("old dependency"))}
        })
        compose.setContent{Screen(source)};open();fill();save();runBlocking{withTimeout(5000){entered.await()}}
        compose.runOnIdle{source=repo};compose.waitForIdle();compose.onNodeWithTag("investment.sale.save").assertIsEnabled()
        finish.complete(Unit);compose.waitForIdle();compose.onNodeWithTag("investment.sale.error").assertDoesNotExist()
        save();closed();Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"})
    }

    @Test fun saleLossAndHistoricalFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp(){
        futureExpense(Long.MAX_VALUE);val context=ApplicationProvider.getApplicationContext<Context>()
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
            java.io.File(context.getExternalFilesDir(null),"investment-sale-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}}
        fun headerPixels():IntArray {
            val sheet=compose.onNodeWithTag("investment.sale.sheet");val bounds=sheet.fetchSemanticsNode().boundsInRoot
            val bottom=maxOf(compose.onNodeWithTag("investment.sale.save").fetchSemanticsNode().boundsInRoot.bottom,compose.onNodeWithTag("investment.sale.cancel").fetchSemanticsNode().boundsInRoot.bottom)
            val bitmap=sheet.captureToImage().asAndroidBitmap();val height=kotlin.math.ceil(bottom-bounds.top).toInt()
            return IntArray(bitmap.width*height).also{bitmap.getPixels(it,0,bitmap.width,0,0,bitmap.width,height)}
        }
        val before=rows();val pending=queues()
        try{for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)){
            compose.runOnIdle{configure(code);language=code;dark=theme};open();compose.runOnIdle{configure(code)}
            fill(gross=Long.MAX_VALUE.toString());finishEntry()
            compose.onNodeWithTag("investment.sale.linkedWarning").performScrollTo();layout("investment.sale.linkedWarning");capture("warning","investment.sale.sheet");val header=headerPixels()
            compose.onNodeWithTag("investment.sale.amount").performScrollTo();layout("investment.sale.amount",true)
            compose.onNodeWithTag("investment.sale.asset").performScrollTo();layout("investment.sale.title");Assert.assertArrayEquals("Scrolled content must not paint over the pinned header",header,headerPixels());capture("paid","investment.sale.sheet")
            compose.onNodeWithTag("investment.sale.free").performScrollTo().performClick();await("investment.sale.zero.description")
            compose.onNodeWithTag("investment.sale.zero.description").performScrollTo();layout("investment.sale.zero.description");Assert.assertArrayEquals("Loss content must not paint over the pinned header",header,headerPixels());capture("loss","investment.sale.sheet")
            compose.onNodeWithTag("investment.sale.amount").assertDoesNotExist();compose.onNodeWithTag("investment.sale.wallet").assertDoesNotExist()
            compose.onNodeWithTag("investment.sale.free").performScrollTo().performClick();await("investment.sale.amount")
            val left=compose.onNodeWithTag("investment.sale.cancel").fetchSemanticsNode().boundsInRoot;val right=compose.onNodeWithTag("investment.sale.save").fetchSemanticsNode().boundsInRoot
            Assert.assertTrue(left.right<=right.left);Assert.assertTrue(left.height>=48*context.resources.displayMetrics.density);Assert.assertTrue(right.height>=48*context.resources.displayMetrics.density)
            save();await("investment.sale.funds.review");compose.runOnIdle{configure(code)}
            layout("investment.sale.funds.message."+walletId);layout("investment.sale.funds.confirm.text");capture("review","investment.sale.funds.review")
            compose.onNodeWithTag("investment.sale.funds.cancel").performClick();compose.onNodeWithTag("investment.sale.cancel").performClick();closed()
            Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }}finally{compose.runOnIdle{originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)};android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}}}
    }

    @Test fun anUnreadableHistoricalUnitShowsUnknownStockAndCannotOpenANewSale(){
        runBlocking {
            val old=store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_TRADE.table).single()
            val raw=old.copy(payload=JsonObject(old.payload+("unit_label" to buildJsonObject{put("bad",true)})))
            store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_TRADE,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        }
        compose.setContent{Screen()}
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.purchase.add"));true}.getOrDefault(false)}
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.purchase.add") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.sale.add"));compose.onNodeWithTag("investment.sale.add").assertIsNotEnabled()
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.asset.stock."+assetId));compose.onNodeWithTag("investment.asset.stock."+assetId).assertTextEquals("—")
    }

    @Test fun disappearingHistoricalFundUsageClearsTheOldReviewAndRequiresAFreshSave(){
        futureExpense(80);compose.setContent{Screen()};open();fill();save();await("investment.sale.funds.review")
        runBlocking {
            val old=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).single{it.id=="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}
            val raw=old.copy(deletedAt=now,payload=JsonObject(old.payload+("deleted_at" to JsonPrimitive(now))))
            store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_TRANSACTION,raw.id,owner.value,MutationKind.DELETE,raw.payload,now,0,device))
        }
        val before=rows();val pending=queues()
        compose.onNodeWithTag("investment.sale.funds.confirm").performClick()
        try{await("investment.sale.error")}catch(failure:Throwable){throw AssertionError(compose.onNodeWithTag("investment.sale.funds.review").printToString(),failure)}
        compose.onNodeWithTag("investment.sale.funds.review").assertDoesNotExist()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        save();closed();Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("kind_raw_value")=="sell"})
    }


    @Test fun cancellingFundConsentRevokesQueuedCallbacksEvenAfterAnIdenticalReopen() {
        futureExpense(80);var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{
                calls++;return if(request.consent==null)repo.saveSale(owner,request,deviceId,now) else Result.failure(IllegalStateException("Canceled presentation must not submit consent"))
            }
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill();save();await("investment.sale.funds.review")
        var oldConfirm:(()->Boolean)?=null;var oldCancel:(()->Boolean)?=null
        compose.onNodeWithTag("investment.sale.funds.confirm").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){oldConfirm=it}
        compose.onNodeWithTag("investment.sale.funds.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){oldCancel=it}
        compose.runOnIdle{oldCancel!!.invoke();oldConfirm!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(1,calls)}
        save();await("investment.sale.funds.review")
        compose.runOnIdle{oldConfirm!!.invoke();oldCancel!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(2,calls)}
        compose.onNodeWithTag("investment.sale.funds.review").assertIsDisplayed()
        compose.onNodeWithTag("investment.sale.funds.confirm").performClick();await("investment.sale.retry");compose.runOnIdle{Assert.assertEquals(3,calls)}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

    @Test fun closingTheFormRevokesAnAlreadyQueuedSaveCallbackBeforeCompositionDisposal() {
        var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Closed form must not submit"))}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill()
        var saveClick:(()->Boolean)?=null;var cancelClick:(()->Boolean)?=null
        compose.onNodeWithTag("investment.sale.save").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){saveClick=it}
        compose.onNodeWithTag("investment.sale.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){cancelClick=it}
        compose.runOnIdle{cancelClick!!.invoke();saveClick!!.invoke()};compose.waitForIdle()
        compose.runOnIdle{Assert.assertEquals(0,calls)};closed();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun editingAndRestoringTheSameValuesDoesNotReviveAnOldFailureRetryCallback() {
        var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Explicit failure"))}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill();save();await("investment.sale.retry")
        var retryClick:(()->Boolean)?=null
        compose.onNodeWithTag("investment.sale.retry").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){retryClick=it}
        compose.onNodeWithTag("investment.sale.amount").performScrollTo().performTextReplacement("80")
        compose.onNodeWithTag("investment.sale.amount").performScrollTo().performTextReplacement("50")
        compose.runOnIdle{retryClick!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(1,calls)}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

    @Test fun readFailureRevokesAnOpenFinancialReview() {
        futureExpense(80);val failure=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = flow{emit(repo.observeSaleSnapshot(owner).first());failure.await();throw java.io.IOException("Form observer lost")}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill();save();await("investment.sale.funds.review")
        compose.runOnIdle{failure.complete(Unit)};await("investment.sale.reload")
        compose.onNodeWithTag("investment.sale.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun lateUncancellablePreflightCannotPresentConsentAfterTheReadFailed() {
        futureExpense(80);val failure=CompletableDeferred<Unit>();val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val returned=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = flow{emit(repo.observeSaleSnapshot(owner).first());failure.await();throw java.io.IOException("Form observer lost")}
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord> = withContext(NonCancellable){entered.complete(Unit);release.await();repo.saveSale(owner,request,deviceId,now).also{returned.complete(Unit)}}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill();save()
        try {
            compose.waitUntil(5000){entered.isCompleted};compose.runOnIdle{failure.complete(Unit)};await("investment.sale.reload")
            compose.runOnIdle{release.complete(Unit)}
            compose.waitUntil(5000){returned.isCompleted && compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo)).fetchSemanticsNodes().isEmpty()}
            compose.onNodeWithTag("investment.sale.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }finally{release.complete(Unit);failure.complete(Unit)}
    }


    @Test fun reloadingAfterReadFailureDoesNotReviveTheOldPreflight() {
        futureExpense(80);var reads=0;var calls=0
        val failure=CompletableDeferred<Unit>();val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val returned=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = if(reads++==0)flow{emit(repo.observeSaleSnapshot(owner).first());failure.await();throw java.io.IOException("Read lost before recovery")} else repo.observeSaleSnapshot(owner)
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord> = if(calls++==0)withContext(NonCancellable){entered.complete(Unit);release.await();repo.saveSale(owner,request,deviceId,now).also{returned.complete(Unit)}} else repo.saveSale(owner,request,deviceId,now)
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill();save()
        try {
            compose.waitUntil(5000){entered.isCompleted};compose.runOnIdle{failure.complete(Unit)};await("investment.sale.reload")
            compose.onNodeWithTag("investment.sale.reload").performScrollTo().performClick()
            compose.waitUntil(5000){reads>=2 && compose.onAllNodesWithTag("investment.sale.reload").fetchSemanticsNodes().isEmpty()}
            compose.runOnIdle{release.complete(Unit)}
            compose.waitUntil(5000){returned.isCompleted && compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo)).fetchSemanticsNodes().isEmpty()}
            compose.onNodeWithTag("investment.sale.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
            save();await("investment.sale.funds.review");compose.runOnIdle{Assert.assertEquals(2,calls)}
            compose.onNodeWithTag("investment.sale.funds.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }finally{release.complete(Unit);failure.complete(Unit)}
    }


    @Test fun aCurrentCommittedRetrySurvivesMetadataOnlyAssetAndWalletAcks() {
        futureExpense(80);var successes=0
        val frozen=CompletableDeferred<InvestmentSaleRequest>();val observed=CompletableDeferred<Unit>();val version=Long.MAX_VALUE-9
        val source=object:InvestmentRepository by repo {
            override fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = repo.observeSaleSnapshot(owner).onEach{snapshot->if(snapshot.rows.any{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==assetId && it.syncVersion==version})observed.complete(Unit)}
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{
                val result=repo.saveSale(owner,request,deviceId,now)
                if(result.isSuccess && successes++==0){frozen.complete(request);return Result.failure(IllegalStateException("Committed response lost"))};return result
            }
        }
        compose.setContent{Screen(source)};open();fill();save();await("investment.sale.funds.review")
        compose.onNodeWithTag("investment.sale.funds.confirm").performClick();await("investment.sale.retry")
        runBlocking {
            val ackAt=java.time.Instant.now().toString()
            val changes=listOf(CloudEntity.INVESTMENT_ASSET to assetId,CloudEntity.LEDGER_WALLET to walletId).map{(entity,id)->
                val raw=store.record(owner,entity.table,id)!!
                val ack=raw.copy(payload=JsonObject(raw.payload+buildJsonObject{put("sync_version",version);put("updated_at",ackAt)}),syncVersion=version,updatedAt=ackAt)
                ack to PendingMutation(entity,id,owner.value,MutationKind.UPSERT,ack.payload,ackAt,version,device)
            };store.commitMutations(changes)
        }
        compose.waitUntil(5000){observed.isCompleted};compose.waitForIdle()
        val afterAck=rows();val pending=queues()
        Assert.assertTrue(planInvestmentSale(afterAck,runBlocking{frozen.await()},device,now).mutations.isEmpty())
        compose.onNodeWithTag("investment.sale.retry").performScrollTo().assertIsEnabled().performClick();closed()
        Assert.assertEquals(2,successes);Assert.assertEquals(afterAck,rows());Assert.assertEquals(pending,queues())
    }


    @Test fun aFailedReadAndRecoveryRevokesThePreviousRetryCallback() {
        var reads=0;var calls=0;val failure=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeSaleSnapshot(owner:UserId):Flow<InvestmentSaleSnapshot> = if(reads++==0)flow{emit(repo.observeSaleSnapshot(owner).first());failure.await();throw java.io.IOException("Retry read lost")} else repo.observeSaleSnapshot(owner)
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Explicit retry failure"))}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};open();fill();save();await("investment.sale.retry")
        var oldRetry:(()->Boolean)?=null
        compose.onNodeWithTag("investment.sale.retry").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){oldRetry=it}
        compose.runOnIdle{failure.complete(Unit)};await("investment.sale.reload")
        compose.onNodeWithTag("investment.sale.reload").performScrollTo().performClick()
        compose.waitUntil(5000){reads>=2 && compose.onAllNodes(hasTestTag("investment.sale.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.runOnIdle{oldRetry!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(1,calls)}
        compose.onNodeWithTag("investment.sale.retry").performScrollTo().assertIsEnabled().performClick();compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(2,calls)}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aQueuedSaveUsesTheCurrentAmountBeforeTheNextComposition() {
        val received=CompletableDeferred<InvestmentSaleRequest>()
        val source=object:InvestmentRepository by repo {
            override suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,deviceId:String,now:String):Result<CloudRecord>{received.complete(request);return repo.saveSale(owner,request,deviceId,now)}
        }
        compose.setContent{Screen(source)};open();fill()
        var saveClick:(()->Boolean)?=null;var replace:((androidx.compose.ui.text.AnnotatedString)->Boolean)?=null
        compose.onNodeWithTag("investment.sale.save").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){saveClick=it}
        compose.onNodeWithTag("investment.sale.amount").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetText){replace=it}
        compose.runOnIdle{replace!!.invoke(androidx.compose.ui.text.AnnotatedString("80"));saveClick!!.invoke()};closed()
        val request=runBlocking{received.await()};Assert.assertEquals(80L,request.draft.grossMinor)
        Assert.assertEquals(80L,rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==request.draft.id}.payload.financeRawLong("gross_amount_minor"))
    }

}
