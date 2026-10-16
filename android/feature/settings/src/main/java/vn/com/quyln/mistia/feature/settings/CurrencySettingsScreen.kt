package vn.com.quyln.mistia.feature.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CurrencySettingsScreen(store: CurrencyPreferencesStore, rates: ExchangeRateRepository, onBack: () -> Unit) {
    val preferences by store.state.collectAsStateWithLifecycle()
    val snapshots by rates.rates.collectAsStateWithLifecycle()
    var menuOpen by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val automatic = preferences.rateMode == CurrencyRateMode.AUTOMATIC
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.settings_currency_title)) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_close)) } }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Card {
                    CurrencyPreferences.supportedCurrencyCodes.forEachIndexed { index, code ->
                        CurrencyToggle("enabled.$code", currencyTitle(code), code in preferences.enabledCurrencyCodes) { store.setEnabled(code, it) }
                        if (index == 0) HorizontalDivider(Modifier.padding(start = 18.dp))
                    }
                }
            }
            item { CurrencyDescription(R.string.settings_currency_enabled_description) }
            item {
                Card {
                    ListItem(headlineContent = { Text(stringResource(R.string.settings_currency_primary_currency)) }, trailingContent = {
                        Box {
                            TextButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("currency.primary")) { Text(currencyTitle(preferences.primaryCurrencyCode)) }
                            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                preferences.enabledCurrencyCodes.forEach { code -> DropdownMenuItem(text = { Text(currencyTitle(code)) },
                                    modifier = Modifier.testTag("currency.primary.$code"), onClick = { store.setPrimary(code); menuOpen = false }) }
                            }
                        }
                    })
                }
            }
            item { CurrencyDescription(R.string.settings_currency_primary_description) }
            if (preferences.enabledCurrencyCodes.size > 1) {
                item {
                    Card {
                        CurrencyToggle("automatic", stringResource(R.string.settings_currency_auto_update_rates), automatic, store::setAutomatic)
                        if (automatic) {
                            HorizontalDivider(Modifier.padding(start = 18.dp))
                            TextButton(onClick = {
                                refreshing = true
                                scope.launch { try { rates.refreshNow() } finally { refreshing = false } }
                            }, enabled = !refreshing, modifier = Modifier.fillMaxWidth().testTag("currency.refresh")) {
                                Text(stringResource(if (refreshing) R.string.settings_currency_refreshing_rates else R.string.settings_currency_refresh_rates))
                                Spacer(Modifier.width(12.dp))
                                if (refreshing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                                else Icon(Icons.Default.Refresh, null)
                            }
                            val timestamp = snapshots.firstOrNull { it.provider != "manual" }?.fetchedAtEpochMillis?.takeIf { it > 0 }
                            Text(if (timestamp == null) stringResource(R.string.settings_currency_not_updated_yet)
                                else stringResource(R.string.settings_currency_last_updated_value,
                                    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(timestamp))),
                                style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp))
                        }
                        HorizontalDivider(Modifier.padding(start = 18.dp))
                        val source = preferences.enabledCurrencyCodes.first { it != preferences.primaryCurrencyCode }
                        val title = stringResource(R.string.settings_currency_rate_pair_value, source, preferences.primaryCurrencyCode)
                        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (automatic) {
                                Text(title, style = MaterialTheme.typography.labelLarge)
                                Text(preferences.displayedRate(snapshots) ?: "—", modifier = Modifier.testTag("currency.automaticRate"))
                            } else {
                                OutlinedTextField(value = preferences.displayedRate() ?: preferences.manualJPYToVNDRate,
                                    onValueChange = store::setDisplayedManualRate, label = { Text(title) }, singleLine = true,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    modifier = Modifier.fillMaxWidth().testTag("currency.manualRate"))
                            }
                        }
                    }
                }
                item { CurrencyDescription(R.string.settings_currency_rate_description) }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable private fun currencyTitle(code: String): String = "$code · " + stringResource(
    if (code == "VND") R.string.settings_currency_currency_name_v_n_d else R.string.settings_currency_currency_name_j_p_y)

@Composable private fun CurrencyDescription(resource: Int) {
    Text(stringResource(resource), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable private fun CurrencyToggle(tag: String, title: String, checked: Boolean, change: (Boolean) -> Unit) {
    ListItem(modifier = Modifier.testTag("currency.$tag").toggleable(checked, role = Role.Switch, onValueChange = change),
        headlineContent = { Text(title) }, trailingContent = { Switch(checked, onCheckedChange = null) })
}
