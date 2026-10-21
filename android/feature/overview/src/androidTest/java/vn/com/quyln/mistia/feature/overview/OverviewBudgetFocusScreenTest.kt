package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewBudgetFocusScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var parent:TransactionCategoryRecord
    private lateinit var child:TransactionCategoryRecord
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val time=Instant.now().toString()
    private val zone=ZoneId.systemDefault()
    private val month=YearMonth.now(zone)
    private val rateRows=MutableStateFlow<List<ExchangeRateSnapshot>>(emptyList())
    private val rates=object:ExchangeRateRepository {override val rates=rateRows;override suspend fun refreshIfStale(nowEpochMillis:Long)=Result.success(Unit)}
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        parent=repo.saveCategory(owner,CategoryDraft(name="Living",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()
        child=repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,time).getOrThrow()
    }
    private fun plan(code:String="JPY",limit:Long=1000)=runBlocking {
        repo.saveBudget(owner,BudgetDraft(child.id,month.atDay(1).atStartOfDay(zone).toInstant().toString(),limit,code,zoneId=zone),device,time).getOrThrow()
    }
    private fun row(amount:Long=7,code:String?="JPY",wallet:String?=null):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("title","Budget exact read");put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code",code?.let(::JsonPrimitive) ?: JsonNull);put("category_id",child.id);wallet?.let {put("source_wallet_id",it)}
            put("is_archived",false);put("occurred_at",time);put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun seed(record:CloudRecord)=runBlocking {store.commitMutation(record,PendingMutation(CloudEntity.fromTable(record.entity)!!,record.id,record.ownerUserId,MutationKind.UPSERT,record.payload,time,0,device))}
    private fun snapshot()=runBlocking {listOf(owner,other).associateWith {subject ->listOf(CloudEntity.BUDGET_PLAN,CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY).associateWith {repo.observe(it,subject).first() to store.pendingMutations(subject,it,Long.MAX_VALUE)}}}
    private fun withoutWrites(action:()->Unit){val before=snapshot();action();Assert.assertEquals(before,snapshot())}
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    @Composable private fun Screen(subject:UserId=owner,primary:String="JPY",source:FinanceRepository=repo,dark:Boolean=false) {
        MistiaTheme(darkTheme=dark) {androidx.compose.material3.Scaffold {padding ->
            OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding),primaryCurrencyCode=primary,exchangeRates=rates)
        }}
    }
    private fun money()="overview.budget.money.${parent.id}"
    private fun reveal() {
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasTestTag("overview.budget.focus"))
        compose.onNodeWithTag("overview.budget.focus").performScrollTo()
    }
    private fun known(amount:Long,limit:Long=1000) {
        reveal();contains(money(),"${formatMinorUnits(amount,"JPY")} / ${formatMinorUnits(limit,"JPY")}")
    }
    private fun held() {
        reveal();compose.onNodeWithTag("overview.budget.unavailable").assertExists()
    }
    private fun contains(tag:String,text:String) {
        val exact=SemanticsMatcher("exact complete budget amount") {node ->
            node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Text)?.singleOrNull()?.text?.let {it==text || it.endsWith(": $text")}==true
        }
        try {compose.waitUntil(5000) {compose.onAllNodes(hasTestTag(tag) and exact,useUnmergedTree=true).fetchSemanticsNodes().isNotEmpty()}}
        catch(error:Throwable) {
            val actual=compose.onAllNodesWithTag(tag,useUnmergedTree=true).fetchSemanticsNodes().map {it.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Text)}
            throw AssertionError("Expected$tag=$text; actual=$actual",error)
        }
        compose.onNodeWithTag(tag,useUnmergedTree=true).assert(exact)
    }
    @Test fun exceededBudgetReplacesPlaceholderWithExactWatchlistAndUpdatesWithoutReadWrites() {
        val saved=plan();val raw=row(1200);seed(raw)
        withoutWrites {compose.setContent {Screen()};known(1200);contains("overview.budget.percent.${parent.id}","120%")}
        seed(raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive(1500)))))
        withoutWrites {known(1500);contains("overview.budget.percent.${parent.id}","150%")}
        seed(child.copy(isArchived=true).toCloudRecord());withoutWrites {known(1500)}
        seed(saved.copy(isArchived=true).toCloudRecord())
        withoutWrites {compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.budget.focus").fetchSemanticsNodes().isEmpty()}}
    }
    @Test fun stableOnlyBudgetAndLoadedEmptyHaveNoWatchlistSection() {
        plan();seed(row(1))
        withoutWrites {compose.setContent {Screen()};compose.waitForIdle();compose.onNodeWithTag("overview.budget.focus").assertDoesNotExist()}
    }
    @Test fun unreadableRequiredMoneyStaysVisibleAsUnknownAndRepairRestoresTheActualAlert() {
        plan();val raw=row(1200);seed(raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive("1200")))))
        withoutWrites {compose.setContent {Screen()};held();contains(money(),"— / ${formatMinorUnits(1000,"JPY")}");contains("overview.budget.percent.${parent.id}","—")
            compose.onNodeWithTag("overview.budget.progress.${parent.id}").assertDoesNotExist()}
        seed(raw);withoutWrites {known(1200)}
    }
    @Test fun snapshotWithheldCannotPublishAnEmptyHealthyOverviewBudget() {
        plan();seed(row(1200));val complete=runBlocking {repo.observeBudgetReadSnapshot(owner).first()};val values=MutableStateFlow<BudgetReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = values.filterNotNull()}
        withoutWrites {compose.setContent {Screen(source=source)};held();compose.onNodeWithTag(money()).assertDoesNotExist()
            compose.runOnIdle {values.value=complete};known(1200)}
    }
    @Test fun loadedThenFailedClearsAmountsAndRetryReadsCurrentRows() {
        plan();val raw=row(1200);seed(raw);val complete=runBlocking {repo.observeBudgetReadSnapshot(owner).first()}
        val release=kotlinx.coroutines.CompletableDeferred<Unit>();val first=java.util.concurrent.atomic.AtomicBoolean(true)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = flow {
            if(first.getAndSet(false)){emit(complete);release.await();throw IllegalStateException("test budget storage unavailable")}
            emitAll(repo.observeBudgetReadSnapshot(owner))
        }}
        withoutWrites {compose.setContent {Screen(source=source)};known(1200);compose.runOnIdle {release.complete(Unit)};held();compose.onNodeWithTag(money()).assertDoesNotExist()}
        seed(raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive(1300)))))
        withoutWrites {compose.onNodeWithTag("overview.budget.retry").performScrollTo().performClick();known(1300)}
    }
    @Test fun replacementOwnerAndLateSnapshotNeverExposeOldPrivateAlert() {
        plan();seed(row(1200));val complete=runBlocking {repo.observeBudgetReadSnapshot(owner).first()}
        val first=MutableStateFlow<BudgetReadSnapshot?>(complete);val second=MutableStateFlow<BudgetReadSnapshot?>(null);var subject by mutableStateOf(owner)
        val source=object:FinanceRepository by repo {override fun observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot> = if(owner==this@OverviewBudgetFocusScreenTest.owner) first.filterNotNull() else second.filterNotNull()}
        withoutWrites {compose.setContent {Screen(subject,source=source)};known(1200);compose.runOnIdle {subject=other};held();compose.onNodeWithTag(money()).assertDoesNotExist()
            compose.runOnIdle {first.value=complete.copy(rows=complete.rows.reversed());second.value=complete};held();compose.onNodeWithTag(money()).assertDoesNotExist()
            compose.runOnIdle {second.value=BudgetReadSnapshot(other,emptyList())}
            compose.waitUntil(5000) {compose.onAllNodesWithTag("overview.budget.focus").fetchSemanticsNodes().isEmpty()}}
    }
    @Test fun parentLimitIsDisplayedOnceAndMissingSummaryFxDoesNotEraseItsOriginalCurrencyAlert() {
        plan();runBlocking {repo.saveBudget(owner,BudgetDraft(parent.id,month.atDay(1).atStartOfDay(zone).toInstant().toString(),2000,"JPY",zoneId=zone),device,time).getOrThrow()}
        seed(row(2500))
        withoutWrites {compose.setContent {Screen(primary="VND")};known(2500,2000);contains("overview.budget.percent.${parent.id}","125%")
            Assert.assertEquals(1,compose.onAllNodesWithTag(money(),useUnmergedTree=true).fetchSemanticsNodes().size)}
    }
    @Test fun exactAndUnavailableWatchlistAmountsRemainCompleteAtActual130InThreeLanguagesLightDark() {
        val saved=plan(limit=Long.MAX_VALUE).copy(categoryNameSnapshot="Ăn uống",categoryNameEnglishSnapshot="Food",categoryNameJapaneseSnapshot="食費")
        seed(saved.toCloudRecord());val first=row(Long.MAX_VALUE);seed(first);seed(row(Long.MAX_VALUE))
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
            val bitmap=compose.onNodeWithTag("overview.budget.focus").captureToImage().asAndroidBitmap()
            java.io.File(context.getExternalFilesDir(null),"overview-budget-focus-$kind-$language-${if(dark) "dark" else "light"}-font130.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)
            }
        }
        val exact=formatMinorUnits(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,"JPY")
        val limit=formatMinorUnits(Long.MAX_VALUE,"JPY")
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)) {
            withoutWrites {
                compose.runOnIdle {language=code;dark=theme};reveal();contains(money(),"$exact / $limit")
                contains("overview.budget.percent.${parent.id}","200%")
                complete(money());complete("overview.budget.percent.${parent.id}");capture("exact")
            }
            seed(first.copy(payload=JsonObject(first.payload+("amount_minor" to JsonPrimitive("broken")))))
            withoutWrites {held();contains(money(),"— / $limit");complete(money());complete("overview.budget.unavailable");capture("unavailable")}
            seed(first)
        }
    }

    @Test fun watchlistHeaderAndCardGeometryMatchTheSwiftSection() {
        plan();seed(row(1200));compose.setContent {Screen()};known(1200)
        val label=context.getString(R.string.overview_overview_budget_watchlist)
        val title=compose.onNodeWithText(label,ignoreCase=true,useUnmergedTree=true)
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        title.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {it(layouts)}
        val layout=layouts.single()
        Assert.assertEquals(13f,layout.layoutInput.style.fontSize.value,0.0001f)
        Assert.assertEquals(0.6f,layout.layoutInput.style.letterSpacing.value,0.0001f)
        title.assertTextEquals(label.uppercase(context.resources.configuration.locales[0]))
        val header=title.getUnclippedBoundsInRoot()
        val card=compose.onNodeWithTag("overview.budget.card",useUnmergedTree=true).getUnclippedBoundsInRoot()
        Assert.assertEquals(8f,(card.top-header.bottom).value,0.75f)
        val icon=compose.onNodeWithTag("overview.budget.icon.${parent.id}",useUnmergedTree=true).getUnclippedBoundsInRoot()
        Assert.assertEquals(30f,(icon.right-icon.left).value,0.75f)
        Assert.assertEquals(30f,(icon.bottom-icon.top).value,0.75f)
        Assert.assertEquals(14f,(icon.left-card.left).value,0.75f)
    }

}
