package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.transactionDisplayMoney

@Composable
fun TransactionsScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    modifier: Modifier = Modifier,
) {
    val records by repository.observeTransactions(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val walletCurrencies = wallets.associate { it.id to it.currencyCode }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Text(
                text = stringResource(R.string.app_roottab_transactions),
                style = MaterialTheme.typography.headlineMedium,
            )
        }
        if (records.isEmpty()) {
            item {
                MistiaGlassCard { padding ->
                    Text(
                        text = stringResource(R.string.transactions_transactions_no_transactions_yet),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        } else {
            items(records, key = { it.id }) { record ->
                MistiaGlassCard { padding ->
                    val money = record.transactionDisplayMoney(
                        walletCurrencies[record.sourceWalletId],
                        walletCurrencies[record.destinationWalletId],
                    )
                    MistiaRecordRow(
                        title = record.title.ifBlank {
                            stringResource(R.string.shared_corelogic_transaction_unknown_name)
                        },
                        subtitle = record.occurredAt,
                        trailing = formatMinorUnits(money.minor, money.currencyCode),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
    }
}
