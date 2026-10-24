package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.graphics.toArgb
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.feature.management.ManagementScreen

@RunWith(AndroidJUnit4::class)
class TransactionLifecycleEditorTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName !in setOf("lifecycleDialogsFitAllLanguagesAndThemesAtActual130And320Dp","veryLongSavedTitleStillLetsThePersonReadTheWholeConfirmationBeforeActing")){base.evaluate();return}
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
    }}}).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close();if(::folder.isInitialized)folder.deleteRecursively()}}).around(compose)
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var receipts:LocalTransactionReceiptImageRepository
    private lateinit var folder:java.io.File
    private val exchange=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    @Before fun open()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner});repo=OfflineFirstFinanceRepository(store)
        folder=java.io.File(context.cacheDir,"lifecycle-ui-"+java.util.UUID.randomUUID());receipts=LocalTransactionReceiptImageRepository(db,folder)
        repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        val parent=repo.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        repo.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
        val r=TransactionInvestmentSaveRequest(TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-23T00:00:02Z",sourceWalletId=id(1),categoryId=id(31)),TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val review=(repo.prepareTransactionWithInvestmentFunds(owner,r,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        repo.saveTransactionWithInvestmentFunds(owner,r.copy(consent=review.consent),device,now).getOrThrow();Unit
    }
    private fun primary()=runBlocking{LedgerTransactionRecord.fromCloudRecord(requireNotNull(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))))}
    private fun archiveSeed()=runBlocking {
        val r=TransactionInvestmentLifecycleRequest(primary(),TransactionLifecycleAction.ARCHIVE,"2026-10-23T00:01:00Z","JPY","Adjustment",null)
        val review=(repo.prepareTransactionLifecycle(owner,r,device,r.operationAt).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        repo.saveTransactionLifecycle(owner,r.copy(consent=review.consent),device,r.operationAt).getOrThrow();Unit
    }
    private fun awaitTag(tag:String){
        try{compose.waitUntil(5000){compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()}}
        catch(error:Throwable){
            val context=ApplicationProvider.getApplicationContext<Context>()
            val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            bitmap?.let{frame->java.io.File(context.getExternalFilesDir(null),"lifecycle-timeout-"+tag+".png").outputStream().use{frame.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};frame.recycle()}
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews().joinToString {view->
                "window="+view.width+"x"+view.height+" scrollY="+view.scrollY+" ime="+view.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime())
            }
            val roots=compose.onAllNodes(isRoot(),useUnmergedTree=true)
            val tree=(0 until roots.fetchSemanticsNodes().size).joinToString("\n"){roots[it].printToString()}
            throw AssertionError("Waiting for "+tag+"\n"+windows+"\n"+tree,error)
        }
    }
    @Test fun storedEditorArchiveCancelKeepsItsUnsavedDraftAndConfirmationRestoresReservedFunds() {
        var dismissed=false
        compose.setContent{MistiaTheme(darkTheme=false){StoredTransactionEditorRoute(owner,id(20),repo,exchange,receipts,{device},onDismiss={dismissed=true})}}
        compose.waitUntil(5000){compose.onAllNodes(hasSetTextAction() and hasText("Expense")).fetchSemanticsNodes().isNotEmpty()}
        compose.onNode(hasSetTextAction() and hasText("Expense")).performTextReplacement("Unsaved title")
        compose.onNodeWithTag("transaction.archive").performScrollTo().performClick()
        awaitTag("transaction.lifecycle.confirm")
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.cancel")
        compose.onNodeWithTag("transaction.funds.cancel").performClick();compose.onNode(hasSetTextAction() and hasText("Unsaved title")).assertExists()
        Assert.assertFalse(primary().isArchived);Assert.assertFalse(dismissed)
        compose.onNodeWithTag("transaction.archive").performScrollTo().performClick();awaitTag("transaction.lifecycle.confirm");compose.onNodeWithTag("transaction.lifecycle.confirm").performClick()
        awaitTag("transaction.funds.review");compose.onNodeWithTag("transaction.funds.confirm").performClick()
        compose.waitUntil(5000){dismissed};Assert.assertTrue(primary().isArchived);Assert.assertEquals("Expense",primary().title)
        Assert.assertNotNull(runBlocking{store.record(owner,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(id(20),"cash-consumption-booked"))!!.deletedAt})
    }
    @Test fun actualManagementArchiveEntryRestoresOnlyAfterExplicitReservedFundConsent() {
        archiveSeed();var archivePage by mutableStateOf(false)
        compose.setContent{MistiaTheme(darkTheme=false){
            if(archivePage)ArchivedTransactionsRoute(owner,repo,receipts,{device},onDismiss={archivePage=false})
            else ManagementScreen(owner,repo,{device},{},{},{},{},{},{},onOpenArchivedTransactions={archivePage=true})
        }}
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag("management.archived.transactions"))
        compose.onNodeWithTag("management.archived.transactions").performClick();awaitTag("transaction.archived.row."+id(20))
        compose.onNodeWithTag("transaction.archived.restore."+id(20)).performClick();compose.onNodeWithTag("transaction.lifecycle.confirm").performClick()
        awaitTag("transaction.funds.review");Assert.assertTrue(primary().isArchived)
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){!primary().isArchived}
        compose.onNodeWithTag("transaction.archived.row."+id(20)).assertDoesNotExist()
    }
    @Test fun archivedDeleteCancelPreservesFilesAndConfirmedDeleteRemovesTheOwnedImage() {
        archiveSeed();runBlocking{receipts.createReceiptIfAbsent(owner,id(20),byteArrayOf(1,2,3),byteArrayOf(4),"image/jpeg",now).getOrThrow()}
        compose.setContent{MistiaTheme(darkTheme=false){ArchivedTransactionsRoute(owner,repo,receipts,{device},onDismiss={})}}
        awaitTag("transaction.archived.row."+id(20));compose.onNodeWithTag("transaction.archived.delete."+id(20)).performClick()
        compose.onNodeWithTag("transaction.lifecycle.cancel").performClick();Assert.assertNull(primary().deletedAt);Assert.assertEquals(2,folder.listFiles()!!.size)
        compose.onNodeWithTag("transaction.archived.delete."+id(20)).performClick();compose.onNodeWithTag("transaction.lifecycle.confirm").performClick()
        compose.waitUntil(5000){primary().deletedAt!=null && folder.listFiles().orEmpty().isEmpty()}
        compose.onNodeWithTag("transaction.archived.row."+id(20)).assertDoesNotExist();Assert.assertNull(runBlocking{receipts.receipt(id(20))})
    }
    @Test fun committedDeleteWithReceiptFailureExplainsTheResultAndKeepsItsFrozenCleanupRetry() {
        archiveSeed();runBlocking{receipts.createReceiptIfAbsent(owner,id(20),byteArrayOf(1,2,3),byteArrayOf(4),"image/jpeg",now).getOrThrow()}
        var attempts=0
        val failing=object:TransactionReceiptImageRepository by receipts {override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord):Result<Unit>{
            attempts++;return if(attempts==1)Result.failure(java.io.IOException("disk unavailable"))else receipts.deleteReceiptIfUnchanged(ownerUserId,expected)
        }}
        compose.setContent{MistiaTheme(darkTheme=false){ArchivedTransactionsRoute(owner,repo,failing,{device},onDismiss={})}}
        awaitTag("transaction.archived.row."+id(20));compose.onNodeWithTag("transaction.archived.delete."+id(20)).performClick()
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.lifecycle.cleanup")
        Assert.assertNotNull(primary().deletedAt);Assert.assertNotNull(runBlocking{receipts.receipt(id(20))})
        compose.onNodeWithTag("transaction.lifecycle.cleanup").assertExists();compose.onNodeWithTag("transaction.lifecycle.cancel").assertDoesNotExist()
        val committed=runBlocking{store.transactionInvestmentSaveSnapshot(owner)}
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();compose.waitUntil(5000){runBlocking{receipts.receipt(id(20))}==null}
        compose.onNodeWithTag("transaction.lifecycle.dialog").assertDoesNotExist();Assert.assertEquals(committed,runBlocking{store.transactionInvestmentSaveSnapshot(owner)});Assert.assertEquals(2,attempts)
    }
    @Test fun retainingAReceiptAfterCommittedDeletionRequiresItsExplicitKeepAction() {
        archiveSeed();runBlocking{receipts.createReceiptIfAbsent(owner,id(20),byteArrayOf(1),byteArrayOf(4),"image/jpeg",now).getOrThrow()}
        val expected=primary();var done=false;var dismissed=false
        val failing=object:TransactionReceiptImageRepository by receipts {override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord)=Result.failure<Unit>(java.io.IOException("disk unavailable"))}
        compose.setContent{MistiaTheme(darkTheme=false){if(!done)TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.DELETE,repo,failing,emptyList(),{device},"JPY",onDone={done=true},onDismiss={dismissed=true})}}
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.lifecycle.cleanup")
        compose.onNodeWithTag("transaction.lifecycle.dialog").performTouchInput{click(androidx.compose.ui.geometry.Offset(-5f,-5f))}
        Assert.assertFalse(dismissed);Assert.assertFalse(done)
        compose.onNodeWithTag("transaction.lifecycle.keep.receipt").performClick();compose.waitUntil(5000){done}
        Assert.assertNotNull(primary().deletedAt);Assert.assertNotNull(runBlocking{receipts.receipt(id(20))});Assert.assertFalse(dismissed)
    }
    @Test fun confirmedFundReviewDisablesBothActionsUntilItsActualSaveCompletes() {
        archiveSeed();val expected=primary();val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>();var done=false
        val delayed=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord>{
            entered.complete(Unit);finish.await();return repo.saveTransactionLifecycle(owner,request,deviceId,now)
        }}
        compose.setContent{MistiaTheme(darkTheme=false){if(!done)TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.RESTORE,delayed,receipts,emptyList(),{device},"JPY",onDone={done=true},onDismiss={done=true})}}
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review");compose.onNodeWithTag("transaction.funds.confirm").performClick()
        compose.waitUntil(5000){entered.isCompleted}
        compose.onNodeWithTag("transaction.funds.confirm").assertIsNotEnabled();compose.onNodeWithTag("transaction.funds.cancel").assertIsNotEnabled()
        Assert.assertFalse(done);Assert.assertTrue(primary().isArchived)
        finish.complete(Unit);compose.waitUntil(5000){done};Assert.assertFalse(primary().isArchived)
    }
    @Test fun nonCancellableOldRepositoryCompletionCannotDismissTheReplacementAction() {
        archiveSeed();val expected=primary();val entered=CompletableDeferred<Unit>();val finish=CompletableDeferred<Unit>();var done=0
        val old=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord> =
            withContext(NonCancellable){entered.complete(Unit);finish.await();Result.success(expected.copy(isArchived=false,archivedAt=null))}}
        var current by mutableStateOf<FinanceRepository>(old)
        compose.setContent{MistiaTheme(darkTheme=false){TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.RESTORE,current,receipts,emptyList(),{device},"JPY",onDone={done++},onDismiss={})}}
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review");compose.onNodeWithTag("transaction.funds.confirm").performClick()
        compose.waitUntil(5000){entered.isCompleted};compose.runOnIdle{current=repo};awaitTag("transaction.lifecycle.confirm")
        finish.complete(Unit);compose.waitForIdle();Assert.assertEquals(0,done);compose.onNodeWithTag("transaction.lifecycle.confirm").assertIsEnabled()
        Assert.assertTrue(primary().isArchived)
    }
    @Test fun failedSaveRetainsTheArchiveAndExplicitRetryRequestsNewFundConsent() {
        archiveSeed();val expected=primary();var attempts=0;var done=false
        val failing=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord>{
            attempts++;return if(attempts==1)Result.failure(java.io.IOException("offline local storage failure")) else repo.saveTransactionLifecycle(owner,request,deviceId,now)
        }}
        compose.setContent{MistiaTheme(darkTheme=false){if(!done)TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.RESTORE,failing,receipts,emptyList(),{device},"JPY",onDone={done=true},onDismiss={})}}
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review");compose.onNodeWithTag("transaction.funds.confirm").performClick()
        awaitTag("transaction.lifecycle.error");Assert.assertTrue(primary().isArchived);Assert.assertFalse(done)
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review");Assert.assertEquals(1,attempts)
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){done};Assert.assertEquals(2,attempts)
    }
    @Test fun changedFinancialSourceRejectsFrozenConsentThenANewExplicitAttemptReviewsItAgain() {
        archiveSeed();val expected=primary();var done=false
        compose.setContent{MistiaTheme(darkTheme=false){if(!done)TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.RESTORE,repo,receipts,emptyList(),{device},"JPY",onDone={done=true},onDismiss={})}}
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review")
        runBlocking {
            val raw=store.record(owner,CloudEntity.LEDGER_WALLET.table,id(1))!!
            val changed=raw.copy(payload=JsonObject(raw.payload+("opening_balance_minor" to JsonPrimitive(101L))))
            store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,id(1),owner.value,MutationKind.UPSERT,changed.payload,now,raw.syncVersion,device))
        }
        compose.onNodeWithTag("transaction.funds.confirm").performClick();awaitTag("transaction.lifecycle.error");Assert.assertTrue(primary().isArchived)
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review");Assert.assertFalse(done)
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){done}
    }
    @Test fun archiveListShowsLoadFailureAndRetryWithoutInventingAnEmptyLoadedList() {
        archiveSeed();var fail=true
        val failing=object:FinanceRepository by repo {override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> =
            if(fail && entity==CloudEntity.LEDGER_TRANSACTION)flow{throw java.io.IOException("read failed")}else repo.observe(entity,ownerUserId)}
        compose.setContent{MistiaTheme(darkTheme=false){ArchivedTransactionsRoute(owner,failing,receipts,{device},onDismiss={})}}
        awaitTag("transaction.archived.error");compose.onNodeWithTag("transaction.archived.empty").assertDoesNotExist()
        fail=false;compose.onNodeWithTag("transaction.archived.retry").performClick();awaitTag("transaction.archived.row."+id(20));Assert.assertTrue(primary().isArchived)
    }
    @Test fun replacingOwnerWhileConfirmationIsOpenRemovesEveryOldPrivateActionAndRow() {
        archiveSeed();var subject by mutableStateOf(owner)
        compose.setContent{MistiaTheme(darkTheme=false){ArchivedTransactionsRoute(subject,repo,receipts,{device},onDismiss={})}}
        awaitTag("transaction.archived.row."+id(20));compose.onNodeWithTag("transaction.archived.restore."+id(20)).performClick()
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review")
        compose.runOnIdle{subject=UserId(id(99))};awaitTag("transaction.archived.empty")
        compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist();compose.onNodeWithTag("transaction.archived.row."+id(20)).assertDoesNotExist()
        Assert.assertTrue(primary().isArchived)
    }
    @Test fun restoredArchivePageNeverRestoresConsentOrReplaysThePendingAction() {
        archiveSeed();val restoration=StateRestorationTester(compose)
        restoration.setContent{MistiaTheme(darkTheme=false){ArchivedTransactionsRoute(owner,repo,receipts,{device},onDismiss={})}}
        awaitTag("transaction.archived.row."+id(20));compose.onNodeWithTag("transaction.archived.restore."+id(20)).performClick()
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.review")
        val before=runBlocking{store.transactionInvestmentSaveSnapshot(owner)}
        restoration.emulateSavedInstanceStateRestore();awaitTag("transaction.archived.row."+id(20))
        compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist();compose.onNodeWithTag("transaction.lifecycle.dialog").assertDoesNotExist()
        Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
        compose.onNodeWithTag("transaction.archived.restore."+id(20)).performClick();compose.onNodeWithTag("transaction.lifecycle.confirm").performClick()
        awaitTag("transaction.funds.review");compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){!primary().isArchived}
    }
    @Test fun actualCashflowListArchiveUsesTheSameOwnedLifecycleAndHidesItsActiveRow() {
        val analysis=object:ReceiptAnalysisClient {
            override suspend fun analyzeBillItems(request:BillItemAnalysisRequest,accessToken:String):BillItemAnalysisResult=error("unused")
        }
        compose.setContent{MistiaTheme(darkTheme=false){TransactionsScreen(owner,repo,exchange,analysis,receipts,accessTokenProvider={null},deviceIdProvider={device})}}
        compose.waitUntil(5000){compose.onAllNodesWithText("Expense",substring=false).fetchSemanticsNodes().size==1}
        compose.onNodeWithText("Expense",substring=false).performClick();awaitTag("transaction.archive")
        compose.onNodeWithTag("transaction.archive").performScrollTo().performClick();awaitTag("transaction.lifecycle.confirm")
        compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.funds.confirm")
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){primary().isArchived}
        compose.waitUntil(5000){compose.onAllNodesWithTag("transaction.archive").fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithText("Expense",substring=false).assertDoesNotExist()
    }
    @Test fun veryLongSavedTitleStillLetsThePersonReadTheWholeConfirmationBeforeActing() {
        val expected=primary().copy(title="A long saved expense title. ".repeat(80))
        compose.setContent{MistiaTheme(darkTheme=false){TransactionLifecycleActionDialog(owner,expected,TransactionLifecycleAction.ARCHIVE,repo,receipts,emptyList(),{device},"JPY",onDone={},onDismiss={})}}
        compose.onNodeWithTag("transaction.lifecycle.message").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("transaction.lifecycle.confirm").assertIsDisplayed();compose.onNodeWithTag("transaction.lifecycle.cancel").assertIsDisplayed()
        Assert.assertFalse(primary().isArchived)
    }
    @Test fun lifecycleDialogsFitAllLanguagesAndThemesAtActual130And320Dp() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        archiveSeed()
        runBlocking {
            val row=primary().copy(title="Household expense / 家計の支出 / Chi tiêu gia đình",amountMinor=Long.MAX_VALUE).toCloudRecord()
            store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_TRANSACTION,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
        }
        val initial=primary()
        var language by mutableStateOf("en");var dark by mutableStateOf(false);var action by mutableStateOf(TransactionLifecycleAction.ARCHIVE);var visible by mutableStateOf(false)
        var listPage by mutableStateOf(false)
        var cleanupPage by mutableStateOf(false)
        val cleanupRepository=object:FinanceRepository by repo {override suspend fun prepareTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String)=Result.success(TransactionInvestmentSavePlan(initial.copy(isArchived=true,deletedAt=now),emptyList()))}
        val cleanupImages=object:TransactionReceiptImageRepository by receipts {override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord)=Result.failure<Unit>(java.io.IOException("presentation fixture"))}
        var expectedBackground=0
        val before=runBlocking{store.transactionInvestmentSaveSnapshot(owner)}
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
                key(language,dark,action,cleanupPage){MistiaTheme(darkTheme=dark){
                    expectedBackground=androidx.compose.material3.MaterialTheme.colorScheme.background.toArgb()
                    if(cleanupPage)TransactionLifecycleActionDialog(owner,initial.copy(isArchived=true),TransactionLifecycleAction.DELETE,cleanupRepository,cleanupImages,emptyList(),{device},"JPY",onDone={},onDismiss={})
                    else if(listPage)ArchivedTransactionsRoute(owner,repo,receipts,{device},onDismiss={})
                    else if(visible)TransactionLifecycleActionDialog(owner,initial.copy(isArchived=action!=TransactionLifecycleAction.ARCHIVE),action,repo,receipts,emptyList(),{device},"JPY",onDone={},onDismiss={visible=false})
                }}
            }
        }
        fun complete(tag:String):androidx.compose.ui.text.TextLayoutResult {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertFalse(tag+" size="+layout.size+" paragraph="+layout.multiParagraph.height+" text="+layout.layoutInput.text.text,layout.didOverflowHeight);Assert.assertEquals(tag,layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(line in 0 until layout.lineCount){Assert.assertFalse(layout.isLineEllipsized(line));Assert.assertTrue(layout.getLineLeft(line)>=-1f);Assert.assertTrue(layout.getLineRight(line)<=layout.size.width+1f)}
            val paint=android.graphics.Paint();layout.layoutInput.text.text.codePoints().forEach{code->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
            return layout
        }
        try {
            for(choice in TransactionLifecycleAction.entries)for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme;action=choice;visible=true};awaitTag("transaction.lifecycle.confirm")
                compose.runOnIdle{configure(code)}
                for(tag in listOf("title","name","amount","message","confirm.text","cancel.text"))complete("transaction.lifecycle."+tag)
                val confirm=compose.onNodeWithTag("transaction.lifecycle.confirm").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                val cancel=compose.onNodeWithTag("transaction.lifecycle.cancel").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                Assert.assertTrue(confirm.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(cancel.height>=48*context.resources.displayMetrics.density-1)
                Assert.assertFalse("Lifecycle actions overlap",confirm.overlaps(cancel))
                compose.waitForIdle();val screenshot=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                java.io.File(context.getExternalFilesDir(null),"transaction-lifecycle-"+choice.name.lowercase()+"-"+code+"-"+(if(theme)"dark"else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
                compose.onNodeWithTag("transaction.lifecycle.cancel").performClick();compose.waitForIdle();Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
            }
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme;listPage=true};awaitTag("transaction.archived.row."+id(20));compose.runOnIdle{configure(code)}
                for(tag in listOf("transaction.archived.heading","transaction.archived.name."+id(20),"transaction.archived.subtitle."+id(20),"transaction.archived.restore.text."+id(20),"transaction.archived.delete.text."+id(20)))complete(tag)
                Assert.assertEquals("Exact money splits across lines",1,complete("transaction.archived.amount."+id(20)).lineCount)
                val restore=compose.onNodeWithTag("transaction.archived.restore."+id(20)).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                val delete=compose.onNodeWithTag("transaction.archived.delete."+id(20)).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                Assert.assertFalse(restore.overlaps(delete));Assert.assertTrue(restore.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(delete.height>=48*context.resources.displayMetrics.density-1)
                compose.waitForIdle();val screenshot=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                Assert.assertEquals("Archive page does not paint the selected theme background",expectedBackground,screenshot.getPixel(screenshot.width-12,screenshot.height*3/4))
                java.io.File(context.getExternalFilesDir(null),"transaction-lifecycle-list-"+code+"-"+(if(theme)"dark"else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
                Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
            }
            runBlocking{receipts.createReceiptIfAbsent(owner,id(20),byteArrayOf(1),byteArrayOf(2),"image/jpeg",now).getOrThrow()}
            for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                compose.runOnIdle{configure(code);language=code;dark=theme;cleanupPage=true};awaitTag("transaction.lifecycle.confirm");compose.runOnIdle{configure(code)}
                compose.onNodeWithTag("transaction.lifecycle.confirm").performClick();awaitTag("transaction.lifecycle.cleanup")
                for(tag in listOf("title","name","amount","cleanup","confirm.text","keep.receipt.text"))complete("transaction.lifecycle."+tag)
                val retry=compose.onNodeWithTag("transaction.lifecycle.confirm").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                val keep=compose.onNodeWithTag("transaction.lifecycle.keep.receipt").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                Assert.assertFalse(retry.overlaps(keep));Assert.assertTrue(retry.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(keep.height>=48*context.resources.displayMetrics.density-1)
                compose.waitForIdle();val screenshot=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                java.io.File(context.getExternalFilesDir(null),"transaction-lifecycle-cleanup-"+code+"-"+(if(theme)"dark"else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
                Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
            }
        }finally{compose.runOnIdle{originals.forEach{(resource,configuration)->resource.updateConfiguration(configuration,resource.displayMetrics)}}}
    }
}
