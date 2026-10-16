package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class CurrencyPreferencesTest {
    @Test fun defaultsMatchSwiftIncludingManualSnapshot() {
        val p = CurrencyPreferences.fromStored(null,null,null,null)
        assertEquals(listOf("JPY"),p.enabledCurrencyCodes)
        assertEquals("JPY",p.primaryCurrencyCode)
        assertEquals(CurrencyRateMode.MANUAL,p.rateMode)
        assertEquals(ExchangeRateSnapshot("JPY","VND","165","manual",0,null),p.manualRates().single())
    }
    @Test fun storageNormalizesSupportedOrderAndFallback() {
        val p=CurrencyPreferences.fromStored(" vnd ,USD,jpy,VND"," vnd ","automatic","170")
        assertEquals(listOf("JPY","VND"),p.enabledCurrencyCodes)
        assertEquals("VND",p.primaryCurrencyCode)
        assertEquals(CurrencyRateMode.AUTOMATIC,p.rateMode)
        assertEquals("170",p.manualJPYToVNDRate)
        assertEquals("VND",CurrencyPreferences.fromStored("VND","JPY","bad","").primaryCurrencyCode)
    }
    @Test fun lastCurrencyCannotBeDisabledAndPrimaryTracksEnabled() {
        assertEquals(CurrencyPreferences(),CurrencyPreferences().withEnabled("JPY",false))
        val both=CurrencyPreferences().withEnabled(" vnd ",true).withPrimary("VND")
        assertEquals("VND",both.primaryCurrencyCode)
        assertEquals(listOf("VND"),both.withEnabled("JPY",false).enabledCurrencyCodes)
        assertEquals("JPY",both.withEnabled("VND",false).primaryCurrencyCode)
        assertEquals("JPY",CurrencyPreferences().withPrimary("VND").primaryCurrencyCode)
    }
    @Test fun directRateRoundsEightPlacesAndAcceptsComma() {
        val p=CurrencyPreferences(enabledCurrencyCodes=listOf("JPY","VND"),primaryCurrencyCode="VND")
            .withDisplayedManualRate("166,123456785")
        assertEquals("166.12345679",p.manualJPYToVNDRate)
        assertEquals("166.12345679",p.displayedRate())
    }
    @Test fun inverseRateStoresCanonicalPairAndIgnoresInvalidInverse() {
        val p=CurrencyPreferences(enabledCurrencyCodes=listOf("JPY","VND"))
        assertEquals("0.00606061",p.displayedRate())
        val edited=p.withDisplayedManualRate("0.005")
        assertEquals("200",edited.manualJPYToVNDRate)
        assertEquals("0.005",edited.displayedRate())
        assertEquals(edited,edited.withDisplayedManualRate("0"))
        assertEquals(edited,edited.withDisplayedManualRate("bad"))
    }
    @Test fun invalidDirectRateIsRetainedWithoutInventingConversion() {
        val p=CurrencyPreferences(enabledCurrencyCodes=listOf("JPY","VND"),primaryCurrencyCode="VND")
        val invalid=p.withDisplayedManualRate("bad")
        assertEquals("bad",invalid.manualJPYToVNDRate)
        assertNull(invalid.displayedRate())
        assertNull(resolveExchangeRate(100,"JPY","VND",invalid.manualRates()))
        assertEquals("165",CurrencyPreferences.fromStored(null,null,null,"  ").manualRates().single().rateDecimalString)
    }
    @Test fun storedBlankRemainsEditableWhileEffectiveManualRateUsesSwiftDefault() {
        val p=CurrencyPreferences.fromStored("JPY,VND","VND","manual","")
        assertEquals("",p.manualJPYToVNDRate)
        assertEquals("165",p.manualRates().single().rateDecimalString)
        assertNull(p.displayedRate())
    }
    @Test fun automaticDisplayUsesCacheWithoutManualFallback() {
        val p=CurrencyPreferences(enabledCurrencyCodes=listOf("JPY","VND"),rateMode=CurrencyRateMode.AUTOMATIC)
        assertNull(p.displayedRate())
        assertEquals("0.005",p.displayedRate(listOf(ExchangeRateSnapshot("JPY","VND","200","frankfurter",42,"2026-10-16"))))
    }
}
