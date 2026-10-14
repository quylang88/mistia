package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.text.Collator
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*

/** RemoteInstallmentPlan contract; business validation belongs to the editor/repository. */
data class InstallmentPlanRecord(
    val id: String,
    val ownerUserId: String,
    val name: String,
    val iconSymbolName: String,
    val amountPerCycleMinor: Long,
    val dueDay: Int,
    val totalCycles: Int?,
    val frequencyMonths: Int,
    val paymentWalletId: String?,
    val currencyCode: String,
    val isArchived: Boolean,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    fun toPayload(): JsonObject = buildJsonObject {
        put("id", id); put("user_id", ownerUserId); put("name", name); put("icon_symbol_name", iconSymbolName)
        put("amount_per_cycle_minor", amountPerCycleMinor); put("due_day", dueDay)
        put("total_cycles", totalCycles?.let(::JsonPrimitive) ?: JsonNull); put("frequency_months", frequencyMonths)
        put("payment_wallet_id", paymentWalletId?.let(::JsonPrimitive) ?: JsonNull); put("currency_code", currencyCode)
        put("is_archived", isArchived); put("created_at", createdAt); put("updated_at", updatedAt)
        put("deleted_at", deletedAt?.let(::JsonPrimitive) ?: JsonNull); put("sync_version", syncVersion)
        put("last_modified_by_device_id", lastModifiedByDeviceId?.let(::JsonPrimitive) ?: JsonNull)
    }
    fun toCloudRecord() = CloudRecord(CloudEntity.INSTALLMENT_PLAN.table, id, ownerUserId, toPayload(), updatedAt, deletedAt, syncVersion)
    companion object {
        fun fromCloudRecord(record: CloudRecord): InstallmentPlanRecord {
            require(record.entity == CloudEntity.INSTALLMENT_PLAN.table)
            val p = record.payload
            val id = installmentUuid(p.installmentString("id"))
            val owner = installmentUuid(p.installmentString("user_id"))
            require(id == installmentUuid(record.id) && owner == installmentUuid(record.ownerUserId)) { "Installment envelope identity mismatch" }
            return InstallmentPlanRecord(id, owner, p.installmentString("name"), p.installmentString("icon_symbol_name"),
                p.installmentNumber("amount_per_cycle_minor"), p.installmentInt("due_day"), p.installmentOptionalInt("total_cycles"),
                p.installmentInt("frequency_months"), p.installmentOptionalString("payment_wallet_id")?.let(::installmentUuid),
                p.installmentString("currency_code").uppercase(Locale.ROOT), p.installmentBoolean("is_archived"),
                installmentUtc(p.installmentString("created_at")), installmentUtc(p.installmentString("updated_at")),
                (p.installmentOptionalString("deleted_at") ?: record.deletedAt)?.let(::installmentUtc), p.installmentNumber("sync_version"),
                p.installmentOptionalString("last_modified_by_device_id")?.let(::installmentUuid))
        }
    }
}

/** A selected month's due row. Frozen occurrence amount/status/link take precedence. */
data class InstallmentDueRow(
    val plan: InstallmentPlanRecord,
    val month: YearMonth,
    val dueDate: Instant,
    val amountMinor: Long,
    val status: DueStatus,
    val linkedTransactionId: String?,
) {
    val sourceKind: DueSourceKind get() = DueSourceKind.INSTALLMENT
    val categorySystemKey: String get() = "loan_repayment"
}

fun installmentDueRows(owner: UserId, plans: List<InstallmentPlanRecord>, occurrences: List<DueOccurrenceRecord>, month: YearMonth,
    zone: ZoneId): List<InstallmentDueRow> {
    val bySource = linkedMapOf<String, DueOccurrenceRecord>()
    occurrences.filter { it.ownerUserId == owner.value && it.deletedAt == null && it.sourceKind == DueSourceKind.INSTALLMENT && it.selectedMonthKey == month.toString() }
        .forEach { candidate ->
            val existing = bySource[candidate.sourceId]
            if (existing == null || (existing.status == DueStatus.PENDING && candidate.status != DueStatus.PENDING)) bySource[candidate.sourceId] = candidate
        }
    val rows = plans.filter { it.ownerUserId == owner.value && !it.isArchived && it.deletedAt == null }.mapNotNull { plan ->
        val anchor = YearMonth.from(Instant.parse(plan.createdAt).atZone(zone))
        val delta = ChronoUnit.MONTHS.between(anchor, month)
        val frequency = plan.frequencyMonths.coerceAtLeast(1).toLong()
        if (delta < 0 || delta % frequency != 0L || (plan.totalCycles != null && delta / frequency >= plan.totalCycles.toLong())) return@mapNotNull null
        val occurrence = bySource[plan.id]
        val due = month.atDay(plan.dueDay.coerceIn(1, month.lengthOfMonth())).atStartOfDay(zone).toInstant()
        InstallmentDueRow(plan, month, due, occurrence?.amountMinorSnapshot ?: plan.amountPerCycleMinor,
            occurrence?.status ?: DueStatus.PENDING, occurrence?.linkedTransactionId)
    }
    val collator = Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }
    return rows.sortedWith { left, right ->
        val date = left.dueDate.compareTo(right.dueDate)
        if (date != 0) date else collator.compare(left.plan.name, right.plan.name)
    }
}

private val installmentUuidPattern = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
private fun installmentUuid(value: String): String { require(installmentUuidPattern.matches(value)); return UUID.fromString(value).toString() }
private fun installmentUtc(value: String): String = value.also { require(runCatching { Instant.parse(it) }.isSuccess) { "Invalid installment timestamp" } }
private fun JsonObject.installmentOptionalString(key: String): String? = when (val value = get(key)) {
    null, JsonNull -> null
    is JsonPrimitive -> { require(value.isString) { "Installment $key must be a string" }; value.content }
    else -> throw IllegalArgumentException("Installment $key must be a string")
}
private fun JsonObject.installmentString(key: String): String = installmentOptionalString(key) ?: throw IllegalArgumentException("Missing installment $key")
private fun JsonObject.installmentOptionalNumber(key: String): Long? = when (val value = get(key)) {
    null, JsonNull -> null
    is JsonPrimitive -> value.takeUnless { it.isString }?.longOrNull ?: throw IllegalArgumentException("Installment $key must be an Int64")
    else -> throw IllegalArgumentException("Installment $key must be an Int64")
}
private fun JsonObject.installmentNumber(key: String): Long = installmentOptionalNumber(key) ?: throw IllegalArgumentException("Missing installment $key")
private fun JsonObject.installmentOptionalInt(key: String): Int? = installmentOptionalNumber(key)?.let { require(it in Int.MIN_VALUE..Int.MAX_VALUE); it.toInt() }
private fun JsonObject.installmentInt(key: String): Int = installmentOptionalInt(key) ?: throw IllegalArgumentException("Missing installment $key")
private fun JsonObject.installmentBoolean(key: String): Boolean {
    val value = get(key) as? JsonPrimitive ?: throw IllegalArgumentException("Missing installment $key")
    require(!value.isString)
    return value.booleanOrNull ?: throw IllegalArgumentException("Installment $key must be a Boolean")
}
