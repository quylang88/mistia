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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.launch
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
    primaryCurrencyCode: String = "JPY",
) {
    val reportingCurrency = primaryCurrencyCode.trim().uppercase(Locale.ROOT).takeIf { it in CurrencyPreferences.supportedCurrencyCodes } ?: "JPY"
    var cycleAction by remember(ownerUserId.value) {mutableStateOf<Triple<String,String,Boolean>?>(null)}
    var cycleBusy by remember(ownerUserId.value) {mutableStateOf(false)}
    var cycleError by remember(ownerUserId.value) {mutableStateOf(false)}
    val cycleScope=rememberCoroutineScope()
    val billSnapshot by repository.observeRecurringBills(ownerUserId).collectAsStateWithLifecycle(initialValue=null)
    val occurrenceSnapshot by repository.observeDueOccurrences(ownerUserId).collectAsStateWithLifecycle(initialValue=null)
    val bills=billSnapshot.orEmpty()
    val occurrences=occurrenceSnapshot.orEmpty()
    var paymentNavigation by rememberSaveable(ownerUserId.value,stateSaver=BillPaymentNavigation.saver(ownerUserId.value)) {
        mutableStateOf(BillPaymentNavigation(ownerUserId.value,null,YearMonth.now().toString()))
    }
    var billNavigation by rememberSaveable(ownerUserId.value,stateSaver=RecurringBillNavigationState.saver(ownerUserId.value)) {
        mutableStateOf(RecurringBillNavigationState(ownerUserId.value,false,null))
    }
    val editorBill=billNavigation.bill()
    LaunchedEffect(billNavigation) { if(billNavigation.open && billNavigation.payload!=null && editorBill==null) billNavigation=billNavigation.copy(open=false,payload=null) }
    val goals by repository.observeSavingsGoals(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val walletRecords by repository.observe(CloudEntity.LEDGER_WALLET,ownerUserId).collectAsStateWithLifecycle(emptyList())
    val historicalWallets=walletRecords.filter { it.ownerUserId==ownerUserId.value && it.deletedAt==null }.mapNotNull {
        runCatching { LedgerWalletRecord.fromCloudRecord(it).takeIf { wallet -> wallet.ownerUserId==ownerUserId.value && wallet.id==it.id } }.getOrNull()
    }
    var selectedTab by rememberSaveable(ownerUserId.value) { mutableIntStateOf(0) }
    LaunchedEffect(selectedTab) { if(selectedTab !in 0..2) selectedTab=0 }
    var goalNavigation by rememberSaveable(ownerUserId.value,stateSaver=SavingsGoalNavigationState.saver(ownerUserId.value)) {
        mutableStateOf(SavingsGoalNavigationState(ownerUserId.value,false,null))
    }
    val budgets by repository.observeBudgets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val rawBudgets by key(repository,ownerUserId.value) {
        repository.observeBudgetReadRows(ownerUserId).collectAsStateWithLifecycle(initialValue=null)
    }
    val categories by repository.observeBudgetCategories(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val categoryMetadata by repository.observeBudgetCategoryMetadata(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val transactions by repository.observeTransactions(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val wallets by repository.observeWallets(ownerUserId).collectAsStateWithLifecycle(emptyList())
    LaunchedEffect(ownerUserId.value,exchangeRateRepository) { exchangeRateRepository.refreshIfStale() }
    val rates by exchangeRateRepository.rates.collectAsStateWithLifecycle()
    val zone = ZoneId.systemDefault()
    var navigation by rememberSaveable(ownerUserId.value, stateSaver=BudgetNavigationState.saver(ownerUserId.value)) {
        mutableStateOf(BudgetNavigationState(ownerUserId.value,YearMonth.now(zone).toString(),false,null,null))
    }
    var dueMode by rememberSaveable(ownerUserId.value) {mutableIntStateOf(0)}
    val counts by repository.observeEntityCounts(ownerUserId).collectAsStateWithLifecycle(emptyList())
    val values=counts.associate {it.entity to it.count}
    val month=YearMonth.parse(navigation.month)
    val context = LocalContext.current
    val appLocale=LocalConfiguration.current.locales[0]
    val language = when (appLocale.language) { "vi" -> CategoryNameLanguage.VIETNAMESE; "ja" -> CategoryNameLanguage.JAPANESE; else -> CategoryNameLanguage.ENGLISH }
    val adjustmentTitles = remember(context) { listOf("vi","en","ja").map { lang ->
        context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.forLanguageTag(lang)) })
            .getString(R.string.transactions_generated_title_balance_adjustment)
    }.toSet() }
    // Historical spending retains source currency/kind after its wallet is archived.
    val projection = projectRawBudgetPlans(ownerUserId,rawBudgets,categoryMetadata,transactions,historicalWallets,month,Instant.now(),zone,rates,language,adjustmentTitles,reportingCurrency,
        stringResource(R.string.planning_planning_deleted_category))
    LazyColumn(
        modifier = modifier.testTag("budget.screen").fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Text(stringResource(R.string.planning_planning_planning), style = MaterialTheme.typography.headlineMedium)
        }
        item {
            ScrollableTabRow(selectedTabIndex=selectedTab.coerceIn(0,2),edgePadding=0.dp) {
                listOf(R.string.planning_planning_budget,R.string.planning_planning_due2,R.string.planning_planning_goals2).forEachIndexed { index,label ->
                    Tab(selected=selectedTab==index,onClick={selectedTab=index},text={Text(stringResource(label))},modifier=Modifier.testTag("planning.tab.$index"))
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { navigation=navigation.copy(month=month.minusMonths(1).toString()) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.core_ui_mistiamonthnavigation_previous_month)) }
                Text(month.format(DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(appLocale,"yMMMM"),appLocale)), style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = { navigation=navigation.copy(month=month.plusMonths(1).toString()) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.core_ui_mistiamonthnavigation_next_month)) }
            }
        }
        if(selectedTab==0) {
        item {
            MistiaSectionCard(stringResource(R.string.planning_planning_budget)) {
                BudgetSummaryMoney(projection.totalLimitMinor,reportingCurrency,"budget.summary.limit",large=true)
                BudgetSummaryMoney(projection.totalSpentMinor,reportingCurrency,"budget.summary.spent",stringResource(R.string.planning_planning_spent))
                BudgetSummaryMoney(projection.remainingMinor,reportingCurrency,"budget.summary.remaining",stringResource(R.string.planning_planning_remaining))
                if(projection.totalLimitMinor==null || projection.totalSpentMinor==null || projection.remainingMinor==null) Text(stringResource(R.string.overview_overview_reporting_amount_unavailable),Modifier.testTag("budget.summary.unavailable"),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (projection.branches.isEmpty() && projection.totalLimitMinor!=null) item { Text(stringResource(R.string.planning_planning_no_budgets_yet)) }
        items(projection.branches,key={ it.id }) { branch ->
            BudgetBranchCard(branch) { id ->
                val original=id?.let {storedBudgetReadPlan(ownerUserId,it,rawBudgets)}
                if(id==null || original!=null) navigation=navigation.copy(editorId=id,editorOpen=true,editorPayload=original?.toPayload()?.toString())
            }
        }
        item { Button(onClick={navigation=navigation.copy(editorId=null,editorOpen=true,editorPayload=null)},modifier=Modifier.fillMaxWidth().testTag("budget.add")) { Text(stringResource(R.string.planning_planning_add_budget)) } }
        }
        if(selectedTab==2) {
            val rows=savingsGoalRows(ownerUserId,goals,month,zone)
            savingsGoalContent(rows,savingsGoalSummary(rows,reportingCurrency,rates),reportingCurrency=reportingCurrency,
                onAdd={goalNavigation=goalNavigation.copy(open=true,payload=null)},
                onEdit={goalNavigation=goalNavigation.copy(open=true,payload=it.toPayload().toString())})
        }
        if(selectedTab==1) {
            item {Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                listOf(R.string.planning_planning_bills2,R.string.planning_planning_credit_cards,R.string.planning_planning_installments_loans2).forEachIndexed {index,label ->
                    FilterChip(selected=dueMode==index,onClick={dueMode=index},label={Text(stringResource(label))},modifier=Modifier.testTag("planning.due.$index"))
                }
            }}
            if(dueMode==1) item {PlanningCountCard(stringResource(R.string.planning_planning_credit_cards),values[CloudEntity.CREDIT_CARD_PROFILE.table] ?: 0)}
            if(dueMode==2) item {InstallmentDuePane(ownerUserId, repository, month, deviceIdProvider, defaultCurrency=reportingCurrency)}
            if(dueMode==0) {
            val rows=recurringBillDueRows(ownerUserId,bills,occurrences,month,zone)
            item { Text(stringResource(R.string.planning_planning_bills2),style=MaterialTheme.typography.titleLarge) }
            if(rows.isEmpty()) item {Text(stringResource(R.string.planning_planning_no_bills_yet))}
            items(rows,key={"bill.${it.bill.id}"}) {row ->
                MistiaSectionCard(row.bill.name) {
                    Text(row.amountMinor?.let {formatMinorUnits(it,row.bill.currencyCode)} ?: stringResource(R.string.planning_planning_no_amount_yet))
                    Text(stringResource(when(row.status) {
                        DueStatus.PAID -> R.string.planning_planning_paid
                        DueStatus.SKIPPED -> R.string.planning_duepayment_bill_skipped
                        else -> R.string.planning_planning_due2
                    }))
                    Text("${stringResource(R.string.planning_planning_payment_date)}: ${row.paymentStartDate.atZone(zone).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM))}")
                    if(row.hasExplicitDueDate) Text("${stringResource(R.string.planning_planning_deadline)}: ${row.dueDate.atZone(zone).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM))}")
                    row.autoPayDate?.let {Text("${stringResource(R.string.planning_planning_auto_pay_date)}: ${it.atZone(zone).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM))}")}
                    if(!row.bill.isArchived && row.bill.deletedAt==null && row.status!=DueStatus.SKIPPED) TextButton(
                        enabled=!cycleBusy,onClick={paymentNavigation=paymentNavigation.copy(billId=row.bill.id,month=month.toString(),undo=row.status==DueStatus.PAID)},
                        modifier=Modifier.testTag("bill.pay.${row.bill.id}")) {
                        Text(stringResource(if(row.status==DueStatus.PAID) R.string.planning_duepayment_undo_payment else R.string.planning_planning_pay))
                    }
                    if(!row.bill.isArchived && row.bill.deletedAt==null && row.status!=DueStatus.PAID) TextButton(
                        enabled=!cycleBusy,onClick={cycleError=false;cycleAction=Triple(row.bill.id,month.toString(),row.status==DueStatus.SKIPPED)},
                        modifier=Modifier.testTag("bill.skip.${row.bill.id}")) {
                        Text(stringResource(if(row.status==DueStatus.SKIPPED) R.string.planning_duepayment_undo_skip else R.string.planning_duepayment_skip_this_month))
                    }
                    if(!row.bill.isArchived && row.bill.deletedAt==null) TextButton(onClick={billNavigation=billNavigation.copy(payload=row.bill.toPayload().toString(),open=true)},modifier=Modifier.testTag("bill.edit.${row.bill.id}")) {Text(stringResource(R.string.planning_planning_s_a_h_a_n))}
                }
            }
            val paused=bills.filter {it.ownerUserId==ownerUserId.value && !it.isArchived && it.deletedAt==null && it.isPaused}
            if(paused.isNotEmpty()) item {Text(stringResource(R.string.planning_planning_paused_bills),style=MaterialTheme.typography.titleMedium)}
            items(paused,key={"paused.${it.id}"}) {bill ->
                MistiaSectionCard(bill.name) {TextButton(onClick={billNavigation=billNavigation.copy(payload=bill.toPayload().toString(),open=true)},modifier=Modifier.testTag("bill.edit.${bill.id}")) {Text(stringResource(R.string.planning_planning_s_a_h_a_n))}}
            }
            item {Button(onClick={billNavigation=billNavigation.copy(payload=null,open=true)},modifier=Modifier.fillMaxWidth().testTag("bill.add")) {Text(stringResource(R.string.planning_planning_add_bill))}}
            }
        }
    }
    val paymentMonth=YearMonth.parse(paymentNavigation.month)
    val paymentRow=recurringBillDueRows(ownerUserId,bills,occurrences,paymentMonth,zone).firstOrNull {
        it.bill.id==paymentNavigation.billId && !it.bill.isArchived && it.bill.deletedAt==null &&
            it.status==if(paymentNavigation.undo) DueStatus.PAID else DueStatus.PENDING
    }
    LaunchedEffect(paymentNavigation,billSnapshot,occurrenceSnapshot) {
        if(paymentNavigation.billId!=null && billSnapshot!=null && occurrenceSnapshot!=null && paymentRow==null)
            paymentNavigation=paymentNavigation.copy(billId=null)
    }
    if(paymentRow!=null && billSnapshot!=null && occurrenceSnapshot!=null) key(ownerUserId.value,paymentRow.bill.id,paymentMonth,paymentNavigation.undo) {
        BillPaymentSheet(ownerUserId.value,paymentRow,paymentMonth,historicalWallets,paymentNavigation.undo,
            onPay={repository.payRecurringBill(ownerUserId,it,deviceIdProvider(),Instant.now().toString())},
            onUndo={repository.undoRecurringBillPayment(ownerUserId,RecordId(paymentRow.bill.id),paymentMonth,deviceIdProvider(),Instant.now().toString())},
            onDismiss={paymentNavigation=paymentNavigation.copy(billId=null)},category=categories.firstOrNull {it.id==paymentRow.bill.categoryId && it.ownerUserId==ownerUserId.value})
    }
    cycleAction?.let {action ->
        val title=if(action.third) R.string.planning_duepayment_undo_skip else R.string.planning_duepayment_skip_this_month
        AlertDialog(onDismissRequest={if(!cycleBusy) cycleAction=null},title={Text(stringResource(title))},
            text={androidx.compose.foundation.layout.Column {
                Text(stringResource(if(action.third) R.string.planning_duepayment_undo_skip_message else R.string.planning_duepayment_skip_confirmation_message))
                if(cycleError) Text(stringResource(R.string.planning_planning_couldn_t_save_this_bill_right_now),color=MaterialTheme.colorScheme.error)
            }},confirmButton={TextButton(enabled=!cycleBusy,onClick={
                cycleBusy=true;cycleError=false
                cycleScope.launch {
                    val result=if(action.third) repository.undoRecurringBillSkip(ownerUserId,RecordId(action.first),YearMonth.parse(action.second),deviceIdProvider(),Instant.now().toString())
                        else repository.skipRecurringBill(ownerUserId,RecordId(action.first),YearMonth.parse(action.second),deviceIdProvider(),Instant.now().toString()).map {Unit}
                    cycleBusy=false;result.fold(onSuccess={cycleAction=null},onFailure={cycleError=true})
                }
            },modifier=Modifier.testTag("bill.confirmSkip")) {Text(stringResource(title))}},dismissButton={TextButton(enabled=!cycleBusy,onClick={cycleAction=null}) {Text(stringResource(R.string.common_cancel))}})
    }
    if(billNavigation.open && (billNavigation.payload==null || editorBill!=null)) RecurringBillEditorSheet(ownerUserId.value,editorBill,categories,historicalWallets,language,
        onSave={repository.saveRecurringBill(ownerUserId,it,deviceIdProvider(),Instant.now().toString())},
        onPause={repository.pauseRecurringBill(ownerUserId,RecordId(it),deviceIdProvider(),Instant.now().toString())},
        onResume={repository.resumeRecurringBill(ownerUserId,RecordId(it),deviceIdProvider(),Instant.now().toString())},
        onArchive={repository.archiveRecurringBill(ownerUserId,RecordId(it),deviceIdProvider(),Instant.now().toString())},
        onDismiss={billNavigation=billNavigation.copy(open=false,payload=null)},primaryCurrencyCode=reportingCurrency)
    val editorGoal=goalNavigation.goal()
    LaunchedEffect(goalNavigation) {
        if(goalNavigation.open && goalNavigation.payload!=null && editorGoal==null) goalNavigation=goalNavigation.copy(open=false,payload=null)
    }
    if(goalNavigation.open && (goalNavigation.payload==null || editorGoal!=null)) SavingsGoalEditorSheet(ownerUserId.value,editorGoal,historicalWallets,
        onSave={repository.saveSavingsGoal(ownerUserId,it,deviceIdProvider(),Instant.now().toString())},
        onDelete={repository.deleteSavingsGoal(ownerUserId,RecordId(it),deviceIdProvider(),Instant.now().toString())},
        onDismiss={goalNavigation=goalNavigation.copy(open=false,payload=null)},primaryCurrencyCode=reportingCurrency)
    if (navigation.editorOpen) BudgetEditorSheet(ownerUserId.value,navigation.editorPlan(),month,categories,budgets,transactions,language,
        categoryMetadata=categoryMetadata,
        onSave={ draft -> repository.saveBudget(ownerUserId,draft,deviceIdProvider(),Instant.now().toString()) },
        onArchive={ id -> repository.archiveBudget(ownerUserId,RecordId(id),deviceIdProvider(),Instant.now().toString()) },
        onDelete={ id -> repository.deleteBudget(ownerUserId,RecordId(id),deviceIdProvider(),Instant.now().toString()) },
        onDismiss={ navigation=navigation.copy(editorOpen=false,editorId=null,editorPayload=null) },primaryCurrencyCode=reportingCurrency)
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
