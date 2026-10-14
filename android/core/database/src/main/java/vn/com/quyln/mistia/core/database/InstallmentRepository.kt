package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

internal class OfflineInstallmentRepository(private val store: LocalStore) : InstallmentRepository {
    private val mutex = Mutex()
    override fun observeInstallments(ownerUserId: UserId): Flow<List<InstallmentPlanRecord>> =
        store.observeOwnedFinanceRows(CloudEntity.INSTALLMENT_PLAN, ownerUserId).map { records ->
            records.mapNotNull { runCatching { InstallmentPlanRecord.fromCloudRecord(it) }.getOrNull() }
                .filter { !it.isArchived && it.deletedAt == null }
                .sortedWith(compareBy<InstallmentPlanRecord> { Instant.parse(it.createdAt) }.thenBy { it.id })
        }

    override suspend fun saveInstallment(owner: UserId, draft: InstallmentDraft, deviceId: String, now: String): Result<InstallmentPlanRecord> = result {
        mutex.withLock {
            val id = uuid(draft.id); val device = uuid(deviceId); uuid(owner.value)
            val timestamp = Instant.parse(now).toString()
            val name = draft.name.trim().takeIf(String::isNotEmpty) ?: fail(InstallmentValidationError.NAME_REQUIRED)
            if (draft.amountPerCycleMinor <= 0) fail(InstallmentValidationError.INVALID_AMOUNT)
            if (draft.dueDay !in 1..31 && draft.expected?.dueDay != draft.dueDay) fail(InstallmentValidationError.INVALID_DAYS)
            if (draft.frequencyMonths !in 1..12 && draft.expected?.frequencyMonths != draft.frequencyMonths) fail(InstallmentValidationError.INVALID_FREQUENCY)
            val currency = draft.currencyCode.trim().uppercase(Locale.ROOT)
            if (!Regex("[A-Z]{3}").matches(currency)) fail(InstallmentValidationError.INVALID_CURRENCY)
            val walletId = draft.paymentWalletId?.let(::uuid) ?: fail(InstallmentValidationError.INVALID_WALLET)
            draft.expected?.let { if (it.ownerUserId != owner.value || it.id != id) fail(InstallmentValidationError.NOT_FOUND) }
            repeat(3) {
                val snapshot = store.installmentMutationSnapshot(owner, id)
                require(snapshot.owner == owner && snapshot.planId == id)
                val original = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == id }
                val previous = original?.let { record ->
                    if (!record.matchesFinanceReadScope(owner, CloudEntity.INSTALLMENT_PLAN, includingDeleted = true)) fail(InstallmentValidationError.NOT_FOUND)
                    InstallmentPlanRecord.fromCloudRecord(record).also { require(it.syncVersion == record.syncVersion) }
                }
                if ((draft.expected != null && previous == null) || previous?.deletedAt != null || previous?.isArchived == true) fail(InstallmentValidationError.NOT_FOUND)
                if (previous != null && previous.currencyCode != currency) fail(InstallmentValidationError.INVALID_CURRENCY)
                val walletRow = snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).singleOrNull { it.id == walletId }
                    ?.takeIf { it.matchesFinanceReadScope(owner, CloudEntity.LEDGER_WALLET) } ?: fail(InstallmentValidationError.INVALID_WALLET)
                val wallet = runCatching { LedgerWalletRecord.fromCloudRecord(walletRow) }.getOrNull() ?: fail(InstallmentValidationError.INVALID_WALLET)
                if (wallet.kind == null || wallet.kind == WalletKind.CREDIT_CARD || (wallet.isArchived && previous?.paymentWalletId != walletId)) fail(InstallmentValidationError.INVALID_WALLET)
                val saved = InstallmentPlanRecord(id, owner.value, name, draft.iconSymbolName, draft.amountPerCycleMinor, draft.dueDay,
                    draft.totalCycles, draft.frequencyMonths, walletId, previous?.currencyCode ?: currency, false, previous?.createdAt ?: timestamp,
                    timestamp, null, previous?.syncVersion ?: 0, device)
                if (previous != null) {
                    // A server ACK may change version/timestamps while leaving the user's edit baseline intact.
                    val expected = draft.expected
                    if ((expected == null || sameFrozen(expected, previous)) && sameEditable(saved, previous)) return@withLock previous
                    if (expected == null || !sameBaseline(expected, previous)) fail(InstallmentValidationError.STALE_RECORD)
                }
                val editable = setOf("name", "icon_symbol_name", "amount_per_cycle_minor", "due_day", "frequency_months", "total_cycles", "payment_wallet_id", "updated_at", "last_modified_by_device_id")
                val payload = original?.let { JsonObject(it.payload + saved.toPayload().filterKeys { key -> key in editable }) } ?: saved.toPayload()
                val record = saved.toCloudRecord().copy(payload = payload)
                val pending = PendingMutation(CloudEntity.INSTALLMENT_PLAN, id, owner.value, MutationKind.UPSERT, payload, timestamp, record.syncVersion, device)
                val writes = listOf(record to pending)
                snapshot.requireValidMutations(writes)
                if (store.commitInstallmentMutations(snapshot, writes)) return@withLock InstallmentPlanRecord.fromCloudRecord(record)
            }
            fail(InstallmentValidationError.STALE_RECORD)
        }
    }

    override suspend fun deleteInstallment(owner: UserId, expected: InstallmentPlanRecord, deviceId: String, now: String): Result<Unit> = result {
        mutex.withLock {
            val id = uuid(expected.id); val device = uuid(deviceId); uuid(owner.value)
            if (expected.ownerUserId != owner.value) fail(InstallmentValidationError.NOT_FOUND)
            val timestamp = Instant.parse(now).toString()
            repeat(3) {
                val snapshot = store.installmentMutationSnapshot(owner, id)
                require(snapshot.owner == owner && snapshot.planId == id)
                val original = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == id }
                    ?.takeIf { it.matchesFinanceReadScope(owner, CloudEntity.INSTALLMENT_PLAN, includingDeleted = true) }
                    ?: fail(InstallmentValidationError.NOT_FOUND)
                val current = InstallmentPlanRecord.fromCloudRecord(original)
                if (current.deletedAt != null) return@withLock Unit
                if (current.isArchived) fail(InstallmentValidationError.NOT_FOUND)
                if (!sameBaseline(expected, current)) fail(InstallmentValidationError.STALE_RECORD)
                val records = snapshot.liveOccurrencesForDeletion() + original
                val writes = records.map { row ->
                    val payload = JsonObject(row.payload + mapOf("updated_at" to JsonPrimitive(timestamp), "deleted_at" to JsonPrimitive(timestamp), "last_modified_by_device_id" to JsonPrimitive(device)))
                    val record = row.copy(payload = payload, updatedAt = timestamp, deletedAt = timestamp)
                    record to PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)), row.id, owner.value, MutationKind.DELETE, payload, timestamp, row.syncVersion, device)
                }
                snapshot.requireValidMutations(writes)
                if (store.commitInstallmentMutations(snapshot, writes)) return@withLock Unit
            }
            fail(InstallmentValidationError.STALE_RECORD)
        }
    }

    private fun sameEditable(a: InstallmentPlanRecord, b: InstallmentPlanRecord) = a.name == b.name && a.iconSymbolName == b.iconSymbolName &&
        a.amountPerCycleMinor == b.amountPerCycleMinor && a.dueDay == b.dueDay && a.frequencyMonths == b.frequencyMonths &&
        a.totalCycles == b.totalCycles && a.paymentWalletId == b.paymentWalletId
    private fun sameFrozen(a: InstallmentPlanRecord, b: InstallmentPlanRecord) = a.id == b.id && a.ownerUserId == b.ownerUserId &&
        a.currencyCode == b.currencyCode && Instant.parse(a.createdAt) == Instant.parse(b.createdAt) && a.isArchived == b.isArchived && a.deletedAt == b.deletedAt
    private fun sameBaseline(a: InstallmentPlanRecord, b: InstallmentPlanRecord) = sameEditable(a, b) && sameFrozen(a, b)
    private fun uuid(value: String): String {
        if (!Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(value)) fail(InstallmentValidationError.INVALID_IDENTITY)
        return UUID.fromString(value).toString()
    }
    private fun fail(reason: InstallmentValidationError): Nothing = throw InstallmentValidationException(reason)
    private suspend fun <T> result(block: suspend () -> T): Result<T> = try { Result.success(block()) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { Result.failure(error) }
}
