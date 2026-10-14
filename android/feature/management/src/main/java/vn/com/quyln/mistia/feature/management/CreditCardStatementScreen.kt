package vn.com.quyln.mistia.feature.management

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

private data class StatementRecords(
    val wallets: List<LedgerWalletRecord>,
    val profiles: List<CreditCardProfileRecord>,
    val transactions: List<LedgerTransactionRecord>,
    val occurrences: List<DueOccurrenceRecord>,
    val categories: List<TransactionCategoryRecord>,
)
private sealed interface StatementLoad {
    data object Loading : StatementLoad
    data class Loaded(val records: StatementRecords) : StatementLoad
    data object Failed : StatementLoad
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreditCardStatementScreen(owner: UserId, walletId: String, repository: FinanceRepository, onBack: () -> Unit) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var retry by remember(owner, walletId) { mutableIntStateOf(0) }
    var reference by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) { reference = Instant.now(); delay(60_000) }
        }
    }
    val zone = ZoneId.systemDefault()
    val bounds = StatementMonthBounds.current(reference, zone)
    var navigation by rememberSaveable(owner.value, walletId, stateSaver = CreditCardStatementNavigation.saver(owner.value, walletId)) {
        mutableStateOf(CreditCardStatementNavigation(owner.value, walletId, bounds.maximum.toString()))
    }
    val month = bounds.clamp(YearMonth.parse(navigation.month))
    LaunchedEffect(month) { navigation = navigation.copy(month = month.toString()) }
    val load by produceState<StatementLoad>(StatementLoad.Loading, owner, walletId, retry, lifecycle) {
        value = StatementLoad.Loading
        try {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(
                    repository.observe(CloudEntity.LEDGER_WALLET, owner).map { rows -> rows.mapNotNull {
                        if (it.ownerUserId != owner.value) null else runCatching { LedgerWalletRecord.fromCloudRecord(it) }.getOrNull()
                    } },
                    repository.observeCreditCardProfiles(owner), repository.observeTransactions(owner),
                    repository.observeDueOccurrences(owner), repository.observeBudgetCategoryMetadata(owner),
                ) { wallets, profiles, transactions, occurrences, categories ->
                    StatementRecords(wallets, profiles, transactions, occurrences, categories)
                }.collect { value = StatementLoad.Loaded(it) }
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { value = StatementLoad.Failed }
    }
    val records = (load as? StatementLoad.Loaded)?.records
    val rendered = remember(owner, walletId, records, month, reference, zone) {
        records?.let { runCatching { creditCardStatementViewData(owner, walletId, it.wallets, it.profiles,
            it.transactions, it.occurrences, it.categories, month, reference, zone) } }
    }
    val data = rendered?.getOrNull()
    val latestBack by rememberUpdatedState(onBack)
    LaunchedEffect(records, rendered) {
        if (records != null && rendered?.isSuccess == true && data == null) latestBack()
    }
    Scaffold(topBar = {
        TopAppBar(title = { Text(data?.wallet?.name ?: stringResource(R.string.management_management_credit_card2)) },
            navigationIcon = { IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_close))
            } })
    }) { padding ->
        when {
            load == StatementLoad.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.testTag("statement.loading"))
            }
            load == StatementLoad.Failed || rendered?.isFailure == true -> Column(
                Modifier.fillMaxWidth().padding(padding).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(stringResource(R.string.management_managementcreditcardstatement_could_not_load), Modifier.testTag("statement.error"))
                TextButton(onClick = { retry++ }) { Text(stringResource(R.string.management_managementcreditcardstatement_retry)) }
            }
            data != null -> CreditCardStatementContent(data, records!!.categories.filter { it.ownerUserId == owner.value }, month, bounds, zone,
                onMonth = { navigation = navigation.copy(month = bounds.clamp(it).toString()) }, modifier = Modifier.padding(padding))
        }
    }
}

