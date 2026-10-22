package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
class InvestmentLinkedWalletScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description ->
        object:org.junit.runners.model.Statement(){override fun evaluate(){
            if(description.methodName!="linkedWalletSelectorAndChoicesFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
            val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use{it.readText().trim()}
            val originalFont=shell("settings get system font_scale").takeUnless{it=="null"} ?: "1.0"
            val originalSize=Regex("Override size: ([0-9]+x[0-9]+)").find(shell("wm size"))?.groupValues?.get(1)
            val metrics=instrumentation.targetContext.resources.displayMetrics
            try {
                shell("wm size "+kotlin.math.round(320*metrics.density).toInt()+"x"+metrics.heightPixels);shell("settings put system font_scale 1.3")
                val end=android.os.SystemClock.uptimeMillis()+5000
                while(instrumentation.targetContext.resources.configuration.fontScale!=1.3f && android.os.SystemClock.uptimeMillis()<end)android.os.SystemClock.sleep(20)
                Assert.assertEquals(1.3f,instrumentation.targetContext.resources.configuration.fontScale,0.0001f)
                base.evaluate()
            }finally {
                shell("settings put system font_scale "+originalFont);shell(if(originalSize==null)"wm size reset" else "wm size "+originalSize)
            }
        }}
    }).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-4444-444444444444"
    private val previous="55555555-5555-5555-5555-555555555555"
    private val target="66666666-6666-6666-6666-666666666666"
    private val cashId="88888888-8888-8888-8888-888888888888"
    private val now="2026-10-22T00:00:00Z"
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstInvestmentRepository(store)
    }
    private fun wallet(id:String,name:String="Wallet",code:String="VND")=WalletDraft(id=id,name=name,kind=WalletKind.CASH,currencyCode=code,openingBalanceMinor=10000).toMutation(owner,null,device,now).record
    private fun system(first:Boolean=false)=wallet(investmentSystemWalletId(owner)).let{it.copy(payload=JsonObject(it.payload+buildJsonObject {
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("opening_balance_minor",0L)
        put("investment_linked_wallet_id",if(first)JsonNull else JsonPrimitive(previous))
    }))}
    private fun seed(vararg rows:CloudRecord)=runBlocking {rows.groupBy{it.ownerUserId}.values.forEach{batch ->store.commitMutations(batch.map{it to PendingMutation(CloudEntity.fromTable(it.entity)!!,it.id,it.ownerUserId,MutationKind.UPSERT,it.payload,now,it.syncVersion,device)})}}
    private fun prepare(first:Boolean=false) {
        seed(system(first),wallet(previous,"Old wallet"),wallet(target,"Target wallet"),CloudRecord(CloudEntity.INVESTMENT_POSTING.table,cashId,owner.value,buildJsonObject {
            put("id",cashId);put("user_id",owner.value);put("wallet_id",previous);put("role_raw_value","cashAccrual")
            put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",300L);put("currency_code","VND")
            put("accounting_amount_minor",300L);put("accounting_currency_code","VND");put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
        },now,null,0))
    }
    @Composable private fun Screen(subject:UserId=owner,source:InvestmentRepository=repo,dark:Boolean=false){MistiaTheme(darkTheme=dark){Scaffold{padding ->InvestmentScreen(subject,source,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("JPY","VND"))}}}
    private fun rows()=runBlocking{store.investmentWalletSnapshot(owner)}
    private fun queues()=runBlocking{InvestmentWalletSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}}
    private fun await(tag:String){compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
    private fun choose(){await("investment.wallet.link.choose");compose.onNodeWithTag("investment.wallet.link.choose").performScrollTo().performClick();await("investment.wallet.link.option."+target)}
    private fun select(){compose.onNodeWithTag("investment.wallet.link.option."+target).performScrollTo().performClick()}
    private fun linked(){compose.waitUntil(5000){rows().rows.single{it.id==investmentSystemWalletId(owner)}.payload.financeRawString("investment_linked_wallet_id")==target}}
    @Test fun actualFirstLinkChoicePersistsOnlyTheCanonicalPreference() {
        prepare(true);val beforeWallets=rows().rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table && it.id!=investmentSystemWalletId(owner)}
        compose.setContent{Screen()};choose();select();linked()
        Assert.assertEquals(beforeWallets,rows().rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table && it.id!=investmentSystemWalletId(owner)})
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table});Assert.assertEquals(4,queues().values.sumOf{it.size})
        await("investment.wallet.linked.name");compose.onNodeWithTag("investment.wallet.linked.name").assertTextEquals("Target wallet")
    }
    @Test fun changingOnlyTheDefaultLeavesBookedCashAndEveryFinancialRowUnchanged() {
        prepare();val cash=rows().rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        compose.setContent{Screen()};choose();select();await("investment.wallet.link.onlyDefault")
        compose.onNodeWithTag("investment.wallet.link.onlyDefault").performClick();linked()
        Assert.assertEquals(cash,rows().rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table})
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table});Assert.assertEquals(4,queues().values.sumOf{it.size})
    }
    @Test fun changeAndMoveAllExecutesTheActualRoomTransferWithTwoSignedPostings() {
        prepare();val wallets=rows().rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associate{it.id to it.payload.financeRawLong("opening_balance_minor")}
        compose.setContent{Screen()};choose();select();await("investment.wallet.link.moveAll")
        compose.onNodeWithTag("investment.wallet.link.moveAll").performClick();linked()
        val actual=rows().rows
        Assert.assertEquals(wallets,actual.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associate{it.id to it.payload.financeRawLong("opening_balance_minor")})
        Assert.assertEquals(300L,actual.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
        val postings=actual.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        Assert.assertEquals(0L,postings.filter{it.payload.financeRawString("wallet_id")==previous}.sumOf{it.payload.financeRawLong("amount_minor")!!})
        Assert.assertEquals(300L,postings.single{it.payload.financeRawString("wallet_id")==target}.payload.financeRawLong("amount_minor"))
        Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun cancelOfTheChangeChoicesDoesNotChangeSourceRowsOrQueues() {
        prepare();val before=rows();val pending=queues();compose.setContent{Screen()};choose();select();await("investment.wallet.link.cancel")
        compose.onNodeWithTag("investment.wallet.link.cancel").performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.wallet.link.moveAll").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun walletOptionsExcludeCreditArchivedForeignCurrencyAndForeignOwnerRows() {
        prepare(true)
        val jpy=wallet("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","Wrong currency","JPY")
        val credit=wallet("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","Credit").let{it.copy(payload=JsonObject(it.payload+("kind_raw_value" to JsonPrimitive("creditCard"))))}
        val archived=wallet("cccccccc-cccc-cccc-cccc-cccccccccccc","Archived").let{it.copy(payload=JsonObject(it.payload+("is_archived" to JsonPrimitive(true))))}
        val foreign=wallet("dddddddd-dddd-dddd-dddd-dddddddddddd","Foreign").let{it.copy(ownerUserId="eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",payload=JsonObject(it.payload+("user_id" to JsonPrimitive("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"))))}
        seed(jpy,credit,archived,foreign);val before=rows();val pending=queues();compose.setContent{Screen()};choose()
        for(raw in listOf(jpy,credit,archived,foreign))compose.onNodeWithTag("investment.wallet.link.option."+raw.id).assertDoesNotExist()
        compose.onNodeWithTag("investment.wallet.link.option."+previous).assertExists()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun failedReadKeepsTheConfirmedTargetAndDisablesBothChoicesUntilRetry() {
        prepare();val initial=rows();var starts=0;val fail=MutableStateFlow(false)
        val source=object:InvestmentRepository by repo {
            override fun observeWalletSnapshot(owner:UserId):Flow<InvestmentWalletSnapshot> = flow {
                if(starts++==0){emit(initial);fail.first{it};throw IllegalStateException("read failed")}
                emitAll(repo.observeWalletSnapshot(owner))
            }
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source=source)};choose();select();await("investment.wallet.link.moveAll")
        compose.runOnIdle{fail.value=true}
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.wallet.link.retry").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.wallet.link.onlyDefault").assertIsNotEnabled();compose.onNodeWithTag("investment.wallet.link.moveAll").assertIsNotEnabled()
        compose.onNodeWithTag("investment.wallet.link.target").assertTextEquals("Target wallet")
        compose.onAllNodesWithTag("investment.wallet.link.retry").onLast().performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.wallet.link.moveAll") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun failedSaveAndSavedStateRestoreKeepTheSameTargetAmountAndEventForRetry() {
        prepare();val calls=mutableListOf<InvestmentWalletLinkRequest>();val restorer=StateRestorationTester(compose)
        val source=object:InvestmentRepository by repo {
            override suspend fun changeLinkedWallet(owner:UserId,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Result<Unit> {
                calls.add(request);if(calls.size==1)return Result.failure(IllegalStateException("disk failed"))
                return repo.changeLinkedWallet(owner,request,deviceId,now)
            }
        }
        val before=rows();val pending=queues();restorer.setContent{Screen(source=source)};choose();select();await("investment.wallet.link.moveAll")
        compose.onNodeWithTag("investment.wallet.link.moveAll").performClick();await("investment.wallet.link.error")
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues());Assert.assertEquals(1,calls.size)
        restorer.emulateSavedInstanceStateRestore();await("investment.wallet.link.moveAll")
        compose.onNodeWithTag("investment.wallet.link.target").assertTextEquals("Target wallet")
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.wallet.link.moveAll") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.wallet.link.moveAll").performClick();linked()
        Assert.assertEquals(2,calls.size);Assert.assertEquals(calls.first().eventId,calls.last().eventId)
        Assert.assertEquals(300L,calls.last().expectedBookedMinor);Assert.assertEquals(target,calls.last().expectedTarget.id)
        Assert.assertEquals(1,rows().rows.count{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
    }
    @Test fun newerCashAndTargetChangesCannotSilentlyReplaceTheFrozenConfirmation() {
        prepare();compose.setContent{Screen()};choose();select();await("investment.wallet.link.moveAll")
        val amount=compose.onNodeWithTag("investment.wallet.link.amount").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].single().text
        val cash=rows().rows.single{it.id==cashId};seed(cash.copy(payload=JsonObject(cash.payload+buildJsonObject{put("amount_minor",301L);put("accounting_amount_minor",301L)})))
        await("investment.wallet.link.conflict")
        compose.onNodeWithTag("investment.wallet.link.amount").assertTextEquals(amount)
        compose.onNodeWithTag("investment.wallet.link.moveAll").assertIsNotEnabled();compose.onNodeWithTag("investment.wallet.link.onlyDefault").assertIsEnabled()
        seed(wallet(target,"Changed target","JPY"))
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.wallet.link.onlyDefault") and isNotEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.wallet.link.target").assertTextEquals("Target wallet")
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
    }
    @Test fun oldNonCancellableSuccessCannotDismissAnotherOwnersSelectorOrAcceptDuplicateActions() {
        prepare();val other=UserId("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
        val otherSystem=system(true).let{raw ->raw.copy(id=investmentSystemWalletId(other),ownerUserId=other.value,payload=JsonObject(raw.payload+buildJsonObject{put("id",investmentSystemWalletId(other));put("user_id",other.value)}))}
        val otherWallet=wallet("dddddddd-dddd-dddd-dddd-dddddddddddd","Other private wallet").let{it.copy(ownerUserId=other.value,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))}
        seed(otherSystem,otherWallet)
        var subject by mutableStateOf(owner);val release=CompletableDeferred<Unit>();var calls=0;var completed=false
        val source=object:InvestmentRepository by repo {
            override suspend fun changeLinkedWallet(owner:UserId,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Result<Unit> = withContext(NonCancellable) {
                calls++;release.await();completed=true;Result.success(Unit)
            }
        }
        compose.setContent{Screen(subject,source)};choose();select();await("investment.wallet.link.moveAll")
        compose.onNodeWithTag("investment.wallet.link.moveAll").performClick();await("investment.wallet.link.saving")
        compose.onNodeWithTag("investment.wallet.link.moveAll").assertIsNotEnabled();compose.onNodeWithTag("investment.wallet.link.onlyDefault").assertIsNotEnabled()
        compose.onNodeWithTag("investment.wallet.link.cancel").assertIsNotEnabled();Assert.assertEquals(1,calls)
        compose.runOnIdle{subject=other}
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.wallet.link.confirmation").fetchSemanticsNodes().isEmpty()}
        compose.onAllNodesWithText("Target wallet").assertCountEquals(0)
        compose.onNodeWithTag("investment.wallet.link.choose").performScrollTo().performClick();await("investment.wallet.link.option."+otherWallet.id)
        compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){completed};compose.waitForIdle()
        compose.onNodeWithTag("investment.wallet.link.picker").assertExists();compose.onNodeWithTag("investment.wallet.link.option."+otherWallet.id).assertExists()
        Assert.assertEquals(1,calls);Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
    }

    @Test fun linkedWalletSelectorAndChoicesFitThreeLanguagesBothThemesAtActual130And320Dp() {
        prepare();val context=ApplicationProvider.getApplicationContext<Context>();val before=rows();val pending=queues()
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config){Screen(dark=dark)}
        }
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String) {
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource ->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            }
            windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        fun complete(node:SemanticsNodeInteraction) {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true));Assert.assertFalse(layout.didOverflowHeight)
            for(line in 0 until layout.lineCount) {
                Assert.assertFalse(layout.isLineEllipsized(line));Assert.assertTrue(layout.getLineRight(line)<=layout.size.width+1f);Assert.assertTrue(layout.getLineLeft(line)>=-1f)
            }
        }
        fun capture(kind:String,node:SemanticsNodeInteraction) {
            val bitmap=node.captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-linked-wallet-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use {
                Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))
            }
        }
        try {
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme}
                val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
                await("investment.wallet.link.choose");compose.onNodeWithTag("investment.wallet.link.card").performScrollTo().assertIsDisplayed()
                complete(compose.onNodeWithText(localized.getString(R.string.investment_wallet_linked_wallet),useUnmergedTree=true))
                complete(compose.onNodeWithText(localized.getString(R.string.investment_wallet_change),useUnmergedTree=true))
                Assert.assertEquals(288*context.resources.displayMetrics.density,compose.onNodeWithTag("investment.wallet.link.card").fetchSemanticsNode().boundsInRoot.width,1f)
                capture("card",compose.onNodeWithTag("investment.wallet.link.card"))
                choose();compose.runOnIdle{configure(code)}
                val title=compose.onNodeWithText(localized.getString(R.string.investment_wallet_choose_linked_wallet),useUnmergedTree=true)
                title.performScrollTo().assertIsDisplayed();complete(title)
                complete(compose.onNodeWithText("Target wallet",useUnmergedTree=true))
                capture("picker",compose.onNodeWithTag("investment.wallet.link.picker"))
                select();await("investment.wallet.link.moveAll");compose.runOnIdle{configure(code)}
                for(resource in listOf(R.string.investment_wallet_change_choice_title,R.string.investment_wallet_change_choice_message,R.string.investment_wallet_only_change_default,R.string.investment_wallet_change_and_transfer_all)) {
                    val node=compose.onNodeWithText(localized.getString(resource),useUnmergedTree=true);node.assertIsDisplayed();complete(node)
                }
                complete(compose.onNodeWithTag("investment.wallet.link.target"));complete(compose.onNodeWithTag("investment.wallet.link.amount"))
                val actionTags=listOf("investment.wallet.link.onlyDefault","investment.wallet.link.moveAll","investment.wallet.link.cancel")
                val actionBounds=actionTags.map{compose.onNodeWithTag(it).fetchSemanticsNode().boundsInRoot}
                for(index in 0 until actionBounds.lastIndex)Assert.assertTrue("Overlapping actions "+actionTags[index]+" and "+actionTags[index+1],actionBounds[index].bottom<=actionBounds[index+1].top+1f)
                compose.onNodeWithTag("investment.wallet.link.moveAll").assertIsEnabled();capture("choices",compose.onNode(isDialog()))
                compose.onNodeWithTag("investment.wallet.link.cancel").performClick()
                Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
            }
        }finally {compose.runOnIdle{
            originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }}
    }

}
