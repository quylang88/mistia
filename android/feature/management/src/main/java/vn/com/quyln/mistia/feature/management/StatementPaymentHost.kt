package vn.com.quyln.mistia.feature.management

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import vn.com.quyln.mistia.core.designsystem.InvestmentFundUsageDialog
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

private data class StatementPaymentIntent(val request:CreditCardStatementPaymentRequest,val wallet:LedgerWalletRecord?,val device:String)

/** Consent/request state deliberately is not saveable or shared across subject/month/repository. */
@Composable internal fun StatementPaymentHost(owner:String,statement:CreditCardStatement?,wallets:List<LedgerWalletRecord>,
    primaryCurrencyCode:String,deviceIdProvider:()->String,now:()->Instant,
    onPay:suspend (CreditCardStatementPaymentRequest,String)->Result<SavedCreditCardStatementPayment>,operationScopeKey:Any?,
    content:@Composable ((CreditCardStatement)->Unit,Boolean)->Unit) {
    key(owner,statement?.account?.wallet?.id,statement?.month,primaryCurrencyCode,operationScopeKey) {
        OwnedStatementPaymentHost(owner,statement,wallets,primaryCurrencyCode,deviceIdProvider,now,onPay,content)
    }
}

@Composable private fun OwnedStatementPaymentHost(owner:String,statement:CreditCardStatement?,wallets:List<LedgerWalletRecord>,
    primaryCurrencyCode:String,deviceIdProvider:()->String,now:()->Instant,
    onPay:suspend (CreditCardStatementPaymentRequest,String)->Result<SavedCreditCardStatementPayment>,
    content:@Composable ((CreditCardStatement)->Unit,Boolean)->Unit) {
    var busy by remember {mutableStateOf(false)}
    var review by remember {mutableStateOf<InvestmentFundUsageReview?>(null)}
    var intent by remember {mutableStateOf<StatementPaymentIntent?>(null)}
    var error by remember {mutableStateOf<Int?>(null)}
    var success by remember {mutableStateOf(false)}
    val scope=rememberCoroutineScope()
    val currentStatement by rememberUpdatedState(statement)
    val currentWallets by rememberUpdatedState(wallets)
    val currentPay by rememberUpdatedState(onPay)
    val adjustmentTitle=stringResource(R.string.investment_wallet_history_adjustment)
    val title=statement?.account?.wallet?.name?.let{stringResource(R.string.management_managementcreditcardstatement_payment_title,it)}.orEmpty()
    fun visible(p:StatementPaymentIntent):Boolean {
        val current=currentStatement ?: return false
        if(current.account.wallet.ownerUserId!=owner || !current.isPayable || !sameStatementPaymentTarget(current,p.request.expected))return false
        val wallet=currentWallets.singleOrNull{it.id==current.account.profile.paymentSourceWalletId && it.ownerUserId==owner}
        return if(p.wallet==null)wallet==null else wallet!=null && creditCardStatementPaymentWalletMatches(wallet,p.wallet)
    }
    fun changed() {review=null;intent=null;error=R.string.management_managementcreditcardstatement_payment_changed}
    fun execute(p:StatementPaymentIntent) {
        if(busy)return
        if(!visible(p)){changed();return}
        intent=p;review=null;error=null;success=false;busy=true
        scope.launch {
            fun failed(failure:Throwable) {
                if(failure is CancellationException)throw failure
                val needed=(failure as? InvestmentFundUsageConfirmationRequired)?.review
                if(needed!=null && needed.consent.ownerUserId==owner && needed.consent.transactionId==p.request.context.creation.id) {
                    if(!visible(p)){changed();return}
                    review=needed;intent=p
                } else {
                    review=null
                    if(failure is InvestmentFundUsageException && failure.reason in setOf(InvestmentFundUsageError.STALE_CONSENT,InvestmentFundUsageError.EVENT_CONFLICT))intent=null
                    error=statementPaymentErrorResource(failure)
                }
            }
            try {
                val result=currentPay(p.request,p.device)
                currentCoroutineContext().ensureActive()
                result.fold(onSuccess={saved->
                    if(saved.transaction.ownerUserId!=owner || saved.transaction.id!=p.request.context.creation.id ||
                        saved.transaction.amountMinor!=p.request.expected.amountMinor || saved.occurrence.ownerUserId!=owner ||
                        saved.occurrence.sourceId!=p.request.expected.account.wallet.id || saved.occurrence.selectedMonthKey!=p.request.expected.month.toString() ||
                        saved.occurrence.linkedTransactionId!=saved.transaction.id) {
                        failed(IllegalStateException("Invalid statement payment result"))
                    } else {review=null;intent=null;success=true}
                },onFailure=::failed)
            }catch(cancelled:CancellationException){throw cancelled}catch(failure:Exception){failed(failure)}finally{busy=false}
        }
    }
    LaunchedEffect(statement,wallets) {
        val p=intent
        if(review!=null && p!=null && !busy && !visible(p))changed()
    }
    content({target->
        if(!busy && target.account.wallet.ownerUserId==owner) {
            val old=intent?.takeIf{visible(it)}
            val prepared=old ?: StatementPaymentIntent(CreditCardStatementPaymentRequest(target,
                BillInvestmentOperationContext(TransactionCreationIdentity(UUID.randomUUID().toString(),now().toString()),primaryCurrencyCode,adjustmentTitle),title),
                wallets.singleOrNull{it.ownerUserId==owner && it.id==target.account.profile.paymentSourceWalletId},deviceIdProvider())
            execute(prepared)
        }
    },busy)
    val pending=review;val p=intent
    if(pending!=null && p!=null)InvestmentFundUsageDialog(pending,wallets.filter{it.ownerUserId==owner},
        onDismiss={if(!busy){review=null;intent=null}},onConfirm={
            if(!busy && visible(p))execute(p.copy(request=p.request.copy(context=p.request.context.copy(consent=pending.consent))))else if(!busy)changed()
        },isSaving=busy,tagPrefix="statement.funds",canConfirm=visible(p))
    val message=if(success)R.string.management_managementcreditcardstatement_statement_paid else error
    if(message!=null)AlertDialog(onDismissRequest={if(!busy){success=false;error=null}},
        title={Text(stringResource(R.string.management_management_credit_card2))},
        text={Text(stringResource(message),Modifier.testTag("statement.payment.message"))},
        confirmButton={TextButton(onClick={success=false;error=null},enabled=!busy,modifier=Modifier.testTag("statement.payment.close")){Text(stringResource(R.string.common_ok))}})
}

