package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import kotlinx.coroutines.flow.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.feature.overview.OverviewScreen

@RunWith(AndroidJUnit4::class)
class StoredTransactionEditorRouteTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var wallet:LedgerWalletRecord
    private lateinit var category:TransactionCategoryRecord
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time="2026-10-16T00:00:00Z"
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private val exchange=object:ExchangeRateRepository {
        override val rates=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
        override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)
    }
    private open class Receipts:TransactionReceiptImageRepository {
        override suspend fun receipt(transactionId:String):TransactionReceiptImageRecord?=null
        override suspend fun replaceReceipt(ownerUserId:UserId,transactionId:String,imageData:ByteArray,thumbnailData:ByteArray,contentType:String,now:String):Result<TransactionReceiptImageRecord> = error("Unexpected replace")
        override suspend fun imageData(receipt:TransactionReceiptImageRecord):Result<ByteArray> = error("Unexpected image read")
        override suspend fun thumbnailData(receipt:TransactionReceiptImageRecord):Result<ByteArray> = error("Unexpected thumbnail read")
        override suspend fun deleteReceipt(transactionId:String)=Result.success(Unit)
        override suspend fun deleteAccount(ownerUserId:UserId)=Result.success(Unit)
    }
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        wallet=repo.saveWallet(owner,WalletDraft(name="Cash VND",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=Long.MAX_VALUE),device,time).getOrThrow()
        val parent=repo.saveCategory(owner,CategoryDraft(name="Home",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()
        category=repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,time).getOrThrow()
    }
    private fun records(subject:UserId=owner)=runBlocking {repo.observeTransactions(subject).first()}
    private fun seed(name:String="Original",amount:Long=9007199254740993L)=runBlocking {
        repo.saveTransaction(owner,TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title=name,amountMinor=amount,occurredAt=time,sourceWalletId=wallet.id,categoryId=category.id),device,time).getOrThrow()
    }
    @Composable private fun Route(id:String,subject:UserId=owner,repository:FinanceRepository=repo,receipts:TransactionReceiptImageRepository=Receipts(),dismiss:()->Unit={},dark:Boolean=false) {
        MistiaTheme(darkTheme=dark) {StoredTransactionEditorRoute(subject,id,repository,exchange,receipts,{device},"VND",dismiss)}
    }
    private fun title()=compose.onNode(hasText(context.getString(R.string.transactions_transactioneditor_expense_name)) and hasSetTextAction())
    private fun save()=compose.onNodeWithText(context.getString(R.string.common_save)).performScrollTo().performClick()
    private fun awaitTitle(value:String) {compose.waitUntil(5000) {compose.onAllNodes(hasSetTextAction() and hasText(value)).fetchSemanticsNodes().isNotEmpty()}}
    @Test fun realOverviewTapOpensStoredFormAndSavesExactAmountAndMatchingOutbox() {
        val original=seed();var selected by mutableStateOf<String?>(null)
        compose.setContent {MistiaTheme(darkTheme=false) {
            OverviewScreen(owner,repo,MutableStateFlow(SyncStatus.Idle),primaryCurrencyCode="VND",onOpenTransaction={selected=it})
            selected?.let {id -> StoredTransactionEditorRoute(owner,id,repo,exchange,Receipts(),{device},"VND",onDismiss={selected=null})}
        }}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.recent.${original.id}").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.recent.${original.id}").performScrollTo().performClick();awaitTitle("Original")
        compose.onNodeWithTag("transaction.amount").performScrollTo().assertTextContains("9,007,199,254,740,993")
        title().performScrollTo().performTextReplacement("Edited from Overview");save()
        compose.waitUntil(5000) {records().single().title=="Edited from Overview" && selected==null}
        val saved=records().single();Assert.assertEquals(original.amountMinor,saved.amountMinor);Assert.assertEquals(original.id,saved.id)
        Assert.assertEquals(saved.toPayload(),runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).single()}.mutation.payload)
    }
    @Test fun realOverviewDayHoldAndRowOpenStoredFormThenSaveExactMoneyAndMatchingOutbox() {
        val original=seed();var selected by mutableStateOf<String?>(null)
        compose.setContent {MistiaTheme(darkTheme=false) {
            OverviewScreen(owner,repo,MutableStateFlow(SyncStatus.Idle),primaryCurrencyCode="VND",onOpenTransaction={selected=it},overlayPresented=selected!=null)
            selected?.let {id -> StoredTransactionEditorRoute(owner,id,repo,exchange,Receipts(),{device},"VND",onDismiss={selected=null})}
        }}
        val day=java.time.Instant.parse(time).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        val monday=java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY)
        val historyWeeks=java.time.temporal.ChronoUnit.WEEKS.between(day.with(monday),java.time.LocalDate.now().with(monday)).toInt().coerceAtLeast(0)
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.chart.pager").fetchSemanticsNodes().isNotEmpty()}
        repeat(historyWeeks) {compose.onNodeWithTag("overview.chart.pager").performScrollTo().performTouchInput {swipeRight()}}
        val bar=hasTestTag("overview.chart.day.$day") and hasContentDescription(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(original.amountMinor,"VND"),substring=true)
        compose.waitUntil(5000) {compose.onAllNodes(bar).fetchSemanticsNodes().isNotEmpty()}
        compose.onNode(bar).performScrollTo().performTouchInput {down(center);advanceEventTime(400);up()}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.day.row.${original.id}").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.day.row.${original.id}").performScrollTo().performTouchInput {click()};awaitTitle("Original")
        compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist()
        compose.onNodeWithTag("transaction.amount").performScrollTo().assertTextContains("9,007,199,254,740,993")
        title().performScrollTo().performTextReplacement("Edited from day details");save()
        compose.waitUntil(5000) {records().single().title=="Edited from day details" && selected==null}
        val saved=records().single();Assert.assertEquals(original.amountMinor,saved.amountMinor);Assert.assertEquals(original.id,saved.id)
        Assert.assertEquals(saved.toPayload(),runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_TRANSACTION,Long.MAX_VALUE).single()}.mutation.payload)
    }
    @Test fun unreadableOriginalDayRowOpensUnavailableStoredEditorWithoutWritingZero() {
        val original=seed("Unreadable original",7)
        val damaged=original.toCloudRecord().let {it.copy(payload=JsonObject(it.payload+mapOf("amount_minor" to JsonPrimitive("broken"),"reporting_expense_minor" to JsonPrimitive(3))))}
        runBlocking {store.commitMutation(damaged,PendingMutation(CloudEntity.LEDGER_TRANSACTION,damaged.id,owner.value,MutationKind.UPSERT,damaged.payload,time,0,device))}
        fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
        val before=snapshot();var selected by mutableStateOf<String?>(null)
        compose.setContent {MistiaTheme(darkTheme=false) {
            OverviewScreen(owner,repo,MutableStateFlow(SyncStatus.Idle),primaryCurrencyCode="VND",onOpenTransaction={selected=it},overlayPresented=selected!=null)
            selected?.let {id -> StoredTransactionEditorRoute(owner,id,repo,exchange,Receipts(),{device},"VND",onDismiss={selected=null})}
        }}
        val day=java.time.Instant.parse(time).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        val monday=java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY)
        val weeks=java.time.temporal.ChronoUnit.WEEKS.between(day.with(monday),java.time.LocalDate.now().with(monday)).toInt().coerceAtLeast(0)
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.chart.pager").fetchSemanticsNodes().isNotEmpty()}
        repeat(weeks) {compose.onNodeWithTag("overview.chart.pager").performScrollTo().performTouchInput {swipeRight()}}
        val bar=hasTestTag("overview.chart.day.$day") and hasContentDescription(vn.com.quyln.mistia.core.designsystem.formatMinorUnits(3,"VND"),substring=true)
        compose.waitUntil(5000) {compose.onAllNodes(bar).fetchSemanticsNodes().isNotEmpty()}
        compose.onNode(bar).performScrollTo().performTouchInput {down(center);advanceEventTime(400);up()}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.day.row.${original.id}").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.day.amount.${original.id}",useUnmergedTree=true).assertTextEquals("\u2014")
        compose.onNodeWithTag("overview.day.row.${original.id}").performScrollTo().performTouchInput {click()}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("overview.day.sheet").assertDoesNotExist();compose.onNodeWithTag("transaction.amount").assertDoesNotExist()
        compose.onNodeWithText(context.getString(R.string.common_save)).assertDoesNotExist();Assert.assertEquals(original.id,selected);Assert.assertEquals(before,snapshot())
    }
    @Test fun switchingRecordClosesOldCalculatorAndLoadsOnlySelectedOwnedAmount() {
        val first=seed("First",123);val second=seed("Second",456);var id by mutableStateOf(first.id)
        val before=records().associateBy {it.id}
        compose.setContent {Route(id)};awaitTitle("First")
        compose.onNodeWithTag("transaction.amount.calculator").performScrollTo().performClick()
        compose.runOnIdle {id=second.id};awaitTitle("Second")
        compose.onNodeWithTag("amountCalculator.dialog").assertDoesNotExist();compose.onNodeWithTag("transaction.amount").assertTextContains("456")
        Assert.assertEquals(before,records().associateBy {it.id})
    }
    @Test fun foreignOrMissingTargetShowsUnavailableAndNeverTurnsIntoNewDraft() {
        val original=seed();val before=records()
        compose.setContent {Route(original.id,other)}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("transaction.stored.unavailable").assertExists()
        compose.onNodeWithTag("transaction.amount").assertDoesNotExist();Assert.assertEquals(before,records());Assert.assertTrue(records(other).isEmpty())
    }
    @Test fun oldNonCancellableSaveCannotDismissReplacementRecord() {
        val first=seed("First",123);val second=seed("Second",456)
        var id by mutableStateOf(first.id);var dismissed=false
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        val wrapped=object:FinanceRepository by repo {
            override suspend fun saveTransaction(ownerUserId:UserId,draft:TransactionDraft,deviceId:String,now:String):Result<LedgerTransactionRecord> {
                val result=repo.saveTransaction(ownerUserId,draft,deviceId,now);started.complete(Unit)
                withContext(NonCancellable) {release.await()};finished.complete(Unit);return result
            }
        }
        compose.setContent {Route(id,repository=wrapped,dismiss={dismissed=true})};awaitTitle("First")
        try {
            title().performTextReplacement("Old saved");save();compose.waitUntil(5000) {started.isCompleted}
            compose.runOnIdle {id=second.id};awaitTitle("Second");title().performTextReplacement("New private draft")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            title().assertTextContains("New private draft");Assert.assertFalse(dismissed)
            Assert.assertEquals("Old saved",records().single {it.id==first.id}.title);Assert.assertEquals(second,records().single {it.id==second.id})
        } finally {release.complete(Unit)}
    }
    @Test fun receiptEnvelopeIsCheckedBeforeAnyForeignImageBytesAreRead() {
        val original=seed();var imageReads=0
        val receipts=object:Receipts() {
            override suspend fun receipt(transactionId:String)=TransactionReceiptImageRecord(device,other.value,transactionId,"private","private","image/jpeg",10,time,time)
            override suspend fun imageData(receipt:TransactionReceiptImageRecord):Result<ByteArray> {imageReads++;return Result.success(byteArrayOf(1))}
        }
        compose.setContent {Route(original.id,receipts=receipts)};awaitTitle("Original")
        compose.waitUntil(5000) {compose.onAllNodesWithText(context.getString(R.string.transactions_transactioneditor_couldn_t_load_the_saved_receipt_image)).fetchSemanticsNodes().isNotEmpty()}
        Assert.assertEquals(0,imageReads);Assert.assertEquals(original,records().single())
    }
    @Test fun importedUsdKeepsMajorMinorMeaningAndExplicitVndReportingPair() {
        val usd=runBlocking {repo.saveWallet(owner,WalletDraft(name="Cash USD",kind=WalletKind.CASH,currencyCode="USD",openingBalanceMinor=100000),device,time).getOrThrow()}
        val original=runBlocking {repo.saveTransaction(owner,TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Imported USD",amountMinor=1375,
            occurredAt=time,sourceWalletId=usd.id,categoryId=category.id,reportingCurrencyCode="VND",reportingAmountMinor=20000,conversionMode=CurrencyConversionMode.MANUAL),device,time).getOrThrow()}
        compose.setContent {Route(original.id)};awaitTitle("Imported USD")
        compose.onNodeWithTag("transaction.amount").performScrollTo().assertTextContains("13.75").performTextReplacement("14.25")
        compose.onNodeWithTag("transaction.reportingAmount").performScrollTo().performTextReplacement("30000");save()
        compose.waitUntil(5000) {records().single().amountMinor==1425L}
        val saved=records().single();Assert.assertEquals("USD",saved.sourceCurrencyCode);Assert.assertEquals("VND",saved.reportingCurrencyCode)
        Assert.assertEquals(30000L,saved.reportingAmountMinor);Assert.assertEquals(original.id,saved.id)
    }
    @Test fun ownerSwitchClearsPrivateDraftAndNeverLoadsTheOtherOwnersRecordBySameId() {
        val original=seed();var subject by mutableStateOf(owner);val before=records()
        compose.setContent {Route(original.id,subject)};awaitTitle("Original");title().performTextReplacement("Private unsaved")
        compose.runOnIdle {subject=other}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Private unsaved").assertDoesNotExist();compose.onNodeWithTag("transaction.amount").assertDoesNotExist()
        Assert.assertEquals(before,records());Assert.assertTrue(records(other).isEmpty())
    }
    @Test fun cancelledReceiptLookupNeverReadsOldImageOrReplacesTheNextRecordsReceiptState() {
        val first=seed("First",123);val second=seed("Second",456)
        val started=CompletableDeferred<Unit>();val release=CompletableDeferred<Unit>();val finished=CompletableDeferred<Unit>()
        var id by mutableStateOf(first.id);var imageReads=0
        val receipts=object:Receipts() {
            override suspend fun receipt(transactionId:String):TransactionReceiptImageRecord? {
                if(transactionId!=first.id) return null
                started.complete(Unit);withContext(NonCancellable) {release.await()};finished.complete(Unit)
                return TransactionReceiptImageRecord(device,owner.value,first.id,"old","old","image/jpeg",10,time,time)
            }
            override suspend fun imageData(receipt:TransactionReceiptImageRecord):Result<ByteArray> {imageReads++;return Result.success(byteArrayOf(1))}
        }
        compose.setContent {Route(id,receipts=receipts)}
        try {
            awaitTitle("First");compose.waitUntil(5000) {started.isCompleted};compose.runOnIdle {id=second.id};awaitTitle("Second")
            compose.runOnIdle {release.complete(Unit)};compose.waitUntil(5000) {finished.isCompleted}
            title().assertTextContains("Second");Assert.assertEquals(0,imageReads)
            compose.onNodeWithText(context.getString(R.string.transactions_transactioneditor_couldn_t_load_the_saved_receipt_image)).assertDoesNotExist()
            Assert.assertEquals(listOf("First","Second"),records().map {it.title}.sorted())
        } finally {release.complete(Unit)}
    }
    @Test fun paidCreditCardLinkedTargetIsHeldBeforeEditableFieldsAreShown() {
        val card=runBlocking {repo.saveCreditCard(owner,CreditCardDraft(name="Card",currencyCode="VND",creditLimitMinor=10000),device,time).getOrThrow()}
        val original=runBlocking {repo.saveTransaction(owner,TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Paid card charge",amountMinor=100,
            occurredAt=time,sourceWalletId=card.wallet.id,categoryId=category.id),device,time).getOrThrow()}
        val due=DueOccurrenceRecord(java.util.UUID.randomUUID().toString(),owner.value,"creditCard",card.wallet.id,"2026-10",time,100,"paid",time,original.id,time,time,null,0,device)
        runBlocking {store.commitMutation(due.toCloudRecord(),PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD,due.id,owner.value,MutationKind.UPSERT,due.toPayload(),time,0,device))}
        val before=records()
        compose.setContent {Route(original.id)}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText(context.getString(R.string.transactions_transactioneditor_this_transaction_is_part_of_a_paid)).assertExists()
        compose.onNodeWithTag("transaction.amount").assertDoesNotExist();Assert.assertEquals(before,records())
    }
    @Test fun storedEditorAndCalculatorRenderExactVndLightDarkAtFont130WithoutWrites() {
        val original=seed();val before=records();var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Route(original.id,dark=dark)}
        }
        awaitTitle("Original")
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme=="dark"}
            compose.onNodeWithTag("transaction.amount").performScrollTo().assertTextContains("9,007,199,254,740,993")
            capture("overview-stored-editor-$theme-font130.png")
            compose.onNodeWithTag("transaction.amount.calculator").performScrollTo().performClick()
            compose.onNodeWithTag("amountCalculator.result").assertTextEquals("9,007,199,254,740,993")
            capture("overview-stored-calculator-$theme-font130.png")
            compose.onNodeWithTag("amountCalculator.cancel").performClick()
        }
        Assert.assertEquals(before,records())
    }
    private fun capture(name:String) {
        compose.waitForIdle()
        val automation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline=android.os.SystemClock.uptimeMillis()+5000
        var previous:android.graphics.Bitmap?=null
        var stableFrames=0
        var stable:android.graphics.Bitmap?=null
        while(android.os.SystemClock.uptimeMillis()<deadline) {
            val frame=checkNotNull(automation.takeScreenshot())
            stableFrames=if(previous?.sameAs(frame)==true) stableFrames+1 else 0
            previous?.recycle();previous=frame
            if(stableFrames>=3) {stable=frame;break}
        }
        if(stable==null) previous?.recycle()
        val bitmap=checkNotNull(stable) {"Screenshot did not reach stable compositor frames: $name"}
        java.io.File(ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        bitmap.recycle()
    }
    @Test fun storedEditorOpensAtLargeHeightLikeSwiftBeforeAnyScrollOrGesture() {
        val original=seed()
        compose.setContent {Route(original.id)};awaitTitle("Original");compose.waitForIdle()
        val image=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
        val height=image.height;image.recycle()
        val top=compose.onNodeWithText(context.getString(R.string.transactions_transactioneditor_edit_transaction)).fetchSemanticsNode().boundsInRoot.top
        Assert.assertTrue("Stored editor heading opens too low: top=$top screenHeight=$height",top<height/3f)
        Assert.assertEquals(original,records().single())
    }
    @Test fun failedDependencyLoadCanRetryWithoutCreatingOrMutatingAnyRecord() {
        val original=seed();var attempts=0
        val wrapped=object:FinanceRepository by repo {
            override fun observeWallets(ownerUserId:UserId):Flow<List<LedgerWalletRecord>> = flow {
                if(attempts++==0) throw java.io.IOException("Synthetic read failure")
                emitAll(repo.observeWallets(ownerUserId))
            }
        }
        compose.setContent {Route(original.id,repository=wrapped)}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.retry").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("transaction.amount").assertDoesNotExist();compose.onNodeWithTag("transaction.stored.retry").performClick()
        awaitTitle("Original");Assert.assertEquals(original,records().single());Assert.assertTrue(attempts>=2)
    }
    @Test fun unsupportedFamilyRecordIsReadOnlyAndCannotBecomeAnOrdinaryDraft() {
        val original=seed();val imported=original.copy(primaryKindWireValue="transfer",transferSubtypeWireValue="familyTransfer")
        runBlocking {store.commitMutation(imported.toCloudRecord(),PendingMutation(CloudEntity.LEDGER_TRANSACTION,imported.id,owner.value,MutationKind.UPSERT,imported.toPayload(),time,0,device))}
        compose.setContent {Route(imported.id)}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText(context.getString(R.string.transactions_stored_editor_unsupported)).assertExists()
        compose.onNodeWithTag("transaction.amount").assertDoesNotExist();Assert.assertEquals(imported,records().single())
    }
    @Test fun malformedStoredCalendarIsHeldInsteadOfShowingCurrentDateAsItsValue() {
        val original=seed();val raw=MutableStateFlow(listOf(original.copy(occurredAt="broken-date").toCloudRecord()))
        val wrapped=object:FinanceRepository by repo {
            override fun observe(entity:CloudEntity,ownerUserId:UserId):Flow<List<CloudRecord>> = if(entity==CloudEntity.LEDGER_TRANSACTION) raw else repo.observe(entity,ownerUserId)
        }
        compose.setContent {Route(original.id,repository=wrapped)}
        compose.waitUntil(5000) {compose.onAllNodesWithTag("transaction.stored.unavailable").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("transaction.amount").assertDoesNotExist();Assert.assertEquals(original,records().single())
    }
    @Test fun restoredRouteRetainsOwnedUnsavedDraftAcrossRepositoryReload() {
        val original=seed();val restore=androidx.compose.ui.test.junit4.StateRestorationTester(compose)
        restore.setContent {Route(original.id)};awaitTitle("Original")
        title().performScrollTo().performTextReplacement("Restored private draft")
        compose.onNodeWithTag("transaction.amount").performScrollTo().performTextReplacement("9007199254740995")
        restore.emulateSavedInstanceStateRestore();awaitTitle("Restored private draft")
        compose.onNodeWithTag("transaction.amount").performScrollTo().assertTextContains("9,007,199,254,740,995")
        Assert.assertEquals(original,records().single())
    }
}
