package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class BillInvestmentPaymentScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="billFundPayAndUndoFitAllLanguagesThemesAtActual130And320Dp"){base.evaluate();return}
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
        }finally{shell("settings put system font_scale "+font);shell(if(size==null)"wm size reset"else "wm size "+size)}
    }}}).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val month=YearMonth.of(2026,10)
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var bill:RecurringBillPlanRecord
    private lateinit var wallet:LedgerWalletRecord
    @Before fun open()=runBlocking<Unit> {
        val context=ApplicationProvider.getApplicationContext<Context>()
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner});val catalog=systemCategoryCatalog(context)
        repo=OfflineFirstFinanceRepository(store,zone,catalog)
        repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        val category=repo.observeCategories(owner).first().first{it.kind==TransactionCategoryKind.EXPENSE && it.hierarchyRole==CategoryHierarchyRole.CHILD && !it.isArchived}
        wallet=repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        bill=repo.saveRecurringBill(owner,RecurringBillDraft("Bill seventy",category.id,70,wallet.id,"JPY",paymentStartDay=1,zoneId=zone),device,now).getOrThrow()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",wallet.id);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
    }
    private suspend fun source()=CloudEntity.entries.associateWith{store.recordsIncludingDeleted(owner,it.table)}
    private suspend fun queues()=CloudEntity.entries.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    private fun awaitTag(tag:String)=compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}
    @Test fun actualBillSheetReviewsThirtyReservedMinorBeforePayingAndCancellationWritesNothing()=runBlocking<Unit> {
        val due=recurringBillDueRows(owner,listOf(bill),emptyList(),month,zone).single()
        val before=source();val queued=queues();var closed by mutableStateOf(false)
        val failures=mutableListOf<Throwable>();var attempts=0
        compose.setContent{MistiaTheme(darkTheme=false){if(!closed)BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={request->repo.payRecurringBill(owner,request,device,Instant.now().toString()).also{attempts++;it.exceptionOrNull()?.let(failures::add)}},
            onUndo={Result.failure(IllegalStateException("Pay fixture cannot undo"))},onDismiss={closed=true})}}
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("bill.confirmPayment").performClick()
        compose.waitUntil(5000){attempts==1}
        Assert.assertTrue("Expected explicit fund review, got "+failures.lastOrNull(),failures.lastOrNull() is InvestmentFundUsageConfirmationRequired)
        awaitTag("bill.funds.review");Assert.assertEquals(before,source());Assert.assertEquals(queued,queues())
        compose.onNodeWithTag("bill.funds.cancel").performClick();compose.onNodeWithTag("bill.paymentSheet").assertExists()
        Assert.assertFalse(closed);Assert.assertEquals(before,source());Assert.assertEquals(queued,queues())
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("bill.confirmPayment").performClick();awaitTag("bill.funds.review")
        compose.onNodeWithTag("bill.funds.confirm").performClick();compose.waitUntil(5000){closed}
        val expense=repo.observeTransactions(owner).first().single{it.primaryKind==TransactionPrimaryKind.EXPENSE}
        Assert.assertEquals(70L,expense.amountMinor);Assert.assertEquals(wallet.id,expense.sourceWalletId)
        val cycle=repo.observeDueOccurrences(owner).first().single();Assert.assertEquals(DueStatus.PAID,cycle.status)
        Assert.assertEquals(expense.id,cycle.linkedTransactionId);Assert.assertEquals(70L,cycle.amountMinorSnapshot)
        val consumption=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(expense.id,"cash-consumption-booked"))!!
        Assert.assertEquals(-30L,consumption.payload.financeRawLong("amount_minor"));Assert.assertNull(consumption.deletedAt)
        Assert.assertEquals(1,failures.filterIsInstance<InvestmentFundUsageConfirmationRequired>().map{it.review.consent.transactionId}.distinct().size)
        Assert.assertEquals(expense.id,failures.filterIsInstance<InvestmentFundUsageConfirmationRequired>().last().review.consent.transactionId)
    }
    private fun due()=runBlocking{recurringBillDueRows(owner,listOf(bill),repo.observeDueOccurrences(owner).first(),month,zone).single()}
    private fun submitToFundReview() {
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("bill.confirmPayment").performClick();awaitTag("bill.funds.review")
    }
    private fun seedPaid()=runBlocking {
        val request=BillPaymentRequest(RecordId(bill.id),month,RecordId(wallet.id),70,expectedBill=bill,
            investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),"2026-10-23T00:01:00Z"),"JPY","Adjustment"))
        val review=(repo.payRecurringBill(owner,request,device,"2026-10-23T00:01:00Z").exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        repo.payRecurringBill(owner,request.copy(investment=request.investment!!.copy(consent=review.consent)),device,"2026-10-23T00:01:00Z").getOrThrow()
    }
    @Test fun actualUndoSheetRestoresFundsOnlyAfterItsSeparateConfirmation()=runBlocking<Unit> {
        seedPaid();val due=due();val before=source();val queue=queues();var closed by mutableStateOf(false)
        compose.setContent{MistiaTheme(darkTheme=false){if(!closed)BillPaymentSheet(owner.value,due,month,listOf(wallet),true,
            onPay={Result.failure(IllegalStateException("Undo cannot pay"))},onUndo={error("Must use the atomic fund-aware undo")},onDismiss={closed=true},
            onInvestmentUndo={repo.undoRecurringBillPaymentWithInvestmentFunds(owner,it,device,Instant.now().toString())})}}
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();awaitTag("bill.funds.review")
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
        compose.onNodeWithTag("bill.funds.cancel").performClick();Assert.assertFalse(closed);Assert.assertEquals(before,source())
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();awaitTag("bill.funds.review");compose.onNodeWithTag("bill.funds.confirm").performClick()
        compose.waitUntil(5000){closed}
        Assert.assertNotNull(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.deletedAt)
        Assert.assertNotNull(store.record(owner,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(id(20),"cash-consumption-booked"))!!.deletedAt)
        Assert.assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table).all{it.deletedAt!=null})
    }
    @Test fun pendingActualFundPaymentDisablesBothFundActionsUntilRoomCompletes() {
        val due=due();var closed=false;val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>()
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={request->if(request.investment?.consent!=null){entered.complete(Unit);finish.await()};repo.payRecurringBill(owner,request,device,Instant.now().toString())},
            onUndo={Result.success(Unit)},onDismiss={closed=true})}}
        submitToFundReview();compose.onNodeWithTag("bill.funds.confirm").performClick();compose.waitUntil(5000){entered.isCompleted}
        compose.onNodeWithTag("bill.funds.confirm").assertIsNotEnabled();compose.onNodeWithTag("bill.funds.cancel").assertIsNotEnabled()
        Assert.assertFalse(closed);Assert.assertTrue(runBlocking{repo.observeTransactions(owner).first()}.isEmpty())
        finish.complete(Unit);compose.waitUntil(5000){closed};Assert.assertEquals(70L,runBlocking{repo.observeTransactions(owner).first().single()}.amountMinor)
    }
    @Test fun changingTheHiddenWalletSourceRejectsConsentAndRequiresANewExplicitAttempt()=runBlocking<Unit> {
        val due=due();var closed=false;val previews=mutableListOf<InvestmentFundUsageReview>()
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={request->repo.payRecurringBill(owner,request,device,Instant.now().toString()).also{(it.exceptionOrNull() as? InvestmentFundUsageConfirmationRequired)?.review?.let(previews::add)}},
            onUndo={Result.success(Unit)},onDismiss={closed=true})}}
        submitToFundReview()
        val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)!!;val changed=old.copy(payload=JsonObject(old.payload+("opening_balance_minor" to JsonPrimitive(101L))))
        store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,changed.id,owner.value,MutationKind.UPSERT,changed.payload,now,changed.syncVersion,device))
        val before=source();val queue=queues();compose.onNodeWithTag("bill.funds.confirm").performClick();awaitTag("bill.paymentError")
        Assert.assertFalse(closed);Assert.assertEquals(before,source());Assert.assertEquals(queue,queues());Assert.assertEquals(1,previews.size)
        submitToFundReview();Assert.assertEquals(2,previews.size);Assert.assertEquals(29L,previews.last().comparison.primaryChange!!.proposedMinor.longValueExact())
        compose.onNodeWithTag("bill.funds.confirm").performClick();compose.waitUntil(5000){closed}
    }
    @Test fun nonCancellableOldRepositoryCompletionCannotDismissOrChangeTheReplacementForm() {
        val due=due();val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>();var closed=0
        val old=object:FinanceRepository by repo {override suspend fun payRecurringBill(owner:UserId,request:BillPaymentRequest,deviceId:String,now:String):Result<SavedBillPayment> {
            if(request.investment?.consent==null)return repo.payRecurringBill(owner,request,deviceId,now)
            return withContext(NonCancellable){entered.complete(Unit);finish.await();Result.failure(java.io.IOException("late previous dependency"))}
        }}
        var current by mutableStateOf<FinanceRepository>(old)
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={current.payRecurringBill(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={closed++},operationScopeKey=current)}}
        submitToFundReview();compose.onNodeWithTag("bill.funds.confirm").performClick();compose.waitUntil(5000){entered.isCompleted}
        compose.runOnIdle{current=repo};compose.onNodeWithTag("bill.funds.review").assertDoesNotExist()
        finish.complete(Unit);compose.waitForIdle();Assert.assertEquals(0,closed)
        compose.onNodeWithTag("bill.paymentSheet").assertExists();compose.onNodeWithTag("bill.paymentError").assertDoesNotExist()
    }
    @Test fun replacingOwnerWhileFundReviewIsOpenHidesEveryOldPrivateSourceAndAction() {
        val due=due();var subject by mutableStateOf(owner.value)
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(subject,due,month,listOf(wallet),false,
            onPay={repo.payRecurringBill(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={})}}
        submitToFundReview();compose.runOnIdle{subject=id(99)}
        compose.onNodeWithTag("bill.funds.review").assertDoesNotExist();compose.onAllNodesWithText(bill.name).assertCountEquals(0)
        compose.onNodeWithTag("bill.paymentSheet").assertDoesNotExist();Assert.assertTrue(runBlocking{repo.observeTransactions(owner).first()}.isEmpty())
    }
    @Test fun aMixedWalletInputCannotRevealAnotherOwnersNameInsideTheFundReview() {
        val due=due();val foreign=wallet.copy(ownerUserId=id(99),name="Other owner secret")
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(foreign,wallet),false,
            onPay={repo.payRecurringBill(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={})}}
        submitToFundReview();compose.onAllNodesWithText("Other owner secret").assertCountEquals(0)
        compose.onNodeWithTag("bill.funds.name."+wallet.id).assertTextEquals(wallet.name)
    }
    @Test fun savedFormRestorationRetainsItsIdentityButNeverRestoresConsentOrReplaysPayment()=runBlocking<Unit> {
        val restoration=StateRestorationTester(compose);val due=due();val previews=mutableListOf<InvestmentFundUsageReview>()
        restoration.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={request->repo.payRecurringBill(owner,request,device,Instant.now().toString()).also{(it.exceptionOrNull() as? InvestmentFundUsageConfirmationRequired)?.review?.let(previews::add)}},
            onUndo={Result.success(Unit)},onDismiss={})}}
        submitToFundReview();val before=source();val queue=queues();Assert.assertEquals(1,previews.size)
        restoration.emulateSavedInstanceStateRestore();compose.waitForIdle()
        compose.onNodeWithTag("bill.funds.review").assertDoesNotExist();compose.onNodeWithTag("bill.paymentConfirmation").assertDoesNotExist()
        Assert.assertEquals(1,previews.size);Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
        submitToFundReview();Assert.assertEquals(2,previews.size);Assert.assertEquals(previews.first().consent.transactionId,previews.last().consent.transactionId)
    }

    @Test fun lostResponseAfterActualCommitRetriesWithoutAnySecondFinancialWrite()=runBlocking<Unit> {
        val due=due();var closed=false;var lost=false;var writesAfterCommit:Map<CloudEntity,List<CloudRecord>>?=null
        var queuesAfterCommit:Map<CloudEntity,List<QueuedMutation>>?=null
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={request->val result=repo.payRecurringBill(owner,request,device,Instant.now().toString())
                if(result.isSuccess && !lost){lost=true;writesAfterCommit=source();queuesAfterCommit=queues();Result.failure(java.io.IOException("lost committed response"))}else result},
            onUndo={Result.success(Unit)},onDismiss={closed=true})}}
        submitToFundReview();compose.onNodeWithTag("bill.funds.confirm").performClick();awaitTag("bill.paymentError")
        Assert.assertFalse(closed);Assert.assertTrue(lost)
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("bill.confirmPayment").performClick()
        compose.waitUntil(5000){closed};Assert.assertEquals(writesAfterCommit,source());Assert.assertEquals(queuesAfterCommit,queues())
    }
    @Test fun actualPrimaryCurrencyIsUsedToRejectForeignReservedFundsWithLocalizedExplanation()=runBlocking<Unit> {
        val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)!!
        val vnd=old.copy(payload=JsonObject(old.payload+("currency_code" to JsonPrimitive("VND"))+("opening_balance_minor" to JsonPrimitive(100_000L))));run {
            // Model an existing legacy FX reserve; the generic wallet writer must keep rejecting this change.
            val queue = db.syncOutboxDao().record(owner.value, vnd.entity, vnd.id)!!
            db.cloudRecordDao().upsert(CloudRecordEntity(vnd.ownerUserId, vnd.entity, vnd.id, vnd.payload.toString(), vnd.updatedAt, vnd.deletedAt, vnd.syncVersion, true, 0))
            db.syncOutboxDao().upsert(queue.copy(payloadJson = vnd.payload.toString()))
            Assert.assertEquals("VND", LedgerWalletRecord.fromCloudRecord(store.record(owner, vnd.entity, vnd.id)!!).currencyCode)
            Assert.assertEquals(vnd.payload.toString(), db.syncOutboxDao().record(owner.value, vnd.entity, vnd.id)!!.payloadJson)
        }
        wallet=LedgerWalletRecord.fromCloudRecord(vnd)
        val raw=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!;val posting=raw.copy(payload=JsonObject(raw.payload+buildJsonObject{put("currency_code","VND");put("amount_minor",40_000L);put("accounting_amount_minor",2L)}))
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
        bill=bill.copy(currencyCode="VND",amountMinor=70_000);store.commitMutation(bill.toCloudRecord(),bill.pendingMutation())
        val due=due();val before=source();val queue=queues()
        compose.setContent{MistiaTheme(darkTheme=false){BillPaymentSheet(owner.value,due,month,listOf(wallet),false,
            onPay={repo.payRecurringBill(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={},primaryCurrencyCode="JPY")}}
        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("bill.confirmPayment").performClick();awaitTag("bill.paymentError")
        val context=ApplicationProvider.getApplicationContext<Context>()
        compose.onNodeWithTag("bill.paymentError").assertTextEquals(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_error_fund_usage_currency_mismatch))
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues());compose.onNodeWithTag("bill.funds.review").assertDoesNotExist()
    }
    @Test fun billFundPayAndUndoFitAllLanguagesThemesAtActual130And320Dp() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        runBlocking {
            val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)!!
            val raw=old.copy(payload=JsonObject(old.payload+buildJsonObject{put("opening_balance_minor",Long.MAX_VALUE);put("name","Investment reserve / 投資資金 / Quỹ đầu tư")}))
            store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device));wallet=LedgerWalletRecord.fromCloudRecord(raw)
            val previous=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!
            val posting=previous.copy(payload=JsonObject(previous.payload+("amount_minor" to JsonPrimitive(Long.MAX_VALUE))+("accounting_amount_minor" to JsonPrimitive(Long.MAX_VALUE))))
            store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
            bill=bill.copy(name="Household Internet / 家庭の通信費 / Hóa đơn mạng gia đình",amountMinor=Long.MAX_VALUE);store.commitMutation(bill.toCloudRecord(),bill.pendingMutation())
        }
        var language by mutableStateOf("en");var dark by mutableStateOf(false);var undoMode by mutableStateOf(false);var generation by mutableIntStateOf(0)
        var row by mutableStateOf(due())
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String) {
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            }
            windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        compose.setContent {
            val configuration=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(configuration),androidx.compose.ui.platform.LocalConfiguration provides configuration) {
                key(language,dark,undoMode,generation){MistiaTheme(darkTheme=dark){BillPaymentSheet(owner.value,row,month,listOf(wallet),undoMode,
                    onPay={repo.payRecurringBill(owner,it,device,Instant.now().toString())},onUndo={error("Use investment undo")},onDismiss={},
                    onInvestmentUndo={repo.undoRecurringBillPaymentWithInvestmentFunds(owner,it,device,Instant.now().toString())})}}
            }
        }
        fun complete(tag:String) {
            val results=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(results)}
            val layout=results.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertFalse(tag,layout.didOverflowHeight);Assert.assertEquals(tag,layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(line in 0 until layout.lineCount){Assert.assertFalse(layout.isLineEllipsized(line));Assert.assertTrue(layout.getLineLeft(line)>=-1f);Assert.assertTrue(layout.getLineRight(line)<=layout.size.width+1f)}
            val paint=android.graphics.Paint();layout.layoutInput.text.text.codePoints().forEach{code->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
        }
        fun capture(mode:String,code:String,theme:Boolean) {
            compose.waitForIdle();val screenshot=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
            java.io.File(context.getExternalFilesDir(null),"bill-funds-"+mode+"-"+code+"-"+(if(theme)"dark"else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
        }
        try {
            for(mode in listOf(false,true)) {
                if(mode)runBlocking {
                    val r=BillPaymentRequest(RecordId(bill.id),month,RecordId(wallet.id),Long.MAX_VALUE,expectedBill=bill,investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),"2026-10-23T00:01:00Z"),"JPY","Adjustment"))
                    val review=(repo.payRecurringBill(owner,r,device,"2026-10-23T00:01:00Z").exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
                    repo.payRecurringBill(owner,r.copy(investment=r.investment!!.copy(consent=review.consent)),device,"2026-10-23T00:01:00Z").getOrThrow()
                }
                val before=runBlocking{source()};val queue=runBlocking{queues()}
                for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                    compose.runOnIdle{configure(code);language=code;dark=theme;undoMode=mode;row=due();generation++};compose.waitForIdle();compose.runOnIdle{configure(code)}
                    if(!mode) {
                        compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick();awaitTag("bill.paymentConfirmation");compose.runOnIdle{configure(code)}
                        complete("bill.confirmationAmount");capture("confirmation",code,theme)
                        compose.onNodeWithTag("bill.confirmPayment").performClick()
                    }else compose.onNodeWithTag("bill.submitPayment").performScrollTo().performClick()
                    awaitTag("bill.funds.review");compose.runOnIdle{configure(code)}
                    for(tag in listOf("bill.funds.title","bill.funds.name."+wallet.id,"bill.funds.message."+wallet.id,"bill.funds.confirm.text","bill.funds.cancel.text"))complete(tag)
                    val confirm=compose.onNodeWithTag("bill.funds.confirm").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                    val cancel=compose.onNodeWithTag("bill.funds.cancel").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                    Assert.assertFalse(confirm.overlaps(cancel));Assert.assertTrue(confirm.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(cancel.height>=48*context.resources.displayMetrics.density-1)
                    capture(if(mode)"restore"else "use",code,theme)
                    compose.onNodeWithTag("bill.funds.cancel").performClick();Assert.assertEquals(before,runBlocking{source()});Assert.assertEquals(queue,runBlocking{queues()})
                }
            }
        }finally{compose.runOnIdle{originals.forEach{(resource,configuration)->resource.updateConfiguration(configuration,resource.displayMetrics)}}}
    }

    @Test fun actualUpcomingBillRouteRetriesACommittedPaymentAfterObserverChangesTheCycleToPaid()=runBlocking<Unit> {
        var lost=false;var closed=false
        val controlled=object:FinanceRepository by repo {
            override suspend fun payRecurringBill(owner:UserId,request:BillPaymentRequest,deviceId:String,now:String):Result<SavedBillPayment> {
                val result=repo.payRecurringBill(owner,request,deviceId,now)
                return if(result.isSuccess && !lost){lost=true;Result.failure(java.io.IOException("lost committed bill response"))}else result
            }
        }
        compose.setContent{MistiaTheme(darkTheme=false){if(!closed)UpcomingRecurringPaymentSheet(owner,UpcomingDuePaymentTarget(owner.value,DueSourceKind.RECURRING_BILL,bill.id,month),controlled,{device},{closed=true})}}
        awaitTag("bill.submitPayment");submitToFundReview();compose.onNodeWithTag("bill.funds.confirm").performClick()
        awaitTag("bill.paymentError");awaitTag("bill.paymentStale")
        Assert.assertTrue(lost);val before=source();val queue=queues()
        compose.onNodeWithTag("bill.retryPayment").performScrollTo().performClick();compose.waitUntil(5000){closed}
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }

}
