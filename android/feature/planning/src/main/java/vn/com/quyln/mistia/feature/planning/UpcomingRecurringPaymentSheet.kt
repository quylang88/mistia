package vn.com.quyln.mistia.feature.planning

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

private sealed interface UpcomingPaymentLoad {
    data object Loading:UpcomingPaymentLoad
    data object Failed:UpcomingPaymentLoad
    data class Loaded(val snapshot:UpcomingDueReadSnapshot):UpcomingPaymentLoad
}
private data class UpcomingPaymentData(val sources:UpcomingDueReadSources,val wallets:List<LedgerWalletRecord>,val categories:List<TransactionCategoryRecord>)

private fun paymentData(owner:UserId,snapshot:UpcomingDueReadSnapshot):UpcomingPaymentData?=runCatching {
    val sources=requireNotNull(upcomingDueReadSources(owner,snapshot))
    val wallets=snapshot.records(CloudEntity.LEDGER_WALLET).filter {it.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,requireBodyIdentity=true)}.mapNotNull {raw ->
        val deleted=raw.financeRawDeleted(requireTimestamp=true);val archived=raw.payload.financeRawArchived()
        if(deleted==true || archived==true) return@mapNotNull null
        require(deleted==false && archived==false)
        val kind=requireNotNull(raw.payload.financeRawString("kind_raw_value")?.let(WalletKind::fromWireValue))
        if(kind==WalletKind.INVESTMENT) return@mapNotNull null
        val code=requireNotNull(raw.payload.financeRawString("currency_code")?.financeReportingCode());java.util.Currency.getInstance(code)
        LedgerWalletRecord.fromCloudRecord(raw)
    }
    val categories=snapshot.records(CloudEntity.TRANSACTION_CATEGORY).filter {it.financeRawIdentity(owner,CloudEntity.TRANSACTION_CATEGORY,requireBodyIdentity=true)}
        .mapNotNull {runCatching {TransactionCategoryRecord.fromCloudRecord(it)}.getOrNull()}
    UpcomingPaymentData(sources,wallets,categories)
}.getOrNull()

/** Identity-only entry point: reload the original cycle and never turn a stale Pay target into Undo/Create. */
@Composable
fun UpcomingRecurringPaymentSheet(owner:UserId,target:UpcomingDuePaymentTarget,repository:FinanceRepository,
    deviceIdProvider:suspend ()->String,onDismiss:()->Unit) {
    if(target.ownerUserId==owner.value) key(owner.value,target) {
        val lifecycle=LocalLifecycleOwner.current.lifecycle
        var retry by remember {mutableIntStateOf(0)}
        val load by key(repository,retry,lifecycle) {
            produceState<UpcomingPaymentLoad>(UpcomingPaymentLoad.Loading) {
                try {
                    lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                        value=UpcomingPaymentLoad.Loading
                        repository.observeUpcomingDueReadSnapshot(owner).collect {
                            value=if(it.owner==owner) UpcomingPaymentLoad.Loaded(it) else UpcomingPaymentLoad.Failed
                        }
                    }
                } catch(cancelled:CancellationException) {throw cancelled}
                catch(_:Exception) {value=UpcomingPaymentLoad.Failed}
            }
        }
        val snapshot=(load as? UpcomingPaymentLoad.Loaded)?.snapshot
        val data=remember(snapshot) {snapshot?.let {paymentData(owner,it)}}
        val failed=load==UpcomingPaymentLoad.Failed || (snapshot!=null && data==null)
        val zone=ZoneId.systemDefault()
        val bill=remember(data,target,zone) {data?.sources?.let {recurringBillDueRows(owner,it.bills,it.occurrences,target.month,zone).singleOrNull {row ->row.bill.id==target.sourceId && row.status==DueStatus.PENDING && row.linkedTransactionId==null}}}
        val installment=remember(data,target,zone) {data?.sources?.let {installmentDueRows(owner,it.installments,it.occurrences,target.month,zone).singleOrNull {row ->row.plan.id==target.sourceId && row.status==DueStatus.PENDING && row.linkedTransactionId==null}}}
        var firstBill by remember {mutableStateOf<RecurringBillDueRow?>(null)}
        var firstInstallment by remember {mutableStateOf<InstallmentDueRow?>(null)}
        SideEffect {
            if(firstBill==null && bill!=null) firstBill=bill
            if(firstInstallment==null && installment!=null) firstInstallment=installment
        }
        val billRow=bill ?: firstBill
        val installmentRow=firstInstallment ?: installment
        when {
            target.sourceKind==DueSourceKind.RECURRING_BILL && billRow!=null -> BillPaymentSheet(owner.value,billRow,target.month,data?.wallets.orEmpty(),false,
                onPay={repository.payRecurringBill(owner,it,deviceIdProvider(),Instant.now().toString())},
                onUndo={Result.failure(IllegalStateException("Pay target cannot undo"))},onDismiss=onDismiss,
                category=data?.categories?.firstOrNull {it.id==billRow.bill.categoryId},
                dataReady=data!=null,loadFailed=failed,targetCurrent=bill!=null,onRetryLoad={retry++})
            target.sourceKind==DueSourceKind.INSTALLMENT && installmentRow!=null -> InstallmentPaymentSheet(owner.value,installmentRow,data?.wallets.orEmpty(),
                dataReady=data!=null,loadFailed=failed,targetCurrent=installmentPaymentTargetIsCurrent(installmentRow,installment),onRetryLoad={retry++},
                onPay={repository.payInstallment(owner,it,deviceIdProvider(),Instant.now().toString())},
                onUndo={Result.failure(IllegalStateException("Pay target cannot undo"))},onDismiss=onDismiss)
            else -> AlertDialog(onDismissRequest=onDismiss,modifier=Modifier.testTag("upcoming.paymentUnavailable"),text={
                if(load==UpcomingPaymentLoad.Loading) CircularProgressIndicator()
                else Text(stringResource(if(failed) R.string.planning_installment_load_error else R.string.planning_duepayment_could_not_find_the_due_item))
            },confirmButton={TextButton(onClick=onDismiss) {Text(stringResource(R.string.common_close))}},
                dismissButton={if(failed) TextButton(onClick={retry++},modifier=Modifier.testTag("upcoming.paymentRetry")) {Text(stringResource(R.string.planning_installment_retry))}})
        }
    }
}