@Composable
internal fun CreditCardStatementContent(
    data: CreditCardStatementViewData,
    categories: List<TransactionCategoryRecord>,
    month: YearMonth,
    bounds: StatementMonthBounds,
    zone: ZoneId,
    onMonth: (YearMonth) -> Unit,
    modifier: Modifier = Modifier,
) {
    val locale = LocalConfiguration.current.locales[0]
    val dateFormat = remember(locale, zone) { DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT).withLocale(locale).withZone(zone) }
    val statement = data.statement
    val byCategory = remember(categories, data.wallet.ownerUserId) { categories.filter { it.ownerUserId == data.wallet.ownerUserId }.associateBy { it.id } }
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 56.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { StatementMonthNavigation(month, bounds, onMonth) }
        if (statement == null) item {
            MistiaGlassCard { _ -> Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.management_managementcreditcardstatement_no_statement_yet), fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.management_managementcreditcardstatement_this_card_has_no_spending_data_for),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            } }
        } else {
            item {
                MistiaGlassCard { _ -> Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.management_managementcreditcardstatement_total_due), style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(formatMinorUnits(statement.amountMinor, data.wallet.currencyCode), Modifier.testTag("statement.total"),
                                style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Black)
                        }
                        StatementStatusPill(statement.state)
                    }
                    Column {
                        StatementDetail(Icons.Default.CalendarMonth, stringResource(R.string.management_managementcreditcardstatement_statement_period), statementMonthText(month, locale))
                        HorizontalDivider(Modifier.padding(start = 34.dp))
                        StatementDetail(Icons.Default.LockOpen, stringResource(R.string.management_managementcreditcardstatement_closing_date), dateFormat.format(statement.closingDate))
                        HorizontalDivider(Modifier.padding(start = 34.dp))
                        StatementDetail(Icons.Default.Event, stringResource(R.string.management_managementcreditcardstatement_due_date), dateFormat.format(statement.dueDate))
                        HorizontalDivider(Modifier.padding(start = 34.dp))
                        StatementDetail(Icons.Default.AccountBalanceWallet, stringResource(R.string.management_managementcreditcardstatement_linked_wallet),
                            data.linkedWalletName ?: stringResource(R.string.management_managementcreditcardstatement_no_linked_wallet))
                    }
                } }
            }
            item { Text(stringResource(R.string.management_managementcreditcardstatement_charges_in_cycle).uppercase(locale), Modifier.padding(start = 4.dp),
                style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (data.charges.isEmpty()) item {
                MistiaGlassCard { _ -> Text(stringResource(R.string.management_managementcreditcardstatement_no_charges_in_this_cycle),
                    Modifier.fillMaxWidth().padding(vertical = 30.dp, horizontal = 14.dp), textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant) }
            } else item {
                MistiaGlassCard(contentPadding = PaddingValues(0.dp)) { _ -> Column {
                    data.charges.forEachIndexed { index, tx ->
                        StatementCharge(tx, byCategory[tx.categoryId], data.wallet.currencyCode, statement.state == CreditCardStatementState.PAID, dateFormat)
                        if (index < data.charges.lastIndex) HorizontalDivider(Modifier.padding(start = 56.dp))
                    }
                } }
            }
        }
    }
}

@Composable
private fun StatementDetail(icon: ImageVector, title: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.End)
    }
}

