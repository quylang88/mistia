package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.json.*

sealed interface NotificationBillAction {
    data class Pay(val billId:String,val month:YearMonth):NotificationBillAction
    data class TopUp(val walletId:String):NotificationBillAction
}
fun notificationBillAction(owner:UserId,row:AppNotificationRecord,bills:List<RecurringBillPlanRecord>,
    occurrences:List<DueOccurrenceRecord>,wallets:List<LedgerWalletRecord>,zone:ZoneId):NotificationBillAction? = runCatching {
    if(row.ownerUserId!=owner.value || row.resourceType!="bill" || row.source !in setOf("system","localReminder")) return@runCatching null
    val metadata=row.metadata ?: return@runCatching null
    if(metadata["sourceKind"]!=JsonPrimitive("recurringBill")) return@runCatching null
    val id=UUID.fromString((metadata["sourceId"] as? JsonPrimitive)?.content).toString()
    if(UUID.fromString(row.resourceId).toString()!=id) return@runCatching null
    val month=YearMonth.parse((metadata["dueMonthKey"] as? JsonPrimitive)?.content)
    if(row.kind=="billAutoPaymentFailed") {
        val walletId=UUID.fromString((metadata["linkedPaymentWalletId"] as? JsonPrimitive)?.content).toString()
        val wallet=wallets.singleOrNull {it.id==walletId && it.ownerUserId==owner.value && it.deletedAt==null && !it.isArchived && it.kind!=null}
            ?: return@runCatching null
        return@runCatching NotificationBillAction.TopUp(wallet.id)
    }
    if(row.kind !in setOf("billPaymentRequired","billOverdue")) return@runCatching null
    val bill=bills.singleOrNull {it.id==id && it.ownerUserId==owner.value && it.deletedAt==null && !it.isArchived && (it.scheduleKind!=BillScheduleKind.RECURRING || !it.isPaused)}
        ?: return@runCatching null
    val due=recurringBillDueRows(owner,listOf(bill),occurrences,month,zone).singleOrNull()
        ?: return@runCatching null
    if(due.status!=DueStatus.PENDING || due.linkedTransactionId!=null) return@runCatching null
    NotificationBillAction.Pay(bill.id,month)
}.getOrNull()
