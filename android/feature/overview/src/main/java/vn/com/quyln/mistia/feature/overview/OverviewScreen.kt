package vn.com.quyln.mistia.feature.overview

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.key
import java.time.ZoneId
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
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
    unreadNotificationCount:Int=0,
    onOpenNotifications:()->Unit={},
    primaryCurrencyCode:String="JPY",
    onOpenTransaction:(String)->Unit={},
    exchangeRates:vn.com.quyln.mistia.core.model.ExchangeRateRepository?=null,
) {
    key(ownerUserId.value) {
        OwnedOverviewScreen(ownerUserId, repository, syncStatus, modifier, unreadNotificationCount, onOpenNotifications, primaryCurrencyCode, onOpenTransaction, exchangeRates)
    }
}

@Composable
private fun OwnedOverviewScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    syncStatus: StateFlow<SyncStatus>,
    modifier: Modifier,
    unreadNotificationCount: Int,
    onOpenNotifications: () -> Unit,
    primaryCurrencyCode: String,
    onOpenTransaction: (String) -> Unit,
    exchangeRates:vn.com.quyln.mistia.core.model.ExchangeRateRepository?,
) {
    val reference=rememberOverviewReferenceTime()
    val rates=exchangeRates?.rates?.collectAsStateWithLifecycle()?.value.orEmpty()
    androidx.compose.runtime.LaunchedEffect(exchangeRates) {exchangeRates?.refreshIfStale()}
    val context=androidx.compose.ui.platform.LocalContext.current
    val knownTitles=remember(context) {vn.com.quyln.mistia.core.designsystem.knownTransactionTitles(context)}
    val zone=ZoneId.systemDefault()
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val transactions by repository.observe(CloudEntity.LEDGER_TRANSACTION, ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observe(CloudEntity.LEDGER_WALLET, ownerUserId)
        .collectAsStateWithLifecycle(emptyList())
    val channels by repository.observe(CloudEntity.INVESTMENT_CHANNEL,ownerUserId).collectAsStateWithLifecycle(emptyList())
    val investmentAssets by repository.observe(CloudEntity.INVESTMENT_ASSET,ownerUserId).collectAsStateWithLifecycle(emptyList())
    val trades by repository.observe(CloudEntity.INVESTMENT_TRADE,ownerUserId).collectAsStateWithLifecycle(emptyList())
    val financial=remember(ownerUserId,transactions,wallets) {overviewFinancialInputs(ownerUserId,transactions,wallets)}
    val inventory=remember(ownerUserId,channels,investmentAssets,trades) {vn.com.quyln.mistia.core.model.overviewInventoryCost(ownerUserId,channels,investmentAssets,trades)}
    val assetBalance=remember(ownerUserId,financial,wallets,inventory,primaryCurrencyCode,rates) {
        val accounting=vn.com.quyln.mistia.core.model.overviewInventoryAccountingCurrency(ownerUserId,wallets,primaryCurrencyCode)
        vn.com.quyln.mistia.core.model.overviewTotalAssets(ownerUserId,financial.wallets,financial.records,primaryCurrencyCode,rates,if(accounting==null) java.math.BigInteger.ZERO else inventory,accounting ?: primaryCurrencyCode)
    }
    val monthly=remember(ownerUserId,financial,primaryCurrencyCode,rates,reference,zone,knownTitles) {
        vn.com.quyln.mistia.core.model.overviewMonthlyCashflow(ownerUserId,financial.records,financial.wallets,primaryCurrencyCode,rates,knownTitles,reference,zone).last()
    }
    val recent = remember(ownerUserId, transactions, wallets, primaryCurrencyCode) {
        overviewRecentTransactions(ownerUserId, transactions, wallets, primaryCurrencyCode)
    }
    val titleCategories by repository.observeBudgetCategoryMetadata(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val titleCategoriesById = remember(titleCategories, ownerUserId) { titleCategories.filter { it.ownerUserId == ownerUserId.value }.associateBy { it.id } }
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
                Row(verticalAlignment=Alignment.CenterVertically) {
                    if (status is SyncStatus.Pulling) CircularProgressIndicator(modifier = Modifier.height(24.dp))
                    IconButton(onClick=onOpenNotifications) {
                        BadgedBox(badge={if(unreadNotificationCount>0) Badge {Text(if(unreadNotificationCount>99) "99+" else unreadNotificationCount.toString())}}) {
                            Icon(Icons.Default.Notifications,stringResource(R.string.notifications_notificationcenter_notifications))
                        }
                    }
                }
            }
        }
        item {OverviewHeroMetrics(monthly,primaryCurrencyCode,assetBalance)}
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
                if (recent.isEmpty()) {
                    Text(
                        text = stringResource(R.string.overview_overview_no_transactions_have_been_recorded_recently),
                        modifier = Modifier.padding(top = 12.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    recent.forEachIndexed { index,row ->
                        OverviewRecentTransactionRow(row,titleCategoriesById[row.transaction.categoryId],reference,zone,Modifier.clickable {onOpenTransaction(row.transaction.id)})
                        if(index<recent.lastIndex) HorizontalDivider()
                    }
                }
            }
        }
        item { Spacer(Modifier.height(92.dp)) }
    }
}
