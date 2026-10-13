package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import kotlinx.serialization.json.contentOrNull
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.RecurringBillPlanRecord
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

typealias RecurringBillPushSummary = DomainPushSummary

class RecurringBillPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.RECURRING_BILL_PLAN,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        allowTombstoneDeletes = true,
        validateRecord = { record ->
            val decoded=RecurringBillPlanRecord.fromCloudRecord(record)
            require(decoded.ownerUserId==record.ownerUserId && decoded.id==record.id && decoded.syncVersion==record.syncVersion) {
                "Bill payload identity/version disagrees with its envelope"
            }
        },
        normalizeSemanticPayload = ::billSemanticPayload,
        orderMutations = { mutations, owner ->
            val pendingWallets = localStore.pendingMutationRecordIds(owner, CloudEntity.LEDGER_WALLET.table)
            val pendingCategories = localStore.pendingMutationRecordIds(owner, CloudEntity.TRANSACTION_CATEGORY.table)
            mutations.filter { queued ->
                if (queued.mutation.kind == MutationKind.DELETE) true
                else {
                    val payload = localStore.record(owner, CloudEntity.RECURRING_BILL_PLAN.table, queued.mutation.recordId)?.payload
                        ?: queued.mutation.payload
                    val walletId = (payload?.get("payment_wallet_id") as? JsonPrimitive)?.contentOrNull
                    val categoryId = (payload?.get("category_id") as? JsonPrimitive)?.contentOrNull
                    (walletId == null || walletId !in pendingWallets) && (categoryId == null || categoryId !in pendingCategories)
                }
            }
        },
    )

    override val entity: CloudEntity = CloudEntity.RECURRING_BILL_PLAN

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): RecurringBillPushSummary = delegate.pushPending(ownerUserId, accessToken)
}

/** Comparison only: Swift typed defaults, UUID values, nil/empty raw schedule and Date instants. */
private fun billSemanticPayload(payload:JsonObject):JsonObject {
    val id=(payload["id"] as JsonPrimitive).content
    val owner=(payload["user_id"] as JsonPrimitive).content
    val decoded=RecurringBillPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.RECURRING_BILL_PLAN.table,id,owner,payload,null,null,0))
    val fields=decoded.toPayload().toMutableMap()
    // Swift fingerprints the original currency string without changing its case.
    fields["currency_code"]=payload.getValue("currency_code")
    if(decoded.scheduleKindWireValue.isNullOrEmpty()) fields["schedule_kind_raw_value"]=kotlinx.serialization.json.JsonNull
    listOf("payment_start_date","first_scheduled_month","due_date","auto_pay_date","paused_at","resume_start_month").forEach { key ->
        val raw=(fields[key] as? JsonPrimitive)?.contentOrNull
        if(raw!=null) fields[key]=JsonPrimitive(Instant.parse(raw).toString())
    }
    return JsonObject(fields)
}
