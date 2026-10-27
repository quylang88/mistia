package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradePublicationSnapshotTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-26T00:00:00Z"
    private val base=9007199254740993L
    private fun row(entity:CloudEntity=CloudEntity.INVESTMENT_TRADE,identity:String=id)=CloudRecord(entity.table,identity,owner.value,buildJsonObject {
        put("id",identity);put("user_id",owner.value);put("updated_at",now);put("created_at",now);put("sync_version",base);put("deleted_at",JsonNull);put("last_modified_by_device_id",device)
    },now,null,base)
    private fun queue(row:CloudRecord=row())=QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,base,device),3,45000,"network_io",true)
    private fun source()=InvestmentTradePublicationSnapshot(owner,id,listOf(row()),listOf(queue()),setOf(CloudEntity.INVESTMENT_TRADE.table to id))
    @Test fun exactCurrentQueueMatchesTheSameOwnedDirtyRowWithLongAndRetryStamps() {
        val s=source();s.requireCoherent();assertTrue(s.matches(queue()));assertEquals(row(),s.requestedRecord);assertEquals(queue(),s.requestedQueue)
    }
    @Test fun queueChangesInRetryErrorRemoteObservationOrPayloadCannotReuseTheOldProof() {
        val s=source();val q=queue()
        for(changed in listOf(q.copy(attemptCount=4),q.copy(nextAttemptAtEpochMillis=46000),q.copy(lastError="http_503"),q.copy(remoteIdentityObserved=false),
            q.copy(mutation=q.mutation.copy(payload=JsonObject(q.mutation.payload!!+("future" to JsonPrimitive(true)))))))assertFalse(s.matches(changed))
    }
    @Test fun everyPendingRowRequiresExactPayloadBaseDeviceDateAndDirtyProof() {
        val s=source();val q=queue()
        for(changed in listOf(q.copy(mutation=q.mutation.copy(baseVersion=base-1)),q.copy(mutation=q.mutation.copy(deviceId=id)),
            q.copy(mutation=q.mutation.copy(modifiedAt="2026-10-26T00:01:00Z")),q.copy(mutation=q.mutation.copy(payload=JsonObject(row().payload+("name" to JsonPrimitive("Unqueued")))))))
            assertTrue(runCatching{s.copy(pending=listOf(changed)).requireCoherent()}.isFailure)
        assertTrue(runCatching{s.copy(dirtyKeys=emptySet()).requireCoherent()}.isFailure)
    }
    @Test fun orphanQueuesDirtyRowsAndDuplicateIdentitiesAreNotCoherent() {
        val s=source()
        for(changed in listOf(s.copy(rows=emptyList()),s.copy(pending=emptyList()),s.copy(rows=s.rows+s.rows),s.copy(pending=s.pending+s.pending)))
            assertTrue(runCatching{changed.requireCoherent()}.isFailure)
    }
    @Test fun foreignOwnerBodyOrEntityCannotContaminateTheFinancialReadGeneration() {
        val s=source();val foreign=row(identity=device).copy(ownerUserId=id)
        val wrongBody=row(identity=device).let{it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(id))))}
        val wrongEntity=row(CloudEntity.SAVINGS_GOAL,device)
        for(raw in listOf(foreign,wrongBody,wrongEntity))assertTrue(runCatching{s.copy(rows=s.rows+raw).requireCoherent()}.isFailure)
        assertTrue(runCatching{s.copy(owner=UserId(id)).requireCoherent()}.isFailure)
    }
    @Test fun aReorderedGenerationIsUnchangedButChangedFinancialInputsRevokeIt() {
        val s=source();val wallet=row(CloudEntity.LEDGER_WALLET,device);val current=s.copy(rows=s.rows+wallet)
        current.requireUnchanged(current.copy(rows=current.rows.reversed()))
        assertTrue(runCatching{current.requireUnchanged(current.copy(rows=s.rows+wallet.copy(payload=JsonObject(wallet.payload+("opening_balance_minor" to JsonPrimitive(200))))))}.isFailure)
        assertTrue(runCatching{current.requireUnchanged(current.copy(tradeId=device))}.isFailure)
    }
    @Test fun anotherCurrentTradeQueueCannotBeAcknowledgedAsTheRequestedTrade() {
        val s=source();val other=row(identity=device);val q=queue(other)
        val complete=s.copy(rows=s.rows+other,pending=s.pending+q,dirtyKeys=s.dirtyKeys+(other.entity to other.id))
        complete.requireCoherent();assertFalse(complete.matches(q));assertTrue(complete.matches(queue()))
    }
    @Test fun cleanReadsAndDeleteQueuesKeepTheirDistinctDirtyAndTombstoneStates() {
        val s=source();s.copy(pending=emptyList(),dirtyKeys=emptySet()).requireCoherent()
        val dead=row().let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        val q=queue(dead).let{it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE))}
        val source=s.copy(rows=listOf(dead),pending=listOf(q));source.requireCoherent();assertTrue(source.matches(q))
        assertTrue(runCatching{source.copy(pending=listOf(q.copy(mutation=q.mutation.copy(kind=MutationKind.UPSERT)))).requireCoherent()}.isFailure)
    }
}
