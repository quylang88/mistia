package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import java.util.Locale
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.designsystem.AmountCalculatorDialog
import vn.com.quyln.mistia.core.model.*

@Composable
internal fun InstallmentEditorSheet(
    owner: String, id: String, original: InstallmentPlanRecord?, currency: String, wallets: List<LedgerWalletRecord>,
    dataReady: Boolean = true, loadFailed: Boolean = false, onRetryLoad: () -> Unit = {},
    onSave: suspend (InstallmentDraft) -> Result<InstallmentPlanRecord>,
    onDelete: suspend (InstallmentPlanRecord) -> Result<Unit>, onDismiss: () -> Unit,
) {
    if (original != null && (original.ownerUserId != owner || original.id != id || original.isArchived || original.deletedAt != null)) return
    val boundCurrency = original?.currencyCode ?: currency.trim().uppercase(Locale.ROOT)
    key(owner, id, boundCurrency, original != null) {
        OwnedInstallmentEditorSheet(owner, id, original, boundCurrency, wallets, dataReady, loadFailed, onRetryLoad, onSave, onDelete, onDismiss)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OwnedInstallmentEditorSheet(
    owner: String, id: String, original: InstallmentPlanRecord?, currency: String, wallets: List<LedgerWalletRecord>,
    dataReady: Boolean, loadFailed: Boolean, onRetryLoad: () -> Unit,
    onSave: suspend (InstallmentDraft) -> Result<InstallmentPlanRecord>,
    onDelete: suspend (InstallmentPlanRecord) -> Result<Unit>, onDismiss: () -> Unit,
) {
    val initial = remember(owner, id) { original?.let { InstallmentEditorState.from(owner, it) } ?: InstallmentEditorState.fresh(owner, id, currency) }
    var state by rememberSaveable(owner, id, currency, original != null, stateSaver = InstallmentEditorState.scopedSaver(owner, id, currency, original != null)) { mutableStateOf(initial) }
    var busy by remember { mutableStateOf(false) }
    var calculator by rememberSaveable(owner, id) { mutableStateOf(false) }
    var discard by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()
    val latestSave by rememberUpdatedState(onSave)
    val latestDelete by rememberUpdatedState(onDelete)
    val latestDismiss by rememberUpdatedState(onDismiss)
    val changed = state != initial
    fun close() { if (!busy) { if (changed) discard = true else latestDismiss() } }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = {
        if (it == SheetValue.Hidden && (changed || busy)) { if (!busy) discard = true; false } else true
    })
    ModalBottomSheet(onDismissRequest = { close() }, sheetState = sheet) {
        val focus = LocalFocusManager.current
        Column(Modifier.fillMaxWidth().testTag("installment.editor").verticalScroll(rememberScrollState()).imePadding().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(if (original == null) R.string.planning_planning_kho_n_m_i else R.string.planning_planning_s_a_kho_n),
                    Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = { close() }, enabled = !busy, modifier = Modifier.testTag("installment.close")) { Text(stringResource(R.string.common_close)) }
            }
            TextButton(onClick = { focus.clearFocus(); picker = "icon" }, enabled = !busy, modifier = Modifier.testTag("installment.icon")) {
                InstallmentIcon(state.iconSymbolName); Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.planning_planning_icon_kho_n_tr_g_p_vay))
            }
            OutlinedTextField(state.name, onValueChange = { state = state.copy(name = it); error = null },
                label = { Text(stringResource(R.string.planning_planning_name)) }, singleLine = true, enabled = !busy,
                modifier = Modifier.fillMaxWidth().testTag("installment.name"))
            OutlinedTextField(state.amountText, onValueChange = { state = state.copy(amountText = installmentAmountInput(it)); error = null },
                label = { Text(stringResource(R.string.planning_planning_amount_per_cycle)) }, suffix = { Text(state.currencyCode) },
                trailingIcon = { IconButton(enabled = !busy, onClick = { focus.clearFocus(); calculator = true }, modifier = Modifier.testTag("installment.amount.calculator")) {
                    Icon(Icons.Filled.Calculate, contentDescription = stringResource(R.string.shared_amount_calculator_open_calculator))
                } },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, enabled = !busy,
                modifier = Modifier.fillMaxWidth().testTag("installment.amountInput"))
            state.amountMinor()?.let { amount ->
                Text(stringResource(R.string.planning_installment_editor_amount_preview, formatMinorUnits(amount, state.currencyCode)),
                    Modifier.testTag("installment.amountPreview"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = { focus.clearFocus(); picker = "day" }, enabled = !busy, modifier = Modifier.fillMaxWidth().testTag("installment.day")) {
                Text(stringResource(R.string.planning_planning_due_day), Modifier.weight(1f))
                Text(stringResource(R.string.planning_planning_day_value, state.dueDay.toString()))
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { state = state.copy(frequencyMonths = state.frequencyMonths - 1); error = null },
                    enabled = !busy && state.frequencyMonths in 2..12, modifier = Modifier.testTag("installment.frequencyLess")) {
                    Icon(Icons.Default.Remove, stringResource(R.string.planning_planning_frequency_every_value_month_s, (state.frequencyMonths - 1).toString()))
                }
                TextButton(onClick = { focus.clearFocus(); picker = "frequency" }, enabled = !busy, modifier = Modifier.weight(1f).testTag("installment.frequency")) {
                    Text(stringResource(R.string.planning_planning_frequency_every_value_month_s, state.frequencyMonths.toString()))
                }
                IconButton(onClick = { state = state.copy(frequencyMonths = state.frequencyMonths + 1); error = null },
                    enabled = !busy && state.frequencyMonths in 1..11, modifier = Modifier.testTag("installment.frequencyMore")) {
                    Icon(Icons.Default.Add, stringResource(R.string.planning_planning_frequency_every_value_month_s, (state.frequencyMonths + 1).toString()))
                }
            }
            OutlinedTextField(state.totalCyclesText, onValueChange = { state = state.copy(totalCyclesText = it); error = null },
                label = { Text(stringResource(R.string.planning_planning_total_cycles_optional)) }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), enabled = !busy,
                modifier = Modifier.fillMaxWidth().testTag("installment.cycles"))
            TextButton(onClick = { focus.clearFocus(); picker = "wallet" }, enabled = !busy && dataReady,
                modifier = Modifier.fillMaxWidth().testTag("installment.wallet")) {
                Text(stringResource(R.string.planning_planning_payment_wallet), Modifier.weight(1f))
                if (!dataReady && !loadFailed) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else Text(wallets.firstOrNull { it.ownerUserId == owner && it.deletedAt == null && it.id == state.paymentWalletId }?.let { "${it.name} · ${it.currencyCode}" }
                    ?: stringResource(R.string.planning_planning_choose_wallet))
            }
            if (loadFailed) {
                Text(stringResource(R.string.planning_installment_load_error), color = MaterialTheme.colorScheme.error)
                TextButton(onClick = onRetryLoad, enabled = !busy) { Text(stringResource(R.string.planning_installment_retry)) }
            }
            error?.let { Text(stringResource(it), Modifier.testTag("installment.editorError"), color = MaterialTheme.colorScheme.error) }
            Button(onClick = {
                if (busy) return@Button
                val draft = try { state.toDraft(wallets) } catch (e: Exception) { error = installmentEditorError(e, false); return@Button }
                busy = true; error = null
                scope.launch {
                    try { guardedInstallmentMutation { latestSave(draft) }.fold(onSuccess = { latestDismiss() }, onFailure = { error = installmentEditorError(it, false) }) }
                    finally { busy = false }
                }
            }, enabled = !busy && dataReady, modifier = Modifier.fillMaxWidth().testTag("installment.save")) {
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.common_save))
            }
            if (original != null) TextButton(onClick = { if (!busy) deleting = true }, enabled = !busy,
                modifier = Modifier.fillMaxWidth().testTag("installment.delete")) {
                Text(stringResource(R.string.planning_planning_delete_this_item2), color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(16.dp))
        }
    }
    if (calculator) AmountCalculatorDialog(state.amountText, "$owner:$id:${state.currencyCode}",
        onCommit = { state = state.copy(amountText = installmentAmountInput(it)); error = null }, onDismiss = { calculator = false })
    if (discard) AlertDialog(onDismissRequest = { discard = false },
        title = { Text(stringResource(R.string.planning_budget_editor_discard_title)) },
        text = { Text(stringResource(R.string.planning_installment_editor_discard_message)) },
        confirmButton = { TextButton(onClick = { discard = false; latestDismiss() }, modifier = Modifier.testTag("installment.discard")) { Text(stringResource(R.string.planning_budget_editor_discard)) } },
        dismissButton = { TextButton(onClick = { discard = false }, modifier = Modifier.testTag("installment.keepEditing")) { Text(stringResource(R.string.planning_budget_editor_keep_editing)) } })
    if (deleting && original != null) AlertDialog(onDismissRequest = { deleting = false },
        title = { Text(stringResource(R.string.planning_planning_delete_this_item)) },
        text = { Text(stringResource(R.string.planning_installment_editor_delete_message)) },
        confirmButton = { TextButton(onClick = {
            if (busy) return@TextButton
            deleting = false; busy = true; error = null
            scope.launch {
                try { guardedInstallmentMutation { latestDelete(requireNotNull(state.baseline())) }.fold(onSuccess = { latestDismiss() }, onFailure = { error = installmentEditorError(it, true) }) }
                finally { busy = false }
            }
        }, modifier = Modifier.testTag("installment.confirmDelete")) { Text(stringResource(R.string.common_delete)) } },
        dismissButton = { TextButton(onClick = { deleting = false }) { Text(stringResource(R.string.common_cancel)) } })
    if (picker != null) AlertDialog(onDismissRequest = { picker = null }, title = { Text(when (picker) {
        "wallet" -> stringResource(R.string.planning_planning_payment_wallet)
        "icon" -> stringResource(R.string.planning_planning_icon_kho_n_tr_g_p_vay)
        "day" -> stringResource(R.string.planning_planning_due_day)
        else -> stringResource(R.string.planning_planning_frequency_every_value_month_s, state.frequencyMonths.toString())
    }) },
        text = { Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
            when (picker) {
                "wallet" -> {
                    TextButton(onClick = { state = state.copy(paymentWalletId = null); picker = null; error = null }) { Text(stringResource(R.string.planning_planning_choose_wallet)) }
                    eligibleInstallmentWallets(owner, original?.paymentWalletId, wallets, state.currencyCode).forEach { wallet ->
                        PickerRow(wallet.id == state.paymentWalletId, "${wallet.name} · ${wallet.currencyCode}", "installment.pickWallet.${wallet.id}") {
                            state = state.copy(paymentWalletId = wallet.id); picker = null; error = null
                        }
                    }
                }
                "icon" -> installmentIcons.forEach { (token, label) ->
                    Row(Modifier.fillMaxWidth().clickable { state = state.copy(iconSymbolName = token); picker = null; error = null }
                        .testTag("installment.pickIcon.$token").padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(state.iconSymbolName == token, onClick = null); InstallmentIcon(token); Spacer(Modifier.width(8.dp)); Text(stringResource(label))
                    }
                }
                "day" -> (1..31).forEach { day -> PickerRow(day == state.dueDay, stringResource(R.string.planning_planning_day_value, day.toString()), "installment.pickDay.$day") {
                    state = state.copy(dueDay = day); picker = null; error = null
                } }
                else -> (1..12).forEach { frequency -> PickerRow(frequency == state.frequencyMonths,
                    stringResource(R.string.planning_planning_frequency_every_value_month_s, frequency.toString()), "installment.pickFrequency.$frequency") {
                    state = state.copy(frequencyMonths = frequency); picker = null; error = null
                } }
            }
        } }, confirmButton = { TextButton(onClick = { picker = null }) { Text(stringResource(R.string.common_close)) } })
}

