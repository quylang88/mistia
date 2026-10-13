package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import android.content.res.Configuration
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*
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
fun PlanningScreen(
    ownerUserId: UserId,
    repository: FinanceRepository,
    modifier: Modifier = Modifier,
    deviceIdProvider: () -> String,
    exchangeRateRepository: ExchangeRateRepository,
) {
    val goals by repository.observeSavingsGoals(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val walletRecords by repository.observe(CloudEntity.LEDGER_WALLET,ownerUserId).collectAsStateWithLifecycle(emptyList())
    val goalWallets=walletRecords.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull {
        runCatching { LedgerWalletRecord.fromCloudRecord(it).takeIf { wallet -> wallet.ownerUserId==ownerUserId.value && wallet.id==it.id } }.getOrNull()
    }
    var selectedTab by rememberSaveable(ownerUserId.value) { mutableIntStateOf(0) }
    var goalNavigation by rememberSaveable(ownerUserId.value,stateSaver=SavingsGoalNavigationState.saver(ownerUserId.value)) {
        mutableStateOf(SavingsGoalNavigationState(ownerUserId.value,false,null))
    }
    val budgets by repository.observeBudgets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val categories by repository.observeBudgetCategories(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val transactions by repository.observeTransactions(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    LaunchedEffect(ownerUserId.value,exchangeRateRepository) { exchangeRateRepository.refreshIfStale() }
    val rates by exchangeRateRepository.rates.collectAsStateWithLifecycle()
    val zone = ZoneId.systemDefault()
    var navigation by rememberSaveable(ownerUserId.value, stateSaver=BudgetNavigationState.saver(ownerUserId.value)) {
        mutableStateOf(BudgetNavigationState(ownerUserId.value,YearMonth.now(zone).toString(),false,null,null))
    }
    val month=YearMonth.parse(navigation.month)
    val context = LocalContext.current
    val language = when (Locale.getDefault().language) { "vi" -> CategoryNameLanguage.VIETNAMESE; "ja" -> CategoryNameLanguage.JAPANESE; else -> CategoryNameLanguage.ENGLISH }
    val adjustmentTitles = remember(context) { listOf("vi","en","ja").map { lang ->
        context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.forLanguageTag(lang)) })
            .getString(R.string.transactions_generated_title_balance_adjustment)
    }.toSet() }
    val projection = projectBudgets(ownerUserId,budgets,categories,transactions,wallets,month,Instant.now(),zone,rates,language,adjustmentTitles,"JPY",
        stringResource(R.string.planning_planning_deleted_category))
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val values = counts.associate { it.entity to it.count }
    LazyColumn(
        modifier = modifier.testTag("budget.screen").fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Text(stringResource(R.string.planning_planning_planning), style = MaterialTheme.typography.headlineMedium)
        }
        item {
            ScrollableTabRow(selectedTabIndex=selectedTab,edgePadding=0.dp) {
                listOf(R.string.planning_planning_budget,R.string.planning_planning_goals2,R.string.planning_planning_bills2,R.string.planning_planning_installments_loans2).forEachIndexed { index,label ->
                    Tab(selected=selectedTab==index,onClick={selectedTab=index},text={Text(stringResource(label))},modifier=Modifier.testTag("planning.tab.$index"))
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { navigation=navigation.copy(month=month.minusMonths(1).toString()) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.core_ui_mistiamonthnavigation_previous_month)) }
                Text(month.format(DateTimeFormatter.ofPattern("MMMM yyyy",Locale.getDefault())), style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = { navigation=navigation.copy(month=month.plusMonths(1).toString()) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.core_ui_mistiamonthnavigation_next_month)) }
            }
        }
        if(selectedTab==0) {
        item {
            MistiaSectionCard(stringResource(R.string.planning_planning_budget)) {
                Text(formatMinorUnits(projection.totalLimitMinor,"JPY"), style=MaterialTheme.typography.headlineSmall)
                Text("${stringResource(R.string.planning_planning_spent)}: ${formatMinorUnits(projection.totalSpentMinor,"JPY")}")
                Text("${stringResource(R.string.planning_planning_remaining)}: ${formatMinorUnits(projection.remainingMinor,"JPY")}")
            }
        }
        if (projection.branches.isEmpty()) item { Text(stringResource(R.string.planning_planning_no_budgets_yet)) }
        items(projection.branches,key={ it.id }) { branch ->
            BudgetBranchCard(branch) { id -> navigation=navigation.copy(editorId=id,editorOpen=true,editorPayload=budgets.firstOrNull { it.id==id }?.toPayload()?.toString()) }
        }
        item { Button(onClick={navigation=navigation.copy(editorId=null,editorOpen=true,editorPayload=null)},modifier=Modifier.fillMaxWidth().testTag("budget.add")) { Text(stringResource(R.string.planning_planning_add_budget)) } }
        }
        if(selectedTab==1) {
            val rows=savingsGoalRows(ownerUserId,goals,month,zone)
            savingsGoalContent(rows,savingsGoalSummary(rows,"JPY",rates),
                onAdd={goalNavigation=goalNavigation.copy(open=true,payload=null)},
                onEdit={goalNavigation=goalNavigation.copy(open=true,payload=it.toPayload().toString())})
        }
        if(selectedTab==2) item { PlanningCountCard(stringResource(R.string.planning_planning_bills2),values[CloudEntity.RECURRING_BILL_PLAN.table] ?: 0) }
        if(selectedTab==3) item { PlanningCountCard(stringResource(R.string.planning_planning_installments_loans2),values[CloudEntity.INSTALLMENT_PLAN.table] ?: 0) }
    }
    val editorGoal=goalNavigation.goal()
    LaunchedEffect(goalNavigation) {
        if(goalNavigation.open && goalNavigation.payload!=null && editorGoal==null) goalNavigation=goalNavigation.copy(open=false,payload=null)
    }
    if(goalNavigation.open && (goalNavigation.payload==null || editorGoal!=null)) SavingsGoalEditorSheet(ownerUserId.value,editorGoal,goalWallets,
        onSave={repository.saveSavingsGoal(ownerUserId,it,deviceIdProvider(),Instant.now().toString())},
        onDelete={repository.deleteSavingsGoal(ownerUserId,RecordId(it),deviceIdProvider(),Instant.now().toString())},
        onDismiss={goalNavigation=goalNavigation.copy(open=false,payload=null)})
    if (navigation.editorOpen) BudgetEditorSheet(ownerUserId.value,navigation.editorPlan(),month,categories,budgets,transactions,language,
        onSave={ draft -> repository.saveBudget(ownerUserId,draft,deviceIdProvider(),Instant.now().toString()) },
        onArchive={ id -> repository.archiveBudget(ownerUserId,RecordId(id),deviceIdProvider(),Instant.now().toString()) },
        onDelete={ id -> repository.deleteBudget(ownerUserId,RecordId(id),deviceIdProvider(),Instant.now().toString()) },
        onDismiss={ navigation=navigation.copy(editorOpen=false,editorId=null,editorPayload=null) })
}

@Composable
private fun PlanningCountCard(title: String, count: Int) {
    MistiaSectionCard(title = title) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.End,
        ) {
            Text(count.toString(), style = MaterialTheme.typography.headlineSmall)
        }
    }
}
