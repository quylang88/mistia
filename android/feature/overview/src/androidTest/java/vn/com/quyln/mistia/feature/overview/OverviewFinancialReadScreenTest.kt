package vn.com.quyln.mistia.feature.overview

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class OverviewFinancialReadScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var repo:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val sync=MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();repo=OfflineFirstFinanceRepository(RoomLocalStore(db))}
    private fun snapshot(subject:UserId=owner,amount:Long=1375):OverviewFinancialReadSnapshot {
        val id="22222222-2222-2222-2222-222222222222";val time=Instant.now().toString()
        val row=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,subject.value,buildJsonObject {
            put("id",id);put("user_id",subject.value);put("title","Owned expense");put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code","JPY");put("occurred_at",time);put("created_at",time);put("updated_at",time);put("is_archived",false)
        },time,null,0)
        return OverviewFinancialReadSnapshot(subject,listOf(row))
    }
    @Composable private fun Screen(subject:UserId=owner,source:FinanceRepository){MistiaTheme(darkTheme=false) {
        androidx.compose.material3.Scaffold {padding ->OverviewScreen(subject,source,sync,androidx.compose.ui.Modifier.padding(padding))}
    }}
    private fun metric(value:String){compose.onNodeWithTag("overview.monthly.expense").performScrollTo().assertTextEquals(value)}
    private fun revealRecent(tag:String){
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).assertExists()
    }
    @Test fun withheldFirstReadIsUnavailableUntilActuallyLoadedEmpty(){
        val values=MutableStateFlow<OverviewFinancialReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=values.filterNotNull()}
        compose.setContent {Screen(source=source)};metric("—")
        compose.onNodeWithTag("overview.financial.loading").assertExists()
        revealRecent("overview.recent.unavailable")
        compose.runOnIdle {values.value=OverviewFinancialReadSnapshot(owner,emptyList())};metric(formatMinorUnits(0,"JPY"))
        compose.onNodeWithTag("overview.financial.loading").assertDoesNotExist()
        revealRecent("overview.recent.empty")
    }
    @Test fun errorAfterLoadedClearsPrivateMoneyAndRetryStartsFreshRead(){
        val crash=MutableStateFlow(false);var attempts=0
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=flow {
            attempts++
            if(attempts==1){emit(snapshot());crash.first {it};throw IllegalStateException("read failed")}
            emit(snapshot(amount=42));awaitCancellation()
        }}
        compose.setContent {Screen(source=source)};metric(formatMinorUnits(1375,"JPY"))
        compose.runOnIdle {crash.value=true};metric("—")
        compose.onNodeWithTag("overview.financial.retry").performScrollTo().performClick();metric(formatMinorUnits(42,"JPY"))
        Assert.assertEquals(2,attempts)
    }
    @Test fun ownerReplacementCannotShowZeroOrOldMoneyAndRejectsLateForeignSnapshot(){
        var subject by mutableStateOf(owner)
        val first=MutableStateFlow<OverviewFinancialReadSnapshot?>(snapshot());val next=MutableStateFlow<OverviewFinancialReadSnapshot?>(null)
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=if(owner==this@OverviewFinancialReadScreenTest.owner) first.filterNotNull() else next.filterNotNull()}
        compose.setContent {Screen(subject,source)};metric(formatMinorUnits(1375,"JPY"))
        compose.runOnIdle {subject=other};metric("—")
        compose.runOnIdle {first.value=snapshot(amount=900);next.value=snapshot()};metric("—")
        compose.onNodeWithTag("overview.financial.retry").performScrollTo().assertExists()
        compose.runOnIdle {next.value=snapshot(other,77)};metric(formatMinorUnits(77,"JPY"))
    }
    @Test fun inclusiveDamagedDeletionDoesNotResurrectRecentRowsOrClaimLoadedEmpty(){
        val raw=snapshot().rows.single()
        val damaged=raw.copy(payload=JsonObject(raw.payload+("deleted_at" to buildJsonObject {put("bad",true)})))
        val values=MutableStateFlow(OverviewFinancialReadSnapshot(owner,listOf(damaged)))
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=values}
        compose.setContent {Screen(source=source)}
        revealRecent("overview.recent.unavailable")
        compose.onNodeWithText("Owned expense").assertDoesNotExist();compose.onNodeWithTag("overview.recent.empty").assertDoesNotExist()
        compose.runOnIdle {values.value=snapshot()}
        compose.onNodeWithText("Owned expense").assertExists();compose.onNodeWithTag("overview.recent.unavailable").assertDoesNotExist()
    }
    @Test fun lifecycleStopCancelsReadAndRestartCollectsCurrentSnapshot(){
        val host=object:androidx.lifecycle.LifecycleOwner {
            val registry=androidx.lifecycle.LifecycleRegistry.createUnsafe(this)
            override val lifecycle:androidx.lifecycle.Lifecycle get()=registry
        };host.registry.currentState=androidx.lifecycle.Lifecycle.State.RESUMED
        var starts=0;var stops=0;var amount=1375L
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId)=flow {
            starts++
            try{emit(snapshot(amount=amount));awaitCancellation()}finally{stops++}
        }}
        compose.setContent {CompositionLocalProvider(androidx.lifecycle.compose.LocalLifecycleOwner provides host){Screen(source=source)}}
        metric(formatMinorUnits(1375,"JPY"))
        compose.runOnIdle {host.registry.currentState=androidx.lifecycle.Lifecycle.State.CREATED}
        compose.runOnIdle {Assert.assertEquals(1,stops);amount=42;host.registry.currentState=androidx.lifecycle.Lifecycle.State.RESUMED}
        metric(formatMinorUnits(42,"JPY"));Assert.assertEquals(2,starts)
    }
    @Test fun readFailureHintsAndRetryStayCompleteAtActual130InThreeLanguagesLightDark(){
        val context=ApplicationProvider.getApplicationContext<Context>()
        val source=object:FinanceRepository by repo {override fun observeOverviewFinancialReadSnapshot(owner:UserId):Flow<OverviewFinancialReadSnapshot> = flow {throw IllegalStateException("unavailable")}}
        var language by mutableStateOf("en");var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            val config=android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
            CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides context.createConfigurationContext(config),
                androidx.compose.ui.platform.LocalConfiguration provides config,
                androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=dark){androidx.compose.material3.Scaffold {padding ->OverviewScreen(owner,source,sync,androidx.compose.ui.Modifier.padding(padding))}}
            }
        }
        for(code in listOf("en","vi","ja")) for(theme in listOf(false,true)){
            compose.runOnIdle {language=code;dark=theme};metric("—")
            compose.onNodeWithTag("overview.financial.retry").performScrollTo().assertExists()
            for(tag in listOf("overview.assets.unavailable","overview.monthly.income.unavailable","overview.monthly.expense.unavailable")) {
                compose.onNodeWithTag(tag).performScrollTo()
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithTag(tag).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
                val layout=layouts.single();Assert.assertEquals(1.3f,layout.layoutInput.density.fontScale,0.0001f)
                Assert.assertEquals(layout.layoutInput.text.length,layout.getLineEnd(layout.lineCount-1,true))
                for(line in 0 until layout.lineCount) Assert.assertFalse(layout.isLineEllipsized(line))
            }
            val localized=context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(code))})
            compose.onNodeWithTag("overview.assets.unavailable").assertTextEquals(localized.getString(vn.com.quyln.mistia.core.designsystem.R.string.overview_overview_assets_unavailable))
            compose.onNodeWithTag("overview.financial.retry").performScrollTo()
            val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
            java.io.File(context.getExternalFilesDir(null),"overview-financial-error-$code-${if(theme) "dark" else "light"}-font130.png").outputStream().use{Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))};bitmap.recycle()
        }
    }

}
