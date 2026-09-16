package vn.com.quyln.mistia.feature.investment

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.MistiaRecordRow
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.long
import vn.com.quyln.mistia.core.designsystem.string
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.UserId

@Composable
fun InvestmentScreen(
    ownerUserId: UserId,
    repository: InvestmentRepository,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val assets by repository.observeAssets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val trades by repository.observeTrades(ownerUserId).collectAsStateWithLifecycle(emptyList())
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.common_close))
            }
            Text(stringResource(R.string.investment_title), style = MaterialTheme.typography.headlineMedium)
        }
        if (assets.isEmpty()) {
            item {
                MistiaGlassCard { padding ->
                    Text(stringResource(R.string.investment_hub_empty_message), Modifier.padding(padding))
                }
            }
        } else {
            items(assets, key = { it.id }) { asset ->
                MistiaGlassCard { padding ->
                    MistiaRecordRow(
                        title = asset.string("name") ?: stringResource(R.string.investment_hub_assets_tab),
                        subtitle = asset.string("default_unit_label") ?: asset.string("currency_code"),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
        if (trades.isNotEmpty()) {
            item { Text(stringResource(R.string.investment_hub_activity), style = MaterialTheme.typography.titleLarge) }
            items(trades.take(20), key = { it.id }) { trade ->
                val currency = trade.string("currency_code") ?: "JPY"
                MistiaGlassCard { padding ->
                    MistiaRecordRow(
                        title = trade.string("kind_raw_value") ?: stringResource(R.string.investment_hub_activity),
                        subtitle = trade.string("occurred_at"),
                        trailing = trade.long("gross_amount_minor")?.let { formatMinorUnits(it, currency) },
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
    }
}
