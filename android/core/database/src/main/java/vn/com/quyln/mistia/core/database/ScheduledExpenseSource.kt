package vn.com.quyln.mistia.core.database

import java.time.Duration
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

/** Uses actual domain records and scheduling; no synthetic bill or cloud payload is created. */
internal class ScheduledExpenseSource(val raw: CloudRecord, val kind: DueSourceKind) {
    val bill = if (kind == DueSourceKind.RECURRING_BILL) RecurringBillPlanRecord.fromCloudRecord(raw) else null
    val installment = if (kind == DueSourceKind.INSTALLMENT) InstallmentPlanRecord.fromCloudRecord(raw) else null
    init { require(bill != null || installment != null) }
    val id get() = bill?.id ?: requireNotNull(installment).id
    val name get() = bill?.name ?: requireNotNull(installment).name
    val iconSymbolName get() = bill?.iconSymbolName ?: requireNotNull(installment).iconSymbolName
    val currencyCode get() = bill?.currencyCode ?: requireNotNull(installment).currencyCode
    val paymentWalletId get() = bill?.paymentWalletId ?: installment?.paymentWalletId
    val categoryId get() = bill?.categoryId
    val autoPayEnabled get() = bill?.autoPayEnabled
    val isPaused get() = bill?.isPaused ?: false
    val isArchived get() = bill?.isArchived ?: requireNotNull(installment).isArchived
    val ownerUserId get() = bill?.ownerUserId ?: requireNotNull(installment).ownerUserId
    val deletedAt get() = bill?.deletedAt ?: installment?.deletedAt
    fun due(owner: UserId, occurrences: List<DueOccurrenceRecord>, month: YearMonth, zone: ZoneId): ScheduledExpenseDue? =
        bill?.let { source -> recurringBillDueRows(owner, listOf(source), occurrences, month, zone).singleOrNull()?.let {
            ScheduledExpenseDue(it.amountMinor, it.dueDate, it.autoPayDate)
        } } ?: installment?.let { source -> installmentDueRows(owner, listOf(source), occurrences, month, zone).singleOrNull()?.let {
            ScheduledExpenseDue(it.amountMinor, it.dueDate, null)
        } }
    fun matchesExpected(expected: InstallmentPlanRecord): Boolean {
        val current = installment ?: return false
        if (Duration.between(Instant.parse(current.createdAt), Instant.parse(expected.createdAt)).abs() >= Duration.ofNanos(1000)) return false
        return current.copy(createdAt = expected.createdAt, updatedAt = expected.updatedAt, syncVersion = expected.syncVersion,
            lastModifiedByDeviceId = expected.lastModifiedByDeviceId) == expected
    }
}
internal data class ScheduledExpenseDue(val amountMinor: Long?, val dueDate: Instant, val autoPayDate: Instant?)
