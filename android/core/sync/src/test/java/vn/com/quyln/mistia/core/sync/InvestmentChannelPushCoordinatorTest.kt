package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentChannelPushCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val token="channel-token"
    private val now="2026-10-24T00:00:00Z"
    private var session:AuthSession?=AuthSession(owner,null,token,"refresh",Long.MAX_VALUE)
    private fun record(version:Long=0,name:String="Cards",date:String=now)=InvestmentChannelRecord(id,owner.value,name,"chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,date,null,version,device)
        .toCloudRecord().let{it.copy(payload=JsonObject(it.payload+("future_null" to JsonNull)))}
    private fun queue(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_CHANNEL,row.id,row.ownerUserId,
        if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device),0,0,null)
    private fun coordinator(store:Store,remote:Remote,enabled:Boolean=true)=InvestmentChannelPushCoordinator(store,remote,enabled,{session},{4000})
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
    @Test fun newerRemoteMetadataWinsWithoutAWriteOrAStaleLocalQueue()=runTest {
        val row=record(3);val winner=record(4,"Remote","2026-10-24T01:00:00Z")
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
        val row=record(3);val winner=record(4,"Remote","2026-10-24T01:00:00Z");val store=Store(row,queue(row))
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
    private class Store(var record:CloudRecord?,var queued:QueuedMutation?):LocalStore {
        override fun observe(entity:String,ownerUserId:UserId)=MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId:UserId)=MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=record
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=error("Publication must not call a generic mutation writer")
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int)=listOfNotNull(queued).filter{
            it.mutation.subjectUserId==ownerUserId.value && it.mutation.entity==entity && it.nextAttemptAtEpochMillis<=dueAtEpochMillis}
        override suspend fun investmentChannelPublicationSnapshot(owner:UserId,id:String)=InvestmentChannelPublicationSnapshot(owner,record,queued,queued!=null)
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord):Boolean=error("Channel ACK must use its scoped boundary")
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean=error("Channel failure must use its scoped boundary")
        override suspend fun acknowledgeInvestmentChannelMutation(mutation:QueuedMutation,remoteRecord:CloudRecord,isSessionCurrent:()->Boolean):Boolean {
            if(queued!=mutation || record?.payload!=mutation.mutation.payload)return false
            queued=null;record=remoteRecord;return true
        }
        override suspend fun recordInvestmentChannelMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String,isSessionCurrent:()->Boolean):Boolean {
            if(queued!=mutation || record?.payload!=mutation.mutation.payload)return false
            queued=mutation.copy(attemptCount=mutation.attemptCount+1,nextAttemptAtEpochMillis=nextAttemptAtEpochMillis,lastError=errorCode);return true
        }
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=Unit
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String)=listOfNotNull(queued).mapTo(mutableSetOf()){it.mutation.recordId}
        override suspend fun clearAccount(ownerUserId:UserId)=Unit
    }
    private class Remote:RemoteMutationStore {
        var fetched:CloudRecord?=null;var created:CloudRecord?=null;var updated:CloudRecord?=null
        val fetchSequence=mutableListOf<CloudRecord?>()
        var fetchError:Throwable?=null;var createError:Throwable?=null
        var updateExpected:Long?=null;var updatedPayload:JsonObject?=null
        var createdPayload:JsonObject?=null
        var fetches=0;var writes=0
        var onFetch:()->Unit={};var onCreate:()->Unit={}
        override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? {fetches++;onFetch();fetchError?.let{throw it};return if(fetchSequence.isEmpty())fetched else fetchSequence.removeAt(0)}
        override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord {writes++;createdPayload=payload;onCreate();createError?.let{throw it};return requireNotNull(created)}
        override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {writes++;updateExpected=expectedVersion;updatedPayload=payload;return updated}
    }
}
