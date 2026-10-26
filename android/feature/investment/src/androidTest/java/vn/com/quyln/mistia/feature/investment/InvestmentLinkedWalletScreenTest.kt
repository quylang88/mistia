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
            if(description.methodName !in setOf("linkedWalletSelectorAndChoicesFitThreeLanguagesBothThemesAtActual130And320Dp","cashReadCardsFitThreeLanguagesBothThemesAtActual130And320Dp")){base.evaluate();return}
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
    @Test fun actualPickerExcludesEveryReservedPurposeAndKeepsOrdinaryChoices() {
        prepare(true)
        val reserved="99999999-9999-9999-9999-999999999999"
        val raw=wallet(reserved,"Reserved").let{it.copy(payload=JsonObject(it.payload+("system_purpose_raw_value" to JsonPrimitive("futureReserved"))))}
        seed(raw);val before=rows();val pending=queues()
        compose.setContent{Screen()};choose()
        compose.onNodeWithTag("investment.wallet.link.option."+target).assertExists()
        compose.onNodeWithTag("investment.wallet.link.option."+reserved).assertDoesNotExist()
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun changingOnlyTheDefaultLeavesBookedCashAndEveryFinancialRowUnchanged() {
        prepare();val cash=rows().rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        compose.setContent{Screen()};choose();select();await("investment.wallet.link.onlyDefault")
        compose.onNodeWithTag("investment.wallet.link.onlyDefault").performClick();linked()
        Assert.assertEquals(cash,rows().rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table})
        Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table});Assert.assertEquals(4,queues().values.sumOf{it.size})
    }
    @Test fun frozenLinkChoiceSurvivesServerReadonlyRootMetadataAcknowledgement() {
        prepare();val observed=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeCashSnapshot(owner:UserId)=repo.observeCashSnapshot(owner).onEach{snapshot->
                if(snapshot.rows.any{it.id==investmentSystemWalletId(owner) && it.syncVersion==5L})observed.complete(Unit)
            }
        }
        compose.setContent{Screen(source=source)};choose();select();await("investment.wallet.link.onlyDefault")
        runBlocking {
            for(id in listOf(previous,target)) {
                val raw=store.record(owner,CloudEntity.LEDGER_WALLET.table,id)!!
                val q=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==id}
                Assert.assertTrue(store.acknowledgeMutation(q,raw.copy(syncVersion=1,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(1))))))
            }
            val state=store.investmentWalletPublicationSnapshot(owner);val raw=state.record!!
            val remote=raw.copy(syncVersion=5,updatedAt="2026-10-26T00:30:00Z",payload=JsonObject(raw.payload+buildJsonObject {
                put("name","Investment Wallet");put("icon_symbol_name","chart.line.uptrend.xyaxis");put("icon_color_hex","#9A67FF")
                put("sort_order",2147483547);put("updated_at","2026-10-26T00:30:00Z");put("sync_version",5)
            }))
            Assert.assertTrue(store.acknowledgeInvestmentWalletMutation(state.pending!!,remote,state))
        }
        compose.waitUntil(5000){observed.isCompleted};compose.waitForIdle()
        val financial=rows().rows.filter{it.entity!=CloudEntity.LEDGER_WALLET.table}
        compose.onNodeWithTag("investment.wallet.link.onlyDefault").assertIsEnabled()
            .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){Assert.assertTrue(it())}
        linked();Assert.assertEquals(financial,rows().rows.filter{it.entity!=CloudEntity.LEDGER_WALLET.table})
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
        prepare();val initial=runBlocking{store.investmentCashSnapshot(owner)};var starts=0;val fail=MutableStateFlow(false)
        val source=object:InvestmentRepository by repo {
            override fun observeCashSnapshot(owner:UserId):Flow<InvestmentCashReadSnapshot> = flow {
                if(starts++==0){emit(initial);fail.first{it};throw IllegalStateException("read failed")}
                emitAll(repo.observeCashSnapshot(owner))
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

    private fun profit(value:JsonElement=JsonPrimitive(800L)):CloudRecord {
        val id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        return CloudRecord(CloudEntity.INVESTMENT_TRADE.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("realized_profit_loss_minor",value);put("accounting_currency_code","VND")
        },now,null,0)
    }
    private fun showCash(tag:String) {
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag(tag))
        await(tag)
    }
    @Test fun financialSummaryShowsPersistedProfitShortfallAndActualCashWithoutDoubleCounting() {
        prepare();seed(profit());val before=runBlocking{store.investmentCashSnapshot(owner)};val pending=queues()
        compose.setContent{Screen()};await("investment.cash.profit")
        compose.onNodeWithTag("investment.cash.profit").assertTextEquals("+"+vn.com.quyln.mistia.core.designsystem.formatMinorUnits(800,"VND"))
        compose.onNodeWithTag("investment.cash.available").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(300,"VND"))
        compose.onNodeWithTag("investment.cash.shortfall").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(500,"VND"))
        showCash("investment.wallet.link.actual")
        val context=ApplicationProvider.getApplicationContext<Context>()
        compose.onNodeWithTag("investment.wallet.link.actual").assertTextEquals(context.getString(R.string.investment_wallet_actual_balance,vn.com.quyln.mistia.core.designsystem.formatMinorUnits(10000,"VND")))
        compose.onNodeWithTag("investment.wallet.link.portion").assertTextEquals(context.getString(R.string.investment_wallet_investment_portion,vn.com.quyln.mistia.core.designsystem.formatMinorUnits(300,"VND")))
        Assert.assertEquals(before,runBlocking{store.investmentCashSnapshot(owner)});Assert.assertEquals(pending,queues())
    }
    @Test fun unreadableProfitDoesNotEraseCashAndUnreadableCashNeverBecomesEmpty() {
        prepare();seed(profit(JsonPrimitive("broken")));compose.setContent{Screen()};await("investment.cash.profit")
        compose.onNodeWithTag("investment.cash.profit").assertTextEquals("—")
        compose.onNodeWithTag("investment.cash.available").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(300,"VND"))
        val posting=rows().rows.single{it.id==cashId};seed(posting.copy(payload=JsonObject(posting.payload+("amount_minor" to JsonNull))))
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.available") and hasText("—")).fetchSemanticsNodes().isNotEmpty()}
        showCash("investment.cash.locations.unavailable");compose.onNodeWithTag("investment.cash.locations.empty").assertDoesNotExist()
        showCash("investment.wallet.link.actual");compose.onNodeWithTag("investment.wallet.link.portion").assertTextEquals("—")
    }
    @Test fun orphanCashKeepsAccountingAndOriginalCurrencyReferencesWithoutForeignWalletNames() {
        prepare();val id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";val orphan="cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        val template=rows().rows.single{it.id==cashId}
        seed(template.copy(id=id,payload=JsonObject(template.payload+buildJsonObject {
            put("id",id);put("wallet_id",orphan);put("currency_code","JPY");put("amount_minor",50L);put("accounting_amount_minor",12500L)
        })))
        val before=runBlocking{store.investmentCashSnapshot(owner)};compose.setContent{Screen()};await("investment.cash.available")
        compose.onNodeWithTag("investment.cash.available").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(12800,"VND"))
        showCash("investment.cash.location."+orphan)
        val context=ApplicationProvider.getApplicationContext<Context>()
        compose.onNodeWithTag("investment.cash.location.name."+orphan).assertTextEquals(context.getString(R.string.investment_wallet_unidentified))
        compose.onNodeWithTag("investment.cash.location.amount."+orphan).assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(12500,"VND"))
        compose.onNodeWithTag("investment.cash.location.original."+orphan).assertTextEquals(context.getString(R.string.investment_wallet_original_amount_reference,vn.com.quyln.mistia.core.designsystem.formatMinorUnits(50,"JPY")))
        Assert.assertEquals(before,runBlocking{store.investmentCashSnapshot(owner)})
    }

    @Test fun cashReadFailureRetryEmptyAndLateOwnerEmissionNeverShowStaleFinancialAmounts() {
        prepare();seed(profit());val initial=runBlocking{store.investmentCashSnapshot(owner)}
        val other=UserId("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");val release=CompletableDeferred<Unit>();var oldCompleted=false;var starts=0
        var subject by mutableStateOf(owner)
        val source=object:InvestmentRepository by repo {
            override fun observeCashSnapshot(owner:UserId):Flow<InvestmentCashReadSnapshot> = flow {
                if(owner==this@InvestmentLinkedWalletScreenTest.owner) {
                    if(starts++==0)throw IllegalStateException("disk failed")
                    emit(initial)
                    withContext(NonCancellable){release.await();oldCompleted=true;emit(initial)}
                }else emit(InvestmentCashReadSnapshot(owner,emptyList()))
            }
        }
        val pending=queues();compose.setContent{Screen(subject,source)};await("investment.cash.retry")
        compose.onNodeWithTag("investment.cash.profit").assertTextEquals("—");compose.onAllNodesWithTag("investment.cash.retry").onFirst().performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.profit") and hasText("+"+vn.com.quyln.mistia.core.designsystem.formatMinorUnits(800,"VND"))).fetchSemanticsNodes().isNotEmpty()}
        compose.runOnIdle{subject=other;release.complete(Unit)};compose.waitUntil(5000){oldCompleted}
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.profit") and hasText(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(0,"VND"))).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.cash.available").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(0,"VND"))
        showCash("investment.cash.locations.empty");Assert.assertEquals(pending,queues())
    }
    @Test fun cashReadCardsFitThreeLanguagesBothThemesAtActual130And320Dp() {
        prepare()
        val first=profit(JsonPrimitive(Long.MAX_VALUE));val second=first.copy(id="dddddddd-dddd-4ddd-8ddd-dddddddddddd").let{it.copy(payload=JsonObject(it.payload+("id" to JsonPrimitive(it.id))))}
        val template=rows().rows.single{it.id==cashId};val orphan="cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        seed(first,second,template.copy(id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",payload=JsonObject(template.payload+buildJsonObject {
            put("id","bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");put("wallet_id",orphan);put("currency_code","JPY");put("amount_minor",Long.MAX_VALUE);put("accounting_amount_minor",Long.MAX_VALUE)
        })))
        val context=ApplicationProvider.getApplicationContext<Context>();val before=runBlocking{store.investmentCashSnapshot(owner)};val pending=queues()
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config){Screen(dark=dark)}
        }
        fun complete(tag:String) {
            val node=compose.onNodeWithTag(tag);val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true));Assert.assertFalse(layout.didOverflowHeight)
            for(line in 0 until layout.lineCount){Assert.assertFalse(layout.isLineEllipsized(line));Assert.assertTrue(layout.getLineRight(line)<=layout.size.width+1f);Assert.assertTrue(layout.getLineLeft(line)>=-1f)}
            val paint=android.graphics.Paint();layout.layoutInput.text.text.codePoints().forEach{code ->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
        }
        fun capture(kind:String,tag:String) {
            showCash(tag);compose.onNodeWithTag(tag).assertIsDisplayed()
            val bitmap=compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-cash-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        }
        for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
            compose.runOnIdle{language=code;dark=theme}
            showCash("investment.cash.summary")
            for(tag in listOf("investment.cash.profit","investment.cash.available","investment.cash.shortfall"))complete(tag)
            for(tag in listOf("investment.cash.profit","investment.cash.available","investment.cash.shortfall")) {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag(tag).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
                Assert.assertEquals("Money digits must stay together: "+tag,1,layouts.single().lineCount)
            }
            val profitLayouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag("investment.cash.profit").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(profitLayouts)}
            Assert.assertEquals(androidx.compose.ui.graphics.Color(if(theme)0xFF30D158 else 0xFF34C759),profitLayouts.single().layoutInput.style.color)

            val summary=compose.onNodeWithTag("investment.cash.summary").fetchSemanticsNode().boundsInRoot
            Assert.assertEquals(288*context.resources.displayMetrics.density,summary.width,1f)
            capture("summary","investment.cash.summary")
            showCash("investment.wallet.link.card");complete("investment.wallet.link.actual");complete("investment.wallet.link.portion");capture("linked","investment.wallet.link.card")
            showCash("investment.cash.location."+orphan)
            complete("investment.cash.location.amount."+orphan);complete("investment.cash.location.original."+orphan)
            capture("location","investment.cash.location."+orphan)
            Assert.assertEquals(before,runBlocking{store.investmentCashSnapshot(owner)});Assert.assertEquals(pending,queues())
        }
    }

    @Test fun unusedOtherWalletDamageKeepsActualCashVisibleWhileSelectorIsUnavailable() {
        prepare();val other=wallet("ffffffff-ffff-4fff-8fff-ffffffffffff").let{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive("broken"))))}
        seed(other);val before=runBlocking{store.investmentCashSnapshot(owner)};compose.setContent{Screen()};await("investment.cash.available")
        showCash("investment.wallet.link.actual")
        val context=ApplicationProvider.getApplicationContext<Context>()
        compose.onNodeWithTag("investment.wallet.link.actual").assertTextEquals(context.getString(R.string.investment_wallet_actual_balance,vn.com.quyln.mistia.core.designsystem.formatMinorUnits(10000,"VND")))
        compose.onNodeWithTag("investment.wallet.link.choose").assertIsNotEnabled()
        Assert.assertEquals(before,runBlocking{store.investmentCashSnapshot(owner)})
    }

    @Test fun firstLinkWithALostSuccessReceiptCanRetryTheFrozenChoiceWithoutAnotherWrite() {
        prepare(first=true);var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun changeLinkedWallet(owner:UserId,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Result<Unit> {
                calls++;val result=repo.changeLinkedWallet(owner,request,deviceId,now)
                return if(calls==1 && result.isSuccess)Result.failure(IllegalStateException("receipt lost")) else result
            }
        }
        compose.setContent{Screen(source=source)};choose();select();await("investment.wallet.link.error")
        linked();compose.onNodeWithTag("investment.wallet.link.retrySave").assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.wallet.link.picker").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(2,calls);Assert.assertEquals(4,queues().values.sumOf{it.size});Assert.assertTrue(rows().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
    }

}
