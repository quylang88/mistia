package vn.com.quyln.mistia.core.model

import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

interface InstallmentRepository {
    fun observeInstallments(ownerUserId: UserId): Flow<List<InstallmentPlanRecord>>
    suspend fun skipInstallment(owner: UserId, expected: InstallmentPlanRecord, month: java.time.YearMonth, deviceId: String, now: String): Result<DueOccurrenceRecord> =
        Result.failure(UnsupportedOperationException("Installment skip unavailable"))
    suspend fun undoInstallmentSkip(owner: UserId, expected: InstallmentPlanRecord, month: java.time.YearMonth, deviceId: String, now: String): Result<Unit> =
        Result.failure(UnsupportedOperationException("Installment skip undo unavailable"))
    suspend fun saveInstallment(owner: UserId, draft: InstallmentDraft, deviceId: String, now: String): Result<InstallmentPlanRecord>
    suspend fun deleteInstallment(owner: UserId, expected: InstallmentPlanRecord, deviceId: String, now: String): Result<Unit>
}

/** A caller-owned stable client ID also makes an interrupted creation safe to replay. */
data class InstallmentDraft(
    val id: String,
    val name: String,
    val amountPerCycleMinor: Long,
    val dueDay: Int,
    val frequencyMonths: Int,
    val totalCycles: Int?,
    val paymentWalletId: String?,
    val currencyCode: String,
    val iconSymbolName: String = "mistia.plan.installment",
    val expected: InstallmentPlanRecord? = null,
)

enum class InstallmentValidationError {
    NAME_REQUIRED, INVALID_AMOUNT, INVALID_DAYS, INVALID_FREQUENCY, INVALID_CURRENCY, INVALID_TOTAL_CYCLES,
    INVALID_WALLET, INVALID_IDENTITY, NOT_FOUND, STALE_RECORD, NOT_SCHEDULED, SETTLED_CYCLE,
}
class InstallmentValidationException(val reason: InstallmentValidationError) : IllegalArgumentException(reason.name)

