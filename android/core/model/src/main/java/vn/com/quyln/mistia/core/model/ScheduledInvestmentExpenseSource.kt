package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

/** Actual domain records and schedules; no synthetic bill payload enters the money proof. */
internal class ScheduledInvestmentExpenseSource(raw:CloudRecord,val kind:DueSourceKind) {
    val recurring=if(kind==DueSourceKind.RECURRING_BILL)RecurringBillPlanRecord.fromCloudRecord(raw)else null
    val installment=if(kind==DueSourceKind.INSTALLMENT)InstallmentPlanRecord.fromCloudRecord(raw)else null
    init{require(recurring!=null || installment!=null)}
    val id get()=recurring?.id ?: requireNotNull(installment).id
    val name get()=recurring?.name ?: requireNotNull(installment).name
    val iconSymbolName get()=recurring?.iconSymbolName ?: requireNotNull(installment).iconSymbolName
    val currencyCode get()=recurring?.currencyCode ?: requireNotNull(installment).currencyCode
    val paymentWalletId get()=recurring?.paymentWalletId ?: installment?.paymentWalletId
    val categoryId get()=recurring?.categoryId
    val amountMinor get()=recurring?.amountMinor ?: installment?.amountPerCycleMinor
    val autoPayEnabled get()=recurring?.autoPayEnabled
    val isPaused get()=recurring?.isPaused ?: false
    val isArchived get()=recurring?.isArchived ?: requireNotNull(installment).isArchived
    val ownerUserId get()=recurring?.ownerUserId ?: requireNotNull(installment).ownerUserId
    val deletedAt get()=recurring?.deletedAt ?: installment?.deletedAt
    fun due(owner:UserId,occurrences:List<DueOccurrenceRecord>,month:YearMonth,zone:ZoneId):ScheduledInvestmentDue? =
        if(recurring!=null)recurringBillDueRows(owner,listOf(recurring),occurrences,month,zone).singleOrNull()?.let {
            ScheduledInvestmentDue(it.amountMinor,it.dueDate,it.autoPayDate,it.linkedTransactionId)
        }else installmentDueRows(owner,listOf(requireNotNull(installment)),occurrences,month,zone).singleOrNull()?.let {
            ScheduledInvestmentDue(it.amountMinor,it.dueDate,null,it.linkedTransactionId)
        }
}
internal data class ScheduledInvestmentDue(val amountMinor:Long?,val dueDate:Instant,val autoPayDate:Instant?,val linkedTransactionId:String?)
