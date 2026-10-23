package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.designsystem.InvestmentFundUsageDialog
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun InstallmentPaymentSheet(owner: String, row: InstallmentDueRow, wallets: List<LedgerWalletRecord>, dataReady: Boolean = true,
    loadFailed: Boolean = false, targetCurrent: Boolean = true, onRetryLoad: () -> Unit = {}, onPay: suspend (InstallmentPaymentRequest) -> Result<SavedInstallmentPayment>,
    onUndo: suspend () -> Result<Unit>, onDismiss: () -> Unit,
    primaryCurrencyCode:String="JPY",operationScopeKey:Any?=null,onInvestmentUndo:(suspend (InstallmentInvestmentUndoRequest)->Result<Unit>)?=null,operationNow:()->java.time.Instant=java.time.Instant::now) {
    if(row.plan.ownerUserId!=owner)return
    key(owner,row.plan.id,row.month,row.status==DueStatus.PAID,primaryCurrencyCode) {
        OwnedInstallmentPaymentSheet(owner,row,wallets,dataReady,loadFailed,targetCurrent,onRetryLoad,onPay,onUndo,onDismiss,
            primaryCurrencyCode,onInvestmentUndo,operationScopeKey,operationNow)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun OwnedInstallmentPaymentSheet(owner:String,row:InstallmentDueRow,wallets:List<LedgerWalletRecord>,dataReady:Boolean,
    loadFailed:Boolean,targetCurrent:Boolean,onRetryLoad:()->Unit,onPay:suspend (InstallmentPaymentRequest)->Result<SavedInstallmentPayment>,
    onUndo:suspend ()->Result<Unit>,onDismiss:()->Unit,primaryCurrencyCode:String,onInvestmentUndo:(suspend (InstallmentInvestmentUndoRequest)->Result<Unit>)?,operationScopeKey:Any?,operationNow:()->java.time.Instant) {
    val undo = row.status == DueStatus.PAID
    val locale = LocalConfiguration.current.locales[0]
    val cycleMonth = row.month.format(DateTimeFormatter.ofPattern("LLLL yyyy", locale))
    val initial = remember(owner, row.plan.id, row.month) { InstallmentPaymentState.initial(owner, row, wallets) }
    var state by rememberSaveable(owner, row.plan.id, row.month, stateSaver = InstallmentPaymentState.saver(owner, row.plan.id, row.month.toString())) { mutableStateOf(initial) }
    var busy by remember(operationScopeKey) { mutableStateOf(false) }
    var error by remember(operationScopeKey) { mutableStateOf<Int?>(null) }
    var choosing by remember(operationScopeKey) { mutableStateOf(false) }
    var discard by remember(operationScopeKey) { mutableStateOf(false) }
    var confirmation by remember(operationScopeKey) { mutableStateOf<InstallmentPaymentRequest?>(null) }
    val adjustmentTitle=stringResource(R.string.investment_wallet_history_adjustment)
    val creation by rememberSaveable(owner,row.plan.id,row.month,stateSaver=listSaver<TransactionCreationIdentity,Any>(
        save={listOf(owner,row.plan.id,row.month.toString(),it.id,it.createdAt)},restore={values->runCatching {
            if(values.size!=5 || values[0]!=owner || values[1]!=row.plan.id || values[2]!=row.month.toString())return@runCatching null
            TransactionCreationIdentity(values[3] as String,values[4] as String).also{require(financeRawUuid(it.id)==it.id);java.time.Instant.parse(it.createdAt)}
        }.getOrNull()})) {mutableStateOf(TransactionCreationIdentity(java.util.UUID.randomUUID().toString(),operationNow().toString()))}
    val investment=BillInvestmentOperationContext(creation,primaryCurrencyCode,adjustmentTitle)
    var fundReview by remember(operationScopeKey){mutableStateOf<InvestmentFundUsageReview?>(null)}
    var fundPayment by remember(operationScopeKey){mutableStateOf<InstallmentPaymentRequest?>(null)}
    var fundUndo by remember(operationScopeKey){mutableStateOf<InstallmentInvestmentUndoRequest?>(null)}
    var retryPayment by remember(operationScopeKey) {mutableStateOf<InstallmentPaymentRequest?>(null)}
    var retryUndo by remember(operationScopeKey) {mutableStateOf<InstallmentInvestmentUndoRequest?>(null)}
    val currentInvestmentUndo by rememberUpdatedState(onInvestmentUndo)
    val scope = key(operationScopeKey){rememberCoroutineScope()}
    val currentPay by rememberUpdatedState(onPay)
    val currentUndo by rememberUpdatedState(onUndo)
    val currentDismiss by rememberUpdatedState(onDismiss)
    val choices = eligibleInstallmentPaymentWallets(owner, row.plan.currencyCode, wallets)
    val selected = choices.firstOrNull { it.id == state.walletId }
    val request = if (dataReady && targetCurrent && !undo) runCatching { state.request(row, wallets).copy(investment=investment) }.getOrNull() else null
    val changed = !undo && state.changed
    fun close() { if (!busy) { if (changed) discard = true else currentDismiss() } }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = {
        if (it == SheetValue.Hidden && (busy || changed)) { if (!busy) discard = true; false } else true
    })
    fun execute(payment:InstallmentPaymentRequest?,undoRequest:InstallmentInvestmentUndoRequest?=null,resuming:Boolean=false) {
        val knownRetry=resuming && if(undo)undoRequest!=null && undoRequest==retryUndo else payment!=null && payment==retryPayment
        if(busy || !dataReady || (!targetCurrent && !knownRetry) || (resuming && !knownRetry))return
        val frozenUndo=if(undo)undoRequest ?: InstallmentInvestmentUndoRequest(row.plan,row.month,row.amountMinor,row.linkedTransactionId,investment)else null
        if((!undo && (payment==null || !payment.matchesInstallmentPaymentConsent(if(knownRetry)runCatching{state.request(row,wallets)}.getOrNull()else request) || payment.investment?.creation!=creation)) ||
            (frozenUndo!=null && (!row.plan.matchesInstallmentPaymentSource(frozenUndo.expected) || frozenUndo.expectedAmountMinor!=row.amountMinor || frozenUndo.expectedLinkedTransactionId!=row.linkedTransactionId))) {
            error=R.string.planning_installment_cycle_stale;confirmation=null;fundReview=null;fundPayment=null;fundUndo=null;return
        }
        retryPayment=null;retryUndo=null
        busy=true;error=null
        scope.launch {
            fun failed(failure:Throwable) {
                val review=(failure as? InvestmentFundUsageConfirmationRequired)?.review
                if(review!=null && review.consent.ownerUserId==owner && review.consent.transactionId==creation.id) {
                    fundReview=review;fundPayment=payment;fundUndo=frozenUndo
                }else{fundReview=null;fundPayment=null;fundUndo=null;retryPayment=payment;retryUndo=frozenUndo;error=installmentPaymentError(failure)}
            }
            try {
                val result=if(undo)currentInvestmentUndo?.invoke(requireNotNull(frozenUndo)) ?: currentUndo() else currentPay(requireNotNull(payment)).map{Unit}
                currentCoroutineContext().ensureActive()
                (result.exceptionOrNull() as? CancellationException)?.let{throw it}
                result.fold(onSuccess={currentDismiss()},onFailure={failed(it)})
            }catch(cancelled:CancellationException){throw cancelled}
             catch(failure:Exception){currentCoroutineContext().ensureActive();failed(failure)}
             finally{busy=false;confirmation=null}
        }
    }
    ModalBottomSheet(onDismissRequest = { close() }, sheetState = sheet) {
        Column(Modifier.fillMaxWidth().testTag("installment.paymentSheet").verticalScroll(rememberScrollState()).imePadding().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(if (undo) R.string.planning_duepayment_undo_payment else R.string.planning_duepayment_pay_now), style = MaterialTheme.typography.titleLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                InstallmentIcon(row.plan.iconSymbolName)
                Column {
                    Text(row.plan.name, style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.planning_duepayment_payment_cycle_month, cycleMonth))
                }
            }
            if (undo) {
                Text(formatMinorUnits(row.amountMinor, row.plan.currencyCode), Modifier.testTag("installment.undoAmount"))
                Text(stringResource(R.string.planning_duepayment_undo_payment_message))
            } else {
                Text(if(dataReady && targetCurrent) formatMinorUnits(row.amountMinor, row.plan.currencyCode) else "—", Modifier.testTag("installment.paymentAmount"),
                    style = MaterialTheme.typography.headlineSmall)
                TextButton(enabled = !busy && dataReady, onClick = { choosing = true }, modifier = Modifier.fillMaxWidth().testTag("installment.paymentWallet")) {
                    Text("${stringResource(R.string.planning_duepayment_payment_wallet)}: ${selected?.let { "${it.name} · ${it.currencyCode}" } ?: stringResource(R.string.planning_duepayment_choose_wallet)}")
                }
                Text(stringResource(R.string.planning_installment_payment_currency_mismatch), style = MaterialTheme.typography.bodySmall,
                    color = if (choices.isEmpty() && dataReady) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!dataReady && !loadFailed) CircularProgressIndicator(Modifier.testTag("installment.paymentLoading"))
            if (loadFailed) {
                Text(stringResource(R.string.planning_installment_load_error), color = MaterialTheme.colorScheme.error)
                TextButton(enabled = !busy, onClick = onRetryLoad) { Text(stringResource(R.string.planning_installment_retry)) }
            }
            if (dataReady && !targetCurrent) Text(stringResource(R.string.planning_installment_cycle_stale), Modifier.testTag("installment.paymentStale"), color = MaterialTheme.colorScheme.error)
            error?.let { Text(stringResource(it), Modifier.testTag("installment.paymentError"), color = MaterialTheme.colorScheme.error) }
            if(!targetCurrent && (retryPayment!=null || retryUndo!=null)) TextButton(enabled=!busy && dataReady,
                onClick={execute(retryPayment,retryUndo,true)},modifier=Modifier.fillMaxWidth().testTag("installment.retryPayment")) {
                Text(stringResource(R.string.planning_installment_retry))
            }
            if (busy) CircularProgressIndicator(Modifier.testTag("installment.paymentBusy"))
            Button(enabled = !busy && dataReady && targetCurrent && (undo || request != null), onClick = { if (undo) execute(null) else confirmation = request },
                modifier = Modifier.fillMaxWidth().testTag("installment.submitPayment")) {
                Text(stringResource(if (undo) R.string.planning_duepayment_undo_payment else R.string.planning_duepayment_pay_now))
            }
            TextButton(enabled = !busy, onClick = { close() }, modifier = Modifier.testTag("installment.closePayment")) { Text(stringResource(R.string.common_close)) }
        }
    }
    fundReview?.let{review->
        val payable=if(undo)fundUndo?.let{row.plan.matchesInstallmentPaymentSource(it.expected) && row.amountMinor==it.expectedAmountMinor && row.linkedTransactionId==it.expectedLinkedTransactionId}==true
            else fundPayment?.matchesInstallmentPaymentConsent(request)==true
        InvestmentFundUsageDialog(review,wallets,onDismiss={fundReview=null;fundPayment=null;fundUndo=null;confirmation=null},onConfirm={
            if(undo)fundUndo?.let{execute(null,it.copy(investment=it.investment.copy(consent=review.consent)))}
            else fundPayment?.let{execute(it.copy(investment=it.investment!!.copy(consent=review.consent)))}
        },isSaving=busy,tagPrefix="installment.funds",canConfirm=dataReady && targetCurrent && payable)
    }
    if (choosing) AlertDialog(onDismissRequest = { choosing = false }, title = { Text(stringResource(R.string.planning_duepayment_choose_wallet)) },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) { choices.forEach { wallet ->
            TextButton(onClick = { state = state.copy(walletId = wallet.id); error = null; choosing = false }, modifier = Modifier.testTag("installment.payWallet.${wallet.id}")) {
                Text("${wallet.name} · ${wallet.currencyCode}")
            }
        } } }, confirmButton = { TextButton(onClick = { choosing = false }) { Text(stringResource(R.string.common_close)) } })
    confirmation?.let { frozen ->
        AlertDialog(onDismissRequest = { if (!busy) confirmation = null }, modifier=Modifier.testTag("installment.paymentConfirmation"),title = { Text(stringResource(R.string.planning_duepayment_pay_now)) },
            text = { Column { Text(row.plan.name); Text(if(dataReady && targetCurrent) formatMinorUnits(requireNotNull(frozen.amountMinorOverride), row.plan.currencyCode) else "—",Modifier.testTag("installment.confirmationAmount")); Text(selected?.name.orEmpty()) } },
            confirmButton = { TextButton(enabled = !busy && dataReady && targetCurrent && frozen.matchesInstallmentPaymentConsent(request), onClick = { execute(frozen) }, modifier = Modifier.testTag("installment.confirmPayment")) {
                Text(stringResource(R.string.planning_duepayment_pay_now))
            } }, dismissButton = { TextButton(enabled = !busy, onClick = { confirmation = null }) { Text(stringResource(R.string.common_cancel)) } })
    }
    if (discard) AlertDialog(onDismissRequest = { discard = false }, title = { Text(stringResource(R.string.planning_budget_editor_discard_title)) },
        confirmButton = { TextButton(onClick = { discard = false; currentDismiss() }, modifier = Modifier.testTag("installment.discardPayment")) { Text(stringResource(R.string.planning_budget_editor_discard)) } },
        dismissButton = { TextButton(onClick = { discard = false }, modifier = Modifier.testTag("installment.keepPayment")) { Text(stringResource(R.string.planning_budget_editor_keep_editing)) } })
}

private fun installmentPaymentError(error: Throwable): Int = when ((error as? BillPaymentException)?.reason) {
    BillPaymentError.WALLET_CURRENCY_MISMATCH -> R.string.planning_installment_payment_currency_mismatch
    BillPaymentError.SOURCE_CHANGED -> R.string.planning_installment_cycle_stale
    BillPaymentError.MISSING_AMOUNT -> R.string.planning_installment_editor_invalid_amount
    else -> billPaymentErrorResource(error)
}
