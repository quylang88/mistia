package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentLinkedWalletRepository(private val store:LocalStore) {
    fun observe(owner:UserId)=store.observeInvestmentWalletSnapshot(owner).map { snapshot ->
        require(snapshot.owner==owner)
        require(snapshot.rows.all { row ->
            val entity=CloudEntity.fromTable(row.entity)
            entity!=null && entity in InvestmentWalletSnapshot.entities && row.financeRawIdentity(owner,entity,true)
        })
        require(snapshot.rows.map{it.entity to it.id}.distinct().size==snapshot.rows.size)
        snapshot
    }

    suspend fun change(owner:UserId,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Result<Unit> = try {
        var committed=false
        repeat(3) {
            if(!committed) {
                val snapshot=store.investmentWalletSnapshot(owner)
                if(snapshot.owner!=owner)throw InvestmentWalletLinkException(InvestmentWalletLinkError.UNREADABLE_SOURCE)
                val plan=planInvestmentWalletLink(snapshot,request,deviceId,now)
                committed=plan.mutations.isEmpty() || store.commitInvestmentWalletLink(snapshot,request,deviceId,now)
            }
        }
        if(!committed)throw InvestmentWalletLinkException(InvestmentWalletLinkError.STALE_RECORD)
        Result.success(Unit)
    }catch(cancelled:CancellationException){throw cancelled}
    catch(failure:Exception){Result.failure(failure)}
}
