package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentMetadataStageRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="33333333-3333-3333-3333-333333333333"
    private val contextId="22222222-2222-2222-2222-222222222222"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-27T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner});repo=OfflineFirstInvestmentRepository(store)}
    @After fun close(){db.close()}
    private suspend fun source()=store.investmentTradePublicationSnapshot(owner,id)
    private suspend fun seed(entity:CloudEntity=CloudEntity.INVESTMENT_ASSET,base:Long=4):CloudRecord? {
        val context=if(entity==CloudEntity.INVESTMENT_ASSET)InvestmentChannelRecord(contextId,owner.value,"Shop","shippingbox.fill","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
            else InvestmentAssetRecord(contextId,owner.value,id,"Cards","VND",null,"box",0,false,null,now,now,null,0,device).toCloudRecord()
        val contextEntity=CloudEntity.fromTable(context.entity)!!
        store.commitMutation(context,PendingMutation(contextEntity,context.id,owner.value,MutationKind.UPSERT,context.payload,now,0,device))
        val cq=store.pendingMutations(owner,contextEntity,Long.MAX_VALUE).single()
        assertTrue(store.acknowledgeMutation(cq,context.copy(syncVersion=1,payload=JsonObject(context.payload+("sync_version" to JsonPrimitive(1))))))
        val local=if(entity==CloudEntity.INVESTMENT_ASSET)InvestmentAssetRecord(id,owner.value,contextId,"New cards","VND",null,"box",0,true,now,now,now,null,base,device).toCloudRecord()
            else InvestmentChannelRecord(id,owner.value,"New shop","shippingbox.fill","#9A67FF",0,true,now,now,now,null,base,device).toCloudRecord()
        store.commitMutation(local,PendingMutation(entity,id,owner.value,MutationKind.UPSERT,local.payload,now,base,device))
        val q=source().pending.single()
        assertTrue(store.recordMutationFailure(q,9000,"http_503"))
        return if(base==0L)null else local.copy(payload=JsonObject(local.payload+buildJsonObject{put("name","Old name");put("is_archived",false);put("archived_at",JsonNull)}))
    }
    private fun reply(p:InvestmentMetadataStagePreparation)=p.proposal.copy(updatedAt="2026-10-27T00:30:00Z",payload=JsonObject(p.proposal.payload+("updated_at" to JsonPrimitive("2026-10-27T00:30:00Z"))))
    @Test fun assetPreparationChangesOnlyPrivatePayloadAndKeepsAllDatabaseAndQueueStamps()=runBlocking {
        val remote=seed();val before=source();val row=db.cloudRecordDao().record(owner.value,CloudEntity.INVESTMENT_ASSET.table,id)!!
        val queued=db.syncOutboxDao().record(owner.value,CloudEntity.INVESTMENT_ASSET.table,id)!!
        val p=store.prepareInvestmentMetadataStage(before,CloudEntity.INVESTMENT_ASSET,id,remote)!!
        assertEquals(p.preparedSource,source());source().requireCoherent()
        val after=db.cloudRecordDao().record(owner.value,CloudEntity.INVESTMENT_ASSET.table,id)!!
        val aq=db.syncOutboxDao().record(owner.value,CloudEntity.INVESTMENT_ASSET.table,id)!!
        assertEquals(row.copy(payloadJson=after.payloadJson),after);assertEquals(queued.copy(payloadJson=aq.payloadJson),aq)
        assertEquals(true,source().rows.single{it.id==id}.payload.financeRawArchived())
    }
    @Test fun newChannelStageRebasesItsExactVersionAndObservationButKeepsTheFinalArchivePending()=runBlocking {
        val remote=seed(CloudEntity.INVESTMENT_CHANNEL,0);val p=store.prepareInvestmentMetadataStage(source(),CloudEntity.INVESTMENT_CHANNEL,id,remote)!!
        val before=source().pending.single()
        assertTrue(store.rebaseInvestmentMetadataStage(p.preparedSource,p.entity,id,p.stage,reply(p)))
        val after=source();after.requireCoherent();val q=after.pending.single()
        assertEquals(1L,q.mutation.baseVersion);assertTrue(q.remoteIdentityObserved);assertEquals(before.attemptCount,q.attemptCount)
        assertEquals(before.nextAttemptAtEpochMillis,q.nextAttemptAtEpochMillis);assertEquals(before.lastError,q.lastError)
        assertEquals(true,after.rows.single{it.id==id}.payload.financeRawArchived());assertEquals(now,q.mutation.modifiedAt)
    }
    @Test fun lateStagePreservesAnActualRepositoryRestoreAndRename()=runBlocking {
        val remote=seed();val p=store.prepareInvestmentMetadataStage(source(),CloudEntity.INVESTMENT_ASSET,id,remote)!!
        val old=InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==id})
        repo.restoreAsset(owner,old,device,"2026-10-27T00:14:00Z").getOrThrow()
        val restored=InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==id})
        repo.saveAsset(owner,InvestmentAssetDraft(id,contextId,"Later local name","VND","box",restored),device,"2026-10-27T00:15:00Z").getOrThrow()
        val before=source();assertTrue(store.rebaseInvestmentMetadataStage(p.preparedSource,p.entity,id,p.stage,reply(p)))
        val after=source();val row=after.rows.single{it.id==id};assertEquals("Later local name",row.payload.financeRawString("name"));assertEquals(false,row.payload.financeRawArchived())
        assertEquals(before.pending.single().mutation.modifiedAt,after.pending.single().mutation.modifiedAt);assertEquals(5L,row.syncVersion)
    }
    @Test fun changedWholeGenerationCannotPrepareTheOlderProposal()=runBlocking {
        val remote=seed();val before=source()
        repo.restoreAsset(owner,InvestmentAssetRecord.fromCloudRecord(before.rows.single{it.id==id}),device,"2026-10-27T00:15:00Z").getOrThrow()
        val current=source();assertNull(store.prepareInvestmentMetadataStage(before,CloudEntity.INVESTMENT_ASSET,id,remote));assertEquals(current,source())
    }
    @Test fun unsubmittedRemoteMetadataCannotAdvanceAnyLocalBase()=runBlocking {
        val remote=seed();val p=store.prepareInvestmentMetadataStage(source(),CloudEntity.INVESTMENT_ASSET,id,remote)!!
        val before=source();val bad=reply(p).let{it.copy(payload=JsonObject(it.payload+("name" to JsonPrimitive("Unsubmitted"))))}
        assertTrue(runCatching{store.rebaseInvestmentMetadataStage(p.preparedSource,p.entity,id,p.stage,bad)}.isFailure);assertEquals(before,source())
    }
    private fun failOutbox(){db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_stage BEFORE INSERT ON sync_outbox WHEN NEW.record_id = '$id' BEGIN SELECT RAISE(ABORT, 'stage queue failure'); END")}
    @Test fun queueWriteFailuresRollBackPreparationAndRebaseTogetherWithTheirRow()=runBlocking {
        val remote=seed();var before=source();failOutbox()
        assertTrue(runCatching{store.prepareInvestmentMetadataStage(before,CloudEntity.INVESTMENT_ASSET,id,remote)}.exceptionOrNull().toString().contains("stage queue failure"));assertEquals(before,source())
        db.openHelper.writableDatabase.execSQL("DROP TRIGGER reject_stage")
        val p=store.prepareInvestmentMetadataStage(source(),CloudEntity.INVESTMENT_ASSET,id,remote)!!;before=source();failOutbox()
        assertTrue(runCatching{store.rebaseInvestmentMetadataStage(p.preparedSource,p.entity,id,p.stage,reply(p))}.exceptionOrNull().toString().contains("stage queue failure"));assertEquals(before,source())
    }
    @Test fun finalSessionFenceRollsBackPreparation()=runBlocking {
        val remote=seed();val before=source();var checks=0
        assertTrue(runCatching{store.prepareInvestmentMetadataStage(before,CloudEntity.INVESTMENT_ASSET,id,remote){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(before,source())
    }
    @Test fun finalSessionFenceRollsBackBothRebaseWrites()=runBlocking {
        val remote=seed();val p=store.prepareInvestmentMetadataStage(source(),CloudEntity.INVESTMENT_ASSET,id,remote)!!;val before=source();var checks=0
        assertTrue(runCatching{store.rebaseInvestmentMetadataStage(p.preparedSource,p.entity,id,p.stage,reply(p)){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(before,source())
    }
    private suspend fun rejectPull(entity:CloudEntity) {
        seed(entity);val row=source().rows.single{it.entity==entity.table && it.id==id};val q=source().pending.single()
        assertTrue(store.acknowledgeMutation(q,row));val before=source()
        val injected=row.copy(payload=JsonObject(row.payload+(LOCAL_INVESTMENT_METADATA_STAGES_KEY to JsonNull)))
        assertTrue(runCatching{store.replacePullSnapshot(owner,entity.table,listOf(injected))}.isFailure);assertEquals(before,source())
    }
    @Test fun assetPullCannotSeedPrivateStagingAuthorityBeforeDeletingCleanRows()=runBlocking{rejectPull(CloudEntity.INVESTMENT_ASSET)}
    @Test fun channelPullCannotSeedPrivateStagingAuthorityBeforeDeletingCleanRows()=runBlocking{rejectPull(CloudEntity.INVESTMENT_CHANNEL)}
}
