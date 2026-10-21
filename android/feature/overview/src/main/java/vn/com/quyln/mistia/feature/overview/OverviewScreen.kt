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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.time.ZoneId
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.com.quyln.mistia.core.designsystem.MistiaSectionCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*
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
    overlayPresented:Boolean=false,
    onOpenRecurringDue:(UpcomingDuePaymentTarget)->Unit={},
) {
    val reportingCurrency=primaryCurrencyCode.trim().uppercase(java.util.Locale.ROOT)
        .takeIf {it in vn.com.quyln.mistia.core.model.CurrencyPreferences.supportedCurrencyCodes} ?: "JPY"
    key(ownerUserId.value) {
        OwnedOverviewScreen(ownerUserId, repository, syncStatus, modifier, unreadNotificationCount, onOpenNotifications, reportingCurrency, onOpenTransaction, exchangeRates, overlayPresented, onOpenRecurringDue)
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
    overlayPresented:Boolean,
    onOpenRecurringDue:(UpcomingDuePaymentTarget)->Unit,
) {
    val reference=rememberOverviewReferenceTime()
    val rates=exchangeRates?.rates?.collectAsStateWithLifecycle()?.value.orEmpty()
    androidx.compose.runtime.LaunchedEffect(exchangeRates) {exchangeRates?.refreshIfStale()}
    val context=androidx.compose.ui.platform.LocalContext.current
    val knownTitles=remember(context) {vn.com.quyln.mistia.core.designsystem.knownTransactionTitles(context)}
    val zone=ZoneId.systemDefault()
    var financialRetry by remember(repository) {androidx.compose.runtime.mutableIntStateOf(0)}
    val financialLoad by overviewFinancialReadLoad(ownerUserId,repository,financialRetry)
    val financialSnapshot=(financialLoad as? OverviewFinancialReadLoad.Loaded)?.snapshot
    val transactions=financialSnapshot?.records(CloudEntity.LEDGER_TRANSACTION).orEmpty()
    val wallets=financialSnapshot?.records(CloudEntity.LEDGER_WALLET).orEmpty()
    val channels=financialSnapshot?.records(CloudEntity.INVESTMENT_CHANNEL).orEmpty()
    val investmentAssets=financialSnapshot?.records(CloudEntity.INVESTMENT_ASSET).orEmpty()
    val trades=financialSnapshot?.records(CloudEntity.INVESTMENT_TRADE).orEmpty()
    val inventory=remember(ownerUserId,financialSnapshot) {if(financialSnapshot==null) null else overviewInventoryCost(ownerUserId,channels,investmentAssets,trades)}
    val assetBalance=remember(ownerUserId,financialSnapshot,inventory,primaryCurrencyCode,rates) {
        if(financialSnapshot==null) return@remember null
        val accounting=vn.com.quyln.mistia.core.model.overviewInventoryAccountingCurrency(ownerUserId,wallets,primaryCurrencyCode)
        overviewAssetBalance(ownerUserId,transactions,wallets,primaryCurrencyCode,rates,inventory,accounting)
    }
    val monthly=remember(ownerUserId,financialSnapshot,primaryCurrencyCode,rates,reference,zone,knownTitles) {
        if(financialSnapshot==null) listOf(OverviewMonthlyCashflow(java.time.YearMonth.from(reference.atZone(zone)),null,null)) else overviewRawMonthlyCashflow(ownerUserId,transactions,wallets,primaryCurrencyCode,rates,knownTitles,reference,zone)
    }
    val weeks=remember(ownerUserId,financialSnapshot,primaryCurrencyCode,rates,reference,zone,knownTitles) {
        if(financialSnapshot==null) {
            val today=reference.atZone(zone).toLocalDate();val start=today.minusDays(today.dayOfWeek.value.toLong()-1)
            listOf(OverviewWeekSpending(start,true,(0L..6).map {OverviewDailySpending(start.plusDays(it),null,0.0)}))
        } else overviewRawWeeklySpending(ownerUserId,transactions,wallets,primaryCurrencyCode,rates,knownTitles,reference,zone)
    }
    val recent = remember(ownerUserId, financialSnapshot, primaryCurrencyCode) {
        if(financialSnapshot==null) null else overviewRecentTransactions(ownerUserId, transactions, wallets, primaryCurrencyCode)
    }
    val recentUncertain=remember(ownerUserId,financialSnapshot) {financialSnapshot==null || overviewRecentHasUncertainDeletion(ownerUserId,transactions,wallets)}
    val titleCategories=remember(ownerUserId,financialSnapshot) {
        financialSnapshot?.records(CloudEntity.TRANSACTION_CATEGORY).orEmpty().mapNotNull {raw ->
            if(!raw.financeRawIdentity(ownerUserId,CloudEntity.TRANSACTION_CATEGORY,true)) null
            else runCatching {TransactionCategoryRecord.fromCloudRecord(raw)}.getOrNull()
        }
    }
    val titleCategoriesById = remember(titleCategories, ownerUserId) { titleCategories.filter { it.ownerUserId == ownerUserId.value }.associateBy { it.id } }
    val language=androidx.compose.ui.platform.LocalConfiguration.current.locales[0].language
    val categoryCatalog=remember(context.applicationContext) {vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog(context)}
    val categoryCurrency=primaryCurrencyCode.trim().uppercase(java.util.Locale.ROOT).takeIf {it in vn.com.quyln.mistia.core.model.CurrencyPreferences.supportedCurrencyCodes} ?: "JPY"
    val categoryMonths=remember(ownerUserId,financialSnapshot,titleCategories,categoryCurrency,rates,language,categoryCatalog,reference,zone) {
        if(financialSnapshot==null) listOf(OverviewCategorySpendingMonth(java.time.YearMonth.from(reference.atZone(zone)),categoryCurrency,emptyList(),null)) else overviewRawCategorySpendingMonths(ownerUserId,transactions,wallets,titleCategories,categoryCurrency,rates,language,categoryCatalog,reference,zone)
    }
    val status by syncStatus.collectAsStateWithLifecycle()
    var selectedDay by remember {mutableStateOf<java.time.LocalDate?>(null)}
    androidx.compose.runtime.LaunchedEffect(overlayPresented) {if(overlayPresented) selectedDay=null}
    fun expenseDay(day:java.time.LocalDate)=overviewRawExpenseDay(ownerUserId,transactions,wallets,day,primaryCurrencyCode,rates,knownTitles,zone)
    val dayDetails=remember(selectedDay,ownerUserId,financialSnapshot,primaryCurrencyCode,rates,knownTitles,zone) {if(financialSnapshot==null) null else selectedDay?.let(::expenseDay)}
    androidx.compose.runtime.LaunchedEffect(financialSnapshot==null) {if(financialSnapshot==null) selectedDay=null}

    var budgetRetry by remember(repository) {androidx.compose.runtime.mutableIntStateOf(0)}
    val budgetLoad by overviewBudgetReadLoad(ownerUserId,repository,budgetRetry)
    val budgetSnapshot=(budgetLoad as? OverviewBudgetReadLoad.Loaded)?.snapshot
    val budgetLanguage=when(language) {"vi" -> CategoryNameLanguage.VIETNAMESE;"ja" -> CategoryNameLanguage.JAPANESE;else -> CategoryNameLanguage.ENGLISH}
    val budgetDeletedName=stringResource(R.string.planning_planning_deleted_category)
    val budgetLocale=androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    val budgetAlerts=remember(budgetSnapshot,reference,zone,rates,budgetLanguage,knownTitles,primaryCurrencyCode,budgetDeletedName,budgetLocale) {
        overviewBudgetAlerts(projectRawBudgetReadSnapshot(ownerUserId,budgetSnapshot,java.time.YearMonth.from(reference.atZone(zone)),reference,zone,rates,
            budgetLanguage,knownTitles[GeneratedTransactionTitle.BALANCE_ADJUSTMENT].orEmpty().toSet(),primaryCurrencyCode,budgetDeletedName),locale=budgetLocale)
    }

    var dueRetry by remember(repository) {androidx.compose.runtime.mutableIntStateOf(0)}
    val dueLoad by overviewDueReadLoad(ownerUserId,repository,dueRetry)
    val dueSnapshot=(dueLoad as? OverviewDueReadLoad.Loaded)?.snapshot
    val dueAlerts=remember(dueSnapshot,reference,zone,budgetLocale) {
        projectUpcomingRecurringDues(ownerUserId,dueSnapshot,reference,zone,budgetLocale)
    }

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
        item {
            Column {
                if(financialLoad==OverviewFinancialReadLoad.Loading) CircularProgressIndicator(Modifier.height(24.dp).testTag("overview.financial.loading"))
                if(financialLoad==OverviewFinancialReadLoad.Failed) androidx.compose.material3.TextButton(onClick={financialRetry++},modifier=Modifier.testTag("overview.financial.retry")) {
                    Text(stringResource(R.string.planning_installment_retry))
                }
                OverviewHeroMetrics(monthly,primaryCurrencyCode,assetBalance,weeks,categoryMonths,overlayPresented || selectedDay!=null || financialSnapshot==null) {day ->
                    if(financialSnapshot!=null && !overlayPresented && expenseDay(day).let {it.rows.isNotEmpty() || it.hasUncertainEntries}) selectedDay=day
                }
            }
        }
        if(budgetAlerts==null || budgetAlerts.isNotEmpty()) item(key="overview.budget.focus") {
            OverviewBudgetFocus(budgetAlerts,budgetLoad==OverviewBudgetReadLoad.Failed,onRetry={budgetRetry++})
        }
        if(dueAlerts==null || dueAlerts.isNotEmpty()) item(key="overview.due.section") {
            OverviewUpcomingDues(dueAlerts,dueLoad==OverviewDueReadLoad.Failed || (dueSnapshot!=null && dueAlerts==null),
                onRetry={dueRetry++},onSelect={if(!overlayPresented) onOpenRecurringDue(it.paymentTarget())},enabled=!overlayPresented,zone=zone)
        }
        item {
            MistiaSectionCard(title = stringResource(R.string.overview_overview_recent_transactions)) {
                if(recentUncertain) {
                    Text(stringResource(R.string.overview_overview_reporting_amount_unavailable),Modifier.padding(top=12.dp).testTag("overview.recent.unavailable"),color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (recent!=null && recent.isEmpty() && !recentUncertain) {
                    Text(
                        text = stringResource(R.string.overview_overview_no_transactions_have_been_recorded_recently),
                        modifier = Modifier.padding(top = 12.dp).testTag("overview.recent.empty"),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else if(recent!=null) {
                    recent.forEachIndexed { index,row ->
                        OverviewRecentTransactionRow(row,titleCategoriesById[row.transaction.categoryId],reference,zone,Modifier.clickable {onOpenTransaction(row.transaction.id)})
                        if(index<recent.lastIndex) HorizontalDivider()
                    }
                }
            }
        }
        item { Spacer(Modifier.height(92.dp)) }
    }
    dayDetails?.let {day -> key(day.day) {
        OverviewDayTransactionsSheet(day,overviewDayWalletMetadata(ownerUserId,wallets),titleCategoriesById,zone,onDismiss={selectedDay=null},onSelect={id ->
            if(day.rows.any {it.transaction.id==id}) {selectedDay=null;onOpenTransaction(id)}
        })
    }}
}
