package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentMetadataStagingTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channel="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val objectId="55555555-5555-5555-5555-555555555555"
    private val now="2026-10-27T00:00:00Z"
    private data class Fixture(val source:InvestmentTradePublicationSnapshot,val remote:CloudRecord,val entity:CloudEntity)
    private fun fixture(entity:CloudEntity=CloudEntity.INVESTMENT_ASSET,base:Long=4):Fixture {
        val row=if(entity==CloudEntity.INVESTMENT_ASSET)InvestmentAssetRecord(id,owner.value,channel,"New cards","VND",null,"box",0,true,now,now,now,null,base,device).toCloudRecord()
            else InvestmentChannelRecord(id,owner.value,"New shop","shippingbox.fill","#9A67FF",0,true,now,now,now,null,base,device).toCloudRecord()
        val local=row.copy(payload=JsonObject(row.payload+("future_metadata" to JsonNull)))
        val q=QueuedMutation(PendingMutation(entity,id,owner.value,MutationKind.UPSERT,local.payload,now,base,device),3,9000,"http_503",false)
        val source=InvestmentTradePublicationSnapshot(owner,id,listOf(local),listOf(q),setOf(entity.table to id))
        val remote=local.copy(payload=JsonObject(local.payload+buildJsonObject{put("name","Old name");put("is_archived",false);put("archived_at",JsonNull)}))
        return Fixture(source,remote,entity)
    }
    private fun prepare(f:Fixture)=prepareInvestmentMetadataStage(f.source,f.entity,id,f.remote,
        if(f.entity==CloudEntity.INVESTMENT_ASSET)InvestmentAssetPublicationSnapshot(owner,f.source.rows.single(),f.source.pending.single(),true) else null)
    private fun reply(p:InvestmentMetadataStagePreparation)=p.proposal.copy(updatedAt="2026-10-27T00:30:00Z",
        payload=JsonObject(p.proposal.payload+("updated_at" to JsonPrimitive("2026-10-27T00:30:00Z"))))
    @Test fun preparingActiveAssetMetadataPreservesTheFinalArchiveProposalAndRetryGeneration() {
        val f=fixture();val p=prepare(f)
        assertEquals(false,p.proposal.payload.financeRawArchived());assertEquals(JsonNull,p.proposal.payload["archived_at"])
        assertEquals("New cards",p.proposal.payload.financeRawString("name"));assertEquals(5L,p.proposal.syncVersion)
        assertFalse(LOCAL_INVESTMENT_METADATA_STAGES_KEY in p.proposal.payload)
        assertEquals(true,p.preparedRecord.payload.financeRawArchived());p.preparedSource.requireCoherent()
        assertEquals(f.source.pending.single().copy(mutation=f.source.pending.single().mutation.copy(payload=p.preparedRecord.payload)),p.preparedSource.pending.single())
        assertEquals(listOf(p.stage),localInvestmentMetadataStages(p.preparedRecord))
    }
    @Test fun channelStagingUsesTheSameExplicitNullAndOwnedPreparedEvidence() {
        val p=prepare(fixture(CloudEntity.INVESTMENT_CHANNEL))
        assertEquals(false,p.proposal.payload.financeRawArchived());assertEquals(JsonNull,p.proposal.payload["future_metadata"])
        assertEquals(listOf(p.stage),localInvestmentMetadataStages(p.preparedRecord))
    }
    @Test fun definiteStageRebasesOnlySyncIdentityAndLeavesTheArchiveQueued() {
        val p=prepare(fixture());val result=planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,reply(p),p.preparedSource)!!
        assertEquals(5L,result.first.syncVersion);assertEquals(5L,result.second.mutation.baseVersion)
        assertEquals(now,result.first.updatedAt);assertEquals(now,result.second.mutation.modifiedAt)
        assertEquals(true,result.first.payload.financeRawArchived());assertEquals(3,result.second.attemptCount);assertEquals(9000L,result.second.nextAttemptAtEpochMillis)
        assertEquals("http_503",result.second.lastError);assertTrue(result.second.remoteIdentityObserved)
    }
    @Test fun durablePreparedEvidenceProtectsANewerNameAcrossALostOrLateServerClockReply() {
        val p=prepare(fixture());val current=p.preparedSource.let{s->
            val row=s.rows.single().copy(updatedAt="2026-10-27T00:15:00Z",payload=JsonObject(s.rows.single().payload+buildJsonObject{put("name","Later local name");put("updated_at","2026-10-27T00:15:00Z")}))
            s.copy(rows=listOf(row),pending=s.pending.map{it.copy(mutation=it.mutation.copy(payload=row.payload,modifiedAt=row.updatedAt!!))})
        }
        val recovered=localInvestmentMetadataStages(current.rows.single()).single()
        val result=planInvestmentMetadataStageRebase(current,p.entity,id,recovered,reply(p),current)!!
        assertEquals("Later local name",result.first.payload.financeRawString("name"));assertEquals("2026-10-27T00:15:00Z",result.first.updatedAt)
        assertEquals(5L,result.first.syncVersion);assertEquals(true,result.first.payload.financeRawArchived())
    }
    @Test fun keepPhotoUsesTheComparedServerPhotoButANewerRemovalCannotBeOverwritten() {
        val path=InvestmentProductImagePath.create(owner,id,objectId).value
        val f=fixture().let{it.copy(remote=it.remote.copy(payload=JsonObject(it.remote.payload+("image_path" to JsonPrimitive(path)))))}
        val p=prepare(f);assertEquals(path,p.proposal.payload.financeRawString("image_path"))
        val accepted=planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,reply(p),p.preparedSource)!!
        assertEquals(path,accepted.first.payload.financeRawString("image_path"))
        val current=p.preparedSource.let{s->
            val marker=buildJsonObject{put("version",1);put("owner_user_id",owner.value);put("asset_id",id);put("revision",objectId);put("previous_path",path);put("candidate",JsonNull)}
            val row=s.rows.single().copy(payload=JsonObject(s.rows.single().payload+(LOCAL_ASSET_IMAGE_INTENT_KEY to marker)))
            s.copy(rows=listOf(row),pending=s.pending.map{it.copy(mutation=it.mutation.copy(payload=row.payload))})
        }
        assertEquals(JsonNull,planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,reply(p),current)!!.first.payload["image_path"])
    }
    @Test fun foreignChangedOrUnpreparedRepliesCannotRebaseAnyProposal() {
        val f=fixture();val p=prepare(f);val r=reply(p)
        for(bad in listOf(r.copy(ownerUserId=device,payload=JsonObject(r.payload+("user_id" to JsonPrimitive(device)))),
            r.copy(payload=JsonObject(r.payload+("name" to JsonPrimitive("Unsubmitted name"))))))
            assertTrue(runCatching{planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,bad,p.preparedSource)}.isFailure)
        assertNull(planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,r,f.source))
    }
    @Test fun preparedEvidenceIsStrictBoundedAndKeepsInt64VersionsExact() {
        val p=prepare(fixture(base=9007199254740993L));assertEquals(9007199254740994L,p.stage.replyVersion)
        val bad=p.preparedRecord.copy(payload=JsonObject(p.preparedRecord.payload+(LOCAL_INVESTMENT_METADATA_STAGES_KEY to JsonNull)))
        assertTrue(runCatching{localInvestmentMetadataStages(bad)}.isFailure)
        assertTrue(runCatching{prepare(fixture(base=Long.MAX_VALUE))}.isFailure)
    }
    @Test fun adoptingANewerKeptPhotoRetiresOnlyTheUnchangedAlreadyAcknowledgedPhotoIntent() {
        val f=fixture();val previous=InvestmentProductImagePath.create(owner,id,objectId).value
        val next=InvestmentProductImagePath.create(owner,id,device).value
        val marker=buildJsonObject {
            put("version",1);put("owner_user_id",owner.value);put("asset_id",id);put("revision",objectId);put("previous_path",JsonNull)
            put("candidate",buildJsonObject{put("path",previous);put("image_sha256","0".repeat(64));put("thumbnail_sha256","1".repeat(64))})
        }
        val row=f.source.rows.single().copy(payload=JsonObject(f.source.rows.single().payload+buildJsonObject{put("image_path",previous);put(LOCAL_ASSET_IMAGE_INTENT_KEY,marker)}))
        val s=f.source.copy(rows=listOf(row),pending=f.source.pending.map{it.copy(mutation=it.mutation.copy(payload=row.payload))})
        val remote=f.remote.copy(payload=JsonObject(f.remote.payload+("image_path" to JsonPrimitive(next))))
        val p=prepareInvestmentMetadataStage(s,f.entity,id,remote,InvestmentAssetPublicationSnapshot(owner,row,s.pending.single(),true,localAssetImagePublication(row),true))
        val accepted=planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,reply(p),p.preparedSource)!!.first
        assertEquals(next,accepted.payload.financeRawString("image_path"));assertNull(localAssetImagePublication(accepted))
        assertFalse(LOCAL_ASSET_IMAGE_INTENT_KEY in accepted.payload)
    }
    @Test fun unreadableNewerPhotoAuthorityCannotBeRebasedByAnOlderStage() {
        val p=prepare(fixture());val row=p.preparedRecord.copy(payload=JsonObject(p.preparedRecord.payload+(LOCAL_ASSET_IMAGE_INTENT_KEY to JsonNull)))
        val current=p.preparedSource.copy(rows=listOf(row),pending=p.preparedSource.pending.map{it.copy(mutation=it.mutation.copy(payload=row.payload))})
        assertTrue(runCatching{planInvestmentMetadataStageRebase(p.preparedSource,p.entity,id,p.stage,reply(p),current)}.isFailure)
    }
    @Test fun preparingSeventyDistinctStagesRetainsOnlyTheLatestSixtyFourAndRejectsAnOversizedJournal() {
        val f=fixture();var s=f.source
        repeat(70){index->
            val remote=f.remote.copy(syncVersion=4L+index,payload=JsonObject(f.remote.payload+("sync_version" to JsonPrimitive(4L+index))))
            s=prepareInvestmentMetadataStage(s,f.entity,id,remote,InvestmentAssetPublicationSnapshot(owner,s.rows.single(),s.pending.single(),true)).preparedSource
        }
        val row=s.rows.single();val stages=localInvestmentMetadataStages(row)
        assertEquals(64,stages.size);assertEquals(10L,stages.first().remoteBase);assertEquals(73L,stages.last().remoteBase)
        assertEquals(3,s.pending.single().attemptCount);assertEquals(9000L,s.pending.single().nextAttemptAtEpochMillis)
        val marker=row.payload.getValue(LOCAL_INVESTMENT_METADATA_STAGES_KEY).jsonObject
        val entries=marker.getValue("stages").jsonArray
        val bad=row.copy(payload=JsonObject(row.payload+(LOCAL_INVESTMENT_METADATA_STAGES_KEY to JsonObject(marker+("stages" to JsonArray(entries+entries.first()))))))
        assertTrue(runCatching{localInvestmentMetadataStages(bad)}.isFailure)
    }
}
