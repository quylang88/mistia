package vn.com.quyln.mistia.core.database

import java.time.YearMonth
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

/** Shares guarded expense/undo execution; source records, scheduling and categories stay domain-specific. */
internal class OfflineInstallmentPaymentRepository(private val store: LocalStore, private val zone: () -> ZoneId,
    private val catalog: SystemCategoryCatalog?) : InstallmentPaymentRepository {
    override suspend fun payInstallment(owner: UserId, request: InstallmentPaymentRequest, deviceId: String, now: String): Result<SavedInstallmentPayment> =
        if(request.investment!=null) result {
            val snapshot=store.installmentInvestmentMoneySnapshot(owner,RecordId(request.expected.id),request.month)
            val operation=InstallmentInvestmentMoneyOperation.Pay(request)
            val definitions=requireNotNull(catalog){"System category catalog unavailable"};val currentZone=zone()
            planInstallmentInvestmentMoney(snapshot,operation,definitions,deviceId,now,currentZone)
            requireNotNull(store.commitInstallmentInvestmentMoney(snapshot,operation,definitions,deviceId,now,currentZone).payment)
        }else executor(request.expected).payRecurringBill(owner, BillPaymentRequest(RecordId(request.expected.id), request.month, request.walletId,
            request.amountMinorOverride,expectedDueAmountMinor=request.expectedDueAmountMinor), deviceId, now).map { SavedInstallmentPayment(it.transaction, it.occurrences) }
    override suspend fun undoInstallmentPayment(owner: UserId, expected: InstallmentPlanRecord, month: YearMonth, deviceId: String, now: String): Result<Unit> =
        executor(expected).undoRecurringBillPayment(owner, RecordId(expected.id), month, deviceId, now)
    override suspend fun undoInstallmentPaymentWithInvestmentFunds(owner:UserId,request:InstallmentInvestmentUndoRequest,deviceId:String,now:String):Result<Unit> = result {
        val snapshot=store.installmentInvestmentMoneySnapshot(owner,RecordId(request.expected.id),request.month)
        val operation=InstallmentInvestmentMoneyOperation.Undo(request)
        val definitions=requireNotNull(catalog){"System category catalog unavailable"};val currentZone=zone()
        planInstallmentInvestmentMoney(snapshot,operation,definitions,deviceId,now,currentZone)
        store.commitInstallmentInvestmentMoney(snapshot,operation,definitions,deviceId,now,currentZone)
        Unit
    }
    private suspend fun <T> result(block:suspend ()->T):Result<T> = try{Result.success(block())}
        catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
        catch(error:Exception){Result.failure(error)}
    private fun executor(expected: InstallmentPlanRecord) = OfflineBillPaymentRepository(store, zone, catalog,
        sourceKind = DueSourceKind.INSTALLMENT, expectedInstallment = expected)
}
