package vn.com.quyln.mistia.feature.transactions

import android.graphics.BitmapFactory
import android.text.format.Formatter
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.util.Locale
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.designsystem.AmountCalculatorDialog
import vn.com.quyln.mistia.core.designsystem.MistiaGlassCard
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.InvestmentFundUsageConfirmationRequired
import vn.com.quyln.mistia.core.model.InvestmentFundUsageReview
import vn.com.quyln.mistia.core.model.InvestmentFundUsageException
import vn.com.quyln.mistia.core.model.InvestmentFundUsageError
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CurrencyConversionMode
import vn.com.quyln.mistia.core.model.ExchangeRateSnapshot
import vn.com.quyln.mistia.core.model.LedgerTransactionRecord
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.TransactionDebtIntent
import vn.com.quyln.mistia.core.model.TransactionDraft
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionTransferSubtype
import vn.com.quyln.mistia.core.model.TransactionValidationError
import vn.com.quyln.mistia.core.model.TransactionValidationException
import vn.com.quyln.mistia.core.model.WalletKind
import vn.com.quyln.mistia.core.model.matchingExchangeRateSnapshot

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun TransactionEditorSheet(
    ownerId: String,
    transaction: LedgerTransactionRecord?,
    wallets: List<LedgerWalletRecord>,
    categories: List<TransactionCategoryRecord>,
    exchangeRates: List<ExchangeRateSnapshot>,
    now: String,
    primaryCurrencyCode: String = "JPY",
    initialState: TransactionEditorState? = null,
    receiptState: TransactionReceiptEditorState = TransactionReceiptEditorState.none(),
    receiptLoading: Boolean = false,
    receiptLoadFailed: Boolean = false,
    onRemoveReceipt: () -> Unit = {},
    onSaveSuccess: () -> Unit = {},
    onDismiss: () -> Unit,
    onSave: suspend (TransactionDraft) -> Result<LedgerTransactionRecord>,
    saveSessionKey:Any?=null,
    onArchive:(()->Unit)?=null,
) {
    if (transaction != null && transaction.ownerUserId != ownerId) return
    val primary = primaryCurrencyCode.trim().uppercase(Locale.ROOT)
    // The generated creation identity is saved inside the editor, not part of its restoration group key.
    key(ownerId, transaction?.id, initialState?.copy(creationIdentity=null), primary) {
        OwnedTransactionEditorSheet(ownerId, transaction, wallets.filter { it.ownerUserId == ownerId }, categories.filter { it.ownerUserId == ownerId },
            exchangeRates, now, primary, initialState, receiptState, receiptLoading, receiptLoadFailed, onRemoveReceipt, onSaveSuccess, onDismiss, onSave,saveSessionKey,onArchive)
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun OwnedTransactionEditorSheet(
    ownerId: String,
    transaction: LedgerTransactionRecord?,
    wallets: List<LedgerWalletRecord>,
    categories: List<TransactionCategoryRecord>,
    exchangeRates: List<ExchangeRateSnapshot>,
    now: String,
    primaryCurrencyCode: String,
    initialState: TransactionEditorState? = null,
    receiptState: TransactionReceiptEditorState = TransactionReceiptEditorState.none(),
    receiptLoading: Boolean = false,
    receiptLoadFailed: Boolean = false,
    onRemoveReceipt: () -> Unit = {},
    onSaveSuccess: () -> Unit = {},
    onDismiss: () -> Unit,
    onSave: suspend (TransactionDraft) -> Result<LedgerTransactionRecord>,
    saveSessionKey:Any?,
    onArchive:(()->Unit)?,
) {
    var state by rememberSaveable(ownerId, transaction?.id, initialState?.copy(creationIdentity=null), primaryCurrencyCode, stateSaver = TransactionEditorState.scopedSaver(ownerId, transaction?.id, primaryCurrencyCode)) {
        val initial = transaction?.let(TransactionEditorState::edit) ?: initialState ?: TransactionEditorState.new(now)
        val initialCurrency = wallets.firstOrNull { it.id == initial.sourceWalletId && !it.isArchived && it.deletedAt == null }?.currencyCode
        mutableStateOf(if (initial.primaryKind != TransactionPrimaryKind.TRANSFER)
            initial.forReportingCurrency(initialCurrency, primaryCurrencyCode, exchangeRates) else initial)
    }
    var validation by remember { mutableStateOf<TransactionEditorValidation?>(null) }
    var operationError by remember(saveSessionKey) { mutableStateOf<TransactionValidationError?>(null) }
    var genericFailure by remember(saveSessionKey) { mutableStateOf(false) }
    var fundCurrencyError by remember(saveSessionKey) {mutableStateOf(false)}
    var isSaving by remember(saveSessionKey) { mutableStateOf(false) }
    var fundConfirmation by remember(saveSessionKey) {mutableStateOf<Pair<TransactionDraft,InvestmentFundUsageReview>?>(null)}
    var showsDatePicker by remember { mutableStateOf(false) }
    var showsTimePicker by remember { mutableStateOf(false) }
    val parentScope = rememberCoroutineScope()
    val scope=remember(parentScope,saveSessionKey){CoroutineScope(parentScope.coroutineContext+SupervisorJob(parentScope.coroutineContext[Job]))}
    DisposableEffect(scope){onDispose{scope.cancel()}}
    val activeWallets = wallets.filter { !it.isArchived && it.deletedAt == null && it.kind != null }
    val isDebtLend = state.primaryKind == TransactionPrimaryKind.TRANSFER &&
        state.transferSubtype == TransactionTransferSubtype.DEBT &&
        state.debtIntent == TransactionDebtIntent.LEND
    val sourceWallets = activeWallets.filter {
        when (state.primaryKind) {
            TransactionPrimaryKind.EXPENSE -> true
            TransactionPrimaryKind.INCOME -> it.kind != WalletKind.CREDIT_CARD
            TransactionPrimaryKind.TRANSFER -> isDebtLend || it.kind != WalletKind.CREDIT_CARD
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
    val sourceCurrency = sourceWallet?.currencyCode?.trim()?.uppercase(Locale.ROOT)
    val destinationCurrency = destinationWallet?.currencyCode?.trim()?.uppercase(Locale.ROOT)
    val isReporting = state.primaryKind != TransactionPrimaryKind.TRANSFER
    val conversionTarget = if (isReporting) primaryCurrencyCode else destinationCurrency
    val isCrossCurrency = state.primaryKind == TransactionPrimaryKind.TRANSFER && state.transferSubtype == TransactionTransferSubtype.INTERNAL_TRANSFER &&
        sourceWallet != null && destinationWallet != null && sourceCurrency != destinationCurrency
    val showsConversion = isCrossCurrency || (isReporting && sourceWallet != null && sourceCurrency != primaryCurrencyCode)
    val displayedFxState = if (showsConversion) state.withCurrentAppRate(sourceWallet?.currencyCode, conversionTarget, exchangeRates, reporting = isReporting) else state

    val sourceCalculatorAvailable = sourceCurrency in setOf("JPY", "VND")
    val destinationCalculatorAvailable = isCrossCurrency && state.conversionMode == CurrencyConversionMode.MANUAL &&
        destinationCurrency in setOf("JPY", "VND")
    val reportingCalculatorAvailable = showsConversion && isReporting && state.conversionMode == CurrencyConversionMode.MANUAL && primaryCurrencyCode in setOf("JPY", "VND")
    val calculatorScope = listOf(primaryCurrencyCode, ownerId, transaction?.id.orEmpty(), state.primaryKind.name, state.transferSubtype?.name.orEmpty(),
        state.sourceWalletId.orEmpty(), sourceCurrency.orEmpty(), state.destinationWalletId.orEmpty(),
        destinationCurrency.orEmpty(), state.conversionMode?.name.orEmpty()).joinToString(":")
    var calculatorField by rememberSaveable(calculatorScope, stateSaver = listSaver<String?, String>(
        save = { listOf(calculatorScope, it.orEmpty()) },
        restore = { values -> values.takeIf { it.size == 2 && it[0] == calculatorScope }?.get(1)?.takeIf { it == "source" || it == "destination" || it == "reporting" } },
    )) { mutableStateOf<String?>(null) }
    val focus = LocalFocusManager.current
    fun changeAmount(value: String) {
        state = state.withAmount(value, sourceWallet?.currencyCode)
            .withCurrentAppRate(sourceWallet?.currencyCode, conversionTarget, exchangeRates, reporting = isReporting)
    }
    fun submitDraft(draft:TransactionDraft) {
        if(isSaving)return
        fundCurrencyError=false
        isSaving=true
        scope.launch {
            try {
                val saved=try{onSave(draft)}catch(error:kotlinx.coroutines.CancellationException){throw error}catch(error:Throwable){Result.failure(error)}
                currentCoroutineContext().ensureActive()
                saved.fold(onSuccess={onSaveSuccess();onDismiss()},onFailure={error->
                    val review=(error as? InvestmentFundUsageConfirmationRequired)?.review
                    if(review!=null && review.consent.ownerUserId==ownerId && review.consent.transactionId==(draft.id ?: draft.creationIdentity?.id)) {
                        fundConfirmation=draft.copy(investmentConsent=null) to review
                    } else {
                        operationError=(error as? TransactionValidationException)?.reason
                        fundCurrencyError=(error as? InvestmentFundUsageException)?.reason==InvestmentFundUsageError.CURRENCY_MISMATCH
                        genericFailure=operationError==null && !fundCurrencyError
                    }
                })
            } finally {isSaving=false}
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!isSaving) onDismiss() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            TransactionEditorHeading(
                title=stringResource(if(transaction==null)R.string.shared_sync_mistiasynccoordinator_new_transaction else R.string.transactions_transactioneditor_edit_transaction),
                isSaving=isSaving,onDismiss=onDismiss,onSave={
                    val result=state.toDraft(sourceCurrencyCode=sourceWallet?.currencyCode,destinationCurrencyCode=destinationWallet?.currencyCode,
                        rates=exchangeRates,primaryCurrencyCode=primaryCurrencyCode)
                    validation=result.validation;operationError=null;genericFailure=false;fundCurrencyError=false
                    result.draft?.let(::submitDraft)
                },
            )

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
                        if (isDebtLend) {
                            FilterChip(
                                selected = true,
                                onClick = {},
                                enabled = false,
                                label = { Text(stringResource(R.string.shared_corelogic_financeenums_lend)) },
                            )
                        } else {
                            TransactionPrimaryKind.entries.forEach { kind ->
                                FilterChip(
                                    selected = state.primaryKind == kind,
                                    onClick = {
                                        val selected = state.selectKind(kind)
                                        state = if (selected.sourceWalletId != null &&
                                            sourceWalletsForKind(activeWallets, kind).none {
                                                it.id == selected.sourceWalletId
                                            }
                                        ) {
                                            selected.copy(sourceWalletId = null)
                                        } else {
                                            selected
                                        }
                                        val selectedSource = activeWallets.firstOrNull { it.id == state.sourceWalletId }
                                        state = state.withFxPair(selectedSource?.currencyCode, if (kind == TransactionPrimaryKind.TRANSFER) destinationWallet?.currencyCode else primaryCurrencyCode,
                                            exchangeRates, reporting = kind != TransactionPrimaryKind.TRANSFER)
                                        validation = null
                                        operationError = null
                                    },
                                    label = { Text(transactionKindTitle(kind)) },
                                )
                            }
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
                        onValueChange = { changeAmount(it) },
                        modifier = Modifier.fillMaxWidth().testTag("transaction.amount"),
                        trailingIcon = { if (sourceCalculatorAvailable) IconButton(enabled = !isSaving,
                            onClick = { focus.clearFocus(); calculatorField = "source" }, modifier = Modifier.testTag("transaction.amount.calculator")) {
                            Icon(Icons.Filled.Calculate, contentDescription = stringResource(R.string.shared_amount_calculator_open_calculator))
                        } },
                        label = {
                            Text(
                                sourceCurrency?.let {
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
                            if (isDebtLend) {
                                R.string.transactions_transactioneditor_counterparty
                            } else if (state.primaryKind == TransactionPrimaryKind.TRANSFER) {
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
                            if (isDebtLend) {
                                R.string.transactions_transactioneditor_wallet_used
                            } else if (state.primaryKind == TransactionPrimaryKind.TRANSFER) {
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
                                        val selectedDestination = destinationWallet
                                            ?.takeIf { !isDebtLend && it.id != wallet.id }
                                        state = state.withAmountCurrency(sourceWallet?.currencyCode, wallet.currencyCode).copy(
                                            sourceWalletId = wallet.id,
                                            destinationWalletId = selectedDestination?.id,
                                        ).withFxPair(
                                            wallet.currencyCode,
                                            if (isReporting) primaryCurrencyCode else selectedDestination?.currencyCode,
                                            exchangeRates,
                                            reporting = isReporting,
                                        )
                                        validation = null
                                    },
                                    label = { Text(walletPickerTitle(wallet)) },
                                )
                            }
                        }
                    }

                    if (isDebtLend) {
                        OutlinedTextField(
                            value = state.counterpartyName,
                            onValueChange = {
                                state = state.copy(counterpartyName = it)
                                validation = null
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = {
                                Text(stringResource(R.string.transactions_transactioneditor_counterparty_name))
                            },
                            singleLine = true,
                        )
                    } else if (state.primaryKind == TransactionPrimaryKind.TRANSFER) {
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
                                            .withFxPair(
                                                sourceWallet?.currencyCode,
                                                wallet.currencyCode,
                                                exchangeRates,
                                            )
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

            if (showsConversion && sourceWallet != null && conversionTarget != null) {
                MistiaGlassCard { padding ->
                    Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(stringResource(R.string.transactions_transactioneditor_conversion), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val appRateAvailable = matchingExchangeRateSnapshot(sourceWallet.currencyCode, conversionTarget, exchangeRates) != null
                            FilterChip(selected = state.conversionMode == CurrencyConversionMode.APP_RATE, enabled = appRateAvailable,
                                onClick = {
                                    state = state.withFxPair(sourceWallet.currencyCode, conversionTarget, exchangeRates, reporting = isReporting)
                                    validation = null
                                }, label = { Text(stringResource(R.string.transactions_transactioneditor_use_app_rate)) })
                            FilterChip(selected = state.conversionMode != CurrencyConversionMode.APP_RATE,
                                onClick = {
                                    state = state.copy(conversionMode = CurrencyConversionMode.MANUAL,
                                        destinationAmountText = if (isReporting) state.destinationAmountText else "",
                                        reportingAmountText = if (isReporting) "" else state.reportingAmountText,
                                        exchangeRateText = "", exchangeRateProvider = "manual", exchangeRateDate = null)
                                    validation = null
                                }, label = { Text(stringResource(R.string.transactions_transactioneditor_enter_manually)) })
                        }
                        if (state.conversionMode != CurrencyConversionMode.APP_RATE) {
                            val fieldTag = if (isReporting) "transaction.reportingAmount" else "transaction.destinationAmount"
                            val canCalculate = if (isReporting) reportingCalculatorAvailable else destinationCalculatorAvailable
                            OutlinedTextField(value = if (isReporting) displayedFxState.reportingAmountText else displayedFxState.destinationAmountText,
                                onValueChange = { state = if (isReporting) state.withReportingAmount(it, conversionTarget) else state.withDestinationAmount(it, conversionTarget) },
                                modifier = Modifier.fillMaxWidth().testTag(fieldTag),
                                trailingIcon = { if (canCalculate) IconButton(enabled = !isSaving,
                                    onClick = { focus.clearFocus(); calculatorField = if (isReporting) "reporting" else "destination" }, modifier = Modifier.testTag("$fieldTag.calculator")) {
                                    Icon(Icons.Filled.Calculate, contentDescription = stringResource(R.string.shared_amount_calculator_open_calculator))
                                } },
                                label = { Text("${stringResource(if (isReporting) R.string.transactions_transactioneditor_converted_amount else R.string.transactions_transactioneditor_destination_amount)} ($conversionTarget)") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
                        }
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

            if (receiptState.preview != null || receiptLoading || receiptLoadFailed ||
                receiptState.newReceiptRequired
            ) {
                TransactionReceiptEditorSection(
                    state = receiptState,
                    isLoading = receiptLoading,
                    loadFailed = receiptLoadFailed,
                    onRemove = onRemoveReceipt,
                )
            }

            if(transaction!=null && onArchive!=null)TextButton(onClick=onArchive,enabled=!isSaving,
                modifier=Modifier.fillMaxWidth().heightIn(min=48.dp).testTag("transaction.archive")) {
                Text(stringResource(R.string.transactions_transactioneditor_archive_transaction),color=MaterialTheme.colorScheme.error)
            }

            (if(fundCurrencyError)stringResource(R.string.investment_error_fund_usage_currency_mismatch) else
                transactionEditorError(validation, operationError, genericFailure, state.occurredAt))?.let { message ->
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

    fundConfirmation?.let {(draft,review)->
        TransactionInvestmentFundDialog(review,wallets,onDismiss={fundConfirmation=null},onConfirm={
            fundConfirmation=null
            submitDraft(draft.copy(investmentConsent=review.consent))
        })
    }

    val calculatesSource = calculatorField == "source" && sourceCalculatorAvailable
    val calculatesDestination = calculatorField == "destination" && destinationCalculatorAvailable
    val calculatesReporting = calculatorField == "reporting" && reportingCalculatorAvailable
    if (!isSaving && (calculatesSource || calculatesDestination || calculatesReporting)) {
        AmountCalculatorDialog(if (calculatesSource) state.amountText else if (calculatesReporting) state.reportingAmountText else state.destinationAmountText, "$calculatorScope:$calculatorField",
            onCommit = {
                if (calculatesSource) changeAmount(it)
                else if (calculatesReporting) state = state.withReportingAmount(it, primaryCurrencyCode)
                else state = state.withDestinationAmount(it, destinationWallet?.currencyCode)
                validation = null; operationError = null; genericFailure = false
            }, onDismiss = { calculatorField = null })
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

@Composable
private fun TransactionReceiptEditorSection(
    state: TransactionReceiptEditorState,
    isLoading: Boolean,
    loadFailed: Boolean,
    onRemove: () -> Unit,
) {
    val preview = state.preview
    val context = LocalContext.current
    var showsPreview by remember(preview) { mutableStateOf(false) }
    val thumbnail = remember(preview) {
        preview?.thumbnailData?.let { bytes ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
        }
    }
    MistiaGlassCard { padding ->
        Column(
            modifier = Modifier.padding(padding),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.transactions_transactioneditor_image),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            when {
                isLoading -> Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
                    Text(
                        stringResource(R.string.transactions_transactioneditor_receipt_image),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                preview != null && thumbnail != null -> Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Image(
                        bitmap = thumbnail,
                        contentDescription = stringResource(
                            R.string.transactions_transactioneditor_receipt_image,
                        ),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(54.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .clickable { showsPreview = true },
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.transactions_transactioneditor_receipt_image))
                        Text(
                            Formatter.formatShortFileSize(context, preview.byteCount.toLong()),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    TextButton(onClick = onRemove) {
                        Text(
                            stringResource(R.string.transactions_transactioneditor_remove_image),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
                else -> {
                    Text(
                        stringResource(
                            R.string.transactions_transactioneditor_couldn_t_load_the_saved_receipt_image,
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
                    if (state.newReceiptRequired || state.storedReceiptPresent) {
                        TextButton(onClick = onRemove) {
                            Text(
                                stringResource(R.string.transactions_transactioneditor_remove_image),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            }
        }
    }

    if (showsPreview && preview != null) {
        val fullImageBytes = remember(preview) { preview.imageData }
        val fullImageResult by produceState<Result<ImageBitmap>?>(
            initialValue = null,
            key1 = fullImageBytes,
        ) {
            value = withContext(Dispatchers.Default) {
                runCatching {
                    requireNotNull(
                        BitmapFactory.decodeByteArray(fullImageBytes, 0, fullImageBytes.size),
                    ).asImageBitmap()
                }
            }
        }
        AlertDialog(
            onDismissRequest = { showsPreview = false },
            confirmButton = {
                TextButton(onClick = { showsPreview = false }) {
                    Text(stringResource(R.string.common_ok))
                }
            },
            title = { Text(stringResource(R.string.transactions_transactioneditor_receipt_image)) },
            text = {
                val fullImage = fullImageResult?.getOrNull()
                if (fullImage != null) {
                    Image(
                        bitmap = fullImage,
                        contentDescription = stringResource(
                            R.string.transactions_transactioneditor_receipt_image,
                        ),
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxWidth().heightIn(max = 560.dp),
                    )
                } else if (fullImageResult == null) {
                    CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 2.dp)
                } else {
                    Text(
                        stringResource(
                            R.string.transactions_transactioneditor_couldn_t_load_the_saved_receipt_image,
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
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
        validation == TransactionEditorValidation.COUNTERPARTY_REQUIRED ->
            R.string.transactions_transactioneditor_enter_the_counterparty_name
        validation == TransactionEditorValidation.SAME_WALLET ->
            R.string.transactions_transactioneditor_source_and_destination_wallets_must_be_different
        validation == TransactionEditorValidation.INVALID_AMOUNT ->
            R.string.transactions_transactioneditor_enter_an_amount_greater_than
        validation == TransactionEditorValidation.INVALID_REPORTING_AMOUNT ||
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
        operationError == TransactionValidationError.COUNTERPARTY_REQUIRED ->
            R.string.transactions_transactioneditor_enter_the_counterparty_name
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

private fun walletPickerTitle(wallet: LedgerWalletRecord): String =
    "${wallet.name} · ${wallet.currencyCode.trim().uppercase(Locale.ROOT)}"

private fun transactionLocalDateTime(value: String): LocalDateTime =
    runCatching { Instant.parse(value).atZone(ZoneId.systemDefault()).toLocalDateTime() }
        .getOrElse { Instant.now().atZone(ZoneId.systemDefault()).toLocalDateTime() }

private fun transactionInstant(value: LocalDateTime): String =
    value.atZone(ZoneId.systemDefault()).toInstant().toString()
