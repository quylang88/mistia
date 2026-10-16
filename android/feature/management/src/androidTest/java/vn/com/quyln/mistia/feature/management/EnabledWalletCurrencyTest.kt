package vn.com.quyln.mistia.feature.management

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class EnabledWalletCurrencyTest {
    private val compose=createComposeRule()
    @get:Rule val rules=RuleChain.outerRule(object:ExternalResource() {override fun after() {if(::db.isInitialized) db.close()}}).around(compose)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var preferences:LocalCurrencyPreferencesStore
    private lateinit var prefName:String
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="22222222-2222-2222-2222-222222222222"
    private val now="2026-10-16T00:00:00Z"
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        prefName="enabled-wallet-${java.util.UUID.randomUUID()}";preferences=LocalCurrencyPreferencesStore(context,prefName)
    }
    @After fun cleanup() {preferences.close();context.getSharedPreferences(prefName,Context.MODE_PRIVATE).edit().clear().commit()}
    @Composable private fun Wallet(wallet:LedgerWalletRecord?=null,dark:Boolean=false) {
        val p by preferences.state.collectAsState()
        MistiaTheme(darkTheme=dark) {WalletEditorSheet(owner.value,wallet,0,onDismiss={},
            onSave={repo.saveWallet(owner,it,device,now)},onArchive={Result.success(Unit)},enabledCurrencyCodes=p.enabledCurrencyCodes)}
    }
    @Composable private fun Card(account:CreditCardAccount?=null,locked:Boolean=false,dark:Boolean=false) {
        val p by preferences.state.collectAsState()
        MistiaTheme(darkTheme=dark) {CreditCardEditorSheet(owner.value,account?.wallet,account?.profile,emptyList(),0,onDismiss={},
            onSave={repo.saveCreditCard(owner,it,device,now)},currencyEditable=!locked,enabledCurrencyCodes=p.enabledCurrencyCodes)}
    }
    private fun tag(value:String)=compose.onNodeWithTag(value)
    private fun onlyVND() {preferences.setEnabled("VND",true);preferences.setEnabled("JPY",false)}
    @Test fun newWalletUsesEnabledChoicesAndPreservesTypedDraftOnLiveSettingsChange() {
        compose.setContent {Wallet()}
        tag("wallet.currency.VND").assertDoesNotExist()
        tag("wallet.name").performScrollTo().performTextReplacement("Exact VND")
        tag("wallet.openingBalance").performScrollTo().performTextReplacement("9007199254740993")
        compose.runOnIdle {preferences.setEnabled("VND",true)}
        tag("wallet.currency.JPY").performScrollTo().assertIsSelected()
        tag("wallet.currency.VND").performClick().assertIsSelected()
        tag("wallet.openingBalance").performScrollTo().assertTextContains("9,007,199,254,740,993")
        Assert.assertTrue(runBlocking {repo.observeWallets(owner).first().isEmpty()})
        tag("wallet.save").performScrollTo().performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeWallets(owner).first().size == 1}}
        val saved=runBlocking {repo.observeWallets(owner).first().single()}
        Assert.assertEquals("VND",saved.currencyCode);Assert.assertEquals(9007199254740993L,saved.openingBalanceMinor)
        Assert.assertEquals(1,runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).size})
        Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()})
    }
    @Test fun newCardOnlyOffersEnabledVNDAndPersistsExplicitSelectionExactly() {
        onlyVND();compose.setContent {Card()}
        tag("card.currency.JPY").assertDoesNotExist()
        tag("card.currency.VND").performScrollTo().performClick().assertIsSelected()
        tag("card.name").performScrollTo().performTextReplacement("Exact card")
        tag("card.creditLimit").performScrollTo().performTextReplacement("9007199254740993")
        Assert.assertTrue(runBlocking {repo.observeWallets(owner).first().isEmpty()})
        tag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeCreditCardProfiles(owner).first().size == 1}}
        val card=runBlocking {repo.observeWallets(owner).first().single()};val profile=runBlocking {repo.observeCreditCardProfiles(owner).first().single()}
        Assert.assertEquals("VND",card.currencyCode);Assert.assertEquals(0L,card.openingBalanceMinor)
        Assert.assertEquals(9007199254740993L,profile.creditLimitMinor)
        Assert.assertEquals(1,runBlocking {store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).size})
        Assert.assertEquals(1,runBlocking {store.pendingMutations(owner,CloudEntity.CREDIT_CARD_PROFILE,Long.MAX_VALUE).size})
        Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()})
    }
    @Test fun disabledCurrentWalletCurrencyStaysVisibleAndSavesWithoutRetagging() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Stored",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=9007199254740993L),device,now).getOrThrow()}
        onlyVND();compose.setContent {Wallet(wallet)}
        tag("wallet.currency.JPY").assertDoesNotExist()
        tag("wallet.currentCurrency").performScrollTo().assertTextEquals("JPY")
        tag("wallet.currency.VND").assertIsNotSelected()
        tag("wallet.name").performScrollTo().performTextReplacement("Renamed")
        tag("wallet.save").performScrollTo().performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeWallets(owner).first().single().name == "Renamed"}}
        val saved=runBlocking {repo.observeWallets(owner).first().single()}
        Assert.assertEquals(wallet.currencyCode,saved.currencyCode);Assert.assertEquals(wallet.openingBalanceMinor,saved.openingBalanceMinor)
    }
    @Test fun lockedCardKeepsDisabledCurrentCurrencyAndLimitDuringMetadataSave() {
        val card=runBlocking {repo.saveCreditCard(owner,CreditCardDraft(name="Stored",currencyCode="JPY",creditLimitMinor=9007199254740993L),device,now).getOrThrow()}
        onlyVND();compose.setContent {Card(card,locked=true)}
        tag("card.currency.JPY").assertDoesNotExist()
        tag("card.currentCurrency").performScrollTo().assertTextEquals("JPY")
        tag("card.currency.VND").assertIsNotEnabled()
        tag("card.name").performScrollTo().performTextReplacement("Renamed")
        tag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeWallets(owner).first().single().name == "Renamed"}}
        Assert.assertEquals("JPY",runBlocking {repo.observeWallets(owner).first().single().currencyCode})
        Assert.assertEquals(card.profile.creditLimitMinor,runBlocking {repo.observeCreditCardProfiles(owner).first().single().creditLimitMinor})
    }
    @Test fun removingDraftCurrencyKeepsOpenCardCalculatorAndExactMoneyUntilExplicitSave() {
        compose.setContent {Card()}
        tag("card.name").performScrollTo().performTextReplacement("Preserved draft")
        tag("card.creditLimit").performScrollTo().performTextReplacement("9007199254740993")
        tag("card.creditLimit.calculator").performScrollTo().performClick()
        tag("amountCalculator.key.+").performClick();tag("amountCalculator.key.1").performClick()
        tag("amountCalculator.result").assertTextEquals("9,007,199,254,740,994")
        compose.runOnIdle {onlyVND()}
        tag("amountCalculator.result").assertTextEquals("9,007,199,254,740,994")
        tag("amountCalculator.key.OK").performClick()
        tag("card.currentCurrency").performScrollTo().assertTextEquals("JPY")
        tag("card.currency.VND").assertIsNotSelected()
        tag("card.creditLimit").performScrollTo().assertTextContains("9,007,199,254,740,994")
        Assert.assertTrue(runBlocking {repo.observeWallets(owner).first().isEmpty()})
        tag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) {runBlocking {repo.observeCreditCardProfiles(owner).first().size == 1}}
        Assert.assertEquals("JPY",runBlocking {repo.observeWallets(owner).first().single().currencyCode})
        Assert.assertEquals(9007199254740994L,runBlocking {repo.observeCreditCardProfiles(owner).first().single().creditLimitMinor})
        Assert.assertTrue(runBlocking {repo.observeTransactions(owner).first().isEmpty()})
    }
    @Test fun disabledCurrencyChoicesRenderClearlyLightDarkAtLargeFont() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Stored JPY",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=9007199254740993L),device,now).getOrThrow()}
        val card=runBlocking {repo.saveCreditCard(owner,CreditCardDraft(name="Stored card",currencyCode="JPY",creditLimitMinor=9007199254740993L),device,now).getOrThrow()}
        onlyVND();var dark by mutableStateOf(false);var showCard by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {
                if(showCard) Card(card,locked=true,dark=dark) else Wallet(wallet,dark=dark)
            }
        }
        for(kind in listOf("wallet","card")) {
            compose.runOnIdle {showCard=kind == "card"}
            for(theme in listOf("light","dark")) {
                compose.runOnIdle {dark=theme == "dark"}
                tag("$kind.currentCurrency").performScrollTo().assertTextEquals("JPY")
                tag("$kind.currency.JPY").assertDoesNotExist()
                tag("$kind.currency.VND").performScrollTo().assertIsDisplayed()
                tag("$kind.currentCurrency").assertIsDisplayed()
                if(kind == "card") tag("card.currency.VND").assertIsNotEnabled()
                compose.waitForIdle()
                val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                java.io.File(context.getExternalFilesDir(null),"enabled-$kind-$theme-font130.png").outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
                bitmap.recycle()
            }
        }
    }
    @Test fun managementForwardsLiveEnabledDeviceChoicesIntoExistingWalletEditor() {
        val wallet=runBlocking {repo.saveWallet(owner,WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()}
        compose.setContent {
            val p by preferences.state.collectAsState()
            MistiaTheme(darkTheme=false) {ManagementScreen(owner,repo,deviceIdProvider={device},onTranslatePendingCategories={},onSyncNow={},onSignOut={},
                onOpenFamily={},onOpenInvestment={},onOpenCreditCardStatements={},enabledCurrencyCodes=p.enabledCurrencyCodes)}
        }
        compose.waitUntil(5000) {compose.onAllNodesWithTag("management.wallet.${wallet.id}").fetchSemanticsNodes().isNotEmpty()}
        tag("management.wallet.${wallet.id}").performClick()
        tag("wallet.currency.VND").assertDoesNotExist()
        compose.runOnIdle {preferences.setEnabled("VND",true)}
        tag("wallet.currency.VND").performScrollTo().assertIsEnabled()
        Assert.assertEquals(wallet,runBlocking {repo.observeWallets(owner).first().single()})
    }
}
