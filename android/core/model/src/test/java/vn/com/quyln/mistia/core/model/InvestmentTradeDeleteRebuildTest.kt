package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradeDeleteRebuildTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val asset="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val ids=(1..4).map{"44444444-4444-4444-4444-"+it.toString().padStart(12,'0')}
    private val now="2026-10-27T00:00:00Z"
    private fun row(id:String,version:Long=10)=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("asset_id",asset);put("channel_id",asset);put("kind_raw_value","buy")
        put("quantity_decimal_string","1");put("unit_label","box");put("gross_amount_minor",0);put("currency_code","VND")
        put("accounting_gross_amount_minor",0);put("accounting_currency_code","VND");put("funding_wallet_id",JsonNull);put("capital_return_wallet_id",JsonNull)
        put("created_at",now);put("occurred_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",version);put("last_modified_by_device_id",device)
    },now,null,version)
    private fun source(rows:List<CloudRecord>,requested:String)=InvestmentTradePublicationSnapshot(owner,requested,rows,rows.map{raw->
        QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_TRADE,raw.id,owner.value,if(raw.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,raw.payload,raw.updatedAt!!,raw.syncVersion,device),2,1000,"network_io")
    },rows.map{it.entity to it.id}.toSet())
    private fun stamped(raw:CloudRecord,version:Long,date:String,deleted:String?=raw.deletedAt)=raw.copy(syncVersion=version,updatedAt=date,deletedAt=deleted,payload=JsonObject(raw.payload-LOCAL_TRADE_PUBLICATION_PARENTS_KEY+buildJsonObject {
        put("sync_version",version);put("updated_at",date);put("deleted_at",deleted?.let(::JsonPrimitive) ?: JsonNull);put("last_modified_by_device_id",device)
    }))
    private fun localDelete(raw:CloudRecord,date:String)=investmentAssetChanged(raw,buildJsonObject{put("deleted_at",date)},device,date).copy(deletedAt=date)
    private fun receipt():InvestmentTradePublicationReceipt {
        val before=ids.take(2).map{row(it)};val date="2026-10-27T00:15:00Z"
        val s=source(before.map{localDelete(it,date)},ids[0]);val sent=s.requestedRecord!!.let{it.copy(payload=investmentTradePayloadForCloud(it.payload))}
        val after=before.map{stamped(it,11,date,if(it.id==ids[0])date else null)}
        return InvestmentTradePublicationReceipt(s,sent,10,listOf(after.first()),setOf(asset),InvestmentTradeDeleteRebuild(before,after))
    }
    @Test fun fourOldestFirstLocalDeletionsRetainExplicitPeerEvidenceAcrossEveryDefiniteServerRebuild() {
        var server=ids.map{row(it)}
        var local=server.mapIndexed{index,raw->localDelete(raw,"2026-10-27T00:15:0${index}Z")}
        for(id in ids.reversed()) {
            val current=source(local,id);val before=server;val savedAt=current.requestedRecord!!.deletedAt!!
            server=server.map{raw->if(raw.deletedAt!=null)raw else stamped(raw,raw.syncVersion+1,savedAt,if(raw.id==id)savedAt else null)}
            val saved=server.single{it.id==id};val sent=current.requestedRecord!!.let{it.copy(payload=investmentTradePayloadForCloud(it.payload))}
            val r=InvestmentTradePublicationReceipt(current,sent,before.single{it.id==id}.syncVersion,listOf(saved),setOf(asset),InvestmentTradeDeleteRebuild(before,server))
            val changed=planInvestmentTradePublicationReceipt(r,current).associateBy{it.id};local=local.map{changed[it.id] ?: it}
            for(peer in server.filter{it.deletedAt==null})assertTrue("Missing definite peer receipt at version ${peer.syncVersion}",isKnownPriorInvestmentTradePublication(local.single{it.id==peer.id},peer,device))
        }
        assertTrue(local.all{it.syncVersion==10L && it.deletedAt!=null})
    }
    @Test fun aValidDeleteTraceProvesOnlyItsUnchangedActiveSibling() {
        val r=receipt();assertEquals(listOf(ids[1]),investmentTradeDeleteRebuildPeers(r).map{it.id})
        assertEquals(setOf(ids[0],ids[1]),planInvestmentTradePublicationReceipt(r,r.source).map{it.id}.toSet())
    }
    @Test fun malformedOrRacedDeleteTracesCannotCreateCausalAuthority() {
        val r=receipt();val trace=r.deleteRebuild!!;val peer=trace.after.last()
        fun altered(fields:JsonObject)=peer.copy(payload=JsonObject(peer.payload+fields))
        val variants=listOf(
            trace.copy(before=trace.before+trace.before.first()),
            trace.copy(after=trace.after.dropLast(1)),
            trace.copy(after=trace.after+row(ids[2])),
            trace.copy(after=trace.after.dropLast(1)+stamped(peer,12,peer.updatedAt!!)),
            trace.copy(after=trace.after.dropLast(1)+stamped(peer,11,"2026-10-27T00:16:00Z")),
            trace.copy(after=trace.after.dropLast(1)+altered(buildJsonObject{put("note","another user proposal")})),
            trace.copy(after=trace.after.dropLast(1)+altered(buildJsonObject{put("last_modified_by_device_id",asset)})),
            trace.copy(after=trace.after.dropLast(1)+altered(buildJsonObject{put(LOCAL_TRADE_PUBLICATION_PARENTS_KEY,JsonNull)})),
            trace.copy(after=trace.after.dropLast(1)+peer.copy(ownerUserId=asset,payload=JsonObject(peer.payload+("user_id" to JsonPrimitive(asset))))),
        )
        for(broken in variants)assertThrows(IllegalArgumentException::class.java){investmentTradeDeleteRebuildPeers(r.copy(deleteRebuild=broken))}
    }
    @Test fun aDeleteTraceMustBeBoundToTheDefiniteRequestedCasReply() {
        val r=receipt();val t=r.deleteRebuild!!
        for(broken in listOf(r.copy(expectedVersion=9),r.copy(returned=listOf(t.after.last())),r.copy(returned=emptyList()),
            r.copy(deleteRebuild=t.copy(after=t.before)),r.copy(deleteRebuild=t.copy(before=t.after))))
            assertThrows(IllegalArgumentException::class.java){investmentTradeDeleteRebuildPeers(broken)}
    }
    @Test fun anActiveMutationCannotClaimADeleteRebuildTrace() {
        val r=receipt();val before=r.deleteRebuild!!.before.first()
        assertThrows(IllegalArgumentException::class.java){investmentTradeDeleteRebuildPeers(r.copy(sent=before))}
    }
}
