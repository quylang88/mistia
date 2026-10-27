package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

fun interface InvestmentTradeMetadataRemote {
    suspend fun fetchMetadata(owner:UserId,entity:CloudEntity,id:String,accessToken:String):CloudRecord?
}

/** Owned active metadata observations can prove a prerequisite while its final archive stays queued. */
fun investmentTradeActiveMetadataPrerequisites(
    source:InvestmentTradePublicationSnapshot,affectedAssetIds:Set<String>,remoteMetadata:List<CloudRecord>,
):Set<Pair<String,String>> {
    source.requireCoherent()
    require(affectedAssetIds.size in 1..2 && affectedAssetIds.all{financeRawUuid(it)==it})
    val byKey=source.rows.associateBy{it.entity to it.id}
    val dependencies=linkedSetOf<Pair<String,String>>()
    for(id in affectedAssetIds) {
        val key=CloudEntity.INVESTMENT_ASSET.table to id
        val asset=InvestmentAssetRecord.fromCloudRecord(requireNotNull(byKey[key]))
        require(asset.deletedAt==null)
        dependencies+=key
        val channel=CloudEntity.INVESTMENT_CHANNEL.table to asset.channelId
        require(InvestmentChannelRecord.fromCloudRecord(requireNotNull(byKey[channel])).deletedAt==null)
        dependencies+=channel
    }
    val keys=remoteMetadata.map{it.entity to it.id}
    require(keys.distinct().size==keys.size)
    fun semantic(payload:JsonObject):JsonObject=JsonObject((payload-LOCAL_ASSET_PUBLICATION_KEYS-
        setOf("is_archived","archived_at","updated_at","sync_version","last_modified_by_device_id")).mapValues{(key,value)->
        if(key=="created_at") {
            val instant=Instant.parse(requireNotNull((value as? JsonPrimitive)?.takeIf{it.isString}?.content))
            JsonPrimitive(Instant.ofEpochSecond(instant.epochSecond,Math.rint(instant.nano.toDouble()/1000).toLong()*1000).toString())
        } else value
    })
    for(remote in remoteMetadata) {
        val key=remote.entity to remote.id
        require(key in dependencies && key in source.dirtyKeys)
        val entity=requireNotNull(CloudEntity.fromTable(remote.entity))
        require(remote.financeRawIdentity(source.owner,entity,true) && remote.payload.financeRawString("id")==remote.id &&
            remote.payload.financeRawString("user_id")==source.owner.value && remote.syncVersion>0 &&
            remote.payload.financeRawLong("sync_version")==remote.syncVersion && remote.updatedAt==remote.payload.financeRawString("updated_at") &&
            remote.deletedAt==null && remote.financeRawDeleted(true)==false && remote.payload.financeRawArchived()==false)
        require(remote.payload.keys.none{it.startsWith("_mistia_android_")})
        when(entity) {
            CloudEntity.INVESTMENT_ASSET->InvestmentAssetRecord.fromCloudRecord(remote)
            CloudEntity.INVESTMENT_CHANNEL->InvestmentChannelRecord.fromCloudRecord(remote)
            else->error("Invalid investment metadata entity")
        }
        val local=requireNotNull(byKey[key])
        localInvestmentMetadataStages(local)
        require(local.deletedAt==null && local.payload.financeRawArchived()==true && remote.syncVersion>=local.syncVersion)
        val queued=source.pending.single{it.mutation.entity==entity && it.mutation.recordId==remote.id}
        require(queued.mutation.kind==MutationKind.UPSERT)
        require(semantic(local.payload)==semantic(remote.payload))
    }
    return keys.toSet()
}
