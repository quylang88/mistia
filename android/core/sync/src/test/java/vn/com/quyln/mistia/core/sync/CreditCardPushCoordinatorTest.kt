package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
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

class CreditCardPushCoordinatorTest {
    @Test
    fun `new profile is created at version one and acknowledged`() = runTest {
        val local = FakeLocalStore(localRecord(0), queued(0))
        val remote = FakeRemoteStore().apply { createdResult = remoteRecord(1) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(1L, remote.createdPayload?.long("sync_version"))
        assertEquals(WALLET_ID, remote.createdPayload?.string("wallet_id"))
        assertEquals(1L, local.record?.syncVersion)
        assertNull(local.queued)
    }

    @Test
    fun `existing profile uses conditional version and increments payload`() = runTest {
        val local = FakeLocalStore(localRecord(7), queued(7))
        val remote = FakeRemoteStore().apply {
            fetched = remoteRecord(7, issuer = "Remote before")
            updatedResult = remoteRecord(8)
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(7L, remote.expectedVersion)
        assertEquals(8L, remote.updatedPayload?.long("sync_version"))
        assertNull(local.queued)
    }

    @Test
    fun `transient failure keeps profile mutation with bounded retry`() = runTest {
        val local = FakeLocalStore(localRecord(0), queued(0))
        val remote = FakeRemoteStore().apply { fetchFailure = IOException("offline") }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.retryableFailures)
        assertEquals(NOW_MILLIS + 30_000, local.queued?.nextAttemptAtEpochMillis)
        assertEquals("network_io", local.queued?.lastError)
    }

    @Test
    fun `disabled profile gate leaves outbox and network untouched`() = runTest {
        val original = queued(0)
        val local = FakeLocalStore(localRecord(0), original)
        val remote = FakeRemoteStore()

        val result = CreditCardPushCoordinator(local, remote, writesEnabled = false) { NOW_MILLIS }
            .pushPending(UserId(OWNER), TOKEN)

        assertEquals(CreditCardPushSummary(), result)
        assertSame(original, local.queued)
        assertEquals(0, remote.fetchCalls)
    }

    private fun coordinator(local: LocalStore, remote: RemoteMutationStore) =
        CreditCardPushCoordinator(local, remote, writesEnabled = true) { NOW_MILLIS }

    private fun queued(baseVersion: Long) = QueuedMutation(
        mutation = PendingMutation(
            CloudEntity.CREDIT_CARD_PROFILE,
            PROFILE_ID,
            OWNER,
            MutationKind.UPSERT,
            localRecord(baseVersion).payload,
            NOW,
            baseVersion,
            DEVICE,
        ),
        attemptCount = 0,
        nextAttemptAtEpochMillis = 0,
        lastError = null,
    )

    private fun localRecord(version: Long) = record(version, "Local", NOW)
    private fun remoteRecord(version: Long, issuer: String = "Local") = record(version, issuer, NOW)
    private fun record(version: Long, issuer: String, updatedAt: String) = CloudRecord(
        entity = CloudEntity.CREDIT_CARD_PROFILE.table,
        id = PROFILE_ID,
        ownerUserId = OWNER,
        payload = JsonObject(
            mapOf(
                "user_id" to JsonPrimitive(OWNER),
                "id" to JsonPrimitive(PROFILE_ID),
                "issuer_name" to JsonPrimitive(issuer),
                "wallet_id" to JsonPrimitive(WALLET_ID),
                "payment_source_wallet_id" to JsonNull,
                "updated_at" to JsonPrimitive(updatedAt),
                "deleted_at" to JsonNull,
                "sync_version" to JsonPrimitive(version),
                "last_modified_by_device_id" to JsonPrimitive(DEVICE),
            )
        ),
        updatedAt = updatedAt,
        deletedAt = null,
        syncVersion = version,
    )

    private class FakeLocalStore(var record: CloudRecord?, var queued: QueuedMutation?) : LocalStore {
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            MutableStateFlow(emptyList())
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = record
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ) = listOfNotNull(queued).filter {
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
        var updatedResult: CloudRecord? = null
        var createdPayload: JsonObject? = null
        var updatedPayload: JsonObject? = null
        var expectedVersion: Long? = null
        var fetchCalls = 0

        override suspend fun fetchRecord(
            entity: CloudEntity,
            recordId: String,
            accessToken: String,
            ownerUserId: UserId,
        ): CloudRecord? {
            fetchCalls++
            fetchFailure?.let { throw it }
            return fetched
        }
        override suspend fun createRecord(
            entity: CloudEntity,
            accessToken: String,
            ownerUserId: UserId,
            payload: JsonObject,
        ): CloudRecord {
            createdPayload = payload
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
            this.expectedVersion = expectedVersion
            updatedPayload = payload
            return updatedResult
        }
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content
    private fun JsonObject.long(key: String) = (get(key) as JsonPrimitive).content.toLong()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val PROFILE_ID = "22222222-2222-2222-2222-222222222222"
        const val WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val DEVICE = "44444444-4444-4444-4444-444444444444"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-23T12:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
