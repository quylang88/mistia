package vn.com.quyln.mistia.core.model

import java.time.YearMonth

/** The visible source baseline prevents a changed amount/schedule/currency from paying silently. */
data class InstallmentPaymentRequest(val expected: InstallmentPlanRecord, val month: YearMonth,
    val walletId: RecordId? = null, val amountMinorOverride: Long? = null)
data class SavedInstallmentPayment(val transaction: LedgerTransactionRecord, val occurrences: List<DueOccurrenceRecord>)
interface InstallmentPaymentRepository {
    suspend fun payInstallment(owner: UserId, request: InstallmentPaymentRequest, deviceId: String, now: String): Result<SavedInstallmentPayment> =
        Result.failure(UnsupportedOperationException("Installment payment unavailable"))
    suspend fun undoInstallmentPayment(owner: UserId, expected: InstallmentPlanRecord, month: YearMonth, deviceId: String, now: String): Result<Unit> =
        Result.failure(UnsupportedOperationException("Installment payment undo unavailable"))
}
