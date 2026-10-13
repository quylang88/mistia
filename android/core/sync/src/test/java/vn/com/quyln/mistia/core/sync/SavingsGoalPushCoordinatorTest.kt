package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
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

class SavingsGoalPushCoordinatorTest {
    @Test fun `equal target instants with different ISO formatting acknowledge without writing`() = runTest {
        val local=FakeLocalStore(localRecord(3),queued(3))
        val remote=FakeRemoteStore().apply {
            fetched=remoteRecord(3).let { it.copy(payload=JsonObject(it.payload+("target_date" to JsonPrimitive("2027-01-01T09:00:00+09:00")))) }
        }
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.acknowledged)
        assertEquals(0,remote.writeCalls)
        assertNull(local.queued)
        assertEquals("2027-01-01T09:00:00+09:00",local.record!!.payload.string("target_date"))
    }
    @Test fun `different target instant remains a genuine same clock conflict`() = runTest {
        val local=FakeLocalStore(localRecord(3),queued(3))
        val remote=FakeRemoteStore().apply {
            fetched=remoteRecord(3).let { it.copy(payload=JsonObject(it.payload+("target_date" to JsonPrimitive("2027-02-01T00:00:00Z")))) }
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).conflicts)
        assertEquals(1,remote.writeCalls) // Conditional race refetch still distinguishes the target dates.
        assertEquals("2027-01-01T00:00:00Z",local.record!!.payload.string("target_date"))
    }
    @Test
    fun `new goal is created at version one and acknowledged`() = runTest {
        val local = FakeLocalStore(localRecord(version = 0), queued(baseVersion = 0))
        val remote = FakeRemoteStore().apply { createdResult = remoteRecord(version = 1) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(1L, remote.createdPayload?.long("sync_version"))
        assertEquals(1L, local.record?.syncVersion)
        assertNull(local.queued)
    }

    @Test
    fun `existing goal uses conditional version and increments payload version`() = runTest {
        val local = FakeLocalStore(localRecord(version = 7), queued(baseVersion = 7))
        val remote = FakeRemoteStore().apply {
            fetched = remoteRecord(version = 7, name = "Remote before")
            updatedResult = remoteRecord(version = 8)
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(7L, remote.updateExpectedVersion)
        assertEquals(8L, remote.updatedPayload?.long("sync_version"))
        assertNull(local.queued)
    }

    @Test
    fun `semantic equality acknowledges server representation without writing`() = runTest {
        val local = FakeLocalStore(localRecord(version = 3), queued(baseVersion = 3))
        val remote = FakeRemoteStore().apply {
            fetched = remoteRecord(version = 4, updatedAt = LATER)
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.acknowledged)
        assertEquals(0, result.pushed)
        assertEquals(0, remote.writeCalls)
        assertEquals(4L, local.record?.syncVersion)
    }

    @Test
    fun `unresolved version conflict retains local mutation for review`() = runTest {
        val local = FakeLocalStore(localRecord(version = 3), queued(baseVersion = 3))
        val remote = FakeRemoteStore().apply {
            fetched = remoteRecord(version = 3, name = "Remote conflict")
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.conflicts)
        assertEquals(Long.MAX_VALUE, local.queued?.nextAttemptAtEpochMillis)
        assertEquals("conflict_same_clock_version_different_payload", local.queued?.lastError)
        assertEquals("Local", local.record?.payload?.string("name"))
    }

    @Test
    fun `transient failure persists bounded retry without dropping mutation`() = runTest {
        val original = queued(baseVersion = 0)
        val local = FakeLocalStore(localRecord(version = 0), original)
        val remote = FakeRemoteStore().apply { fetchFailure = SupabaseHttpException(503, "secret") }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.retryableFailures)
        assertEquals(1, local.queued?.attemptCount)
        assertEquals(NOW_MILLIS + 30_000, local.queued?.nextAttemptAtEpochMillis)
        assertEquals("http_503", local.queued?.lastError)
    }

    @Test
    fun `create race refetches and resolves the winning server row`() = runTest {
        val local = FakeLocalStore(localRecord(version = 0), queued(baseVersion = 0))
        val remote = FakeRemoteStore().apply {
            createFailure = SupabaseHttpException(409, "duplicate")
            fetchResults.add(null)
            fetchResults.add(remoteRecord(version = 1, updatedAt = LATER))
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.acknowledged)
        assertEquals(2, remote.fetchCalls)
        assertEquals(1L, local.record?.syncVersion)
        assertNull(local.queued)
    }

    @Test
    fun `disabled goal gate leaves outbox and network untouched`() = runTest {
        val original = queued(baseVersion = 0)
        val local = FakeLocalStore(localRecord(version = 0), original)
        val remote = FakeRemoteStore()

        val result = SavingsGoalPushCoordinator(local, remote, writesEnabled = false) { NOW_MILLIS }
            .pushPending(UserId(OWNER), TOKEN)

        assertEquals(SavingsGoalPushSummary(), result)
        assertSame(original, local.queued)
        assertEquals(0, remote.fetchCalls)
    }

    @Test
    fun `coroutine cancellation propagates without poisoning retry metadata`() = runTest {
        val original = queued(baseVersion = 0)
        val local = FakeLocalStore(localRecord(version = 0), original)
        val remote = FakeRemoteStore().apply { fetchFailure = CancellationException("cancelled") }

        val failure = runCatching {
            coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
        assertSame(original, local.queued)
    }

    @Test fun `another account cannot read or push this outbox`() = runTest {
        val original = queued(0)
        val local = FakeLocalStore(localRecord(0), original)
        val remote = FakeRemoteStore()
        assertEquals(SavingsGoalPushSummary(), coordinator(local, remote).pushPending(UserId(OTHER), TOKEN))
        assertEquals(0, remote.fetchCalls)
        assertSame(original, local.queued)
    }

    @Test fun `late create acknowledgement preserves a newer local mutation`() = runTest {
        val original = queued(0)
        val newer = original.copy(mutation = original.mutation.copy(modifiedAt = LATER))
        val local = FakeLocalStore(localRecord(0), original)
        val remote = FakeRemoteStore().apply {
            onFetch = { local.queued = newer; local.record = remoteRecord(0, name = "New edit", updatedAt = LATER) }
            createdResult = remoteRecord(1)
        }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.staleResponses)
        assertSame(newer, local.queued)
        assertEquals("New edit", local.record!!.payload.string("name"))
    }

    @Test fun `missing remote deletion acknowledges local tombstone without creating`() = runTest {
        val local = FakeLocalStore(deletedRecord(0), queuedDelete(0))
        val remote = FakeRemoteStore()
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.acknowledged)
        assertEquals(0, remote.writeCalls)
        assertEquals(NOW, local.record!!.deletedAt)
        assertNull(local.queued)
    }

    @Test fun `already deleted server representation is acknowledged without patch`() = runTest {
        val local = FakeLocalStore(deletedRecord(7), queuedDelete(7))
        val remote = FakeRemoteStore().apply { fetched = deletedRecord(8, LATER) }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.acknowledged)
        assertEquals(0, remote.writeCalls)
        assertEquals(8L, local.record!!.syncVersion)
    }

    @Test fun `same semantic live remote does not erase pending deletion and patch stays sparse`() = runTest {
        val local = FakeLocalStore(deletedRecord(7), queuedDelete(7))
        val remote = FakeRemoteStore().apply { fetched = remoteRecord(7); updatedResult = deletedRecord(8) }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.pushed)
        assertEquals(7L, remote.updateExpectedVersion)
        assertEquals(NOW, remote.updatedPayload!!.string("deleted_at"))
        assertEquals(8L, remote.updatedPayload!!.long("sync_version"))
        assertTrue("target_minor" !in remote.updatedPayload!!)
        assertTrue("linked_wallet_id" !in remote.updatedPayload!!)
        assertNull(local.queued)
    }

    @Test fun `delete conditional race refetches and preserves newer remote edit winner`() = runTest {
        val local = FakeLocalStore(deletedRecord(7), queuedDelete(7))
        val remote = FakeRemoteStore().apply {
            fetchResults.add(remoteRecord(7))
            fetchResults.add(remoteRecord(8, name = "Newer remote", updatedAt = LATER))
        }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.acknowledged)
        assertEquals(2, remote.fetchCalls)
        assertNull(local.record!!.deletedAt)
        assertEquals("Newer remote", local.record!!.payload.string("name"))
    }

    @Test fun `delete race with missing remote keeps a synthesized local tombstone`() = runTest {
        val local = FakeLocalStore(deletedRecord(7), queuedDelete(7))
        val remote = FakeRemoteStore().apply { fetchResults.add(remoteRecord(7)); fetchResults.add(null) }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.acknowledged)
        assertEquals(8L, local.record!!.syncVersion)
        assertEquals(NOW, local.record!!.deletedAt)
        assertNull(local.queued)
    }

    @Test fun `local delete winner patches current remote version and force race retains conflict`() = runTest {
        val local = FakeLocalStore(deletedRecord(7, LATER), queuedDelete(7, LATER))
        val remote = FakeRemoteStore().apply { fetched = remoteRecord(8); updatedResult = deletedRecord(9, LATER) }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.pushed)
        assertEquals(8L, remote.updateExpectedVersion)
        val retryLocal = FakeLocalStore(deletedRecord(7, LATER), queuedDelete(7, LATER))
        val race = FakeRemoteStore().apply { fetched = remoteRecord(8) }
        val conflict = coordinator(retryLocal, race).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, conflict.conflicts)
        assertEquals(Long.MAX_VALUE, retryLocal.queued!!.nextAttemptAtEpochMillis)
        assertEquals("conflict_force_delete_race", retryLocal.queued!!.lastError)
    }

    @Test fun `late delete response cannot acknowledge a replacement mutation`() = runTest {
        val original = queuedDelete(7)
        val newer = queuedDelete(7, LATER)
        val local = FakeLocalStore(deletedRecord(7), original)
        val remote = FakeRemoteStore().apply {
            fetched = remoteRecord(7); updatedResult = deletedRecord(8)
            onUpdate = { local.queued = newer; local.record = deletedRecord(7, LATER) }
        }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.staleResponses)
        assertSame(newer, local.queued)
        assertEquals(LATER, local.record!!.deletedAt)
    }

    @Test fun `version overflow never writes a negative sync version`() = runTest {
        val local = FakeLocalStore(localRecord(Long.MAX_VALUE), queued(Long.MAX_VALUE))
        val remote = FakeRemoteStore().apply { fetched = remoteRecord(Long.MAX_VALUE, name = "Old value") }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.permanentFailures)
        assertEquals(0, remote.writeCalls)
        assertEquals(Long.MAX_VALUE, local.queued!!.nextAttemptAtEpochMillis)
    }

    @Test fun `foreign server identity cannot acknowledge an owned mutation`() = runTest {
        val original = queued(3)
        val local = FakeLocalStore(localRecord(3), original)
        val remote = FakeRemoteStore().apply { fetched = remoteRecord(3).copy(ownerUserId = OTHER) }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.permanentFailures)
        assertEquals(original.mutation, local.queued!!.mutation)
        assertEquals(OWNER, local.record!!.ownerUserId)
    }

    @Test fun `pending wallet dependency defers goal without poisoning its retry state`() = runTest {
        val original = queued(0)
        val local = FakeLocalStore(localRecord(0), original).apply { walletPendingIds = setOf(WALLET_ID) }
        val remote = FakeRemoteStore()
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(SavingsGoalPushSummary(), result)
        assertSame(original, local.queued)
        assertEquals(0, remote.fetchCalls)
        local.walletPendingIds = emptySet()
        remote.createdResult = remoteRecord(1)
        assertEquals(1, coordinator(local, remote).pushPending(UserId(OWNER), TOKEN).pushed)
    }

    @Test fun `delete can acknowledge missing remote even while wallet remains pending`() = runTest {
        val local = FakeLocalStore(deletedRecord(0), queuedDelete(0)).apply { walletPendingIds = setOf(WALLET_ID) }
        val result = coordinator(local, FakeRemoteStore()).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.acknowledged)
        assertNull(local.queued)
    }

    @Test fun `later live local edit must not semantic ack an older remote tombstone`() = runTest {
        val live = remoteRecord(7, updatedAt = LATER)
        val pending = queued(7).let { it.copy(mutation = it.mutation.copy(payload = live.payload, modifiedAt = LATER)) }
        val local = FakeLocalStore(live, pending)
        val remote = FakeRemoteStore().apply { fetched = deletedRecord(8); updatedResult = remoteRecord(9, updatedAt = LATER) }
        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)
        assertEquals(1, result.pushed)
        assertEquals(8L, remote.updateExpectedVersion)
        assertNull(local.record!!.deletedAt)
        assertNull(local.queued)
    }

    private fun deletedRecord(version: Long, time: String = NOW): CloudRecord {
        val record = remoteRecord(version, updatedAt = time)
        return record.copy(deletedAt = time, payload = JsonObject(record.payload + ("deleted_at" to JsonPrimitive(time))))
    }
    private fun queuedDelete(version: Long, time: String = NOW) = queued(version).let {
        it.copy(mutation = it.mutation.copy(kind = MutationKind.DELETE, payload = deletedRecord(version, time).payload, modifiedAt = time))
    }

    private fun coordinator(local: LocalStore, remote: RemoteMutationStore) =
        SavingsGoalPushCoordinator(local, remote, writesEnabled = true) { NOW_MILLIS }

    private fun queued(baseVersion: Long) = QueuedMutation(
        mutation = PendingMutation(
            entity = CloudEntity.SAVINGS_GOAL,
            recordId = GOAL_ID,
            subjectUserId = OWNER,
            kind = MutationKind.UPSERT,
            payload = localRecord(baseVersion).payload,
            modifiedAt = NOW,
            baseVersion = baseVersion,
            deviceId = DEVICE,
        ),
        attemptCount = 0,
        nextAttemptAtEpochMillis = 0,
        lastError = null,
    )

    private fun localRecord(version: Long) = record(version, "Local", NOW)
    private fun remoteRecord(version: Long, name: String = "Local", updatedAt: String = NOW) =
        record(version, name, updatedAt)

    private fun record(version: Long, name: String, updatedAt: String) =
        vn.com.quyln.mistia.core.model.SavingsGoalRecord(
            GOAL_ID,OWNER,name,"mistia.goal.savings",9007199254740993L,100,
            "2027-01-01T00:00:00Z",WALLET_ID,"JPY",0,false,NOW,updatedAt,null,version,DEVICE,
        ).toCloudRecord()

    private class FakeLocalStore(
        var record: CloudRecord?,
        var queued: QueuedMutation?,
    ) : LocalStore {
        var walletPendingIds: Set<String> = emptySet()
        private val records = MutableStateFlow(emptyList<CloudRecord>())
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> = records
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = record
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
            if (entity == CloudEntity.LEDGER_WALLET.table) walletPendingIds
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
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val GOAL_ID = "22222222-2222-2222-2222-222222222222"
        const val WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val OTHER = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
