package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.MistiaRecordRow
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.ExchangeRateRepository
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.isLockedByPaidCreditCardStatement
import vn.com.quyln.mistia.core.model.transactionDisplayMoney

@Composable
fun TransactionsScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    exchangeRateRepository: ExchangeRateRepository,
    deviceIdProvider: suspend () -> String,
    modifier: Modifier = Modifier,
) {
    val records by repository.observeTransactions(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val categories by repository.observeCategories(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val creditCardProfiles by repository.observeCreditCardProfiles(ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val dueOccurrences by repository.observe(CloudEntity.DUE_OCCURRENCE_RECORD, ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val exchangeRates by exchangeRateRepository.rates.collectAsStateWithLifecycle()
    LaunchedEffect(exchangeRateRepository) {
        exchangeRateRepository.refreshIfStale()
    }
    var editorOpen by rememberSaveable { mutableStateOf(false) }
    var editorTransactionId by rememberSaveable { mutableStateOf<String?>(null) }
    val walletCurrencies = wallets.associate { it.id to it.currencyCode }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = stringResource(R.string.app_roottab_transactions),
                    style = MaterialTheme.typography.headlineMedium,
                )
                Button(
                    onClick = {
                        editorTransactionId = null
                        editorOpen = true
                    },
                ) {
                    Text(stringResource(R.string.shared_sync_mistiasynccoordinator_new_transaction))
                }
            }
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
                val isLockedByPaidStatement = record.isLockedByPaidCreditCardStatement(
                    wallets = wallets,
                    creditCardProfiles = creditCardProfiles,
                    categories = categories,
                    transactions = records,
                    dueOccurrences = dueOccurrences,
                )
                val isEditable = record.supportsNativeTransactionEditor() && !isLockedByPaidStatement
                MistiaGlassCard(
                    modifier = Modifier.clickable(enabled = isEditable) {
                        editorTransactionId = record.id
                        editorOpen = true
                    },
                ) { padding ->
                    val money = record.transactionDisplayMoney(
                        walletCurrencies[record.sourceWalletId],
                        walletCurrencies[record.destinationWalletId],
                    )
                    MistiaRecordRow(
                        title = record.title.ifBlank {
                            stringResource(R.string.shared_corelogic_transaction_unknown_name)
                        },
                        subtitle = if (isLockedByPaidStatement) {
                            stringResource(
                                R.string.transactions_transactioneditor_this_transaction_is_part_of_a_paid
                            )
                        } else {
                            record.occurredAt
                        },
                        trailing = formatMinorUnits(money.minor, money.currencyCode),
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
    }

    if (editorOpen) {
        val transaction = editorTransactionId?.let { id -> records.firstOrNull { it.id == id } }
        if (editorTransactionId == null || transaction != null) {
            TransactionEditorSheet(
                transaction = transaction,
                wallets = wallets,
                categories = categories,
                exchangeRates = exchangeRates,
                now = Instant.now().toString(),
                onDismiss = { editorOpen = false },
                onSave = { draft ->
                    repository.saveTransaction(
                        ownerUserId = ownerUserId,
                        draft = draft,
                        deviceId = deviceIdProvider(),
                        now = Instant.now().toString(),
                    )
                },
            )
        }
    }
}