internal fun sameStatementPaymentTarget(a:CreditCardStatement,b:CreditCardStatement):Boolean = creditCardStatementPaymentSourceMatches(a,b)

internal fun statementPaymentErrorResource(error:Throwable):Int=when(error) {
    is CreditCardStatementPaymentException->when(error.reason) {
        CreditCardStatementPaymentError.CURRENCY_MISMATCH->R.string.management_managementcreditcardstatement_currency_mismatch
        CreditCardStatementPaymentError.MISSING_LINKED_WALLET,CreditCardStatementPaymentError.INVALID_WALLET->R.string.management_managementcreditcardstatement_please_set_a_linked_payment_wallet_for
        else->R.string.management_managementcreditcardstatement_payment_changed
    }
    is InvestmentFundUsageException->when(error.reason) {
        InvestmentFundUsageError.CURRENCY_MISMATCH->R.string.investment_error_fund_usage_currency_mismatch
        InvestmentFundUsageError.STALE_CONSENT,InvestmentFundUsageError.EVENT_CONFLICT->R.string.management_managementcreditcardstatement_payment_changed
        else->R.string.planning_duepayment_payment_failed
    }
    is TransactionValidationException->if(error.reason==TransactionValidationError.INSUFFICIENT_WALLET_BALANCE)
        R.string.management_managementcreditcardstatement_the_linked_wallet_balance_is_not_enough else R.string.planning_duepayment_payment_failed
    else->R.string.planning_duepayment_payment_failed
}