/** Complete raw tables protect wallet validation, source identity and all related occurrence inserts. */
data class InstallmentMutationSnapshot(val owner: UserId, val planId: String, val recordsByEntity: Map<CloudEntity, List<CloudRecord>>) {
    companion object { val entities = setOf(CloudEntity.INSTALLMENT_PLAN, CloudEntity.LEDGER_WALLET, CloudEntity.DUE_OCCURRENCE_RECORD) }
    fun requireUnchanged(current: Map<CloudEntity, List<CloudRecord>>) {
        require(current.keys == entities && recordsByEntity.keys == entities)
        require(entities.all { current.getValue(it).sortedBy(CloudRecord::id) == recordsByEntity.getValue(it).sortedBy(CloudRecord::id) })
    }
    fun liveOccurrencesForDeletion(): List<CloudRecord> = recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).filter { row ->
        if (!ownedIdentity(row, owner, CloudEntity.DUE_OCCURRENCE_RECORD) || row.payload.text("source_kind_raw_value") != "installment" ||
            normalizedUuid(row.payload.text("source_id")) != normalizedUuid(planId)) return@filter false
        val typed = DueOccurrenceRecord.fromCloudRecord(row)
        require(typed.syncVersion == row.syncVersion) { "Occurrence version metadata mismatch" }
        typed.deletedAt == null
    }

    fun requireValidMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        require(recordsByEntity.keys == entities)
        recordsByEntity.forEach { (entity, rows) ->
            require(rows.all { it.entity == entity.table && it.ownerUserId == owner.value })
            require(rows.map { it.id }.distinct().size == rows.size)
        }
        require(normalizedUuid(owner.value) != null && normalizedUuid(planId) == planId)
        require(mutations.isNotEmpty() && mutations.map { it.first.entity to it.first.id }.distinct().size == mutations.size)
        val planWrite = mutations.single { it.first.entity == CloudEntity.INSTALLMENT_PLAN.table }
        val target = planWrite.first
        require(target.id == planId && ownedIdentity(target, owner, CloudEntity.INSTALLMENT_PLAN))
        val candidate = InstallmentPlanRecord.fromCloudRecord(target)
        require(candidate.syncVersion == target.syncVersion)
        val original = recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == planId }
        val previous = original?.let { require(ownedIdentity(it, owner, CloudEntity.INSTALLMENT_PLAN)); InstallmentPlanRecord.fromCloudRecord(it) }
        require(previous == null || (previous.deletedAt == null && !previous.isArchived && previous.syncVersion == original.syncVersion))
        val deleting = candidate.deletedAt != null
        val related = if (deleting) liveOccurrencesForDeletion() else emptyList()
        val occurrenceWrites = mutations.filter { it.first.entity == CloudEntity.DUE_OCCURRENCE_RECORD.table }
        require(occurrenceWrites.map { it.first.id }.toSet() == related.map { it.id }.toSet())
        if (deleting) require(previous != null && candidate.deletedAt == candidate.updatedAt)
        else {
            require(candidate.name.isNotBlank() && candidate.name == candidate.name.trim() && candidate.amountPerCycleMinor > 0)
            require(candidate.dueDay in 1..31 || previous?.dueDay == candidate.dueDay)
            require(candidate.frequencyMonths in 1..12 || previous?.frequencyMonths == candidate.frequencyMonths)
            require(!candidate.isArchived)
            require(Regex("[A-Z]{3}").matches(candidate.currencyCode))
            if (previous == null) require(candidate.createdAt == candidate.updatedAt)
            val walletRow = recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).singleOrNull { it.id == candidate.paymentWalletId }
                ?: throw IllegalArgumentException("Missing installment wallet")
            require(ownedIdentity(walletRow, owner, CloudEntity.LEDGER_WALLET))
            val wallet = LedgerWalletRecord.fromCloudRecord(walletRow)
            require(wallet.deletedAt == null && wallet.kind != null && wallet.kind != WalletKind.CREDIT_CARD &&
                (!wallet.isArchived || previous?.paymentWalletId == wallet.id))
        }
        val allowedFields = if (deleting) setOf("updated_at", "deleted_at", "last_modified_by_device_id") else
            setOf("name", "icon_symbol_name", "amount_per_cycle_minor", "due_day", "frequency_months", "total_cycles", "payment_wallet_id", "updated_at", "last_modified_by_device_id")
        original?.let { requireFrozen(it, target, allowedFields) }
        mutations.forEach { (record, mutation) ->
            val entity = CloudEntity.fromTable(record.entity)
            require(entity == CloudEntity.INSTALLMENT_PLAN || entity == CloudEntity.DUE_OCCURRENCE_RECORD)
            require(ownedIdentity(record, owner, requireNotNull(entity)))
            val before = if (entity == CloudEntity.INSTALLMENT_PLAN) original else related.singleOrNull { it.id == record.id }
            require(entity == CloudEntity.INSTALLMENT_PLAN || before != null)
            require(record.syncVersion == (before?.syncVersion ?: 0L))
            require(mutation.entity == entity && mutation.subjectUserId == owner.value && mutation.recordId == record.id && mutation.payload == record.payload)
            require(mutation.baseVersion == (before?.syncVersion ?: 0L) && mutation.modifiedAt == candidate.updatedAt && record.updatedAt == candidate.updatedAt)
            require(mutation.deviceId == planWrite.second.deviceId)
            require(normalizedUuid(mutation.deviceId) == mutation.deviceId && record.payload.text("last_modified_by_device_id") == mutation.deviceId)
            require(mutation.kind == if (deleting) MutationKind.DELETE else MutationKind.UPSERT)
            require(record.deletedAt == if (deleting) candidate.updatedAt else null)
            require(record.payload.text("updated_at") == candidate.updatedAt)
            if (deleting) {
                require(record.payload.text("deleted_at") == candidate.updatedAt)
                before?.let { requireFrozen(it, record, setOf("updated_at", "deleted_at", "last_modified_by_device_id")) }
            }
        }
        require(Instant.parse(candidate.updatedAt).toString() == candidate.updatedAt)
    }
}

private fun requireFrozen(before: CloudRecord, after: CloudRecord, editable: Set<String>) {
    require(before.payload.filterKeys { it !in editable } == after.payload.filterKeys { it !in editable }) { "Frozen installment metadata changed" }
}
private fun JsonObject.text(key: String): String? = (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
private val mutationUuidPattern = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
private fun normalizedUuid(value: String?): String? = value?.takeIf { mutationUuidPattern.matches(it) }?.let { UUID.fromString(it).toString() }
private fun ownedIdentity(row: CloudRecord, owner: UserId, entity: CloudEntity): Boolean = row.entity == entity.table && row.ownerUserId == owner.value &&
    normalizedUuid(row.id) != null && normalizedUuid(row.id) == normalizedUuid(row.payload.text("id")) && normalizedUuid(row.payload.text("user_id")) == normalizedUuid(owner.value)
