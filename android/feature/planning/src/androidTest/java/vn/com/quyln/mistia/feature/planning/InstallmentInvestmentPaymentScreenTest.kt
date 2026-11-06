package vn.com.quyln.mistia.feature.planning

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
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
class InstallmentInvestmentPaymentScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName!="installmentFundPayAndUndoFitAllLanguagesThemesAtActual130And320Dp"){base.evaluate();return}
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
    private lateinit var plan:InstallmentPlanRecord
    private lateinit var wallet:LedgerWalletRecord
    @Before fun open()=runBlocking<Unit> {
        val context=ApplicationProvider.getApplicationContext<Context>()
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner});val catalog=systemCategoryCatalog(context)
        repo=OfflineFirstFinanceRepository(store,zone,catalog)
        repo.ensureDefaultSystemCategories(owner,catalog,device,now).getOrThrow()
        wallet=repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        plan=InstallmentPlanRecord(id(50),owner.value,"Installment seventy","mistia.plan.loan",70,23,12,1,wallet.id,"JPY",false,now,now,null,0,device)
        store.commitMutation(plan.toCloudRecord(),PendingMutation(CloudEntity.INSTALLMENT_PLAN,plan.id,owner.value,MutationKind.UPSERT,plan.toPayload(),now,0,device))
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
    @Test fun actualInstallmentSheetReviewsThirtyReservedMinorBeforePayingAndCancelWritesNothing()=runBlocking<Unit> {
        val due=installmentDueRows(owner,listOf(plan),emptyList(),month,zone).single()
        val before=source();val queued=queues();var closed by mutableStateOf(false)
        val failures=mutableListOf<Throwable>();var attempts=0
        compose.setContent{MistiaTheme(darkTheme=false){if(!closed)InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={request->repo.payInstallment(owner,request,device,Instant.now().toString()).also{attempts++;it.exceptionOrNull()?.let(failures::add)}},
            onUndo={Result.failure(IllegalStateException("Pay fixture cannot undo"))},onDismiss={closed=true})}}
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("installment.confirmPayment").performClick()
        compose.waitUntil(5000){attempts==1}
        Assert.assertTrue("Expected explicit fund review, got "+failures.lastOrNull(),failures.lastOrNull() is InvestmentFundUsageConfirmationRequired)
        awaitTag("installment.funds.review");Assert.assertEquals(before,source());Assert.assertEquals(queued,queues())
        compose.onNodeWithTag("installment.funds.cancel").performClick();Assert.assertFalse(closed)
        Assert.assertEquals(before,source());Assert.assertEquals(queued,queues())
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("installment.confirmPayment").performClick();awaitTag("installment.funds.review")
        compose.onNodeWithTag("installment.funds.confirm").performClick();compose.waitUntil(5000){closed}
        val expense=repo.observeTransactions(owner).first().single{it.primaryKind==TransactionPrimaryKind.EXPENSE}
        Assert.assertEquals(70L,expense.amountMinor);Assert.assertEquals(wallet.id,expense.sourceWalletId)
        val cycle=repo.observeDueOccurrences(owner).first().single();Assert.assertEquals("installment",cycle.sourceKindWireValue)
        Assert.assertEquals(expense.id,cycle.linkedTransactionId);Assert.assertEquals(70L,cycle.amountMinorSnapshot)
        val consumption=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(expense.id,"cash-consumption-booked"))!!
        Assert.assertEquals(-30L,consumption.payload.financeRawLong("amount_minor"));Assert.assertNull(consumption.deletedAt)
    }
    private suspend fun putPlan() {
        val row=plan.toCloudRecord()
        store.commitMutation(row,PendingMutation(CloudEntity.INSTALLMENT_PLAN,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
    }
    private fun due()=runBlocking{installmentDueRows(owner,listOf(plan),repo.observeDueOccurrences(owner).first(),month,zone).single()}
    private fun submitToFundReview() {
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("installment.confirmPayment").performClick();awaitTag("installment.funds.review")
    }
    private fun seedPaid()=runBlocking {
        val request=InstallmentPaymentRequest(plan,month,RecordId(wallet.id),70,
            investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),"2026-10-23T00:01:00Z"),"JPY","Adjustment"))
        val review=(repo.payInstallment(owner,request,device,"2026-10-23T00:01:00Z").exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        repo.payInstallment(owner,request.copy(investment=request.investment!!.copy(consent=review.consent)),device,"2026-10-23T00:01:00Z").getOrThrow()
    }
    @Test fun actualUndoSheetRestoresFundsOnlyAfterItsSeparateConfirmation()=runBlocking<Unit> {
        seedPaid();val due=due();val before=source();val queue=queues();var closed by mutableStateOf(false)
        compose.setContent{MistiaTheme(darkTheme=false){if(!closed)InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={Result.failure(IllegalStateException("Undo cannot pay"))},onUndo={error("Must use the atomic fund-aware undo")},onDismiss={closed=true},
            onInvestmentUndo={repo.undoInstallmentPaymentWithInvestmentFunds(owner,it,device,Instant.now().toString())})}}
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();awaitTag("installment.funds.review")
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
        compose.onNodeWithTag("installment.funds.cancel").performClick();Assert.assertFalse(closed);Assert.assertEquals(before,source())
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();awaitTag("installment.funds.review");compose.onNodeWithTag("installment.funds.confirm").performClick()
        compose.waitUntil(5000){closed}
        Assert.assertNotNull(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.deletedAt)
        Assert.assertNotNull(store.record(owner,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(id(20),"cash-consumption-booked"))!!.deletedAt)
        Assert.assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table).all{it.deletedAt!=null})
    }
    @Test fun pendingActualFundPaymentDisablesBothFundActionsUntilRoomCompletes() {
        val due=due();var closed=false;val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>()
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={request->if(request.investment?.consent!=null){entered.complete(Unit);finish.await()};repo.payInstallment(owner,request,device,Instant.now().toString())},
            onUndo={Result.success(Unit)},onDismiss={closed=true})}}
        submitToFundReview();compose.onNodeWithTag("installment.funds.confirm").performClick();compose.waitUntil(5000){entered.isCompleted}
        compose.onNodeWithTag("installment.funds.confirm").assertIsNotEnabled();compose.onNodeWithTag("installment.funds.cancel").assertIsNotEnabled()
        Assert.assertFalse(closed);Assert.assertTrue(runBlocking{repo.observeTransactions(owner).first()}.isEmpty())
        finish.complete(Unit);compose.waitUntil(5000){closed};Assert.assertEquals(70L,runBlocking{repo.observeTransactions(owner).first().single()}.amountMinor)
    }
    @Test fun changingTheHiddenWalletSourceRejectsConsentAndRequiresANewExplicitAttempt()=runBlocking<Unit> {
        val due=due();var closed=false;val previews=mutableListOf<InvestmentFundUsageReview>()
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={request->repo.payInstallment(owner,request,device,Instant.now().toString()).also{(it.exceptionOrNull() as? InvestmentFundUsageConfirmationRequired)?.review?.let(previews::add)}},
            onUndo={Result.success(Unit)},onDismiss={closed=true})}}
        submitToFundReview()
        val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)!!;val changed=old.copy(payload=JsonObject(old.payload+("opening_balance_minor" to JsonPrimitive(101L))))
        store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,changed.id,owner.value,MutationKind.UPSERT,changed.payload,now,changed.syncVersion,device))
        val before=source();val queue=queues();compose.onNodeWithTag("installment.funds.confirm").performClick();awaitTag("installment.paymentError")
        Assert.assertFalse(closed);Assert.assertEquals(before,source());Assert.assertEquals(queue,queues());Assert.assertEquals(1,previews.size)
        submitToFundReview();Assert.assertEquals(2,previews.size);Assert.assertEquals(29L,previews.last().comparison.primaryChange!!.proposedMinor.longValueExact())
        compose.onNodeWithTag("installment.funds.confirm").performClick();compose.waitUntil(5000){closed}
    }
    @Test fun nonCancellableOldRepositoryCompletionCannotDismissOrChangeTheReplacementForm() {
        val due=due();val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>();var closed=0
        val old=object:FinanceRepository by repo {override suspend fun payInstallment(owner:UserId,request:InstallmentPaymentRequest,deviceId:String,now:String):Result<SavedInstallmentPayment> {
            if(request.investment?.consent==null)return repo.payInstallment(owner,request,deviceId,now)
            return withContext(NonCancellable){entered.complete(Unit);finish.await();Result.failure(java.io.IOException("late previous dependency"))}
        }}
        var current by mutableStateOf<FinanceRepository>(old)
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={current.payInstallment(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={closed++},operationScopeKey=current)}}
        submitToFundReview();compose.onNodeWithTag("installment.funds.confirm").performClick();compose.waitUntil(5000){entered.isCompleted}
        compose.runOnIdle{current=repo};compose.onNodeWithTag("installment.funds.review").assertDoesNotExist()
        finish.complete(Unit);compose.waitForIdle();Assert.assertEquals(0,closed)
        compose.onNodeWithTag("installment.paymentSheet").assertExists();compose.onNodeWithTag("installment.paymentError").assertDoesNotExist()
    }
    @Test fun replacingOwnerWhileFundReviewIsOpenHidesEveryOldPrivateSourceAndAction() {
        val due=due();var subject by mutableStateOf(owner.value)
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(subject,due,listOf(wallet),
            onPay={repo.payInstallment(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={})}}
        submitToFundReview();compose.runOnIdle{subject=id(99)}
        compose.onNodeWithTag("installment.funds.review").assertDoesNotExist();compose.onAllNodesWithText(plan.name).assertCountEquals(0)
        compose.onNodeWithTag("installment.paymentSheet").assertDoesNotExist();Assert.assertTrue(runBlocking{repo.observeTransactions(owner).first()}.isEmpty())
    }
    @Test fun aMixedWalletInputCannotRevealAnotherOwnersNameInsideTheFundReview() {
        val due=due();val foreign=wallet.copy(ownerUserId=id(99),name="Other owner secret")
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(foreign,wallet),
            onPay={repo.payInstallment(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={})}}
        submitToFundReview();compose.onAllNodesWithText("Other owner secret").assertCountEquals(0)
        compose.onNodeWithTag("installment.funds.name."+wallet.id).assertTextEquals(wallet.name)
    }
    @Test fun savedFormRestorationRetainsItsIdentityButNeverRestoresConsentOrReplaysPayment()=runBlocking<Unit> {
        val restoration=StateRestorationTester(compose);val due=due();val previews=mutableListOf<InvestmentFundUsageReview>()
        restoration.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={request->repo.payInstallment(owner,request,device,Instant.now().toString()).also{(it.exceptionOrNull() as? InvestmentFundUsageConfirmationRequired)?.review?.let(previews::add)}},
            onUndo={Result.success(Unit)},onDismiss={})}}
        submitToFundReview();val before=source();val queue=queues();Assert.assertEquals(1,previews.size)
        restoration.emulateSavedInstanceStateRestore();compose.waitForIdle()
        compose.onNodeWithTag("installment.funds.review").assertDoesNotExist();compose.onNodeWithTag("installment.paymentConfirmation").assertDoesNotExist()
        Assert.assertEquals(1,previews.size);Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
        submitToFundReview();Assert.assertEquals(2,previews.size);Assert.assertEquals(previews.first().consent.transactionId,previews.last().consent.transactionId)
    }

    @Test fun lostResponseAfterActualCommitRetriesWithoutAnySecondFinancialWrite()=runBlocking<Unit> {
        val due=due();var closed=false;var lost=false;var writesAfterCommit:Map<CloudEntity,List<CloudRecord>>?=null
        var queuesAfterCommit:Map<CloudEntity,List<QueuedMutation>>?=null
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={request->val result=repo.payInstallment(owner,request,device,Instant.now().toString())
                if(result.isSuccess && !lost){lost=true;writesAfterCommit=source();queuesAfterCommit=queues();Result.failure(java.io.IOException("lost committed response"))}else result},
            onUndo={Result.success(Unit)},onDismiss={closed=true})}}
        submitToFundReview();compose.onNodeWithTag("installment.funds.confirm").performClick();awaitTag("installment.paymentError")
        Assert.assertFalse(closed);Assert.assertTrue(lost)
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("installment.confirmPayment").performClick()
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
        plan=plan.copy(currencyCode="VND",amountPerCycleMinor=70_000);putPlan()
        val due=due();val before=source();val queue=queues()
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,due,listOf(wallet),
            onPay={repo.payInstallment(owner,it,device,Instant.now().toString())},onUndo={Result.success(Unit)},onDismiss={},primaryCurrencyCode="JPY")}}
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("installment.confirmPayment").performClick();awaitTag("installment.paymentError")
        val context=ApplicationProvider.getApplicationContext<Context>()
        compose.onNodeWithTag("installment.paymentError").assertTextEquals(context.getString(vn.com.quyln.mistia.core.designsystem.R.string.investment_error_fund_usage_currency_mismatch))
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues());compose.onNodeWithTag("installment.funds.review").assertDoesNotExist()
    }
    @Test fun installmentFundPayAndUndoFitAllLanguagesThemesAtActual130And320Dp() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        runBlocking {
            val old=store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)!!
            val raw=old.copy(payload=JsonObject(old.payload+buildJsonObject{put("opening_balance_minor",Long.MAX_VALUE);put("name","Investment reserve / 投資資金 / Quỹ đầu tư")}))
            store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device));wallet=LedgerWalletRecord.fromCloudRecord(raw)
            val previous=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!
            val posting=previous.copy(payload=JsonObject(previous.payload+("amount_minor" to JsonPrimitive(Long.MAX_VALUE))+("accounting_amount_minor" to JsonPrimitive(Long.MAX_VALUE))))
            store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
            plan=plan.copy(name="Household Internet / 家庭の通信費 / Hóa đơn mạng gia đình",amountPerCycleMinor=Long.MAX_VALUE);putPlan()
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
                key(language,dark,undoMode,generation){MistiaTheme(darkTheme=dark){InstallmentPaymentSheet(owner.value,row,listOf(wallet),
                    onPay={repo.payInstallment(owner,it,device,Instant.now().toString())},onUndo={error("Use investment undo")},onDismiss={},
                    onInvestmentUndo={repo.undoInstallmentPaymentWithInvestmentFunds(owner,it,device,Instant.now().toString())})}}
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
            java.io.File(context.getExternalFilesDir(null),"installment-funds-"+mode+"-"+code+"-"+(if(theme)"dark"else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
        }
        try {
            for(mode in listOf(false,true)) {
                if(mode)runBlocking {
                    val r=InstallmentPaymentRequest(plan,month,RecordId(wallet.id),Long.MAX_VALUE,investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),"2026-10-23T00:01:00Z"),"JPY","Adjustment"))
                    val review=(repo.payInstallment(owner,r,device,"2026-10-23T00:01:00Z").exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
                    repo.payInstallment(owner,r.copy(investment=r.investment!!.copy(consent=review.consent)),device,"2026-10-23T00:01:00Z").getOrThrow()
                }
                val before=runBlocking{source()};val queue=runBlocking{queues()}
                for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                    compose.runOnIdle{configure(code);language=code;dark=theme;undoMode=mode;row=due();generation++};compose.waitForIdle();compose.runOnIdle{configure(code)}
                    if(!mode) {
                        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();awaitTag("installment.paymentConfirmation");compose.runOnIdle{configure(code)}
                        complete("installment.confirmationAmount");capture("confirmation",code,theme)
                        compose.onNodeWithTag("installment.confirmPayment").performClick()
                    }else compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick()
                    awaitTag("installment.funds.review");compose.runOnIdle{configure(code)}
                    for(tag in listOf("installment.funds.title","installment.funds.name."+wallet.id,"installment.funds.message."+wallet.id,"installment.funds.confirm.text","installment.funds.cancel.text"))complete(tag)
                    val confirm=compose.onNodeWithTag("installment.funds.confirm").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                    val cancel=compose.onNodeWithTag("installment.funds.cancel").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                    Assert.assertFalse(confirm.overlaps(cancel));Assert.assertTrue(confirm.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(cancel.height>=48*context.resources.displayMetrics.density-1)
                    capture(if(mode)"restore"else "use",code,theme)
                    compose.onNodeWithTag("installment.funds.cancel").performClick();Assert.assertEquals(before,runBlocking{source()});Assert.assertEquals(queue,runBlocking{queues()})
                }
            }
        }finally{compose.runOnIdle{originals.forEach{(resource,configuration)->resource.updateConfiguration(configuration,resource.displayMetrics)}}}
    }

    @Test fun actualDuePaneRetriesACommittedPaymentAfterObserverChangesTheCycleToPaid()=routeLostPayment(false)
    @Test fun actualUpcomingRouteRetriesACommittedPaymentAfterObserverChangesTheCycleToPaid()=routeLostPayment(true)
    private fun routeLostPayment(upcoming:Boolean)=runBlocking<Unit> {
        var lost=false;var closed by mutableStateOf(false)
        val controlled=object:FinanceRepository by repo {
            override suspend fun payInstallment(owner:UserId,request:InstallmentPaymentRequest,deviceId:String,now:String):Result<SavedInstallmentPayment> {
                val result=repo.payInstallment(owner,request,deviceId,now)
                return if(result.isSuccess && !lost){lost=true;Result.failure(java.io.IOException("lost committed route response"))}else result
            }
        }
        compose.setContent{MistiaTheme(darkTheme=false){
            if(upcoming) {
                if(!closed)UpcomingRecurringPaymentSheet(owner,UpcomingDuePaymentTarget(owner.value,DueSourceKind.INSTALLMENT,plan.id,month),controlled,{device},{closed=true})
            }else Column(Modifier.verticalScroll(rememberScrollState())){InstallmentDuePane(owner,controlled,month,{device})}
        }}
        if(!upcoming){awaitTag("installment.pay."+plan.id);compose.onNodeWithTag("installment.pay."+plan.id).performScrollTo().performClick()}
        awaitTag("installment.submitPayment");submitToFundReview();compose.onNodeWithTag("installment.funds.confirm").performClick()
        awaitTag("installment.paymentError");awaitTag("installment.paymentStale")
        Assert.assertTrue(lost);val before=source();val queue=queues()
        compose.onNodeWithTag("installment.retryPayment").performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("installment.paymentSheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }
    @Test fun actualDuePaneRetriesACommittedUndoAfterObserverChangesTheCycleToPending()=runBlocking<Unit> {
        seedPaid();var lost=false
        val controlled=object:FinanceRepository by repo {
            override suspend fun undoInstallmentPaymentWithInvestmentFunds(owner:UserId,request:InstallmentInvestmentUndoRequest,deviceId:String,now:String):Result<Unit> {
                val result=repo.undoInstallmentPaymentWithInvestmentFunds(owner,request,deviceId,now)
                return if(result.isSuccess && !lost){lost=true;Result.failure(java.io.IOException("lost committed undo response"))}else result
            }
        }
        compose.setContent{MistiaTheme(darkTheme=false){Column(Modifier.verticalScroll(rememberScrollState())){InstallmentDuePane(owner,controlled,month,{device})}}}
        awaitTag("installment.pay."+plan.id);compose.onNodeWithTag("installment.pay."+plan.id).performScrollTo().performClick()
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();awaitTag("installment.funds.review")
        compose.onNodeWithTag("installment.funds.confirm").performClick();awaitTag("installment.paymentError");awaitTag("installment.paymentStale")
        Assert.assertTrue(lost);val before=source();val queue=queues()
        compose.onNodeWithTag("installment.retryPayment").performScrollTo().performClick()
        compose.waitUntil(5000){compose.onAllNodesWithTag("installment.paymentSheet").fetchSemanticsNodes().isEmpty()}
        Assert.assertEquals(before,source());Assert.assertEquals(queue,queues())
    }

    @Test fun retryCannotSubmitTheFrozenWalletAfterVisibleWalletSelectionChanges() {
        val row=due();var current by mutableStateOf(true);var attempts=0
        val alternate=wallet.copy(id=id(98),name="Alternate cash")
        compose.setContent{MistiaTheme(darkTheme=false){InstallmentPaymentSheet(owner.value,row,listOf(wallet,alternate),targetCurrent=current,
            onPay={attempts++;current=false;Result.failure(java.io.IOException("ambiguous result"))},onUndo={Result.success(Unit)},onDismiss={})}}
        compose.onNodeWithTag("installment.submitPayment").performScrollTo().performClick();compose.onNodeWithTag("installment.confirmPayment").performClick()
        awaitTag("installment.paymentError");awaitTag("installment.retryPayment")
        compose.onNodeWithTag("installment.paymentWallet").performScrollTo().performClick();compose.onNodeWithTag("installment.payWallet."+alternate.id).performClick()
        compose.onNodeWithTag("installment.retryPayment").performScrollTo().performClick()
        compose.runOnIdle{Assert.assertEquals(1,attempts)}
    }

}
