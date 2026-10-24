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
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentTradeEditingScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="editingAndFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
        val font=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
        val size=Regex("Override size: ([0-9]+x[0-9]+)").find(shell("wm size"))?.groupValues?.get(1)
        val metrics=instrumentation.targetContext.resources.displayMetrics
        try {
            shell("wm size "+kotlin.math.round(320*metrics.density).toInt()+"x"+metrics.heightPixels);shell("settings put system font_scale 1.3")
            val end=android.os.SystemClock.uptimeMillis()+5000
            while((instrumentation.targetContext.resources.configuration.fontScale!=1.3f || instrumentation.targetContext.resources.configuration.screenWidthDp!=320) && android.os.SystemClock.uptimeMillis()<end)android.os.SystemClock.sleep(20)
            Assert.assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f);Assert.assertEquals(320,instrumentation.targetContext.resources.configuration.screenWidthDp);base.evaluate()
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

    private val saleId="77777777-7777-7777-7777-777777777777"
    private fun seedSale(gross:Long=50)=runBlocking {
        val asset=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
        val wallet=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,walletId)!!)
        val request=InvestmentSaleRequest(InvestmentSaleDraft(saleId,assetId,"1","box",gross,gross,"VND",null,null,null,walletId,null,null,now,now),asset,wallet,null,"Reserve")
        val result=repo.saveSale(owner,request,device,now);val error=result.exceptionOrNull()
        if(error is InvestmentSaleConfirmationRequired)repo.saveSale(owner,request.copy(consent=error.review.consent),device,now).getOrThrow() else result.getOrThrow()
    }
    private fun await(tag:String){compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
    private fun rows()=runBlocking{store.investmentPurchaseSnapshot(owner)}
    private fun queues()=runBlocking{InvestmentTradeDeletionSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    private val buyId="55555555-5555-5555-5555-555555555555"
    private fun openEdit(id:String=buyId) {
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.trade."+id));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.trade."+id).performClick();await("investment.trade.detail.quantity")
        compose.onNodeWithTag("investment.trade.detail.edit").performScrollTo().performClick();await("investment.edit.quantity")
    }
    @Test fun actualPurchaseEditHydratesOriginalValuesAndUpdatesTheSameTrade() {
        compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.quantity").assertTextContains("2.5",substring=true)
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().assertTextContains("70",substring=true).performTextReplacement("80")
        compose.onNodeWithTag("investment.edit.save").assertIsEnabled().performClick();await("investment.trade.detail.quantity")
        val raw=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==buyId}
        Assert.assertEquals(80L,raw.payload.financeRawLong("gross_amount_minor"));Assert.assertEquals("2026-10-22T00:00:00Z",raw.payload.financeRawString("created_at"))
        Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }
    @Test fun cancelPurchaseEditPreservesEverySourceRecordAndOutbox() {
        val before=rows();val pending=queues();compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("80")
        compose.onNodeWithTag("investment.edit.cancel").performClick();await("investment.trade.detail.quantity")
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun saleEditExcludesItsOriginalQuantityFromAvailableStock() {
        seedSale();compose.setContent{Screen()};openEdit(saleId)
        compose.onNodeWithTag("investment.edit.available").assertTextContains("2.5",substring=true)
        compose.onNodeWithTag("investment.edit.quantity").performScrollTo().performTextReplacement("2.5")
        compose.onNodeWithTag("investment.edit.save").assertIsEnabled().performClick();await("investment.trade.detail.quantity")
        val raw=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        Assert.assertEquals("0",raw.payload.financeRawString("position_quantity_after_decimal_string"))
        Assert.assertEquals(70L,raw.payload.financeRawLong("released_cost_basis_minor"));Assert.assertEquals(-20L,raw.payload.financeRawLong("realized_profit_loss_minor"))
    }
    private fun seedReserve(amount:Long=60)=runBlocking {
        val raw=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",owner.value,buildJsonObject {
            put("id","bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");put("user_id",owner.value);put("event_id","cccccccc-cccc-cccc-cccc-cccccccccccc");put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",walletId);put("ledger_transaction_id",JsonNull)
            put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual");put("amount_minor",amount);put("currency_code","VND");put("accounting_amount_minor",amount);put("accounting_currency_code","VND")
            put("occurred_at","2026-10-21T00:00:00Z");put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
        },now,null,0)
        store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_POSTING,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        // Build a coherent initial reserved-funding fixture through the public typed purchase planner.
        val snapshot=rows().let{it.copy(rows=it.rows.filterNot{row->
            (row.entity==CloudEntity.INVESTMENT_TRADE.table && row.id==buyId) ||
            (row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id==investmentLedgerIdentity(buyId,"funding")) ||
            (row.entity==CloudEntity.INVESTMENT_POSTING.table && row.id==investmentLedgerIdentity(buyId,"funding-posting"))
        })}
        val asset=InvestmentAssetRecord.fromCloudRecord(snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==assetId})
        val wallet=LedgerWalletRecord.fromCloudRecord(snapshot.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==walletId})
        val request=InvestmentPurchaseRequest(InvestmentPurchaseDraft(buyId,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,"2026-10-22T00:00:00Z","2026-10-22T00:00:00Z"),asset,wallet,null,"Reserve")
        val attempt=runCatching{planInvestmentPurchase(snapshot,request,device,now)}
        val review=(attempt.exceptionOrNull() as? InvestmentPurchaseConfirmationRequired)?.review
        val plan=attempt.getOrNull() ?: planInvestmentPurchase(snapshot,request.copy(consent=review?.consent),device,now)
        store.commitMutations(plan.mutations)
    }
    @Test fun editedFundReviewCancelAndRestorationKeepDraftButRequireFreshConsent() {
        seedReserve();val before=rows();val pending=queues();val restoration=StateRestorationTester(compose)
        restoration.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("60")
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review")
        compose.onNodeWithTag("investment.edit.funds.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review");restoration.emulateSavedInstanceStateRestore()
        await("investment.edit.amount");compose.onNodeWithTag("investment.edit.amount").assertTextContains("60",substring=true)
        compose.onNodeWithTag("investment.edit.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review");compose.onNodeWithTag("investment.edit.funds.confirm").performClick();await("investment.trade.detail.quantity")
        Assert.assertEquals(60L,rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==buyId}.payload.financeRawLong("gross_amount_minor"))
    }
    @Test fun committedEditResponseLossCanRetryTheExactResultWithoutAnyMoreWrites() {
        var calls=0
        val lost=object:InvestmentRepository by repo {
            override suspend fun editTrade(owner:UserId,request:InvestmentTradeEditRequest,deviceId:String,now:String):Result<CloudRecord> {
                calls++;val result=repo.editTrade(owner,request,deviceId,now)
                return if(calls==1 && result.isSuccess)Result.failure(java.io.IOException("Committed edit response lost")) else result
            }
        }
        compose.setContent{Screen(lost)};openEdit();compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("80")
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.retry")
        val after=rows();val pending=queues();compose.onNodeWithTag("investment.edit.retry").performScrollTo().assertIsEnabled().performClick();await("investment.trade.detail.quantity")
        Assert.assertEquals(2,calls);Assert.assertEquals(after,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun restoredEditCannotOverwriteANewerUnseenPrimary() {
        val restoration=StateRestorationTester(compose);restoration.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("80")
        runBlocking {
            val old=store.record(owner,CloudEntity.INVESTMENT_TRADE.table,buyId)!!
            val raw=old.copy(payload=JsonObject(old.payload+("note" to JsonPrimitive("Newer unseen note"))))
            store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_TRADE,buyId,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))
        }
        restoration.emulateSavedInstanceStateRestore();await("investment.edit.amount");val before=rows();val pending=queues()
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.error")
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun editUsesTheStoredSourceRateEvenWhenTheCurrentRateChanged() {
        runBlocking {
            val foreign=repo.saveAsset(owner,InvestmentAssetDraft("99999999-9999-9999-9999-999999999999",channel,"JPY stock","JPY","box"),device,now).getOrThrow()
            val wallet=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,walletId)!!)
            repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",foreign.id,"1","box",1,10,"VND","10","old provider",null,walletId,10,null,null,now,now),foreign,wallet,null,"Reserve"),device,now).getOrThrow()
        }
        compose.setContent{Screen(rates=listOf(ExchangeRateSnapshot("JPY","VND","20","new provider",0,null)))};openEdit("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("2")
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.trade.detail.quantity")
        val raw=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id=="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}
        Assert.assertEquals(20L,raw.payload.financeRawLong("accounting_gross_amount_minor"));Assert.assertEquals("10",raw.payload.financeRawString("exchange_rate_decimal_string"));Assert.assertEquals("old provider",raw.payload.financeRawString("exchange_rate_provider"))
    }

    @Test fun editingAndFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp(){
        val context=ApplicationProvider.getApplicationContext<Context>()
        runBlocking {
            val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,walletId)!!
            val raw=old.copy(payload=JsonObject(old.payload+("opening_balance_minor" to JsonPrimitive(Long.MAX_VALUE))))
            store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,walletId,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))
        };seedReserve(Long.MAX_VALUE)
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
            java.io.File(context.getExternalFilesDir(null),"investment-edit-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}}
        val before=rows();val pending=queues()
        try{for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)){
            compose.runOnIdle{configure(code);language=code;dark=theme};openEdit();compose.runOnIdle{configure(code)}
            compose.onNodeWithTag("investment.edit.quantity").performScrollTo().performTextReplacement("2.5")
            compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement(Long.MAX_VALUE.toString());layout("investment.edit.amount",true)
            compose.onNodeWithTag("investment.edit.asset").performScrollTo();capture("top","investment.edit.sheet")
            compose.onNodeWithTag("investment.edit.accounting").performScrollTo();layout("investment.edit.accounting")
            compose.onNodeWithTag("investment.edit.note").performScrollTo();capture("bottom","investment.edit.sheet")
            compose.onNodeWithTag("investment.edit.save").assertIsDisplayed();compose.onNodeWithTag("investment.edit.cancel").assertIsDisplayed()
            val left=compose.onNodeWithTag("investment.edit.cancel").fetchSemanticsNode().boundsInRoot;val right=compose.onNodeWithTag("investment.edit.save").fetchSemanticsNode().boundsInRoot
            Assert.assertTrue(left.right<=right.left);Assert.assertTrue(left.height>=48*context.resources.displayMetrics.density);Assert.assertTrue(right.height>=48*context.resources.displayMetrics.density)
            compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review");compose.runOnIdle{configure(code)}
            layout("investment.edit.funds.message."+walletId);layout("investment.edit.funds.confirm.text");capture("review","investment.edit.funds.review")
            compose.onNodeWithTag("investment.edit.funds.cancel").performClick();compose.onNodeWithTag("investment.edit.cancel").performClick();await("investment.trade.detail.quantity");compose.onNodeWithTag("investment.trade.detail.close").performClick();compose.waitUntil(5000){compose.onAllNodesWithTag("investment.trade.detail.sheet").fetchSemanticsNodes().isEmpty()}
            Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }}finally{compose.runOnIdle{originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)};android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}}}
    }


    private fun targetAsset()=runBlocking{repo.saveAsset(owner,InvestmentAssetDraft("88888888-8888-8888-8888-888888888888",channel,"Other stock","VND","box"),device,now).getOrThrow()}
    @Test fun movingPurchaseUpdatesTheSameTradeAndEveryPostingWithoutLosingOldStock() {
        val target=targetAsset();compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.asset").performScrollTo().performClick();compose.onNodeWithTag("investment.edit.asset."+target.id).performClick()
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.trade.detail.quantity")
        val snapshot=rows();val raw=snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==buyId}
        Assert.assertEquals(target.id,raw.payload.financeRawString("asset_id"));Assert.assertEquals(1,snapshot.rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
        Assert.assertTrue(snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("trade_id")==buyId}.all{it.payload.financeRawString("asset_id")==target.id})
    }
    @Test fun movingPurchaseNeededByALaterSaleShowsStockErrorAndWritesNothing() {
        seedSale();val target=targetAsset();val before=rows();val pending=queues();compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.asset").performScrollTo().performClick();compose.onNodeWithTag("investment.edit.asset."+target.id).performClick()
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.error")
        compose.onNodeWithTag("investment.edit.error").performScrollTo().assertTextEquals(ApplicationProvider.getApplicationContext<Context>().getString(R.string.investment_error_insufficient_position))
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun queuedEditSaveUsesCurrentMoneyBeforeTheNextComposition() {
        compose.setContent{Screen()};openEdit()
        var saveClick:(()->Boolean)?=null;var replace:((androidx.compose.ui.text.AnnotatedString)->Boolean)?=null
        compose.onNodeWithTag("investment.edit.save").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){saveClick=it}
        compose.onNodeWithTag("investment.edit.amount").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetText){replace=it}
        compose.runOnIdle{replace!!.invoke(androidx.compose.ui.text.AnnotatedString("80"));saveClick!!.invoke()};await("investment.trade.detail.quantity")
        Assert.assertEquals(80L,rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==buyId}.payload.financeRawLong("gross_amount_minor"))
    }
    @Test fun cancelEditRevokesItsQueuedSaveBeforeDisposal() {
        val before=rows();val pending=queues();compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("80")
        var saveClick:(()->Boolean)?=null;var cancel:(()->Boolean)?=null
        compose.onNodeWithTag("investment.edit.save").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){saveClick=it}
        compose.onNodeWithTag("investment.edit.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){cancel=it}
        compose.runOnIdle{cancel!!.invoke();saveClick!!.invoke()};await("investment.trade.detail.quantity")
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun canceledEditFundReviewCannotSubmitOrCancelAnIdenticalNewReview() {
        seedReserve();val before=rows();val pending=queues();compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("60")
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review")
        var confirm:(()->Boolean)?=null;var cancel:(()->Boolean)?=null
        compose.onNodeWithTag("investment.edit.funds.confirm").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){confirm=it}
        compose.onNodeWithTag("investment.edit.funds.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){cancel=it}
        compose.runOnIdle{cancel!!.invoke();confirm!!.invoke()};compose.waitForIdle();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review")
        compose.runOnIdle{confirm!!.invoke();cancel!!.invoke()};compose.waitForIdle();compose.onNodeWithTag("investment.edit.funds.review").assertIsDisplayed()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.edit.funds.confirm").performClick();await("investment.trade.detail.quantity")
        Assert.assertEquals(60L,rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==buyId}.payload.financeRawLong("gross_amount_minor"))
    }

    @Test fun editingPaidPurchaseToFreeStockRetiresItsFundingRows() {
        compose.setContent{Screen()};openEdit()
        compose.onNodeWithTag("investment.edit.free").performScrollTo().performClick()
        compose.onNodeWithTag("investment.edit.amount").assertDoesNotExist();compose.onNodeWithTag("investment.edit.wallet").assertDoesNotExist()
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.trade.detail.quantity")
        val snapshot=rows();val raw=snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==buyId}
        Assert.assertEquals(0L,raw.payload.financeRawLong("gross_amount_minor"));Assert.assertEquals("2.5",raw.payload.financeRawString("quantity_decimal_string"));Assert.assertEquals(JsonNull,raw.payload["funding_wallet_id"])
        Assert.assertNotNull(snapshot.rows.single{it.id==investmentLedgerIdentity(buyId,"funding")}.deletedAt);Assert.assertNotNull(snapshot.rows.single{it.id==investmentLedgerIdentity(buyId,"funding-posting")}.deletedAt)
    }
    @Test fun editingSaleToTotalLossPreservesIdentityAndUsesSystemLossPostings() {
        seedSale();compose.setContent{Screen()};openEdit(saleId)
        compose.onNodeWithTag("investment.edit.free").performScrollTo().performClick()
        compose.onNodeWithTag("investment.edit.amount").assertDoesNotExist();compose.onNodeWithTag("investment.edit.save").performClick();await("investment.trade.detail.quantity")
        val snapshot=rows();val raw=snapshot.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        Assert.assertEquals(0L,raw.payload.financeRawLong("gross_amount_minor"));Assert.assertEquals(-28L,raw.payload.financeRawLong("realized_profit_loss_minor"));Assert.assertEquals(JsonNull,raw.payload["capital_return_wallet_id"])
        Assert.assertEquals(investmentSystemWalletId(owner),snapshot.rows.single{it.id==investmentLedgerIdentity(saleId,"cash-accrual-posting")}.payload.financeRawString("wallet_id"))
    }
    @Test fun failedEditReadRevokesItsOpenFundReviewAndQueuedConfirm() {
        seedReserve();val failure=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observePurchaseSnapshot(owner:UserId):Flow<InvestmentPurchaseSnapshot> = flow{emit(repo.observePurchaseSnapshot(owner).first());failure.await();throw java.io.IOException("Edit read lost")}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source)};openEdit()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("60")
        compose.onNodeWithTag("investment.edit.save").performClick();await("investment.edit.funds.review")
        var confirm:(()->Boolean)?=null
        compose.onNodeWithTag("investment.edit.funds.confirm").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){confirm=it}
        compose.runOnIdle{failure.complete(Unit)};await("investment.edit.reload")
        compose.runOnIdle{confirm!!.invoke()};compose.waitForIdle();compose.onNodeWithTag("investment.edit.funds.review").assertDoesNotExist()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

    private fun foreignFreeStock()=runBlocking {
        val foreign=repo.saveAsset(owner,InvestmentAssetDraft("99999999-9999-9999-9999-999999999999",channel,"JPY free stock","JPY","box"),device,now).getOrThrow()
        repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",foreign.id,"1","box",0,0,"VND",null,null,null,null,null,null,null,"2026-10-22T01:00:00Z",now),foreign,null,null,"Reserve"),device,now).getOrThrow()
        foreign
    }
    @Test fun foreignFreePurchaseCanBecomePaidUsingTheAvailableCurrentRate() {
        foreignFreeStock();compose.setContent{Screen(rates=listOf(ExchangeRateSnapshot("JPY","VND","10","current",0,null)))};openEdit("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        compose.onNodeWithTag("investment.edit.free").performScrollTo().performClick()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("2")
        compose.onNodeWithTag("investment.edit.save").assertIsEnabled().performClick();await("investment.trade.detail.quantity")
        val raw=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id=="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}
        Assert.assertEquals(20L,raw.payload.financeRawLong("accounting_gross_amount_minor"));Assert.assertEquals("10",raw.payload.financeRawString("exchange_rate_decimal_string"))
    }
    @Test fun foreignTotalLossCanBecomeAReceiptUsingTheAvailableCurrentRate() {
        val foreign=foreignFreeStock()
        runBlocking{repo.saveSale(owner,InvestmentSaleRequest(InvestmentSaleDraft(saleId,foreign.id,"1","box",0,0,"VND",null,null,null,null,null,null,now,now),foreign,null,null,"Reserve"),device,now).getOrThrow()}
        compose.setContent{Screen(rates=listOf(ExchangeRateSnapshot("JPY","VND","10","current",0,null)))};openEdit(saleId)
        compose.onNodeWithTag("investment.edit.free").performScrollTo().performClick()
        compose.onNodeWithTag("investment.edit.amount").performScrollTo().performTextReplacement("2")
        compose.onNodeWithTag("investment.edit.save").assertIsEnabled().performClick();await("investment.trade.detail.quantity")
        val raw=rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        Assert.assertEquals(20L,raw.payload.financeRawLong("accounting_gross_amount_minor"));Assert.assertEquals(20L,raw.payload.financeRawLong("realized_profit_loss_minor"));Assert.assertEquals("10",raw.payload.financeRawString("exchange_rate_decimal_string"))
    }

}
