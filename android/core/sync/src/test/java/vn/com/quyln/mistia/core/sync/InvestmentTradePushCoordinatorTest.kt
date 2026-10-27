package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class InvestmentTradePushCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-26T00:00:00Z"
    private val serverTime="2026-10-26T00:30:00Z"
    private val token="investment-trade-token"
    private var session:AuthSession?=AuthSession(owner,null,token,"refresh",Long.MAX_VALUE)
    private data class Fixture(val source:InvestmentTradePublicationSnapshot,val cloud:InvestmentTradeCloudSnapshot)
    private fun fixture(cost:Long=70):Fixture {
        val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,0,device)
        val channelRow=InvestmentChannelRecord(channel,owner.value,"Shop","shippingbox.fill","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000).toMutation(owner,null,device,now).record
        val root=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record.let{
            it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))
        }
        val before=InvestmentPurchaseSnapshot(owner,listOf(asset.toCloudRecord(),channelRow,wallet,root))
        val request=InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",cost,cost,"VND",null,null,null,if(cost>0)walletId else null,if(cost>0)cost else null,null,null,now,now),asset,if(cost>0)LedgerWalletRecord.fromCloudRecord(wallet) else null,null,"Reserve")
        val plan=planInvestmentPurchase(before,request,device,now)
        val queues=plan.mutations.map{QueuedMutation(it.second,0,0,null,false)}
        val source=InvestmentTradePublicationSnapshot(owner,id,before.rows+plan.mutations.map{it.first},queues,plan.mutations.map{it.first.entity to it.first.id}.toSet())
        val rows=plan.mutations.map{(raw,_)->val version=if(raw.entity==CloudEntity.INVESTMENT_TRADE.table)2L else 1L
            raw.copy(syncVersion=version,updatedAt=serverTime,payload=JsonObject(raw.payload+buildJsonObject{put("sync_version",version);put("updated_at",serverTime)}))}
        return Fixture(source,InvestmentTradeCloudSnapshot(owner,setOf(assetId),rows))
    }
    private fun coordinator(store:Store,remote:Remote,enabled:Boolean=true)=InvestmentTradePushCoordinator(store,remote,enabled,{session},{4000})
    @Test fun createUsesOnlyTheClosedTradePortAndAtomicallyAcknowledgesItsFinancialChildren()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud)
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.pushed);assertTrue(store.data.pending.isEmpty());assertTrue(store.data.dirtyKeys.isEmpty())
        assertEquals(1,remote.writes);assertEquals(0L,remote.bases.single());assertEquals(1L,remote.proposals.single().syncVersion)
        assertEquals(70L,store.data.requestedRecord!!.payload.financeRawLong("gross_amount_minor"))
        assertEquals(2L,store.data.requestedRecord!!.syncVersion)
    }
    @Test fun matchingServerIntentAcknowledgesTheCompleteResultWithoutAnotherRpc()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{published[id]=f.cloud.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.acknowledged);assertEquals(0,remote.writes);assertTrue(store.data.pending.isEmpty())
    }
    @Test fun disabledGateDoesNotReadHttpOrWriteAnyBookkeeping()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud)
        assertEquals(DomainPushSummary(),coordinator(store,remote,false).pushPending(owner,token))
        assertEquals(0,store.reads);assertEquals(0,remote.fetches);assertEquals(0,remote.writes);assertEquals(f.source,store.data)
    }
    @Test fun futureBackoffIsPreservedWithoutHttp()=runTest {
        val f=fixture();val before=f.source.copy(pending=f.source.pending.map{it.copy(nextAttemptAtEpochMillis=5000)})
        val store=Store(before);val remote=Remote(f.cloud)
        assertEquals(DomainPushSummary(),coordinator(store,remote).pushPending(owner,token));assertEquals(before,store.data);assertEquals(0,remote.fetches)
    }
    @Test fun dirtyMetadataPrerequisiteDefersBeforeAnyTradeHttp()=runTest {
        val f=fixture();val asset=f.source.rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table}
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_ASSET,asset.id,owner.value,MutationKind.UPSERT,asset.payload,now,asset.syncVersion,device),0,0,null)
        val before=f.source.copy(pending=f.source.pending+q,dirtyKeys=f.source.dirtyKeys+(asset.entity to asset.id))
        val store=Store(before);val remote=Remote(f.cloud)
        assertEquals(DomainPushSummary(),coordinator(store,remote).pushPending(owner,token));assertEquals(before,store.data);assertEquals(0,remote.fetches)
    }
    @Test fun retryableNetworkFailureUpdatesOnlyTheExactTradeQueueWithASafeCode()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{fetchError=SupabaseHttpException(503,"private token body")}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).retryableFailures)
        val q=store.data.requestedQueue!!;assertEquals(1,q.attemptCount);assertEquals(34000L,q.nextAttemptAtEpochMillis);assertEquals("http_503",q.lastError)
        assertEquals(f.source.pending.filter{it.mutation.entity!=CloudEntity.INVESTMENT_TRADE},store.data.pending.filter{it.mutation.entity!=CloudEntity.INVESTMENT_TRADE})
    }
    @Test fun sameOwnerTokenRotationDuringFetchRevokesEveryWriteAndFailureRecord()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{onFetch={session=session!!.copy(accessToken="replaced")}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(f.source,store.data);assertEquals(0,remote.writes)
    }
    @Test fun malformedFinalFinancialResultRetainsAllDirtyChildrenForRetry()=runTest {
        val f=fixture();val store=Store(f.source);val cloud=f.cloud.copy(rows=f.cloud.rows.filterNot{it.entity==CloudEntity.LEDGER_TRANSACTION.table})
        val remote=Remote(cloud);val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.retryableFailures);assertEquals(3,store.data.pending.size);assertEquals(3,store.data.dirtyKeys.size)
        assertEquals(70L,store.data.requestedRecord!!.payload.financeRawLong("gross_amount_minor"))
    }

    private fun version(raw:CloudRecord,v:Long)=raw.copy(syncVersion=v,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(v))))
    private fun note(raw:CloudRecord,text:String)=raw.copy(payload=JsonObject(raw.payload+("note" to JsonPrimitive(text))))
    @Test fun invalidCapturedSessionCancelsBeforeReadingAnyOwnerPartition()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud);session=session!!.copy(accessToken="other-token")
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(0,store.reads);assertEquals(0,remote.fetches)
    }
    @Test fun zeroPromotionalBuyPublishesWithoutInventedFundingRows()=runTest {
        val f=fixture(0);val store=Store(f.source);val remote=Remote(f.cloud)
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed);assertTrue(store.data.pending.isEmpty())
        assertFalse(store.data.rows.any{it.entity in setOf(CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)})
    }
    @Test fun exactLongCasUsesTheComparedVersionAndTheAdditionalRebuildIncrement()=runTest {
        val f=fixture();val base=9007199254740993L
        val local=version(note(f.source.requestedRecord!!,"local"),base)
        val data=f.source.copy(rows=f.source.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)local else it},pending=f.source.pending.map{if(it.mutation.entity==CloudEntity.INVESTMENT_TRADE)it.copy(mutation=it.mutation.copy(baseVersion=base,payload=local.payload)) else it})
        val store=Store(data);val remote=Remote(f.cloud).apply{published[id]=version(note(f.cloud.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table},"old"),base)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(listOf(base),remote.bases);assertEquals(base+2,store.data.requestedRecord!!.syncVersion)
    }
    @Test fun createCollisionRefetchesAndAcknowledgesTheMatchingCompleteResult()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{
            writeError=SupabaseHttpException(409,"");onWrite={published[id]=f.cloud.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}}
        }
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(1,remote.writes);assertTrue(store.data.pending.isEmpty());assertTrue(remote.fetches>=2)
    }
    @Test fun casMissRefetchesTheOtherDevicesWinnerAndItsFinancialResult()=runTest {
        val f=fixture();val winner=fixture(90).cloud.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.let{it.copy(payload=JsonObject(it.payload+("last_modified_by_device_id" to JsonPrimitive(walletId))))}
        val store=Store(f.source);val remote=Remote(fixture(90).cloud).apply{
            published[id]=version(note(f.cloud.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table},"old"),0)
            misses=1;onWrite={published[id]=winner}
        }
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(90L,store.data.requestedRecord!!.payload.financeRawLong("gross_amount_minor"));assertEquals(1,remote.writes)
    }
    @Test fun anUnprovenOwnServerResultIsAnExplicitConflictWithoutConsumingAnyChild()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(fixture(90).cloud).apply{published[id]=prepared.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).conflicts)
        assertEquals(3,store.data.pending.size);assertEquals(0,remote.writes);assertEquals(Long.MAX_VALUE,store.data.requestedQueue!!.nextAttemptAtEpochMillis)
    }
    @Test fun observedMissingTradeIsHeldAsAConflictRatherThanCreatedAgain()=runTest {
        val f=fixture();val store=Store(f.source.copy(pending=f.source.pending.map{if(it.mutation.entity==CloudEntity.INVESTMENT_TRADE)it.copy(remoteIdentityObserved=true) else it}));val remote=Remote(f.cloud)
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).conflicts);assertEquals(0,remote.writes);assertEquals(3,store.data.pending.size)
    }
    @Test fun aLateDefiniteReplyDoesNotFailOrBackoffTheNewerActualLocalNote()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{onWrite={store.editNote("new note")}}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).staleResponses)
        val current=store.data;assertEquals("new note",current.requestedRecord!!.payload.financeRawString("note"))
        assertEquals(0,current.requestedQueue!!.attemptCount);assertEquals(0L,current.requestedQueue!!.nextAttemptAtEpochMillis)
        assertTrue(isKnownPriorInvestmentTradePublication(current.requestedRecord!!,remote.published.getValue(id),device))
        remote.onWrite=null
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(listOf(0L,2L),remote.bases);assertTrue(store.data.pending.isEmpty());assertEquals("new note",store.data.requestedRecord!!.payload.financeRawString("note"))
    }
    @Test fun aSessionRevokedDuringTheRpcCannotRecordAReceiptOrAcknowledgement()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{onWrite={session=null}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException);assertEquals(f.source,store.data)
    }
    @Test fun multiplePendingTradeIntentsPublishBeforeTheSingleWholeAssetReconciliation()=runTest {
        val f=fixture();val second="77777777-7777-7777-7777-777777777777";val source=f.source
        val rows=source.rows;val plan=planInvestmentPurchase(InvestmentPurchaseSnapshot(owner,rows),InvestmentPurchaseRequest(InvestmentPurchaseDraft(second,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(rows.single{it.id==walletId}),null,"Reserve"),device,now)
        val writes=plan.mutations.associateBy{it.first.entity to it.first.id}
        val data=source.copy(rows=rows.filterNot{it.entity to it.id in writes}+writes.values.map{it.first},pending=source.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in writes}+writes.values.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=source.dirtyKeys+writes.keys)
        val cloud=f.cloud.copy(rows=data.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.map{version(it,if(it.entity==CloudEntity.INVESTMENT_TRADE.table)2 else 1)})
        val store=Store(data);val remote=Remote(cloud)
        assertEquals(DomainPushSummary(pushed=2),coordinator(store,remote).pushPending(owner,token));assertEquals(2,remote.writes);assertEquals(1,store.acknowledgements);assertTrue(store.data.pending.isEmpty())
    }
    private fun deleted(f:Fixture):Fixture {
        val plan=planInvestmentTradeDeletion(InvestmentTradeDeletionSnapshot(owner,f.source.rows),InvestmentTradeDeletionRequest(f.source.requestedRecord!!,null,"Reserve"),device,now)
        val byKey=plan.mutations.associateBy{it.first.entity to it.first.id}
        val data=f.source.copy(rows=f.source.rows.filterNot{it.entity to it.id in byKey}+plan.mutations.map{it.first},pending=plan.mutations.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=byKey.keys)
        return f.copy(source=data)
    }
    @Test fun neverPublishedDeletionClearsOnlyItsAbsentTradeAndFinancialQueuesWithoutRpc()=runTest {
        val f=deleted(fixture());val store=Store(f.source);val remote=Remote(f.cloud.copy(rows=emptyList()))
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged);assertTrue(store.data.pending.isEmpty());assertEquals(0,remote.deletes);assertEquals(0,remote.writes)
    }
    @Test fun publishedDeletionUsesTheClosedDeleteRpcAndAcknowledgesTheActualTombstones()=runTest {
        val f=deleted(fixture());val store=Store(f.source);val remote=Remote(f.cloud).apply{published[id]=prepared.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed);assertEquals(1,remote.deletes);assertEquals(0,remote.writes)
        assertTrue(store.data.pending.isEmpty());assertEquals(3L,store.data.requestedRecord!!.syncVersion)
    }

    @Test fun fifoPublicationUsesOccurrenceOrderWhenTheEarlierBuyWasEditedAfterTheLaterSale()=runTest {
        val f=fixture();val saleId="77777777-7777-7777-7777-777777777777";val rows=f.source.rows
        val plan=planInvestmentSale(InvestmentSaleSnapshot(owner,rows),InvestmentSaleRequest(InvestmentSaleDraft(saleId,assetId,"1","box",80,80,"VND",null,null,null,walletId,null,null,"2026-10-26T00:01:00Z",now),
            InvestmentAssetRecord.fromCloudRecord(rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(rows.single{it.id==walletId}),null,"Reserve"),device,now)
        val keys=plan.mutations.map{it.first.entity to it.first.id}.toSet()
        val combined=f.source.copy(rows=rows.filterNot{it.entity to it.id in keys}+plan.mutations.map{it.first},pending=f.source.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys}+plan.mutations.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=f.source.dirtyKeys+keys)
        val editedAt="2026-10-26T01:00:00Z"
        val buy=combined.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}.let{it.copy(updatedAt=editedAt,payload=JsonObject(it.payload+("updated_at" to JsonPrimitive(editedAt))))}
        val data=combined.copy(rows=combined.rows.map{if(it.entity==buy.entity && it.id==buy.id)buy else it},pending=combined.pending.map{q->if(q.mutation.entity==CloudEntity.INVESTMENT_TRADE && q.mutation.recordId==id)q.copy(mutation=q.mutation.copy(payload=buy.payload,modifiedAt=editedAt)) else q})
        val cloud=f.cloud.copy(rows=data.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.map{version(it,if(it.entity==CloudEntity.INVESTMENT_TRADE.table)2 else 1)})
        val store=Store(data);val remote=Remote(cloud)
        assertEquals(2,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(listOf(id,saleId),remote.proposals.map{it.id});assertTrue(store.data.pending.isEmpty())
    }

    @Test fun aNewSaleWhoseAcquisitionIsBackedOffWaitsWithoutSendingAnInvalidIntermediateRpc()=runTest {
        val f=fixture();val saleId="77777777-7777-7777-7777-777777777777";val rows=f.source.rows
        val plan=planInvestmentSale(InvestmentSaleSnapshot(owner,rows),InvestmentSaleRequest(InvestmentSaleDraft(saleId,assetId,"1","box",80,80,"VND",null,null,null,walletId,null,null,"2026-10-26T00:01:00Z",now),
            InvestmentAssetRecord.fromCloudRecord(rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(rows.single{it.id==walletId}),null,"Reserve"),device,now)
        val keys=plan.mutations.map{it.first.entity to it.first.id}.toSet()
        val combined=f.source.copy(rows=rows.filterNot{it.entity to it.id in keys}+plan.mutations.map{it.first},pending=f.source.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys}+plan.mutations.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=f.source.dirtyKeys+keys)
        val data=combined.copy(pending=combined.pending.map{if(it.mutation.entity==CloudEntity.INVESTMENT_TRADE && it.mutation.recordId==id)it.copy(nextAttemptAtEpochMillis=5000) else it})
        val cloud=f.cloud.copy(rows=data.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.map{version(it,if(it.entity==CloudEntity.INVESTMENT_TRADE.table)2 else 1)})
        val store=Store(data);val remote=Remote(cloud)
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(0,remote.writes);assertEquals(1,result.retryableFailures);assertEquals(0,result.permanentFailures)
        val saleQueue=store.data.pending.single{it.mutation.entity==CloudEntity.INVESTMENT_TRADE && it.mutation.recordId==saleId}
        assertEquals("investment_trade_dependency_pending",saleQueue.lastError);assertEquals(34000L,saleQueue.nextAttemptAtEpochMillis)
        assertEquals(data.pending.single{it.mutation.entity==CloudEntity.INVESTMENT_TRADE && it.mutation.recordId==id},store.data.requestedQueue)
    }

    @Test fun aNonDependencyHttp403IsPermanentAndRetainsOnlyASafeStatusCode()=runTest {
        val f=fixture();val store=Store(f.source);val remote=Remote(f.cloud).apply{fetchError=SupabaseHttpException(403,"private response body")}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals(1,result.permanentFailures);assertEquals(0,result.retryableFailures);assertEquals("http_403",store.data.requestedQueue!!.lastError)
        assertEquals(Long.MAX_VALUE,store.data.requestedQueue!!.nextAttemptAtEpochMillis);assertEquals(3,store.data.pending.size)
    }
    @Test fun aBusinessDependencyRejectionCanBeRetriedAfterAnotherPendingTradeMakesProgress()=runTest {
        val f=fixture();val second="77777777-7777-7777-7777-777777777777";val source=f.source;val rows=source.rows
        val plan=planInvestmentPurchase(InvestmentPurchaseSnapshot(owner,rows),InvestmentPurchaseRequest(InvestmentPurchaseDraft(second,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(rows.single{it.id==walletId}),null,"Reserve"),device,now)
        val writes=plan.mutations.associateBy{it.first.entity to it.first.id}
        val data=source.copy(rows=rows.filterNot{it.entity to it.id in writes}+writes.values.map{it.first},pending=source.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in writes}+writes.values.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=source.dirtyKeys+writes.keys)
        val cloud=f.cloud.copy(rows=data.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.map{version(it,if(it.entity==CloudEntity.INVESTMENT_TRADE.table)2 else 1)})
        val store=Store(data);val remote=Remote(cloud).apply{writeError=SupabaseHttpException(400,"local prerequisite fixture")}
        assertEquals(DomainPushSummary(pushed=2),coordinator(store,remote).pushPending(owner,token));assertTrue(store.data.pending.isEmpty())
        assertEquals(listOf(id,second,id),remote.proposals.map{it.id})
    }

    @Test fun aDeferredOlderRejectedProposalCannotBackoffANewerLocalEdit()=runTest {
        val f=fixture();val saleId="77777777-7777-7777-7777-777777777777";val rows=f.source.rows
        val plan=planInvestmentSale(InvestmentSaleSnapshot(owner,rows),InvestmentSaleRequest(InvestmentSaleDraft(saleId,assetId,"1","box",80,80,"VND",null,null,null,walletId,null,null,"2026-10-26T00:01:00Z",now),
            InvestmentAssetRecord.fromCloudRecord(rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(rows.single{it.id==walletId}),null,"Reserve"),device,now)
        val keys=plan.mutations.map{it.first.entity to it.first.id}.toSet()
        val data=f.source.copy(rows=rows.filterNot{it.entity to it.id in keys}+plan.mutations.map{it.first},pending=f.source.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys}+plan.mutations.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=f.source.dirtyKeys+keys)
        val cloud=f.cloud.copy(rows=data.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.map{version(it,if(it.entity==CloudEntity.INVESTMENT_TRADE.table)2 else 1)})
        val store=Store(data);val remote=Remote(cloud).apply{writeError=SupabaseHttpException(400,"");onWrite={store.editNote("new local proposal")}}
        val result=coordinator(store,remote).pushPending(owner,token)
        assertEquals("new local proposal",store.data.requestedRecord!!.payload.financeRawString("note"))
        assertEquals(0,store.data.requestedQueue!!.attemptCount);assertEquals(0L,store.data.requestedQueue!!.nextAttemptAtEpochMillis)
        assertEquals(1,result.staleResponses);assertEquals(0,result.permanentFailures)
    }
    private inner class Store(var data:InvestmentTradePublicationSnapshot):LocalStore {
        var reads=0;var acknowledgements=0
        fun editNote(note:String) {
            val raw=data.requestedRecord!!;val rows=data.rows
            val plan=planInvestmentTradeEdit(InvestmentTradeCreationSnapshot(owner,rows),InvestmentTradeEditRequest(raw,InvestmentTradeEditDraft(id,assetId,InvestmentTradeKind.BUY,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,note,now,now),
                InvestmentAssetRecord.fromCloudRecord(rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(rows.single{it.id==walletId}),null,"Reserve"),device,"2026-10-26T00:15:00Z")
            val keys=plan.mutations.map{it.first.entity to it.first.id}.toSet()
            data=data.copy(rows=rows.filterNot{it.entity to it.id in keys}+plan.mutations.map{it.first},pending=data.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys}+plan.mutations.map{QueuedMutation(it.second,0,0,null)},dirtyKeys=data.dirtyKeys+keys)
        }
        override suspend fun investmentTradePublicationSnapshot(owner:UserId,tradeId:String):InvestmentTradePublicationSnapshot {require(owner==data.owner);reads++;return data.copy(tradeId=tradeId)}
        override suspend fun recordInvestmentTradePublicationReceipt(receipt:InvestmentTradePublicationReceipt,isSessionCurrent:()->Boolean):Int {
            check(isSessionCurrent());val changes=planInvestmentTradePublicationReceipt(receipt,data.copy(tradeId=receipt.source.tradeId));val map=changes.associateBy{it.entity to it.id}
            data=data.copy(rows=data.rows.map{map[it.entity to it.id] ?: it},pending=data.pending.map{q->map[q.mutation.entity.table to q.mutation.recordId]?.let{q.copy(mutation=q.mutation.copy(payload=it.payload))} ?: q});return changes.size
        }
        override suspend fun acknowledgeInvestmentTradeResult(expected:InvestmentTradePublicationSnapshot,candidate:InvestmentTradeCloudSnapshot,deviceId:String,now:String,isSessionCurrent:()->Boolean):Boolean {
            acknowledgements++
            check(isSessionCurrent());if(runCatching{expected.requireUnchanged(data.copy(tradeId=expected.tradeId))}.isFailure)return false
            val plan=planInvestmentTradeResultAcknowledgement(expected,candidate,deviceId,now)
            val keys=(plan.acknowledgements.map{it.first}+plan.absentAcknowledgements).map{it.mutation.entity.table to it.mutation.recordId}.toSet()
            if(keys.isEmpty())return false
            val imported=plan.imports.associateBy{it.entity to it.id}
            data=data.copy(rows=data.rows.map{imported[it.entity to it.id] ?: it}+plan.imports.filter{r->data.rows.none{it.entity==r.entity && it.id==r.id}},pending=data.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys},dirtyKeys=data.dirtyKeys-keys)
            return true
        }
        override suspend fun recordInvestmentTradeMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String,expected:InvestmentTradePublicationSnapshot,isSessionCurrent:()->Boolean):Boolean {
            check(isSessionCurrent());if(runCatching{expected.requireUnchanged(data.copy(tradeId=expected.tradeId))}.isFailure)return false
            data=data.copy(pending=data.pending.map{if(it==mutation)it.copy(attemptCount=it.attemptCount+1,nextAttemptAtEpochMillis=nextAttemptAtEpochMillis,lastError=errorCode) else it});return true
        }
        override fun observe(entity:String,ownerUserId:UserId)=MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId:UserId)=MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=error("Use atomic trade snapshot")
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=error("No generic trade mutation")
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int):List<QueuedMutation> = error("No capped trade queue selection")
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=error("No pull replacement")
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String):Set<String> = error("Use atomic trade dirty keys")
        override suspend fun clearAccount(ownerUserId:UserId)=error("No account clearing")
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord):Boolean=error("No generic trade ACK")
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean=error("No generic trade failure")
    }
    private inner class Remote(val prepared:InvestmentTradeCloudSnapshot):InvestmentTradeRemote {
        val published=linkedMapOf<String,CloudRecord>();var fetches=0;var writes=0;var reads=0;var deletes=0;var misses=0
        var fetchError:Exception?=null;var writeError:Exception?=null;var onFetch:(()->Unit)?=null;var onWrite:(()->Unit)?=null
        val bases=mutableListOf<Long>();val proposals=mutableListOf<CloudRecord>()
        override suspend fun fetchTrade(owner:UserId,id:String,accessToken:String):CloudRecord? {require(owner==prepared.owner && accessToken==token);fetches++;onFetch?.invoke();fetchError?.let{throw it};return published[id]}
        override suspend fun mutateTrade(owner:UserId,proposal:CloudRecord,expectedVersion:Long,affectedAssetIds:Set<String>,accessToken:String):InvestmentTradeMutationResult? {
            require(owner==prepared.owner && accessToken==token && affectedAssetIds==setOf(assetId));writes++;bases+=expectedVersion;proposals+=proposal;onWrite?.invoke()
            writeError?.let{writeError=null;throw it};if(misses>0){misses--;return null}
            val raw=prepared.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==proposal.id}
            val v=if(expectedVersion==0L)2 else proposal.syncVersion+1
            val saved=raw.copy(syncVersion=v,updatedAt=serverTime,payload=JsonObject(raw.payload+investmentTradePayloadForCloud(proposal.payload)+buildJsonObject{put("sync_version",v);put("updated_at",serverTime)}))
            published[proposal.id]=saved;return InvestmentTradeMutationResult(saved,published.values.toList())
        }
        override suspend fun fetchTradeResult(owner:UserId,affectedAssetIds:Set<String>,knownTradeIds:Set<String>,accessToken:String):InvestmentTradeCloudSnapshot {
            require(owner==prepared.owner && accessToken==token && affectedAssetIds==setOf(assetId));reads++
            val financial=prepared.rows.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table}.map{raw->
                val parent=published.values.singleOrNull{trade->listOf("funding","capital-return","profit-loss","funding-posting","capital-return-posting","profit-loss-posting","cash-accrual-posting").any{investmentLedgerIdentity(trade.id,it)==raw.id}}
                if(parent?.deletedAt!=null)raw.copy(deletedAt=parent.deletedAt,payload=JsonObject(raw.payload+("deleted_at" to JsonPrimitive(parent.deletedAt)))) else raw
            }
            return prepared.copy(rows=published.values.toList()+financial)
        }
        override suspend fun deleteTrade(owner:UserId,id:String,expectedVersion:Long,modifiedAt:String,deviceId:String,accessToken:String):CloudRecord? {
            require(owner==prepared.owner && accessToken==token && deviceId==device);deletes++
            val old=published[id] ?: return null
            val dead=old.copy(syncVersion=expectedVersion+1,deletedAt=modifiedAt,payload=JsonObject(old.payload+buildJsonObject{put("sync_version",expectedVersion+1);put("deleted_at",modifiedAt);put("last_modified_by_device_id",deviceId)}))
            published[id]=dead;return dead
        }
    }
}
