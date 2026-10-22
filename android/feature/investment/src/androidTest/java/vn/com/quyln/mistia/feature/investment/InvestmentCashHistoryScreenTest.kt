package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
class InvestmentCashHistoryScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description ->
        object:org.junit.runners.model.Statement(){override fun evaluate(){
            if(description.methodName != "cashHistoryAndExistingTransferFormsFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
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
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private var activeOwner=owner
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val linked="22222222-2222-4222-8222-222222222222"
    private val selected="33333333-3333-4333-8333-333333333333"
    private val device="44444444-4444-4444-8444-444444444444"
    private val event="55555555-5555-4555-8555-555555555555"
    private val profitId="66666666-6666-4666-8666-666666666666"
    private val cashId="77777777-7777-4777-8777-777777777777"
    private val now="2026-10-22T00:00:00Z"
    private fun wallet(id:String)=WalletDraft(id=id,name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,now).record
    private fun rows():List<CloudRecord> {
        val system=wallet(investmentSystemWalletId(owner)).let{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+buildJsonObject {
            put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",linked);put("opening_balance_minor",0L);put("sync_version",9007199254740993L);put("future_field","preserve")
        }))}
        fun row(entity:CloudEntity,id:String,fields:JsonObject)=CloudRecord(entity.table,id,owner.value,JsonObject(fields+buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("sync_version",0L);put("deleted_at",JsonNull)
        }),now,null,0)
        return listOf(system,wallet(linked),wallet(selected),row(CloudEntity.INVESTMENT_TRADE,profitId,buildJsonObject{put("realized_profit_loss_minor",800L);put("accounting_currency_code","VND");put("kind_raw_value","sell");put("asset_id",cashId);put("quantity_decimal_string","1");put("unit_label","box");put("funding_wallet_id",selected);put("capital_return_wallet_id",linked);put("occurred_at","2026-10-18T00:00:00Z");put("gross_amount_minor",900L);put("currency_code","VND")}),
            row(CloudEntity.INVESTMENT_POSTING,cashId,buildJsonObject {
                put("event_id",profitId);put("trade_id",profitId);put("asset_id",cashId);put("ledger_transaction_id",profitId);put("occurred_at","2026-10-18T00:00:00Z");put("wallet_id",linked);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
                put("amount_minor",300L);put("currency_code","VND");put("accounting_amount_minor",300L);put("accounting_currency_code","VND")
            }))
    }
    private fun mutation(raw:CloudRecord)=raw to PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device)
    private fun request(withdraw:Boolean=false,otherWallet:Boolean=false):InvestmentCashTransferRequest {
        val records=rows();fun wallet(id:String)=investmentLinkedWalletRecord(records.single{it.id==id})
        val direction=if(withdraw)InvestmentCashTransferDirection.WITHDRAWAL else InvestmentCashTransferDirection.DEPOSIT
        val amount=if(withdraw)300L else 500L
        val target=if(otherWallet)selected else linked
        return InvestmentCashTransferRequest(wallet(investmentSystemWalletId(owner)),wallet(linked),wallet(target),
            InvestmentCashTransferDraft(event,direction,target,amount," Test note ","2026-10-20T12:34:00Z",now),
            InvestmentCashTransferPreview(direction,amount,amount,java.math.BigInteger.valueOf(800),java.math.BigInteger.valueOf(300),java.math.BigInteger.valueOf(300),java.math.BigInteger.valueOf(if(withdraw || !otherWallet)9700 else 10000)),"Transfer")
    }

    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    @Before fun setup(){
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={activeOwner});repo=OfflineFirstInvestmentRepository(store)
    }
    private fun prepare(firstLink:Boolean=false)=runBlocking {
        val rows=rows().map{row ->if(firstLink && row.id==investmentSystemWalletId(owner))row.copy(payload=JsonObject(row.payload+("investment_linked_wallet_id" to JsonNull))) else row}
        store.commitMutations(rows.map(::mutation))
    }
    private fun snapshot(subject:UserId=owner)=runBlocking{store.investmentCashSnapshot(subject)}
    private fun queues(subject:UserId=owner)=runBlocking{InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(subject,it,Long.MAX_VALUE)}}
    @Composable private fun Screen(subject:UserId=owner,source:InvestmentRepository=repo,dark:Boolean=false){MistiaTheme(darkTheme=dark){Scaffold{padding ->InvestmentScreen(subject,source,{},Modifier.padding(padding),primaryCurrencyCode="VND",deviceIdProvider={device},enabledCurrencyCodes=listOf("JPY","VND"))}}}
    private fun await(tag:String){compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
    private fun open(withdraw:Boolean=false){
        val tag=if(withdraw)"investment.cash.withdraw" else "investment.cash.deposit"
        await(tag);compose.waitUntil(5000){compose.onAllNodes(hasTestTag(tag) and isEnabled()).fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag(tag).performScrollTo().assertIsEnabled().performClick()
        await("investment.cash.transfer.sheet")
    }
    private fun tapAndAwait(tag:String,next:String) {
        val node=compose.onNodeWithTag(tag);node.performScrollTo().assertIsDisplayed().assertIsEnabled()
        val before=node.fetchSemanticsNode().boundsInRoot
        node.performClick()
        try{await(next)}catch(failure:Throwable){throw AssertionError("Click "+tag+" bounds before="+before+" after="+runCatching{node.fetchSemanticsNode().boundsInRoot}.getOrNull()+"; "+
            runCatching{compose.onNodeWithTag("investment.cash.transfer.sheet").printToString()}.getOrDefault("sheet missing"),failure)}
    }
    private fun save(){compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled().performClick()
        try{compose.waitUntil(5000){snapshot().rows.any{it.entity==CloudEntity.LEDGER_TRANSACTION.table}}}
        catch(failure:Throwable){throw AssertionError("No ledger after Save click: "+runCatching{compose.onNodeWithTag("investment.cash.transfer.sheet").printToString()}.getOrDefault("sheet missing"),failure)}}


    private fun deposited()=runBlocking{prepare();repo.saveCashTransfer(owner,request(),device,now).getOrThrow()}
    private fun history() {
        await("investment.list");compose.onNodeWithTag("investment.list").performScrollToNode(hasTestTag("investment.cash.history.seeAll"))
        compose.onNodeWithTag("investment.cash.history.seeAll").assertIsDisplayed().performClick();await("investment.cash.history.screen")
    }
    private fun edit() {
        history();await("investment.cash.history.item."+event);compose.onNodeWithTag("investment.cash.history.item."+event).performScrollTo().performClick();await("investment.cash.transfer.sheet")
    }
    @Test fun actualPreviewTimelineAndFiltersShowThePersistedEventOnceWithOriginalAmountAndDates() {
        deposited();val before=snapshot();val pending=queues();compose.setContent{Screen()};history()
        compose.onNodeWithTag("investment.cash.history.item."+event).assertExists();compose.onNodeWithTag("investment.cash.history.item."+profitId).assertExists()
        compose.onNodeWithTag("investment.cash.history.filter.OUTGOING").performClick();compose.onNodeWithTag("investment.cash.history.item."+event).assertDoesNotExist()
        compose.onNodeWithTag("investment.cash.history.filter.INCOMING").performClick();compose.onNodeWithTag("investment.cash.history.item."+event).assertExists()
        compose.onNodeWithTag("investment.cash.history.back").performClick();compose.onNodeWithTag("investment.cash.history.screen").assertDoesNotExist()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun openingThePersistedDepositRestoresItsExactDraftAndSavingEditsBothRowsWithoutAnotherIdentity() {
        deposited();compose.setContent{Screen()};edit()
        compose.onNodeWithTag("investment.cash.transfer.amount").assert(hasText("500",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().assert(hasText("Test note",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled().performClick()
        compose.waitUntil(5000){snapshot().rows.single{it.id==event}.payload.financeRawLong("amount_minor")==400L}
        compose.onNodeWithTag("investment.cash.transfer.sheet").assertDoesNotExist();val read=snapshot()
        Assert.assertEquals(7,read.rows.size);Assert.assertEquals(7,queues().values.sumOf{it.size});Assert.assertEquals(java.math.BigInteger.valueOf(700),investmentCashFinancialView(read,"VND").availableMinor)
        val posting=read.rows.single{it.id==investmentLedgerIdentity(event,"cash-transfer-posting")}
        Assert.assertEquals(400L,posting.payload.financeRawLong("amount_minor"));Assert.assertEquals("2026-10-20T12:34:00Z",read.rows.single{it.id==event}.payload.financeRawString("occurred_at"))
    }
    @Test fun deleteConfirmationCancelKeepsTheCompletePairAndConfirmDeletesBothQueuesAtomically() {
        deposited();val before=snapshot();val pending=queues();compose.setContent{Screen()};edit()
        compose.onNodeWithTag("investment.cash.transfer.delete").performScrollTo().performClick();await("investment.cash.transfer.delete.confirm")
        compose.onNodeWithTag("investment.cash.transfer.delete.cancel").performClick();Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.cash.transfer.delete").performScrollTo().performClick();await("investment.cash.transfer.delete.confirm")
        compose.onNodeWithTag("investment.cash.transfer.delete.confirm").performClick()
        compose.waitUntil(5000){snapshot().rows.single{it.id==event}.deletedAt!=null};compose.onNodeWithTag("investment.cash.transfer.sheet").assertDoesNotExist()
        val ids=setOf(event,investmentLedgerIdentity(event,"cash-transfer-posting"));Assert.assertEquals(2,snapshot().rows.count{it.id in ids && it.deletedAt!=null})
        val eventQueues=queues().values.flatten().map{it.mutation}.filter{it.recordId in ids};Assert.assertEquals(2,eventQueues.size);Assert.assertTrue(eventQueues.all{it.kind==MutationKind.DELETE})
        Assert.assertEquals(java.math.BigInteger.valueOf(300),investmentCashFinancialView(snapshot(),"VND").availableMinor)
    }
    @Test fun aConsumedDepositCannotBeDeletedAndShowsTheLocalizedDependencyErrorWithoutWrites() {
        deposited();runBlocking{
            val posting=rows().single{it.id==cashId};val id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
            store.commitMutations(listOf(mutation(posting.copy(id=id,payload=JsonObject(posting.payload+buildJsonObject {
                put("id",id);put("event_id",id);put("ledger_transaction_id",id);put("trade_id",JsonNull);put("asset_id",JsonNull);put("role_raw_value","cashConsumption");put("amount_minor",-400L);put("accounting_amount_minor",-400L)
            })))))
        }
        val before=snapshot();val pending=queues();compose.setContent{Screen()};edit()
        compose.onNodeWithTag("investment.cash.transfer.delete").performScrollTo().performClick();await("investment.cash.transfer.delete.confirm")
        compose.onNodeWithTag("investment.cash.transfer.delete.confirm").performClick();await("investment.cash.transfer.error")
        val context=ApplicationProvider.getApplicationContext<Context>()
        compose.onNodeWithTag("investment.cash.transfer.error").performScrollTo().assertTextEquals(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_cash_transfer_error_has_dependents))
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues());compose.onNodeWithTag("investment.cash.transfer.sheet").assertExists()
    }
    @Test fun existingWithdrawalReopensTheDestinationAndCanChangeItsAmountWithActualBalancesRecomputedOnce() {
        prepare();runBlocking{repo.saveCashTransfer(owner,request(withdraw=true,otherWallet=true),device,now).getOrThrow()};compose.setContent{Screen()};edit()
        compose.onNodeWithTag("investment.cash.transfer.amount").assert(hasText("300",substring=false)).performTextReplacement("200")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled().performClick()
        compose.waitUntil(5000){snapshot().rows.single{it.id==event}.payload.financeRawLong("amount_minor")==200L}
        val read=snapshot();val balances=financeWalletBalancesRaw(owner,read.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(java.math.BigInteger.valueOf(9800),balances[linked]);Assert.assertEquals(java.math.BigInteger.valueOf(10200),balances[selected])
        Assert.assertEquals(java.math.BigInteger.valueOf(100),investmentCashFinancialView(read,"VND").availableMinor);Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun changingTheSourceWalletOfAnExistingDepositUsesCapacityWithItsOriginalEventExcluded() {
        deposited();compose.setContent{Screen()};edit()
        compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo().performClick();await("investment.cash.transfer.wallet.option."+selected)
        compose.onNodeWithTag("investment.cash.transfer.wallet.option."+selected).performClick()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled().performClick()
        compose.waitUntil(5000){snapshot().rows.single{it.id==event}.payload.financeRawString("source_wallet_id")==selected}
        val read=snapshot();val balances=financeWalletBalancesRaw(owner,read.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(java.math.BigInteger.valueOf(9600),balances[selected]);Assert.assertEquals(java.math.BigInteger.valueOf(10400),balances[linked]);Assert.assertEquals(7,read.rows.size)
    }
    @Test fun lostEditedSuccessReceiptCanRetryTheSameFrozenRequestWithoutAnotherFinancialWrite() {
        deposited();val requests=mutableListOf<InvestmentCashTransferLifecycleRequest>()
        val lost=object:InvestmentRepository by repo {
            override suspend fun changeCashTransfer(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit> {
                requests+=request;val result=repo.changeCashTransfer(owner,request,deviceId,now)
                return if(requests.size==1 && result.isSuccess)Result.failure(IllegalStateException("synthetic lost edit receipt")) else result
            }
        }
        compose.setContent{Screen(source=lost)};edit();compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.save").performClick();await("investment.cash.transfer.error")
        val committed=snapshot();val pending=queues();Assert.assertEquals(400L,committed.rows.single{it.id==event}.payload.financeRawLong("amount_minor"))
        compose.onNodeWithTag("investment.cash.transfer.retrySave").performScrollTo().assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.transfer.sheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(2,requests.size);Assert.assertEquals(requests[0],requests[1]);Assert.assertEquals(committed,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun lostDeleteSuccessReceiptCanRetryTheOriginalConfirmedDeletionAfterItsRowsAreTombstoned() {
        deposited();val requests=mutableListOf<InvestmentCashTransferLifecycleRequest>()
        val lost=object:InvestmentRepository by repo {
            override suspend fun changeCashTransfer(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit> {
                requests+=request;val result=repo.changeCashTransfer(owner,request,deviceId,now)
                return if(requests.size==1 && result.isSuccess)Result.failure(IllegalStateException("synthetic lost delete receipt")) else result
            }
        }
        compose.setContent{Screen(source=lost)};edit();compose.onNodeWithTag("investment.cash.transfer.delete").performScrollTo().performClick();await("investment.cash.transfer.delete.confirm")
        compose.onNodeWithTag("investment.cash.transfer.delete.confirm").performClick();await("investment.cash.transfer.error")
        val committed=snapshot();val pending=queues();Assert.assertNotNull(committed.rows.single{it.id==event}.deletedAt)
        compose.onNodeWithTag("investment.cash.transfer.retryDelete").performScrollTo().assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.transfer.sheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(2,requests.size);Assert.assertEquals(requests[0],requests[1]);Assert.assertEquals(committed,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun selectedHistoryFilterExposesItsActualSelectionToAccessibility() {
        deposited();compose.setContent{Screen()};history()
        compose.onNodeWithTag("investment.cash.history.filter.ALL").assertIsSelected()
        compose.onNodeWithTag("investment.cash.history.filter.MOVEMENT").performClick().assertIsSelected()
        compose.onNodeWithTag("investment.cash.history.filter.ALL").assertIsNotSelected()
    }
    @Test fun anEmptyHistoryShowsOneEmptyMessageAndDoesNotWriteAnything() {
        runBlocking{store.commitMutations(rows().filterNot{it.id==cashId}.map(::mutation))}
        val before=snapshot();val pending=queues();compose.setContent{Screen()};history()
        val text=ApplicationProvider.getApplicationContext<Context>().getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_history_empty)
        compose.onAllNodesWithText(text).assertCountEquals(1);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun failedEditAndSavedStateRestoreRetainOriginalIdentityDraftAndConsentUntilARealRetry() {
        deposited();val requests=mutableListOf<InvestmentCashTransferLifecycleRequest>()
        val failing=object:InvestmentRepository by repo {
            override suspend fun changeCashTransfer(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit> {
                requests+=request
                return if(requests.size==1)Result.failure(IllegalStateException("synthetic failed edit")) else repo.changeCashTransfer(owner,request,deviceId,now)
            }
        }
        val restorer=StateRestorationTester(compose);restorer.setContent{Screen(source=failing)};edit()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextReplacement("Saved draft")
        compose.onNodeWithTag("investment.cash.transfer.save").performClick();await("investment.cash.transfer.error");restorer.emulateSavedInstanceStateRestore()
        await("investment.cash.transfer.sheet");compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().assert(hasText("400",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().assert(hasText("Saved draft",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled().performClick()
        compose.waitUntil(5000){snapshot().rows.single{it.id==event}.payload.financeRawLong("amount_minor")==400L}
        Assert.assertEquals(2,requests.size);Assert.assertEquals(requests[0],requests[1]);Assert.assertEquals(7,snapshot().rows.size)
    }
    @Test fun nativeAndroidBackReturnsFromHistoryWithoutAnyFinancialOrQueueChange() {
        deposited();val before=snapshot();val pending=queues();compose.setContent{Screen()};history()
        Assert.assertTrue(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK))
        await("investment.list");compose.onNodeWithTag("investment.cash.history.screen").assertDoesNotExist()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun deletingAfterUnsavedWalletAndAmountChangesStillDeletesOnlyTheOriginalPersistedTransfer() {
        deposited();compose.setContent{Screen()};edit()
        compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo().performClick();await("investment.cash.transfer.wallet.option."+selected)
        compose.onNodeWithTag("investment.cash.transfer.wallet.option."+selected).performClick()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.delete").performScrollTo().assertIsEnabled().performClick();await("investment.cash.transfer.delete.confirm")
        compose.onNodeWithTag("investment.cash.transfer.delete.confirm").performClick();compose.waitUntil(5000){snapshot().rows.single{it.id==event}.deletedAt!=null}
        val read=snapshot();val ledger=read.rows.single{it.id==event};Assert.assertEquals(500L,ledger.payload.financeRawLong("amount_minor"));Assert.assertEquals(linked,ledger.payload.financeRawString("source_wallet_id"))
        val balances=financeWalletBalancesRaw(owner,read.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(java.math.BigInteger.valueOf(10000),balances[linked]);Assert.assertEquals(java.math.BigInteger.valueOf(10000),balances[selected]);Assert.assertEquals(7,read.rows.size)
    }
    @Test fun historyReadFailureShowsNoInventedRowsAndOnlyActualReadRetryRevealsTheOwnedTimeline() {
        deposited();val before=snapshot();val pending=queues();var collections=0
        val failing=object:InvestmentRepository by repo {
            override fun observeCashSnapshot(owner:UserId)=flow {
                collections++;if(collections==1)throw IllegalStateException("synthetic history disk failure")
                emitAll(repo.observeCashSnapshot(owner))
            }
        }
        compose.setContent{Screen(source=failing)};history();await("investment.cash.history.error")
        compose.onNodeWithTag("investment.cash.history.item."+event).assertDoesNotExist();compose.onNodeWithTag("investment.cash.history.retry").performClick()
        await("investment.cash.history.item."+event);compose.onNodeWithTag("investment.cash.history.error").assertDoesNotExist()
        Assert.assertEquals(2,collections);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun actualTimelineRevealsEventsBeyondTheInitialFiftyThroughRealScrollingWithoutWrites() {
        prepare();runBlocking {
            val profit=snapshot().rows.single{it.id==profitId}.let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("realized_profit_loss_minor",100000L);put("gross_amount_minor",100900L)}))}
            store.commitMutations(listOf(mutation(profit)))
            for(index in 1..60) {
                val view=readInvestmentCashTransfer(snapshot(),InvestmentCashTransferDirection.DEPOSIT,linked,50)
                val id=java.util.UUID(0,index.toLong()).toString()
                val request=InvestmentCashTransferRequest(view.system,view.linked,view.selected,InvestmentCashTransferDraft(id,InvestmentCashTransferDirection.DEPOSIT,linked,50,"History "+index,"2026-10-20T12:34:00Z",now),view.preview,"Transfer")
                repo.saveCashTransfer(owner,request,device,now).getOrThrow()
            }
        }
        val before=snapshot();val pending=queues();Assert.assertEquals(61,investmentCashHistory(before,"VND").size)
        compose.setContent{Screen()};history();var found=false
        repeat(30){if(!found){compose.onNodeWithTag("investment.cash.history.list").performTouchInput{swipeUp()};compose.waitForIdle();found=compose.onAllNodesWithTag("investment.cash.history.item."+profitId).fetchSemanticsNodes().isNotEmpty()}}
        compose.onNodeWithTag("investment.cash.history.item."+profitId).performScrollTo().assertIsDisplayed()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun repositoryRebindingForTheSameOwnerRetainsTheOriginalHistoryEditorAndItsDraft() {
        deposited();var source by mutableStateOf<InvestmentRepository>(repo);val requests=mutableListOf<InvestmentCashTransferLifecycleRequest>()
        compose.setContent{Screen(source=source)};edit();compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextReplacement("Rebound draft")
        compose.runOnIdle{source=object:InvestmentRepository by OfflineFirstInvestmentRepository(store) {
            override suspend fun changeCashTransfer(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit>{requests+=request;return repo.changeCashTransfer(owner,request,deviceId,now)}
        }}
        await("investment.cash.transfer.sheet");compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.transfer.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().assert(hasText("400",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().assert(hasText("Rebound draft",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.save").performClick();compose.waitUntil(5000){snapshot().rows.single{it.id==event}.payload.financeRawLong("amount_minor")==400L}
        Assert.assertEquals(event,(requests.single() as InvestmentCashTransferLifecycleRequest.Save).transfer.draft.id);Assert.assertEquals("Rebound draft",snapshot().rows.single{it.id==event}.payload.financeRawString("note"))
    }
    @Test fun aNoncancellableOldOwnerEditCannotWriteDismissOrLeakIntoTheNewOwnersForm() {
        deposited();runBlocking{store.commitMutations(rows().map{raw ->
            val id=if(raw.id==investmentSystemWalletId(owner))investmentSystemWalletId(other) else raw.id
            raw.copy(id=id,ownerUserId=other.value,payload=JsonObject(raw.payload+buildJsonObject{put("id",id);put("user_id",other.value)}))
        }.map(::mutation))}
        fun rawRows(subject:UserId)=runBlocking{InvestmentCashReadSnapshot.entities.flatMap{store.recordsIncludingDeleted(subject,it.table)}}
        val oldRows=rawRows(owner);val otherRows=rawRows(other);val oldQueues=queues(owner);val otherQueues=queues(other)
        val entered=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>();var calls=0
        val blocked=object:InvestmentRepository by repo {
            override suspend fun changeCashTransfer(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit> = withContext(NonCancellable) {
                calls++;entered.complete(Unit)
                try{release.await();repo.changeCashTransfer(owner,request,deviceId,now)}finally{finished.complete(Unit)}
            }
        }
        var subject by mutableStateOf(owner);compose.setContent{Screen(subject=subject,source=blocked)}
        try {
            edit();compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextReplacement("Private old draft")
            compose.onNodeWithTag("investment.cash.transfer.save").performTouchInput{click();click()}
            compose.waitUntil(5000){entered.isCompleted};Assert.assertEquals(1,calls)
            compose.runOnIdle{activeOwner=other;subject=other};await("investment.list");open()
            compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().assert(hasText("",substring=false));compose.onAllNodesWithText("Private old draft").assertCountEquals(0)
            compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){finished.isCompleted};compose.waitForIdle()
            compose.onNodeWithTag("investment.cash.transfer.sheet").assertExists();Assert.assertEquals(oldRows,rawRows(owner));Assert.assertEquals(otherRows,rawRows(other));Assert.assertEquals(oldQueues,queues(owner));Assert.assertEquals(otherQueues,queues(other))
        }finally{release.complete(Unit)}
    }
    @Test fun cashHistoryAndExistingTransferFormsFitThreeLanguagesBothThemesAtActual130And320Dp() {
        prepare();runBlocking {
            val base=snapshot().rows.map{raw ->raw.copy(payload=JsonObject(raw.payload+buildJsonObject {
                if(raw.id==linked){put("opening_balance_minor",Long.MAX_VALUE);put("name","Household wallet / 共同ウォレット / Ví giao dịch chung")}
                if(raw.id==profitId){put("realized_profit_loss_minor",Long.MAX_VALUE);put("gross_amount_minor",Long.MAX_VALUE)}
            }))}
            val second=base.single{it.id==profitId}.let{it.copy(id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",payload=JsonObject(it.payload+("id" to JsonPrimitive("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))))}
            store.commitMutations((base+second).map(::mutation))
            val view=readInvestmentCashTransfer(snapshot(),InvestmentCashTransferDirection.DEPOSIT,linked,0)
            repo.saveCashTransfer(owner,InvestmentCashTransferRequest(view.system,view.linked,view.selected,request().draft.copy(amountMinor=view.preview.maximumMinor,note="Original note / Ghi chú / 元のメモ"),view.preview.copy(requestedMinor=view.preview.maximumMinor),"Transfer"),device,now).getOrThrow()
        }
        val before=snapshot();val pending=queues();val context=ApplicationProvider.getApplicationContext<Context>()
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config){Screen(dark=dark)}
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
        fun complete(node:SemanticsNodeInteraction,editable:Boolean=false):androidx.compose.ui.text.TextLayoutResult {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val result=layouts.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true));Assert.assertFalse(result.didOverflowHeight)
            val width=if(editable)node.fetchSemanticsNode().boundsInRoot.width-32*context.resources.displayMetrics.density else result.size.width.toFloat()
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue("Clipped text: "+result.layoutInput.text,result.getLineRight(line)<=width+1f);Assert.assertTrue(result.getLineLeft(line)>=-1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{code ->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
            return result
        }
        fun capture(kind:String,tag:String) {
            val bitmap=compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-cash-history-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        }
        try {
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme};history();compose.runOnIdle{configure(code)}
                val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
                for(resource in listOf(vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_history_title,vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_history_filter_all,
                    vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_history_filter_incoming,vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_history_filter_outgoing,vn.com.quyln.mistia.core.designsystem.R.string.investment_wallet_history_filter_movement))
                    complete(compose.onNodeWithText(localized.getString(resource),useUnmergedTree=true))
                compose.onNodeWithTag("investment.cash.history.item."+event).performScrollTo()
                val money=compose.onNodeWithTag("investment.cash.history.amount."+event,useUnmergedTree=true)
                money.assertTextEquals("+"+vn.com.quyln.mistia.core.designsystem.formatMinorUnits(java.math.BigInteger.valueOf(Long.MAX_VALUE)-java.math.BigInteger.valueOf(300),"VND"))
                val moneyLayout=complete(money);Assert.assertEquals(1,moneyLayout.lineCount)
                Assert.assertEquals(androidx.compose.ui.graphics.Color(if(theme)0xFF30D158 else 0xFF34C759),moneyLayout.layoutInput.style.color)
                val card=compose.onNodeWithTag("investment.cash.history.item."+event);val cardBounds=card.fetchSemanticsNode().boundsInRoot
                val bitmap=card.captureToImage().asAndroidBitmap();val density=context.resources.displayMetrics.density
                val surface=if(theme)vn.com.quyln.mistia.core.designsystem.MistiaColors.CardDark else androidx.compose.ui.graphics.Color.White
                fun close(actual:Int,expected:Int)=listOf(0,8,16).all{shift ->kotlin.math.abs((actual shr shift and 255)-(expected shr shift and 255))<=1}
                val findings=mutableListOf<String>()
                if(!close(bitmap.getPixel(bitmap.width/2,(4*density).toInt()),surface.toArgb()))findings+="History cards must use the grouped-card surface"
                val icon=compose.onNodeWithTag("investment.cash.history.icon."+event,useUnmergedTree=true).fetchSemanticsNode().boundsInRoot
                val iconPixel=bitmap.getPixel((icon.left-cardBounds.left+2*density).toInt(),((icon.top+icon.bottom)/2-cardBounds.top).toInt())
                val tint=androidx.compose.ui.graphics.Color(if(theme)0xFF30D158 else 0xFF34C759).copy(alpha=0.1f).compositeOver(surface).toArgb()
                if(!close(iconPixel,tint))findings+="Manual cash history icon must retain source 10 percent accent background"
                if(moneyLayout.layoutInput.style.textAlign!=androidx.compose.ui.text.style.TextAlign.End)findings+="History money must align to the trailing edge"
                Assert.assertTrue(findings.joinToString("; "),findings.isEmpty())
                Assert.assertEquals(320*context.resources.displayMetrics.density,compose.onNodeWithTag("investment.cash.history.screen").fetchSemanticsNode().boundsInRoot.width,1f)
                for(filter in InvestmentCashHistoryFilter.entries)Assert.assertTrue(compose.onNodeWithTag("investment.cash.history.filter."+filter.name).fetchSemanticsNode().boundsInRoot.height>=48*context.resources.displayMetrics.density)
                capture("timeline","investment.cash.history.screen")
                compose.onNodeWithTag("investment.cash.history.filter.OUTGOING").performClick().assertIsSelected();capture("empty","investment.cash.history.screen")
                compose.onNodeWithTag("investment.cash.history.filter.ALL").performClick()
                compose.onNodeWithTag("investment.cash.history.item."+event).performScrollTo().performClick();await("investment.cash.transfer.sheet");compose.runOnIdle{configure(code)}
                compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().assert(hasText("9,223,372,036,854,775,507",substring=false));complete(compose.onNodeWithTag("investment.cash.transfer.amount"),true)
                compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo();capture("edit-top","investment.cash.transfer.sheet")
                compose.onNodeWithTag("investment.cash.transfer.delete").performScrollTo().assertIsEnabled();capture("edit-bottom","investment.cash.transfer.sheet")
                compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled();compose.onNodeWithTag("investment.cash.transfer.cancel").assertIsDisplayed()
                compose.onNodeWithTag("investment.cash.transfer.delete").performClick();await("investment.cash.transfer.delete.confirm");compose.runOnIdle{configure(code)}
                val confirm=compose.onNodeWithTag("investment.cash.transfer.delete.confirm");val cancel=compose.onNodeWithTag("investment.cash.transfer.delete.cancel")
                confirm.assertIsDisplayed();cancel.assertIsDisplayed();complete(confirm);complete(cancel)
                Assert.assertTrue(confirm.fetchSemanticsNode().boundsInRoot.bottom<=cancel.fetchSemanticsNode().boundsInRoot.top+1f)
                capture("delete","investment.cash.transfer.delete.dialog");cancel.performClick();compose.onNodeWithTag("investment.cash.transfer.cancel").performClick()
                compose.onNodeWithTag("investment.cash.history.back").performClick();Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
            }
        }finally{compose.runOnIdle{
            originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }}
    }
    @Test fun spendingHistoryTitleUsesFoundationWhitespaceTrimmingWithoutChangingStoredText() {
        deposited();val id="cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        runBlocking {
            val ledger=snapshot().rows.single{it.id==event}.let{it.copy(id=id,payload=JsonObject(it.payload+buildJsonObject {
                put("id",id);put("title","\u200b\u0085Spending title\u200b\u0085");put("primary_kind_raw_value","expense");put("transfer_subtype_raw_value",JsonNull);put("settlement_role_raw_value",JsonNull)
                put("destination_wallet_id",JsonNull);put("destination_currency_code",JsonNull);put("destination_amount_minor",JsonNull);put("amount_minor",10L);put("reporting_amount_minor",10L);put("reporting_expense_minor",10L)
                put("occurred_at","2026-10-21T12:34:00Z")
            }))}
            val posting=rows().single{it.id==cashId}.let{it.copy(id=id,payload=JsonObject(it.payload+buildJsonObject {
                put("id",id);put("event_id",id);put("ledger_transaction_id",id);put("trade_id",JsonNull);put("asset_id",JsonNull);put("role_raw_value","cashConsumption");put("amount_minor",-10L);put("accounting_amount_minor",-10L);put("occurred_at","2026-10-21T12:34:00Z")
            }))}
            store.commitMutations(listOf(mutation(ledger),mutation(posting)))
        }
        val before=snapshot();val pending=queues();compose.setContent{Screen()};history();await("investment.cash.history.item."+id)
        compose.onNodeWithText("Spending title",useUnmergedTree=true).assertExists();Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
}
