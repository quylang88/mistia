package vn.com.quyln.mistia.core.sync

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.*
import kotlinx.serialization.json.JsonObject
import vn.com.quyln.mistia.core.model.*

/** One captured generic attempt, isolated even if sync calls overlap. */
internal class TransactionPublicationAttempt(val queued:QueuedMutation,val local:CloudRecord):AbstractCoroutineContextElement(Key) {
    companion object Key:CoroutineContext.Key<TransactionPublicationAttempt>
    var prepared:QueuedMutation?=null
}

internal fun transactionPublicationWire(payload:JsonObject):JsonObject {
    if(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY !in payload && LOCAL_ORDINARY_CONFLICT_KEY !in payload)return payload
    val row=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,requireNotNull(payload.financeRawString("id")),
        requireNotNull(payload.financeRawString("user_id")),payload,payload.financeRawString("updated_at"),payload.financeRawString("deleted_at"),requireNotNull(payload.financeRawLong("sync_version")))
    return ordinaryPublicationPayloadForCloud(row)
}

/** Persist the exact proposed target before the delegate can send any bytes. */
internal class TransactionPublicationRemote(private val local:LocalStore,private val delegate:RemoteMutationStore):RemoteMutationStore by delegate {
    private suspend fun prepare(payload:JsonObject):JsonObject {
        val attempt=requireNotNull(currentCoroutineContext()[TransactionPublicationAttempt])
        val wire=transactionPublicationWire(payload)
        if(attempt.queued.mutation.kind!=MutationKind.UPSERT || !LedgerTransactionRecord.fromCloudRecord(attempt.local).supportsOrdinaryTransactionLifecycle())return wire
        currentCoroutineContext().ensureActive()
        val current=attempt.prepared ?: attempt.queued
        val captured=attempt.local.copy(payload=requireNotNull(current.mutation.payload))
        val prepared=try{local.prepareTransactionPublication(current,captured,wire)}
            catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception){throw MutationFailurePersistenceException(error)}
        currentCoroutineContext().ensureActive()
        if(prepared==null)throw MutationWriteStaleException()
        attempt.prepared=prepared
        return wire
    }
    override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord =
        delegate.createRecord(entity,accessToken,ownerUserId,prepare(payload))
    override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? =
        delegate.conditionalUpdate(entity,recordId,accessToken,ownerUserId,expectedVersion,prepare(payload))
}
