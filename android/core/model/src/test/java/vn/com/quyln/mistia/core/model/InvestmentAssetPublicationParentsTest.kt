package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentAssetPublicationParentsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channel="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-24T00:00:00Z"
    private fun row(version:Long=9007199254740993L,name:String="Before")=InvestmentAssetRecord(id,owner.value,channel,name,"VND",null,"box",0,false,null,now,now,null,version,device).toCloudRecord()
    private fun changed(before:CloudRecord,name:String="After")=investmentAssetChanged(before,buildJsonObject{put("name",name)},device,now)
    private fun server(before:CloudRecord,version:Long=before.syncVersion+1)=before.copy(syncVersion=version,payload=JsonObject(assetPayloadForCloud(before.payload)+( "sync_version" to JsonPrimitive(version))))
    @Test fun realProducerParentsProveOwnPreviousWriteDespiteLaterServerClock() {
        val old=row();val next=changed(old);val remote=server(old).copy(updatedAt="2026-10-24T23:00:00Z")
        assertTrue(isKnownPriorAssetPublication(next,remote,device,false))
        assertEquals(old.syncVersion,localAssetPublicationParents(next).single().baseVersion)
    }
    @Test fun actorVersionDeletedStateAndBusinessFingerprintMustAllMatch() {
        val before=row();val next=changed(before);val remote=server(before)
        val wrong=listOf(server(before,before.syncVersion+2),remote.copy(deletedAt=now),
            remote.copy(payload=JsonObject(remote.payload+("name" to JsonPrimitive("Unrelated")))),
            remote.copy(payload=JsonObject(remote.payload+("last_modified_by_device_id" to JsonPrimitive(channel)))))
        for(value in wrong)assertFalse(isKnownPriorAssetPublication(next,value,device,false))
    }
    @Test fun keepCanCompareMetadataButExplicitPhotoMustMatchItsParentPath() {
        val before=row();val next=changed(before);val remote=server(before).copy(payload=JsonObject(server(before).payload+("image_path" to JsonPrimitive("different"))))
        assertFalse(isKnownPriorAssetPublication(next,remote,device,false))
        assertTrue(isKnownPriorAssetPublication(next,remote,device,true))
    }
    @Test fun boundedJournalRetainsRecentDistinctParentsWithoutRecursivePayloads() {
        var current=row()
        repeat(100){current=changed(current,"Name $it")}
        val entries=localAssetPublicationParents(current)
        assertEquals(64,entries.size);assertEquals(64,entries.distinct().size)
        assertTrue(current.payload.getValue(LOCAL_ASSET_PUBLICATION_PARENTS_KEY).toString().length<25000)
        assertTrue(isKnownPriorAssetPublication(current,server(row(name="Name 98")),device,false))
        assertFalse(isKnownPriorAssetPublication(current,server(row()),device,false))
    }
    @Test fun unchangedBusinessProbeDoesNotGrowOrRewriteEvidence() {
        val next=changed(row())
        assertEquals(next.payload[LOCAL_ASSET_PUBLICATION_PARENTS_KEY],changed(next).payload[LOCAL_ASSET_PUBLICATION_PARENTS_KEY])
    }
    @Test fun confirmedReceiptPinsTheActualServerVersionInsteadOfGuessingFromLocalBase() {
        val before=row(0);val remote=server(before,8)
        val next=changed(before).withAssetPublicationParent(InvestmentAssetPublicationParent(7,8,device,false,
            investmentAssetPublicationFingerprint(remote.payload),investmentAssetPublicationFingerprint(remote.payload,true)))
        assertTrue(isKnownPriorAssetPublication(next,remote,device,false))
        assertFalse(isKnownPriorAssetPublication(next,server(before,9),device,false))
    }
    @Test fun strictMarkerCannotChangeOwnerSchemaOrAllowMalformedUnboundedEntries() {
        val next=changed(row());val marker=next.payload.getValue(LOCAL_ASSET_PUBLICATION_PARENTS_KEY).jsonObject
        val entry=marker.getValue("parents").jsonArray.single().jsonObject
        val bad=listOf<JsonElement>(JsonNull,JsonPrimitive("parent"),JsonObject(marker+("version" to JsonPrimitive(2))),
            JsonObject(marker+("owner_user_id" to JsonPrimitive(channel))),JsonObject(marker+("extra" to JsonNull)),
            JsonObject(marker+("parents" to JsonArray(emptyList()))),JsonObject(marker+("parents" to JsonArray(List(65){entry}))),
            JsonObject(marker+("parents" to JsonArray(listOf(JsonObject(entry+("base_version" to JsonPrimitive(-1))))))),
            JsonObject(marker+("parents" to JsonArray(listOf(JsonObject(entry+("fingerprint" to JsonPrimitive("short"))))))))
        for(value in bad)assertTrue(runCatching{localAssetPublicationParents(next.copy(payload=JsonObject(next.payload+(LOCAL_ASSET_PUBLICATION_PARENTS_KEY to value))))}.isFailure)
    }
    @Test fun malformedExistingEvidenceHoldsTheActualProducerInsteadOfLaunderingIt() {
        val before=row().copy(payload=JsonObject(row().payload+(LOCAL_ASSET_PUBLICATION_PARENTS_KEY to JsonNull)))
        assertTrue(runCatching{changed(before)}.isFailure)
    }
    @Test fun unrelatedOpaqueValuesRemainInWireDataAndItsFingerprint() {
        val before=row().copy(payload=JsonObject(row().payload+("opaque" to JsonPrimitive(Long.MAX_VALUE))))
        val next=changed(before)
        assertEquals(JsonPrimitive(Long.MAX_VALUE),assetPayloadForCloud(next.payload)["opaque"])
        assertNotEquals(investmentAssetPublicationFingerprint(row().payload),investmentAssetPublicationFingerprint(before.payload))
        assertTrue(LOCAL_ASSET_PUBLICATION_KEYS.none{it in assetPayloadForCloud(next.payload)})
    }
    @Test fun equivalentArchivedInstantsNormalizeButRealChangesStillDiffer() {
        val p=JsonObject(row().payload+("archived_at" to JsonPrimitive(now)))
        val equivalent=JsonObject(p+("archived_at" to JsonPrimitive("2026-10-24T00:00:00.000+00:00")))
        assertEquals(investmentAssetPublicationFingerprint(p),investmentAssetPublicationFingerprint(equivalent))
        assertNotEquals(investmentAssetPublicationFingerprint(p),investmentAssetPublicationFingerprint(JsonObject(p+("archived_at" to JsonPrimitive("2026-10-24T00:00:01Z")))))
    }
}
