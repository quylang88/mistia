package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.listSaver
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import vn.com.quyln.mistia.core.model.*

data class BudgetNavigationState(val ownerId: String, val month: String, val editorOpen: Boolean, val editorId: String?, val editorPayload: String?) {
    fun editorPlan(): BudgetPlanRecord? = runCatching {
        val payload = Json.parseToJsonElement(requireNotNull(editorPayload)) as JsonObject
        BudgetPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.BUDGET_PLAN.table, requireNotNull(editorId), ownerId, payload,
            (payload["updated_at"] as? JsonPrimitive)?.content, null, 0))
            .takeIf { it.ownerUserId == ownerId && it.id == editorId }
    }.getOrNull()
    companion object {
        fun saver(owner: String) = listSaver<BudgetNavigationState, Any>(
            save = { listOf(it.ownerId,it.month,it.editorOpen,it.editorId.orEmpty(),it.editorPayload.orEmpty()) },
            restore = { if (it.size != 5 || it[0] != owner) null else BudgetNavigationState(owner,it[1] as String,it[2] as Boolean,
                (it[3] as String).ifEmpty { null },(it[4] as String).ifEmpty { null }) },
        )
    }
}
