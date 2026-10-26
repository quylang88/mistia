package vn.com.quyln.mistia.core.sync

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Asset metadata uses its atomic RPC; derived trade/cash queues have separate publication domains. */
class InvestmentAssetPushCoordinator(
    private val localStore:LocalStore,private val remoteStore:RemoteMutationStore,private val writesEnabled:Boolean,
    private val currentSession:()->AuthSession?,private val nowEpochMillis:()->Long=System::currentTimeMillis,
    private val images:vn.com.quyln.mistia.core.database.FileInvestmentProductImageCache?=null,
    private val imageRemote:InvestmentProductImageRemote?=null,
):DomainPushCoordinator {
    override val entity=CloudEntity.INVESTMENT_ASSET
    private data class PublicationContext(val queued:QueuedMutation,val local:CloudRecord,var source:InvestmentAssetPublicationSnapshot,var remote:CloudRecord?=null) {
        val keepImage:Boolean get()=source.imagePublication==null || source.imageAcknowledged
    }
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive()
        val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())
            throw CancellationException("Investment asset session changed")
        fun checkSession() {
            caller.ensureActive()
            if(currentSession()!=captured)throw CancellationException("Investment asset session changed")
            caller.ensureActive()
        }
        var active:PublicationContext?=null
        suspend fun refresh(q:QueuedMutation,row:CloudRecord):Boolean {
            checkSession()
            val source=localStore.reconcileInvestmentAssetImagePublication(ownerUserId,row.id)
            checkSession()
            if(!source.matches(q,row))return false
            val context=active
            if(context==null || context.queued!=q)active=PublicationContext(q,row,source) else context.source=source
            return true
        }
        suspend fun preflight(q:QueuedMutation,row:CloudRecord):MutationPreflight {
            if(!refresh(q,row))return MutationPreflight.Stale
            if(row.deletedAt!=null)return MutationPreflight.Continue
            val asset=InvestmentAssetRecord.fromCloudRecord(row)
            val raw=localStore.record(ownerUserId,CloudEntity.INVESTMENT_CHANNEL.table,asset.channelId)
            checkSession()
            val channel=raw?.let{InvestmentChannelRecord.fromCloudRecord(it)}
            if(channel==null || channel.ownerUserId!=ownerUserId.value || channel.id!=asset.channelId || channel.deletedAt!=null || channel.isArchived)
                return MutationPreflight.Conflict("asset_channel_unavailable")
            val pending=localStore.pendingMutationRecordIds(ownerUserId,CloudEntity.INVESTMENT_CHANNEL.table)
            checkSession()
            return if(asset.channelId in pending)MutationPreflight.Deferred else MutationPreflight.Continue
        }
        fun context(id:String)=requireNotNull(active).also{require(it.local.id==id)}
        suspend fun ensurePhoto(q:QueuedMutation,row:CloudRecord):MutationPreflight {
            val decision=preflight(q,row)
            if(decision!=MutationPreflight.Continue || row.deletedAt!=null)return decision
            val state=context(row.id)
            if(state.keepImage)return MutationPreflight.Continue
            val publication=requireNotNull(state.source.imagePublication)
            val cache=requireNotNull(images){"Product image cache unavailable"}
            require(cache.verifyPublication(ownerUserId,publication,allowPublished=true).getOrThrow()){"Product image publication changed"}
            val candidate=publication.candidate
            if(candidate!=null && candidate in cache.pendingUploads(ownerUserId).getOrThrow()) {
                val data=cache.imageData(ownerUserId,candidate).getOrThrow()
                checkSession()
                if(!refresh(q,row))return MutationPreflight.Stale
                requireNotNull(imageRemote){"Product image upload unavailable"}.upload(ownerUserId,row.id,candidate.path,data,isCurrent={
                    caller.ensureActive();currentSession()==captured
                }).getOrThrow()
                checkSession()
                if(!cache.markUploadSucceeded(ownerUserId,candidate).getOrThrow())return MutationPreflight.Stale
            }
            return preflight(q,row)
        }
        fun cloudPayload(payload:JsonObject):JsonObject {
            val state=context(requireNotNull(payload.financeRawString("id")))
            val stripped=assetPayloadForCloud(payload)
            return if(state.keepImage && state.remote!=null && "image_path" in stripped)
                JsonObject(stripped+("image_path" to (state.remote!!.payload["image_path"] ?: JsonNull))) else stripped
        }
        val adapter=object:RemoteMutationStore {
            override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? {
                checkSession()
                val result=remoteStore.fetchRecord(entity,recordId,accessToken,ownerUserId)
                checkSession()
                require(result==null || LOCAL_ASSET_IMAGE_INTENT_KEY !in result.payload){"Remote asset cannot supply local image provenance"}
                val state=context(recordId)
                state.remote=result
                refresh(state.queued,state.local)
                return result
            }
            override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord {
                checkSession()
                return remoteStore.createRecord(entity,accessToken,ownerUserId,cloudPayload(payload)).also{checkSession()}
            }
            override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {
                checkSession()
                return remoteStore.conditionalUpdate(entity,recordId,accessToken,ownerUserId,expectedVersion,cloudPayload(payload)).also{checkSession()}
            }
        }
        val delegate=OutboxPushCoordinator(entity,localStore,adapter,writesEnabled,nowEpochMillis,
            allowTombstoneDeletes=true,validateRecord={InvestmentAssetRecord.fromCloudRecord(it)},
            normalizeSemanticPayload={payload->
                val stripped=assetPayloadForCloud(payload)
                val semantic=if(active?.keepImage==true)stripped-"image_path" else stripped
                JsonObject(semantic.mapValues{(key,value)->
                    if(key=="archived_at" && value is JsonPrimitive && value.isString)JsonPrimitive(Instant.parse(value.content).toString()) else value
                })
            },preflight={q,row,_,_->preflight(q,row)},beforeRemoteWrite={q,row,_,_->
                ensurePhoto(q,row)
            },acknowledgeOverride={q,remote->
                checkSession()
                val state=context(q.mutation.recordId)
                val source=state.source
                val publication=source.imagePublication
                val target=remote.payload["image_path"]
                if(publication!=null && !source.imageAcknowledged && remote.deletedAt==null && target==(publication.path?.let(::JsonPrimitive) ?: JsonNull)) {
                    when(val decision=ensurePhoto(q,state.local)) {
                        MutationPreflight.Deferred->return@OutboxPushCoordinator MutationAcknowledgement.Deferred
                        is MutationPreflight.Conflict->return@OutboxPushCoordinator MutationAcknowledgement.Conflict(decision.reason)
                        else->Unit // Room can acknowledge the same photo across a later ordinary rename.
                    }
                }
                val accepted=localStore.acknowledgeInvestmentAssetMutation(q,remote,publication)
                checkSession()
                if(accepted)MutationAcknowledgement.Committed else MutationAcknowledgement.Stale
            },recordFailureOverride={q,next,code->
                checkSession()
                val result=localStore.recordInvestmentAssetMutationFailure(q,next,code)
                checkSession();result
            })
        val result=delegate.pushPending(ownerUserId,accessToken)
        checkSession()
        if(imageRemote!=null)try {
            localStore.cleanupInvestmentProductImages(ownerUserId,imageRemote)
            checkSession()
        }catch(cancelled:CancellationException){throw cancelled}
        catch(error:Exception){checkSession()} // Failed cleanup keeps its durable ready paths for the next sync.
        checkSession()
        return result
    }
}
