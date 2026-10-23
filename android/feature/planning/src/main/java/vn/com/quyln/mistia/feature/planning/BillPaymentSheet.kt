package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import vn.com.quyln.mistia.core.designsystem.InvestmentFundUsageDialog
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.CategoryIcon
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun BillPaymentSheet(
    owner:String,row:RecurringBillDueRow,month:YearMonth,wallets:List<LedgerWalletRecord>,undo:Boolean,
    onPay:suspend (BillPaymentRequest)->Result<SavedBillPayment>,onUndo:suspend ()->Result<Unit>,onDismiss:()->Unit,
    category:TransactionCategoryRecord?=null,dataReady:Boolean=true,loadFailed:Boolean=false,targetCurrent:Boolean=true,onRetryLoad:()->Unit={},
    primaryCurrencyCode:String="JPY",operationScopeKey:Any?=null,onInvestmentUndo:(suspend (BillInvestmentUndoRequest)->Result<Unit>)?=null,
) {
    if(row.bill.ownerUserId!=owner)return
    key(owner,row.bill.id,month,undo,operationScopeKey,primaryCurrencyCode) {
        OwnedBillPaymentSheet(owner,row,month,wallets,undo,onPay,onUndo,onDismiss,category,dataReady,loadFailed,targetCurrent,onRetryLoad,primaryCurrencyCode,onInvestmentUndo)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun OwnedBillPaymentSheet(owner:String,row:RecurringBillDueRow,month:YearMonth,wallets:List<LedgerWalletRecord>,undo:Boolean,
    onPay:suspend (BillPaymentRequest)->Result<SavedBillPayment>,onUndo:suspend ()->Result<Unit>,onDismiss:()->Unit,
    category:TransactionCategoryRecord?,dataReady:Boolean,loadFailed:Boolean,targetCurrent:Boolean,onRetryLoad:()->Unit,
    primaryCurrencyCode:String,onInvestmentUndo:(suspend (BillInvestmentUndoRequest)->Result<Unit>)?) {
    val initial=remember(owner,row.bill.id,month) {BillPaymentState.initial(owner,row,month,wallets)}
    var state by rememberSaveable(owner,row.bill.id,month,stateSaver=BillPaymentState.saver(owner,row.bill.id,month.toString())) {mutableStateOf(initial)}
    var busy by remember {mutableStateOf(false)}
    var error by remember {mutableStateOf<Int?>(null)}
    var chooseWallet by remember {mutableStateOf(false)}
    var discard by remember {mutableStateOf(false)}
    var confirmedRequest by remember {mutableStateOf<BillPaymentRequest?>(null)}
    val adjustmentTitle=stringResource(R.string.investment_wallet_history_adjustment)
    val creation by rememberSaveable(owner,row.bill.id,month,stateSaver=listSaver<TransactionCreationIdentity,Any>(
        save={listOf(owner,row.bill.id,month.toString(),it.id,it.createdAt)},restore={values->runCatching {
            if(values.size!=5 || values[0]!=owner || values[1]!=row.bill.id || values[2]!=month.toString())return@runCatching null
            TransactionCreationIdentity(values[3] as String,values[4] as String).also{require(financeRawUuid(it.id)==it.id);java.time.Instant.parse(it.createdAt)}
        }.getOrNull()})) {mutableStateOf(TransactionCreationIdentity(java.util.UUID.randomUUID().toString(),java.time.Instant.now().toString()))}
    val investment=BillInvestmentOperationContext(creation,primaryCurrencyCode,adjustmentTitle)
    var fundReview by remember {mutableStateOf<InvestmentFundUsageReview?>(null)}
    var fundPayment by remember {mutableStateOf<BillPaymentRequest?>(null)}
    var fundUndo by remember {mutableStateOf<BillInvestmentUndoRequest?>(null)}
    var retryPayment by remember {mutableStateOf<BillPaymentRequest?>(null)}
    var retryUndo by remember {mutableStateOf<BillInvestmentUndoRequest?>(null)}
    val scope=rememberCoroutineScope()
    val currentPay by rememberUpdatedState(onPay)
    val currentInvestmentUndo by rememberUpdatedState(onInvestmentUndo)
    val currentUndo by rememberUpdatedState(onUndo)
    val currentDismiss by rememberUpdatedState(onDismiss)
    val changed=!undo && state!=initial
    fun close() {if(!busy) {if(changed) discard=true else onDismiss()}}
    val sheet=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={
        if(it==SheetValue.Hidden && (busy || changed)) {if(!busy) discard=true;false} else true
    })
    val choices=eligibleBillPaymentWallets(owner,row.bill.currencyCode,wallets)
    val selected=choices.firstOrNull {it.id==state.walletId}
    val request=if(dataReady && targetCurrent) runCatching {state.request(row,wallets).copy(investment=investment)}.getOrNull() else null
    fun execute(payment:BillPaymentRequest?,undoRequest:BillInvestmentUndoRequest?=null,resuming:Boolean=false) {
        val knownRetry=resuming && if(undo)undoRequest!=null && undoRequest==retryUndo else payment!=null && payment==retryPayment
        if(busy || !dataReady || (!targetCurrent && !knownRetry) || (resuming && !knownRetry))return
        val frozenUndo=if(undo)undoRequest ?: BillInvestmentUndoRequest(row.bill,month,row.amountMinor,row.linkedTransactionId,investment)else null
        if((!undo && (payment==null || !payment.matchesBillPaymentConsent(if(knownRetry)runCatching{state.request(row,wallets)}.getOrNull()else request) || payment.investment?.creation!=creation)) ||
            (frozenUndo!=null && (!row.bill.matchesBillPaymentSource(frozenUndo.expected) || frozenUndo.expectedAmountMinor!=row.amountMinor || frozenUndo.expectedLinkedTransactionId!=row.linkedTransactionId))) {
            confirmedRequest=null;fundReview=null;fundPayment=null;fundUndo=null;error=R.string.planning_bill_payment_changed;return
        }
        retryPayment=null;retryUndo=null
        busy=true;error=null
        scope.launch {
            fun failed(failure:Throwable) {
                val review=(failure as? InvestmentFundUsageConfirmationRequired)?.review
                if(review!=null && review.consent.ownerUserId==owner && review.consent.transactionId==creation.id) {
                    fundReview=review;fundPayment=payment;fundUndo=frozenUndo
                } else {fundReview=null;fundPayment=null;fundUndo=null;retryPayment=payment;retryUndo=frozenUndo;error=billPaymentErrorResource(failure)}
            }
            try {
                val result=if(undo)currentInvestmentUndo?.invoke(requireNotNull(frozenUndo)) ?: currentUndo() else currentPay(requireNotNull(payment)).map{Unit}
                currentCoroutineContext().ensureActive()
                result.fold(onSuccess={currentDismiss()},onFailure={failed(it)})
            } catch(cancelled:CancellationException){throw cancelled}
              catch(failure:Exception){currentCoroutineContext().ensureActive();failed(failure)}
              finally {busy=false;confirmedRequest=null}
        }
    }
    ModalBottomSheet(onDismissRequest={close()},sheetState=sheet) {
        Column(Modifier.testTag("bill.paymentSheet").fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            Text(stringResource(if(undo) R.string.planning_duepayment_undo_payment else R.string.planning_duepayment_pay_bill),style=MaterialTheme.typography.titleLarge)
            Row(horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                CategoryIcon(category?.iconSymbolName ?: row.bill.iconSymbolName,TransactionCategoryKind.EXPENSE,
                    category?.iconColorHex ?: "#8A8A8E",Modifier.size(44.dp))
                Column {
                    Text(row.bill.name,style=MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.planning_duepayment_payment_cycle_month,month.toString()))
                    val formatter=DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                    Text("${stringResource(R.string.planning_planning_payment_date)}: ${row.paymentStartDate.atZone(ZoneId.systemDefault()).toLocalDate().format(formatter)}",style=MaterialTheme.typography.bodySmall)
                    if(row.hasExplicitDueDate) Text("${stringResource(R.string.planning_planning_deadline)}: ${row.dueDate.atZone(ZoneId.systemDefault()).toLocalDate().format(formatter)}",style=MaterialTheme.typography.bodySmall)
                }
            }
            if(undo) {
                row.amountMinor?.let {Text(if(dataReady && targetCurrent) formatMinorUnits(it,row.bill.currencyCode) else "—")}
                Text(stringResource(R.string.planning_duepayment_undo_payment_message))
            } else {
                if(row.amountMinor==null) {
                    Text(stringResource(R.string.planning_duepayment_this_bill_has_no_default_amount))
                    OutlinedTextField(state.amountText,onValueChange={state=state.copy(amountText=it);error=null},
                        label={Text(stringResource(R.string.planning_duepayment_enter_amount))},suffix={Text(row.bill.currencyCode)},
                        keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),enabled=!busy && dataReady && targetCurrent,
                        modifier=Modifier.fillMaxWidth().testTag("bill.paymentAmount"))
                } else Text(if(dataReady && targetCurrent) formatMinorUnits(requireNotNull(row.amountMinor),row.bill.currencyCode) else "—",Modifier.testTag("bill.knownPaymentAmount"),style=MaterialTheme.typography.headlineSmall)
                TextButton(enabled=!busy && dataReady && targetCurrent,onClick={chooseWallet=true},modifier=Modifier.fillMaxWidth().testTag("bill.paymentWallet")) {
                    Text("${stringResource(R.string.planning_duepayment_payment_wallet)}: ${selected?.name ?: stringResource(R.string.planning_duepayment_choose_wallet)}")
                }
                if(dataReady && choices.isEmpty()) Text(stringResource(R.string.planning_bill_payment_currency_mismatch),color=MaterialTheme.colorScheme.error)
            }
            if(!dataReady && !loadFailed) CircularProgressIndicator(Modifier.testTag("bill.paymentLoading"))
            if(loadFailed) {
                Text(stringResource(R.string.planning_installment_load_error),color=MaterialTheme.colorScheme.error)
                TextButton(enabled=!busy,onClick=onRetryLoad,modifier=Modifier.testTag("bill.paymentRetry")) {Text(stringResource(R.string.planning_installment_retry))}
            }
            if(dataReady && !targetCurrent) Text(stringResource(R.string.planning_duepayment_could_not_find_the_due_item),Modifier.testTag("bill.paymentStale"),color=MaterialTheme.colorScheme.error)
            error?.let {Text(stringResource(it),color=MaterialTheme.colorScheme.error,modifier=Modifier.testTag("bill.paymentError"))}
            if(!targetCurrent && (retryPayment!=null || retryUndo!=null)) TextButton(enabled=!busy && dataReady,
                onClick={execute(retryPayment,retryUndo,true)},modifier=Modifier.fillMaxWidth().testTag("bill.retryPayment")) {
                Text(stringResource(R.string.planning_installment_retry))
            }
            if(busy) CircularProgressIndicator(Modifier.testTag("bill.paymentBusy"))
            Button(enabled=!busy && dataReady && targetCurrent && (if(undo) row.status==DueStatus.PAID else request!=null),
                onClick={if(undo) execute(null) else confirmedRequest=request},modifier=Modifier.fillMaxWidth().testTag("bill.submitPayment")) {
                Text(stringResource(if(undo) R.string.planning_duepayment_undo_payment else R.string.planning_duepayment_pay_now))
            }
            TextButton(enabled=!busy,onClick={close()},modifier=Modifier.testTag("bill.closePayment")) {Text(stringResource(R.string.common_close))}
        }
    }
    fundReview?.let{review->
        val payable=if(undo)fundUndo?.let{row.bill.matchesBillPaymentSource(it.expected) && row.amountMinor==it.expectedAmountMinor && row.linkedTransactionId==it.expectedLinkedTransactionId}==true
            else fundPayment?.matchesBillPaymentConsent(request)==true
        InvestmentFundUsageDialog(review,wallets,onDismiss={fundReview=null;fundPayment=null;fundUndo=null;confirmedRequest=null},onConfirm={
            if(undo)fundUndo?.let{execute(null,it.copy(investment=it.investment.copy(consent=review.consent)))}
            else fundPayment?.let{execute(it.copy(investment=it.investment!!.copy(consent=review.consent)))}
        },isSaving=busy,tagPrefix="bill.funds",canConfirm=dataReady && targetCurrent && payable)
    }
    if(chooseWallet) AlertDialog(onDismissRequest={chooseWallet=false},title={Text(stringResource(R.string.planning_duepayment_choose_wallet))},
        text={Column(Modifier.verticalScroll(rememberScrollState())) {choices.forEach {wallet ->
            TextButton(onClick={state=state.copy(walletId=wallet.id);error=null;chooseWallet=false},modifier=Modifier.testTag("bill.payWallet.${wallet.id}")) {Text("${wallet.name} · ${wallet.currencyCode}")}
        }}},confirmButton={TextButton(onClick={chooseWallet=false}) {Text(stringResource(R.string.common_close))}})
    confirmedRequest?.let {payment ->
        AlertDialog(onDismissRequest={if(!busy) confirmedRequest=null},modifier=Modifier.testTag("bill.paymentConfirmation"),title={Text(stringResource(R.string.planning_duepayment_pay_bill))},
            text={Column {Text(row.bill.name);Text(if(dataReady && targetCurrent) formatMinorUnits(requireNotNull(payment.amountMinorOverride),state.currency) else "—",Modifier.testTag("bill.confirmationAmount"));
                Text(wallets.firstOrNull {it.id==payment.walletId?.value}?.name.orEmpty())}},
            confirmButton={TextButton(enabled=!busy && dataReady && targetCurrent && payment.matchesBillPaymentConsent(request),onClick={execute(payment)},modifier=Modifier.testTag("bill.confirmPayment")) {Text(stringResource(R.string.planning_duepayment_pay_now))}},
            dismissButton={TextButton(enabled=!busy,onClick={confirmedRequest=null}) {Text(stringResource(R.string.common_cancel))}})
    }
    if(discard) AlertDialog(onDismissRequest={discard=false},title={Text(stringResource(R.string.planning_budget_editor_discard_title))},
        confirmButton={TextButton(onClick={discard=false;onDismiss()},modifier=Modifier.testTag("bill.discardPayment")) {Text(stringResource(R.string.planning_budget_editor_discard))}},
        dismissButton={TextButton(onClick={discard=false}) {Text(stringResource(R.string.planning_budget_editor_keep_editing))}})
}

