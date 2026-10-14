package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.pendingMutation
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class DueOccurrencePushCoordinatorTest {
    @Test fun `gate off has zero remote requests and preserves pending mutation`()=runTest {
        val local=FakeLocalStore(record(0),queued(0));val remote=FakeRemoteStore()
        assertEquals(DomainPushSummary(),DueOccurrencePushCoordinator(local,remote,false).pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls);assertEquals(0,remote.writeCalls);assertNotNull(local.queued)
    }
    @Test fun `new skipped occurrence creates at version one with nullable clears`()=runTest {
        val local=FakeLocalStore(record(0),queued(0));val remote=FakeRemoteStore().apply {createdResult=record(1)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(kotlinx.serialization.json.JsonNull,remote.createdPayload!!["linked_transaction_id"])
        assertEquals(1L,remote.createdPayload!!.long("sync_version"));assertNull(local.queued)
    }
    @Test fun `paid occurrence waits for linked transaction including delete retry`()=runTest {
        val paid=record(0,linked=TX)
        val local=FakeLocalStore(paid,queued(0).let {it.copy(mutation=it.mutation.copy(payload=paid.payload))}).apply {transactionPendingIds=setOf(TX)}
        val remote=FakeRemoteStore().apply {createdResult=record(1,linked=TX)}
        assertEquals(DomainPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls);assertNotNull(local.queued)
        local.record=deleted(0,linked=TX);local.queued=queued(0).let {it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE,payload=local.record!!.payload))}
        assertEquals(DomainPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls)
        local.transactionPendingIds=emptySet();remote.fetched=null
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
    }
    @Test fun `source bill pending defers live occurrence but not independent tombstone`()=runTest {
        val local=FakeLocalStore(record(0),queued(0)).apply {sourcePendingIds=setOf(SOURCE)}
        val remote=FakeRemoteStore()
        assertEquals(DomainPushSummary(),coordinator(local,remote).pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls)
        local.record=deleted(0);local.queued=queued(0).let {it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE,payload=local.record!!.payload))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
    }
    @Test fun `conditional update preserves exact amount version and explicit linked nullable`()=runTest {
        val local=FakeLocalStore(record(9007199254740993L),queued(9007199254740993L))
        val remote=FakeRemoteStore().apply {fetched=record(9007199254740993L,amount=1);updatedResult=record(9007199254740994L)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(9007199254740993L,remote.updateExpectedVersion)
        assertEquals(9007199254740993L,remote.updatedPayload!!.long("amount_minor_snapshot"))
    }
    @Test fun `equal scheduled and paid instants ACK without changing original server representation`()=runTest {
        val local=FakeLocalStore(record(3,linked=TX),queued(3));val remote=FakeRemoteStore().apply {
            fetched=record(4,linked=TX).let {it.copy(payload=JsonObject(it.payload+("scheduled_date" to JsonPrimitive("2026-10-13T09:00:00+09:00"))+("paid_at" to JsonPrimitive("2026-10-13T09:00:00+09:00"))))}
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(0,remote.writeCalls)
        assertEquals("2026-10-13T09:00:00+09:00",local.record!!.payload.string("paid_at"))
    }
    @Test fun `stale ACK cannot clear replacement local undo mutation`()=runTest {
        val local=FakeLocalStore(record(0),queued(0));val newer=queued(0).let {it.copy(mutation=it.mutation.copy(modifiedAt=LATER))}
        val remote=FakeRemoteStore().apply {createdResult=record(1);onFetch={local.queued=newer;local.record=deleted(0)}}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertSame(newer,local.queued);assertNotNull(local.record!!.deletedAt)
    }
    @Test fun `create race refetch ACKs equal occurrence without overwrite`()=runTest {
        val local=FakeLocalStore(record(0),queued(0));val remote=FakeRemoteStore().apply {
            createFailure=SupabaseHttpException(409,"race");fetchResults.add(null);fetchResults.add(record(1))
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(1,remote.writeCalls);assertNull(local.queued)
    }
    @Test fun `foreign payload or invalid numeric amount fail before remote IO`()=runTest {
        listOf("user_id" to JsonPrimitive(OTHER),"amount_minor_snapshot" to JsonPrimitive("123")).forEach {(key,value) ->
            val bad=record(3).let {it.copy(payload=JsonObject(it.payload+(key to value)))}
            val local=FakeLocalStore(bad,queued(3));val remote=FakeRemoteStore()
            assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).permanentFailures)
            assertEquals(0,remote.fetchCalls)
        }
    }
    @Test fun `foreign remote response cannot ACK an owned outbox`()=runTest {
        val local=FakeLocalStore(record(3),queued(3));val remote=FakeRemoteStore().apply {fetched=record(4).copy(ownerUserId=OTHER)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).permanentFailures)
        assertNotNull(local.queued);assertEquals(3L,local.record!!.syncVersion)
    }
    @Test fun `HTTP retry and cancellation preserve pending occurrence`()=runTest {
        val local=FakeLocalStore(record(3),queued(3));val remote=FakeRemoteStore().apply {fetchFailure=SupabaseHttpException(503,"retry")}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).retryableFailures)
        assertTrue(local.queued!!.nextAttemptAtEpochMillis>NOW_MILLIS)
        val fresh=FakeLocalStore(record(3),queued(3));remote.fetchFailure=CancellationException("cancel")
        try {coordinator(fresh,remote).pushPending(UserId(OWNER),TOKEN);org.junit.Assert.fail("cancel swallowed")} catch(expected:CancellationException) {}
        assertEquals(0,fresh.queued!!.attemptCount)
    }
    @Test fun `live linked ledger retains undo when paid occurrence is absent deleted or incompatible`()=runTest {
        val liveLedger=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,TX,OWNER,JsonObject(mapOf(
            "id" to JsonPrimitive(TX), "user_id" to JsonPrimitive(OWNER), "deleted_at" to kotlinx.serialization.json.JsonNull,
        )),NOW,null,3)
        val wrongCycle=record(4,linked=TX).let {it.copy(payload=JsonObject(it.payload+("selected_month_key" to JsonPrimitive("2026-11"))))}
        listOf(null,deleted(4,linked=TX),wrongCycle).forEach {remoteOccurrence ->
            val tombstone=deleted(3,linked=TX)
            val pending=queued(3).let {it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE,payload=tombstone.payload))}
            val local=FakeLocalStore(tombstone,pending)
            val remote=FakeRemoteStore().apply {fetchResults.add(liveLedger);fetchResults.add(remoteOccurrence)}
            assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).conflicts)
            assertEquals(0,remote.writeCalls)
            assertEquals(Long.MAX_VALUE,local.queued!!.nextAttemptAtEpochMillis)
            assertNotNull(local.record!!.deletedAt)
        }
    }
    @Test fun `restoring remote paid occurrence cannot erase a newer same clock mutation`()=runTest {
        val tombstone=deleted(3,linked=TX)
        val pending=queued(3).let {it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE,payload=tombstone.payload))}
        val local=FakeLocalStore(tombstone,pending)
        val ledger=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,TX,OWNER,JsonObject(mapOf(
            "id" to JsonPrimitive(TX), "user_id" to JsonPrimitive(OWNER), "deleted_at" to kotlinx.serialization.json.JsonNull,
        )),NOW,null,3)
        val replacement=pending.copy(mutation=pending.mutation.copy(kind=MutationKind.UPSERT))
        val remote=FakeRemoteStore().apply {
            fetchResults.add(ledger);fetchResults.add(record(4,linked=TX))
            onFetch={if(fetchCalls==2) local.queued=replacement}
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertSame(replacement,local.queued)
        assertEquals(0,remote.writeCalls)
    }
    private fun coordinator(local:LocalStore,remote:RemoteMutationStore)=DueOccurrencePushCoordinator(local,remote,true) {NOW_MILLIS}
    private fun queued(version:Long)=QueuedMutation(vn.com.quyln.mistia.core.model.DueOccurrenceRecord.fromCloudRecord(record(version)).pendingMutation(),0,0,null)
    private fun record(version:Long,amount:Long=9007199254740993L,linked:String?=null)=vn.com.quyln.mistia.core.model.DueOccurrenceRecord(
        ID,OWNER,"recurringBill",SOURCE,"2026-10","2026-10-13T00:00:00Z",amount,if(linked==null) "skipped" else "paid",
        if(linked==null) null else "2026-10-13T00:00:00Z",linked,NOW,NOW,null,version,DEVICE).toCloudRecord()
    private fun deleted(version:Long,linked:String?=null)=record(version,linked=linked).let {it.copy(deletedAt=LATER,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(LATER))))}
    private class FakeLocalStore(
        var record: CloudRecord?,
        var queued: QueuedMutation?,
    ) : LocalStore {
        var transactionPendingIds: Set<String> = emptySet()
        var sourcePendingIds: Set<String> = emptySet()
        private val records = MutableStateFlow(emptyList<CloudRecord>())
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> = records
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) =
            record?.takeIf {it.ownerUserId==ownerUserId.value && it.entity==entity && it.id==recordId}
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ): List<QueuedMutation> = listOfNotNull(queued).filter {
            it.mutation.subjectUserId == ownerUserId.value &&
                it.mutation.entity == entity &&
                it.nextAttemptAtEpochMillis <= dueAtEpochMillis
        }

        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean {
            if (queued != mutation) return false
            queued = null
            record = remoteRecord
            return true
        }

        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ): Boolean {
            if (queued != mutation) return false
            queued = mutation.copy(
                attemptCount = mutation.attemptCount + 1,
                nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
                lastError = errorCode,
            )
            return true
        }

        override suspend fun replacePullSnapshot(
            ownerUserId: UserId,
            entity: String,
            records: List<CloudRecord>,
        ) = Unit
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) =
            if (entity == CloudEntity.RECURRING_BILL_PLAN.table) sourcePendingIds
            else if (entity == CloudEntity.LEDGER_TRANSACTION.table) transactionPendingIds
            else listOfNotNull(queued).filter { it.mutation.subjectUserId == ownerUserId.value && it.mutation.entity.table == entity }
                .mapTo(mutableSetOf()) { it.mutation.recordId }
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
    }

    private class FakeRemoteStore : RemoteMutationStore {
        var fetched: CloudRecord? = null
        var fetchFailure: Throwable? = null
        var createdResult: CloudRecord? = null
        var createFailure: Throwable? = null
        var updatedResult: CloudRecord? = null
        var createdPayload: JsonObject? = null
        var updatedPayload: JsonObject? = null
        var updateExpectedVersion: Long? = null
        var onFetch: (() -> Unit)? = null
        var onUpdate: (() -> Unit)? = null
        var fetchCalls = 0
        var writeCalls = 0
        val fetchResults = ArrayDeque<CloudRecord?>()

        override suspend fun fetchRecord(
            entity: CloudEntity,
            recordId: String,
            accessToken: String,
            ownerUserId: UserId,
        ): CloudRecord? {
            fetchCalls++
            onFetch?.invoke()
            fetchFailure?.let { throw it }
            return if (fetchResults.isNotEmpty()) fetchResults.removeFirst() else fetched
        }

        override suspend fun createRecord(
            entity: CloudEntity,
            accessToken: String,
            ownerUserId: UserId,
            payload: JsonObject,
        ): CloudRecord {
            writeCalls++
            createdPayload = payload
            createFailure?.let { throw it }
            return requireNotNull(createdResult)
        }

        override suspend fun conditionalUpdate(
            entity: CloudEntity,
            recordId: String,
            accessToken: String,
            ownerUserId: UserId,
            expectedVersion: Long,
            payload: JsonObject,
        ): CloudRecord? {
            writeCalls++
            updateExpectedVersion = expectedVersion
            updatedPayload = payload
            onUpdate?.invoke()
            return updatedResult
        }
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content
    private fun JsonObject.long(key: String) = (get(key) as JsonPrimitive).content.toLong()

    private companion object {
        const val OWNER="11111111-1111-1111-1111-111111111111"
        const val ID="22222222-2222-2222-2222-222222222222"
        const val SOURCE="33333333-3333-3333-3333-333333333333"
        const val TX="44444444-4444-4444-4444-444444444444"
        const val DEVICE="55555555-5555-5555-5555-555555555555"
        const val OTHER="66666666-6666-6666-6666-666666666666"
        const val TOKEN="test-token"
        const val NOW="2026-10-13T00:00:00Z"
        const val LATER="2026-10-13T01:00:00Z"
        const val NOW_MILLIS=1791849600000L
    }
}
