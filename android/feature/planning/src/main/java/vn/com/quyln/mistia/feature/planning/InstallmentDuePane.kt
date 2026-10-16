package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.util.UUID
import java.util.Locale
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

private data class InstallmentRecords(val plans: List<InstallmentPlanRecord>, val occurrences: List<DueOccurrenceRecord>, val wallets: List<LedgerWalletRecord>)
private sealed interface InstallmentLoad {
    data object Loading : InstallmentLoad
    data class Loaded(val records: InstallmentRecords) : InstallmentLoad
    data object Failed : InstallmentLoad
}

@Composable
internal fun InstallmentDuePane(owner: UserId, repository: FinanceRepository, month: YearMonth, deviceIdProvider: () -> String, defaultCurrency: String = "JPY", now: () -> Instant = Instant::now) {
    // Saveable keys must survive repository recreation after process death.
    val primary = defaultCurrency.trim().uppercase(Locale.ROOT).takeIf { it in CurrencyPreferences.supportedCurrencyCodes } ?: "JPY"
    key(owner.value) { OwnedInstallmentDuePane(owner, repository, month, deviceIdProvider, primary, now) }
}

@Composable
private fun OwnedInstallmentDuePane(owner: UserId, repository: FinanceRepository, month: YearMonth, deviceIdProvider: () -> String, defaultCurrency: String, now: () -> Instant) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val currentTime by rememberUpdatedState(now)
    var reference by remember { mutableStateOf(currentTime()) }
    var navigation by rememberSaveable(owner.value, stateSaver = InstallmentEditorNavigation.saver(owner.value)) {
        mutableStateOf(InstallmentEditorNavigation.closed(owner.value))
    }
    LaunchedEffect(navigation) { if (!navigation.valid()) navigation = InstallmentEditorNavigation.closed(owner.value) }
    LaunchedEffect(defaultCurrency) {
        if (navigation.editorId != null && navigation.baselinePayload == null && navigation.currency != defaultCurrency) {
            navigation = InstallmentEditorNavigation.create(owner.value, defaultCurrency, UUID.randomUUID().toString())
        }
    }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) { reference = currentTime(); delay(60_000) }
        }
    }
    val zone = ZoneId.systemDefault()
    var paymentNavigation by rememberSaveable(owner.value, month, zone.id, stateSaver = InstallmentPaymentNavigation.saver(owner.value, month)) {
        mutableStateOf(InstallmentPaymentNavigation.closed(owner.value, month))
    }
    var retry by remember { mutableIntStateOf(0) }
    val load by key(repository, retry, lifecycle) {
        produceState<InstallmentLoad>(InstallmentLoad.Loading) {
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    combine(repository.observeInstallments(owner), repository.observeDueOccurrences(owner), repository.observe(CloudEntity.LEDGER_WALLET, owner)) { plans, occurrences, rawWallets ->
                        val wallets = rawWallets.filter { it.ownerUserId == owner.value && it.deletedAt == null }.mapNotNull { row ->
                            runCatching { LedgerWalletRecord.fromCloudRecord(row).takeIf { it.ownerUserId == owner.value && it.id == row.id && it.deletedAt == null } }.getOrNull()
                        }
                        InstallmentRecords(plans, occurrences, wallets)
                    }.collect { value = InstallmentLoad.Loaded(it) }
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { value = InstallmentLoad.Failed }
        }
    }
    val records = (load as? InstallmentLoad.Loaded)?.records
    val rows = remember(records, month, zone) { records?.let { runCatching { installmentDueRows(owner, it.plans, it.occurrences, month, zone) } } }
    when {
        load == InstallmentLoad.Loading -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.testTag("installment.loading"))
        }
        load == InstallmentLoad.Failed || rows?.isFailure == true -> Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.planning_installment_load_error), Modifier.testTag("installment.error"))
            TextButton(onClick = { retry++ }) { Text(stringResource(R.string.planning_installment_retry)) }
        }
        rows?.isSuccess == true -> InstallmentDueWorkflow(owner, repository, rows.getOrThrow(), month, reference, zone, deviceIdProvider, currentTime,
            onAdd = { navigation = InstallmentEditorNavigation.create(owner.value, defaultCurrency, UUID.randomUUID().toString()) },
            onEdit = { navigation = InstallmentEditorNavigation.edit(owner.value, it) },
            onPayment = { paymentNavigation = InstallmentPaymentNavigation.open(owner.value, it) })
    }
    val paymentRow = remember(paymentNavigation) { paymentNavigation.row() }
    if (paymentRow != null && paymentRow.month == month) key(owner.value, month, zone.id, paymentRow.plan.id) {
        InstallmentPaymentSheet(owner.value, paymentRow, records?.wallets.orEmpty(), dataReady = records != null,
            loadFailed = load == InstallmentLoad.Failed, targetCurrent = installmentPaymentTargetIsCurrent(paymentRow,
                rows?.getOrNull()?.firstOrNull { it.plan.id == paymentRow.plan.id }), onRetryLoad = { retry++ },
            onPay = { request -> repository.payInstallment(owner, request, deviceIdProvider(), currentTime().toString()) },
            onUndo = { repository.undoInstallmentPayment(owner, paymentRow.plan, paymentRow.month, deviceIdProvider(), currentTime().toString()) },
            onDismiss = { paymentNavigation = InstallmentPaymentNavigation.closed(owner.value, month) })
    }
    // Keep the editor composed across month/zone/loading changes so drafts and operations survive.
    val editorId = navigation.editorId
    if (editorId != null && navigation.valid()) InstallmentEditorSheet(owner.value, editorId, navigation.baseline(), navigation.currency,
        records?.wallets.orEmpty(), dataReady = records != null, loadFailed = load == InstallmentLoad.Failed, onRetryLoad = { retry++ },
        onSave = { draft -> repository.saveInstallment(owner, draft, deviceIdProvider(), currentTime().toString()) },
        onDelete = { expected -> repository.deleteInstallment(owner, expected, deviceIdProvider(), currentTime().toString()) },
        onDismiss = { navigation = navigation.closed() })
}