@Composable
private fun StatementStatusPill(state: CreditCardStatementState) {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val accent = if (dark) Color(0.65f, 0.45f, 0.98f) else Color(0.43f, 0.23f, 0.76f)
    val (title, icon, color) = when (state) {
        CreditCardStatementState.UNCLOSED -> Triple(R.string.management_managementcreditcardstatement_not_closed_yet, Icons.Default.Lock, MaterialTheme.colorScheme.onSurfaceVariant)
        CreditCardStatementState.PAYABLE -> Triple(R.string.management_managementcreditcardstatement_payable, Icons.Default.CreditCard, accent)
        CreditCardStatementState.OVERDUE -> Triple(R.string.management_managementcreditcardstatement_overdue, Icons.Default.Warning, Color(0xFFD94841))
        CreditCardStatementState.PAID -> Triple(R.string.management_managementcreditcardstatement_paid, Icons.Default.CheckCircle, Color(0xFF2E9E5B))
    }
    Row(Modifier.testTag("statement.status.${state.wireValue}").background(color.copy(alpha = if (dark) 0.18f else 0.12f), CircleShape).padding(horizontal = 10.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, null, Modifier.size(12.dp), tint = color)
        Text(stringResource(title), style = MaterialTheme.typography.labelMedium, color = color, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun StatementCharge(tx: LedgerTransactionRecord, category: TransactionCategoryRecord?, currency: String, locked: Boolean, dates: DateTimeFormatter) {
    Row(Modifier.fillMaxWidth().testTag("statement.charge.${tx.id}").padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CategoryIcon(category?.iconSymbolName ?: "mistia.flow.expense", category?.kind ?: TransactionCategoryKind.EXPENSE,
            category?.iconColorHex ?: "#F76E75", Modifier.size(32.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(tx.title.ifEmpty { category?.let { categoryName(it, currentCategoryLanguage(LocalConfiguration.current.locales[0])) }.orEmpty() },
                    Modifier.weight(1f, fill = false), maxLines = 2, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                if (locked) Icon(Icons.Default.Lock, stringResource(R.string.management_managementcreditcardstatement_paid),
                    Modifier.size(12.dp).testTag("statement.chargeLock.${tx.id}"), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(dates.format(Instant.parse(tx.occurredAt)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text("-" + formatMinorUnits(tx.amountMinor, currency), fontWeight = FontWeight.Bold, color = Color(0.97f, 0.43f, 0.46f))
    }
}

private fun statementMonthText(month: YearMonth, locale: Locale): String =
    month.format(DateTimeFormatter.ofPattern(if (locale.language == "ja") "yyyy年MM月" else "MM/yyyy", locale))

@Composable
internal fun StatementMonthNavigation(month: YearMonth, bounds: StatementMonthBounds, onMonth: (YearMonth) -> Unit) {
    var choosing by rememberSaveable { mutableStateOf(false) }
    val locale = LocalConfiguration.current.locales[0]
    val chooseMonthTitle = stringResource(R.string.core_ui_mistiamonthnavigation_choose_month)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onMonth(month.minusMonths(1)) }, enabled = month > bounds.minimum, modifier = Modifier.testTag("statement.previousMonth")) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.core_ui_mistiamonthnavigation_previous_month))
        }
        FilledTonalButton(onClick = { choosing = true }, modifier = Modifier.weight(1f).testTag("statement.chooseMonth").semantics { contentDescription = chooseMonthTitle }) {
            Icon(Icons.Default.CalendarMonth, null, Modifier.size(18.dp)); Spacer(Modifier.width(10.dp))
            Text(statementMonthText(month, locale), Modifier.weight(1f)); Icon(Icons.Default.UnfoldMore, null, Modifier.size(16.dp))
        }
        IconButton(onClick = { onMonth(month.plusMonths(1)) }, enabled = month < bounds.maximum, modifier = Modifier.testTag("statement.nextMonth")) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.core_ui_mistiamonthnavigation_next_month))
        }
    }
    if (choosing) StatementMonthDialog(month, bounds, onSave = { onMonth(it); choosing = false }, onDismiss = { choosing = false })
}

@Composable
private fun StatementMonthDialog(month: YearMonth, bounds: StatementMonthBounds, onSave: (YearMonth) -> Unit, onDismiss: () -> Unit) {
    var year by rememberSaveable { mutableIntStateOf(month.year) }
    var selectedMonth by rememberSaveable { mutableIntStateOf(month.monthValue) }
    var chooseYear by remember { mutableStateOf(false) }
    var chooseMonth by remember { mutableStateOf(false) }
    val candidate = bounds.clamp(YearMonth.of(year, selectedMonth))
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.core_ui_mistiamonthnavigation_choose_month)) },
        text = { Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.weight(1f)) {
                OutlinedButton(onClick = { chooseMonth = true }, modifier = Modifier.testTag("statement.monthMenu")) {
                    Text(stringResource(R.string.planning_planning_month_value, candidate.monthValue.toString()))
                }
                DropdownMenu(expanded = chooseMonth, onDismissRequest = { chooseMonth = false }) {
                    (1..12).filter { YearMonth.of(candidate.year, it) in bounds.minimum..bounds.maximum }.forEach { value ->
                        DropdownMenuItem(text = { Text(stringResource(R.string.planning_planning_month_value, value.toString())) },
                            onClick = { year = candidate.year; selectedMonth = value; chooseMonth = false }, modifier = Modifier.testTag("statement.month.$value"))
                    }
                }
            }
            Box(Modifier.weight(1f)) {
                OutlinedButton(onClick = { chooseYear = true }, modifier = Modifier.testTag("statement.yearMenu")) {
                    Text(stringResource(R.string.planning_planning_year_value, candidate.year.toString()))
                }
                DropdownMenu(expanded = chooseYear, onDismissRequest = { chooseYear = false }) {
                    (bounds.minimum.year..bounds.maximum.year).forEach { value ->
                        DropdownMenuItem(text = { Text(value.toString()) }, onClick = { year = value; selectedMonth = candidate.monthValue; chooseYear = false },
                            modifier = Modifier.testTag("statement.year.$value"))
                    }
                }
            }
        } },
        confirmButton = { TextButton(onClick = { onSave(candidate) }, modifier = Modifier.testTag("statement.saveMonth")) { Text(stringResource(R.string.common_save)) } },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.testTag("statement.cancelMonth")) { Text(stringResource(R.string.common_cancel)) } })
}
