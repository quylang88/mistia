package vn.com.quyln.mistia.core.network

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsExchangeRateRepositoryTest {
    private class Store: CurrencyPreferencesStore {
        override val state = MutableStateFlow(CurrencyPreferences())
        override fun setEnabled(code:String,enabled:Boolean) {state.value=state.value.withEnabled(code,enabled)}
        override fun setPrimary(code:String) {state.value=state.value.withPrimary(code)}
        override fun setAutomatic(automatic:Boolean) {state.value=state.value.copy(rateMode=if(automatic) CurrencyRateMode.AUTOMATIC else CurrencyRateMode.MANUAL)}
        override fun setDisplayedManualRate(text:String) {state.value=state.value.withDisplayedManualRate(text)}
    }
    private class Auto: ExchangeRateRepository {
        override val rates = MutableStateFlow(listOf(ExchangeRateSnapshot("JPY","VND","200","frankfurter",42,"2026-10-16")))
        var staleCalls=0;var forcedCalls=0;var deferred:CompletableDeferred<Unit>?=null
        override suspend fun refreshIfStale(nowEpochMillis:Long):Result<Unit> {staleCalls++;return Result.success(Unit)}
        override suspend fun refreshNow(nowEpochMillis:Long):Result<Unit> {forcedCalls++;deferred?.await();rates.value=listOf(rates.value.single().copy(rateDecimalString="250"));return Result.success(Unit)}
    }
    @Test fun manualDefaultNeverFetchesAndIgnoresAutomaticCache() = runTest {
        val store=Store();val auto=Auto();val repository=SettingsExchangeRateRepository(store,auto,backgroundScope)
        runCurrent()
        assertEquals("manual",repository.rates.value.single().provider)
        assertEquals("165",repository.rates.value.single().rateDecimalString)
        repository.refreshIfStale(99);repository.refreshNow(99)
        assertEquals(0,auto.staleCalls);assertEquals(0,auto.forcedCalls)
    }
    @Test fun switchingModesPreservesBothSourcesAndManualEdits() = runTest {
        val store=Store();val auto=Auto();val repository=SettingsExchangeRateRepository(store,auto,backgroundScope)
        store.setEnabled("VND",true);store.setPrimary("VND");store.setDisplayedManualRate("180")
        runCurrent();assertEquals("180",repository.rates.value.single().rateDecimalString)
        store.setAutomatic(true);runCurrent();assertEquals("200",repository.rates.value.single().rateDecimalString)
        repository.refreshIfStale(99);assertEquals(1,auto.staleCalls)
        store.setAutomatic(false);runCurrent();assertEquals("180",repository.rates.value.single().rateDecimalString)
    }
    @Test fun delayedAutomaticRefreshCannotReplaceManualSelection() = runTest {
        val store=Store();store.setAutomatic(true)
        val auto=Auto();auto.deferred=CompletableDeferred()
        val repository=SettingsExchangeRateRepository(store,auto,backgroundScope)
        val job=launch {repository.refreshNow(99)};runCurrent();assertEquals(1,auto.forcedCalls)
        store.setAutomatic(false);runCurrent();assertEquals("165",repository.rates.value.single().rateDecimalString)
        auto.deferred!!.complete(Unit);job.join();runCurrent()
        assertEquals("165",repository.rates.value.single().rateDecimalString)
        store.setAutomatic(true);runCurrent();assertEquals("250",repository.rates.value.single().rateDecimalString)
    }
}
