package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun InstallmentDueWorkflow(owner: UserId, repository: FinanceRepository, rows: List<InstallmentDueRow>, month: YearMonth,
    reference: Instant, zone: ZoneId, deviceIdProvider: () -> String, now: () -> Instant,
    onAdd: () -> Unit, onEdit: (InstallmentPlanRecord) -> Unit, onPayment: ((InstallmentDueRow) -> Unit)? = null) {
    // Replacing a month/zone/owner cancels its dialog callback, without discarding the separate metadata editor.
    key(owner.value, month, zone) { OwnedInstallmentDueWorkflow(owner, repository, rows, month, reference, zone, deviceIdProvider, now, onAdd, onEdit, onPayment) }
}

@Composable
private fun OwnedInstallmentDueWorkflow(owner: UserId, repository: FinanceRepository, rows: List<InstallmentDueRow>, month: YearMonth,
    reference: Instant, zone: ZoneId, deviceIdProvider: () -> String, now: () -> Instant,
    onAdd: () -> Unit, onEdit: (InstallmentPlanRecord) -> Unit, onPayment: ((InstallmentDueRow) -> Unit)? = null) {
    var target by remember { mutableStateOf<InstallmentDueRow?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()
    val currentRepository by rememberUpdatedState(repository)
    val currentDevice by rememberUpdatedState(deviceIdProvider)
    val currentTime by rememberUpdatedState(now)
    InstallmentDueContent(rows, reference, zone, onAdd, onEdit, onCycle = { target = it; error = null }, onPayment = onPayment)
    target?.let { selected ->
        val undo = selected.status == DueStatus.SKIPPED
        val title = if (undo) R.string.planning_duepayment_undo_skip else R.string.planning_duepayment_skip_this_month
        val locale = LocalConfiguration.current.locales[0]
        val monthTitle = month.format(DateTimeFormatter.ofPattern("LLLL yyyy", locale))
        AlertDialog(onDismissRequest = { if (!busy) target = null },
            title = { Text(stringResource(title)) },
            text = { Column {
                Text("${selected.plan.name} · $monthTitle")
                Text(stringResource(if (undo) R.string.planning_installment_cycle_undo_message else R.string.planning_installment_cycle_skip_message))
                error?.let { Text(stringResource(it), Modifier.testTag("installment.cycleError"), color = MaterialTheme.colorScheme.error) }
            } },
            confirmButton = { TextButton(enabled = !busy, modifier = Modifier.testTag("installment.confirmCycle"), onClick = {
                if (busy) return@TextButton
                busy = true; error = null
                scope.launch {
                    try {
                        guardedInstallmentMutation {
                            if (undo) currentRepository.undoInstallmentSkip(owner, selected.plan, month, currentDevice(), currentTime().toString())
                            else currentRepository.skipInstallment(owner, selected.plan, month, currentDevice(), currentTime().toString()).map { Unit }
                        }.fold(onSuccess = { target = null }, onFailure = { error = installmentCycleError(it) })
                    } finally { busy = false }
                }
            }) {
                if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(stringResource(title))
            } },
            dismissButton = { TextButton(enabled = !busy, onClick = { target = null }, modifier = Modifier.testTag("installment.cancelCycle")) {
                Text(stringResource(R.string.common_cancel))
            } })
    }
}

private fun installmentCycleError(error: Throwable) = when ((error as? InstallmentValidationException)?.reason) {
    InstallmentValidationError.SETTLED_CYCLE -> R.string.planning_installment_cycle_settled
    InstallmentValidationError.NOT_SCHEDULED -> R.string.planning_installment_cycle_not_scheduled
    InstallmentValidationError.STALE_RECORD -> R.string.planning_installment_cycle_stale
    InstallmentValidationError.NOT_FOUND, InstallmentValidationError.INVALID_IDENTITY -> R.string.planning_duepayment_could_not_find_the_due_item
    else -> R.string.planning_installment_cycle_failed
}
