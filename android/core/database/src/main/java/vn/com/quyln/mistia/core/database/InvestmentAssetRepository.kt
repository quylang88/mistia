package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentAssetRepository(private val store:LocalStore) {
    fun observe(owner:UserId)=store.observeInvestmentAssetSnapshot(owner).map{snapshot ->
        require(snapshot.owner==owner)
        snapshot.copy(rows=snapshot.rows.filter{row ->
            CloudEntity.fromTable(row.entity)?.let{it in InvestmentAssetSnapshot.entities && row.matchesFinanceReadScope(owner,it,true)}==true
        })
    }
    suspend fun save(owner:UserId,draft:InvestmentAssetDraft,device:String,now:String):Result<InvestmentAssetRecord> =
        result{require(draft.imageChange==InvestmentAssetImageChange.Keep){"Asset images require a reserved publication"};mutate(owner,InvestmentAssetRequest.Save(draft),device,now)}
    suspend fun archive(owner:UserId,expected:InvestmentAssetRecord,archived:Boolean,device:String,now:String):Result<Unit> =
        result{mutate(owner,InvestmentAssetRequest.Archive(expected,archived),device,now);Unit}
    private suspend fun mutate(owner:UserId,request:InvestmentAssetRequest,device:String,now:String):InvestmentAssetRecord {
        repeat(3) {
            val snapshot=store.investmentAssetSnapshot(owner)
            if(snapshot.owner!=owner)throw InvestmentAssetException(InvestmentAssetError.UNREADABLE_SOURCE)
            val plan=planInvestmentAssetMutation(snapshot,request,device,now)
            if(plan.mutations.isEmpty() || store.commitInvestmentAssetMutation(snapshot,request,device,now))return plan.asset
        }
        throw InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
    }
    private inline fun <T> result(block:()->T):Result<T> = try{Result.success(block())}
        catch(cancelled:CancellationException){throw cancelled}
        catch(error:Exception){Result.failure(error)}
}
