package vn.com.quyln.mistia.core.database

import android.content.Context
import android.graphics.Bitmap
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentAssetImageRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var cache:FileInvestmentProductImageCache
    private lateinit var directory:File
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val assetId="22222222-2222-2222-2222-222222222222"
    private val channelId="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val revision="55555555-5555-5555-5555-555555555555"
    private val now="2026-10-24T00:00:00Z"
    private var active=owner
    @Before fun setup() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        directory=File(context.cacheDir,"product-image-room-${java.util.UUID.randomUUID()}")
        cache=FileInvestmentProductImageCache(directory,{active})
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active},productImages=cache)
    }
    @After fun close(){db.close();directory.deleteRecursively()}
    private fun draft(expected:InvestmentAssetRecord?=null)=InvestmentAssetDraft(assetId,channelId,"Cards","VND","box",expected)
    private suspend fun prepare() {
        OfflineFirstInvestmentRepository(store).saveChannel(owner,InvestmentChannelDraft(channelId,"Shop"),"VND",device,now).getOrThrow()
    }
    private fun jpeg():ByteArray {
        val bitmap=Bitmap.createBitmap(8,4,Bitmap.Config.ARGB_8888)
        return try{ByteArrayOutputStream().use{bitmap.compress(Bitmap.CompressFormat.JPEG,90,it);it.toByteArray()}}finally{bitmap.recycle()}
    }
    private suspend fun proposal(expected:InvestmentAssetRecord?=null):InvestmentAssetImageSaveRequest {
        val candidate=cache.stage(owner,assetId,jpeg(),jpeg()).getOrThrow()
        val pub=cache.reservePublication(owner,candidate,expected?.imagePath,revision).getOrThrow()
        return InvestmentAssetImageSaveRequest(draft(expected).copy(imageChange=InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,assetId,candidate.path))),pub)
    }
    @Test fun actualImageCreateAtomicallyQueuesMetadataAndLateCancelCannotDeleteItsBytes()=runBlocking {
        prepare();val request=proposal();val before=store.investmentAssetSnapshot(owner)
        assertTrue(store.commitInvestmentAssetImageMutation(before,request,device,now))
        val row=store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!
        assertEquals(request.publication.path,row.payload.financeRawString("image_path"))
        val queued=store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE).single().mutation
        assertEquals(row.payload,queued.payload);assertEquals(0L,queued.baseVersion)
        assertFalse(cache.discardCandidate(owner,request.publication.candidate!!).getOrThrow())
        assertArrayEquals(jpeg(),cache.imageData(owner,request.publication.candidate!!).getOrThrow())
        assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
        assertTrue(cache.markLocalPublished(owner,request.publication).getOrThrow())
        assertEquals(listOf(request.publication.candidate),cache.pendingUploads(owner).getOrThrow())
        assertNull(store.record(other,CloudEntity.INVESTMENT_ASSET.table,assetId))
    }
    @Test fun exactCommittedReplacementRetryDoesNotWriteMetadataAgain()=runBlocking {
        prepare();val original=OfflineFirstInvestmentRepository(store).saveAsset(owner,draft(),device,now).getOrThrow()
        val request=proposal(original)
        assertTrue(store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now))
        assertTrue(cache.markLocalPublished(owner,request.publication).getOrThrow())
        val after=store.investmentAssetSnapshot(owner)
        val queued=store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER no_retry_write BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_assets' BEGIN SELECT RAISE(ABORT, 'retry must not write'); END")
        assertTrue(store.commitInvestmentAssetImageMutation(after,request,device,"2026-10-24T01:00:00Z"))
        assertEquals(after,store.investmentAssetSnapshot(owner));assertEquals(queued,store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE))
    }
    @Test fun ordinaryAssetSaveCannotAttachAnUnstagedPrivatePath()=runBlocking {
        prepare();val before=store.investmentAssetSnapshot(owner)
        val path=InvestmentProductImagePath.create(owner,assetId,"66666666-6666-6666-6666-666666666666")
        val result=OfflineFirstInvestmentRepository(store).saveAsset(owner,draft().copy(imageChange=InvestmentAssetImageChange.Replace(path)),device,now)
        assertTrue("Image changes must use the reserved image boundary",result.isFailure)
        assertEquals(before,store.investmentAssetSnapshot(owner))
    }
    private fun imageRepo(source:LocalStore=store)=OfflineFirstInvestmentRepository(source,productImages=cache)
    private suspend fun staged()=imageRepo().stageProductImage(owner,assetId,PreparedInvestmentProductImage(jpeg(),jpeg(),"image/jpeg",8,4)).getOrThrow()
    private fun imageDraft(candidate:InvestmentProductImageCandidate,expected:InvestmentAssetRecord?=null)=draft(expected).copy(imageChange=InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,assetId,candidate.path)))
    @Test fun repositoryPromotesExactlyCommittedBytesAndRecoversALostRoomReply()=runBlocking {
        prepare();val candidate=staged()
        var loseReply=true
        val lost=object:LocalStore by store {
            override suspend fun commitInvestmentAssetImageMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetImageSaveRequest,deviceId:String,now:String):Boolean {
                val saved=store.commitInvestmentAssetImageMutation(expected,request,deviceId,now)
                if(loseReply){loseReply=false;throw java.io.IOException("synthetic lost reply")}
                return saved
            }
        }
        val saved=imageRepo(lost).saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        assertEquals(candidate.path,saved.imagePath)
        assertEquals(listOf(candidate),cache.pendingUploads(owner).getOrThrow())
        assertFalse(imageRepo().discardProductImage(owner,candidate).getOrThrow())
    }
    @Test fun repositoryRemovalWritesExplicitNullAndSurvivesAnExactRetry()=runBlocking {
        prepare();val candidate=staged()
        val original=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val removeRevision="77777777-7777-7777-7777-777777777777"
        val remove=draft(original).copy(imageChange=InvestmentAssetImageChange.Remove)
        val removed=imageRepo().saveAssetImage(owner,remove,null,removeRevision,device,now).getOrThrow()
        assertNull(removed.imagePath)
        val after=store.investmentAssetSnapshot(owner)
        assertEquals(removed,imageRepo().saveAssetImage(owner,remove,null,removeRevision,device,"2026-10-24T02:00:00Z").getOrThrow())
        assertEquals(after,store.investmentAssetSnapshot(owner))
        assertSame(JsonNull,store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE).single().mutation.payload!!["image_path"])
        assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
        assertTrue(cache.readyDeletions(owner).getOrThrow().isEmpty())
    }
    @Test fun lateQueueFailureRollsBackMetadataAndRetainsTheReservedCandidateForRetry()=runBlocking {
        prepare();val request=proposal();val before=store.investmentAssetSnapshot(owner)
        val queued=store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_image_queue BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'investment_assets' BEGIN SELECT RAISE(ABORT, 'image queue failed'); END")
        assertTrue(runCatching{store.commitInvestmentAssetImageMutation(before,request,device,now)}.isFailure)
        assertEquals(before,store.investmentAssetSnapshot(owner));assertEquals(queued,store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE))
        assertFalse(cache.discardCandidate(owner,request.publication.candidate!!).getOrThrow())
        assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
        db.openHelper.writableDatabase.execSQL("DROP TRIGGER reject_image_queue")
        assertTrue(store.commitInvestmentAssetImageMutation(before,request,device,now))
    }
    @Test fun snapshotRaceCannotReplaceANewerAsset()=runBlocking {
        prepare();val request=proposal();val before=store.investmentAssetSnapshot(owner)
        OfflineFirstInvestmentRepository(store).saveAsset(owner,draft().copy(name="Newer"),device,now).getOrThrow()
        val current=store.investmentAssetSnapshot(owner)
        assertFalse(store.commitInvestmentAssetImageMutation(before,request,device,now))
        assertEquals(current,store.investmentAssetSnapshot(owner));assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
    }
    @Test fun coherentPrimaryWithMissingQueueCannotBecomeAnAcceptedNoWriteRetry()=runBlocking {
        prepare();val request=proposal()
        assertTrue(store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now))
        db.openHelper.writableDatabase.execSQL("DELETE FROM sync_outbox WHERE entity = 'investment_assets'")
        val after=store.investmentAssetSnapshot(owner)
        val error=runCatching{store.commitInvestmentAssetImageMutation(after,request,device,now)}.exceptionOrNull()
        assertTrue(error is IllegalArgumentException);assertEquals("Asset image source has no outbox",error?.message)
        assertEquals(after,store.investmentAssetSnapshot(owner));assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
    }
    @Test fun candidateByteCorruptionPreventsRoomPublicationWithoutDiscardingUnknownFiles()=runBlocking {
        prepare();val request=proposal();val before=store.investmentAssetSnapshot(owner)
        val files=directory.walkTopDown().filter{it.isFile && it.extension=="jpg"}.toList()
        assertEquals(2,files.size);files.first().writeBytes(byteArrayOf(1,2,3))
        assertTrue(runCatching{store.commitInvestmentAssetImageMutation(before,request,device,now)}.isFailure)
        assertEquals(before,store.investmentAssetSnapshot(owner));assertEquals(2,directory.walkTopDown().count{it.isFile && it.extension=="jpg"})
    }

    private fun remote(download:suspend ()->ByteArray?)=object:InvestmentProductImageRemote {
        override suspend fun download(owner:UserId,assetId:String,path:String,isCurrent:()->Boolean)=Result.success(download())
        override suspend fun upload(owner:UserId,assetId:String,path:String,bytes:ByteArray,isCurrent:()->Boolean):Result<Unit> = error("Read must not upload")
        override suspend fun delete(owner:UserId,assetId:String,path:String,isCurrent:()->Boolean):Result<Unit> = error("Read must not delete")
    }
    @Test fun committedPhotoReadAndRestoredDraftPreviewUseOwnedDurableBytes()=runBlocking {
        prepare();val candidate=staged()
        assertArrayEquals(jpeg(),imageRepo().stagedProductImageData(owner,candidate).getOrThrow())
        imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        assertArrayEquals(jpeg(),imageRepo().productImageData(owner,assetId,candidate.path).getOrThrow())
        active=other
        assertTrue(runCatching{imageRepo().productImageData(owner,assetId,candidate.path)}.exceptionOrNull() is CancellationException)
    }
    @Test fun remoteImageIsCachedOnlyAfterRecheckingItsCurrentAssetReference()=runBlocking {
        prepare();val candidate=staged()
        val asset=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val freshCache=FileInvestmentProductImageCache(File(directory,"download-cache"),{active})
        var reads=0
        val reader=OfflineFirstInvestmentRepository(store,productImages=freshCache,productImageRemote=remote{reads++;jpeg()},productImageThumbnailer={jpeg()})
        assertArrayEquals(jpeg(),reader.productImageData(owner,assetId,candidate.path).getOrThrow())
        assertArrayEquals(jpeg(),reader.productImageData(owner,assetId,candidate.path,false).getOrThrow());assertEquals(1,reads)
        assertTrue(freshCache.pendingUploads(owner).getOrThrow().isEmpty())
        imageRepo().saveAssetImage(owner,draft(asset).copy(imageChange=InvestmentAssetImageChange.Remove),null,"77777777-7777-7777-7777-777777777777",device,now).getOrThrow()
        assertTrue(runCatching{reader.productImageData(owner,assetId,candidate.path)}.exceptionOrNull() is CancellationException)
    }
    @Test fun lateRemoteReplyCannotExposeOrCacheAPhotoRemovedWhileDownloading()=runBlocking {
        prepare();val candidate=staged()
        val asset=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val freshCache=FileInvestmentProductImageCache(File(directory,"download-cache"),{active})
        val reader=OfflineFirstInvestmentRepository(store,productImages=freshCache,productImageRemote=remote {
            imageRepo().saveAssetImage(owner,draft(asset).copy(imageChange=InvestmentAssetImageChange.Remove),null,"77777777-7777-7777-7777-777777777777",device,now).getOrThrow()
            jpeg()
        },productImageThumbnailer={jpeg()})
        assertTrue(runCatching{reader.productImageData(owner,assetId,candidate.path)}.exceptionOrNull() is CancellationException)
        assertNull(freshCache.cachedImageData(owner,assetId,candidate.path).getOrThrow())
    }

    @Test fun callerCancellationInsideTheLastOwnerFenceRollsBackImageMetadataAndOutbox()=runBlocking {
        prepare();val request=proposal();val before=store.investmentAssetSnapshot(owner)
        val queued=store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE)
        var work:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,productImages=cache,currentBillOwner={
            val inserted=db.openHelper.writableDatabase.query("SELECT COUNT(*) FROM cloud_records WHERE entity = 'investment_assets'").use{it.moveToFirst();it.getInt(0)>0}
            if(inserted)work!!.cancel(CancellationException("Last asset image fence"))
            active
        })
        work=async(start=CoroutineStart.LAZY){guarded.commitInvestmentAssetImageMutation(before,request,device,now)}
        work.start();assertTrue(runCatching{work.await()}.exceptionOrNull() is CancellationException)
        assertEquals(before,store.investmentAssetSnapshot(owner));assertEquals(queued,store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE))
        assertFalse(cache.discardCandidate(owner,request.publication.candidate!!).getOrThrow())
        assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
    }
    @Test fun aCallerCannotForgeAReservationByCopyingAnotherRevisionOntoARealCandidate()=runBlocking {
        prepare();val request=proposal();val before=store.investmentAssetSnapshot(owner)
        val forged=request.copy(publication=request.publication.copy(revision="77777777-7777-7777-7777-777777777777"))
        assertTrue(runCatching{store.commitInvestmentAssetImageMutation(before,forged,device,now)}.isFailure)
        assertEquals(before,store.investmentAssetSnapshot(owner));assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
    }

}
