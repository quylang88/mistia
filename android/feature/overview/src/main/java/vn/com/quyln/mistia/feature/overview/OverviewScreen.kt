package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaRecordRow
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.long
import vn.com.quyln.mistia.core.designsystem.string
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.SyncStatus
import vn.com.quyln.mistia.core.model.UserId
import kotlinx.coroutines.flow.StateFlow

@Composable
fun OverviewScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    syncStatus: StateFlow<SyncStatus>,
    modifier: Modifier = Modifier,
) {
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val transactions by repository.observe(CloudEntity.LEDGER_TRANSACTION, ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val status by syncStatus.collectAsStateWithLifecycle()
    val countMap = counts.associate { it.entity to it.count }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = stringResource(R.string.overview_overview_overview),
                    style = MaterialTheme.typography.headlineMedium,
                )
                if (status is SyncStatus.Pulling) CircularProgressIndicator(modifier = Modifier.height(24.dp))
            }
        }
        item {
            MistiaSectionCard(title = stringResource(R.string.family_family_wallets_cards)) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(stringResource(R.string.management_management_wallets))
                    Text((countMap[CloudEntity.LEDGER_WALLET.table] ?: 0).toString())
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(stringResource(R.string.management_management_categories))
                    Text((countMap[CloudEntity.TRANSACTION_CATEGORY.table] ?: 0).toString())
                }
            }
        }
        item {
            MistiaSectionCard(title = stringResource(R.string.overview_overview_recent_transactions)) {
                if (transactions.isEmpty()) {
                    Text(
                        text = stringResource(R.string.overview_overview_no_transactions_have_been_recorded_recently),
                        modifier = Modifier.padding(top = 12.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    transactions.take(8).forEach { transaction ->
                        val amount = transaction.long("amount_minor")
                        val currency = transaction.string("reporting_currency_code")
                            ?: transaction.string("source_currency_code")
                            ?: "JPY"
                        MistiaRecordRow(
                            title = transaction.string("title")
                                ?: stringResource(R.string.shared_corelogic_transaction_unknown_name),
                            subtitle = transaction.string("occurred_at"),
                            trailing = amount?.let { formatMinorUnits(it, currency) },
                        )
                    }
                }
            }
        }
        item { Spacer(Modifier.height(92.dp)) }
    }
}
