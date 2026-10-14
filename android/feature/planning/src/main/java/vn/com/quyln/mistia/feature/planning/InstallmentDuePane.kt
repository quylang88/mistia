package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material3.*
import androidx.compose.runtime.*
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

private sealed interface InstallmentLoad {
    data object Loading : InstallmentLoad
    data class Loaded(val rows: List<InstallmentDueRow>) : InstallmentLoad
    data object Failed : InstallmentLoad
}

@Composable
internal fun InstallmentDuePane(owner: UserId, repository: FinanceRepository, month: YearMonth) {
    key(owner.value, repository) { OwnedInstallmentDuePane(owner, repository, month) }
}

@Composable
private fun OwnedInstallmentDuePane(owner: UserId, repository: FinanceRepository, month: YearMonth) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var reference by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) { reference = Instant.now(); delay(60_000) }
        }
    }
    val zone = ZoneId.systemDefault()
    var retry by remember { mutableIntStateOf(0) }
    val load by key(month, zone, retry, lifecycle) {
        produceState<InstallmentLoad>(InstallmentLoad.Loading) {
            value = InstallmentLoad.Loading
            try {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    combine(repository.observeInstallments(owner), repository.observeDueOccurrences(owner)) { plans, occurrences ->
                        installmentDueRows(owner, plans, occurrences, month, zone)
                    }.collect { value = InstallmentLoad.Loaded(it) }
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { value = InstallmentLoad.Failed }
        }
    }
    when (val state = load) {
        InstallmentLoad.Loading -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.testTag("installment.loading"))
        }
        InstallmentLoad.Failed -> Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.planning_installment_load_error), Modifier.testTag("installment.error"))
            TextButton(onClick = { retry++ }) { Text(stringResource(R.string.planning_installment_retry)) }
        }
        is InstallmentLoad.Loaded -> InstallmentDueContent(state.rows, reference, zone)
    }
}

@Composable
internal fun InstallmentDueContent(rows: List<InstallmentDueRow>, reference: Instant, zone: ZoneId) {
    val locale = LocalConfiguration.current.locales[0]
    val dates = remember(locale, zone) { DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT).withLocale(locale).withZone(zone) }
    MistiaGlassCard(contentPadding = PaddingValues(0.dp)) { _ ->
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
                        val icon = when (row.plan.iconSymbolName) {
                            "mistia.plan.loan", "building.columns.fill" -> Icons.Default.AccountBalance
                            "mistia.plan.payment", "calendar.badge.clock" -> Icons.Default.CalendarMonth
                            else -> Icons.Default.CreditCard
                        }
                        Box(Modifier.size(40.dp).background(color.copy(alpha = 0.12f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                            Icon(icon, null, Modifier.size(22.dp), tint = color)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(row.plan.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text(formatMinorUnits(row.amountMinor, row.plan.currencyCode), Modifier.testTag("installment.amount.${row.plan.id}"),
                                style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (row.status != DueStatus.PENDING) Text(stringResource(if (row.status == DueStatus.PAID) R.string.planning_planning_paid else R.string.planning_duepayment_bill_skipped),
                            Modifier.testTag("installment.status.${row.plan.id}").background(color.copy(alpha = 0.12f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 6.dp),
                            color = color, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
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
    }
}
