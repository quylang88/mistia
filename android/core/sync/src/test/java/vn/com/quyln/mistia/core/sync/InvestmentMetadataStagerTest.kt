package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentMetadataStagerTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-27T00:00:00Z"
    private fun source():InvestmentTradePublicationSnapshot {
        val row=InvestmentChannelRecord(id,owner.value,"New shop","shippingbox.fill","#9A67FF",0,true,now,now,now,null,1,device).toCloudRecord()
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_CHANNEL,id,owner.value,MutationKind.UPSERT,row.payload,now,1,device),0,0,null)
        return InvestmentTradePublicationSnapshot(owner,id,listOf(row),listOf(q),setOf(row.entity to id))
    }
    private class Store(val data:InvestmentTradePublicationSnapshot,val failAt:Int,val error:Exception):LocalStore {
        var reads=0
        private fun unexpected():Nothing=throw AssertionError("Unexpected generic local operation")
        override fun observe(entity:String,ownerUserId:UserId)=unexpected()
        override fun observeEntityCounts(ownerUserId:UserId)=unexpected()
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=unexpected()
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=unexpected()
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int)=unexpected()
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord)=unexpected()
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String)=unexpected()
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=unexpected()
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String)=unexpected()
        override suspend fun clearAccount(ownerUserId:UserId)=unexpected()
        override suspend fun investmentTradePublicationSnapshot(owner:UserId,tradeId:String):InvestmentTradePublicationSnapshot {
            if(++reads==failAt)throw error
            return data
        }
    }
    private class Remote(val data:CloudRecord):RemoteMutationStore {
        var writes=0
        override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId)=data
        override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord {writes++;error("Unexpected write")}
        override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {writes++;error("Unexpected write")}
    }
    private fun active(row:CloudRecord)=row.copy(payload=JsonObject(row.payload+buildJsonObject{put("name","Old shop");put("is_archived",false);put("archived_at",JsonNull)}))
    private fun helper(store:Store,remote:Remote)=InvestmentMetadataStager(CloudEntity.INVESTMENT_CHANNEL,store,remote,owner,"captured-token",{},{true})
    @Test fun sourceCancellationBeforeStageCannotBeConvertedIntoAStaleResult()=runTest {
        val s=source();val cancelled=CancellationException("Source owner revoked");val store=Store(s,1,cancelled);val remote=Remote(active(s.rows.single()))
        assertSame(cancelled,runCatching{helper(store,remote).publishActive(s,s.pending.single(),s.rows.single())}.exceptionOrNull())
        assertEquals(0,remote.writes);assertEquals(s,store.data)
    }
    @Test fun sourceReadFailureCannotBeMistakenForAChangedGeneration()=runTest {
        val s=source();val failure=IOException("Local source unavailable");val store=Store(s,1,failure);val remote=Remote(active(s.rows.single()))
        assertSame(failure,runCatching{helper(store,remote).publishActive(s,s.pending.single(),s.rows.single())}.exceptionOrNull())
        assertEquals(0,remote.writes)
    }
    @Test fun recoveryMustHonorCancellationDuringItsFinalSourceRead()=runTest {
        val s=source();val p=prepareInvestmentMetadataStage(s,CloudEntity.INVESTMENT_CHANNEL,id,active(s.rows.single()))
        val cancelled=CancellationException("Source owner revoked");val store=Store(p.preparedSource,2,cancelled);val remote=Remote(p.proposal)
        assertSame(cancelled,runCatching{helper(store,remote).recover(p.preparedSource.pending.single(),p.preparedRecord)}.exceptionOrNull())
        assertEquals(0,remote.writes)
    }
}
