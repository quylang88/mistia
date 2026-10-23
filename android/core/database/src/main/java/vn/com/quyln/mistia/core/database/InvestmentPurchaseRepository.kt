package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentPurchaseRepository(private val store:LocalStore) {
    fun observe(owner:UserId)=store.observeInvestmentPurchaseSnapshot(owner).map{snapshot->
        require(snapshot.owner==owner)
        require(snapshot.rows.all{row->CloudEntity.fromTable(row.entity)?.let{entity->entity in InvestmentPurchaseSnapshot.entities && row.financeRawIdentity(owner,entity,true)}==true})
        snapshot
    }
    suspend fun save(owner:UserId,request:InvestmentPurchaseRequest,device:String,now:String):Result<CloudRecord> = try {
        var result:CloudRecord?=null
        repeat(3) {
            if(result==null) {
                currentCoroutineContext().ensureActive()
                val snapshot=store.investmentPurchaseSnapshot(owner)
                require(snapshot.owner==owner)
                val plan=planInvestmentPurchase(snapshot,request,device,now)
                if(store.commitInvestmentPurchase(snapshot,request,device,now))result=plan.trade
            }
        }
        currentCoroutineContext().ensureActive()
        Result.success(result ?: throw InvestmentAssetException(InvestmentAssetError.STALE_RECORD))
    }catch(cancelled:CancellationException){throw cancelled}
    catch(error:Exception){Result.failure(error)}
}
