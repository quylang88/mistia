package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentCashReconciliationRepository(private val store:LocalStore) {
    suspend fun reconcile(owner:UserId,request:InvestmentCashReconciliationRequest,deviceId:String,now:String):Result<Unit> = try {
        var committed=false
        repeat(3) {
            if(!committed) {
                currentCoroutineContext().ensureActive()
                val snapshot=store.investmentCashSnapshot(owner)
                currentCoroutineContext().ensureActive()
                if(snapshot.owner!=owner)throw InvestmentCashReconciliationException(InvestmentCashReconciliationError.UNREADABLE_SOURCE)
                val plan=planInvestmentCashReconciliation(snapshot,request,deviceId,now)
                committed=plan.mutations.isEmpty() || store.commitInvestmentCashReconciliation(snapshot,request,deviceId,now)
                currentCoroutineContext().ensureActive()
            }
        }
        if(!committed)throw InvestmentCashReconciliationException(InvestmentCashReconciliationError.STALE_RECORD)
        Result.success(Unit)
    }catch(cancelled:CancellationException){throw cancelled}
    catch(failure:Exception){Result.failure(failure)}
}
