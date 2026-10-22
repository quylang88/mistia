package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentCashTransferLifecycleRepository(private val store:LocalStore) {
    suspend fun change(owner:UserId,request:InvestmentCashTransferLifecycleRequest,deviceId:String,now:String):Result<Unit> = try {
        var committed=false
        repeat(3) {
            if(!committed) {
                val snapshot=store.investmentCashSnapshot(owner)
                if(snapshot.owner!=owner)throw InvestmentCashTransferException(InvestmentCashTransferError.UNREADABLE_SOURCE)
                val plan=planInvestmentCashTransferLifecycle(snapshot,request,deviceId,now)
                committed=plan.mutations.isEmpty() || store.commitInvestmentCashTransferLifecycle(snapshot,request,deviceId,now)
            }
        }
        if(!committed)throw InvestmentCashTransferException(InvestmentCashTransferError.STALE_RECORD)
        Result.success(Unit)
    }catch(cancelled:CancellationException){throw cancelled}
    catch(failure:Exception){Result.failure(failure)}
}
