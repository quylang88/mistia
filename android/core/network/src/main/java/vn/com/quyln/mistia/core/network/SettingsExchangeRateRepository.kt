package vn.com.quyln.mistia.core.network

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import vn.com.quyln.mistia.core.model.*

class SettingsExchangeRateRepository(
    private val preferences: CurrencyPreferencesStore,
    private val automatic: ExchangeRateRepository,
    scope: CoroutineScope,
) : ExchangeRateRepository {
    override val rates = combine(preferences.state, automatic.rates) { settings, cached ->
        if (settings.rateMode == CurrencyRateMode.MANUAL) settings.manualRates() else cached
    }.stateIn(scope, SharingStarted.Eagerly, if (preferences.state.value.rateMode == CurrencyRateMode.MANUAL)
        preferences.state.value.manualRates() else automatic.rates.value)
    override suspend fun refreshIfStale(nowEpochMillis: Long): Result<Unit> = if (preferences.state.value.rateMode == CurrencyRateMode.AUTOMATIC) automatic.refreshIfStale(nowEpochMillis) else Result.success(Unit)
    override suspend fun refreshNow(nowEpochMillis: Long): Result<Unit> = if (preferences.state.value.rateMode == CurrencyRateMode.AUTOMATIC) automatic.refreshNow(nowEpochMillis) else Result.success(Unit)
}
