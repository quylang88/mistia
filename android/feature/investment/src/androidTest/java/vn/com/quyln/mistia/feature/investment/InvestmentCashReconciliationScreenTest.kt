package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import java.math.BigInteger
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
class InvestmentCashReconciliationScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="reconciliationFormsFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
        val font=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
        val originalSize=Regex("Override size: ([0-9]+x[0-9]+)").find(shell("wm size"))?.groupValues?.get(1)
        val metrics=instrumentation.targetContext.resources.displayMetrics
        try {
            shell("wm size "+kotlin.math.round(320*metrics.density).toInt()+"x"+metrics.heightPixels);shell("settings put system font_scale 1.3")
            val end=android.os.SystemClock.uptimeMillis()+5000
            while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<end)android.os.SystemClock.sleep(20)
            Assert.assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f);base.evaluate()
        }finally{shell("settings put system font_scale "+font);shell(if(originalSize==null)"wm size reset" else "wm size "+originalSize)}
    }}}).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-22T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private var repository by mutableStateOf<InvestmentRepository?>(null)
    private var displayedOwner by mutableStateOf(owner)
    private var activeOwner=owner
    private var language by mutableStateOf<String?>(null)
    private var dark by mutableStateOf(false)
    private fun rows(foreign:Boolean=false):List<CloudRecord> {
        fun wallet(key:Int,opening:Long,code:String="JPY")=WalletDraft(id=id(key),name="Wallet$key",kind=WalletKind.CASH,currencyCode=code,openingBalanceMinor=opening).toMutation(owner,null,device,now).record
        val system=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(2))}))}
        fun cash(key:Int,wallet:Int,amount:Long,code:String="JPY")=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(key),owner.value,buildJsonObject {
            put("id",id(key));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
            put("event_id",id(key+100));put("wallet_id",id(wallet));put("ledger_transaction_id",id(key+100));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",amount);put("currency_code",code);put("accounting_amount_minor",amount);put("accounting_currency_code","JPY");put("occurred_at",now)
        },now,null,0)
        return listOf(system,wallet(1,150),wallet(2,0),wallet(3,200,if(foreign)"VND" else "JPY"),cash(10,1,50),cash(11,3,60,if(foreign)"VND" else "JPY"))
    }
    private fun start(foreign:Boolean=false,restoration:StateRestorationTester?=null,wrap:(InvestmentRepository)->InvestmentRepository={it}) {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={activeOwner})
        runBlocking{store.commitMutations(rows(foreign).map{row->row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)})}
        repository=wrap(OfflineFirstInvestmentRepository(store))
        val context=ApplicationProvider.getApplicationContext<Context>()
        val content:@Composable ()->Unit={
            val configuration=android.content.res.Configuration(context.resources.configuration).apply{language?.let{setLocale(java.util.Locale.forLanguageTag(it))}}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(configuration),androidx.compose.ui.platform.LocalConfiguration provides configuration){
                MistiaTheme(darkTheme=dark){Scaffold{insets->InvestmentScreen(displayedOwner,requireNotNull(repository),{},Modifier.padding(insets),"JPY",{device},listOf("JPY","VND"))}}
            }
        }
        if(restoration==null)compose.setContent(content) else restoration.setContent(content)
    }
    private fun snapshot()=runBlocking{store.investmentCashSnapshot(owner)}
    private fun queues()=runBlocking{InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    private fun await(tag:String) {
        compose.waitUntil(5000){
            if(compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty())true
            else {runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag(tag))};false}
        }
    }
    private fun tap(tag:String){await(tag);val node=compose.onNodeWithTag(tag);if(runCatching{node.assertIsDisplayed()}.isFailure)node.performScrollTo();node.assertIsDisplayed().assertIsEnabled().performClick()}
    private fun saved(count:Int){compose.waitUntil(5000){snapshot().rows.count{it.entity==CloudEntity.LEDGER_TRANSACTION.table}==count};compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.reconciliation.sheet").fetchSemanticsNodes().isEmpty()}}
    @Test fun singleActualTransferRequiresConsentThenPersistsEightyActualAndFiftyBooked() {
        start();tap("investment.cash.reconcile."+id(1));await("investment.cash.reconciliation.sheet")
        compose.onNodeWithTag("investment.cash.reconciliation.amount").performTextReplacement("80")
        compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsNotEnabled()
        tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");saved(1)
        val after=snapshot();val actual=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(BigInteger.valueOf(70),actual[id(1)]);Assert.assertEquals(BigInteger.valueOf(80),actual[id(2)])
        Assert.assertEquals(BigInteger.valueOf(110),investmentCashFinancialView(after,"JPY").availableMinor)
        Assert.assertEquals(9,queues().values.sumOf{it.size})
    }
    @Test fun reconcileAllShowsBothRealInstructionsAndSavesOneCompleteSixRowBatch() {
        start();tap("investment.cash.reconcile.all");await("investment.cash.reconciliation.sheet")
        compose.onNodeWithTag("investment.cash.reconciliation.instruction."+id(1)).assertExists()
        compose.onNodeWithTag("investment.cash.reconciliation.instruction."+id(3)).assertExists()
        tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");saved(2)
        Assert.assertEquals(12,snapshot().rows.size);Assert.assertEquals(12,queues().values.sumOf{it.size})
        Assert.assertEquals(BigInteger.valueOf(110),investmentCashFinancialView(snapshot(),"JPY").linkedBalances!!.investmentMinor)
    }
    @Test fun foreignOriginalLocationRemainsVisibleButCannotBeReconciledOrIncludedInAll() {
        start(true);await("investment.cash.location.original."+id(3));compose.onNodeWithTag("investment.cash.location.original."+id(3)).assertExists()
        compose.onAllNodesWithTag("investment.cash.reconcile."+id(3)).assertCountEquals(0)
        tap("investment.cash.reconcile.all");await("investment.cash.reconciliation.sheet")
        compose.onNodeWithTag("investment.cash.reconciliation.instruction."+id(1)).assertExists()
        compose.onAllNodesWithTag("investment.cash.reconciliation.instruction."+id(3)).assertCountEquals(0)
        val before=snapshot();val pending=queues();tap("investment.cash.reconciliation.cancel")
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun lostSuccessfulSingleResponseCanRetryAfterAllocationDisappearsWithoutDoubleDebiting() {
        var calls=0;val requests=mutableListOf<InvestmentCashReconciliationRequest>()
        start(wrap={real->object:InvestmentRepository by real{
            override suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit>{requests+=request;calls++;val result=real.reconcileCash(owner,request,deviceId,now);return if(calls==1 && result.isSuccess)Result.failure(java.io.IOException("receipt lost")) else result}
        }})
        tap("investment.cash.reconcile."+id(1));compose.onNodeWithTag("investment.cash.reconciliation.amount").performTextReplacement("80")
        tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");await("investment.cash.reconciliation.error")
        val before=snapshot();val pending=queues();compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsEnabled()
        tap("investment.cash.reconciliation.confirm");compose.onNodeWithTag("investment.cash.reconciliation.confirm").assertIsOff().assertIsEnabled()
        compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsNotEnabled();tap("investment.cash.reconciliation.confirm")
        tap("investment.cash.reconciliation.save");saved(1)
        Assert.assertEquals(2,calls);Assert.assertEquals(requests.first(),requests.last());Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun lostSuccessfulAllResponseRetriesTheSameSixRowProofWithoutAnyNewEvent() {
        var calls=0;start(wrap={real->object:InvestmentRepository by real{override suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit>{calls++;val result=real.reconcileCash(owner,request,deviceId,now);return if(calls==1 && result.isSuccess)Result.failure(java.io.IOException("receipt lost")) else result}}})
        tap("investment.cash.reconcile.all");tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");await("investment.cash.reconciliation.error")
        val before=snapshot();val pending=queues();tap("investment.cash.reconciliation.save");saved(2)
        Assert.assertEquals(2,calls);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun failedSaveDraftAndExactEventIdentitySurviveSavedInstanceStateRestore() {
        val restoration=StateRestorationTester(compose);val requests=mutableListOf<InvestmentCashReconciliationRequest>();var calls=0
        start(restoration=restoration,wrap={real->object:InvestmentRepository by real{override suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit>{requests+=request;calls++;return if(calls==1)Result.failure(java.io.IOException("disk")) else real.reconcileCash(owner,request,deviceId,now)}}})
        tap("investment.cash.reconcile."+id(1));compose.onNodeWithTag("investment.cash.reconciliation.amount").performTextReplacement("80")
        tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");await("investment.cash.reconciliation.error");val before=snapshot();val pending=queues()
        restoration.emulateSavedInstanceStateRestore();await("investment.cash.reconciliation.sheet")
        compose.onNodeWithTag("investment.cash.reconciliation.amount").assertTextContains("80");compose.onNodeWithTag("investment.cash.reconciliation.confirm").assertIsOn()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues());tap("investment.cash.reconciliation.save");saved(1)
        Assert.assertEquals(requests.first(),requests.last())
    }
    @Test fun sourceBalanceChangeClearsConsentAndRequiresExplicitRefreshBeforeNewSave() {
        start();tap("investment.cash.reconcile."+id(1));tap("investment.cash.reconciliation.confirm")
        val wallet=snapshot().rows.single{it.id==id(1)}.let{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(149L))))}
        runBlocking{store.commitMutation(wallet,PendingMutation(CloudEntity.LEDGER_WALLET,wallet.id,owner.value,MutationKind.UPSERT,wallet.payload,now,wallet.syncVersion,device))}
        await("investment.cash.reconciliation.unavailable");compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsNotEnabled();compose.onNodeWithTag("investment.cash.reconciliation.confirm").assertIsOff()
        tap("investment.cash.reconciliation.refresh");compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsNotEnabled()
        tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");saved(1)
    }
    @Test fun zeroSingleAmountIsAnInvalidInputRatherThanAnOverflowMessage() {
        start();tap("investment.cash.reconcile."+id(1));compose.onNodeWithTag("investment.cash.reconciliation.amount").performTextReplacement("0")
        compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.cash.reconciliation.unavailable").assertTextEquals(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext.getString(R.string.investment_error_invalid_trade_input))
    }
    @Test fun sameOwnerRepositoryRebindingKeepsFrozenConsentAndStableEventIdentity() {
        val requests=mutableListOf<InvestmentCashReconciliationRequest>();start(wrap={real->object:InvestmentRepository by real{override suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit>{requests+=request;return Result.failure(java.io.IOException("disk"))}}})
        tap("investment.cash.reconcile."+id(1));compose.onNodeWithTag("investment.cash.reconciliation.amount").performTextReplacement("80");tap("investment.cash.reconciliation.confirm");tap("investment.cash.reconciliation.save");await("investment.cash.reconciliation.error")
        val real=OfflineFirstInvestmentRepository(store);compose.runOnIdle{repository=object:InvestmentRepository by real{override suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit>{requests+=request;return real.reconcileCash(owner,request,deviceId,now)}}}
        await("investment.cash.reconciliation.sheet");tap("investment.cash.reconciliation.save");saved(1);Assert.assertEquals(requests.first(),requests.last())
    }
    @Test fun actualAndroidBackCancelsConfirmedSingleDraftWithoutAnyFinancialChange() {
        start();val before=snapshot();val pending=queues();tap("investment.cash.reconcile."+id(1));tap("investment.cash.reconciliation.confirm")
        compose.waitForIdle()
        compose.waitUntil(5000){android.view.inspector.WindowInspector.getGlobalWindowViews().let{it.size>=2 && it.last().hasWindowFocus()}}
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Assert.assertTrue(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK))
        try{compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.reconciliation.sheet").fetchSemanticsNodes().isEmpty()}}
        catch(original:Throwable) {
            val tree=runCatching{compose.onNodeWithTag("investment.cash.reconciliation.sheet").printToString()}.getOrDefault("no sheet")
            val focus=android.view.inspector.WindowInspector.getGlobalWindowViews().map{it.hasWindowFocus()}
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            val hardwareClosed=runCatching{compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.reconciliation.sheet").fetchSemanticsNodes().isEmpty()}}.isSuccess
            throw AssertionError("Global accessibility Back left modal open; hardware Back closed=$hardwareClosed; windowFocus=$focus; $tree",original)
        }
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun failedInitialFinancialReadCanRetryTheRealOwnedSnapshotWithoutWriting() {
        var fail=true;start(wrap={real->object:InvestmentRepository by real {
            override fun observeCashSnapshot(owner:UserId)=kotlinx.coroutines.flow.flow {
                if(fail)throw java.io.IOException("disk")
                real.observeCashSnapshot(owner).collect{emit(it)}
            }
        }})
        await("investment.cash.retry");val before=snapshot();val pending=queues()
        compose.runOnIdle{fail=false};compose.onAllNodesWithTag("investment.cash.retry").onFirst().performClick()
        tap("investment.cash.reconcile.all");await("investment.cash.reconciliation.sheet");tap("investment.cash.reconciliation.cancel")
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun duplicateTouchAndNoncancellableOldOwnerCallbackCannotWriteOrLeakAfterOwnerReplacement() {
        val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>();var calls=0
        start(wrap={real->object:InvestmentRepository by real {
            override suspend fun reconcileCash(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit> = withContext(NonCancellable) {
                calls++;entered.complete(Unit)
                try{release.await();real.reconcileCash(owner,request,deviceId,now)}finally{finished.complete(Unit)}
            }
        }})
        val before=snapshot();val pending=queues()
        try {
            tap("investment.cash.reconcile."+id(1));compose.onNodeWithTag("investment.cash.reconciliation.amount").performTextReplacement("80");tap("investment.cash.reconciliation.confirm")
            compose.onNodeWithTag("investment.cash.reconciliation.save").performTouchInput{click();click()}
            compose.waitUntil(5000){entered.isCompleted};Assert.assertEquals(1,calls)
            compose.runOnIdle{activeOwner=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");displayedOwner=activeOwner}
            compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.reconciliation.sheet").fetchSemanticsNodes().isEmpty()}
            compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){finished.isCompleted};compose.waitForIdle()
            compose.onAllNodesWithTag("investment.cash.reconciliation.sheet").assertCountEquals(0)
            activeOwner=owner;Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
            Assert.assertTrue(runBlocking{InvestmentCashReadSnapshot.entities.all{store.recordsIncludingDeleted(UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),it.table).isEmpty()}})
        }finally{release.complete(Unit)}
    }
    @Test fun reconciliationFormsFitThreeLanguagesBothThemesAtActual130And320Dp() {
        language="en";start()
        runBlocking{store.commitMutations(snapshot().rows.filter{it.id in setOf(id(1),id(2),id(10))}.map{raw->raw.copy(payload=JsonObject(raw.payload+buildJsonObject {
            if(raw.id==id(1)){put("opening_balance_minor",Long.MAX_VALUE);put("name","Household savings / 共同ウォレット / Ví giao dịch chung")}
            if(raw.id==id(2))put("name","Linked savings / リンク先 / Ví liên kết")
            if(raw.id==id(10)){put("amount_minor",Long.MAX_VALUE);put("accounting_amount_minor",Long.MAX_VALUE)}
        }))}.map{row->row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)})}
        val before=snapshot();val pending=queues();val context=ApplicationProvider.getApplicationContext<Context>()
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String) {
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            }
            windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        fun complete(node:SemanticsNodeInteraction,editable:Boolean=false):androidx.compose.ui.text.TextLayoutResult {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val result=layouts.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true));Assert.assertFalse(result.didOverflowHeight)
            val width=if(editable)node.fetchSemanticsNode().boundsInRoot.width-32*context.resources.displayMetrics.density else result.size.width.toFloat()
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue("Clipped text: "+result.layoutInput.text,result.getLineRight(line)<=width+1f);Assert.assertTrue(result.getLineLeft(line)>=-1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{code->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
            return result
        }
        fun capture(kind:String) {
            val bitmap=compose.onNodeWithTag("investment.cash.reconciliation.sheet").captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-cash-reconciliation-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        }
        try {
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme}
                tap("investment.cash.reconcile."+id(1));compose.runOnIdle{configure(code)}
                compose.onNodeWithTag("investment.cash.reconciliation.amount").performScrollTo().assertTextContains("9,223,372,036,854,775,807")
                complete(compose.onNodeWithTag("investment.cash.reconciliation.amount"),true)
                val money=compose.onNodeWithTag("investment.cash.reconciliation.money."+id(1),useUnmergedTree=true)
                Assert.assertEquals(1,complete(money).lineCount)
                val sheet=compose.onNodeWithTag("investment.cash.reconciliation.sheet").fetchSemanticsNode().boundsInRoot
                Assert.assertEquals(320*context.resources.displayMetrics.density,sheet.width,1f)
                capture("single-top")
                compose.onNodeWithTag("investment.cash.reconciliation.confirm").performScrollTo().assertIsOff()
                val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
                complete(compose.onNodeWithText(localized.getString(R.string.investment_wallet_confirmed_real_transfer),useUnmergedTree=true))
                complete(compose.onNodeWithText(localized.getString(R.string.investment_wallet_confirmed_real_transfer_message),useUnmergedTree=true))
                tap("investment.cash.reconciliation.confirm")
                val save=compose.onNodeWithTag("investment.cash.reconciliation.save");val cancel=compose.onNodeWithTag("investment.cash.reconciliation.cancel")
                save.assertIsDisplayed().assertIsEnabled();cancel.assertIsDisplayed();complete(save);complete(cancel)
                Assert.assertTrue(save.fetchSemanticsNode().boundsInRoot.left>=cancel.fetchSemanticsNode().boundsInRoot.right)
                for(tag in listOf("investment.cash.reconciliation.save","investment.cash.reconciliation.cancel","investment.cash.reconciliation.confirm"))
                    Assert.assertTrue("Hit target: $tag",compose.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot.height>=48*context.resources.displayMetrics.density-1f)
                capture("single-bottom");tap("investment.cash.reconciliation.cancel")
                tap("investment.cash.reconcile.all");compose.runOnIdle{configure(code)}
                compose.onNodeWithTag("investment.cash.reconciliation.instruction."+id(1)).assertExists();compose.onNodeWithTag("investment.cash.reconciliation.instruction."+id(3)).assertExists()
                complete(compose.onNodeWithTag("investment.cash.reconciliation.money."+id(1),useUnmergedTree=true))
                tap("investment.cash.reconciliation.confirm");compose.onNodeWithTag("investment.cash.reconciliation.save").assertIsDisplayed().assertIsEnabled()
                capture("all");tap("investment.cash.reconciliation.cancel")
                Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
            }
        }finally{compose.runOnIdle{originals.forEach{(resource,configuration)->resource.updateConfiguration(configuration,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}}}
    }
}
