package vn.com.quyln.mistia.feature.management

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@androidx.test.filters.SdkSuppress(minSdkVersion=29)
@RunWith(AndroidJUnit4::class)
class WalletInvestmentProtectionScreenTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource(){override fun after(){if(::db.isInitialized)db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var wallet:LedgerWalletRecord
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val now="2026-10-28T00:00:00Z"
    private var dismissed=false
    private val originalResources=linkedMapOf<android.content.res.Resources,Configuration>()
    @Suppress("DEPRECATION")
    private fun configureActualWindows(language:String) {
        val windows=android.view.inspector.WindowInspector.getGlobalWindowViews()
        (windows.map{it.context.resources}+context.resources).distinct().forEach{r->
            originalResources.putIfAbsent(r,Configuration(r.configuration))
            r.updateConfiguration(Configuration(r.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))},r.displayMetrics)
        }
        windows.forEach{it.dispatchConfigurationChanged(Configuration(it.resources.configuration))}
    }
    @Suppress("DEPRECATION")
    @After fun restoreResources() {
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
            originalResources.forEach{(r,c)->r.updateConfiguration(c,r.displayMetrics)}
            android.view.inspector.WindowInspector.getGlobalWindowViews().forEach{it.dispatchConfigurationChanged(Configuration(it.resources.configuration))}
        }
    }
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner});repo=OfflineFirstFinanceRepository(store)
        wallet=repo.saveWallet(owner,WalletDraft(name="Protected cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=1000),device,now).getOrThrow()
        val raw=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).record
        val root=raw.copy(payload=JsonObject(raw.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",wallet.id)}))
        store.commitMutation(root,PendingMutation(CloudEntity.LEDGER_WALLET,root.id,owner.value,MutationKind.UPSERT,root.payload,now,0,device))
    }
    private fun editor(language:String):Context {
        val config=Configuration(context.resources.configuration).apply{setLocale(java.util.Locale.forLanguageTag(language))}
        val localized=context.createConfigurationContext(config)
        compose.setContent {CompositionLocalProvider(LocalContext provides localized,LocalConfiguration provides config) {MistiaTheme(darkTheme=language=="ja") {
            WalletEditorSheet(owner.value,wallet,0,onDismiss={dismissed=true},
                onSave={repo.saveWallet(owner,it,device,"2026-10-28T00:01:00Z")},
                onArchive={repo.archiveWallet(owner,RecordId(wallet.id),device,"2026-10-28T00:01:00Z")},currencyEditable=true,enabledCurrencyCodes=listOf("JPY","VND"))
        }}}
        compose.runOnIdle{configureActualWindows(language)}
        return localized
    }
    private fun archive(language:String) {
        val before=runBlocking{store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)}
        val queues=runBlocking{store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)}
        val localized=editor(language)
        compose.onNodeWithTag("wallet.name").performTextClearance();compose.onNodeWithTag("wallet.name").performTextInput("Unsaved draft")
        compose.onNodeWithText(localized.getString(R.string.management_management_archive_wallet)).performScrollTo().performClick()
        compose.onNodeWithText(localized.getString(R.string.common_archive)).performClick()
        val message=localized.getString(R.string.investment_error_wallet_holds_cash)
        // Dialog dismissal and locale dispatch may remeasure the sheet after its first scroll.
        compose.waitUntil(5000){runCatching {
            compose.onNodeWithText(message).performScrollTo().assertIsDisplayed();true
        }.getOrDefault(false)}
        compose.onNodeWithTag("wallet.name").performScrollTo().assertTextContains("Unsaved draft")
        assertFalse(dismissed);assertEquals(before,runBlocking{store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)})
        assertEquals(queues,runBlocking{store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)})
    }
    @Test fun archiveKeepsDraftAndWalletInVietnamese() {archive("vi")}
    @Test fun archiveKeepsDraftAndWalletInEnglish() {archive("en")}
    @Test fun archiveKeepsDraftAndWalletInJapaneseDarkMode() {archive("ja")}
    @Test fun enabledStaleCurrencyPickerShowsInvestmentReasonAndPreservesThePendingWallet() {
        val localized=editor("en");val before=runBlocking{store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)}
        val queues=runBlocking{store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)}
        compose.onNodeWithTag("wallet.currency.VND").performScrollTo().performClick();compose.onNodeWithTag("wallet.save").performScrollTo().assertIsEnabled().performClick()
        val message=localized.getString(R.string.investment_error_wallet_holds_cash)
        // Dialog dismissal and locale dispatch may remeasure the sheet after its first scroll.
        compose.waitUntil(5000){runCatching {
            compose.onNodeWithText(message).performScrollTo().assertIsDisplayed();true
        }.getOrDefault(false)};assertFalse(dismissed)
        assertEquals(before,runBlocking{store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet.id)});assertEquals(queues,runBlocking{store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)})
    }
}
