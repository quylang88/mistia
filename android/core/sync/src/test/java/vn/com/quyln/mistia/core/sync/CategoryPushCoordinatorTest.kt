package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
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

class CategoryPushCoordinatorTest {
    @Test
    fun `new category preserves explicit nulls uses version one and acknowledges`() = runTest {
        val queued = queued(CATEGORY_ID, baseVersion = 0)
        val local = FakeLocalStore(mapOf(CATEGORY_ID to localRecord()), mutableListOf(queued))
        val remote = FakeRemoteStore().apply { createdResults.add(remoteRecord(version = 1)) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(1L, remote.createdPayloads.single().long("sync_version"))
        assertTrue(remote.createdPayloads.single()["name_english"] is JsonNull)
        assertEquals(1L, local.records[CATEGORY_ID]?.syncVersion)
        assertTrue(local.queued.isEmpty())
    }

    @Test
    fun `existing category conditionally updates from its base version`() = runTest {
        val local = FakeLocalStore(
            mapOf(CATEGORY_ID to localRecord(version = 7)),
            mutableListOf(queued(CATEGORY_ID, baseVersion = 7)),
        )
        val remote = FakeRemoteStore().apply {
            fetchedResults.add(remoteRecord(version = 7, name = "Remote before"))
            updatedResults.add(remoteRecord(version = 8))
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(7L, remote.updateExpectedVersions.single())
        assertEquals(8L, remote.updatedPayloads.single().long("sync_version"))
        assertTrue(local.queued.isEmpty())
    }

    @Test
    fun `semantic equality acknowledges the server representation without writing`() = runTest {
        val local = FakeLocalStore(
            mapOf(CATEGORY_ID to localRecord(version = 3)),
            mutableListOf(queued(CATEGORY_ID, baseVersion = 3)),
        )
        val remote = FakeRemoteStore().apply {
            fetchedResults.add(remoteRecord(version = 4, updatedAt = LATER))
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.acknowledged)
        assertEquals(0, remote.writeCalls)
        assertEquals(4L, local.records[CATEGORY_ID]?.syncVersion)
    }

    @Test
    fun `category parents are pushed before children regardless of edit time`() = runTest {
        val parentQueued = queued(PARENT_ID, baseVersion = 0, modifiedAt = LATER)
        val childQueued = queued(CHILD_ID, baseVersion = 0, modifiedAt = NOW)
        val local = FakeLocalStore(
            mapOf(
                PARENT_ID to localRecord(id = PARENT_ID),
                CHILD_ID to localRecord(id = CHILD_ID, parentId = PARENT_ID),
            ),
            mutableListOf(childQueued, parentQueued),
        )
        val remote = FakeRemoteStore().apply {
            createdResults.add(remoteRecord(id = PARENT_ID, version = 1))
            createdResults.add(remoteRecord(id = CHILD_ID, version = 1, parentId = PARENT_ID))
        }

        coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(listOf(PARENT_ID, CHILD_ID), remote.createdPayloads.map { it.string("id") })
    }

    @Test
    fun `create race refetches and accepts the winning remote category`() = runTest {
        val local = FakeLocalStore(mapOf(CATEGORY_ID to localRecord()), mutableListOf(queued(CATEGORY_ID, 0)))
        val remote = FakeRemoteStore().apply {
            fetchedResults.add(null)
            fetchedResults.add(remoteRecord(version = 1, updatedAt = LATER))
            createFailures.add(SupabaseHttpException(409, "duplicate"))
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.acknowledged)
        assertEquals(2, remote.fetchCalls)
        assertTrue(local.queued.isEmpty())
    }

    @Test
    fun `conditional update race retains unresolved mutation`() = runTest {
        val local = FakeLocalStore(
            mapOf(CATEGORY_ID to localRecord(version = 3)),
            mutableListOf(queued(CATEGORY_ID, 3)),
        )
        val remote = FakeRemoteStore().apply {
            fetchedResults.add(remoteRecord(version = 3, name = "Before"))
            fetchedResults.add(remoteRecord(version = 3, name = "Concurrent", updatedAt = NOW))
            updatedResults.add(null)
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.conflicts)
        assertEquals(Long.MAX_VALUE, local.queued.single().nextAttemptAtEpochMillis)
        assertEquals("conflict_same_clock_version_different_payload", local.queued.single().lastError)
    }

    @Test
    fun `later local category wins a version conflict with conditional force update`() = runTest {
        val local = FakeLocalStore(
            mapOf(CATEGORY_ID to localRecord(version = 2, updatedAt = LATER)),
            mutableListOf(queued(CATEGORY_ID, 2)),
        )
        val remote = FakeRemoteStore().apply {
            fetchedResults.add(remoteRecord(version = 5, name = "Remote", updatedAt = NOW))
            updatedResults.add(remoteRecord(version = 6, updatedAt = LATER))
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(5L, remote.updateExpectedVersions.single())
        assertEquals(6L, remote.updatedPayloads.single().long("sync_version"))
    }

    @Test
    fun `force update race retains category mutation for review`() = runTest {
        val local = FakeLocalStore(
            mapOf(CATEGORY_ID to localRecord(version = 2, updatedAt = LATER)),
            mutableListOf(queued(CATEGORY_ID, 2)),
        )
        val remote = FakeRemoteStore().apply {
            fetchedResults.add(remoteRecord(version = 5, name = "Remote", updatedAt = NOW))
            updatedResults.add(null)
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.conflicts)
        assertEquals("conflict_force_update_race", local.queued.single().lastError)
        assertEquals(Long.MAX_VALUE, local.queued.single().nextAttemptAtEpochMillis)
    }

    @Test
    fun `later remote category wins and replaces local row`() = runTest {
        val local = FakeLocalStore(
            mapOf(CATEGORY_ID to localRecord(version = 2)),
            mutableListOf(queued(CATEGORY_ID, 2)),
        )
        val remoteWinner = remoteRecord(version = 5, name = "Remote", updatedAt = LATER)
        val remote = FakeRemoteStore().apply { fetchedResults.add(remoteWinner) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.acknowledged)
        assertEquals("Remote", local.records[CATEGORY_ID]?.payload?.string("name"))
    }

    @Test
    fun `stale response cannot remove a newer category mutation`() = runTest {
        val old = queued(CATEGORY_ID, 0)
        val newer = queued(CATEGORY_ID, 0, modifiedAt = LATER)
        val local = FakeLocalStore(mapOf(CATEGORY_ID to localRecord()), mutableListOf(old)).apply {
            replacementOnAcknowledge = newer
        }
        val remote = FakeRemoteStore().apply { createdResults.add(remoteRecord(version = 1)) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.staleResponses)
        assertEquals(newer, local.queued.single())
    }

    @Test
    fun `transient failure records retry while cancellation leaves metadata untouched`() = runTest {
        val retryQueued = queued(CATEGORY_ID, 0)
        val retryLocal = FakeLocalStore(mapOf(CATEGORY_ID to localRecord()), mutableListOf(retryQueued))
        val retryRemote = FakeRemoteStore().apply {
            fetchFailures.add(SupabaseHttpException(503, "secret"))
        }

        val retry = coordinator(retryLocal, retryRemote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, retry.retryableFailures)
        assertEquals(NOW_MILLIS + 30_000, retryLocal.queued.single().nextAttemptAtEpochMillis)
        assertEquals("http_503", retryLocal.queued.single().lastError)

        val cancelQueued = queued(CATEGORY_ID, 0)
        val cancelLocal = FakeLocalStore(mapOf(CATEGORY_ID to localRecord()), mutableListOf(cancelQueued))
        val cancelRemote = FakeRemoteStore().apply { fetchFailures.add(CancellationException("cancel")) }
        val failure = runCatching {
            coordinator(cancelLocal, cancelRemote).pushPending(UserId(OWNER), TOKEN)
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
        assertSame(cancelQueued, cancelLocal.queued.single())
    }

    @Test
    fun `disabled category gate leaves network and outbox untouched`() = runTest {
        val original = queued(CATEGORY_ID, 0)
        val local = FakeLocalStore(mapOf(CATEGORY_ID to localRecord()), mutableListOf(original))
        val remote = FakeRemoteStore()

        val result = CategoryPushCoordinator(local, remote, writesEnabled = false) { NOW_MILLIS }
            .pushPending(UserId(OWNER), TOKEN)

        assertEquals(CategoryPushSummary(), result)
        assertSame(original, local.queued.single())
        assertEquals(0, remote.fetchCalls)
    }

    private fun coordinator(local: LocalStore, remote: RemoteMutationStore) =
        CategoryPushCoordinator(local, remote, writesEnabled = true) { NOW_MILLIS }

    private fun queued(id: String, baseVersion: Long, modifiedAt: String = NOW) = QueuedMutation(
        PendingMutation(
            CloudEntity.TRANSACTION_CATEGORY,
            id,
            OWNER,
            MutationKind.UPSERT,
            localRecord(id = id, version = baseVersion, updatedAt = modifiedAt).payload,
            modifiedAt,
            baseVersion,
            DEVICE,
        ),
        0,
        0,
        null,
    )

    private fun localRecord(
        id: String = CATEGORY_ID,
        version: Long = 0,
        name: String = "Local",
        updatedAt: String = NOW,
        parentId: String? = null,
    ) = record(id, version, name, updatedAt, parentId)

    private fun remoteRecord(
        id: String = CATEGORY_ID,
        version: Long,
        name: String = "Local",
        updatedAt: String = NOW,
        parentId: String? = null,
    ) = record(id, version, name, updatedAt, parentId)

    private fun record(id: String, version: Long, name: String, updatedAt: String, parentId: String?) = CloudRecord(
        CloudEntity.TRANSACTION_CATEGORY.table,
        id,
        OWNER,
        JsonObject(
            mapOf(
                "user_id" to JsonPrimitive(OWNER),
                "id" to JsonPrimitive(id),
                "name" to JsonPrimitive(name),
                "name_english" to JsonNull,
                "name_japanese" to JsonNull,
                "parent_category_id" to (parentId?.let(::JsonPrimitive) ?: JsonNull),
                "updated_at" to JsonPrimitive(updatedAt),
                "deleted_at" to JsonNull,
                "sync_version" to JsonPrimitive(version),
                "last_modified_by_device_id" to JsonPrimitive(DEVICE),
            )
        ),
        updatedAt,
        null,
        version,
    )

    private class FakeLocalStore(
        records: Map<String, CloudRecord>,
        val queued: MutableList<QueuedMutation>,
    ) : LocalStore {
        val records = records.toMutableMap()

        var replacementOnAcknowledge: QueuedMutation? = null
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            MutableStateFlow(records.values.toList())
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = records[recordId]
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ) = queued.filter {
            it.mutation.subjectUserId == ownerUserId.value &&
                it.mutation.entity == entity &&
                it.nextAttemptAtEpochMillis <= dueAtEpochMillis
        }.take(limit)

        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean {
            replacementOnAcknowledge?.let { newer ->
                queued.remove(mutation)
                queued.add(newer)
                replacementOnAcknowledge = null
                return false
            }
            if (!queued.remove(mutation)) return false
            records[remoteRecord.id] = remoteRecord
            return true
        }

        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ): Boolean {
            val index = queued.indexOf(mutation)
            if (index < 0) return false
            queued[index] = mutation.copy(
                attemptCount = mutation.attemptCount + 1,
                nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
                lastError = errorCode,
            )
            return true
        }

        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) =
            queued.mapTo(mutableSetOf()) { it.mutation.recordId }
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
    }

    private class FakeRemoteStore : RemoteMutationStore {
        val fetchedResults = ArrayDeque<CloudRecord?>()
        val fetchFailures = ArrayDeque<Throwable>()
        val createdResults = ArrayDeque<CloudRecord>()
        val createFailures = ArrayDeque<Throwable>()
        val updatedResults = ArrayDeque<CloudRecord?>()
        val createdPayloads = mutableListOf<JsonObject>()
        val updatedPayloads = mutableListOf<JsonObject>()
        val updateExpectedVersions = mutableListOf<Long>()
        var fetchCalls = 0
        var writeCalls = 0

        override suspend fun fetchRecord(
            entity: CloudEntity,
            recordId: String,
            accessToken: String,
            ownerUserId: UserId,
        ): CloudRecord? {
            fetchCalls++
            if (fetchFailures.isNotEmpty()) throw fetchFailures.removeFirst()
            return if (fetchedResults.isNotEmpty()) fetchedResults.removeFirst() else null
        }

        override suspend fun createRecord(
            entity: CloudEntity,
            accessToken: String,
            ownerUserId: UserId,
            payload: JsonObject,
        ): CloudRecord {
            writeCalls++
            createdPayloads.add(payload)
            if (createFailures.isNotEmpty()) throw createFailures.removeFirst()
            return createdResults.removeFirst()
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
            updateExpectedVersions.add(expectedVersion)
            updatedPayloads.add(payload)
            return if (updatedResults.isNotEmpty()) updatedResults.removeFirst() else null
        }
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content
    private fun JsonObject.long(key: String) = (get(key) as JsonPrimitive).content.toLong()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val CATEGORY_ID = "22222222-2222-2222-2222-222222222222"
        const val PARENT_ID = "44444444-4444-4444-4444-444444444444"
        const val CHILD_ID = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
