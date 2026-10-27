package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashEventPublicationSnapshotTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val other="44444444-4444-4444-4444-444444444444"
    private val posting="625e1715-81fd-57c6-91e1-596e53e42db5"
    private val now="2026-10-27T00:00:00Z"
    private val version=9007199254740993L
    private fun row(entity:CloudEntity,key:String)=CloudRecord(entity.table,key,owner.value,buildJsonObject {
        put("id",key);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
        put("sync_version",version);put("last_modified_by_device_id",device);put("opaque",Long.MAX_VALUE)
        if(entity==CloudEntity.LEDGER_TRANSACTION)put("settlement_role_raw_value","investmentCashDeposit")
    },now,null,version)
    private fun queue(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,version,device),0,0,null)
    private fun source():InvestmentCashEventPublicationSnapshot {
        val rows=listOf(row(CloudEntity.LEDGER_TRANSACTION,id),row(CloudEntity.INVESTMENT_POSTING,posting),row(CloudEntity.LEDGER_WALLET,other),row(CloudEntity.INVESTMENT_TRADE,device))
        val pending=rows.take(2).map(::queue)
        return InvestmentCashEventPublicationSnapshot(owner,id,rows,pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }
    private fun invalid(s:InvestmentCashEventPublicationSnapshot)=assertTrue(runCatching{s.requireCoherent()}.exceptionOrNull() is IllegalArgumentException)
    @Test fun anOwnedFourEntityGenerationIncludesEveryQueueBeyondTheUsualDueLimit() {
        val s=source();val extra=(1..102).map{row(CloudEntity.INVESTMENT_POSTING,"%08x-0000-4000-8000-000000000000".format(it))};val queues=extra.map(::queue)
        s.copy(rows=s.rows+extra,pending=s.pending+queues,dirtyKeys=s.dirtyKeys+queues.map{it.mutation.entity.table to it.mutation.recordId}).requireCoherent()
        assertEquals(version,s.requestedQueue!!.mutation.baseVersion)
    }
    @Test fun stalePayloadVersionDeviceAndModifiedTimeCannotGrantQueueAuthority() {
        val s=source();val q=s.pending.first()
        val alteredPayload=JsonObject(q.mutation.payload!!+("opaque" to JsonPrimitive(3)))
        val cases=listOf(
            q.copy(mutation=q.mutation.copy(payload=alteredPayload)),
            q.copy(mutation=q.mutation.copy(baseVersion=version-1)),
            q.copy(mutation=q.mutation.copy(deviceId=other)),
            q.copy(mutation=q.mutation.copy(modifiedAt="2026-10-27T01:00:00Z")),
        )
        cases.forEach{invalid(s.copy(pending=listOf(it,s.pending.last())))}
    }
    @Test fun foreignDuplicateDetachedOrUnsupportedRowsAndQueuesAreRejected() {
        val s=source();val ledger=s.requestedRecord!!
        invalid(s.copy(rows=s.rows+ledger));invalid(s.copy(pending=s.pending+s.pending.first()))
        invalid(s.copy(rows=s.rows.map{if(it==ledger)it.copy(ownerUserId=other) else it}))
        invalid(s.copy(rows=s.rows.map{if(it==ledger)it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other)))) else it}))
        invalid(s.copy(dirtyKeys=emptySet()));invalid(s.copy(dirtyKeys=s.dirtyKeys+(CloudEntity.LEDGER_WALLET.table to other)))
        invalid(s.copy(rows=s.rows+row(CloudEntity.TRANSACTION_CATEGORY,"55555555-5555-5555-5555-555555555555")))
        invalid(s.copy(eventId="not-a-uuid"))
    }
    @Test fun tombstonesRequireDeleteQueuesAndConsistentRowMetadata() {
        val s=source();val old=s.requestedRecord!!;val deleted=old.copy(deletedAt=now,payload=JsonObject(old.payload+("deleted_at" to JsonPrimitive(now))))
        val q=s.requestedQueue!!.copy(mutation=s.requestedQueue!!.mutation.copy(payload=deleted.payload))
        val changed=s.copy(rows=s.rows.map{if(it==old)deleted else it},pending=listOf(q,s.pending.last()))
        invalid(changed)
        changed.copy(pending=listOf(q.copy(mutation=q.mutation.copy(kind=MutationKind.DELETE)),s.pending.last())).requireCoherent()
        invalid(s.copy(rows=s.rows.map{if(it==old)it.copy(deletedAt=now) else it}))
    }
    @Test fun orderAloneDoesNotChangeTheGeneration() {
        val s=source();s.requireUnchanged(s.copy(rows=s.rows.reversed(),pending=s.pending.reversed()))
    }
    @Test fun unrelatedWalletChangesRevokeAnOtherwiseIdenticalCashDecision() {
        val s=source();val changed=s.copy(rows=s.rows.map{if(it.entity==CloudEntity.LEDGER_WALLET.table)it.copy(payload=JsonObject(it.payload+("opaque" to JsonPrimitive(42)))) else it})
        assertEquals(s.requestedQueue,changed.requestedQueue)
        assertTrue(runCatching{s.requireUnchanged(changed)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun retryAndRemoteObservationChangesArePartOfTheCapturedGeneration() {
        val s=source();val q=s.pending.last()
        for(next in listOf(q.copy(attemptCount=1),q.copy(nextAttemptAtEpochMillis=50000),q.copy(lastError="network_io"),q.copy(remoteIdentityObserved=true)))
            assertTrue(runCatching{s.requireUnchanged(s.copy(pending=listOf(s.pending.first(),next)))}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun onlyTheExactCurrentCashLedgerQueueCanActAsTheEventWriter() {
        val s=source();assertTrue(s.matches(s.requestedQueue!!));assertFalse(s.matches(s.pending.last()))
        val ledger=s.requestedRecord!!;val ordinary=ledger.copy(payload=JsonObject(ledger.payload+("settlement_role_raw_value" to JsonNull)))
        val q=s.requestedQueue!!.copy(mutation=s.requestedQueue!!.mutation.copy(payload=ordinary.payload))
        assertFalse(s.copy(rows=s.rows.map{if(it==ledger)ordinary else it},pending=listOf(q,s.pending.last())).matches(q))
        assertFalse(s.copy(rows=s.rows.map{if(it==ledger)it.copy(payload=JsonObject(it.payload+("opaque" to JsonPrimitive(9)))) else it}).matches(s.requestedQueue!!))
    }
}
