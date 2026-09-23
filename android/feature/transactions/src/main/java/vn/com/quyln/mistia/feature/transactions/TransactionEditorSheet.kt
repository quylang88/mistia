package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CurrencyConversionMode
import vn.com.quyln.mistia.core.model.LedgerTransactionRecord
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.TransactionDraft
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionValidationError
import vn.com.quyln.mistia.core.model.TransactionValidationException
import vn.com.quyln.mistia.core.model.WalletKind

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TransactionEditorSheet(
    transaction: LedgerTransactionRecord?,
    wallets: List<LedgerWalletRecord>,
    categories: List<TransactionCategoryRecord>,
    now: String,
    onDismiss: () -> Unit,
    onSave: suspend (TransactionDraft) -> Result<LedgerTransactionRecord>,
) {
    var state by rememberSaveable(transaction?.id, stateSaver = TransactionEditorState.Saver) {
        mutableStateOf(transaction?.let(TransactionEditorState::edit) ?: TransactionEditorState.new(now))
    }
    var validation by remember { mutableStateOf<TransactionEditorValidation?>(null) }
    var operationError by remember { mutableStateOf<TransactionValidationError?>(null) }
    var genericFailure by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var showsDatePicker by remember { mutableStateOf(false) }
    var showsTimePicker by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val activeWallets = wallets.filter { !it.isArchived && it.deletedAt == null && it.kind != null }
    val sourceWallets = activeWallets.filter {
        when (state.primaryKind) {
            TransactionPrimaryKind.EXPENSE -> true
            TransactionPrimaryKind.INCOME, TransactionPrimaryKind.TRANSFER -> it.kind != WalletKind.CREDIT_CARD
        }
    }
    val destinationWallets = activeWallets.filter { it.id != state.sourceWalletId }
    val categoryKind = when (state.primaryKind) {
        TransactionPrimaryKind.EXPENSE -> TransactionCategoryKind.EXPENSE
        TransactionPrimaryKind.INCOME -> TransactionCategoryKind.INCOME
        TransactionPrimaryKind.TRANSFER -> null
    }
    val eligibleCategories = categories.filter {
        !it.isArchived && it.deletedAt == null && it.hierarchyRole == CategoryHierarchyRole.CHILD &&
            it.kind == categoryKind
    }
    val sourceWallet = activeWallets.firstOrNull { it.id == state.sourceWalletId }
    val destinationWallet = activeWallets.firstOrNull { it.id == state.destinationWalletId }
    val isCrossCurrency = state.primaryKind == TransactionPrimaryKind.TRANSFER &&
        sourceWallet != null && destinationWallet != null &&
        !sourceWallet.currencyCode.equals(destinationWallet.currencyCode, ignoreCase = true)

    ModalBottomSheet(onDismissRequest = { if (!isSaving) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss, enabled = !isSaving) {
                    Text(stringResource(R.string.common_cancel))
                }
                Text(
                    stringResource(
                        if (transaction == null) R.string.shared_sync_mistiasynccoordinator_new_transaction
                        else R.string.transactions_transactioneditor_edit_transaction
                    ),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Button(
                    enabled = !isSaving,
                    onClick = {
                        val result = state.toDraft(
                            sourceCurrencyCode = sourceWallet?.currencyCode,
                            destinationCurrencyCode = destinationWallet?.currencyCode,
                        )
                        validation = result.validation
                        operationError = null
                        genericFailure = false
                        val draft = result.draft ?: return@Button
                        isSaving = true
                        scope.launch {
                            onSave(draft).fold(
                                onSuccess = { onDismiss() },
                                onFailure = { error ->
                                    isSaving = false
                                    operationError = (error as? TransactionValidationException)?.reason
                                    genericFailure = operationError == null
                                },
                            )
                        }
                    },
                ) { Text(stringResource(R.string.common_save)) }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.transactions_transactioneditor_main_details),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(R.string.transactions_transactioneditor_transaction_type),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        TransactionPrimaryKind.entries.forEach { kind ->
                            FilterChip(
                                selected = state.primaryKind == kind,
                                onClick = {
                                    val selected = state.selectKind(kind)
                                    state = if (selected.sourceWalletId != null &&
                                        sourceWalletsForKind(activeWallets, kind).none { it.id == selected.sourceWalletId }
                                    ) {
                                        selected.copy(sourceWalletId = null)
                                    } else {
                                        selected
                                    }
                                    validation = null
                                    operationError = null
                                },
                                label = { Text(transactionKindTitle(kind)) },
                            )
                        }
                    }
                    OutlinedTextField(
                        value = state.title,
                        onValueChange = { state = state.copy(title = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(transactionTitleLabel(state.primaryKind)) },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.amountText,
                        onValueChange = { state = state.copy(amountText = it) },
                        modifier = Modifier.fillMaxWidth(),
                        label = {
                            Text(
                                sourceWallet?.currencyCode?.let {
                                    "${stringResource(R.string.transactions_transactioneditor_amount)} ($it)"
                                } ?: stringResource(R.string.transactions_transactioneditor_amount)
                            )
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                    )
                    Text(
                        stringResource(R.string.transactions_transactioneditor_date_time),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    val localDateTime = transactionLocalDateTime(state.occurredAt)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { showsDatePicker = true }) {
                            Text(localDateTime.toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)))
                        }
                        OutlinedButton(onClick = { showsTimePicker = true }) {
                            Text(localDateTime.toLocalTime().format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)))
                        }
                    }
                }
            }

            MistiaGlassCard { padding ->
                Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(
                            if (state.primaryKind == TransactionPrimaryKind.TRANSFER) {
                                R.string.transactions_transactioneditor_transfer_flow
                            } else {
                                R.string.transactions_transactioneditor_funding_source
                            }
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(
                            if (state.primaryKind == TransactionPrimaryKind.TRANSFER) {
                                R.string.transactions_transactioneditor_from_wallet
                            } else {
                                R.string.transactions_transactioneditor_wallet
                            }
                        ),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    if (sourceWallets.isEmpty()) {
                        Text(
                            stringResource(R.string.transactions_transactioneditor_you_don_t_have_any_wallets_available),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            sourceWallets.forEach { wallet ->
                                FilterChip(
                                    selected = state.sourceWalletId == wallet.id,
                                    onClick = {
                                        state = state.copy(
                                            sourceWalletId = wallet.id,
                                            destinationWalletId = state.destinationWalletId
                                                ?.takeIf { it != wallet.id },
                                        ).withManualFxIfNeeded(wallet, destinationWallet)
                                        validation = null
                                    },
                                    label = { Text(walletPickerTitle(wallet)) },
                                )
                            }
                        }
                    }

                    if (state.primaryKind == TransactionPrimaryKind.TRANSFER) {
                        Text(
                            stringResource(R.string.transactions_transactioneditor_to_wallet),
                            style = MaterialTheme.typography.labelLarge,
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            destinationWallets.forEach { wallet ->
                                FilterChip(
                                    selected = state.destinationWalletId == wallet.id,
                                    onClick = {
                                        state = state.copy(destinationWalletId = wallet.id)
                                            .withManualFxIfNeeded(sourceWallet, wallet)
                                        validation = null
                                    },
                                    label = { Text(walletPickerTitle(wallet)) },
                                )
                            }
                        }
                    } else {
                        Text(
                            stringResource(R.string.transactions_transactioneditor_category),
                            style = MaterialTheme.typography.labelLarge,
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            eligibleCategories.forEach { category ->
                                FilterChip(
                                    selected = state.categoryId == category.id,
                                    onClick = {
                                        state = state.copy(categoryId = category.id)
                                        validation = null
                                    },
                                    label = { Text(category.name) },
                                )
                            }
                        }
                    }
                }
            }

            if (isCrossCurrency) {
                MistiaGlassCard { padding ->
                    Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            stringResource(R.string.transactions_transactioneditor_conversion),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(
                                selected = state.conversionMode == CurrencyConversionMode.APP_RATE,
                                enabled = state.conversionMode == CurrencyConversionMode.APP_RATE,
                                onClick = {},
                                label = { Text(stringResource(R.string.transactions_transactioneditor_use_app_rate)) },
                            )
                            FilterChip(
                                selected = state.conversionMode != CurrencyConversionMode.APP_RATE,
                                onClick = {
                                    state = state.copy(
                                        conversionMode = CurrencyConversionMode.MANUAL,
                                        exchangeRateProvider = "manual",
                                        exchangeRateDate = null,
                                    )
                                },
                                label = { Text(stringResource(R.string.transactions_transactioneditor_enter_manually)) },
                            )
                        }
                        OutlinedTextField(
                            value = state.destinationAmountText,
                            onValueChange = { state = state.copy(destinationAmountText = it) },
                            modifier = Modifier.fillMaxWidth(),
                            label = {
                                Text(
                                    "${stringResource(R.string.transactions_transactioneditor_destination_amount)} " +
                                        "(${destinationWallet.currencyCode})"
                                )
                            },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true,
                        )
                        OutlinedTextField(
                            value = state.exchangeRateText,
                            onValueChange = { state = state.copy(exchangeRateText = it) },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.settings_currency_rate_value)) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true,
                        )
                    }
                }
            }

            MistiaGlassCard { padding ->
                OutlinedTextField(
                    value = state.note,
                    onValueChange = { state = state.copy(note = it) },
                    modifier = Modifier.padding(padding).fillMaxWidth(),
                    label = { Text(stringResource(R.string.transactions_transactioneditor_notes)) },
                    placeholder = { Text(stringResource(R.string.transactions_transactioneditor_add_a_note_if_needed)) },
                    minLines = 2,
                )
            }

            transactionEditorError(validation, operationError, genericFailure, state.occurredAt)?.let { message ->
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Text(
                stringResource(R.string.transactions_transactioneditor_data_is_saved_directly_on_this_device),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 24.dp),
            )
        }
    }

    if (showsDatePicker) {
        TransactionDatePickerDialog(
            occurredAt = state.occurredAt,
            onDismiss = { showsDatePicker = false },
            onSelected = {
                state = state.copy(occurredAt = it)
                showsDatePicker = false
            },
        )
    }
    if (showsTimePicker) {
        TransactionTimePickerDialog(
            occurredAt = state.occurredAt,
            onDismiss = { showsTimePicker = false },
            onSelected = {
                state = state.copy(occurredAt = it)
                showsTimePicker = false
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TransactionDatePickerDialog(
    occurredAt: String,
    onDismiss: () -> Unit,
    onSelected: (String) -> Unit,
) {
    val current = transactionLocalDateTime(occurredAt)
    val state = rememberDatePickerState(
        initialSelectedDateMillis = current.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    val selected = state.selectedDateMillis?.let {
                        Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    } ?: current.toLocalDate()
                    onSelected(transactionInstant(selected.atTime(current.toLocalTime())))
                },
            ) { Text(stringResource(R.string.common_ok)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
        },
    ) { DatePicker(state) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TransactionTimePickerDialog(
    occurredAt: String,
    onDismiss: () -> Unit,
    onSelected: (String) -> Unit,
) {
    val current = transactionLocalDateTime(occurredAt)
    val state = rememberTimePickerState(current.hour, current.minute, is24Hour = true)
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    onSelected(
                        transactionInstant(
                            current.toLocalDate().atTime(state.hour, state.minute, current.second)
                        )
                    )
                },
            ) { Text(stringResource(R.string.common_ok)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
        },
        text = { TimePicker(state) },
    )
}

@Composable
private fun transactionKindTitle(kind: TransactionPrimaryKind): String = stringResource(
    when (kind) {
        TransactionPrimaryKind.EXPENSE -> R.string.shared_corelogic_financeenums_expense
        TransactionPrimaryKind.INCOME -> R.string.shared_corelogic_financeenums_income
        TransactionPrimaryKind.TRANSFER -> R.string.shared_corelogic_financeenums_transfer
    }
)

@Composable
private fun transactionTitleLabel(kind: TransactionPrimaryKind): String = stringResource(
    when (kind) {
        TransactionPrimaryKind.EXPENSE -> R.string.transactions_transactioneditor_expense_name
        TransactionPrimaryKind.INCOME -> R.string.transactions_transactioneditor_income_name
        TransactionPrimaryKind.TRANSFER -> R.string.transactions_transactioneditor_transaction_name_optional
    }
)

@Composable
private fun transactionEditorError(
    validation: TransactionEditorValidation?,
    operationError: TransactionValidationError?,
    genericFailure: Boolean,
    occurredAt: String,
): String? {
    if (operationError == TransactionValidationError.PAID_CREDIT_CARD_STATEMENT) {
        val statementMonth = transactionLocalDateTime(occurredAt).format(DateTimeFormatter.ofPattern("MM/yyyy"))
        return stringResource(
            R.string.transactions_transactioneditor_the_value_statement_for_this_card_has,
            statementMonth,
        )
    }
    val resource = when {
        validation == TransactionEditorValidation.SOURCE_WALLET_REQUIRED ->
            R.string.transactions_transactioneditor_choose_the_source_wallet
        validation == TransactionEditorValidation.DESTINATION_WALLET_REQUIRED ->
            R.string.transactions_transactioneditor_choose_the_destination_wallet
        validation == TransactionEditorValidation.CATEGORY_REQUIRED ->
            R.string.transactions_transactioneditor_choose_a_category_for_this_transaction
        validation == TransactionEditorValidation.SAME_WALLET ->
            R.string.transactions_transactioneditor_source_and_destination_wallets_must_be_different
        validation == TransactionEditorValidation.INVALID_AMOUNT ->
            R.string.transactions_transactioneditor_enter_an_amount_greater_than
        validation == TransactionEditorValidation.INVALID_DESTINATION_AMOUNT ||
            validation == TransactionEditorValidation.INVALID_EXCHANGE_RATE ->
            R.string.transactions_transactioneditor_enter_the_converted_amount_or_refresh_rates
        operationError == TransactionValidationError.TITLE_REQUIRED ->
            R.string.transactions_transactioneditor_enter_a_transaction_name_before_saving
        operationError == TransactionValidationError.SOURCE_WALLET_REQUIRED ||
            operationError == TransactionValidationError.INVALID_SOURCE_WALLET ->
            R.string.transactions_transactioneditor_choose_the_source_wallet
        operationError == TransactionValidationError.DESTINATION_WALLET_REQUIRED ||
            operationError == TransactionValidationError.INVALID_DESTINATION_WALLET ->
            R.string.transactions_transactioneditor_choose_the_destination_wallet
        operationError == TransactionValidationError.CATEGORY_REQUIRED ||
            operationError == TransactionValidationError.INVALID_CATEGORY ||
            operationError == TransactionValidationError.CATEGORY_KIND_MISMATCH ->
            R.string.transactions_transactioneditor_choose_a_category_for_this_transaction
        operationError == TransactionValidationError.CATEGORY_CHILD_REQUIRED ->
            R.string.transactions_transactioneditor_expenses_and_income_must_use_a_child
        operationError == TransactionValidationError.SAME_WALLET_TRANSFER ->
            R.string.transactions_transactioneditor_source_and_destination_wallets_must_be_different
        operationError == TransactionValidationError.CREDIT_CARD_CANNOT_RECEIVE_INCOME ->
            R.string.transactions_transactioneditor_credit_cards_cannot_receive_income_please_select
        operationError == TransactionValidationError.CREDIT_CARD_CANNOT_SEND_TRANSFER ->
            R.string.transactions_transactioneditor_credit_cards_cannot_send_money_via_transfer
        operationError == TransactionValidationError.CREDIT_LIMIT_EXCEEDED ->
            R.string.transactions_transactioneditor_the_amount_exceeds_the_available_credit_on
        operationError == TransactionValidationError.INSUFFICIENT_WALLET_BALANCE ->
            R.string.transactions_transactioneditor_insufficient_wallet_balance_to_perform_the_transaction
        operationError == TransactionValidationError.INVALID_AMOUNT ->
            R.string.transactions_transactioneditor_enter_an_amount_greater_than
        operationError == TransactionValidationError.CROSS_CURRENCY_DETAILS_REQUIRED ||
            operationError == TransactionValidationError.INVALID_EXCHANGE_RATE ||
            operationError == TransactionValidationError.INVALID_EXCHANGE_RATE_DATE ->
            R.string.transactions_transactioneditor_enter_the_converted_amount_or_refresh_rates
        genericFailure || operationError != null ->
            R.string.transactions_transactioneditor_couldn_t_save_this_transaction_right_now
        else -> null
    }
    return resource?.let { stringResource(it) }
}

private fun sourceWalletsForKind(
    wallets: List<LedgerWalletRecord>,
    kind: TransactionPrimaryKind,
): List<LedgerWalletRecord> = wallets.filter {
    kind == TransactionPrimaryKind.EXPENSE || it.kind != WalletKind.CREDIT_CARD
}

private fun TransactionEditorState.withManualFxIfNeeded(
    source: LedgerWalletRecord?,
    destination: LedgerWalletRecord?,
): TransactionEditorState {
    val isCrossCurrency = source != null && destination != null &&
        !source.currencyCode.equals(destination.currencyCode, ignoreCase = true)
    return if (isCrossCurrency && conversionMode == null) {
        copy(conversionMode = CurrencyConversionMode.MANUAL, exchangeRateProvider = "manual")
    } else {
        this
    }
}

private fun walletPickerTitle(wallet: LedgerWalletRecord): String =
    "${wallet.name} · ${wallet.currencyCode}"

private fun transactionLocalDateTime(value: String): LocalDateTime =
    runCatching { Instant.parse(value).atZone(ZoneId.systemDefault()).toLocalDateTime() }
        .getOrElse { Instant.now().atZone(ZoneId.systemDefault()).toLocalDateTime() }

private fun transactionInstant(value: LocalDateTime): String =
    value.atZone(ZoneId.systemDefault()).toInstant().toString()
