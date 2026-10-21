package vn.com.quyln.mistia.core.database

import java.time.YearMonth
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

/** Shares guarded expense/undo execution; source records, scheduling and categories stay domain-specific. */
internal class OfflineInstallmentPaymentRepository(private val store: LocalStore, private val zone: () -> ZoneId,
    private val catalog: SystemCategoryCatalog?) : InstallmentPaymentRepository {
    override suspend fun payInstallment(owner: UserId, request: InstallmentPaymentRequest, deviceId: String, now: String): Result<SavedInstallmentPayment> =
        executor(request.expected).payRecurringBill(owner, BillPaymentRequest(RecordId(request.expected.id), request.month, request.walletId,
            request.amountMinorOverride,expectedDueAmountMinor=request.expectedDueAmountMinor), deviceId, now).map { SavedInstallmentPayment(it.transaction, it.occurrences) }
    override suspend fun undoInstallmentPayment(owner: UserId, expected: InstallmentPlanRecord, month: YearMonth, deviceId: String, now: String): Result<Unit> =
        executor(expected).undoRecurringBillPayment(owner, RecordId(expected.id), month, deviceId, now)
    private fun executor(expected: InstallmentPlanRecord) = OfflineBillPaymentRepository(store, zone, catalog,
        sourceKind = DueSourceKind.INSTALLMENT, expectedInstallment = expected)
}
