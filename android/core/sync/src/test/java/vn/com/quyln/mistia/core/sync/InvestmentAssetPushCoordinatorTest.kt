package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import vn.com.quyln.mistia.core.database.FileInvestmentProductImageCache
import vn.com.quyln.mistia.core.model.*

class InvestmentAssetPushCoordinatorTest {
    @get:Rule val temporary=TemporaryFolder()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val token="asset-token"
    private val now="2026-10-24T00:00:00Z"
    private var session:AuthSession?=AuthSession(owner,null,token,"refresh",Long.MAX_VALUE)
    private fun record(version:Long=0,name:String="Cards",date:String=now)=InvestmentAssetRecord(id,owner.value,"44444444-4444-4444-4444-444444444444",name,"VND",null,"box",0,false,null,now,date,null,version,device)
        .toCloudRecord().let{it.copy(payload=JsonObject(it.payload+("future_null" to JsonNull)))}
    private fun otherDevice(row:CloudRecord)=row.copy(payload=JsonObject(row.payload+("last_modified_by_device_id" to JsonPrimitive("99999999-9999-9999-9999-999999999999"))))
    private fun queue(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_ASSET,row.id,row.ownerUserId,
        if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device),0,0,null)
    private fun coordinator(store:Store,remote:Remote,enabled:Boolean=true)=InvestmentAssetPushCoordinator(store,remote,enabled,{session},{4000})
    @Test fun channelCreatePublishesMetadataAndAcknowledgesOnlyItsExactQueue()=runTest {
        val original=record();val store=Store(original,queue(original));val remote=Remote().apply{created=record(1)}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.pushed);assertEquals(record(1),store.record);assertNull(store.queued)
        assertEquals(1L,remote.createdPayload!!.financeRawLong("sync_version"));assertSame(JsonNull,remote.createdPayload!!["future_null"])
    }
    @Test fun semanticAcknowledgementUsesTheServerVersionWithoutAnotherWrite()=runTest {
        val row=record(3);val store=Store(row,queue(row));val remote=Remote().apply{fetched=record(7)}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.acknowledged);assertEquals(0,remote.writes);assertEquals(7L,store.record!!.syncVersion);assertNull(store.queued)
    }
    @Test fun disabledGateDoesNotFetchWriteAcknowledgeOrRecordFailure()=runTest {
        val row=record();val q=queue(row);val store=Store(row,q);val remote=Remote()
        val result=coordinator(store,remote,false).pushPending(owner,token)
        assertEquals(DomainPushSummary(),result);assertEquals(0,remote.fetches);assertEquals(0,remote.writes)
        assertEquals(row,store.record);assertEquals(q,store.queued)
    }
    @Test fun accountReplacementDuringFetchPreventsAWriteAndFailureBookkeeping()=runTest {
        val row=record();val q=queue(row);val store=Store(row,q)
        val remote=Remote().apply{onFetch={session=AuthSession(UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),null,"other-token","refresh",Long.MAX_VALUE)}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(0,remote.writes);assertEquals(row,store.record);assertEquals(q,store.queued)
    }
    @Test fun lateCreateResponseCannotEraseANewerNameAndQueue()=runTest {
        val row=record();val store=Store(row,queue(row));val newer=record(name="Newer",date="2026-10-24T01:00:00Z")
        val remote=Remote().apply{created=record(1);onCreate={store.record=newer;store.queued=queue(newer)}}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.staleResponses);assertEquals(newer,store.record);assertEquals(queue(newer),store.queued)
    }

    @Test fun aRowChangedWithoutUpdatingItsQueueIsHeldBeforeTheFirstRemoteRequest()=runTest {
        val old=record();val changed=record(name="Unqueued newer")
        val store=Store(changed,queue(old));val remote=Remote()
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).staleResponses)
        assertEquals(0,remote.fetches);assertEquals(0,remote.writes);assertEquals(changed,store.record);assertEquals(queue(old),store.queued)
    }
    @Test fun aQueueReplacementDuringFetchRevokesTheOldConditionalWrite()=runTest {
        val row=record(3);val old=queue(row);val newer=old.copy(attemptCount=1)
        val store=Store(row,old);val remote=Remote().apply{fetched=record(3,name="Before");onFetch={store.queued=newer}}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).staleResponses)
        assertEquals(0,remote.writes);assertEquals(newer,store.queued)
    }
    @Test fun sameOwnerTokenRotationAlsoRevokesTheOldWrite()=runTest {
        val row=record();val q=queue(row);val store=Store(row,q)
        val remote=Remote().apply{onFetch={session=session!!.copy(accessToken="rotated")}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(0,remote.writes);assertEquals(q,store.queued)
    }
    @Test fun retryableIoFailureRecordsOnlyTheSafeCodeAndExactBackoff()=runTest {
        val row=record();val store=Store(row,queue(row));val remote=Remote().apply{fetchError=java.io.IOException("private backend message")}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.retryableFailures);assertEquals(row,store.record)
        assertEquals(1,store.queued!!.attemptCount);assertEquals(34000L,store.queued!!.nextAttemptAtEpochMillis);assertEquals("network_io",store.queued!!.lastError)
    }
    @Test fun accountChangeAlongsideIoFailureCannotMarkTheOldOwnersQueueFailed()=runTest {
        val row=record();val q=queue(row);val store=Store(row,q)
        val remote=Remote().apply{fetchError=java.io.IOException("private");onFetch={session=null}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(q,store.queued);assertEquals(row,store.record)
    }
    @Test fun cancellationNeverBecomesPermanentFailureBookkeeping()=runTest {
        val row=record();val q=queue(row);val store=Store(row,q);val remote=Remote().apply{fetchError=CancellationException("cancelled")}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(q,store.queued);assertEquals(row,store.record)
    }
    @Test fun localWinnerComparesTheRemoteBaseButPublishesBeyondTheHigherLocalVersion()=runTest {
        val row=record(11);val store=Store(row,queue(row))
        val remote=Remote().apply{fetched=record(7,"Before","2026-10-23T00:00:00Z");updated=record(12)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(7L,remote.updateExpected);assertEquals(12L,remote.updatedPayload!!.financeRawLong("sync_version"));assertNull(store.queued);assertEquals(record(12),store.record)
    }
    @Test fun equalClockAndVersionDifferentContentRemainsAnExplicitConflict()=runTest {
        val row=record();val store=Store(row,queue(row));val remote=Remote().apply{fetched=record(0,"Different")}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).conflicts)
        assertEquals(row,store.record);assertEquals(Long.MAX_VALUE,store.queued!!.nextAttemptAtEpochMillis)
        assertEquals("conflict_same_clock_version_different_payload",store.queued!!.lastError);assertEquals(0,remote.writes)
    }
    @Test fun anUnprovenOwnLaterClockCannotSilentlyConsumeTheCurrentProposal()=runTest {
        val row=record(3);val store=Store(row,queue(row));val remote=Remote().apply{fetched=record(4,"Prior","2026-10-24T01:00:00Z")}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.conflicts);assertEquals(row,store.record);assertEquals(0,remote.writes)
        assertEquals("conflict_own_unproven_publication",store.queued!!.lastError)
    }
    @Test fun newerRemoteMetadataWinsWithoutAWriteOrAStaleLocalQueue()=runTest {
        val row=record(3);val winner=otherDevice(record(4,"Remote","2026-10-24T01:00:00Z"))
        val store=Store(row,queue(row));val remote=Remote().apply{fetched=winner}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(winner,store.record);assertNull(store.queued);assertEquals(0,remote.writes)
    }
    @Test fun createCollisionRefetchesAndAcknowledgesOnlyTheOwnedWinner()=runTest {
        val row=record();val store=Store(row,queue(row));val remote=Remote().apply{
            fetchSequence.addAll(listOf(null,record(1)));createError=vn.com.quyln.mistia.core.network.SupabaseHttpException(409,"")
        }
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(2,remote.fetches);assertEquals(1,remote.writes);assertEquals(record(1),store.record);assertNull(store.queued)
    }
    @Test fun conditionalMissRefetchesTheWinningVersionInsteadOfAcknowledgingANullReply()=runTest {
        val row=record(3);val winner=otherDevice(record(4,"Remote","2026-10-24T01:00:00Z"));val store=Store(row,queue(row))
        val remote=Remote().apply{fetchSequence.addAll(listOf(record(3,"Before"),winner))}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(winner,store.record);assertNull(store.queued);assertEquals(1,remote.writes)
    }
    @Test fun foreignRemoteIdentityCannotReplaceTheOwnedRecordOrClearItsQueue()=runTest {
        val row=record();val store=Store(row,queue(row))
        val remote=Remote().apply{fetched=record(1).let{it.copy(ownerUserId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",payload=JsonObject(it.payload+("user_id" to JsonPrimitive("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))))}}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).permanentFailures)
        assertEquals(row,store.record);assertEquals("invalid_mutation",store.queued!!.lastError);assertEquals(0,remote.writes)
    }
    @Test fun equivalentArchivedInstantAcknowledgesAnOlderClockWithoutAnUnnecessaryWrite()=runTest {
        val local=record(3,date="2026-10-24T02:00:00Z").let{it.copy(payload=JsonObject(it.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(now))))}
        val server=record(4).let{it.copy(payload=JsonObject(it.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive("2026-10-24T00:00:00.000+00:00"))))}
        val store=Store(local,queue(local));val remote=Remote().apply{fetched=server}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(0,remote.writes);assertEquals(server,store.record);assertNull(store.queued)
    }
    @Test fun aRealArchivedInstantChangeStillPublishesTheLaterLocalProposal()=runTest {
        val local=record(3,date="2026-10-24T02:00:00Z").let{it.copy(payload=JsonObject(it.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(now))))}
        val server=record(4).let{it.copy(payload=JsonObject(it.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive("2026-10-23T23:59:59Z"))))}
        val saved=local.copy(syncVersion=5,payload=JsonObject(local.payload+("sync_version" to JsonPrimitive(5))))
        val store=Store(local,queue(local));val remote=Remote().apply{fetched=server;updated=saved}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(1,remote.writes);assertEquals(4L,remote.updateExpected)
        assertEquals(JsonPrimitive(now),remote.updatedPayload!!["archived_at"]);assertEquals(saved,store.record);assertNull(store.queued)
    }
    private fun withImage(row:CloudRecord,path:String?)=row.copy(payload=JsonObject(row.payload+("image_path" to (path?.let(::JsonPrimitive) ?: JsonNull))))
    private val oldImage get()=InvestmentProductImagePath.create(owner,id,"55555555-5555-5555-5555-555555555555").value
    private val remoteImage get()=InvestmentProductImagePath.create(owner,id,"66666666-6666-6666-6666-666666666666").value
    private val imageBytes=byteArrayOf(0xff.toByte(),0xd8.toByte(),42,0xff.toByte(),0xd9.toByte())
    private data class PhotoFixture(val cache:FileInvestmentProductImageCache,val publication:InvestmentProductImagePublication,val row:CloudRecord,val store:Store)
    private suspend fun photo(remove:Boolean=false):PhotoFixture {
        val cache=FileInvestmentProductImageCache(temporary.newFolder(),{session?.userId})
        val baseline=withImage(record(3),if(remove)oldImage else null)
        val typed=InvestmentAssetRecord.fromCloudRecord(baseline)
        val pub=if(remove)cache.reserveRemoval(owner,id,oldImage,"77777777-7777-7777-7777-777777777777").getOrThrow()
            else cache.reservePublication(owner,cache.stage(owner,id,imageBytes,imageBytes).getOrThrow(),null,"77777777-7777-7777-7777-777777777777").getOrThrow()
        val draft=InvestmentAssetDraft(id,typed.channelId,typed.name,typed.currencyCode,"box",typed,
            if(remove)InvestmentAssetImageChange.Remove else InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,id,pub.path!!)))
        val channel=InvestmentChannelRecord(typed.channelId,owner.value,"Shop","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,1,device).toCloudRecord()
        val raw=planInvestmentAssetImageSave(InvestmentAssetSnapshot(owner,listOf(channel,baseline)),InvestmentAssetImageSaveRequest(draft,pub),device,now).mutations.single().first
        cache.markLocalPublished(owner,pub).getOrThrow()
        return PhotoFixture(cache,pub,raw,Store(raw,queue(raw)).apply{publication=pub})
    }
    private fun cloud(row:CloudRecord)=row.copy(payload=JsonObject(assetPayloadForCloud(row.payload)+("sync_version" to JsonPrimitive(4))),syncVersion=4)
    private class ImageRemote(val uploadAction:suspend ()->Unit):InvestmentProductImageRemote {
        var uploads=0;var bytes:ByteArray?=null
        override suspend fun upload(owner:UserId,assetId:String,path:String,bytes:ByteArray,isCurrent:()->Boolean):Result<Unit> {
            uploads++;this.bytes=bytes.copyOf();assertTrue(isCurrent())
            return try{uploadAction();Result.success(Unit)}catch(error:Exception){Result.failure(error)}
        }
        override suspend fun download(owner:UserId,assetId:String,path:String,isCurrent:()->Boolean):Result<ByteArray?> = error("Coordinator must not bypass the image service upload collision policy")
        override suspend fun delete(owner:UserId,assetId:String,path:String,isCurrent:()->Boolean):Result<Unit> = error("Cleanup must use a fresh Room reference guard")
    }
    private fun photos(f:PhotoFixture,remote:Remote,service:ImageRemote)=InvestmentAssetPushCoordinator(f.store,remote,true,{session},{4000},f.cache,service)
    @Test fun explicitReplacementUploadsExactBytesBeforeTheAtomicAssetWrite()=runTest {
        val f=photo();val events=mutableListOf<String>()
        val service=ImageRemote{events.add("image-upload")}
        val remote=Remote().apply{fetched=record(3);updated=cloud(f.row);onFetch={events.add("asset-get")};onUpdate={events.add("asset-rpc")}}
        assertEquals(1,photos(f,remote,service).pushPending(owner,token).pushed)
        assertEquals(listOf("asset-get","image-upload","asset-rpc"),events)
        assertArrayEquals(imageBytes,service.bytes);assertEquals(f.publication.path,remote.updatedPayload!!.financeRawString("image_path"))
        assertFalse(LOCAL_ASSET_IMAGE_INTENT_KEY in remote.updatedPayload!!)
        assertTrue(f.cache.pendingUploads(owner).getOrThrow().isEmpty());assertNull(f.store.queued);assertEquals(1,f.store.cleanups)
    }
    @Test fun uploadFailureCannotSendMetadataOrAcknowledgeThePendingPhoto()=runTest {
        val f=photo();val service=ImageRemote{throw java.io.IOException("private upload error")}
        val remote=Remote().apply{fetched=record(3);updated=cloud(f.row)}
        assertEquals(1,photos(f,remote,service).pushPending(owner,token).retryableFailures)
        assertEquals(0,remote.writes);assertEquals("network_io",f.store.queued!!.lastError)
        assertEquals(listOf(f.publication.candidate),f.cache.pendingUploads(owner).getOrThrow())
    }
    @Test fun aSourceChangeDuringUploadHoldsTheOldMetadataAndRetainsTheNewQueue()=runTest {
        val f=photo();val newer=f.row.copy(payload=JsonObject(f.row.payload+("name" to JsonPrimitive("Later name"))))
        val service=ImageRemote{f.store.record=newer;f.store.queued=queue(newer)}
        val remote=Remote().apply{fetched=record(3);updated=cloud(f.row)}
        assertEquals(1,photos(f,remote,service).pushPending(owner,token).staleResponses)
        assertEquals(0,remote.writes);assertEquals(newer,f.store.record);assertEquals(queue(newer),f.store.queued)
    }
    @Test fun aSessionChangeDuringUploadCannotReachTheAssetRpcOrBookkeeping()=runTest {
        val f=photo();val original=f.store.queued
        val service=ImageRemote{session=null}
        val remote=Remote().apply{fetched=record(3);updated=cloud(f.row)}
        assertTrue(runCatching{photos(f,remote,service).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(0,remote.writes);assertEquals(original,f.store.queued)
    }
    @Test fun semanticImageAcknowledgementAlsoProvesTheImmutableObjectUpload()=runTest {
        val f=photo();val service=ImageRemote{}
        val remote=Remote().apply{fetched=cloud(f.row)}
        assertEquals(1,photos(f,remote,service).pushPending(owner,token).acknowledged)
        assertEquals(1,service.uploads);assertEquals(0,remote.writes);assertNull(f.store.queued)
        assertTrue(f.cache.pendingUploads(owner).getOrThrow().isEmpty())
    }
    @Test fun explicitRemovalRemainsNullAndDoesNotUploadAnObject()=runTest {
        val f=photo(true);val service=ImageRemote{error("Remove must not upload")}
        val remote=Remote().apply{fetched=withImage(record(3),remoteImage);updated=cloud(f.row)}
        assertEquals(1,photos(f,remote,service).pushPending(owner,token).pushed)
        assertSame(JsonNull,remote.updatedPayload!!["image_path"]);assertEquals(0,service.uploads);assertNull(f.store.queued)
    }
    @Test fun metadataKeepPreservesTheLatestRemoteImageOnWriteAndSemanticAck()=runTest {
        val row=withImage(record(3,"New name"),oldImage);val store=Store(row,queue(row))
        val current=withImage(record(3,"Before"),remoteImage)
        val remote=Remote().apply{fetched=current;updated=withImage(record(4,"New name"),remoteImage)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(remoteImage,remote.updatedPayload!!.financeRawString("image_path"))
        val same=withImage(record(4,"New name"),oldImage);val second=Store(same,queue(same))
        val service=Remote().apply{fetched=withImage(record(7,"New name"),remoteImage)}
        assertEquals(1,coordinator(second,service).pushPending(owner,token).acknowledged)
        assertEquals(remoteImage,second.record!!.payload.financeRawString("image_path"));assertEquals(0,service.writes)
    }
    @Test fun anAlreadyAcknowledgedPhotoCarriedByALaterRenameBehavesAsKeep()=runTest {
        val f=photo();f.store.photoAcknowledged=true
        val local=f.row.copy(payload=JsonObject(f.row.payload+("name" to JsonPrimitive("Renamed"))))
        f.store.record=local;f.store.queued=queue(local)
        val service=ImageRemote{error("Acknowledged photo must not replay")}
        val remote=Remote().apply{fetched=withImage(record(3,"Before"),remoteImage);updated=withImage(record(4,"Renamed"),remoteImage)}
        assertEquals(1,photos(f,remote,service).pushPending(owner,token).pushed)
        assertEquals(remoteImage,remote.updatedPayload!!.financeRawString("image_path"));assertEquals(0,service.uploads)
    }
    @Test fun pendingChannelDefersAssetsBeforeAnyImageOrMetadataRequest()=runTest {
        val f=photo();f.store.channelPending=true
        val remote=Remote();val service=ImageRemote{error("Dependency is pending")}
        assertEquals(DomainPushSummary(),photos(f,remote,service).pushPending(owner,token))
        assertEquals(0,service.uploads);assertEquals(0,remote.fetches);assertEquals(0,remote.writes)
    }
    private class Store(var record:CloudRecord?,var queued:QueuedMutation?):LocalStore {
        var publication:InvestmentProductImagePublication?=null
        var photoAcknowledged=false
        var channelPending=false
        var cleanups=0
        override suspend fun cleanupInvestmentProductImages(owner:UserId,remote:InvestmentProductImageRemote):Int {cleanups++;return 0}

        override fun observe(entity:String,ownerUserId:UserId)=MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId:UserId)=MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=if(entity==CloudEntity.INVESTMENT_CHANNEL.table)
            InvestmentChannelRecord("44444444-4444-4444-4444-444444444444",ownerUserId.value,"Shop","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,"2026-10-24T00:00:00Z","2026-10-24T00:00:00Z",null,1,null).toCloudRecord() else record
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=error("Publication must not call a generic mutation writer")
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int)=listOfNotNull(queued).filter{
            it.mutation.subjectUserId==ownerUserId.value && it.mutation.entity==entity && it.nextAttemptAtEpochMillis<=dueAtEpochMillis}
        override suspend fun reconcileInvestmentAssetImagePublication(owner:UserId,id:String,knownResult:InvestmentAssetImageSaveRequest?)=InvestmentAssetPublicationSnapshot(owner,record,queued,queued!=null,publication,photoAcknowledged)
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord):Boolean=error("Channel ACK must use its scoped boundary")
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean=error("Channel failure must use its scoped boundary")
        override suspend fun acknowledgeInvestmentAssetMutation(mutation:QueuedMutation,remoteRecord:CloudRecord,publication:InvestmentProductImagePublication?):Boolean {
            if(queued!=mutation || record?.payload!=mutation.mutation.payload)return false
            queued=null;record=remoteRecord;return true
        }
        override suspend fun recordInvestmentAssetMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean {
            if(queued!=mutation || record?.payload!=mutation.mutation.payload)return false
            queued=mutation.copy(attemptCount=mutation.attemptCount+1,nextAttemptAtEpochMillis=nextAttemptAtEpochMillis,lastError=errorCode);return true
        }
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=Unit
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String)=if(entity==CloudEntity.INVESTMENT_CHANNEL.table && channelPending)setOf("44444444-4444-4444-4444-444444444444") else listOfNotNull(queued).filter{it.mutation.entity.table==entity}.mapTo(mutableSetOf()){it.mutation.recordId}
        override suspend fun clearAccount(ownerUserId:UserId)=Unit
    }
    private class Remote:RemoteMutationStore {
        var fetched:CloudRecord?=null;var created:CloudRecord?=null;var updated:CloudRecord?=null
        val fetchSequence=mutableListOf<CloudRecord?>()
        var fetchError:Throwable?=null;var createError:Throwable?=null
        var updateExpected:Long?=null;var updatedPayload:JsonObject?=null
        var createdPayload:JsonObject?=null
        var fetches=0;var writes=0
        var onFetch:()->Unit={};var onCreate:()->Unit={};var onUpdate:()->Unit={}
        override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? {fetches++;onFetch();fetchError?.let{throw it};return if(fetchSequence.isEmpty())fetched else fetchSequence.removeAt(0)}
        override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord {writes++;createdPayload=payload;onCreate();createError?.let{throw it};return requireNotNull(created)}
        override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {writes++;updateExpected=expectedVersion;updatedPayload=payload;onUpdate();return updated}
    }
}
