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

    @Test fun freshRoomAuthorityRepairsACommittedButUnpromotedCandidateAfterRestart()=runBlocking {
        prepare();val request=proposal()
        assertTrue(store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now))
        assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
        val resumed=RoomLocalStore(db,currentBillOwner={active},productImages=FileInvestmentProductImageCache(directory,{active}))
        val state=resumed.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(request.publication,state.imagePublication);assertFalse(state.imageAcknowledged)
        assertEquals(listOf(request.publication.candidate),cache.pendingUploads(owner).getOrThrow())
        assertTrue(state.matches(store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE).single()))
    }
    @Test fun currentMarkerRepairsAnInterruptedChainWithoutPromotingTheOldRetryTicket()=runBlocking {
        prepare();val first=proposal()
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),first,device,now)
        val b=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
        val newer=cache.stage(owner,assetId,jpeg(),jpeg()).getOrThrow()
        val ticket=cache.reservePublication(owner,newer,b.imagePath,"77777777-7777-7777-7777-777777777777").getOrThrow()
        val request=InvestmentAssetImageSaveRequest(imageDraft(newer,b),ticket)
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now)
        val state=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(ticket,state.imagePublication);assertEquals(listOf(newer),cache.pendingUploads(owner).getOrThrow())
        assertFalse(cache.discardCandidate(owner,first.publication.candidate!!).getOrThrow())
    }
    @Test fun sameEffectRemovalRetryKeepsTheActualCurrentPublicationRevision()=runBlocking {
        prepare();val initial=proposal()
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),initial,device,now)
        val b=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
        val actual=cache.reserveRemoval(owner,assetId,b.imagePath,"77777777-7777-7777-7777-777777777777").getOrThrow()
        val removal=InvestmentAssetImageSaveRequest(draft(b).copy(imageChange=InvestmentAssetImageChange.Remove),actual)
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),removal,device,now)
        val old=cache.reserveRemoval(owner,assetId,b.imagePath,"88888888-8888-8888-8888-888888888888").getOrThrow()
        val retry=removal.copy(publication=old)
        assertTrue(store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),retry,device,now))
        val state=store.reconcileInvestmentAssetImagePublication(owner,assetId,retry)
        assertEquals(actual,state.imagePublication)
        assertFalse(cache.markUploadSucceeded(owner,initial.publication.candidate!!).getOrThrow())
    }
    @Test fun malformedOrUnqueuedCurrentIntentCannotPromoteAnyReservedBytes()=runBlocking {
        prepare();val request=proposal()
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now)
        db.openHelper.writableDatabase.execSQL("DELETE FROM sync_outbox WHERE entity = 'investment_assets'")
        assertTrue(runCatching{store.reconcileInvestmentAssetImagePublication(owner,assetId)}.isFailure)
        assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
    }
    @Test fun ownerChangeDuringReconciliationRetainsReservationAndDoesNotExposeAnotherOwner()=runBlocking {
        prepare();val request=proposal()
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now)
        active=other
        assertTrue(runCatching{store.reconcileInvestmentAssetImagePublication(owner,assetId)}.exceptionOrNull() is CancellationException)
        active=owner;assertTrue(cache.pendingUploads(owner).getOrThrow().isEmpty())
    }

    private suspend fun removeLocalIntentForLegacyFixture() {
        val raw=store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!
        val payload=assetPayloadForCloud(raw.payload).toString()
        for(table in listOf("cloud_records","sync_outbox"))db.openHelper.writableDatabase.execSQL(
            "UPDATE $table SET payload_json = ? WHERE owner_user_id = ? AND entity = 'investment_assets' AND record_id = ?",arrayOf(payload,owner.value,assetId))
    }
    @Test fun legacyUniqueReservedReplacementCanBeRecoveredFromItsActuallyReferencedPath()=runBlocking {
        prepare();val request=proposal()
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now)
        removeLocalIntentForLegacyFixture()
        val state=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(request.publication,state.imagePublication)
        assertEquals(listOf(request.publication.candidate),cache.pendingUploads(owner).getOrThrow())
    }
    @Test fun unmarkedLegacyNullReservationIsHeldUntilAnExplicitKnownResultRetry()=runBlocking {
        prepare();val candidate=staged()
        val initial=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val ticket=cache.reserveRemoval(owner,assetId,initial.imagePath,"77777777-7777-7777-7777-777777777777").getOrThrow()
        val request=InvestmentAssetImageSaveRequest(draft(initial).copy(imageChange=InvestmentAssetImageChange.Remove),ticket)
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),request,device,now)
        removeLocalIntentForLegacyFixture()
        val before=store.investmentAssetSnapshot(owner)
        assertTrue(runCatching{store.reconcileInvestmentAssetImagePublication(owner,assetId)}.isFailure)
        assertEquals(before,store.investmentAssetSnapshot(owner))
        val repaired=store.reconcileInvestmentAssetImagePublication(owner,assetId,request)
        assertEquals(ticket,repaired.imagePublication);assertFalse(repaired.imageAcknowledged)
        assertEquals(before,store.investmentAssetSnapshot(owner))
    }
    @Test fun acknowledgedPhotoIntentAcrossALaterRenameIsRecognizedAsKeep()=runBlocking {
        prepare();val candidate=staged()
        val original=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        assertTrue(cache.markUploadSucceeded(owner,candidate).getOrThrow())
        val ticket=store.reconcileInvestmentAssetImagePublication(owner,assetId).imagePublication!!
        assertTrue(cache.acknowledgePublished(owner,ticket).getOrThrow())
        imageRepo().saveAsset(owner,draft(original).copy(name="Renamed"),device,now).getOrThrow()
        val state=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(ticket,state.imagePublication);assertTrue(state.imageAcknowledged)
        assertEquals("Renamed",InvestmentAssetRecord.fromCloudRecord(state.record!!).name)
    }

    private fun serverResult(raw:CloudRecord,version:Long=9007199254740993L)=raw.copy(syncVersion=version,
        payload=JsonObject(assetPayloadForCloud(raw.payload)+("sync_version" to JsonPrimitive(version))))
    @Test fun assetAckStripsLocalIntentAndClearsOnlyTheExactPrimaryQueue()=runBlocking {
        prepare();val candidate=staged()
        imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        val others=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)
        assertTrue(cache.markUploadSucceeded(owner,candidate).getOrThrow())
        val remote=serverResult(source.record!!)
        assertTrue(store.acknowledgeInvestmentAssetMutation(source.pending!!,remote,source.imagePublication))
        val after=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(remote,after.record);assertNull(after.pending);assertFalse(after.hasPendingMutation)
        assertTrue(after.imageAcknowledged);assertEquals(others,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE))
    }
    @Test fun lateAssetAckMayAcknowledgeTheSamePhotoButCannotEraseALaterRename()=runBlocking {
        prepare();val candidate=staged()
        val asset=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        cache.markUploadSucceeded(owner,candidate).getOrThrow()
        imageRepo().saveAsset(owner,draft(asset).copy(name="Later name"),device,"2026-10-24T01:00:00Z").getOrThrow()
        val newer=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertFalse(store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!),source.imagePublication))
        val after=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(newer.record,after.record);assertEquals(newer.pending,after.pending);assertTrue(after.imageAcknowledged)
    }
    @Test fun oldAssetAckCannotAcknowledgeANewerPhotoRevisionOrAnUnuploadedCandidate()=runBlocking {
        prepare();val candidate=staged()
        val asset=imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertFalse(store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!),source.imagePublication))
        cache.markUploadSucceeded(owner,candidate).getOrThrow()
        val c=staged()
        imageRepo().saveAssetImage(owner,imageDraft(c,asset),c,"77777777-7777-7777-7777-777777777777",device,now).getOrThrow()
        val current=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertFalse(store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!),source.imagePublication))
        val after=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(current,after);assertFalse(after.imageAcknowledged);assertTrue(cache.readyDeletions(owner).getOrThrow().isEmpty())
    }
    @Test fun assetFailureUsesOnlyItsExactCurrentQueueAndRedactedCodes()=runBlocking {
        prepare();imageRepo().saveAsset(owner,draft(),device,now).getOrThrow()
        val source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertTrue(store.recordInvestmentAssetMutationFailure(source.pending!!,34000,"network_io"))
        val current=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(source.record,current.record);assertEquals(1,current.pending!!.attemptCount)
        assertFalse(store.recordInvestmentAssetMutationFailure(source.pending!!,Long.MAX_VALUE,"old_error"))
        assertTrue(runCatching{store.recordInvestmentAssetMutationFailure(current.pending!!,Long.MAX_VALUE,"private body")} .isFailure)
    }

    @Test fun omittingThePublicationTicketCannotBypassTheActualUploadProof()=runBlocking {
        prepare();val candidate=staged()
        imageRepo().saveAssetImage(owner,imageDraft(candidate),candidate,revision,device,now).getOrThrow()
        val source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertFalse(store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!)))
        assertEquals(source,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }

    private suspend fun readyOldImage():Pair<InvestmentProductImageCandidate,InvestmentProductImageCandidate> {
        prepare();val b=staged()
        val first=imageRepo().saveAssetImage(owner,imageDraft(b),b,revision,device,now).getOrThrow()
        cache.markUploadSucceeded(owner,b).getOrThrow()
        var source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!,1),source.imagePublication)
        val current=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
        val c=staged()
        imageRepo().saveAssetImage(owner,imageDraft(c,current),c,"77777777-7777-7777-7777-777777777777",device,now).getOrThrow()
        cache.markUploadSucceeded(owner,c).getOrThrow()
        source=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!,2),source.imagePublication)
        assertEquals(listOf(b.path),cache.readyDeletions(owner).getOrThrow())
        return b to c
    }
    private fun deleting(action:suspend (String,()->Boolean)->Unit)=object:InvestmentProductImageRemote {
        override suspend fun delete(owner:UserId,assetId:String,path:String,isCurrent:()->Boolean):Result<Unit> {
            return try{action(path,isCurrent);Result.success(Unit)}catch(error:Exception){Result.failure(error)}
        }
        override suspend fun upload(owner:UserId,assetId:String,path:String,bytes:ByteArray,isCurrent:()->Boolean):Result<Unit> = error("Cleanup must not upload")
        override suspend fun download(owner:UserId,assetId:String,path:String,isCurrent:()->Boolean):Result<ByteArray?> = error("Cleanup must not download")
    }
    @Test fun imageDeletionRunsOnlyAfterAckAndFreshRoomReferenceChecks()=runBlocking {
        val (b,c)=readyOldImage();val deleted=mutableListOf<String>()
        assertEquals(1,store.cleanupInvestmentProductImages(owner,deleting{path,current->assertTrue(current());deleted.add(path)}))
        assertEquals(listOf(b.path),deleted);assertTrue(cache.readyDeletions(owner).getOrThrow().isEmpty())
        assertTrue(cache.imageData(owner,b).isFailure);assertArrayEquals(jpeg(),cache.imageData(owner,c).getOrThrow())
    }
    @Test fun aSoftDeletedAssetStillReferencingAnOldPhotoPinsThatObjectForRestore()=runBlocking {
        val (b,_)=readyOldImage()
        db.openHelper.writableDatabase.execSQL("UPDATE cloud_records SET payload_json = json_set(payload_json, '$.image_path', ?, '$.deleted_at', ?), deleted_at = ? WHERE entity = 'investment_assets'",arrayOf(b.path,now,now))
        assertEquals(0,store.cleanupInvestmentProductImages(owner,deleting{_,_->error("Restorable photo must stay pinned")}))
        assertEquals(listOf(b.path),cache.readyDeletions(owner).getOrThrow());assertArrayEquals(jpeg(),cache.imageData(owner,b).getOrThrow())
    }
    @Test fun failedOrLateCrossAccountDeletionRetainsReadyAuthorityAndLocalBytes()=runBlocking {
        val (b,_)=readyOldImage()
        assertTrue(runCatching{store.cleanupInvestmentProductImages(owner,deleting{_,_->throw java.io.IOException("synthetic deletion failure")})}.isFailure)
        assertEquals(listOf(b.path),cache.readyDeletions(owner).getOrThrow())
        assertTrue(runCatching{store.cleanupInvestmentProductImages(owner,deleting{_,_->active=other})}.exceptionOrNull() is CancellationException)
        active=owner
        assertEquals(listOf(b.path),cache.readyDeletions(owner).getOrThrow());assertArrayEquals(jpeg(),cache.imageData(owner,b).getOrThrow())
        assertEquals(1,store.cleanupInvestmentProductImages(owner,deleting{_,current->assertTrue(current())}))
    }

    @Test fun oldEquivalentRemovalRetryCannotReactivateAConfirmedPhotoAfterAnOrdinaryResave()=runBlocking {
        prepare();val b=staged()
        val original=imageRepo().saveAssetImage(owner,imageDraft(b),b,revision,device,now).getOrThrow()
        val removeDraft=draft(original).copy(imageChange=InvestmentAssetImageChange.Remove)
        val removed=imageRepo().saveAssetImage(owner,removeDraft,null,"77777777-7777-7777-7777-777777777777",device,now).getOrThrow()
        val published=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertTrue(store.acknowledgeInvestmentAssetMutation(published.pending!!,serverResult(published.record!!,1),published.imagePublication))
        val acknowledged=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
        imageRepo().saveAsset(owner,draft(acknowledged),device,"2026-10-24T02:00:00Z").getOrThrow()
        val before=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertTrue(before.imageAcknowledged)
        imageRepo().saveAssetImage(owner,removeDraft,null,"88888888-8888-8888-8888-888888888888",device,now).getOrThrow()
        val after=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertEquals(before,after);assertTrue(after.imageAcknowledged)
        assertEquals(published.imagePublication,after.imagePublication)
    }
    @Test fun aNewReplacementCanRecoverWhenItsUnpromotedAncestorsLocalBytesAreLost()=runBlocking {
        prepare();val first=proposal()
        store.commitInvestmentAssetImageMutation(store.investmentAssetSnapshot(owner),first,device,now)
        val original=InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,assetId)!!)
        val objectName=first.publication.path!!.substringAfterLast('/')
        val oldFiles=directory.walkTopDown().filter{it.isFile && it.name==objectName}.toList()
        assertEquals(2,oldFiles.size);oldFiles.forEach{assertTrue(it.delete())}
        val c=staged()
        val saved=imageRepo().saveAssetImage(owner,imageDraft(c,original),c,"77777777-7777-7777-7777-777777777777",device,now).getOrThrow()
        assertEquals(c.path,saved.imagePath)
        assertEquals(listOf(c),cache.pendingUploads(owner).getOrThrow())
        assertArrayEquals(jpeg(),cache.imageData(owner,c).getOrThrow());assertTrue(cache.readyDeletions(owner).getOrThrow().isEmpty())
    }

    private suspend fun plainPublication():InvestmentAssetPublicationSnapshot {
        prepare();imageRepo().saveAsset(owner,draft(),device,now).getOrThrow()
        return store.reconcileInvestmentAssetImagePublication(owner,assetId)
    }
    @Test fun ownerReplacementRevokesAssetAckAndFailureBeforeAnyOldOwnerDatabaseWrite()=runBlocking {
        val source=plainPublication();val result=serverResult(source.record!!,1)
        active=other
        assertTrue(runCatching{store.acknowledgeInvestmentAssetMutation(source.pending!!,result)}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{store.recordInvestmentAssetMutationFailure(source.pending!!,34000,"network_io")}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(source,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun finalCallerCancellationRollsBackAppliedAssetAckAndQueueDeletion()=runBlocking {
        val source=plainPublication();val result=serverResult(source.record!!,1)
        var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,productImages=cache,currentBillOwner={
            val version=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE entity = 'investment_assets'").use{it.moveToFirst();it.getLong(0)}
            if(version>0)task!!.cancel(CancellationException("Final asset ACK fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.acknowledgeInvestmentAssetMutation(source.pending!!,result)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        assertEquals(source,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun aLateDatabaseFailureRestoresTheExactAssetQueueInTheAckTransaction()=runBlocking {
        val source=plainPublication();val result=serverResult(source.record!!,1)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_asset_ack BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_assets' BEGIN SELECT RAISE(ABORT, 'synthetic asset ACK failure'); END")
        assertTrue(runCatching{store.acknowledgeInvestmentAssetMutation(source.pending!!,result)}.isFailure)
        assertEquals(source,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun primaryAssetAckCannotConsumeDirtyTradeCashOrPostingQueues()=runBlocking {
        val source=plainPublication()
        val domains=listOf(CloudEntity.INVESTMENT_TRADE,CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING)
        for((index,entity) in domains.withIndex()) {
            val identity="%08d-8888-8888-8888-888888888888".format(index+1)
            val payload=buildJsonObject{put("id",identity);put("user_id",owner.value);put("asset_id",assetId);put("updated_at",now);put("sync_version",0);put("deleted_at",JsonNull);put("future_marker","keep")}.toString()
            db.cloudRecordDao().upsert(CloudRecordEntity(owner.value,entity.table,identity,payload,now,null,0,true,0))
            db.syncOutboxDao().upsert(SyncOutboxEntity(owner.value,entity.table,identity,"upsert",payload,now,0,device))
        }
        val queues=domains.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
        val rows=domains.associateWith{store.recordsIncludingDeleted(owner,it.table)}
        assertTrue(store.acknowledgeInvestmentAssetMutation(source.pending!!,serverResult(source.record!!,1)))
        assertEquals(queues,domains.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)})
        assertEquals(rows,domains.associateWith{store.recordsIncludingDeleted(owner,it.table)})
    }

    private data class ReceiptFixture(val old:InvestmentAssetPublicationSnapshot,val sent:JsonObject,val remote:CloudRecord)
    private suspend fun receiptFixture():ReceiptFixture {
        val old=plainPublication();val oldRecord=requireNotNull(old.record)
        val asset=InvestmentAssetRecord.fromCloudRecord(oldRecord)
        imageRepo().saveAsset(owner,draft(asset).copy(name="Newer"),device,"2026-10-24T00:15:00Z").getOrThrow()
        val current=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertTrue(store.recordInvestmentAssetMutationFailure(current.pending!!,12345,"network_io"))
        val sent=JsonObject(assetPayloadForCloud(oldRecord.payload)+("sync_version" to JsonPrimitive(8)))
        val remote=serverResult(oldRecord,8)
        return ReceiptFixture(old,sent,remote)
    }
    @Test fun confirmedReceiptAtomicallyAddsOnlyEvidenceAndPreservesEveryNewQueueStamp()=runBlocking {
        val f=receiptFixture();val before=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        val storedBefore=db.cloudRecordDao().record(owner.value,CloudEntity.INVESTMENT_ASSET.table,assetId)!!
        assertTrue(store.recordInvestmentAssetPublicationReceipt(f.old.pending!!,f.sent,7,f.remote))
        val after=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        val afterRecord=requireNotNull(after.record);val beforeQueue=requireNotNull(before.pending)
        assertEquals(assetPayloadForCloud(before.record!!.payload),assetPayloadForCloud(afterRecord.payload))
        assertEquals(beforeQueue.copy(mutation=beforeQueue.mutation.copy(payload=afterRecord.payload)),after.pending)
        assertTrue(after.matches(after.pending!!));assertTrue(after.hasPendingMutation)
        assertTrue(isKnownPriorAssetPublication(afterRecord,f.remote,device,false))
        assertEquals(storedBefore.copy(payloadJson=afterRecord.payload.toString()),db.cloudRecordDao().record(owner.value,CloudEntity.INVESTMENT_ASSET.table,assetId))
    }
    @Test fun receiptCannotBeLaunderedFromAnUnrelatedPayloadOrServerVersion()=runBlocking {
        val f=receiptFixture();val before=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        assertTrue(runCatching{store.recordInvestmentAssetPublicationReceipt(f.old.pending!!,JsonObject(f.sent+("name" to JsonPrimitive("Forged"))),7,f.remote)}.isFailure)
        assertTrue(runCatching{store.recordInvestmentAssetPublicationReceipt(f.old.pending!!,f.sent,6,f.remote)}.isFailure)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun receiptRevokesTheOldOwnerBeforeWritingAnything()=runBlocking {
        val f=receiptFixture();val before=store.reconcileInvestmentAssetImagePublication(owner,assetId);active=other
        assertTrue(runCatching{store.recordInvestmentAssetPublicationReceipt(f.old.pending!!,f.sent,7,f.remote)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun receiptQueueInsertFailureRollsBackTheAlreadyUpdatedRow()=runBlocking {
        val f=receiptFixture();val before=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_receipt_queue BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'investment_assets' BEGIN SELECT RAISE(ABORT, 'receipt queue failure'); END")
        assertTrue(runCatching{store.recordInvestmentAssetPublicationReceipt(f.old.pending!!,f.sent,7,f.remote)}.isFailure)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun finalReceiptCallerCancellationRollsBackBothEvidenceWrites()=runBlocking {
        val f=receiptFixture();val before=store.reconcileInvestmentAssetImagePublication(owner,assetId)
        val oldPayload=before.record!!.payload.toString();var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,productImages=cache,currentBillOwner={
            val payload=db.openHelper.writableDatabase.query("SELECT payload_json FROM cloud_records WHERE entity = 'investment_assets'").use{it.moveToFirst();it.getString(0)}
            if(payload!=oldPayload)task!!.cancel(CancellationException("Final receipt fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.recordInvestmentAssetPublicationReceipt(f.old.pending!!,f.sent,7,f.remote)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }
    @Test fun cloudAcknowledgementCannotImportForgedLocalCausalEvidence()=runBlocking {
        val f=plainPublication();val remote=serverResult(f.record!!,1)
        val forged=remote.copy(payload=JsonObject(remote.payload+(LOCAL_ASSET_PUBLICATION_PARENTS_KEY to JsonNull)))
        assertTrue(runCatching{store.acknowledgeInvestmentAssetMutation(f.pending!!,forged)}.isFailure)
        assertEquals(f,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }

    @Test fun finalSessionRotationRollsBackAssetAcknowledgement()=runBlocking {
        val source=plainPublication();val before=source;val result=serverResult(source.record!!,1)
        var sawApplied=false
        val error=runCatching{store.acknowledgeInvestmentAssetMutation(source.pending!!,result,isSessionCurrent={
            val value=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE entity = 'investment_assets'").use{it.moveToFirst();it.getLong(0)}
            if(!(value==0L))sawApplied=true
            value==0L
        })}.exceptionOrNull()
        assertTrue("Session fence must observe the applied write before rollback",sawApplied)
        assertTrue(error is CancellationException)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }

    @Test fun finalSessionRotationRollsBackAssetFailureBookkeeping()=runBlocking {
        val source=plainPublication();val before=source;val result=serverResult(source.record!!,1)
        var sawApplied=false
        val error=runCatching{store.recordInvestmentAssetMutationFailure(source.pending!!,34000,"network_io",isSessionCurrent={
            val value=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE entity = 'investment_assets'").use{it.moveToFirst();it.getLong(0)}
            if(!(value==0L))sawApplied=true
            value==0L
        })}.exceptionOrNull()
        assertTrue("Session fence must observe the applied write before rollback",sawApplied)
        assertTrue(error is CancellationException)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }

    @Test fun finalSessionRotationRollsBackAssetReceipt()=runBlocking {
        val f=receiptFixture();val before=store.reconcileInvestmentAssetImagePublication(owner,assetId);val oldPayload=before.record!!.payload.toString()
        var sawApplied=false
        val error=runCatching{store.recordInvestmentAssetPublicationReceipt(f.old.pending!!,f.sent,7,f.remote,isSessionCurrent={
            val value=db.openHelper.writableDatabase.query("SELECT payload_json FROM cloud_records WHERE entity = 'investment_assets'").use{it.moveToFirst();it.getString(0)}
            if(!(value==oldPayload))sawApplied=true
            value==oldPayload
        })}.exceptionOrNull()
        assertTrue("Session fence must observe the applied write before rollback",sawApplied)
        assertTrue(error is CancellationException)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,assetId))
    }

}
