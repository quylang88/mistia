package vn.com.quyln.mistia.feature.settings

import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.LocalCurrencyPreferencesStore
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CurrencySettingsScreenTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private lateinit var store: LocalCurrencyPreferencesStore
    private lateinit var name: String
    private val auto = Auto()
    private class Auto: ExchangeRateRepository {
        override val rates = MutableStateFlow(emptyList<ExchangeRateSnapshot>())
        var calls = 0
        var hold: CompletableDeferred<Unit>? = null
        override suspend fun refreshIfStale(nowEpochMillis: Long): Result<Unit> = Result.success(Unit)
        override suspend fun refreshNow(nowEpochMillis: Long): Result<Unit> {
            calls++;hold?.await()
            rates.value = listOf(ExchangeRateSnapshot("JPY","VND","200","frankfurter",1792108800000L,"2026-10-16"))
            return Result.success(Unit)
        }
    }
    @Before fun setup() {name="currency-fixture-${java.util.UUID.randomUUID()}";store=LocalCurrencyPreferencesStore(context,name)}
    @After fun cleanup() {store.close();context.getSharedPreferences(name,Context.MODE_PRIVATE).edit().clear().commit()}
    private fun show() {compose.setContent {MistiaTheme(darkTheme=false) {CurrencySettingsScreen(store,auto,{})}}}
    private fun tag(name: String) = compose.onNodeWithTag("currency.$name")
    @Test fun storeRecreationRetainsDevicePreferencesAndLegacyNormalization() {
        store.setEnabled("VND",true);store.setPrimary("VND");store.setDisplayedManualRate("170.125");store.setAutomatic(true)
        store.close();store=LocalCurrencyPreferencesStore(context,name)
        Assert.assertEquals(CurrencyPreferences(listOf("JPY","VND"),"VND",CurrencyRateMode.AUTOMATIC,"170.125"),store.state.value)
        store.close()
        context.getSharedPreferences(name,Context.MODE_PRIVATE).edit()
            .putString("mistia.settings.currency.enabled-codes"," vnd ,USD,VND")
            .putString("mistia.settings.currency.code"," vnd ").putString("mistia.settings.currency.rate-mode","unknown").commit()
        store=LocalCurrencyPreferencesStore(context,name)
        Assert.assertEquals(listOf("JPY","VND"),store.state.value.enabledCurrencyCodes)
        Assert.assertEquals("VND",store.state.value.primaryCurrencyCode)
        Assert.assertEquals(CurrencyRateMode.MANUAL,store.state.value.rateMode)
    }
    @Test fun blankDirectRateSurvivesStoreRecreationWithoutRewritingUserInput() {
        store.setEnabled("VND",true);store.setPrimary("VND");store.setDisplayedManualRate("")
        store.close();store=LocalCurrencyPreferencesStore(context,name)
        Assert.assertEquals("",store.state.value.manualJPYToVNDRate)
        Assert.assertEquals("165",store.state.value.manualRates().single().rateDecimalString)
        show();tag("manualRate").performScrollTo().assertTextContains("")
    }
    @Test fun devicePreferenceChangesFromAnotherStoreReachOpenScreen() {
        show()
        LocalCurrencyPreferencesStore(context,name).use { other ->
            other.setEnabled("VND",true);other.setPrimary("VND");other.setDisplayedManualRate("180")
            compose.waitUntil(5000) {store.state.value.primaryCurrencyCode == "VND"}
            tag("enabled.VND").assertIsOn()
            tag("manualRate").performScrollTo().assertTextContains("180")
        }
    }
    @Test fun rateControlsRenderLightDarkAtLargeFont() {
        store.setEnabled("VND",true);store.setPrimary("VND");store.setDisplayedManualRate("166.12345679")
        auto.rates.value=listOf(ExchangeRateSnapshot("JPY","VND","200","frankfurter",1792108800000L,"2026-10-16"))
        var dark by mutableStateOf(false)
        compose.setContent {
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,1.3f)) {
                MistiaTheme(darkTheme=dark) {CurrencySettingsScreen(store,auto,{})}
            }
        }
        for(theme in listOf("light","dark")) {
            compose.runOnIdle {dark=theme == "dark";store.setAutomatic(false)}
            tag("manualRate").performScrollTo().assertTextContains("166.12345679")
            capture("currency-settings-$theme-manual-font130.png")
            tag("automatic").performScrollTo().performClick()
            tag("automaticRate").performScrollTo().assertTextEquals("200")
            capture("currency-settings-$theme-automatic-font130.png")
        }
    }
    private fun capture(name:String) {
        compose.waitForIdle()
        val bitmap=checkNotNull(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
        java.io.File(context.getExternalFilesDir(null),name).outputStream().use {Assert.assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it))}
        bitmap.recycle()
    }
    @Test fun togglesKeepOneCurrencyAndPrimaryMenuOnlyOffersEnabled() {
        show();tag("enabled.JPY").assertIsOn();tag("enabled.VND").assertIsOff()
        tag("enabled.JPY").performClick().assertIsOn()
        tag("automatic").assertDoesNotExist()
        tag("enabled.VND").performClick();tag("primary").performClick();tag("primary.VND").performClick()
        compose.runOnIdle {Assert.assertEquals("VND",store.state.value.primaryCurrencyCode)}
        tag("enabled.VND").performClick()
        compose.runOnIdle {Assert.assertEquals("JPY",store.state.value.primaryCurrencyCode)}
        tag("primary").performClick();tag("primary.VND").assertDoesNotExist()
    }
    @Test fun manualFieldStoresDirectAndInverseWithoutLosingExactCanonicalRate() {
        store.setEnabled("VND",true);show()
        tag("manualRate").performScrollTo().assertTextContains("0.00606061")
        tag("manualRate").performTextReplacement("0.005")
        compose.runOnIdle {Assert.assertEquals("200",store.state.value.manualJPYToVNDRate)}
        tag("primary").performScrollTo().performClick();tag("primary.VND").performClick()
        tag("manualRate").performScrollTo().assertTextContains("200")
        tag("manualRate").performTextReplacement("166,123456785")
        compose.runOnIdle {Assert.assertEquals("166.12345679",store.state.value.manualJPYToVNDRate)}
        tag("manualRate").performTextClearance()
        compose.runOnIdle {Assert.assertEquals("",store.state.value.manualJPYToVNDRate)}
        tag("manualRate").performTextReplacement("bad")
        compose.runOnIdle {Assert.assertEquals("bad",store.state.value.manualJPYToVNDRate)}
    }
    @Test fun automaticRefreshIsExplicitBusyAndDoesNotChangeManualPreference() {
        store.setEnabled("VND",true);store.setPrimary("VND");store.setDisplayedManualRate("180");auto.hold=CompletableDeferred()
        show();tag("automatic").performScrollTo().performClick()
        tag("manualRate").assertDoesNotExist();tag("automaticRate").performScrollTo().assertTextEquals("—")
        tag("refresh").performScrollTo().performClick().assertIsNotEnabled()
        compose.runOnIdle {Assert.assertEquals(1,auto.calls)}
        tag("automatic").performScrollTo().performClick()
        tag("manualRate").performScrollTo().assertTextContains("180")
        compose.runOnIdle {auto.hold!!.complete(Unit)}
        tag("manualRate").assertTextContains("180")
        tag("automatic").performScrollTo().performClick()
        tag("automaticRate").performScrollTo().assertTextEquals("200")
        tag("refresh").performScrollTo().assertIsEnabled()
        compose.runOnIdle {Assert.assertEquals("180",store.state.value.manualJPYToVNDRate)}
    }
}
