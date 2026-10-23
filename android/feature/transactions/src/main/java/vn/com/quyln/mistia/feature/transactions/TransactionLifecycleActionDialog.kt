package vn.com.quyln.mistia.feature.transactions

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.designsystem.formatMinorUnits
import vn.com.quyln.mistia.core.model.*

@Composable internal fun TransactionLifecycleActionDialog(owner:UserId,expected:LedgerTransactionRecord,action:TransactionLifecycleAction,
    repository:FinanceRepository,receipts:TransactionReceiptImageRepository,wallets:List<LedgerWalletRecord>,deviceIdProvider:suspend ()->String,
    primaryCurrencyCode:String,onDone:()->Unit,onDismiss:()->Unit) {
    if(expected.ownerUserId!=owner.value)return
    key(owner.value,expected.id,action,repository,receipts,primaryCurrencyCode) {
        OwnedLifecycleActionDialog(owner,expected,action,repository,receipts,wallets,deviceIdProvider,primaryCurrencyCode,onDone,onDismiss)
    }
}

@Composable private fun OwnedLifecycleActionDialog(owner:UserId,expected:LedgerTransactionRecord,action:TransactionLifecycleAction,
    repository:FinanceRepository,receipts:TransactionReceiptImageRepository,wallets:List<LedgerWalletRecord>,deviceIdProvider:suspend ()->String,
    primaryCurrencyCode:String,onDone:()->Unit,onDismiss:()->Unit) {
    val operationAt=remember{java.time.Instant.now().toString()}
    val adjustment=stringResource(R.string.investment_wallet_history_adjustment)
    val request=TransactionInvestmentLifecycleRequest(expected,action,operationAt,primaryCurrencyCode,adjustment,null)
    var review by remember{mutableStateOf<InvestmentFundUsageReview?>(null)}
    var receiptSnapshot by remember{mutableStateOf<TransactionLifecycleReceiptSnapshot?>(null)}
    var saving by remember{mutableStateOf(false)}
    var failure by remember{mutableStateOf<Throwable?>(null)}
    var cleanupPending by remember{mutableStateOf(false)}
    val scope=rememberCoroutineScope()
    fun submit(consent:InvestmentFundUsageConsent?=null) {
        if(saving)return
        saving=true;failure=null
        scope.launch {
            try {
                val device=deviceIdProvider();val now=java.time.Instant.now().toString();val accepted=request.copy(consent=consent)
                if(action==TransactionLifecycleAction.DELETE && receiptSnapshot==null)
                    receiptSnapshot=captureTransactionLifecycleReceiptSnapshot(owner,accepted,device,now,repository,receipts)
                val result=saveTransactionLifecycleWithReceipt(owner,accepted,device,now,repository,receipts,receiptSnapshot)
                currentCoroutineContext().ensureActive()
                result.getOrThrow()
                onDone()
            } catch(cancelled:CancellationException){throw cancelled}
              catch(error:Throwable) {
                  currentCoroutineContext().ensureActive()
                  val requested=(error as? InvestmentFundUsageConfirmationRequired)?.review
                  if(requested!=null && requested.consent.ownerUserId==owner.value && requested.consent.transactionId==expected.id)review=requested
                  else {review=null;failure=error;if(error is TransactionReceiptCleanupRequired)cleanupPending=true}
              } finally {saving=false}
        }
    }
    val funds=review
    if(funds!=null) {
        TransactionInvestmentFundDialog(funds,wallets,onDismiss=onDismiss,onConfirm={submit(funds.consent)},isSaving=saving)
        return
    }
    val actionTitle=when(action) {
        TransactionLifecycleAction.ARCHIVE->R.string.common_archive
        TransactionLifecycleAction.RESTORE->R.string.management_managementarchiveditems_restore
        TransactionLifecycleAction.DELETE->R.string.management_managementarchiveditems_delete_permanently
    }
    val message=when(action) {
        TransactionLifecycleAction.ARCHIVE->R.string.transactions_transaction_lifecycle_archive_message
        TransactionLifecycleAction.RESTORE->R.string.transactions_transaction_lifecycle_restore_message
        TransactionLifecycleAction.DELETE->R.string.transactions_transaction_lifecycle_delete_message
    }
    AlertDialog(onDismissRequest={if(!saving && !cleanupPending)onDismiss()},modifier=Modifier.testTag("transaction.lifecycle.dialog"),title={Text(stringResource(if(cleanupPending)R.string.transactions_transaction_lifecycle_receipt_retained_title else actionTitle),Modifier.testTag("transaction.lifecycle.title"))},
        text={Column(Modifier.heightIn(max=400.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(expected.title,Modifier.testTag("transaction.lifecycle.name"))
            Text(formatMinorUnits(expected.amountMinor,expected.sourceCurrencyCode ?: wallets.firstOrNull{it.id==expected.sourceWalletId}?.currencyCode ?: primaryCurrencyCode),Modifier.testTag("transaction.lifecycle.amount"))
            if(cleanupPending)Text(stringResource(R.string.transactions_transaction_lifecycle_receipt_retained),Modifier.testTag("transaction.lifecycle.cleanup"))
            else Text(stringResource(message),Modifier.testTag("transaction.lifecycle.message"))
            failure?.takeUnless{cleanupPending}?.let{error->
                val reason=when {
                    error is InvestmentFundUsageException && error.reason==InvestmentFundUsageError.CURRENCY_MISMATCH->R.string.investment_error_fund_usage_currency_mismatch
                    error is TransactionValidationException && error.reason==TransactionValidationError.PAID_CREDIT_CARD_STATEMENT->R.string.transactions_transactioneditor_this_transaction_is_part_of_a_paid
                    error is TransactionValidationException && error.reason==TransactionValidationError.INSUFFICIENT_WALLET_BALANCE->R.string.transactions_transactioneditor_insufficient_wallet_balance_to_perform_the_transaction
                    error is IllegalArgumentException->R.string.transactions_transaction_lifecycle_changed
                    else->R.string.transactions_transactioneditor_couldn_t_save_this_transaction_right_now
                }
                Text(stringResource(reason),Modifier.testTag("transaction.lifecycle.error"),color=MaterialTheme.colorScheme.error)
            }
            if(saving)CircularProgressIndicator(Modifier.size(24.dp).testTag("transaction.lifecycle.saving"))
        }},
        confirmButton={TextButton(onClick={submit()},enabled=!saving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.lifecycle.confirm")){Text(stringResource(if(cleanupPending)R.string.planning_installment_retry else actionTitle),Modifier.testTag("transaction.lifecycle.confirm.text"))}},
        dismissButton={if(cleanupPending)TextButton(onClick=onDone,enabled=!saving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.lifecycle.keep.receipt")){Text(stringResource(R.string.transactions_transaction_lifecycle_keep_receipt),Modifier.testTag("transaction.lifecycle.keep.receipt.text"))}
            else TextButton(onClick=onDismiss,enabled=!saving,modifier=Modifier.heightIn(min=48.dp).testTag("transaction.lifecycle.cancel")){Text(stringResource(R.string.common_cancel),Modifier.testTag("transaction.lifecycle.cancel.text"))}})
}
