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

import vn.com.quyln.mistia.core.model.seedRecord
import vn.com.quyln.mistia.core.model.bootstrapMutation
class SystemCategorySeedPushTest {
    private val catalog=vn.com.quyln.mistia.core.model.SystemCategoryCatalog.parse("""[
      {"id":"parent_expense_housing","kind":"expense","active":true,"icon":"mistia.category.parent.expense.housing","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Home","en":"Home","ja":"Home"},"aliases":[],"children":[
      {"id":"rent","active":true,"icon":"mistia.category.expense.home.rent","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Rent","en":"Rent","ja":"Rent"},"aliases":[]}]}
    ]""")
    private val parent=catalog.definitions.single {it.parentKey==null}.seedRecord(UserId(OWNER),null,DEVICE,NOW).copy(id=PARENT_ID)
    private fun row(name:String="Rent",time:String=NOW,version:Long=0)=catalog.definitions.single {it.key=="rent"}.seedRecord(UserId(OWNER),PARENT_ID,DEVICE,NOW)
        .copy(name=name,updatedAt=time,syncVersion=version).toCloudRecord()
    private fun pending(record:CloudRecord)=QueuedMutation(vn.com.quyln.mistia.core.model.TransactionCategoryRecord.fromCloudRecord(record).bootstrapMutation(),0,0,null)
    private fun local(record:CloudRecord=row())=FakeLocalStore(mapOf(record.id to record,parent.id to parent.toCloudRecord()),mutableListOf(pending(record)))
    private fun coordinator(local:LocalStore,remote:RemoteMutationStore)=CategoryPushCoordinator(local,remote,true,catalog) {NOW_MILLIS}

    @Test fun `untouched seed accepts older remote customization without any write`()=runTest {
        val local=local()
        val remoteRow=row("Remote custom","2026-09-22T00:00:00Z",7)
        val remote=FakeRemoteStore().apply {fetchedResults.add(remoteRow)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(0,remote.writeCalls);assertEquals(remoteRow,local.records[CATEGORY_ID]);assertTrue(local.queued.isEmpty())
    }
    @Test fun `explicit edit follows normal local winner instead of bootstrap preference`()=runTest {
        val local=local(row("User edit",LATER))
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote custom",NOW,7));updatedResults.add(row("User edit",LATER,8))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls);assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"))
    }
    @Test fun `favorite edit at same clock does not classify as untouched seed`()=runTest {
        val edited=row().let {it.copy(payload=JsonObject(it.payload+("is_favorite" to JsonPrimitive(true))))}
        val local=local(edited)
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote custom","2026-09-22T00:00:00Z",7));updatedResults.add(edited.copy(syncVersion=8,payload=JsonObject(edited.payload+("sync_version" to JsonPrimitive(8)))))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    @Test fun `remote tombstone wins untouched bootstrap and is never resurrected`()=runTest {
        val local=local()
        val remoteRow=row("Deleted","2026-09-22T00:00:00Z",7).let {it.copy(deletedAt=NOW,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(NOW))))}
        val remote=FakeRemoteStore().apply {fetchedResults.add(remoteRow)}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(0,remote.writeCalls);assertEquals(NOW,local.records[CATEGORY_ID]!!.deletedAt)
    }
    @Test fun `create race accepts remote customization instead of force updating it`()=runTest {
        val local=local()
        val remote=FakeRemoteStore().apply {fetchedResults.add(null);fetchedResults.add(row("Racer","2026-09-22T00:00:00Z",1));createFailures.add(SupabaseHttpException(409,"duplicate"))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(1,remote.writeCalls);assertTrue(remote.updatedPayloads.isEmpty())
    }
    @Test fun `late preference ACK cannot delete a replacement user mutation`()=runTest {
        val newer=pending(row("User edit",LATER))
        val local=local().apply {replacementOnAcknowledge=newer;replacementRecordOnAcknowledge=row("User edit",LATER)}
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote","2026-09-22T00:00:00Z",7));fetchedResults.add(row("Remote","2026-09-22T00:00:00Z",7));updatedResults.add(row("User edit",LATER,8))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(newer,local.queued.single());assertEquals(0,remote.writeCalls)
        assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"))
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals("User edit",local.records[CATEGORY_ID]!!.payload.string("name"));assertTrue(local.queued.isEmpty())
    }
    @Test fun `new untouched seed still creates normally when remote absent`()=runTest {
        val local=local()
        val remote=FakeRemoteStore().apply {createdResults.add(row(version=1))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    @Test fun `disabled category gate remains silent even with bootstrap catalog`()=runTest {
        val local=local();val remote=FakeRemoteStore()
        assertEquals(CategoryPushSummary(),CategoryPushCoordinator(local,remote,false,catalog) {NOW_MILLIS}.pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls);assertEquals(1,local.queued.size)
    }
    @Test fun `previously uploaded system category still follows normal winner semantics`()=runTest {
        val local=local(row(time=LATER,version=5))
        val remote=FakeRemoteStore().apply {fetchedResults.add(row("Remote",NOW,7));updatedResults.add(row(time=LATER,version=8))}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertEquals(1,remote.writeCalls)
    }
    private class FakeLocalStore(
        records: Map<String, CloudRecord>,
        val queued: MutableList<QueuedMutation>,
    ) : LocalStore {
        val records = records.toMutableMap()

        var replacementOnAcknowledge: QueuedMutation? = null
        var replacementRecordOnAcknowledge: CloudRecord? = null
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
                replacementRecordOnAcknowledge?.let { records[it.id]=it }
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
        const val CATEGORY_ID = "b37f0c1b-b967-5f0a-ba59-0e795d0a4d75"
        const val PARENT_ID = "44444444-4444-4444-4444-444444444444"
        const val CHILD_ID = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
