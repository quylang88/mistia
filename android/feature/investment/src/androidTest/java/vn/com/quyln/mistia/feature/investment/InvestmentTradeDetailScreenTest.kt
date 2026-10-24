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
class InvestmentTradeDetailScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="detailDeleteAndFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
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
    @Test fun actualActivityDetailShowsFifoMoneyAndDeleteCancelThenConfirmRestoresStock() {
        seedSale();compose.setContent{Screen()}
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.trade."+saleId));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.trade."+saleId).performClick();await("investment.trade.detail.sheet")
        compose.onNodeWithTag("investment.trade.detail.channel").assertTextEquals("Shop")
        compose.onNodeWithTag("investment.trade.detail.quantity").assertTextContains("1 box",substring=true)
        compose.onNodeWithTag("investment.trade.detail.basis").performScrollTo().assertTextContains("28",substring=true)
        compose.onNodeWithTag("investment.trade.detail.profit").performScrollTo().assertTextContains("22",substring=true)
        val before=rows();val pending=queues()
        compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo().performClick();await("investment.trade.detail.delete.review")
        compose.onNodeWithTag("investment.trade.detail.delete.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo().performClick();await("investment.trade.detail.delete.review")
        compose.onNodeWithTag("investment.trade.detail.delete.confirm").performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.trade.detail.sheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertNotNull(rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}.deletedAt)
        compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.asset.stock."+assetId));compose.onNodeWithTag("investment.asset.stock."+assetId).assertTextContains("2.5",substring=true)
    }
    private fun tapTrade(id:String=saleId){
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.trade."+id));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.trade."+id).performClick()
    }
    private fun openTrade(id:String=saleId){tapTrade(id);await("investment.trade.detail.quantity")}
    @Test fun purchaseDetailShowsItsAcquisitionCostRatherThanZeroReleasedCost() {
        compose.setContent{Screen()};openTrade("55555555-5555-5555-5555-555555555555")
        compose.onNodeWithTag("investment.trade.detail.basis").performScrollTo().assertTextContains("70",substring=true)
    }
    @Test fun committedLostResponseCanRetryAfterANewOpaqueMetadataFieldWithoutAnyMoreWrites() {
        seedSale();var calls=0
        val lost=object:InvestmentRepository by repo {
            override suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Result<CloudRecord> {
                calls++;val result=repo.deleteTrade(owner,request,deviceId,now)
                if(calls==1 && result.isSuccess) {
                    val old=store.record(owner,CloudEntity.INVESTMENT_TRADE.table,request.expectedTrade.id)!!
                    val raw=old.copy(payload=JsonObject(old.payload+("future_flag" to JsonPrimitive("keep"))))
                    store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_TRADE,raw.id,owner.value,MutationKind.DELETE,raw.payload,requireNotNull(raw.updatedAt),raw.syncVersion,deviceId))
                    return Result.failure(java.io.IOException("Committed response lost"))
                }
                return result
            }
        }
        compose.setContent{Screen(source=lost)};openTrade()
        compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo().performClick();await("investment.trade.detail.delete.review")
        compose.onNodeWithTag("investment.trade.detail.delete.confirm").performClick();await("investment.trade.detail.error")
        val before=rows();val pending=queues()
        compose.onNodeWithTag("investment.trade.detail.retry").performScrollTo().assertIsDisplayed().assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.trade.detail.sheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(2,calls);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        Assert.assertEquals(JsonPrimitive("keep"),rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}.payload["future_flag"])
    }

    private val expenseId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private fun futureExpense(amount:Long=80)=runBlocking {
        val row=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,expenseId,owner.value,buildJsonObject {
            put("id",expenseId);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("occurred_at","2026-10-24T00:00:00Z");put("deleted_at",JsonNull);put("sync_version",0L)
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Later expense");put("amount_minor",amount);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull);put("is_archived",false)
            put("reporting_amount_minor",amount);put("reporting_currency_code","VND");put("reporting_expense_minor",amount);put("reporting_income_minor",0L)
        },now,null,0)
        store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_TRANSACTION,row.id,owner.value,MutationKind.UPSERT,row.payload,now,0,device))
    }
    private fun deleteFromDetail(){compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo().performClick();await("investment.trade.detail.delete.review");compose.onNodeWithTag("investment.trade.detail.delete.confirm").performClick()}
    @Test fun cashHistoryTradeOpensDetailAndClosingItKeepsTheSelectedHistoryFilter() {
        seedSale();val before=rows();val pending=queues();compose.setContent{Screen()}
        compose.waitUntil(5000){runCatching{compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.cash.history.seeAll"));true}.getOrDefault(false)}
        compose.onNodeWithTag("investment.cash.history.seeAll").performClick();await("investment.cash.history.screen")
        compose.onNodeWithTag("investment.cash.history.filter.INCOMING").performClick()
        compose.onNodeWithTag("investment.cash.history.list").performScrollToNode(hasTestTag("investment.cash.history.item."+saleId))
        compose.onNodeWithTag("investment.cash.history.item."+saleId).performClick();await("investment.trade.detail.quantity")
        compose.onNodeWithTag("investment.trade.detail.quantity").assertTextContains("1 box",substring=true)
        compose.onNodeWithTag("investment.trade.detail.close").performClick();await("investment.cash.history.screen")
        compose.onNodeWithTag("investment.cash.history.filter.INCOMING").assertIsSelected();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aPurchaseStillNeededByItsSaleShowsTheStockErrorAndDeletesNothing() {
        seedSale();val before=rows();val pending=queues();compose.setContent{Screen()};openTrade("55555555-5555-5555-5555-555555555555")
        deleteFromDetail();await("investment.trade.detail.error")
        compose.onNodeWithTag("investment.trade.detail.error").performScrollTo().assertTextEquals(ApplicationProvider.getApplicationContext<Context>().getString(R.string.investment_error_insufficient_position))
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun deletingHistoricalFundUsageCanCancelAndRestoreButNeedsAFreshExplicitReview() {
        futureExpense();seedSale();val before=rows();val pending=queues();val context=ApplicationProvider.getApplicationContext<Context>()
        val restoration=StateRestorationTester(compose);restoration.setContent{Screen()};openTrade();deleteFromDetail();await("investment.trade.detail.funds.review")
        compose.onNodeWithTag("investment.trade.detail.funds.confirm.text",useUnmergedTree=true).assertTextEquals(context.getString(R.string.investment_trade_delete_cash_review_action))
        compose.onNodeWithTag("investment.trade.detail.funds.message."+walletId).assertTextEquals(context.getString(R.string.investment_trade_delete_cash_review_message,formatMinorUnits(22,"VND"),formatMinorUnits(0,"VND"),formatMinorUnits(0,"VND")))
        compose.onNodeWithTag("investment.trade.detail.funds.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        deleteFromDetail();await("investment.trade.detail.funds.review");restoration.emulateSavedInstanceStateRestore();await("investment.trade.detail.quantity")
        compose.onNodeWithTag("investment.trade.detail.funds.review").assertDoesNotExist();compose.onNodeWithTag("investment.trade.detail.delete.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        deleteFromDetail();await("investment.trade.detail.funds.review");compose.onNodeWithTag("investment.trade.detail.funds.confirm").performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.trade.detail.sheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertNotNull(rows().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}.deletedAt)
        Assert.assertNotNull(rows().rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(expenseId,"cash-consumption-booked")}.deletedAt)
    }
    @Test fun aForeignDetailSnapshotCannotExposeFieldsOrPermitDeletion() {
        seedSale();val other=UserId("99999999-9999-9999-9999-999999999999")
        val source=object:InvestmentRepository by repo {
            override fun observeTradeDeletionSnapshot(subject:UserId)=repo.observeTradeDeletionSnapshot(subject).map{snapshot->snapshot.copy(owner=other,rows=snapshot.rows.map{row->row.copy(ownerUserId=other.value,payload=JsonObject(row.payload+buildJsonObject{put("user_id",other.value);if(row.entity==CloudEntity.INVESTMENT_ASSET.table)put("name","Foreign private asset")}))})}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source=source)};tapTrade();await("investment.trade.detail.unavailable")
        compose.onNodeWithTag("investment.trade.detail.quantity").assertDoesNotExist();compose.onNodeWithTag("investment.trade.detail.delete").assertDoesNotExist();compose.onNodeWithText("Foreign private asset").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aReadFailureClearsAnOpenFundReviewAndAllOldDetailFields() {
        futureExpense();seedSale();val failure=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeTradeDeletionSnapshot(subject:UserId)=flow {
                emit(repo.observeTradeDeletionSnapshot(subject).first());failure.await();throw java.io.IOException("Detail observer lost")
            }
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source=source)};openTrade();deleteFromDetail();await("investment.trade.detail.funds.review")
        compose.runOnIdle{failure.complete(Unit)};await("investment.trade.detail.unavailable")
        compose.onNodeWithTag("investment.trade.detail.funds.review").assertDoesNotExist();compose.onNodeWithTag("investment.trade.detail.quantity").assertDoesNotExist();compose.onNodeWithTag("investment.trade.detail.delete").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aLateUncancellableFundResultCannotShowAReviewAfterTheDetailReadFailed() {
        futureExpense();seedSale();val failure=CompletableDeferred<Unit>();val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>()
        val source=object:InvestmentRepository by repo {
            override fun observeTradeDeletionSnapshot(subject:UserId)=flow {
                emit(repo.observeTradeDeletionSnapshot(subject).first());failure.await();throw java.io.IOException("Detail observer lost")
            }
            override suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Result<CloudRecord> = withContext(NonCancellable){started.complete(Unit);release.await();repo.deleteTrade(owner,request,deviceId,now)}
        }
        val before=rows();val pending=queues();compose.setContent{Screen(source=source)};openTrade()
        try {
            deleteFromDetail();compose.waitUntil(5000){started.isCompleted};compose.runOnIdle{failure.complete(Unit)};await("investment.trade.detail.unavailable")
            compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){compose.onAllNodesWithTag("investment.trade.detail.saving").fetchSemanticsNodes().isEmpty()}
            compose.onNodeWithTag("investment.trade.detail.funds.review").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }finally{release.complete(Unit);failure.complete(Unit)}
    }

    @Test fun cancellingThePrimaryPromptRevokesAQueuedOldConfirmationCallback() {
        seedSale();var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return Result.failure(IllegalStateException("Cancelled intent must not reach repository"))}
        }
        compose.setContent{Screen(source=source)};openTrade();compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo().performClick();await("investment.trade.detail.delete.review")
        var confirm:(()->Boolean)?=null;var cancel:(()->Boolean)?=null
        compose.onNodeWithTag("investment.trade.detail.delete.confirm").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){confirm=it}
        compose.onNodeWithTag("investment.trade.detail.delete.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){cancel=it}
        val before=rows();val pending=queues();compose.runOnIdle{cancel!!.invoke();confirm!!.invoke()};compose.waitForIdle()
        compose.runOnIdle{Assert.assertEquals(0,calls)}
        compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo().performClick();await("investment.trade.detail.delete.review")
        compose.runOnIdle{confirm!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(0,calls)}
        compose.onNodeWithTag("investment.trade.detail.delete.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun cancellingFundConsentRevokesAQueuedOldUseCallback() {
        futureExpense();seedSale();var calls=0
        val source=object:InvestmentRepository by repo {
            override suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Result<CloudRecord>{calls++;return if(request.consent==null)repo.deleteTrade(owner,request,deviceId,now) else Result.failure(IllegalStateException("Cancelled consent must not reach repository"))}
        }
        compose.setContent{Screen(source=source)};openTrade();deleteFromDetail();await("investment.trade.detail.funds.review")
        var confirm:(()->Boolean)?=null;var cancel:(()->Boolean)?=null
        compose.onNodeWithTag("investment.trade.detail.funds.confirm").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){confirm=it}
        compose.onNodeWithTag("investment.trade.detail.funds.cancel").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick){cancel=it}
        val before=rows();val pending=queues();compose.runOnIdle{cancel!!.invoke();confirm!!.invoke()};compose.waitForIdle()
        compose.runOnIdle{Assert.assertEquals(1,calls)}
        deleteFromDetail();await("investment.trade.detail.funds.review");compose.runOnIdle{confirm!!.invoke()};compose.waitForIdle();compose.runOnIdle{Assert.assertEquals(2,calls)}
        compose.onNodeWithTag("investment.trade.detail.funds.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun repositoryReplacementDropsTheOldSaveAndItsLateFundResultCannotReplaceTheNewReview() {
        futureExpense();seedSale();val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        val old=object:InvestmentRepository by repo {
            override suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Result<CloudRecord> = withContext(NonCancellable){started.complete(Unit);release.await();repo.deleteTrade(owner,request,deviceId,now).also{finished.complete(Unit)}}
        }
        var current:InvestmentRepository by mutableStateOf(old)
        val before=rows();val pending=queues();compose.setContent{Screen(source=current)};openTrade()
        try {
            deleteFromDetail();compose.waitUntil(5000){started.isCompleted};compose.runOnIdle{current=repo};await("investment.trade.detail.quantity")
            compose.onNodeWithTag("investment.trade.detail.saving").assertDoesNotExist();compose.onNodeWithTag("investment.trade.detail.funds.review").assertDoesNotExist()
            deleteFromDetail();await("investment.trade.detail.funds.review");compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){finished.isCompleted}
            compose.onNodeWithTag("investment.trade.detail.funds.review").assertExists();compose.onNodeWithTag("investment.trade.detail.error").assertDoesNotExist();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }finally{release.complete(Unit)}
    }

    @Test fun anOlderPurchaseRemainsReachableAfterMoreThanTwentyNewerTrades() {
        runBlocking {
            val asset=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
            for(index in 1..21) {
                val id=java.util.UUID(0,index.toLong()).toString()
                repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"1","box",0,0,"VND",null,null,null,null,null,null,null,"2026-10-23T01:00:00Z",now),asset,null,null,"Reserve"),device,now).getOrThrow()
            }
        }
        val before=rows();val pending=queues();compose.setContent{Screen()};openTrade("55555555-5555-5555-5555-555555555555")
        compose.onNodeWithTag("investment.trade.detail.quantity").assertTextContains("2.5 box",substring=true)
        compose.onNodeWithTag("investment.trade.detail.basis").performScrollTo().assertTextContains("70",substring=true);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

    @Test fun detailDeleteAndFundReviewFitThreeLanguagesBothThemesAtActual130And320Dp() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        runBlocking {
            val old=store.record(owner,CloudEntity.INVESTMENT_TRADE.table,"55555555-5555-5555-5555-555555555555")!!
            repo.deleteTrade(owner,InvestmentTradeDeletionRequest(old,null,"Reserve"),device,now).getOrThrow()
            val prior=store.record(owner,CloudEntity.LEDGER_WALLET.table,walletId)!!
            val wallet=prior.copy(payload=JsonObject(prior.payload+buildJsonObject{put("opening_balance_minor",Long.MAX_VALUE);put("name","Cash / 共同ウォレット / Ví chung")}))
            store.commitMutation(wallet,PendingMutation(CloudEntity.LEDGER_WALLET,wallet.id,owner.value,MutationKind.UPSERT,wallet.payload,now,wallet.syncVersion,device))
            val asset=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
            repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft("88888888-8888-8888-8888-888888888888",assetId,"2.5","box",Long.MAX_VALUE,Long.MAX_VALUE,"VND",null,null,null,walletId,Long.MAX_VALUE,null,null,"2026-10-22T00:00:00Z","2026-10-22T00:00:00Z"),asset,LedgerWalletRecord.fromCloudRecord(wallet),null,"Reserve"),device,now).getOrThrow()
        }
        futureExpense(Long.MAX_VALUE);val sale=seedSale(Long.MAX_VALUE)
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String){
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            };windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config){key(language,dark){Screen(dark=dark)}}
        }
        fun complete(tag:String,oneLine:Boolean=false):androidx.compose.ui.text.TextLayoutResult {
            val results=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(results)}
            val result=results.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            if(result.didOverflowHeight) {
                val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                bitmap?.let{frame->java.io.File(context.getExternalFilesDir(null),"investment-trade-detail-overflow-"+language+"-"+dark+".png").outputStream().use{frame.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};frame.recycle()}
            }
            Assert.assertFalse("Overflow "+tag+" "+language+"/"+dark+" size="+result.size+" paragraph="+result.multiParagraph.height+" constraints="+result.layoutInput.constraints+" lines="+result.lineCount+" end="+result.getLineEnd(result.lineCount-1,true)+"/"+result.layoutInput.text.length,result.didOverflowHeight);Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true))
            if(oneLine)Assert.assertEquals("Money split "+tag,1,result.lineCount)
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue("Clipped "+tag+": "+result.getLineRight(line)+" > "+result.size.width,result.getLineRight(line)<=result.size.width+1f);Assert.assertTrue(result.getLineLeft(line)>=-1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{c->if(!Character.isWhitespace(c))Assert.assertTrue("Missing glyph "+c,paint.hasGlyph(String(Character.toChars(c))))}
            return result
        }
        fun capture(kind:String){
            compose.waitForIdle()
            val committed=java.util.concurrent.CountDownLatch(1)
            compose.runOnIdle {
                val window=android.view.inspector.WindowInspector.getGlobalWindowViews().last{it.isShown && it.isHardwareAccelerated}
                window.viewTreeObserver.registerFrameCommitCallback{committed.countDown()}
                window.postInvalidateOnAnimation()
            }
            Assert.assertTrue("Screenshot waits for the current native frame",committed.await(3,java.util.concurrent.TimeUnit.SECONDS))
            val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
            java.io.File(context.getExternalFilesDir(null),"investment-trade-detail-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
        }
        fun buttons(confirm:String,cancel:String){
            val a=compose.onNodeWithTag(confirm).assertIsDisplayed().fetchSemanticsNode().boundsInRoot;val b=compose.onNodeWithTag(cancel).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
            Assert.assertTrue(a.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(b.height>=48*context.resources.displayMetrics.density-1)
            Assert.assertTrue(a.right<=b.left || b.right<=a.left || a.bottom<=b.top || b.bottom<=a.top)
        }
        fun headerPixels():IntArray {
            val sheet=compose.onNodeWithTag("investment.trade.detail.sheet");val bounds=sheet.fetchSemanticsNode().boundsInRoot
            val close=compose.onNodeWithTag("investment.trade.detail.close").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
            val title=compose.onNodeWithTag("investment.trade.detail.title").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
            val bitmap=sheet.captureToImage().asAndroidBitmap();val height=kotlin.math.ceil(maxOf(close.bottom,title.bottom)-bounds.top).toInt()
            return IntArray(bitmap.width*height).also{bitmap.getPixels(it,0,bitmap.width,0,0,bitmap.width,height)}
        }
        val before=rows();val pending=queues()
        try{for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)){
            compose.runOnIdle{configure(code);language=code;dark=theme};openTrade();compose.runOnIdle{configure(code)}
            listOf("title","asset","asset.label","channel","channel.label","kind","quantity","quantity.label").forEach{complete("investment.trade.detail."+it)}
            listOf("gross","accounting","basis","profit").forEach{complete("investment.trade.detail."+it,true);complete("investment.trade.detail."+it+".label")}
            val header=headerPixels();capture("top")
            compose.onNodeWithTag("investment.trade.detail.time").performScrollTo();complete("investment.trade.detail.time");complete("investment.trade.detail.position.label")
            complete("investment.trade.detail.position")
            complete("investment.trade.detail.position.cost",true);complete("investment.trade.detail.position.cost.label")
            compose.onNodeWithTag("investment.trade.detail.position.cost").assertTextEquals(formatMinorUnits(requireNotNull(sale.payload.financeRawLong("position_cost_basis_after_minor")),"VND"));Assert.assertArrayEquals("Detail scroll must preserve pinned header",header,headerPixels());capture("money")
            compose.onNodeWithTag("investment.trade.detail.delete").performScrollTo();complete("investment.trade.detail.delete.description");complete("investment.trade.detail.delete.text")
            compose.onNodeWithTag("investment.trade.detail.delete").performClick();await("investment.trade.detail.delete.review");compose.runOnIdle{configure(code)}
            listOf("title","message","confirm.text","cancel.text").forEach{complete("investment.trade.detail.delete."+it)};buttons("investment.trade.detail.delete.confirm","investment.trade.detail.delete.cancel");capture("delete")
            compose.onNodeWithTag("investment.trade.detail.delete.cancel").performClick();Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
            deleteFromDetail();await("investment.trade.detail.funds.review");compose.runOnIdle{configure(code)}
            listOf("title","name."+walletId,"message."+walletId,"confirm.text","cancel.text").forEach{complete("investment.trade.detail.funds."+it)};buttons("investment.trade.detail.funds.confirm","investment.trade.detail.funds.cancel");capture("funds")
            compose.onNodeWithTag("investment.trade.detail.funds.cancel").performClick();compose.onNodeWithTag("investment.trade.detail.close").performClick()
            compose.waitUntil(5000){compose.onAllNodesWithTag("investment.trade.detail.sheet").fetchSemanticsNodes().isEmpty()};Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        }}finally{compose.runOnIdle{originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)};android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}}}
    }

}
