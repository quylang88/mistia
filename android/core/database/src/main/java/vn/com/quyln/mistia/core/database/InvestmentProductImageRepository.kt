package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

internal class OfflineInvestmentProductImageRepository(
    private val store:LocalStore,private val cache:FileInvestmentProductImageCache?,
    private val remote:InvestmentProductImageRemote?,private val thumbnailer:(suspend (ByteArray)->ByteArray)?,
) {
    suspend fun stagedData(owner:UserId,candidate:InvestmentProductImageCandidate):Result<ByteArray> = result {
        images().imageData(owner,candidate,thumbnail=true).getOrThrow()
    }
    suspend fun data(owner:UserId,assetId:String,path:String,thumbnail:Boolean):Result<ByteArray?> = result {
        InvestmentProductImagePath.parse(owner,assetId,path)
        requireReference(owner,assetId,path)
        val cached=images().cachedImageData(owner,assetId,path,thumbnail).getOrThrow()
        if(cached!=null) {
            requireReference(owner,assetId,path)
            return@result cached
        }
        val service=remote ?: return@result null
        val caller=currentCoroutineContext()
        val full=service.download(owner,assetId,path,isCurrent={caller[kotlinx.coroutines.Job]?.isActive!=false}).getOrThrow()
        requireReference(owner,assetId,path)
        if(full==null)return@result null
        val thumb=requireNotNull(thumbnailer){"Product image thumbnail preparation unavailable"}(full)
        requireReference(owner,assetId,path)
        images().cacheDownloaded(owner,assetId,path,full,thumb).getOrThrow()
        requireReference(owner,assetId,path)
        if(thumbnail)thumb else full
    }
    private suspend fun requireReference(owner:UserId,assetId:String,path:String) {
        val raw=snapshot(owner).rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==assetId}
            ?: throw CancellationException("Product image source changed")
        require(raw.ownerUserId==owner.value){"Product image source owner differs"}
        val asset=InvestmentAssetRecord.fromCloudRecord(raw)
        if(asset.deletedAt!=null || asset.imagePath!=path)throw CancellationException("Product image source changed")
        currentCoroutineContext().ensureActive()
    }
    suspend fun stage(owner:UserId,assetId:String,image:PreparedInvestmentProductImage):Result<InvestmentProductImageCandidate> = result {
        require(image.mimeType=="image/jpeg" && image.width in 1..1600 && image.height in 1..1600){"Invalid prepared product image"}
        images().stage(owner,assetId,image.imageData,image.thumbnailData).getOrThrow()
    }
    suspend fun discard(owner:UserId,candidate:InvestmentProductImageCandidate):Result<Boolean> = result {
        images().discardCandidate(owner,candidate).getOrThrow()
    }
    suspend fun save(owner:UserId,draft:InvestmentAssetDraft,candidate:InvestmentProductImageCandidate?,revision:String,device:String,now:String):Result<InvestmentAssetRecord> = result {
        val previous=ownedInvestmentImagePathOrNull(owner,draft.id,draft.expected?.imagePath)
        // Validate the frozen proposal before reserving files. No financial/history writes here.
        val ticket=InvestmentProductImagePublication(owner.value,draft.id,revision,previous,candidate)
        val request=InvestmentAssetImageSaveRequest(draft,ticket)
        val initial=snapshot(owner)
        planInvestmentAssetImageSave(initial,request,device,now)
        val reserved=if(candidate==null)images().reserveRemoval(owner,draft.id,previous,revision).getOrThrow()
            else images().reservePublication(owner,candidate,previous,revision).getOrThrow()
        require(reserved==ticket)
        repeat(3) {
            val current=snapshot(owner)
            val plan=planInvestmentAssetImageSave(current,request,device,now)
            try {
                if(!store.commitInvestmentAssetImageMutation(current,request,device,now))return@repeat
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception) {
                // A thrown reply is not a rollback. Only a fresh, exact no-write Room proof
                // can acknowledge the publication; uncertainty retains the reservation.
                val durable=snapshot(owner)
                val known=planInvestmentAssetImageSave(durable,request,device,now)
                if(known.mutations.isNotEmpty())throw error
                if(!store.commitInvestmentAssetImageMutation(durable,request,device,now))return@repeat
            }
            currentCoroutineContext().ensureActive()
            require(images().markLocalPublished(owner,ticket).getOrThrow()){"Product image publication changed"}
            return@result plan.asset
        }
        throw InvestmentAssetException(InvestmentAssetError.STALE_RECORD)
    }
    private suspend fun snapshot(owner:UserId):InvestmentAssetSnapshot {
        currentCoroutineContext().ensureActive()
        return store.investmentAssetSnapshot(owner).also {
            require(it.owner==owner){"Product image source owner changed"}
            currentCoroutineContext().ensureActive()
        }
    }
    private fun images()=requireNotNull(cache){"Product image cache unavailable"}
    private suspend inline fun <T> result(block:()->T):Result<T> = try {
        currentCoroutineContext().ensureActive();Result.success(block())
    }catch(cancelled:CancellationException){throw cancelled}
    catch(error:Exception){Result.failure(error)}
}
