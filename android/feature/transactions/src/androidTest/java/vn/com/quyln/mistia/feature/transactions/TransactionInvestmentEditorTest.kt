package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
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
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionInvestmentEditorTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(org.junit.rules.TestRule{base,description->object:org.junit.runners.model.Statement(){override fun evaluate(){
        if(description.methodName !in setOf("fundDialogsFitThreeLanguagesBothThemesAtActual130And320Dp","reallocationReviewFitsThreeLanguagesBothThemesAtActual130And320Dp")){base.evaluate();return}
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
    }}}).around(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close();if(::folder.isInitialized)folder.deleteRecursively()}}).around(compose)
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-22T00:00:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repository:OfflineFirstFinanceRepository
    private lateinit var receipts:LocalTransactionReceiptImageRepository
    private lateinit var folder:java.io.File
    private lateinit var wallet:LedgerWalletRecord
    private lateinit var categories:List<TransactionCategoryRecord>
    private val image=PreparedReceiptImage(byteArrayOf(1,2,3),byteArrayOf(4,5),"image/jpeg",1,1)
    private var dismissed=false
    @Before fun open()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner});repository=OfflineFirstFinanceRepository(store)
        folder=java.io.File(context.cacheDir,"fund-editor-"+java.util.UUID.randomUUID());receipts=LocalTransactionReceiptImageRepository(db,folder)
        wallet=repository.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        val parent=repository.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        val child=repository.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow();categories=listOf(parent,child)
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-22T00:00:01Z")
        },now,null,0)
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
    }
    private fun initial()=TransactionEditorState.new(now).copy(title="Expense",amountText="70",occurredAt="2026-10-22T00:00:02Z",sourceWalletId=id(1),categoryId=id(31),creationIdentity=TransactionCreationIdentity(id(20),now))
    @Composable private fun Editor(record:LedgerTransactionRecord?=null,withReceipt:Boolean=false,repo:FinanceRepository=repository,
        initialOverride:TransactionEditorState?=null,candidates:List<LedgerWalletRecord> = listOf(wallet),restoredReceiptState:TransactionReceiptEditorState?=null) {
        var open by remember{mutableStateOf(true)}
        if(open)MistiaTheme(darkTheme=false){TransactionEditorSheet(owner.value,record,candidates,categories,emptyList(),now,"JPY",initialState=if(record==null)initialOverride ?: initial()else null,
            receiptState=restoredReceiptState ?: TransactionReceiptEditorState.none(),onDismiss={dismissed=true;open=false},saveSessionKey=repo,onSave={draft->
                if(restoredReceiptState!=null)saveInvestmentAwareEditorReceiptState(owner,draft,"JPY","Automatic adjustment",device,now,repo,receipts,restoredReceiptState)
                else saveInvestmentAwareEditorTransaction(owner,draft,"JPY","Automatic adjustment",device,now,repo,receipts,if(withReceipt)image else null)})}
    }
    private fun save(){compose.onNodeWithText(context.getString(R.string.common_save)).performClick()}
    private fun review(){compose.waitUntil(5000){compose.onAllNodesWithTag("transaction.funds.review").fetchSemanticsNodes().isNotEmpty()}}
    private fun primary()=runBlocking{store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))}
    @Test fun realReceiptEditorCancelDoesNotWriteAndConfirmationSavesBothFundsAndImage() {
        compose.setContent{Editor(withReceipt=true)};save();review()
        compose.onNodeWithText(context.getString(R.string.investment_wallet_use_funds_title)).assertIsDisplayed()
        Assert.assertNull(primary());Assert.assertNull(runBlocking{receipts.receipt(id(20))})
        compose.onNodeWithTag("transaction.funds.cancel").performClick();compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist();Assert.assertNull(primary())
        save();review();compose.onNodeWithTag("transaction.funds.confirm").performClick()
        compose.waitUntil(5000){dismissed};Assert.assertEquals(70L,primary()!!.payload.financeRawLong("amount_minor"));Assert.assertNotNull(runBlocking{receipts.receipt(id(20))})
        Assert.assertEquals(2,runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}.size)
    }
    @Test fun editingSeventyToFiftyShowsUpdateThenRestoresTwentyReservedMinor() {
        val original=runBlocking {
            val d=initial().toDraft("JPY",null,primaryCurrencyCode="JPY").draft!!
            val request=TransactionInvestmentSaveRequest(d,d.creationIdentity,null,"Automatic adjustment","JPY")
            val review=(repository.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
            repository.saveTransactionWithInvestmentFunds(owner,request.copy(consent=review.consent),device,now).getOrThrow()
        }
        compose.setContent{Editor(original)};compose.onNodeWithTag("transaction.amount").performScrollTo().performTextReplacement("50");save();review()
        compose.onNodeWithText(context.getString(R.string.investment_wallet_update_funds_title)).assertIsDisplayed();Assert.assertEquals(70L,primary()!!.payload.financeRawLong("amount_minor"))
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        Assert.assertEquals(50L,primary()!!.payload.financeRawLong("amount_minor"))
        val posting=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}.single{it.id!=id(10)}
        Assert.assertEquals(-10L,posting.payload.financeRawLong("amount_minor"))
    }
    @Test fun restoredEditorKeepsCreationIdentityButRequiresFreshExplicitConfirmation() {
        val restoration=StateRestorationTester(compose);restoration.setContent{Editor()};save();review()
        restoration.emulateSavedInstanceStateRestore();compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist();Assert.assertNull(primary())
        save();review();compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        Assert.assertEquals(id(20),primary()!!.id);Assert.assertEquals(1,runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table)}.size)
    }
    @Test fun changedFinancialSourceRejectsOldConsentAndASeparateSaveRequestsFreshConfirmation() {
        compose.setContent{Editor(withReceipt=true)};save();review()
        runBlocking {
            val row=store.record(owner,CloudEntity.LEDGER_WALLET.table,id(1))!!
            val changed=row.copy(payload=JsonObject(row.payload+("opening_balance_minor" to JsonPrimitive(101L))))
            store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,changed.id,owner.value,MutationKind.UPSERT,changed.payload,now,0,device))
        }
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitForIdle();compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist()
        Assert.assertNull(primary());Assert.assertNull(runBlocking{receipts.receipt(id(20))})
        save();review();compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        val posting=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}.single{it.id!=id(10)}
        Assert.assertEquals(-29L,posting.payload.financeRawLong("amount_minor"))
    }
    @Test fun cancellingThenReducingToOrdinaryFundsDoesNotReuseTheOldConsent() {
        compose.setContent{Editor()};save();review();compose.onNodeWithTag("transaction.funds.cancel").performClick()
        compose.onNodeWithTag("transaction.amount").performScrollTo().performTextReplacement("10");save();compose.waitUntil(5000){dismissed}
        Assert.assertEquals(10L,primary()!!.payload.financeRawLong("amount_minor"));Assert.assertEquals(1,runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}.size)
    }
    @Test fun sameOwnerRepositoryReplacementDropsConsentAndPreservesTheUnsubmittedDraft() {
        var current:FinanceRepository by mutableStateOf(repository)
        compose.setContent{Editor(repo=current)};save();review()
        compose.runOnIdle {current=object:FinanceRepository by repository {}}
        compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist();Assert.assertNull(primary())
        compose.onNodeWithTag("transaction.amount").assertTextContains("70")
        save();review();compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        Assert.assertEquals(70L,primary()!!.payload.financeRawLong("amount_minor"))
    }
    @Test fun nonCancellableOldRepositoryResponseCannotReplaceTheNewPromptOrDraft() {
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        val held=object:FinanceRepository by repository {
            override suspend fun prepareTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String):Result<TransactionInvestmentSavePlan> = withContext(NonCancellable) {
                started.complete(Unit);release.await();val result=repository.prepareTransactionWithInvestmentFunds(owner,request,deviceId,now);finished.complete(Unit);result
            }
        }
        var current:FinanceRepository by mutableStateOf(held)
        compose.setContent{Editor(repo=current)}
        try {
            save();compose.waitUntil(5000){started.isCompleted};compose.runOnIdle{current=repository}
            compose.onNodeWithTag("transaction.amount").performScrollTo().performTextReplacement("50");save();review()
            compose.runOnIdle{release.complete(Unit)};compose.waitUntil(5000){finished.isCompleted}
            compose.onNodeWithTag("transaction.funds.review").assertExists();Assert.assertNull(primary());Assert.assertFalse(dismissed)
            compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
            Assert.assertEquals(50L,primary()!!.payload.financeRawLong("amount_minor"))
        } finally {release.complete(Unit)}
    }
    @Test fun removingAllPreviousFundUseShowsRestoreAndTombstonesTheOldPosting() {
        val original=runBlocking {
            val d=initial().toDraft("JPY",null,primaryCurrencyCode="JPY").draft!!
            val request=TransactionInvestmentSaveRequest(d,d.creationIdentity,null,"Automatic adjustment","JPY")
            val review=(repository.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
            repository.saveTransactionWithInvestmentFunds(owner,request.copy(consent=review.consent),device,now).getOrThrow()
        }
        compose.setContent{Editor(original)};compose.onNodeWithTag("transaction.amount").performScrollTo().performTextReplacement("40");save();review()
        compose.onNodeWithText(context.getString(R.string.investment_wallet_restore_funds_title)).assertIsDisplayed();Assert.assertEquals(70L,primary()!!.payload.financeRawLong("amount_minor"))
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        val posting=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}.single{it.id!=id(10)}
        Assert.assertNotNull(posting.deletedAt);Assert.assertEquals(40L,primary()!!.payload.financeRawLong("amount_minor"))
        val queue=runBlocking{store.pendingMutations(owner,CloudEntity.INVESTMENT_POSTING,Long.MAX_VALUE)}.single{it.mutation.recordId==posting.id}
        Assert.assertEquals(MutationKind.DELETE,queue.mutation.kind)
    }
    private fun setForeignReserve()=runBlocking {
        wallet=wallet.copy(currencyCode="VND",openingBalanceMinor=100_000)
        val raw=wallet.toCloudRecord();store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        val old=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!
        val posting=old.copy(payload=JsonObject(old.payload+buildJsonObject{put("currency_code","VND");put("amount_minor",40_000L);put("accounting_amount_minor",2L)}))
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
    }
    @Test fun foreignFundUseShowsItsLocalizedCurrencyRuleBeforeSavingAnyReceipt() {
        setForeignReserve()
        val state=initial().copy(amountText="70,000",reportingAmountText="1,400",reportingAmountCurrencyCode="JPY",conversionMode=CurrencyConversionMode.MANUAL)
        compose.setContent{Editor(withReceipt=true,initialOverride=state)};save()
        compose.waitUntil(5000){compose.onAllNodesWithText(context.getString(R.string.investment_error_fund_usage_currency_mismatch)).fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText(context.getString(R.string.investment_error_fund_usage_currency_mismatch)).performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist();Assert.assertNull(primary());Assert.assertNull(runBlocking{receipts.receipt(id(20))})
        compose.onNodeWithTag("transaction.amount").performScrollTo().performTextReplacement("")
        compose.onNodeWithTag("transaction.save").performScrollTo().performClick()
        compose.onNodeWithText(context.getString(R.string.investment_error_fund_usage_currency_mismatch)).assertDoesNotExist()
        Assert.assertNull(primary())
    }
    @Test fun ordinaryOnlyFxStillSavesFromAForeignWalletThatHoldsInvestmentMoney() {
        setForeignReserve()
        val destination=runBlocking{repository.saveWallet(owner,WalletDraft(id=id(2),name="JPY",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=0),device,now).getOrThrow()}
        val state=initial().copy(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,categoryId=null,
            amountText="50,000",destinationWalletId=destination.id,destinationAmountText="1,000",conversionMode=CurrencyConversionMode.MANUAL)
        compose.setContent{Editor(initialOverride=state,candidates=listOf(wallet,destination))};save();compose.waitUntil(5000){dismissed}
        Assert.assertEquals(50_000L,primary()!!.payload.financeRawLong("amount_minor"));Assert.assertEquals(1_000L,primary()!!.payload.financeRawLong("destination_amount_minor"))
        Assert.assertEquals(1,runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}.size)
    }
    @Test fun recreatedReceiptEditorWithoutMemoryRecognizesTheAlreadyCommittedReceiptAndTransaction() {
        runBlocking {
            val d=initial().toDraft("JPY",null,primaryCurrencyCode="JPY").draft!!
            val request=TransactionInvestmentSaveRequest(d,d.creationIdentity,null,"Automatic adjustment","JPY")
            val review=(repository.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
            saveInvestmentAwareEditorTransaction(owner,d.copy(investmentConsent=review.consent),"JPY","Automatic adjustment",device,now,repository,receipts,image).getOrThrow()
        }
        val before=runBlocking{store.transactionInvestmentSaveSnapshot(owner)};val stored=runBlocking{receipts.receipt(id(20))}
        val restoration=StateRestorationTester(compose);var retained=false
        restoration.setContent {
            val receipt by rememberSaveable(stateSaver=TransactionReceiptEditorState.Saver){mutableStateOf(TransactionReceiptEditorState.pending(image))}
            retained=receipt.newReceiptImageForSave().isSuccess
            Editor(restoredReceiptState=receipt)
        }
        compose.runOnIdle{Assert.assertTrue(retained)};restoration.emulateSavedInstanceStateRestore();compose.runOnIdle{Assert.assertFalse(retained)}
        save();compose.waitUntil(5000){dismissed};compose.onNodeWithTag("transaction.funds.review").assertDoesNotExist()
        Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)});Assert.assertEquals(stored,runBlocking{receipts.receipt(id(20))})
        Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun fundDialogsFitThreeLanguagesBothThemesAtActual130And320Dp() {
        runBlocking {
            wallet=wallet.copy(openingBalanceMinor=Long.MAX_VALUE,name="Household savings / 共同ウォレット / Ví giao dịch chung")
            val raw=wallet.toCloudRecord();store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
            val old=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!
            val posting=old.copy(payload=JsonObject(old.payload+buildJsonObject{put("amount_minor",Long.MAX_VALUE-100);put("accounting_amount_minor",Long.MAX_VALUE-100)}))
            store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
        }
        var language by mutableStateOf("en");var dark by mutableStateOf(false);var mode by mutableStateOf("use")
        var original:LedgerTransactionRecord?=null
        var observedSaveError:Throwable?=null
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
                key(mode,language,dark) {MistiaTheme(darkTheme=dark) {
                    val proposed=if(mode=="restore")50L else 9_007_199_254_740_993L
                    TransactionEditorSheet(owner.value,if(mode=="use")null else original?.copy(amountMinor=proposed),listOf(wallet),categories,emptyList(),now,"JPY",
                        initialState=initial().copy(amountText=proposed.toString()),onDismiss={},onSave={draft->saveInvestmentAwareEditorTransaction(owner,draft,"JPY","Automatic adjustment",device,now,repository,receipts).also{observedSaveError=it.exceptionOrNull()}})
                }}
            }
        }
        fun complete(tag:String):androidx.compose.ui.text.TextLayoutResult {
            val results=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(results)}
            val result=results.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            Assert.assertFalse(result.didOverflowHeight);Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true))
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue(result.getLineLeft(line)>=-1f);Assert.assertTrue(result.getLineRight(line)<=result.size.width+1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{code->if(!Character.isWhitespace(code))Assert.assertTrue("Missing glyph "+code,paint.hasGlyph(String(Character.toChars(code))))}
            return result
        }
        try {
            for(kind in listOf("use","update","restore")) {
                if(kind=="update")runBlocking {
                    val d=initial().copy(amountText=Long.MAX_VALUE.toString()).toDraft("JPY",null,primaryCurrencyCode="JPY").draft!!
                    val request=TransactionInvestmentSaveRequest(d,d.creationIdentity,null,"Automatic adjustment","JPY")
                    val review=(repository.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
                    original=repository.saveTransactionWithInvestmentFunds(owner,request.copy(consent=review.consent),device,now).getOrThrow()
                }
                val before=runBlocking{store.transactionInvestmentSaveSnapshot(owner)}
                for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)) {
                    compose.runOnIdle{configure(code);mode=kind;language=code;dark=theme}
                    val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
                    val heading=complete("transaction.heading")
                    val word=heading.layoutInput.text.text.indexOf("cashflow",ignoreCase=true)
                    if(code=="en" && word>=0)Assert.assertEquals("Header splits an ordinary word",heading.getLineForOffset(word),heading.getLineForOffset(word+"cashflow".length-1))
                    val saveBounds=compose.onNodeWithTag("transaction.save").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                    Assert.assertTrue("Save action has no usable width",saveBounds.width>=48*context.resources.displayMetrics.density-1)
                    Assert.assertTrue("Save action has no usable height",saveBounds.height>=48*context.resources.displayMetrics.density-1)
                    compose.onNodeWithText(localized.getString(R.string.common_save)).performClick()
                    try{review()}catch(error:Throwable){
                        val roots=compose.onAllNodes(isRoot(),useUnmergedTree=true)
                        throw AssertionError(kind+"/"+code+"/"+theme+" result="+observedSaveError+"\n"+(0 until roots.fetchSemanticsNodes().size).joinToString("\n"){roots[it].printToString()},error)
                    }
                    compose.runOnIdle{configure(code)}
                    listOf("transaction.funds.title","transaction.funds.name."+id(1),"transaction.funds.message."+id(1),"transaction.funds.confirm.text","transaction.funds.cancel.text").forEach(::complete)
                    for(tag in listOf("transaction.funds.confirm","transaction.funds.cancel")) {
                        val bounds=compose.onNodeWithTag(tag).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                        Assert.assertTrue("Small action: "+tag,bounds.height>=48*context.resources.displayMetrics.density-1)
                    }
                    compose.waitForIdle()
                    val screenshot=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                    java.io.File(context.getExternalFilesDir(null),"transaction-funds-"+kind+"-"+code+"-"+(if(theme)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
                    compose.onNodeWithTag("transaction.funds.cancel").performClick()
                    Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
                }
            }
        }finally{compose.runOnIdle{originals.forEach{(resource,configuration)->resource.updateConfiguration(configuration,resource.displayMetrics)}}}
    }
    private suspend fun seedEqualTotalHistory(firstAmount:Long=100,secondAmount:Long=60) {
        for((key,amount) in listOf(21 to firstAmount,22 to secondAmount)) {
            val date=if(key==21)"2026-10-22T00:00:02Z" else "2026-10-22T00:00:03Z"
            val raw=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id(key),owner.value,buildJsonObject {
                put("id",id(key));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("occurred_at",date);put("deleted_at",JsonNull);put("sync_version",0L)
                put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Existing expense "+key)
                put("amount_minor",amount);put("source_wallet_id",id(1));put("source_currency_code","JPY");put("destination_wallet_id",JsonNull);put("category_id",id(31));put("is_archived",false)
                put("reporting_currency_code","JPY");put("reporting_amount_minor",amount);put("reporting_expense_minor",amount);put("reporting_income_minor",0L)
            },now,null,0)
            store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_TRANSACTION,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        }
        val cash=store.investmentCashSnapshot(owner)
        val first=cash.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(21)}
        for((row,pending) in planInvestmentFundUsage(cash,"JPY",first,reviewInvestmentFundUsage(cash,"JPY",first).consent,"Automatic adjustment",device,now).mutations)store.commitMutation(row,pending)
    }

    @Test fun incomeReallocatingTheSameReservedTotalRequiresReviewAndCancelWritesNothing() {
        runBlocking {
            seedEqualTotalHistory()
            val parent=repository.saveCategory(owner,CategoryDraft(id=id(40),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
            val child=repository.saveCategory(owner,CategoryDraft(id=id(41),name="Income child",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
            categories=categories+listOf(parent,child)
        }
        val before=runBlocking{store.transactionInvestmentSaveSnapshot(owner)}
        val pending=runBlocking{TransactionInvestmentSaveSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}}
        val draft=initial().copy(primaryKind=TransactionPrimaryKind.INCOME,title="Income",amountText="60",categoryId=id(41),occurredAt="2026-10-22T00:00:01.500Z")
        compose.setContent{Editor(initialOverride=draft)};save();review()
        compose.onNodeWithTag("transaction.funds.title").assertTextEquals(context.getString(R.string.investment_wallet_reallocate_funds_title))
        compose.onNodeWithTag("transaction.funds.message."+id(1)).assertTextEquals(context.getString(R.string.investment_wallet_reallocate_funds_message,formatMinorUnits(60,"JPY"),formatMinorUnits(0,"JPY")))
        Assert.assertNull(primary());Assert.assertFalse(dismissed)
        compose.onNodeWithTag("transaction.funds.cancel").performClick()
        Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
        Assert.assertEquals(pending,runBlocking{TransactionInvestmentSaveSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}})
        save();review();compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        Assert.assertEquals(60L,primary()!!.payload.financeRawLong("amount_minor"))
        val rows=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}
        Assert.assertNotNull(rows.single{it.id==investmentLedgerIdentity(id(21),"cash-consumption-booked")}.deletedAt)
        Assert.assertEquals(-60L,rows.single{it.id==investmentLedgerIdentity(id(22),"cash-consumption-booked")}.payload.financeRawLong("amount_minor"))
    }

    @Test fun reallocationReviewFitsThreeLanguagesBothThemesAtActual130And320Dp() {
        runBlocking {
            wallet=wallet.copy(openingBalanceMinor=Long.MAX_VALUE,name="Cash / 共同ウォレット / Ví chung")
            val raw=wallet.toCloudRecord();store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
            val old=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!
            val posting=old.copy(payload=JsonObject(old.payload+buildJsonObject{put("amount_minor",Long.MAX_VALUE);put("accounting_amount_minor",Long.MAX_VALUE)}))
            store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
            seedEqualTotalHistory(Long.MAX_VALUE,Long.MAX_VALUE)
            val parent=repository.saveCategory(owner,CategoryDraft(id=id(40),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
            val child=repository.saveCategory(owner,CategoryDraft(id=id(41),name="Income child",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow();categories=categories+listOf(parent,child)
        }
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        val before=runBlocking{store.transactionInvestmentSaveSnapshot(owner)}
        val originals=linkedMapOf<android.content.res.Resources,android.content.res.Configuration>()
        fun configure(code:String) {
            val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
            (windows.map{it.context.resources}+context.resources).distinct().forEach{resource->
                originals.putIfAbsent(resource,android.content.res.Configuration(resource.configuration))
                resource.updateConfiguration(android.content.res.Configuration(resource.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))},resource.displayMetrics)
            };windows.forEach{it.dispatchConfigurationChanged(android.content.res.Configuration(it.resources.configuration))}
        }
        compose.setContent {
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),androidx.compose.ui.platform.LocalConfiguration provides config) {
                key(language,dark){MistiaTheme(darkTheme=dark){TransactionEditorSheet(owner.value,null,listOf(wallet),categories,emptyList(),now,"JPY",
                    initialState=initial().copy(primaryKind=TransactionPrimaryKind.INCOME,title="Income",amountText=Long.MAX_VALUE.toString(),categoryId=id(41),occurredAt="2026-10-22T00:00:01.500Z"),
                    onDismiss={},onSave={draft->saveInvestmentAwareEditorTransaction(owner,draft,"JPY","Automatic adjustment",device,now,repository,receipts)})}}
            }
        }
        fun complete(tag:String){
            val results=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(results)}
            val result=results.single();Assert.assertEquals(1.3f,result.layoutInput.density.fontScale,0.0001f)
            Assert.assertFalse(result.didOverflowHeight);Assert.assertEquals(result.layoutInput.text.length,result.getLineEnd(result.lineCount-1,true))
            for(line in 0 until result.lineCount){Assert.assertFalse(result.isLineEllipsized(line));Assert.assertTrue(result.getLineLeft(line)>=-1f);Assert.assertTrue(result.getLineRight(line)<=result.size.width+1f)}
            val paint=android.graphics.Paint();result.layoutInput.text.text.codePoints().forEach{c->if(!Character.isWhitespace(c))Assert.assertTrue("Missing glyph "+c,paint.hasGlyph(String(Character.toChars(c))))}
        }
        try{for(code in listOf("en","vi","ja"))for(theme in listOf(false,true)){
            compose.runOnIdle{configure(code);language=code;dark=theme}
            compose.onNodeWithTag("transaction.save").performClick();review();compose.runOnIdle{configure(code)}
            listOf("transaction.funds.title","transaction.funds.name."+id(1),"transaction.funds.message."+id(1),"transaction.funds.confirm.text","transaction.funds.cancel.text").forEach(::complete)
            val confirm=compose.onNodeWithTag("transaction.funds.confirm").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
            val cancel=compose.onNodeWithTag("transaction.funds.cancel").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
            Assert.assertTrue(confirm.height>=48*context.resources.displayMetrics.density-1);Assert.assertTrue(cancel.height>=48*context.resources.displayMetrics.density-1)
            Assert.assertTrue(confirm.left>=cancel.right || confirm.bottom<=cancel.top || cancel.bottom<=confirm.top)
            val screenshot=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
            java.io.File(context.getExternalFilesDir(null),"transaction-funds-reallocation-"+code+"-"+(if(theme)"dark" else "light")+"-font130-width320.png").outputStream().use{Assert.assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};screenshot.recycle()
            compose.onNodeWithTag("transaction.funds.cancel").performClick();Assert.assertEquals(before,runBlocking{store.transactionInvestmentSaveSnapshot(owner)})
        }}finally{compose.runOnIdle{originals.forEach{(resource,config)->resource.updateConfiguration(config,resource.displayMetrics)}}}
    }

    @Test fun renamingAnExpenseWithUnchangedReservedUsageKeepsTheExistingUseConfirmation() {
        val original=runBlocking {
            val draft=initial().toDraft("JPY",null,primaryCurrencyCode="JPY").draft!!
            val r=TransactionInvestmentSaveRequest(draft,draft.creationIdentity,null,"Automatic adjustment","JPY")
            val consent=(repository.prepareTransactionWithInvestmentFunds(owner,r,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent
            repository.saveTransactionWithInvestmentFunds(owner,r.copy(consent=consent),device,now).getOrThrow()
        }
        val postings=runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)}
        compose.setContent{Editor(original.copy(title="Renamed expense"))};save();review()
        compose.onNodeWithTag("transaction.funds.title").assertTextEquals(context.getString(R.string.investment_wallet_use_funds_title))
        compose.onNodeWithTag("transaction.funds.confirm").performClick();compose.waitUntil(5000){dismissed}
        Assert.assertEquals("Renamed expense",primary()!!.payload.financeRawString("title"))
        Assert.assertEquals(postings,runBlocking{store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_POSTING.table)})
    }

}
