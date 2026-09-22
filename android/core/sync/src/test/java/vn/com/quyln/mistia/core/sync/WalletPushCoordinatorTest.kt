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

class WalletPushCoordinatorTest {
    @Test
    fun `new wallet is created at version one and acknowledged`() = runTest {
        val local = FakeLocalStore(localRecord(version = 0), queued(baseVersion = 0))
        val remote = FakeRemoteStore().apply { createdResult = remoteRecord(version = 1) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(1L, remote.createdPayload?.long("sync_version"))
        assertEquals(1L, local.record?.syncVersion)
        assertNull(local.queued)
    }

    @Test
    fun `existing wallet uses conditional version and increments payload version`() = runTest {
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
    fun `disabled wallet gate leaves outbox and network untouched`() = runTest {
        val original = queued(baseVersion = 0)
        val local = FakeLocalStore(localRecord(version = 0), original)
        val remote = FakeRemoteStore()

        val result = WalletPushCoordinator(local, remote, writesEnabled = false) { NOW_MILLIS }
            .pushPending(UserId(OWNER), TOKEN)

        assertEquals(WalletPushSummary(), result)
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

    private fun coordinator(local: LocalStore, remote: RemoteMutationStore) =
        WalletPushCoordinator(local, remote, writesEnabled = true) { NOW_MILLIS }

    private fun queued(baseVersion: Long) = QueuedMutation(
        mutation = PendingMutation(
            entity = CloudEntity.LEDGER_WALLET,
            recordId = WALLET_ID,
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

    private fun record(version: Long, name: String, updatedAt: String) = CloudRecord(
        entity = CloudEntity.LEDGER_WALLET.table,
        id = WALLET_ID,
        ownerUserId = OWNER,
        payload = JsonObject(
            mapOf(
                "user_id" to JsonPrimitive(OWNER),
                "id" to JsonPrimitive(WALLET_ID),
                "name" to JsonPrimitive(name),
                "updated_at" to JsonPrimitive(updatedAt),
                "deleted_at" to kotlinx.serialization.json.JsonNull,
                "sync_version" to JsonPrimitive(version),
                "last_modified_by_device_id" to JsonPrimitive(DEVICE),
            )
        ),
        updatedAt = updatedAt,
        deletedAt = null,
        syncVersion = version,
    )

    private class FakeLocalStore(
        var record: CloudRecord?,
        var queued: QueuedMutation?,
    ) : LocalStore {
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
            listOfNotNull(queued).mapTo(mutableSetOf()) { it.mutation.recordId }
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
            return updatedResult
        }
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content
    private fun JsonObject.long(key: String) = (get(key) as JsonPrimitive).content.toLong()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val WALLET_ID = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
