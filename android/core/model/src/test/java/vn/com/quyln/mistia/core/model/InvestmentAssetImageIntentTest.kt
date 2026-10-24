package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentAssetImageIntentTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val assetId="22222222-2222-2222-2222-222222222222"
    private val channel="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val old="2026-10-20T00:00:00Z";private val now="2026-10-24T00:00:00Z"
    private val first=InvestmentProductImagePath.create(owner,assetId,"55555555-5555-5555-5555-555555555555")
    private val second=InvestmentProductImagePath.create(owner,assetId,"66666666-6666-6666-6666-666666666666")
    private val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards","VND",first.value,"box",0,false,null,old,old,null,9007199254740993L,device)
    private fun snapshot(existing:InvestmentAssetRecord?=asset):InvestmentAssetSnapshot {
        val rawChannel=InvestmentChannelRecord(channel,owner.value,"Shop","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,old,old,null,0,device).toCloudRecord()
        val records=listOfNotNull(rawChannel,existing?.toCloudRecord()?.let{it.copy(payload=JsonObject(it.payload+("future_flag" to JsonPrimitive("keep"))))})
        return InvestmentAssetSnapshot(owner,records)
    }
    private fun draft(change:InvestmentAssetImageChange,expected:InvestmentAssetRecord?=asset)=InvestmentAssetDraft(assetId,channel,"Cards","VND","box",expected,change)
    @Test fun replaceChangesOnlyTheOwnedImageAndRetainsUnknownAndLongMetadata() {
        val p=planInvestmentAssetMutation(snapshot(),InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Replace(second))),device,now)
        assertEquals(second.value,p.asset.imagePath);assertEquals(1,p.mutations.size)
        assertEquals(JsonPrimitive("keep"),p.mutations.single().first.payload["future_flag"]);assertEquals(9007199254740993L,p.mutations.single().second.baseVersion)
        assertEquals("Cards",p.asset.name);assertEquals(old,p.asset.createdAt)
    }
    @Test fun removalEmitsExplicitNullAndKeepPreservesTheStoredPhoto() {
        val removed=planInvestmentAssetMutation(snapshot(),InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Remove)),device,now)
        assertNull(removed.asset.imagePath);assertSame(JsonNull,removed.mutations.single().first.payload["image_path"])
        val kept=planInvestmentAssetMutation(snapshot(),InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Keep)),device,now)
        assertEquals(first.value,kept.asset.imagePath)
    }
    @Test fun imageFromAnotherOwnerOrAssetCannotBeAttached() {
        val paths=listOf(InvestmentProductImagePath.create(UserId("77777777-7777-7777-7777-777777777777"),assetId,"88888888-8888-8888-8888-888888888888"),
            InvestmentProductImagePath.create(owner,"99999999-9999-9999-9999-999999999999","88888888-8888-8888-8888-888888888888"))
        for(path in paths)assertTrue(runCatching{planInvestmentAssetMutation(snapshot(),InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Replace(path))),device,now)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun aNewerPhotoCannotBeOverwrittenThroughAnOldAssetBaseline() {
        val current=snapshot(asset.copy(imagePath=second.value))
        val e=runCatching{planInvestmentAssetMutation(current,InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Remove)),device,now)}.exceptionOrNull()
        assertEquals(InvestmentAssetError.STALE_RECORD,(e as? InvestmentAssetException)?.reason)
    }
    @Test fun createRetryNeverReplacesTheExistingPhotoAndExplicitReplacementMustMatch() {
        val request=InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Replace(first),null))
        val p=planInvestmentAssetMutation(snapshot(null),request,device,now)
        val after=InvestmentAssetSnapshot(owner,snapshot(null).rows+p.mutations.map{it.first})
        assertTrue(planInvestmentAssetMutation(after,request,device,now).mutations.isEmpty())
        val kept=planInvestmentAssetMutation(after,InvestmentAssetRequest.Save(draft(InvestmentAssetImageChange.Keep,null)),device,now)
        assertTrue(kept.mutations.isEmpty());assertEquals(first.value,kept.asset.imagePath)
        for(change in listOf(InvestmentAssetImageChange.Remove,InvestmentAssetImageChange.Replace(second))) {
            val e=runCatching{planInvestmentAssetMutation(after,InvestmentAssetRequest.Save(draft(change,null)),device,now)}.exceptionOrNull()
            assertEquals(InvestmentAssetError.STALE_RECORD,(e as? InvestmentAssetException)?.reason)
        }
    }
    private fun publication(remove:Boolean=false)=InvestmentProductImagePublication(owner.value,assetId,"77777777-7777-7777-7777-777777777777",first.value,
        if(remove)null else InvestmentProductImageCandidate(owner.value,assetId,second.value,"0".repeat(64),"1".repeat(64)))
    @Test fun exactImageMetadataRetryAfterAckNeverRewritesThePrimary() {
        val request=InvestmentAssetImageSaveRequest(draft(InvestmentAssetImageChange.Replace(second)),publication())
        val firstSave=planInvestmentAssetImageSave(snapshot(),request,device,now)
        val current=firstSave.asset.copy(syncVersion=Long.MAX_VALUE-9,updatedAt="2026-10-24T01:00:00Z")
        val after=snapshot(current)
        val retry=planInvestmentAssetImageSave(after,request,device,"2026-10-24T02:00:00Z")
        assertTrue(retry.mutations.isEmpty());assertEquals(current,retry.asset)
    }
    @Test fun exactRemovalMetadataRetryRetainsExplicitAbsenceWithoutAnotherWrite() {
        val request=InvestmentAssetImageSaveRequest(draft(InvestmentAssetImageChange.Remove),publication(true))
        val firstSave=planInvestmentAssetImageSave(snapshot(),request,device,now)
        assertNull(firstSave.asset.imagePath)
        assertTrue(planInvestmentAssetImageSave(snapshot(firstSave.asset),request,device,now).mutations.isEmpty())
    }
    @Test fun anUnrelatedMetadataEditCannotBePassedOffAsTheCommittedImageResult() {
        val request=InvestmentAssetImageSaveRequest(draft(InvestmentAssetImageChange.Replace(second)),publication())
        val changed=snapshot(asset.copy(imagePath=second.value,name="Newer name"))
        val error=runCatching{planInvestmentAssetImageSave(changed,request,device,now)}.exceptionOrNull()
        assertEquals(InvestmentAssetError.STALE_RECORD,(error as? InvestmentAssetException)?.reason)
    }
    @Test fun imageTicketMustMatchTheFrozenPreviousAndProposedImageIdentity() {
        val d=draft(InvestmentAssetImageChange.Replace(second));val pub=publication()
        for(bad in listOf(pub.copy(previousPath=null),pub.copy(assetId="88888888-8888-8888-8888-888888888888"),pub.copy(candidate=null))) {
            val error=runCatching{planInvestmentAssetImageSave(snapshot(),InvestmentAssetImageSaveRequest(d,bad),device,now)}.exceptionOrNull()
            assertEquals(InvestmentAssetError.STALE_RECORD,(error as? InvestmentAssetException)?.reason)
        }
    }

}
