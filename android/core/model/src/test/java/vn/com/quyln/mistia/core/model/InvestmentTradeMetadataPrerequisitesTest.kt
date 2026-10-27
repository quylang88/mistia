package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradeMetadataPrerequisitesTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val asset="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-27T00:00:00Z"
    private fun fixture(archiveChannel:Boolean=false):Pair<InvestmentTradePublicationSnapshot,List<CloudRecord>> {
        val rows=listOf(
            InvestmentAssetRecord(asset,owner.value,channel,"Cards","VND",null,"box",0,!archiveChannel,if(archiveChannel)null else now,now,now,null,4,device).toCloudRecord(),
            InvestmentChannelRecord(channel,owner.value,"Shop","shippingbox.fill","#9A67FF",0,archiveChannel,if(archiveChannel)now else null,now,now,null,4,device).toCloudRecord(),
        ).map{it.copy(payload=JsonObject(it.payload+("future_metadata" to JsonNull)))}
        val row=rows.single{it.payload.financeRawArchived()==true}
        val entity=CloudEntity.fromTable(row.entity)!!
        val q=QueuedMutation(PendingMutation(entity,row.id,owner.value,MutationKind.UPSERT,row.payload,now,4,device),0,0,null)
        val source=InvestmentTradePublicationSnapshot(owner,device,rows,listOf(q),setOf(row.entity to row.id))
        val active=row.copy(syncVersion=5,payload=JsonObject(row.payload+buildJsonObject{put("is_archived",false);put("archived_at",JsonNull);put("sync_version",5)}))
        return source to listOf(active)
    }
    private fun proof(s:InvestmentTradePublicationSnapshot,rows:List<CloudRecord>)=investmentTradeActiveMetadataPrerequisites(s,setOf(asset),rows)
    private fun changed(row:CloudRecord,key:String,value:JsonElement)=row.copy(payload=JsonObject(row.payload+(key to value)))
    @Test fun activeOwnedAssetProvesOnlyItsPendingArchiveWithoutConsumingOrRewritingSource() {
        val(s,r)=fixture();s.requireCoherent();val before=s.copy()
        assertEquals(setOf(CloudEntity.INVESTMENT_ASSET.table to asset),proof(s,r));assertEquals(before,s)
    }
    @Test fun activeOwnedChannelCanProveTheChannelArchivePrerequisite() {
        val(s,r)=fixture(true)
        assertEquals(setOf(CloudEntity.INVESTMENT_CHANNEL.table to channel),proof(s,r))
    }
    @Test fun absentEvidenceDoesNotBypassDirtyMetadata() {
        val(s,_)=fixture();assertTrue(proof(s,emptyList()).isEmpty())
    }
    @Test fun changedNameUnitCurrencyPhotoOrOpaqueMetadataCannotProveTheDesiredGeneration() {
        val(s,r)=fixture();val row=r.single()
        for((key,value) in listOf("name" to JsonPrimitive("Other"),"default_unit_label" to JsonPrimitive("piece"),"currency_code" to JsonPrimitive("JPY"),"image_path" to JsonPrimitive("other"),"future_metadata" to JsonPrimitive("other")))
            assertTrue(key,runCatching{proof(s,listOf(changed(row,key,value)))}.isFailure)
    }
    @Test fun foreignDuplicatePrivateArchivedDeletedAndRegressedEvidenceIsRejected() {
        val(s,r)=fixture();val row=r.single()
        val foreign=changed(row,"user_id",JsonPrimitive(device)).copy(ownerUserId=device)
        val regressed=changed(row,"sync_version",JsonPrimitive(3)).copy(syncVersion=3)
        val dead=changed(row,"deleted_at",JsonPrimitive(now)).copy(deletedAt=now)
        val private=changed(row,LOCAL_ASSET_PUBLICATION_PARENTS_KEY,JsonArray(emptyList()))
        for(rows in listOf(listOf(foreign),r+r,listOf(private),listOf(changed(row,"is_archived",JsonPrimitive(true))),listOf(dead),listOf(regressed)))
            assertTrue(rows.toString(),runCatching{proof(s,rows)}.isFailure)
    }
    @Test fun ordinaryDirtyActiveMetadataIsNotAnArchiveException() {
        val(s,r)=fixture();val active=s.rows.single{it.id==asset}.let{changed(changed(it,"is_archived",JsonPrimitive(false)),"archived_at",JsonNull)}
        val source=s.copy(rows=s.rows.map{if(it.id==asset)active else it},pending=s.pending.map{it.copy(mutation=it.mutation.copy(payload=active.payload))})
        assertTrue(runCatching{proof(source,r)}.isFailure)
    }
}
