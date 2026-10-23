package vn.com.quyln.mistia.feature.planning

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.res.stringResource
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.flow.combine
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

private data class NotificationBillData(val bills:List<RecurringBillPlanRecord>,val occurrences:List<DueOccurrenceRecord>,
    val wallets:List<LedgerWalletRecord>,val categories:List<TransactionCategoryRecord>)

@Composable
fun NotificationBillPaymentSheet(owner:UserId,target:NotificationBillAction.Pay,repository:FinanceRepository,
    deviceIdProvider:suspend ()->String,onDismiss:()->Unit,primaryCurrencyCode:String="JPY") {
    key(owner.value,target.billId,target.month,repository,primaryCurrencyCode) {
        val data by produceState<NotificationBillData?>(null,owner,target) {
            combine(repository.observeRecurringBills(owner),repository.observeDueOccurrences(owner),repository.observeWallets(owner),repository.observeCategories(owner)) {
                bills,occurrences,wallets,categories -> NotificationBillData(bills,occurrences,wallets,categories)
            }.collect {value=it}
        }
        val snapshot=data
        val bill=snapshot?.bills?.singleOrNull {it.id==target.billId && it.ownerUserId==owner.value && !it.isArchived && (it.scheduleKind!=BillScheduleKind.RECURRING || !it.isPaused) && it.deletedAt==null}
        val row=bill?.let {recurringBillDueRows(owner,listOf(it),snapshot!!.occurrences,target.month,ZoneId.systemDefault()).singleOrNull()}
        if(snapshot==null) {
            AlertDialog(onDismissRequest=onDismiss,text={CircularProgressIndicator()},confirmButton={})
        } else if(row==null) {
            AlertDialog(onDismissRequest=onDismiss,text={Text(stringResource(R.string.planning_duepayment_could_not_find_the_due_item))},
                confirmButton={TextButton(onClick=onDismiss) {Text(stringResource(R.string.common_ok))}})
        } else {
            BillPaymentSheet(owner.value,row,target.month,snapshot.wallets,false,
                onPay={request -> repository.payRecurringBill(owner,request,deviceIdProvider(),Instant.now().toString())},
                onUndo={Result.failure(IllegalStateException("Notification payment cannot undo"))},onDismiss=onDismiss,
                category=snapshot.categories.firstOrNull {it.id==row.bill.categoryId},primaryCurrencyCode=primaryCurrencyCode,operationScopeKey=repository)
        }
    }
}
