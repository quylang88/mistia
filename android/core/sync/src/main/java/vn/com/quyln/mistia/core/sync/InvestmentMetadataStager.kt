package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException
import kotlinx.serialization.json.JsonObject

/** Publishes an active prerequisite while its final metadata intent remains in the outbox. */
internal class InvestmentMetadataStager(
    private val entity:CloudEntity,private val local:LocalStore,private val remote:RemoteMutationStore,
    private val owner:UserId,private val token:String,private val checkCurrent:()->Unit,private val isCurrent:()->Boolean,
    private val knownPrior:(CloudRecord,CloudRecord,String)->Boolean = {_,_,_->false},
) {
    private var preparation:InvestmentMetadataStagePreparation?=null
    fun failureQueue(original:QueuedMutation):QueuedMutation {
        val p=preparation ?: return original
        val old=p.source.pending.singleOrNull{it.mutation.entity==entity && it.mutation.recordId==p.id}
        return if(old==original)p.preparedSource.pending.single{it.mutation.entity==entity && it.mutation.recordId==p.id} else original
    }
    private suspend fun source(id:String):InvestmentTradePublicationSnapshot {
        checkCurrent();val result=local.investmentTradePublicationSnapshot(owner,id);checkCurrent()
        require(result.owner==owner && result.tradeId==id);result.requireCoherent();return result
    }
    private suspend fun unchanged(expected:InvestmentTradePublicationSnapshot):Boolean {
        val current=source(expected.tradeId)
        return runCatching{expected.requireUnchanged(current)}.isSuccess
    }
    private fun matches(s:InvestmentTradePublicationSnapshot,q:QueuedMutation,row:CloudRecord)=
        q in s.pending && s.rows.singleOrNull{it.entity==entity.table && it.id==row.id}==row
    private fun scoped(row:CloudRecord,id:String) {
        require(row.entity==entity.table && row.id==id && row.ownerUserId==owner.value && row.financeRawIdentity(owner,entity,true) &&
            row.payload.financeRawString("id")==id && row.payload.financeRawString("user_id")==owner.value &&
            row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==row.payload.financeRawString("updated_at") &&
            row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at") && row.payload.keys.none{it.startsWith("_mistia_android_")})
        if(entity==CloudEntity.INVESTMENT_ASSET)InvestmentAssetRecord.fromCloudRecord(row) else InvestmentChannelRecord.fromCloudRecord(row)
    }
    suspend fun recover(q:QueuedMutation,row:CloudRecord):MutationPreflight? {
        preparation=null
        val stages=localInvestmentMetadataStages(row)
        if(stages.isEmpty())return null
        val before=source(row.id);if(!matches(before,q,row))return MutationPreflight.Stale
        checkCurrent();val observed=remote.fetchRecord(entity,row.id,token,owner);checkCurrent()
        if(!unchanged(before))return MutationPreflight.Stale
        if(observed==null)return if(q.mutation.baseVersion>0 || q.remoteIdentityObserved)MutationPreflight.Conflict("investment_stage_missing") else null
        scoped(observed,row.id)
        val stage=stages.singleOrNull{it.localBase==row.syncVersion && it.replyVersion==observed.syncVersion && it.device==q.mutation.deviceId &&
            observed.payload.financeRawString("last_modified_by_device_id")==it.device && investmentMetadataStageFingerprint(observed.payload)==it.fingerprint} ?: return null
        checkCurrent();val accepted=local.rebaseInvestmentMetadataStage(before,entity,row.id,stage,observed,isCurrent);checkCurrent()
        return if(accepted)MutationPreflight.Reconciled else MutationPreflight.Stale
    }
    suspend fun publishActive(before:InvestmentTradePublicationSnapshot,q:QueuedMutation,row:CloudRecord,
        beforeStage:suspend (CloudRecord?)->MutationPreflight = {MutationPreflight.Continue}):MutationPreflight {
        preparation=null;checkCurrent();require(matches(before,q,row))
        val observed=remote.fetchRecord(entity,row.id,token,owner);checkCurrent();observed?.let{scoped(it,row.id)}
        if(!unchanged(before))return MutationPreflight.Stale
        if(observed==null && (q.mutation.baseVersion>0 || q.remoteIdentityObserved))return MutationPreflight.Conflict("investment_stage_missing")
        if(observed!=null && observed.syncVersion<row.syncVersion)return MutationPreflight.Conflict("investment_stage_regressed")
        val ready=beforeStage(observed);checkCurrent();if(ready!=MutationPreflight.Continue)return ready
        if(!unchanged(before))return MutationPreflight.Stale
        val photo=if(entity==CloudEntity.INVESTMENT_ASSET)local.reconcileInvestmentAssetImagePublication(owner,row.id) else null
        checkCurrent()
        val preview=prepareInvestmentMetadataStage(before,entity,row.id,observed,photo)
        val sameActive=observed!=null && investmentMetadataStageFingerprint(observed.payload)==preview.stage.fingerprint
        val adoptPhoto=entity==CloudEntity.INVESTMENT_ASSET && preview.stage.keepImage && row.payload["image_path"]!=preview.proposal.payload["image_path"]
        if(sameActive && !adoptPhoto)return MutationPreflight.Deferred
        if(observed!=null && observed.syncVersion>q.mutation.baseVersion && !knownPrior(row,observed,q.mutation.deviceId)) {
            if(localInvestmentMetadataStages(row).isNotEmpty() && observed.payload.financeRawString("last_modified_by_device_id")==q.mutation.deviceId)
                return MutationPreflight.Conflict("own_unproven_stage")
            fun semantic(raw:CloudRecord)=raw.copy(payload=JsonObject(investmentMetadataPayloadForCloud(raw.payload).let{
                if(preview.stage.keepImage)it-"image_path" else it
            }))
            when(ConflictResolver.resolve(semantic(row),semantic(observed)).winner) {
                ConflictWinner.REMOTE->return MutationPreflight.Acknowledge(observed)
                ConflictWinner.UNRESOLVED->return MutationPreflight.Conflict("investment_stage_unresolved")
                ConflictWinner.LOCAL->Unit
            }
        }
        checkCurrent()
        val p=local.prepareInvestmentMetadataStage(before,entity,row.id,observed,isCurrent) ?: return MutationPreflight.Stale
        checkCurrent();preparation=p
        if(!unchanged(p.preparedSource))return MutationPreflight.Stale
        checkCurrent()
        val saved=try {
            if(observed==null)remote.createRecord(entity,token,owner,p.proposal.payload)
            else remote.conditionalUpdate(entity,row.id,token,owner,observed.syncVersion,p.proposal.payload)
        }catch(error:SupabaseHttpException){if(error.statusCode==409)null else throw error}
        checkCurrent()
        if(saved==null)return MutationPreflight.Deferred
        val accepted=local.rebaseInvestmentMetadataStage(p.preparedSource,entity,row.id,p.stage,saved,isCurrent);checkCurrent()
        return if(accepted)MutationPreflight.Reconciled else MutationPreflight.Stale
    }
}
