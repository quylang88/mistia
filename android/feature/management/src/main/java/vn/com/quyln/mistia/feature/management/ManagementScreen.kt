package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft

@Composable
fun ManagementScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    deviceIdProvider: suspend () -> String,
    onSyncNow: () -> Unit,
    onSignOut: () -> Unit,
    onOpenFamily: () -> Unit,
    onOpenInvestment: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val values = counts.associate { it.entity to it.count }
    var walletEditorTarget by remember { mutableStateOf<WalletEditorTarget?>(null) }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        item {
            Text(
                stringResource(R.string.app_roottab_manage),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
        }
        item {
            WalletsSection(
                wallets = wallets,
                onAdd = { walletEditorTarget = WalletEditorTarget(null) },
                onEdit = { walletEditorTarget = WalletEditorTarget(it.id) },
            )
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
        item { Spacer(Modifier.height(92.dp)) }
    }

    walletEditorTarget?.let { target ->
        val wallet = target.walletId?.let { id -> wallets.firstOrNull { it.id == id } }
        WalletEditorSheet(
            wallet = wallet,
            nextSortOrder = (wallets.maxOfOrNull(LedgerWalletRecord::sortOrder) ?: -1) + 1,
            onDismiss = { walletEditorTarget = null },
            onSave = { draft: WalletDraft ->
                repository.saveWallet(
                    ownerUserId = ownerUserId,
                    draft = draft,
                    deviceId = deviceIdProvider(),
                    now = Instant.now().toString(),
                )
            },
            onArchive = archive@{
                val id = target.walletId
                    ?: return@archive Result.failure(IllegalStateException("Wallet ID is missing"))
                repository.archiveWallet(
                    ownerUserId = ownerUserId,
                    walletId = RecordId(id),
                    deviceId = deviceIdProvider(),
                    now = Instant.now().toString(),
                )
            },
        )
    }
}

@Composable
private fun WalletsSection(
    wallets: List<LedgerWalletRecord>,
    onAdd: () -> Unit,
    onEdit: (LedgerWalletRecord) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                stringResource(R.string.management_management_wallets),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
            )
            TextButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = null)
                Text(stringResource(R.string.management_management_add_wallet))
            }
        }

        MistiaGlassCard(contentPadding = PaddingValues(0.dp)) { _ ->
            if (wallets.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(22.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        stringResource(R.string.management_management_no_wallets_yet),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(R.string.management_management_add_cash_pay_pay_bank_or_credit_card),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onAdd) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Text(stringResource(R.string.management_management_add_wallet))
                    }
                }
            } else {
                Column {
                    wallets.forEachIndexed { index, wallet ->
                        WalletRow(wallet = wallet, onClick = { onEdit(wallet) })
                        if (index != wallets.lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                    TextButton(
                        onClick = onAdd,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Text(stringResource(R.string.management_management_add_wallet))
                    }
                }
            }
        }
    }
}

@Composable
private fun WalletRow(wallet: LedgerWalletRecord, onClick: () -> Unit) {
    val editable = wallet.kind in WalletEditorState.supportedKinds
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = editable, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        WalletIcon(wallet.iconSymbolName, wallet.kind, wallet.iconColorHex, Modifier.size(44.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                wallet.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                wallet.kind?.let { walletKindTitle(it) } ?: wallet.kindWireValue,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                formatMinorUnits(wallet.openingBalanceMinor, wallet.currencyCode),
                style = MaterialTheme.typography.labelLarge,
            )
            if (editable) {
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
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

private data class WalletEditorTarget(val walletId: String?)
