package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** A complete remote observation; it grants no local acknowledgement by itself. */
data class InvestmentOrdinaryPublicationResult(
    val owner: UserId,
    val eventId: String,
    val transaction: CloudRecord,
    val adjustment: CloudRecord?,
    val postings: List<CloudRecord>,
) {
    val rows: List<CloudRecord> get() = listOfNotNull(transaction, adjustment) + postings
}

data class InvestmentOrdinaryAcknowledgementPlan(
    val records: List<CloudRecord>,
    val acknowledgements: List<Pair<QueuedMutation, CloudRecord>>,
)

/** The Room boundary must recompute this plan under its whole-generation fence. */
fun planInvestmentOrdinaryAcknowledgement(
    source: InvestmentOrdinaryPublicationSnapshot,
    candidate: InvestmentOrdinaryPublicationResult,
): InvestmentOrdinaryAcknowledgementPlan {
    val group = investmentOrdinaryPublicationGroup(source)
    require(candidate.owner == source.owner && candidate.eventId == source.eventId)
    require(group.queues.isNotEmpty())
    val local = group.rows.associateBy { it.entity to it.id }
    val remote = candidate.rows.associateBy { it.entity to it.id }
    require(remote.size == candidate.rows.size && remote.keys == local.keys)
    require(candidate.transaction.entity == CloudEntity.LEDGER_TRANSACTION.table && candidate.transaction.id == source.eventId)
    require(candidate.adjustment?.id == group.adjustment?.id)
    require(candidate.postings.all { it.entity == CloudEntity.INVESTMENT_POSTING.table })
    for ((key, expected) in local) {
        val actual = remote.getValue(key)
        requireCashEventRow(source.owner, actual, requireNotNull(CloudEntity.fromTable(key.first)), remote = true)
        require(expected.syncVersion in 0 until Long.MAX_VALUE && actual.syncVersion == expected.syncVersion + 1)
        require(ordinaryPublicationBusiness(expected.payload) == ordinaryPublicationBusiness(actual.payload))
    }
    return InvestmentOrdinaryAcknowledgementPlan(candidate.rows, group.queues.map {
        it to remote.getValue(it.mutation.entity.table to it.mutation.recordId)
    })
}

/** PostgreSQL represents instants at microsecond precision and emits nullable columns. */
internal fun ordinaryPublicationBusiness(payload: JsonObject): JsonObject = JsonObject(
    payload.filter { (key, value) -> key != "sync_version" && value != JsonNull }.mapValues { (key, value) ->
        if (key in setOf("created_at", "updated_at", "occurred_at", "deleted_at", "archived_at")) {
            JsonPrimitive(cashEventInstant(payload.financeRawString(key)).toString())
        } else value
    },
)

/** Complete terminal-empty cloud read for recovery; absence is explicit. */
data class InvestmentOrdinaryCloudSnapshot(
    val owner: UserId,
    val eventId: String,
    val transaction: CloudRecord?,
    val adjustment: CloudRecord?,
    val postings: List<CloudRecord>,
)

interface InvestmentOrdinaryRemote {
    suspend fun fetchEvent(owner: UserId, eventId: String, accessToken: String): InvestmentOrdinaryCloudSnapshot
    suspend fun publish(source: InvestmentOrdinaryPublicationSnapshot, accessToken: String): InvestmentOrdinaryPublicationResult
}

val INVESTMENT_ORDINARY_RETRY_CODES = setOf(
    "ordinary_investment_version_conflict", "ordinary_investment_capacity_conflict", "ordinary_investment_invalid_wallet",
)