@Composable
internal fun InstallmentDueContent(rows: List<InstallmentDueRow>, reference: Instant, zone: ZoneId,
    onAdd: (() -> Unit)? = null, onEdit: ((InstallmentPlanRecord) -> Unit)? = null, onCycle: ((InstallmentDueRow) -> Unit)? = null, onPayment: ((InstallmentDueRow) -> Unit)? = null) {
    val locale = LocalConfiguration.current.locales[0]
    val dates = remember(locale, zone) { DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT).withLocale(locale).withZone(zone) }
    MistiaGlassCard(contentPadding = PaddingValues(0.dp)) { _ ->
        Column {
        if (rows.isEmpty()) Text(stringResource(R.string.planning_planning_no_installments_or_loans_yet),
            Modifier.fillMaxWidth().testTag("installment.empty").padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        else Column {
            rows.forEachIndexed { index, row ->
                val days = ChronoUnit.DAYS.between(reference.atZone(zone).toLocalDate(), row.dueDate.atZone(zone).toLocalDate())
                val color = when {
                    row.status == DueStatus.PAID -> Color(0xFF00BFA5)
                    row.status == DueStatus.SKIPPED -> MaterialTheme.colorScheme.onSurfaceVariant
                    days < 0 -> Color(0xFFF45C7E)
                    days <= 3 -> Color(0xFFF59B3F)
                    else -> Color(0xFF5B7BFF)
                }
                Column(Modifier.fillMaxWidth().testTag("installment.row.${row.plan.id}").padding(horizontal = 15.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(Modifier.weight(1f).then(if (onEdit == null) Modifier else Modifier.testTag("installment.edit.${row.plan.id}").clickable { onEdit(row.plan) }),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        InstallmentIcon(row.plan.iconSymbolName, color)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(row.plan.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text(formatMinorUnits(row.amountMinor, row.plan.currencyCode), Modifier.testTag("installment.amount.${row.plan.id}"),
                                style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        }
                        if (row.status != DueStatus.PENDING) Text(stringResource(if (row.status == DueStatus.PAID) R.string.planning_planning_paid else R.string.planning_duepayment_bill_skipped),
                            Modifier.testTag("installment.status.${row.plan.id}").background(color.copy(alpha = 0.12f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 6.dp),
                            color = color, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                    }
                    if (onPayment != null && row.status != DueStatus.SKIPPED) TextButton(onClick = { onPayment(row) },
                        modifier = Modifier.align(Alignment.End).testTag("installment.pay.${row.plan.id}")) {
                        Text(stringResource(if (row.status == DueStatus.PAID) R.string.planning_duepayment_undo_payment else R.string.planning_duepayment_pay_now))
                    }
                    if (onCycle != null && row.status != DueStatus.PAID) TextButton(
                        onClick = { onCycle(row) }, modifier = Modifier.align(Alignment.End).testTag("installment.skip.${row.plan.id}")) {
                        Text(stringResource(if (row.status == DueStatus.SKIPPED) R.string.planning_duepayment_undo_skip else R.string.planning_duepayment_skip_this_month))
                    }
                    if (row.status == DueStatus.PENDING) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(dates.format(row.dueDate), Modifier.testTag("installment.due.${row.plan.id}"), style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(when {
                            days < 0 -> stringResource(R.string.planning_planning_overdue_by_value_days, (-days).toString())
                            days == 0L -> stringResource(R.string.planning_planning_due_today)
                            else -> stringResource(R.string.planning_planning_value_days_left, days.toString())
                        }, Modifier.testTag("installment.timing.${row.plan.id}"), style = MaterialTheme.typography.labelMedium, color = color)
                    }
                }
                if (index < rows.lastIndex) HorizontalDivider(Modifier.padding(start = 52.dp))
            }
        }
        if (onAdd != null) {
            if (rows.isNotEmpty()) HorizontalDivider(Modifier.padding(start = 52.dp))
            TextButton(onClick = onAdd, modifier = Modifier.fillMaxWidth().testTag("installment.add").padding(vertical = 8.dp)) {
                Text(stringResource(R.string.planning_planning_add_installment_loan))
            }
        }
        }
    }
}
