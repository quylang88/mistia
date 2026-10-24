package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class InvestmentChannelAcknowledgementTest {
    @Test fun equivalentServerArchivedDateRetainsVisibleConsentButARealChangeDoesNot() {
        val now="2026-10-24T00:00:00Z"
        val before=InvestmentChannelRecord("22222222-2222-2222-2222-222222222222","11111111-1111-1111-1111-111111111111","Cards","chart.line.uptrend.xyaxis","#9A67FF",0,true,now,now,now,null,3,"33333333-3333-3333-3333-333333333333")
        val server=before.copy(archivedAt="2026-10-24T00:00:00.000+00:00",createdAt="2026-10-24T00:00:00.000+00:00",updatedAt="2026-10-24T01:00:00Z",syncVersion=9,lastModifiedByDeviceId=null)
        assertTrue(before.matchesVisibleInvestmentChannel(server))
        assertFalse(before.matchesVisibleInvestmentChannel(server.copy(name="Newer")))
        assertFalse(before.matchesVisibleInvestmentChannel(server.copy(archivedAt="2026-10-24T00:00:01Z")))
        assertFalse(before.matchesVisibleInvestmentChannel(server.copy(isArchived=false,archivedAt=null)))
    }
    @Test fun aQueueDeviceStampMustMatchTheStoredPayloadBeforeItCanAuthorizePublication() {
        val owner=UserId("11111111-1111-1111-1111-111111111111");val id="22222222-2222-2222-2222-222222222222"
        val device="33333333-3333-3333-3333-333333333333";val now="2026-10-24T00:00:00Z"
        val row=InvestmentChannelRecord(id,owner.value,"Cards","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_CHANNEL,id,owner.value,MutationKind.UPSERT,row.payload,now,0,"44444444-4444-4444-4444-444444444444"),0,0,null)
        assertFalse(InvestmentChannelPublicationSnapshot(owner,row,q,true).matches(q))
    }

}
