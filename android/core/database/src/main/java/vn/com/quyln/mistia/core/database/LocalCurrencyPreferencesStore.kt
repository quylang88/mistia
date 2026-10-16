package vn.com.quyln.mistia.core.database

import android.content.Context
import android.content.SharedPreferences
import java.io.Closeable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import vn.com.quyln.mistia.core.model.*

/** Device settings, matching UserDefaults; independent of financial owner data. */
class LocalCurrencyPreferencesStore(context: Context, preferencesName: String = "mistia-currency-preferences") : CurrencyPreferencesStore, Closeable {
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val mutable = MutableStateFlow(read())
    override val state: StateFlow<CurrencyPreferences> = mutable.asStateFlow()
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> mutable.value = read() }
    init { preferences.registerOnSharedPreferenceChangeListener(listener) }

    override fun setEnabled(code: String, enabled: Boolean) = update { it.withEnabled(code, enabled) }
    override fun setPrimary(code: String) = update { it.withPrimary(code) }
    override fun setAutomatic(automatic: Boolean) = update {
        it.copy(rateMode = if (automatic) CurrencyRateMode.AUTOMATIC else CurrencyRateMode.MANUAL)
    }
    override fun setDisplayedManualRate(text: String) = update { it.withDisplayedManualRate(text) }

    @Synchronized private fun update(change: (CurrencyPreferences) -> CurrencyPreferences) {
        val value = change(read())
        preferences.edit().putString(ENABLED, value.enabledCurrencyCodes.joinToString(","))
            .putString(PRIMARY, value.primaryCurrencyCode)
            .putString(MODE, if (value.rateMode == CurrencyRateMode.AUTOMATIC) "automatic" else "manual")
            .putString(MANUAL, value.manualJPYToVNDRate).apply()
        mutable.value = value
    }
    private fun read(): CurrencyPreferences = CurrencyPreferences.fromStored(
        preferences.getString(ENABLED, null), preferences.getString(PRIMARY, null),
        preferences.getString(MODE, null), preferences.getString(MANUAL, null))
    override fun close() { preferences.unregisterOnSharedPreferenceChangeListener(listener) }

    private companion object {
        const val ENABLED = "mistia.settings.currency.enabled-codes"
        const val PRIMARY = "mistia.settings.currency.code"
        const val MODE = "mistia.settings.currency.rate-mode"
        const val MANUAL = "mistia.settings.currency.manual-rate.jpy-vnd"
    }
}
