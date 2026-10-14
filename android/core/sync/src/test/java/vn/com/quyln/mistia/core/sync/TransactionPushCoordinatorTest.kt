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
import vn.com.quyln.mistia.core.model.pendingMutation
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

class TransactionPushCoordinatorTest {
    @Test
    fun `new transaction preserves dependency ids and is acknowledged at version one`() = runTest {
        val local = FakeLocalStore(localRecord(0), queued(0))
        val remote = FakeRemoteStore().apply { createdResult = remoteRecord(1) }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(1L, remote.createdPayload?.long("sync_version"))
        assertEquals(SOURCE_WALLET_ID, remote.createdPayload?.string("source_wallet_id"))
        assertEquals(CATEGORY_ID, remote.createdPayload?.string("category_id"))
        assertEquals(1_250L, remote.createdPayload?.long("amount_minor"))
        assertEquals(1L, local.record?.syncVersion)
        assertNull(local.queued)
    }

    @Test
    fun `existing transaction uses conditional version and increments payload`() = runTest {
        val local = FakeLocalStore(localRecord(7), queued(7))
        val remote = FakeRemoteStore().apply {
            fetched = remoteRecord(7, title = "Remote before")
            updatedResult = remoteRecord(8)
        }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.pushed)
        assertEquals(7L, remote.expectedVersion)
        assertEquals(8L, remote.updatedPayload?.long("sync_version"))
        assertNull(local.queued)
    }

    @Test
    fun `transient failure keeps transaction mutation with bounded retry`() = runTest {
        val local = FakeLocalStore(localRecord(0), queued(0))
        val remote = FakeRemoteStore().apply { fetchFailure = IOException("offline") }

        val result = coordinator(local, remote).pushPending(UserId(OWNER), TOKEN)

        assertEquals(1, result.retryableFailures)
        assertEquals(NOW_MILLIS + 30_000, local.queued?.nextAttemptAtEpochMillis)
        assertEquals("network_io", local.queued?.lastError)
    }

    @Test
    fun `disabled transaction gate leaves outbox and network untouched`() = runTest {
        val original = queued(0)
        val local = FakeLocalStore(localRecord(0), original)
        val remote = FakeRemoteStore()

        val result = TransactionPushCoordinator(local, remote, writesEnabled = false) { NOW_MILLIS }
            .pushPending(UserId(OWNER), TOKEN)

        assertEquals(TransactionPushSummary(), result)
        assertSame(original, local.queued)
        assertEquals(0, remote.fetchCalls)
    }


    private fun tombstone(version:Long,deleted:String=DELETED)=record(version,"Local",deleted).let {
        it.copy(deletedAt=deleted,payload=JsonObject(it.payload+mapOf("deleted_at" to JsonPrimitive(deleted))))
    }
    private fun deletion(row:CloudRecord)=queued(row.syncVersion).let {
        it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE,payload=row.payload,modifiedAt=row.updatedAt!!))
    }
    @Test fun `bill undo delete uses exact conditional version and transaction actor metadata only`()=runTest {
        val version=9007199254740993L
        val row=tombstone(version)
        val local=FakeLocalStore(row,deletion(row))
        val remote=FakeRemoteStore().apply {fetched=remoteRecord(version);updatedResult=tombstone(version+1)}
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.pushed)
        assertEquals(version,remote.expectedVersion)
        assertEquals(version+1,remote.updatedPayload?.long("sync_version"))
        assertEquals(OWNER,remote.updatedPayload?.string("last_modified_by_user_id"))
        assertEquals(DELETED,remote.updatedPayload?.string("deleted_at"))
        assertEquals(setOf("id","user_id","updated_at","deleted_at","sync_version","last_modified_by_device_id","last_modified_by_user_id"),remote.updatedPayload?.keys)
        assertNull(local.queued)
    }
    @Test fun `never uploaded deleted transaction acknowledges locally without creating a remote row`()=runTest {
        val row=tombstone(0)
        val local=FakeLocalStore(row,deletion(row))
        val remote=FakeRemoteStore()
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.acknowledged);assertNull(local.queued)
        assertEquals(row,local.record);assertNull(remote.createdPayload);assertNull(remote.updatedPayload)
    }
    @Test fun `already deleted remote ledger is acknowledged losslessly`()=runTest {
        val row=tombstone(7)
        val local=FakeLocalStore(row,deletion(row))
        val acknowledged=tombstone(9)
        val remote=FakeRemoteStore().apply {fetched=acknowledged}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(acknowledged,local.record);assertNull(remote.updatedPayload)
    }
    @Test fun `new pending tombstone arriving during network update survives stale ACK`()=runTest {
        val row=tombstone(7)
        val local=FakeLocalStore(row,deletion(row))
        val replacement=tombstone(7,"2026-09-25T12:00:00.000Z")
        val newer=deletion(replacement)
        val remote=FakeRemoteStore().apply {
            fetched=remoteRecord(7);updatedResult=tombstone(8)
            beforeUpdate={local.record=replacement;local.queued=newer}
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(newer,local.queued);assertEquals(replacement,local.record)
    }
    @Test fun `delete cancellation propagates and offline failure retains bounded retry`()=runTest {
        val row=tombstone(7)
        val queued=deletion(row)
        val local=FakeLocalStore(row,queued)
        val remote=FakeRemoteStore().apply {fetchFailure=kotlinx.coroutines.CancellationException("cancelled")}
        try {coordinator(local,remote).pushPending(UserId(OWNER),TOKEN);org.junit.Assert.fail("Cancellation swallowed")}
        catch (_:kotlinx.coroutines.CancellationException) { }
        assertEquals(queued,local.queued)
        remote.fetchFailure=IOException("offline")
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.retryableFailures)
        assertEquals(NOW_MILLIS+30000,local.queued?.nextAttemptAtEpochMillis)
        assertEquals(MutationKind.DELETE,local.queued?.mutation?.kind)
    }
    @Test fun `disabled transaction delete gate makes no network request`()=runTest {
        val row=tombstone(7)
        val queued=deletion(row)
        val local=FakeLocalStore(row,queued)
        val remote=FakeRemoteStore()
        assertEquals(DomainPushSummary(),TransactionPushCoordinator(local,remote,false) {NOW_MILLIS}.pushPending(UserId(OWNER),TOKEN))
        assertEquals(0,remote.fetchCalls);assertEquals(queued,local.queued)
    }
    @Test fun `conditional delete race is bounded and keeps conflict tombstone`()=runTest {
        val row=tombstone(7)
        val local=FakeLocalStore(row,deletion(row))
        val remote=FakeRemoteStore().apply {fetched=remoteRecord(7)}
        val result=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,result.conflicts);assertEquals(2,remote.updateCalls)
        assertEquals(Long.MAX_VALUE,local.queued?.nextAttemptAtEpochMillis)
        assertEquals("conflict_force_delete_race",local.queued?.lastError)
        assertEquals(row,local.record)
    }
    @Test fun `delete edit conflict follows later remote edit and preserves its full payload`()=runTest {
        val row=tombstone(7)
        val local=FakeLocalStore(row,deletion(row))
        val winner=record(9,"Remote edited","2026-09-26T12:00:00.000Z")
        val remote=FakeRemoteStore().apply {fetched=winner}
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).acknowledged)
        assertEquals(winner,local.record);assertNull(remote.updatedPayload)
    }
    @Test fun `investment cash events cannot bypass their required RPC as direct ledger writes`()=runTest {
        for(role in listOf("investmentCashDeposit","investmentCashWithdrawal")) for(kind in listOf(MutationKind.UPSERT,MutationKind.DELETE)) {
            val base=if(kind==MutationKind.DELETE) tombstone(0) else localRecord(0)
            val row=base.copy(payload=JsonObject(base.payload+mapOf("settlement_role_raw_value" to JsonPrimitive(role))))
            val queued=if(kind==MutationKind.DELETE) deletion(row) else queued(0).let {it.copy(mutation=it.mutation.copy(payload=row.payload))}
            val local=FakeLocalStore(row,queued)
            val remote=FakeRemoteStore()
            assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).permanentFailures)
            assertEquals(0,remote.fetchCalls);assertNull(remote.createdPayload);assertNull(remote.updatedPayload)
        }
    }

    @Test fun `late undo response preserves repayment which resurrects one remote ledger identity`()=runTest {
        val row=tombstone(7)
        val local=FakeLocalStore(row,deletion(row))
        val repaid=record(7,"Repayment","2026-09-26T00:00:00.001Z")
        val replacement=QueuedMutation(PendingMutation(CloudEntity.LEDGER_TRANSACTION,TRANSACTION_ID,OWNER,
            MutationKind.UPSERT,repaid.payload,repaid.updatedAt!!,7,DEVICE),0,0,null)
        val deletedRemote=tombstone(8)
        val remote=FakeRemoteStore().apply {
            fetched=remoteRecord(7);updatedResult=deletedRemote
            beforeUpdate={local.record=repaid;local.queued=replacement}
        }
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(replacement,local.queued);assertEquals(repaid,local.record)
        remote.beforeUpdate=null;remote.fetched=deletedRemote
        remote.updatedResult=repaid.copy(syncVersion=9,payload=JsonObject(repaid.payload+("sync_version" to JsonPrimitive(9))))
        assertEquals(1,coordinator(local,remote).pushPending(UserId(OWNER),TOKEN).pushed)
        assertNull(local.queued);assertNull(local.record!!.deletedAt)
        assertEquals(TRANSACTION_ID,local.record!!.id)
        assertEquals(9L,local.record!!.syncVersion)
        assertNull(remote.createdPayload)
        assertEquals(2,remote.updateCalls)
    }

    @Test fun `bill undo occurrence waits until real transaction coordinator clears ledger delete`()=runTest { verifyBillUndoFlow(false) }
    @Test fun `remote winning ledger edit restores paid occurrence instead of deleting its history`()=runTest { verifyBillUndoFlow(true) }
    private suspend fun verifyBillUndoFlow(remoteWins:Boolean) {
        val row=tombstone(7)
        val ledger=FakeLocalStore(row,deletion(row))
        val occurrence=vn.com.quyln.mistia.core.model.DueOccurrenceRecord(CATEGORY_ID,OWNER,"recurringBill",SOURCE_WALLET_ID,
            "2026-09",NOW,1250,"paid",NOW,TRANSACTION_ID,NOW,DELETED,DELETED,7,DEVICE)
        val occurrenceMutation=QueuedMutation(occurrence.pendingMutation(MutationKind.DELETE),0,0,null)
        val due=FakeLocalStore(occurrence.toCloudRecord(),occurrenceMutation)
        val local=object:LocalStore by ledger {
            override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=when(entity) {
                CloudEntity.LEDGER_TRANSACTION.table -> ledger.record
                CloudEntity.DUE_OCCURRENCE_RECORD.table -> due.record
                else -> null
            }
            override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int)=
                ledger.pendingMutations(ownerUserId,entity,dueAtEpochMillis,limit)+due.pendingMutations(ownerUserId,entity,dueAtEpochMillis,limit)
            override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String)=
                listOfNotNull(ledger.queued,due.queued).filter {it.mutation.entity.table==entity && it.mutation.subjectUserId==ownerUserId.value}.mapTo(mutableSetOf()) {it.mutation.recordId}
            override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord)=
                if(mutation.mutation.entity==CloudEntity.LEDGER_TRANSACTION) ledger.acknowledgeMutation(mutation,remoteRecord) else due.acknowledgeMutation(mutation,remoteRecord)
        }
        val authoritativeLedger=if(remoteWins) record(9,"Remote edited","2026-09-26T12:00:00.000Z") else remoteRecord(7)
        val authoritativeOccurrence=occurrence.copy(deletedAt=null,updatedAt=NOW).toCloudRecord()
        val records=mutableMapOf(CloudEntity.LEDGER_TRANSACTION to authoritativeLedger,CloudEntity.DUE_OCCURRENCE_RECORD to authoritativeOccurrence)
        val patches=mutableListOf<CloudEntity>()
        val remote=object:RemoteMutationStore {
            override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId)=records[entity]
            override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord=error("Undo never creates remote records")
            override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {
                val current=records[entity] ?: return null
                if(current.syncVersion!=expectedVersion) return null
                patches+=entity
                return current.copy(payload=JsonObject(current.payload+payload),updatedAt=payload.string("updated_at"),
                    deletedAt=payload.string("deleted_at"),syncVersion=payload.long("sync_version")).also {records[entity]=it}
            }
        }
        val occurrencePush=DueOccurrencePushCoordinator(local,remote,true) {NOW_MILLIS}
        assertEquals(DomainPushSummary(),occurrencePush.pushPending(UserId(OWNER),TOKEN))
        assertEquals(emptyList<CloudEntity>(),patches)
        val ledgerResult=coordinator(local,remote).pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,if(remoteWins) ledgerResult.acknowledged else ledgerResult.pushed)
        val occurrenceResult=occurrencePush.pushPending(UserId(OWNER),TOKEN)
        assertEquals(1,if(remoteWins) occurrenceResult.acknowledged else occurrenceResult.pushed)
        assertNull(ledger.queued);assertNull(due.queued)
        if(remoteWins) {
            assertEquals(emptyList<CloudEntity>(),patches)
            assertEquals(authoritativeLedger,ledger.record)
            assertEquals(authoritativeOccurrence,due.record)
        } else {
            assertEquals(listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.DUE_OCCURRENCE_RECORD),patches)
            assertEquals(DELETED,records.getValue(CloudEntity.LEDGER_TRANSACTION).deletedAt)
            assertEquals(DELETED,records.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).deletedAt)
        }
    }

    private fun coordinator(local: LocalStore, remote: RemoteMutationStore) =
        TransactionPushCoordinator(local, remote, writesEnabled = true) { NOW_MILLIS }

    private fun queued(baseVersion: Long) = QueuedMutation(
        mutation = PendingMutation(
            CloudEntity.LEDGER_TRANSACTION,
            TRANSACTION_ID,
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
    private fun remoteRecord(version: Long, title: String = "Local") = record(version, title, NOW)
    private fun record(version: Long, title: String, updatedAt: String) = CloudRecord(
        entity = CloudEntity.LEDGER_TRANSACTION.table,
        id = TRANSACTION_ID,
        ownerUserId = OWNER,
        payload = JsonObject(
            mapOf(
                "user_id" to JsonPrimitive(OWNER),
                "id" to JsonPrimitive(TRANSACTION_ID),
                "primary_kind_raw_value" to JsonPrimitive("expense"),
                "transfer_subtype_raw_value" to JsonNull,
                "debt_intent_raw_value" to JsonNull,
                "entry_status_raw_value" to JsonPrimitive("posted"),
                "title" to JsonPrimitive(title),
                "amount_minor" to JsonPrimitive(1_250),
                "source_currency_code" to JsonPrimitive("JPY"),
                "occurred_at" to JsonPrimitive(NOW),
                "created_at" to JsonPrimitive(NOW),
                "updated_at" to JsonPrimitive(updatedAt),
                "created_by_user_id" to JsonPrimitive(OWNER),
                "last_modified_by_user_id" to JsonPrimitive(OWNER),
                "source_wallet_id" to JsonPrimitive(SOURCE_WALLET_ID),
                "destination_wallet_id" to JsonNull,
                "category_id" to JsonPrimitive(CATEGORY_ID),
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
        var updateCalls = 0
        var beforeUpdate: (() -> Unit)? = null

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
            updateCalls++
            beforeUpdate?.invoke()
            this.expectedVersion = expectedVersion
            updatedPayload = payload
            return updatedResult
        }
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content
    private fun JsonObject.long(key: String) = (get(key) as JsonPrimitive).content.toLong()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val TRANSACTION_ID = "22222222-2222-2222-2222-222222222222"
        const val SOURCE_WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val CATEGORY_ID = "44444444-4444-4444-4444-444444444444"
        const val DEVICE = "55555555-5555-5555-5555-555555555555"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-23T12:00:00.000Z"
        const val DELETED = "2026-09-24T12:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
