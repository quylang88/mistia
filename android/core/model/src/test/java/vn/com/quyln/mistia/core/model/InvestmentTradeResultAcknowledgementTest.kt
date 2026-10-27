package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradeResultAcknowledgementTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-26T00:00:00Z"
    private val serverTime="2026-10-26T00:30:00Z"
    private data class Case(val source:InvestmentTradePublicationSnapshot,val cloud:InvestmentTradeCloudSnapshot)
    private fun fixture(cost:Long=70):Case {
        val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,0,device)
        val channelRow=InvestmentChannelRecord(channel,owner.value,"Shop","shippingbox.fill","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000).toMutation(owner,null,device,now).record
        val root=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record.let{
            it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))
        }
        val before=InvestmentPurchaseSnapshot(owner,listOf(asset.toCloudRecord(),channelRow,wallet,root))
        val request=InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",cost,cost,"VND",null,null,null,walletId,cost,null,null,now,now),asset,LedgerWalletRecord.fromCloudRecord(wallet),null,"Reserve")
        val plan=planInvestmentPurchase(before,request,device,now)
        val queues=plan.mutations.map{QueuedMutation(it.second,2,34000,"network_io",false)}
        val source=InvestmentTradePublicationSnapshot(owner,id,before.rows+plan.mutations.map{it.first},queues,plan.mutations.map{it.first.entity to it.first.id}.toSet())
        val rows=plan.mutations.map{(raw,_)->val version=if(raw.entity==CloudEntity.INVESTMENT_TRADE.table)2L else 1L
            raw.copy(syncVersion=version,updatedAt=serverTime,payload=JsonObject(raw.payload+buildJsonObject{put("sync_version",version);put("updated_at",serverTime)}))}
        return Case(source,InvestmentTradeCloudSnapshot(owner,setOf(assetId),rows))
    }
    private fun plan(f:Case)=planInvestmentTradeResultAcknowledgement(f.source,f.cloud,device,serverTime)
    private fun changed(raw:CloudRecord,fields:JsonObject)=raw.copy(payload=JsonObject(raw.payload+fields))
    private fun updateSource(f:Case,entity:CloudEntity,fields:JsonObject):Case {
        val old=f.source.rows.single{it.entity==entity.table && (entity!=CloudEntity.INVESTMENT_TRADE || it.id==id)}
        val current=changed(old,fields)
        return f.copy(source=f.source.copy(rows=f.source.rows.map{if(it.entity==old.entity && it.id==old.id)current else it},
            pending=f.source.pending.map{if(it.mutation.entity==entity && it.mutation.recordId==old.id)it.copy(mutation=it.mutation.copy(payload=current.payload)) else it}))
    }
    @Test fun completeBuyAcknowledgesExactTradeLedgerAndPostingAndImportsTheirRealVersions() {
        val f=fixture();val p=plan(f)
        assertEquals(3,p.acknowledgements.size);assertTrue(p.absentAcknowledgements.isEmpty());assertEquals(f.cloud.rows.toSet(),p.imports.toSet())
        assertEquals(f.source.pending.toSet(),p.acknowledgements.map{it.first}.toSet())
        assertEquals(2L,p.acknowledgements.single{it.first.mutation.entity==CloudEntity.INVESTMENT_TRADE}.second.syncVersion)
    }
    @Test fun aDifferentCurrentUserIntentCannotBeConsumedByAnOlderServerClockResult() {
        val f=updateSource(fixture(),CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("gross_amount_minor",90);put("accounting_gross_amount_minor",90)})
        assertTrue(runCatching{plan(f)}.isFailure)
    }
    @Test fun serverFifoAuthorityMayReplaceStaleReadonlyCachesAfterUserIntentMatches() {
        var f=updateSource(fixture(),CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("position_cost_basis_after_minor",999)})
        f=updateSource(f,CloudEntity.LEDGER_TRANSACTION,buildJsonObject{put("amount_minor",999)})
        val p=plan(f);assertEquals(3,p.acknowledgements.size)
        assertEquals(70L,p.imports.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
    }
    @Test fun unrelatedPendingWalletMutationIsNeverConsumedOrImported() {
        val f=fixture();val other=WalletDraft(id="77777777-7777-7777-7777-777777777777",name="Other",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now)
        val q=QueuedMutation(other.pending,0,0,null)
        val s=f.source.copy(rows=f.source.rows+other.record,pending=f.source.pending+q,dirtyKeys=f.source.dirtyKeys+(other.record.entity to other.record.id))
        val p=plan(f.copy(source=s));assertEquals(3,p.acknowledgements.size);assertFalse(p.acknowledgements.any{it.first==q});assertFalse(p.imports.any{it.id==other.record.id})
    }
    @Test fun aMissingActiveFinancialRowDefersTheEntireAcknowledgement() {
        val f=fixture();assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=f.cloud.rows.filterNot{it.entity==CloudEntity.LEDGER_TRANSACTION.table})))}.isFailure)
    }
    @Test fun incorrectActiveFinancialMoneyCurrencyRoleOrWalletCannotAuthorizeAnyAck() {
        val f=fixture()
        for(fields in listOf(buildJsonObject{put("amount_minor",71)},buildJsonObject{put("source_currency_code","JPY")},
            buildJsonObject{put("settlement_role_raw_value","investmentReconciliation")},buildJsonObject{put("source_wallet_id",device)})) {
            val rows=f.cloud.rows.map{if(it.entity==CloudEntity.LEDGER_TRANSACTION.table)changed(it,fields) else it}
            assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=rows)))}.isFailure)
        }
    }
    @Test fun foreignDuplicateOrUnrelatedEntityRowsAreRejectedBeforeAcknowledgement() {
        val f=fixture();val first=f.cloud.rows.first()
        val foreign=first.copy(ownerUserId=device,payload=JsonObject(first.payload+("user_id" to JsonPrimitive(device))))
        for(rows in listOf(f.cloud.rows+first,f.cloud.rows.filter{it!=first}+foreign,f.cloud.rows+f.source.rows.single{it.id==walletId}))
            assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=rows)))}.isFailure)
        assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(owner=UserId(device))))}.isFailure)
    }
    @Test fun unknownFutureIntentFieldsArePreservedAndCannotBeSilentlyDiscarded() {
        val f=updateSource(fixture(),CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("future_large",Long.MAX_VALUE);put("future_null",JsonNull)})
        assertTrue(runCatching{plan(f)}.isFailure)
        val rows=f.cloud.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)changed(it,buildJsonObject{put("future_large",Long.MAX_VALUE);put("future_null",JsonNull)}) else it}
        val p=plan(f.copy(cloud=f.cloud.copy(rows=rows)));assertEquals(JsonPrimitive(Long.MAX_VALUE),p.imports.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.payload["future_large"])
    }
    @Test fun postgresTimestampPrecisionDoesNotInventANewImmutableCreatedDateIntent() {
        val f=updateSource(fixture(),CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("created_at","2026-10-26T00:00:00.123456789Z")})
        val rows=f.cloud.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)changed(it,buildJsonObject{put("created_at","2026-10-26T00:00:00.123457Z")}) else it}
        assertEquals(3,plan(f.copy(cloud=f.cloud.copy(rows=rows))).acknowledgements.size)
    }
    private fun deleted(f:Case):Case {
        val rows=f.source.rows.map{raw->if(raw.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table))
            raw.copy(deletedAt=now,payload=JsonObject(raw.payload+("deleted_at" to JsonPrimitive(now)))) else raw}
        val byKey=rows.associateBy{it.entity to it.id}
        val queues=f.source.pending.map{q->q.copy(mutation=q.mutation.copy(kind=MutationKind.DELETE,payload=byKey[q.mutation.entity.table to q.mutation.recordId]!!.payload))}
        return f.copy(source=f.source.copy(rows=rows,pending=queues))
    }
    @Test fun neverPublishedDeletedTradeAndChildrenCanClearOnlyTheirExactAbsentQueues() {
        val f=deleted(fixture());val p=plan(f.copy(cloud=f.cloud.copy(rows=emptyList())))
        assertTrue(p.acknowledgements.isEmpty());assertEquals(f.source.pending.toSet(),p.absentAcknowledgements.toSet());assertTrue(p.imports.isEmpty())
    }
    @Test fun anObservedMissingDeletedRecordIsNotTreatedAsNeverPublished() {
        val initial=deleted(fixture());val f=initial.copy(source=initial.source.copy(pending=initial.source.pending.map{q->q.copy(remoteIdentityObserved=true)}))
        assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=emptyList())))}.isFailure)
    }
    @Test fun anOpaqueFieldNamedDeletedCannotShadowTheActualDeletionIntent() {
        val f=updateSource(fixture(),CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("deleted","local opaque value")})
        val rows=f.cloud.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)changed(it,buildJsonObject{put("deleted","different server value")}) else it}
        assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=rows)))}.isFailure)
    }
    @Test fun malformedRetiredFinancialFieldsCannotEnterTheCacheUnderAValidParentTombstone() {
        val f=deleted(fixture());val dead=f.cloud.rows.map{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        for((entity,fields) in listOf(CloudEntity.LEDGER_TRANSACTION to buildJsonObject{put("last_modified_by_device_id","bad")},
            CloudEntity.LEDGER_TRANSACTION to buildJsonObject{put("title",true)},CloudEntity.LEDGER_TRANSACTION to buildJsonObject{put("reporting_amount_minor","70")},
            CloudEntity.LEDGER_TRANSACTION to buildJsonObject{put("source_wallet_id",false)},CloudEntity.INVESTMENT_POSTING to buildJsonObject{put("wallet_id",device)})) {
            val rows=dead.map{if(it.entity==entity.table)changed(it,fields) else it}
            assertTrue(fields.toString(),runCatching{plan(f.copy(cloud=f.cloud.copy(rows=rows)))}.isFailure)
        }
    }
    @Test fun completeOwnedTombstonesAcknowledgeTheDeletedTradeAndItsRetiredChildren() {
        val f=deleted(fixture());val rows=f.cloud.rows.map{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        val p=plan(f.copy(cloud=f.cloud.copy(rows=rows)));assertEquals(3,p.acknowledgements.size);assertTrue(p.imports.all{it.deletedAt!=null})
    }
    private fun remoteWinner(f:Case,cost:Long=90):Case {
        val other="88888888-8888-8888-8888-888888888888"
        val rows=fixture(cost).cloud.rows.map{changed(it,buildJsonObject{put("last_modified_by_device_id",other)})}
        return f.copy(cloud=f.cloud.copy(rows=rows,remoteIntentWinners=setOf(id)))
    }
    @Test fun aProvenOtherDeviceRemoteWinnerReconcilesTheEntireFinancialResultTogether() {
        val f=remoteWinner(fixture());val p=plan(f);assertEquals(3,p.acknowledgements.size)
        assertEquals(90L,p.imports.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
        assertEquals(90L,p.imports.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.payload.financeRawLong("gross_amount_minor"))
    }
    @Test fun aRemoteWinnerRequestCannotOverrideALaterLocalClockOrAnUnprovenOwnReply() {
        val f=remoteWinner(fixture())
        val later=updateSource(f,CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("updated_at","2026-10-26T01:00:00Z")}).let{it.copy(source=it.source.copy(
            rows=it.source.rows.map{r->if(r.entity==CloudEntity.INVESTMENT_TRADE.table)r.copy(updatedAt="2026-10-26T01:00:00Z") else r},
            pending=it.source.pending.map{q->if(q.mutation.entity==CloudEntity.INVESTMENT_TRADE)q.copy(mutation=q.mutation.copy(modifiedAt="2026-10-26T01:00:00Z")) else q}))}
        assertTrue(runCatching{plan(later)}.isFailure)
        val own=f.copy(cloud=f.cloud.copy(rows=f.cloud.rows.map{changed(it,buildJsonObject{put("last_modified_by_device_id",device)})}))
        assertTrue(runCatching{plan(own)}.isFailure)
    }
    @Test fun completeOtherDeviceDeletionMayDefeatTheQueuedLiveIntentWithoutPartialFinancialAck() {
        val f=fixture();val rows=f.cloud.rows.map{r->r.copy(deletedAt=serverTime,payload=JsonObject(r.payload+buildJsonObject{put("deleted_at",serverTime);put("last_modified_by_device_id",walletId)}))}
        val p=plan(f.copy(cloud=f.cloud.copy(rows=rows,remoteIntentWinners=setOf(id))))
        assertEquals(3,p.acknowledgements.size);assertTrue(p.imports.all{it.deletedAt!=null})
    }
    @Test fun remoteWinnerCannotConsumeUnrelatedOrMissingTradeAuthority() {
        val f=remoteWinner(fixture())
        for(ids in listOf(setOf(walletId),setOf(id,walletId)))assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(remoteIntentWinners=ids)))}.isFailure)
        assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=f.cloud.rows.filterNot{it.entity==CloudEntity.INVESTMENT_TRADE.table})))}.isFailure)
    }

    @Test fun deletionDominatesSupersededLocalBusinessFieldsButStillImportsOnlyTheActualCloudTombstones() {
        val f=updateSource(deleted(fixture()),CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("note","discarded unpublished note");put("future_null",JsonNull)})
        val rows=f.cloud.rows.map{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        val p=plan(f.copy(cloud=f.cloud.copy(rows=rows)))
        assertEquals(3,p.acknowledgements.size);assertNull(p.imports.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.payload.financeRawString("note"))
        val changedCreated=rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)changed(it,buildJsonObject{put("created_at","2026-10-25T00:00:00Z")}) else it}
        assertTrue(runCatching{plan(f.copy(cloud=f.cloud.copy(rows=changedCreated)))}.isFailure)
    }

}
