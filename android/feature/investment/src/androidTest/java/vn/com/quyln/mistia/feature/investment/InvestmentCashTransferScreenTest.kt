package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
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
import vn.com.quyln.mistia.core.model.*

@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
class InvestmentCashTransferScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description ->
        object:org.junit.runners.model.Statement(){override fun evaluate(){
            if(description.methodName != "cashTransferFormsAndPickersFitThreeLanguagesBothThemesAtActual130And320Dp"){base.evaluate();return}
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
        return listOf(system,wallet(linked),wallet(selected),row(CloudEntity.INVESTMENT_TRADE,profitId,buildJsonObject{put("realized_profit_loss_minor",800L);put("accounting_currency_code","VND")}),
            row(CloudEntity.INVESTMENT_POSTING,cashId,buildJsonObject {
                put("wallet_id",linked);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
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
        store=RoomLocalStore(db);repo=OfflineFirstInvestmentRepository(store)
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
        await(tag);compose.onNodeWithTag(tag).performScrollTo().assertIsEnabled().performClick()
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

    @Test fun actualSameWalletDepositShowsFullCapacityDateTimeAndNoteThenClassifiesWithoutMovingActualCash() {
        prepare();val wallets=snapshot().rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table};compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("500")
        compose.onNodeWithTag("investment.cash.transfer.sameWallet").assertExists()
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextInput("  Native note  ")
        tapAndAwait("investment.cash.transfer.date","investment.cash.transfer.date.dialog")
        compose.onNodeWithTag("investment.cash.transfer.date.cancel").performClick();compose.onNodeWithTag("investment.cash.transfer.date.dialog").assertDoesNotExist()
        tapAndAwait("investment.cash.transfer.time","investment.cash.transfer.time.dialog")
        compose.onNodeWithTag("investment.cash.transfer.time.cancel").performClick();compose.onNodeWithTag("investment.cash.transfer.time.dialog").assertDoesNotExist();save()
        val read=snapshot();val ledger=read.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        Assert.assertEquals("Native note",ledger.payload.financeRawString("note"));Assert.assertEquals(500L,ledger.payload.financeRawLong("amount_minor"))
        Assert.assertEquals("investmentCashDeposit",ledger.payload.financeRawString("settlement_role_raw_value"));Assert.assertEquals(linked,ledger.payload.financeRawString("source_wallet_id"));Assert.assertEquals(linked,ledger.payload.financeRawString("destination_wallet_id"))
        Assert.assertEquals(java.math.BigInteger.valueOf(10000),investmentCashFinancialView(read,"VND").linkedActualMinor);Assert.assertEquals(java.math.BigInteger.valueOf(800),investmentCashFinancialView(read,"VND").availableMinor)
        Assert.assertEquals(wallets,read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table});Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun actualWithdrawalToAnotherWalletMovesTheLedgerPairAndSubtractsOnlyLinkedBookedCash() {
        prepare();compose.setContent{Screen()};open(withdraw=true)
        compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo().performClick();await("investment.cash.transfer.wallet.option."+selected)
        compose.onNodeWithTag("investment.cash.transfer.wallet.option."+selected).performClick();save()
        val read=snapshot();val ledger=read.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        Assert.assertEquals("investmentCashWithdrawal",ledger.payload.financeRawString("settlement_role_raw_value"));Assert.assertEquals(300L,ledger.payload.financeRawLong("amount_minor"))
        Assert.assertEquals(linked,ledger.payload.financeRawString("source_wallet_id"));Assert.assertEquals(selected,ledger.payload.financeRawString("destination_wallet_id"))
        val balances=financeWalletBalancesRaw(owner,read.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(java.math.BigInteger.valueOf(9700),balances[linked]);Assert.assertEquals(java.math.BigInteger.valueOf(10300),balances[selected])
        Assert.assertEquals(java.math.BigInteger.ZERO,investmentCashFinancialView(read,"VND").availableMinor);Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun overCapacityIsDisabledMaximumRestoresExactAmountAndCancelKeepsRowsAndQueues() {
        prepare();val before=snapshot();val pending=queues();compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("501")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.cash.transfer.maximum").performScrollTo().performClick()
        compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("500")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsEnabled()
        compose.onNodeWithTag("investment.cash.transfer.cancel").assertIsDisplayed().performClick()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun missingLinkedWalletRoutesToTheRealSelectorAndResumesTheSamePendingDepositAction() {
        prepare(firstLink=true);compose.setContent{Screen()}
        await("investment.cash.deposit");compose.onNodeWithTag("investment.cash.deposit").performScrollTo().performClick()
        await("investment.wallet.link.option."+linked);compose.onNodeWithTag("investment.wallet.link.option."+linked).performScrollTo().performClick()
        await("investment.cash.transfer.sheet");compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("500");save()
        val read=snapshot();Assert.assertEquals(linked,read.rows.single{it.id==investmentSystemWalletId(owner)}.payload.financeRawString("investment_linked_wallet_id"))
        Assert.assertEquals(java.math.BigInteger.valueOf(800),investmentCashFinancialView(read,"VND").availableMinor);Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun usdEntryUsesMajorCurrencyInputWhileTheSavedTransferKeepsExactCents() {
        runBlocking{store.commitMutations(rows().map{row ->row.copy(payload=JsonObject(row.payload.mapValues{(key,value)->
            if(key in setOf("currency_code","accounting_currency_code"))JsonPrimitive("USD") else value
        }))}.map(::mutation))}
        compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").assert(hasText("5",substring=false))
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("4.75");save()
        val read=snapshot();val ledger=read.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        Assert.assertEquals("USD",ledger.payload.financeRawString("source_currency_code"));Assert.assertEquals(475L,ledger.payload.financeRawLong("amount_minor"));Assert.assertEquals(475L,ledger.payload.financeRawLong("destination_amount_minor"))
        Assert.assertEquals(java.math.BigInteger.valueOf(775),investmentCashFinancialView(read,"VND").availableMinor)
        Assert.assertEquals(java.math.BigInteger.valueOf(10000),investmentCashFinancialView(read,"VND").linkedActualMinor)
    }

    @Test fun sourceModalSaveAndCancelRemainVisibleWhenTheLongFormIsScrolledToItsNote() {
        prepare();val before=snapshot();val pending=queues();compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextInput("Long note\n".repeat(30))
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo()
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled()
        compose.onNodeWithTag("investment.cash.transfer.cancel").assertIsDisplayed().performClick()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }

    @Test fun saveFailureAndSavedStateRestoreKeepTheSameAmountNoteDateAndEventUntilRealRetryCommits() {
        prepare();val calls=mutableListOf<InvestmentCashTransferRequest>();val restorer=StateRestorationTester(compose)
        val source=object:InvestmentRepository by repo {
            override suspend fun saveCashTransfer(owner:UserId,request:InvestmentCashTransferRequest,deviceId:String,now:String):Result<Unit> {
                calls.add(request);return if(calls.size==1)Result.failure(IllegalStateException("disk failed")) else repo.saveCashTransfer(owner,request,deviceId,now)
            }
        }
        val before=snapshot();val pending=queues();restorer.setContent{Screen(source=source)};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextInput("Restored note")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().performClick();await("investment.cash.transfer.error")
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues());Assert.assertEquals(1,calls.size)
        restorer.emulateSavedInstanceStateRestore();await("investment.cash.transfer.sheet")
        compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("400");compose.onNodeWithTag("investment.cash.transfer.note").assertTextContains("Restored note")
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.transfer.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};save()
        Assert.assertEquals(2,calls.size);Assert.assertEquals(calls.first().draft,calls.last().draft);Assert.assertEquals(calls.first().expectedPreview,calls.last().expectedPreview)
        Assert.assertEquals(7,queues().values.sumOf{it.size});Assert.assertEquals(400L,snapshot().rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
    }
    @Test fun lostSuccessReceiptAllowsTheOriginalCashRequestToRetryAfterItsCapacityIsExhausted() {
        prepare();val calls=mutableListOf<InvestmentCashTransferRequest>()
        val source=object:InvestmentRepository by repo {
            override suspend fun saveCashTransfer(owner:UserId,request:InvestmentCashTransferRequest,deviceId:String,now:String):Result<Unit> {
                calls.add(request);val result=repo.saveCashTransfer(owner,request,deviceId,now)
                return if(calls.size==1 && result.isSuccess)Result.failure(IllegalStateException("receipt lost")) else result
            }
        }
        compose.setContent{Screen(source=source)};open();compose.onNodeWithTag("investment.cash.transfer.save").performClick();await("investment.cash.transfer.error")
        val committed=snapshot();val pending=queues()
        Assert.assertEquals(java.math.BigInteger.valueOf(800),investmentCashFinancialView(committed,"VND").availableMinor)
        compose.onNodeWithTag("investment.cash.transfer.retrySave").performScrollTo().assertIsEnabled().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.transfer.sheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(2,calls.size);Assert.assertEquals(calls.first(),calls.last());Assert.assertEquals(committed,snapshot());Assert.assertEquals(pending,queues());Assert.assertEquals(7,pending.values.sumOf{it.size})
    }
    @Test fun failedCashReadRetainsEnteredFieldsAndOnlyRetryingThatReadCanReenableSave() {
        prepare();val initial=snapshot();val crash=MutableStateFlow(false);var starts=0
        val source=object:InvestmentRepository by repo {
            override fun observeCashSnapshot(owner:UserId):Flow<InvestmentCashReadSnapshot> = flow {
                if(starts++==0){emit(initial);crash.first{it};throw IllegalStateException("read failed")}
                emitAll(repo.observeCashSnapshot(owner))
            }
        }
        compose.setContent{Screen(source=source)};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextInput("Read retry note")
        val pending=queues();compose.runOnIdle{crash.value=true};await("investment.cash.transfer.readError")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsNotEnabled();compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("400")
        compose.onNodeWithTag("investment.cash.transfer.note").assertTextContains("Read retry note")
        Assert.assertEquals(initial,snapshot());Assert.assertEquals(pending,queues())
        compose.onNodeWithTag("investment.cash.transfer.retryRead").performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.transfer.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};save()
        Assert.assertEquals(2,starts);Assert.assertEquals(400L,snapshot().rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
    }
    @Test fun changedProfitCapacityRequiresExplicitReviewAndNeverSilentlyReplacesEnteredAmount() {
        prepare();compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        val profit=rows().single{it.id==profitId}.let{it.copy(payload=JsonObject(it.payload+("realized_profit_loss_minor" to JsonPrimitive(900L))))}
        runBlocking{store.commitMutations(listOf(mutation(profit)))};await("investment.cash.transfer.conflict")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsNotEnabled();compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("400")
        compose.onNodeWithTag("investment.cash.transfer.limit.amount").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(500,"VND"))
        compose.onNodeWithTag("investment.cash.transfer.retryRead").performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.transfer.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("investment.cash.transfer.limit.amount").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(600,"VND"));save()
        Assert.assertEquals(400L,snapshot().rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"));Assert.assertEquals(java.math.BigInteger.valueOf(700),investmentCashFinancialView(snapshot(),"VND").availableMinor)
    }
    @Test fun replacingOwnerWhileSaveCannotCancelMustNotDismissOrLeakIntoTheNewOwnersForm() {
        prepare();runBlocking{store.commitMutations(rows().map{row ->
            val id=if(row.id==investmentSystemWalletId(owner))investmentSystemWalletId(other) else row.id
            row.copy(id=id,ownerUserId=other.value,payload=JsonObject(row.payload+buildJsonObject{put("id",id);put("user_id",other.value)}))
        }.map(::mutation))}
        val release=CompletableDeferred<Unit>();val completed=java.util.concurrent.atomic.AtomicBoolean(false);val calls=java.util.concurrent.atomic.AtomicInteger(0)
        var subject by mutableStateOf(owner)
        val source=object:InvestmentRepository by repo {
            override suspend fun saveCashTransfer(owner:UserId,request:InvestmentCashTransferRequest,deviceId:String,now:String):Result<Unit> = withContext(NonCancellable) {
                calls.incrementAndGet();release.await();completed.set(true);Result.success(Unit)
            }
        }
        val before=snapshot();val otherBefore=snapshot(other);val pending=queues();val otherPending=queues(other)
        compose.setContent{Screen(subject,source)};open();compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextInput("Private old owner note")
        compose.onNodeWithTag("investment.cash.transfer.save").performClick();await("investment.cash.transfer.saving")
        compose.onNodeWithTag("investment.cash.transfer.save").assertIsNotEnabled();compose.onNodeWithTag("investment.cash.transfer.cancel").assertIsNotEnabled();Assert.assertEquals(1,calls.get())
        compose.runOnIdle{subject=other};compose.waitUntil(5000){compose.onAllNodesWithTag("investment.cash.transfer.sheet").fetchSemanticsNodes().isEmpty()}
        compose.onAllNodes(hasText("Private old owner note",substring=true)).assertCountEquals(0);open()
        compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){completed.get()};compose.waitForIdle()
        compose.onNodeWithTag("investment.cash.transfer.sheet").assertExists();compose.onAllNodes(hasText("Private old owner note",substring=true)).assertCountEquals(0)
        Assert.assertEquals(1,calls.get());Assert.assertEquals(before,snapshot());Assert.assertEquals(otherBefore,snapshot(other));Assert.assertEquals(pending,queues());Assert.assertEquals(otherPending,queues(other))
    }
    @Test fun transferOptionsExcludeOtherCurrencyCreditArchivedAndForeignOwnerWallets() {
        prepare()
        val jpy=wallet("99999999-9999-4999-8999-999999999999").let{it.copy(payload=JsonObject(it.payload+("currency_code" to JsonPrimitive("JPY"))))}
        val credit=wallet("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb").let{it.copy(payload=JsonObject(it.payload+("kind_raw_value" to JsonPrimitive("creditCard"))))}
        val archived=wallet("cccccccc-cccc-4ccc-8ccc-cccccccccccc").let{it.copy(payload=JsonObject(it.payload+("is_archived" to JsonPrimitive(true))))}
        val foreign=wallet("dddddddd-dddd-4ddd-8ddd-dddddddddddd").let{it.copy(ownerUserId=other.value,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))}
        runBlocking{listOf(jpy,credit,archived,foreign).groupBy{it.ownerUserId}.values.forEach{store.commitMutations(it.map(::mutation))}};val before=snapshot();val pending=queues()
        compose.setContent{Screen()};open();compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo().performClick()
        await("investment.cash.transfer.wallet.option."+linked)
        for(row in listOf(jpy,credit,archived,foreign))compose.onNodeWithTag("investment.cash.transfer.wallet.option."+row.id).assertDoesNotExist()
        compose.onNodeWithTag("investment.cash.transfer.wallet.option."+selected).assertExists()
        compose.onNodeWithTag("investment.cash.transfer.wallet.option."+linked).performClick();compose.onNodeWithTag("investment.cash.transfer.cancel").performClick()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun recreatingTheRepositoryForTheSameOwnerMustPreserveTheSavedFinancialDraftAndEvent() {
        prepare();val calls=mutableListOf<InvestmentCashTransferRequest>();val restorer=StateRestorationTester(compose)
        val first=object:InvestmentRepository by repo {
            override suspend fun saveCashTransfer(owner:UserId,request:InvestmentCashTransferRequest,deviceId:String,now:String):Result<Unit>{calls.add(request);return Result.failure(IllegalStateException("disk failed"))}
        }
        val replacement=OfflineFirstInvestmentRepository(store)
        val next=object:InvestmentRepository by replacement {
            override suspend fun saveCashTransfer(owner:UserId,request:InvestmentCashTransferRequest,deviceId:String,now:String):Result<Unit>{calls.add(request);return replacement.saveCashTransfer(owner,request,deviceId,now)}
        }
        var source:InvestmentRepository by mutableStateOf(first)
        restorer.setContent{Screen(source=source)};open()
        compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().performTextReplacement("400")
        compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo().performTextInput("Rebound owner note")
        compose.onNodeWithTag("investment.cash.transfer.save").performClick();await("investment.cash.transfer.error")
        compose.runOnIdle{source=next};restorer.emulateSavedInstanceStateRestore();await("investment.cash.transfer.sheet")
        compose.onNodeWithTag("investment.cash.transfer.amount").assertTextContains("400");compose.onNodeWithTag("investment.cash.transfer.note").assertTextContains("Rebound owner note")
        compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.transfer.save") and isEnabled()).fetchSemanticsNodes().isNotEmpty()};save()
        Assert.assertEquals(2,calls.size);Assert.assertEquals(calls.first().draft,calls.last().draft);Assert.assertEquals(7,queues().values.sumOf{it.size})
    }

    @Test fun depositFromAnotherWalletMovesItsActualPairAndKeepsTheExistingLinkedAllocation() {
        prepare();compose.setContent{Screen()};open()
        compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo().performClick();await("investment.cash.transfer.wallet.option."+selected)
        compose.onNodeWithTag("investment.cash.transfer.wallet.option."+selected).performClick()
        compose.onNodeWithTag("investment.cash.transfer.sameWallet").assertDoesNotExist();save()
        val read=snapshot();val ledger=read.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        Assert.assertEquals("investmentCashDeposit",ledger.payload.financeRawString("settlement_role_raw_value"));Assert.assertEquals(selected,ledger.payload.financeRawString("source_wallet_id"));Assert.assertEquals(linked,ledger.payload.financeRawString("destination_wallet_id"))
        val balances=financeWalletBalancesRaw(owner,read.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(java.math.BigInteger.valueOf(9500),balances[selected]);Assert.assertEquals(java.math.BigInteger.valueOf(10500),balances[linked])
        Assert.assertEquals(java.math.BigInteger.valueOf(800),investmentCashFinancialView(read,"VND").availableMinor);Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun sameWalletWithdrawalReleasesBookedCashWithoutChangingAnyActualWalletBalance() {
        prepare();val wallets=snapshot().rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table};compose.setContent{Screen()};open(withdraw=true)
        compose.onNodeWithTag("investment.cash.transfer.sameWallet").assertExists();save()
        val read=snapshot();val ledger=read.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        Assert.assertEquals("investmentCashWithdrawal",ledger.payload.financeRawString("settlement_role_raw_value"));Assert.assertEquals(linked,ledger.payload.financeRawString("source_wallet_id"));Assert.assertEquals(linked,ledger.payload.financeRawString("destination_wallet_id"))
        Assert.assertEquals(java.math.BigInteger.valueOf(10000),investmentCashFinancialView(read,"VND").linkedActualMinor);Assert.assertEquals(java.math.BigInteger.ZERO,investmentCashFinancialView(read,"VND").availableMinor)
        Assert.assertEquals(wallets,read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table});Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun aChangedAccountingCurrencyCannotRelabelTheOldAmountEvenWhenNumericCapacityMatches() {
        prepare();compose.setContent{Screen()};open()
        // Restore an already changed legacy source; a new local protected currency edit is now forbidden.
        runBlocking{restoreLegacyInvestmentFixture(db,rows().map{row ->row.copy(payload=JsonObject(row.payload.mapValues{(key,value)->
            if(key in setOf("currency_code","accounting_currency_code"))JsonPrimitive("USD") else value
        }))}.map(::mutation))};await("investment.cash.transfer.conflict")
        val before=snapshot();val pending=queues()
        compose.onNodeWithTag("investment.cash.transfer.amount").assert(hasText("500",substring=false));compose.onNodeWithTag("investment.cash.transfer.save").assertIsNotEnabled()
        compose.onNodeWithTag("investment.cash.transfer.limit.amount").assertTextEquals(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(500,"VND"))
        compose.onNodeWithTag("investment.cash.transfer.retryRead").performScrollTo().performClick();await("investment.cash.transfer.conflict")
        compose.onNodeWithTag("investment.cash.transfer.amount").assert(hasText("500",substring=false));compose.onNodeWithTag("investment.cash.transfer.save").assertIsNotEnabled()
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues());compose.onNodeWithTag("investment.cash.transfer.cancel").performClick()
        open();compose.onNodeWithTag("investment.cash.transfer.amount").assert(hasText("5",substring=false));save()
        val ledger=snapshot().rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table};Assert.assertEquals("USD",ledger.payload.financeRawString("source_currency_code"));Assert.assertEquals(500L,ledger.payload.financeRawLong("amount_minor"))
    }
    @Test fun selectedCalendarDateAndClockValuesBecomeTheSameBackdatedLedgerAndPostingInstant() {
        prepare();compose.setContent{Screen()};open()
        tapAndAwait("investment.cash.transfer.date","investment.cash.transfer.date.dialog")
        val targetDate=java.time.LocalDate.now().withDayOfMonth(20)
        val day=hasText(targetDate.format(java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy",java.util.Locale.US))) and hasAnyAncestor(hasTestTag("investment.cash.transfer.date.dialog"))
        if(compose.onAllNodes(day).fetchSemanticsNodes().isEmpty())throw AssertionError("Calendar selection semantics: "+compose.onNodeWithTag("investment.cash.transfer.date.dialog").printToString())
        compose.onNode(day).performClick()
        compose.onNodeWithTag("investment.cash.transfer.date.confirm").performClick();compose.onNodeWithTag("investment.cash.transfer.date.dialog").assertDoesNotExist()
        tapAndAwait("investment.cash.transfer.time","investment.cash.transfer.time.dialog")
        val hour=if(java.time.ZonedDateTime.now().hour==14)15 else 14
        val minute=if(java.time.ZonedDateTime.now().minute==25)30 else 25
        val hourMatch=hasContentDescription(hour.toString()+" hours") and hasAnyAncestor(hasTestTag("investment.cash.transfer.time.dialog"))
        if(compose.onAllNodes(hourMatch).fetchSemanticsNodes().isEmpty())throw AssertionError("Clock selection semantics: "+compose.onNodeWithTag("investment.cash.transfer.time.dialog").printToString())
        compose.onAllNodes(hourMatch).onLast().performClick()
        val minuteMatch=hasContentDescription(minute.toString()+" minutes") and hasAnyAncestor(hasTestTag("investment.cash.transfer.time.dialog"))
        try{compose.waitUntil(5000){compose.onAllNodes(minuteMatch).fetchSemanticsNodes().isNotEmpty()}}catch(failure:Throwable){throw AssertionError("Minute selection semantics: "+compose.onNodeWithTag("investment.cash.transfer.time.dialog").printToString(),failure)}
        compose.onAllNodes(minuteMatch).onLast().performClick()
        compose.onNodeWithTag("investment.cash.transfer.time.confirm").performClick();compose.onNodeWithTag("investment.cash.transfer.time.dialog").assertDoesNotExist();save()
        val read=snapshot();val ledger=read.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        val created=java.time.Instant.parse(ledger.payload.financeRawString("created_at")).atZone(java.time.ZoneId.systemDefault())
        val selected=java.time.Instant.parse(ledger.payload.financeRawString("occurred_at")).atZone(java.time.ZoneId.systemDefault())
        Assert.assertEquals(created.toLocalDate().withDayOfMonth(20),selected.toLocalDate());Assert.assertEquals(hour,selected.hour);Assert.assertEquals(minute,selected.minute)
        val posting=read.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==ledger.id}
        Assert.assertEquals(ledger.payload.financeRawString("occurred_at"),posting.payload.financeRawString("occurred_at"));Assert.assertEquals(7,queues().values.sumOf{it.size})
    }

    @Test fun cashTransferFormsAndPickersFitThreeLanguagesBothThemesAtActual130And320Dp() {
        prepare()
        val context=ApplicationProvider.getApplicationContext<Context>()
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
        fun layout(tag:String,editable:Boolean=false) {
            val node=compose.onNodeWithTag(tag);val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val result=layouts.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true));Assert.assertFalse(result.didOverflowHeight)
            val width=if(editable)node.fetchSemanticsNode().boundsInRoot.width-32*context.resources.displayMetrics.density else result.size.width.toFloat()
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue("Clipped "+tag+": "+result.getLineRight(line)+" > "+width,result.getLineRight(line)<=width+1f);Assert.assertTrue(result.getLineLeft(line)>=-1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{code ->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
        }
        fun capture(kind:String,tag:String) {
            val bitmap=compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"investment-cash-transfer-"+kind+"-"+language+"-"+(if(dark)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        }
        try {
            for(withdraw in listOf(false,true)) {
                val base=rows().map{row ->row.copy(payload=JsonObject(row.payload+buildJsonObject {
                    if(row.id==linked)put("opening_balance_minor",Long.MAX_VALUE)
                    if(row.id==profitId)put("realized_profit_loss_minor",Long.MAX_VALUE)
                    if(withdraw && row.id==cashId){put("amount_minor",Long.MAX_VALUE);put("accounting_amount_minor",Long.MAX_VALUE)}
                }))}
                val profit=base.single{it.id==profitId}.let{it.copy(id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",payload=JsonObject(it.payload+("id" to JsonPrimitive("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))))}
                val extra=if(withdraw)listOf(base.single{it.id==cashId}.let{it.copy(id="cccccccc-cccc-4ccc-8ccc-cccccccccccc",payload=JsonObject(it.payload+("id" to JsonPrimitive("cccccccc-cccc-4ccc-8ccc-cccccccccccc"))))}) else emptyList()
                runBlocking{store.commitMutations((base+profit+extra).map(::mutation))}
                val expected=vn.com.quyln.mistia.core.designsystem.formatMinorUnits(if(withdraw)java.math.BigInteger.valueOf(Long.MAX_VALUE)*java.math.BigInteger.TWO else java.math.BigInteger.valueOf(300),"VND")
                compose.waitUntil(5000){compose.onAllNodes(hasTestTag("investment.cash.available") and hasText(expected)).fetchSemanticsNodes().isNotEmpty()}
                val kind=if(withdraw)"withdrawal" else "deposit"
                val before=snapshot();val pending=queues()
                for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                    compose.runOnIdle{configure(code);language=code;dark=theme};open(withdraw);compose.runOnIdle{configure(code)}
                    compose.onNodeWithTag("investment.cash.transfer.amount").performScrollTo().assert(hasText(if(withdraw)"9,223,372,036,854,775,807" else "9,223,372,036,854,775,507",substring=false));layout("investment.cash.transfer.amount",true)
                    compose.onNodeWithTag("investment.cash.transfer.wallet").performScrollTo();capture(kind+"-top","investment.cash.transfer.sheet")
                    compose.onNodeWithTag("investment.cash.transfer.limit.amount").performScrollTo();layout("investment.cash.transfer.limit.amount")
                    compose.onNodeWithTag("investment.cash.transfer.note").performScrollTo();capture(kind+"-bottom","investment.cash.transfer.sheet")
                    compose.onNodeWithTag("investment.cash.transfer.save").assertIsDisplayed().assertIsEnabled();compose.onNodeWithTag("investment.cash.transfer.cancel").assertIsDisplayed()
                    val left=compose.onNodeWithTag("investment.cash.transfer.cancel").fetchSemanticsNode().boundsInRoot
                    val right=compose.onNodeWithTag("investment.cash.transfer.save").fetchSemanticsNode().boundsInRoot;Assert.assertTrue(left.right<=right.left)
                    if(!withdraw) {
                        tapAndAwait("investment.cash.transfer.date","investment.cash.transfer.date.dialog");compose.runOnIdle{configure(code)}
                        compose.onNodeWithTag("investment.cash.transfer.date.confirm").assertIsDisplayed();capture("date","investment.cash.transfer.date.dialog");compose.onNodeWithTag("investment.cash.transfer.date.cancel").performClick()
                        tapAndAwait("investment.cash.transfer.time","investment.cash.transfer.time.dialog");compose.runOnIdle{configure(code)}
                        compose.onNodeWithTag("investment.cash.transfer.time.confirm").assertIsDisplayed();capture("time","investment.cash.transfer.time.dialog");compose.onNodeWithTag("investment.cash.transfer.time.cancel").performClick()
                    }
                    compose.onNodeWithTag("investment.cash.transfer.cancel").performClick();Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
                }
            }
        }finally{compose.runOnIdle{
            originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }}
    }

}
