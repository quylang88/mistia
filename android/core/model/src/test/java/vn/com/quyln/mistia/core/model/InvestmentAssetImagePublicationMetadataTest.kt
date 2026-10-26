package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentAssetImagePublicationMetadataTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channelId="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val old="2026-10-20T00:00:00Z";private val now="2026-10-24T00:00:00Z"
    private val first=InvestmentProductImagePath.create(owner,id,"55555555-5555-5555-5555-555555555555")
    private val second=InvestmentProductImagePath.create(owner,id,"66666666-6666-6666-6666-666666666666")
    private val revision="77777777-7777-7777-7777-777777777777"
    private val key="_mistia_android_asset_image_intent"
    private val asset=InvestmentAssetRecord(id,owner.value,channelId,"Cards","VND",first.value,"box",0,false,null,old,old,null,9007199254740993L,device)
    private val channel=InvestmentChannelRecord(channelId,owner.value,"Shop","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,old,old,null,0,device).toCloudRecord()
    private fun source(raw:CloudRecord=asset.toCloudRecord())=InvestmentAssetSnapshot(owner,listOf(channel,raw))
    private fun publication(remove:Boolean=false)=InvestmentProductImagePublication(owner.value,id,revision,first.value,
        if(remove)null else InvestmentProductImageCandidate(owner.value,id,second.value,"0".repeat(64),"1".repeat(64)))
    private fun saved(remove:Boolean=false):CloudRecord {
        val pub=publication(remove)
        val draft=InvestmentAssetDraft(id,channelId,"Cards","VND","box",asset,
            if(remove)InvestmentAssetImageChange.Remove else InvestmentAssetImageChange.Replace(second))
        val plan=planInvestmentAssetImageSave(source(),InvestmentAssetImageSaveRequest(draft,pub),device,now)
        val mutation=plan.mutations.single()
        assertEquals(mutation.first.payload,mutation.second.payload)
        return mutation.first
    }
    @Test fun realTypedReplacementAtomicallyCarriesExplicitPublicationToOutbox() {
        val row=saved()
        assertTrue(row.payload[key] is JsonObject)
        assertEquals(publication(),localAssetImagePublication(row))
        assertEquals(second.value,InvestmentAssetRecord.fromCloudRecord(row).imagePath)
        assertEquals(9007199254740993L,row.syncVersion)
    }
    @Test fun explicitRemovalPersistsRevisionAndPreviousPathWithNullTarget() {
        val row=saved(true)
        assertSame(JsonNull,row.payload["image_path"])
        assertEquals(publication(true),localAssetImagePublication(row))
    }
    @Test fun ordinaryRenamePreservesThePendingExplicitIntent() {
        val raw=saved();val typed=InvestmentAssetRecord.fromCloudRecord(raw)
        val plan=planInvestmentAssetMutation(source(raw),InvestmentAssetRequest.Save(
            InvestmentAssetDraft(id,channelId,"New name","VND","box",typed)),device,now)
        assertEquals(raw.payload[key],plan.mutations.single().first.payload[key])
        assertEquals(publication(),localAssetImagePublication(plan.mutations.single().first))
    }
    @Test fun cloudPayloadStripsOnlyPrivateIntentPreservingOpaqueValuesAndExplicitNulls() {
        val raw=saved(true)
        val payload=JsonObject(raw.payload+mapOf("future_null" to JsonNull,"future_object" to buildJsonObject{put("large",Long.MAX_VALUE)}))
        val result=assetPayloadForCloud(payload)
        assertEquals(JsonObject(payload.filterKeys{it!=key}),result)
        assertFalse(key in result);assertSame(JsonNull,result["image_path"])
        assertTrue(key in payload)
    }
    @Test fun anUnmarkedLegacyRowHasNoDeclaredPublication() {
        assertNull(localAssetImagePublication(asset.toCloudRecord()))
        assertEquals(asset.toCloudRecord().payload,assetPayloadForCloud(asset.toCloudRecord().payload))
    }
    @Test fun malformedOrUnknownOrForeignIntentIsHeldRatherThanTreatedAsKeep() {
        val raw=saved();val marker=raw.payload.getValue(key).jsonObject
        val bad=listOf<JsonElement>(JsonNull,JsonPrimitive("replace"),JsonObject(marker+("version" to JsonPrimitive(2))),
            JsonObject(marker+("revision" to JsonPrimitive("not-a-uuid"))),
            JsonObject(marker+("owner_user_id" to JsonPrimitive("88888888-8888-8888-8888-888888888888"))),
            JsonObject(marker+("previous_path" to JsonPrimitive("https://example.invalid/photo.jpg"))),
            JsonObject(marker+("candidate" to buildJsonObject{put("path",second.value);put("image_sha256","short");put("thumbnail_sha256","1".repeat(64))})))
        for(value in bad)assertTrue(runCatching{localAssetImagePublication(raw.copy(payload=JsonObject(raw.payload+(key to value))))}.exceptionOrNull() is IllegalArgumentException)
        assertTrue(runCatching{localAssetImagePublication(raw.copy(payload=JsonObject(raw.payload+("image_path" to JsonNull))))}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun knownEquivalentRemovalRetryDoesNotReplaceTheActualNewerRevision() {
        val raw=saved(true);val current=InvestmentAssetRecord.fromCloudRecord(raw)
        val pub=publication(true).copy(revision="88888888-8888-8888-8888-888888888888")
        val draft=InvestmentAssetDraft(id,channelId,"Cards","VND","box",asset,InvestmentAssetImageChange.Remove)
        val plan=planInvestmentAssetImageSave(source(raw),InvestmentAssetImageSaveRequest(draft,pub),device,now)
        assertTrue(plan.mutations.isEmpty());assertEquals(current,plan.asset)
        assertEquals(publication(true),localAssetImagePublication(raw))
    }
    @Test fun serverTimestampFormattingCannotMakeAnUnchangedArchivedAssetStale() {
        val expected=asset.copy(isArchived=true,archivedAt=old)
        val remote=expected.copy(archivedAt="2026-10-20T00:00:00.000+00:00",syncVersion=expected.syncVersion+1)
        val plan=planInvestmentAssetMutation(source(remote.toCloudRecord()),InvestmentAssetRequest.Archive(expected,false),device,now)
        assertFalse(plan.asset.isArchived);assertNull(plan.asset.archivedAt)
        assertEquals(1,plan.mutations.size)
        assertFalse(expected.matchesVisibleInvestmentAsset(remote.copy(archivedAt="2026-10-20T00:00:01Z")))
    }

}
