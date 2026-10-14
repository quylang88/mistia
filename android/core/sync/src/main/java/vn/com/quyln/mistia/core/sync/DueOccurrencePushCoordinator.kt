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
        preflight={queued,local,owner,token ->
            val occurrence=DueOccurrenceRecord.fromCloudRecord(local)
            val linked=occurrence.linkedTransactionId
            if(queued.mutation.kind!=MutationKind.DELETE || linked==null) MutationPreflight.Continue
            else {
                val ledger=localStore.record(owner,CloudEntity.LEDGER_TRANSACTION.table,linked)
                    ?: remoteStore.fetchRecord(CloudEntity.LEDGER_TRANSACTION,linked,token,owner)
                ledger?.let {
                    require(it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==linked && it.ownerUserId==owner.value)
                    require((it.payload["id"] as? JsonPrimitive)?.content==linked && (it.payload["user_id"] as? JsonPrimitive)?.content==owner.value)
                    require((it.payload["deleted_at"] as? JsonPrimitive)?.contentOrNull==it.deletedAt)
                }
                if(ledger==null || ledger.deletedAt!=null) MutationPreflight.Continue
                else {
                    // A later remote edit can win the linked ledger DELETE.
                    // Restore the matching authoritative paid occurrence too.
                    val remote=remoteStore.fetchRecord(CloudEntity.DUE_OCCURRENCE_RECORD,local.id,token,owner)
                    val paid=remote?.let(DueOccurrenceRecord::fromCloudRecord)
                    if(paid!=null && paid.deletedAt==null && paid.status==DueStatus.PAID && paid.linkedTransactionId==linked &&
                        paid.sourceKind==occurrence.sourceKind && paid.sourceId==occurrence.sourceId && paid.selectedMonthKey==occurrence.selectedMonthKey)
                        MutationPreflight.Acknowledge(remote)
                    else MutationPreflight.Conflict("linked_transaction_still_live")
                }
            }
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
