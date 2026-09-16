package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.UserId

@Composable
fun ManagementScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    onSyncNow: () -> Unit,
    onSignOut: () -> Unit,
    onOpenFamily: () -> Unit,
    onOpenInvestment: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val values = counts.associate { it.entity to it.count }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Text(stringResource(R.string.app_roottab_manage), style = MaterialTheme.typography.headlineMedium)
        }
        item {
            MistiaSectionCard(title = stringResource(R.string.management_management_wallets)) {
                CountRow(values[CloudEntity.LEDGER_WALLET.table] ?: 0)
            }
        }
        item {
            MistiaSectionCard(title = stringResource(R.string.management_management_categories)) {
                CountRow(values[CloudEntity.TRANSACTION_CATEGORY.table] ?: 0)
            }
        }
        item {
            OutlinedButton(onClick = onOpenFamily, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.family_family_family))
            }
        }
        item {
            OutlinedButton(onClick = onOpenInvestment, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.investment_title))
            }
        }
        item {
            Button(onClick = onSyncNow, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.management_managementauth_sync_now))
            }
        }
        item {
            OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.management_managementauth_sign_out_this_device))
            }
        }
    }
}

@Composable
private fun CountRow(value: Int) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        horizontalArrangement = Arrangement.End,
    ) {
        Text(value.toString(), style = MaterialTheme.typography.headlineSmall)
    }
}