@Composable private fun PickerRow(selected: Boolean, text: String, tag: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).testTag(tag).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected, onClick = null); Text(text)
    }
}

@Composable internal fun InstallmentIcon(token: String, color: Color? = null) {
    val tint = color ?: when (token) {
        "mistia.plan.loan" -> Color(0xFF5B7BFF)
        "mistia.plan.card_bill" -> Color(0xFFA76BFF)
        "mistia.plan.payment" -> Color(0xFF2DAA9E)
        else -> Color(0xFF7C85A3)
    }
    val icon = when (token) { "mistia.plan.loan", "building.columns.fill" -> Icons.Default.AccountBalance
        "mistia.plan.payment", "calendar.badge.clock" -> Icons.Default.CalendarMonth
        else -> Icons.Default.CreditCard }
    Box(Modifier.size(40.dp).background(tint.copy(alpha = 0.12f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(22.dp), tint = tint)
    }
}

private val installmentIcons = listOf("mistia.plan.installment" to R.string.core_ui_mistiafinanceicons_installment,
    "mistia.plan.loan" to R.string.core_ui_mistiafinanceicons_loan, "mistia.plan.card_bill" to R.string.core_ui_mistiafinanceicons_card_debt,
    "mistia.plan.payment" to R.string.core_ui_mistiafinanceicons_scheduled_payment)

private fun installmentEditorError(error: Throwable, deleting: Boolean): Int = when ((error as? InstallmentValidationException)?.reason) {
    InstallmentValidationError.NAME_REQUIRED -> R.string.planning_planning_enter_a_name_before_saving
    InstallmentValidationError.INVALID_AMOUNT -> R.string.planning_installment_editor_invalid_amount
    InstallmentValidationError.INVALID_TOTAL_CYCLES -> R.string.planning_installment_editor_invalid_total_cycles
    InstallmentValidationError.INVALID_DAYS, InstallmentValidationError.INVALID_FREQUENCY -> R.string.planning_installment_editor_invalid_schedule
    InstallmentValidationError.WALLET_CURRENCY_MISMATCH -> R.string.planning_installment_payment_currency_mismatch
    InstallmentValidationError.INVALID_CURRENCY -> R.string.planning_installment_editor_invalid_currency
    InstallmentValidationError.INVALID_WALLET -> R.string.planning_planning_choose_a_payment_wallet_for_this_item
    InstallmentValidationError.NOT_FOUND, InstallmentValidationError.INVALID_IDENTITY -> R.string.planning_installment_editor_not_found
    InstallmentValidationError.STALE_RECORD -> R.string.planning_installment_editor_stale_record
    else -> if (deleting) R.string.planning_planning_couldn_t_delete_this_item_right_now else R.string.planning_planning_couldn_t_save_this_item_right_now
}
