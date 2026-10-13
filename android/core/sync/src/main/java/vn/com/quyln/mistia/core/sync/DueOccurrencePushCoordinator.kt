package vn.com.quyln.mistia.core.sync

import java.time.Instant
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

class DueOccurrencePushCoordinator(
    localStore:LocalStore,remoteStore:RemoteMutationStore,writesEnabled:Boolean,
    nowEpochMillis:()->Long=System::currentTimeMillis,
):DomainPushCoordinator {
    private val delegate=OutboxPushCoordinator(
        entity=CloudEntity.DUE_OCCURRENCE_RECORD,localStore=localStore,remoteStore=remoteStore,
        writesEnabled=writesEnabled,nowEpochMillis=nowEpochMillis,allowTombstoneDeletes=true,
        validateRecord={record ->
            val decoded=DueOccurrenceRecord.fromCloudRecord(record)
            require(decoded.id==record.id && decoded.ownerUserId==record.ownerUserId && decoded.syncVersion==record.syncVersion)
        },
        normalizeSemanticPayload={payload ->
            val id=(payload["id"] as JsonPrimitive).content
            val owner=(payload["user_id"] as JsonPrimitive).content
            val typed=DueOccurrenceRecord.fromCloudRecord(CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table,id,owner,payload,null,null,0))
            val fields=typed.toPayload().toMutableMap()
            listOf("scheduled_date","paid_at").forEach {key ->
                (fields[key] as? JsonPrimitive)?.contentOrNull?.let {fields[key]=JsonPrimitive(Instant.parse(it).toString())}
            }
            JsonObject(fields)
        },
        orderMutations={mutations,owner ->
            val pendingTransactions=localStore.pendingMutationRecordIds(owner,CloudEntity.LEDGER_TRANSACTION.table)
            val pendingSources=mapOf(
                "recurringBill" to localStore.pendingMutationRecordIds(owner,CloudEntity.RECURRING_BILL_PLAN.table),
                "installment" to localStore.pendingMutationRecordIds(owner,CloudEntity.INSTALLMENT_PLAN.table),
                "creditCard" to localStore.pendingMutationRecordIds(owner,CloudEntity.LEDGER_WALLET.table),
            )
            mutations.filter {queued ->
                val payload=localStore.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,queued.mutation.recordId)?.payload ?: queued.mutation.payload
                val linked=(payload?.get("linked_transaction_id") as? JsonPrimitive)?.contentOrNull
                val source=(payload?.get("source_id") as? JsonPrimitive)?.contentOrNull
                val kind=(payload?.get("source_kind_raw_value") as? JsonPrimitive)?.contentOrNull
                (linked==null || linked !in pendingTransactions) &&
                    (queued.mutation.kind==MutationKind.DELETE || source==null || source !in pendingSources[kind].orEmpty())
            }
        },
    )
    override val entity=CloudEntity.DUE_OCCURRENCE_RECORD
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String)=delegate.pushPending(ownerUserId,accessToken)
}
