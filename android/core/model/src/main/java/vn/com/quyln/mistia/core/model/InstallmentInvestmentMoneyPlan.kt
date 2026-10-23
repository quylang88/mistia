package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import java.time.ZoneId

data class InstallmentInvestmentUndoRequest(val expected:InstallmentPlanRecord,val month:YearMonth,
    val expectedAmountMinor:Long,val expectedLinkedTransactionId:String?,val investment:BillInvestmentOperationContext)
sealed interface InstallmentInvestmentMoneyOperation {
    data class Pay(val request:InstallmentPaymentRequest):InstallmentInvestmentMoneyOperation
    data class Undo(val request:InstallmentInvestmentUndoRequest):InstallmentInvestmentMoneyOperation
}
data class InstallmentInvestmentMoneyPlan(val payment:SavedInstallmentPayment?,val mutations:List<Pair<CloudRecord,PendingMutation>>)
fun planInstallmentInvestmentMoney(snapshot:BillMoneySnapshot,operation:InstallmentInvestmentMoneyOperation,catalog:SystemCategoryCatalog,
    deviceId:String,now:String,zone:ZoneId=ZoneId.systemDefault()):InstallmentInvestmentMoneyPlan =
    BillInvestmentPlanner(snapshot,catalog,deviceId,now,zone).planInstallment(operation)