internal fun billPaymentErrorResource(error:Throwable):Int = when(error) {
    is InvestmentFundUsageException -> when(error.reason) {
        InvestmentFundUsageError.CURRENCY_MISMATCH->R.string.investment_error_fund_usage_currency_mismatch
        InvestmentFundUsageError.STALE_CONSENT,InvestmentFundUsageError.EVENT_CONFLICT->R.string.planning_bill_payment_changed
        else->R.string.planning_duepayment_payment_failed
    }
    is BillPaymentException -> when(error.reason) {
        BillPaymentError.WALLET_CURRENCY_MISMATCH -> R.string.planning_bill_payment_currency_mismatch
        BillPaymentError.MISSING_AMOUNT -> R.string.planning_duepayment_enter_amount
        BillPaymentError.SOURCE_CHANGED -> R.string.planning_bill_payment_changed
        BillPaymentError.INVALID_WALLET -> R.string.planning_duepayment_choose_wallet
        BillPaymentError.NOT_FOUND,BillPaymentError.NOT_SCHEDULED,BillPaymentError.CYCLE_NOT_PENDING -> R.string.planning_duepayment_could_not_find_the_due_item
        else -> R.string.planning_duepayment_payment_failed
    }
    is TransactionValidationException -> when(error.reason) {
        TransactionValidationError.INSUFFICIENT_WALLET_BALANCE -> R.string.transactions_transactioneditor_insufficient_wallet_balance_to_perform_the_transaction
        TransactionValidationError.CREDIT_LIMIT_EXCEEDED -> R.string.transactions_transactioneditor_the_amount_exceeds_the_available_credit_on
        TransactionValidationError.PAID_CREDIT_CARD_STATEMENT -> R.string.transactions_transactioneditor_this_transaction_is_part_of_a_paid
        else -> R.string.planning_duepayment_payment_failed
    }
    else -> R.string.planning_duepayment_payment_failed
}
