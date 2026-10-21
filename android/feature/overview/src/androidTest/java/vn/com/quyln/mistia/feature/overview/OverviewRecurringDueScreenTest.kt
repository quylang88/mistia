package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewRecurringDueScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var category:TransactionCategoryRecord
    private lateinit var wallet:LedgerWalletRecord
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val now=Instant.now().toString()
    private val zone=ZoneId.systemDefault()
    private val month=YearMonth.now(zone)
    private val today=LocalDate.now(zone)
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db)
        repo=OfflineFirstFinanceRepository(store,zone,systemCategoryCatalog(context))
        val parent=repo.saveCategory(owner,CategoryDraft(name="Bills",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        category=repo.saveCategory(owner,CategoryDraft(name="Internet",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id,iconSymbolName="wifi"),device,now).getOrThrow()
        wallet=repo.saveWallet(owner,WalletDraft(name="JPY cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=10000),device,now).getOrThrow()
    }
    private fun bill(amount:Long?=5000)=runBlocking {repo.saveRecurringBill(owner,RecurringBillDraft("Internet due",category.id,amount,wallet.id,"JPY",paymentStartDay=today.dayOfMonth,zoneId=zone),device,now).getOrThrow()}
    private fun seed(row:CloudRecord)=runBlocking {store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->UpcomingDueReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(subject,it.table) to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository=repo,onSelect:(UpcomingDuePaymentTarget)->Unit={},dark:Boolean=false) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,Modifier.padding(padding),onOpenRecurringDue=onSelect)
        }}
    }
    private fun id(bill:RecurringBillPlanRecord)="recurringBill-${bill.id}-$month"
    private fun reveal() {
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasTestTag("overview.due.section"))
        compose.onNodeWithTag("overview.due.section").performScrollTo()
    }
    private fun amount(bill:RecurringBillPlanRecord,minor:Long) {
        reveal();val text=formatMinorUnits(minor,"JPY")
        compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.amount.${id(bill)}",useUnmergedTree=true).fetchSemanticsNodes().singleOrNull()?.config?.getOrNull(SemanticsProperties.Text)?.any {it.text==text}==true}
        compose.onNodeWithTag("overview.due.amount.${id(bill)}",useUnmergedTree=true).assertTextEquals(text)
    }
    @Test fun currentBillShowsExactSourceMoneyAndTapRetainsItsOriginalSourceCycle() {
        val bill=bill(9007199254740993L);var selected:UpcomingDuePaymentTarget?=null
        withoutWrites {compose.setContent {Screen(onSelect={selected=it})};amount(bill,9007199254740993L)
            compose.onNodeWithTag("overview.due.row.${id(bill)}").performClick()
            compose.runOnIdle {Assert.assertEquals(UpcomingDuePaymentTarget(owner.value,DueSourceKind.RECURRING_BILL,bill.id,month),selected)}}
    }
    @Test fun variableBillHasIntentionalNoAmountLabelWhileUnreadableRequiredMoneyIsUnavailable() {
        val bill=bill(null)
        withoutWrites {compose.setContent {Screen()};reveal();compose.onNodeWithTag("overview.due.amount.${id(bill)}",useUnmergedTree=true).assertTextEquals(context.getString(R.string.overview_overview_no_amount_yet))}
        seed(bill.toCloudRecord().let {it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonPrimitive("5000"))))})
        withoutWrites {reveal();compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.unavailable").fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag("overview.due.unavailable").assertExists();compose.onNodeWithTag("overview.due.row.${id(bill)}").assertDoesNotExist()}
        seed(bill.copy(amountMinor=6000).toCloudRecord());withoutWrites {amount(bill,6000)}
    }
    @Test fun livePaidOrArchivedSourceRemovesItsAlertWithoutAReadWritingAnything() {
        val bill=bill();withoutWrites {compose.setContent {Screen()};amount(bill,5000)}
        val occurrence=DueOccurrenceRecord("88888888-8888-8888-8888-888888888888",owner.value,"recurringBill",bill.id,month.toString(),now,5000,"paid",now,null,now,now,null,0,device)
        seed(occurrence.toCloudRecord())
        withoutWrites {compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.section").fetchSemanticsNodes().isEmpty()}}
        seed(occurrence.copy(deletedAt=now).toCloudRecord());withoutWrites {amount(bill,5000)}
        seed(bill.copy(isArchived=true).toCloudRecord())
        withoutWrites {compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.section").fetchSemanticsNodes().isEmpty()}}
    }
    @Test fun withheldReadCannotPublishEmptyOrKnownDuesAndLoadedEmptyHidesTheSection() {
        bill();val values=MutableStateFlow<UpcomingDueReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<UpcomingDueReadSnapshot> = values.filterNotNull()}
        withoutWrites {compose.setContent {Screen(source=source)};reveal();compose.onNodeWithTag("overview.due.unavailable").assertExists()
            compose.runOnIdle {values.value=UpcomingDueReadSnapshot(owner,emptyList())}
            compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.section").fetchSemanticsNodes().isEmpty()}}
    }
    @Test fun failedAfterLoadedClearsOldAlertAndRetryReadsTheCurrentRoomRows() {
        val bill=bill();val complete=runBlocking {repo.observeUpcomingDueReadSnapshot(owner).first()}
        val release=kotlinx.coroutines.CompletableDeferred<Unit>();val first=java.util.concurrent.atomic.AtomicBoolean(true)
        val source=object:FinanceRepository by repo {override fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<UpcomingDueReadSnapshot> = flow {
            if(first.getAndSet(false)){emit(complete);release.await();throw IllegalStateException("test due read failed")}
            emitAll(repo.observeUpcomingDueReadSnapshot(owner))
        }}
        withoutWrites {compose.setContent {Screen(source=source)};amount(bill,5000);compose.runOnIdle {release.complete(Unit)}
            reveal();compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.unavailable").fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithTag("overview.due.unavailable").assertExists();compose.onNodeWithTag("overview.due.row.${id(bill)}").assertDoesNotExist()}
        seed(bill.copy(amountMinor=6000).toCloudRecord())
        withoutWrites {compose.onNodeWithTag("overview.due.retry").performScrollTo().performClick();amount(bill,6000)}
    }
    @Test fun ownerReplacementAndWrongOwnerOrLateSnapshotCannotExposePrivateDue() {
        val bill=bill();val complete=runBlocking {repo.observeUpcomingDueReadSnapshot(owner).first()}
        var subject by mutableStateOf(owner);val first=MutableStateFlow<UpcomingDueReadSnapshot?>(complete);val next=MutableStateFlow<UpcomingDueReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeUpcomingDueReadSnapshot(owner:UserId):Flow<UpcomingDueReadSnapshot> = if(owner==this@OverviewRecurringDueScreenTest.owner) first.filterNotNull() else next.filterNotNull()}
        withoutWrites {compose.setContent {Screen(subject,source)};amount(bill,5000)
            compose.runOnIdle {subject=other};reveal();compose.onNodeWithText(bill.name).assertDoesNotExist()
            compose.runOnIdle {first.value=complete.copy(rows=complete.rows.reversed());next.value=complete};reveal();compose.onNodeWithText(bill.name).assertDoesNotExist()
            compose.runOnIdle {next.value=UpcomingDueReadSnapshot(other,emptyList())}
            compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.section").fetchSemanticsNodes().isEmpty()}}
    }
    @Test fun actuallyLoadedEmptyHasNoDuePlaceholder() {
        val complete=runBlocking {repo.observeUpcomingDueReadSnapshot(owner).first()}
        val source=object:FinanceRepository by repo {override fun observeUpcomingDueReadSnapshot(owner:UserId)=flowOf(complete)}
        withoutWrites {compose.setContent {Screen(source=source)};compose.waitForIdle();compose.onNodeWithTag("overview.due.section").assertDoesNotExist()}
    }
    @Test fun exactVariableAndUnavailableDuesFitAtActual130InThreeLanguagesLightDark() {
        val exact=bill(9007199254740993L).copy(name="Internet • インターネット",iconSymbolName="mistia.category.expense.home_bills.internet")
        seed(exact.toCloudRecord())
        val variable=bill(null).copy(name="Electricity • Điện",iconSymbolName="mistia.plan.bill");seed(variable.toCloudRecord())
        val loan=runBlocking {repo.saveInstallment(owner,InstallmentDraft("33333333-3333-3333-3333-333333333333","Loan • Trả góp",1375,today.dayOfMonth,1,12,wallet.id,"JPY"),device,now).getOrThrow()}
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {Screen(dark=dark)}
        }
        fun complete(tag:String) {
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithTag(tag,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
            Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
            for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
        }
        fun capture(kind:String) {
            compose.onNodeWithTag("overview.due.section").performScrollTo()
            val bitmap=compose.onNodeWithTag("overview.due.section").captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"overview-recurring-due-$kind-$language-${if(dark) "dark" else "light"}-font130.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)
            }
        }
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) {
            withoutWrites {
                compose.runOnIdle {language=code;dark=theme};amount(exact,9007199254740993L)
                compose.onNodeWithTag("overview.due.amount.${id(variable)}",useUnmergedTree=true).assertTextEquals(context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply {setLocale(java.util.Locale.forLanguageTag(code))}).getString(R.string.overview_overview_no_amount_yet))
                for(source in listOf(exact,variable)) {complete("overview.due.amount.${id(source)}");complete("overview.due.detail.${id(source)}")}
                complete("overview.due.amount.installment-${loan.id}-$month");capture("exact-variable")
            }
            seed(exact.toCloudRecord().let {it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonPrimitive("broken"))))})
            withoutWrites {compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.due.unavailable").fetchSemanticsNodes().isNotEmpty()};reveal();complete("overview.due.unavailable");capture("unavailable")}
            seed(exact.toCloudRecord())
        }
    }
    @Test fun dueHeaderAndCardHaveTheSwiftSectionGeometry() {
        val bill=bill();compose.setContent {Screen()};amount(bill,5000)
        val label=context.getString(R.string.overview_overview_upcoming_due_items)
        val title=compose.onNodeWithText(label,ignoreCase=true,useUnmergedTree=true)
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        title.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        Assert.assertEquals(13f,layouts.single().layoutInput.style.fontSize.value,0.0001f)
        val header=title.getUnclippedBoundsInRoot();val card=compose.onNodeWithTag("overview.due.card",useUnmergedTree=true).getUnclippedBoundsInRoot()
        Assert.assertEquals(8f,(card.top-header.bottom).value,0.75f)
        val icon=compose.onNodeWithTag("overview.due.icon.${id(bill)}",useUnmergedTree=true).getUnclippedBoundsInRoot()
        Assert.assertEquals(30f,(icon.right-icon.left).value,0.75f);Assert.assertEquals(30f,(icon.bottom-icon.top).value,0.75f)
        Assert.assertEquals(14f,(icon.left-card.left).value,0.75f)
    }

}
