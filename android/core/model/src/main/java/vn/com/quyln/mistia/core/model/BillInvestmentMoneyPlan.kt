package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*

data class BillInvestmentSettings(val accountingCurrency:String,val adjustmentTitle:String)

/** Frozen local intent; fund consent is never restored or inferred from payment confirmation. */
data class BillInvestmentOperationContext(val creation:TransactionCreationIdentity,val accountingCurrency:String,
    val adjustmentTitle:String,val consent:InvestmentFundUsageConsent?=null)
data class BillInvestmentUndoRequest(val expected:RecurringBillPlanRecord,val month:YearMonth,
    val expectedAmountMinor:Long?,val expectedLinkedTransactionId:String?,val investment:BillInvestmentOperationContext)
sealed interface BillInvestmentMoneyOperation {
    data class Pay(val request:BillPaymentRequest,val presentation:BillAutomaticPaymentText?=null):BillInvestmentMoneyOperation
    data class Undo(val request:BillInvestmentUndoRequest):BillInvestmentMoneyOperation
}
data class BillInvestmentMoneyPlan(val payment:SavedBillPayment?,val mutations:List<Pair<CloudRecord,PendingMutation>>)

/** Complete bill/occurrence/derived write plan, recomputed at the owned Room boundary. */
fun planBillInvestmentMoney(snapshot:BillMoneySnapshot,operation:BillInvestmentMoneyOperation,catalog:SystemCategoryCatalog,
    deviceId:String,now:String,zone:ZoneId=ZoneId.systemDefault()):BillInvestmentMoneyPlan =
    BillInvestmentPlanner(snapshot,catalog,deviceId,now,zone).plan(operation)

fun billInvestmentSuccessNotification(owner:UserId,bill:RecurringBillPlanRecord,month:YearMonth,amount:Long,walletId:String,dueDate:String,
    text:BillAutomaticPaymentText,now:String):AppNotificationRecord=AppNotificationRecord(owner.value,
    "mistia.bill.autopay.success.${bill.id.lowercase()}.$month",text.successTitle,text.successBody,"billAutoPaymentSucceeded",
    resourceType="bill",resourceId=bill.id,createdAt=now,updatedAt=now,metadata=buildJsonObject {
        put("sourceKind","recurringBill");put("sourceId",bill.id);put("dueMonthKey",month.toString());put("dueDate",dueDate)
        put("requiresAmountInput",false);put("currencyCode",bill.currencyCode);put("billName",bill.name);put("linkedPaymentWalletId",walletId)
    })
