package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentTradeRepository(private val store:LocalStore) {
    fun observe(owner:UserId)=store.observeInvestmentPurchaseSnapshot(owner).map{snapshot->
        require(snapshot.owner==owner)
        require(snapshot.rows.all{row->CloudEntity.fromTable(row.entity)?.let{entity->entity in InvestmentPurchaseSnapshot.entities && row.financeRawIdentity(owner,entity,true)}==true})
        snapshot
    }
    suspend fun savePurchase(owner:UserId,request:InvestmentPurchaseRequest,device:String,now:String)=
        save(owner,{planInvestmentPurchase(it,request,device,now).trade},{store.commitInvestmentPurchase(it,request,device,now)})
    suspend fun saveSale(owner:UserId,request:InvestmentSaleRequest,device:String,now:String)=
        save(owner,{planInvestmentSale(it,request,device,now).trade},{store.commitInvestmentSale(it,request,device,now)})
    suspend fun editTrade(owner:UserId,request:InvestmentTradeEditRequest,device:String,now:String)=
        save(owner,{planInvestmentTradeEdit(it,request,device,now).trade},{store.commitInvestmentTradeEdit(it,request,device,now)})
    suspend fun deleteTrade(owner:UserId,request:InvestmentTradeDeletionRequest,device:String,now:String)=
        save(owner,{planInvestmentTradeDeletion(it,request,device,now).trade},{store.commitInvestmentTradeDeletion(it,request,device,now)})
    private suspend fun save(owner:UserId,prepare:(InvestmentTradeCreationSnapshot)->CloudRecord,
        commit:suspend (InvestmentTradeCreationSnapshot)->Boolean):Result<CloudRecord> = try {
        var result:CloudRecord?=null
        repeat(3) {
            if(result==null) {
                currentCoroutineContext().ensureActive()
                val snapshot=store.investmentPurchaseSnapshot(owner)
                require(snapshot.owner==owner)
                val trade=prepare(snapshot)
                if(commit(snapshot))result=trade
            }
        }
        currentCoroutineContext().ensureActive()
        Result.success(result ?: throw InvestmentAssetException(InvestmentAssetError.STALE_RECORD))
    }catch(cancelled:CancellationException){throw cancelled}
    catch(error:Exception){Result.failure(error)}
}
