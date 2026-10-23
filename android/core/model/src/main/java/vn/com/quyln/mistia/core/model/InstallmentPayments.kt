package vn.com.quyln.mistia.core.model

import java.time.YearMonth

/** The visible source baseline prevents a changed amount/schedule/currency from paying silently. */
data class InstallmentPaymentRequest(val expected: InstallmentPlanRecord, val month: YearMonth,
    val walletId: RecordId? = null, val amountMinorOverride: Long? = null,
    val expectedDueAmountMinor:Long = expected.amountPerCycleMinor, val investment:BillInvestmentOperationContext?=null)
data class SavedInstallmentPayment(val transaction: LedgerTransactionRecord, val occurrences: List<DueOccurrenceRecord>)
interface InstallmentPaymentRepository {
    suspend fun undoInstallmentPaymentWithInvestmentFunds(owner:UserId,request:InstallmentInvestmentUndoRequest,deviceId:String,now:String):Result<Unit> =
        Result.failure(UnsupportedOperationException("Installment investment undo unavailable"))
    suspend fun payInstallment(owner: UserId, request: InstallmentPaymentRequest, deviceId: String, now: String): Result<SavedInstallmentPayment> =
        Result.failure(UnsupportedOperationException("Installment payment unavailable"))
    suspend fun undoInstallmentPayment(owner: UserId, expected: InstallmentPlanRecord, month: YearMonth, deviceId: String, now: String): Result<Unit> =
        Result.failure(UnsupportedOperationException("Installment payment undo unavailable"))
}


/** Preserve existing repository source consent while ignoring sync acknowledgement metadata. */
fun InstallmentPlanRecord.matchesInstallmentPaymentSource(expected:InstallmentPlanRecord):Boolean=runCatching {
    if(java.time.Duration.between(java.time.Instant.parse(createdAt),java.time.Instant.parse(expected.createdAt)).abs()>=java.time.Duration.ofNanos(1000)) return@runCatching false
    copy(createdAt=expected.createdAt,updatedAt=expected.updatedAt,syncVersion=expected.syncVersion,lastModifiedByDeviceId=expected.lastModifiedByDeviceId)==expected
}.getOrDefault(false)

/** Visible confirmation excludes the separately checked, non-restored fund authorization. */
fun InstallmentPaymentRequest.matchesInstallmentPaymentConsent(other:InstallmentPaymentRequest?):Boolean =
    other!=null && copy(expected=other.expected,investment=null)==other.copy(investment=null) && expected.matchesInstallmentPaymentSource(other.expected)
