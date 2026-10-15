package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.Duration
import java.time.YearMonth
import java.util.UUID
import kotlinx.serialization.json.*

/** ACK-only: no remote creation, ledger rewrite or inferred currency conversion. */
data class InstallmentPaymentAcknowledgementSnapshot(val owner: UserId, val planId: String,
    val batch: InstallmentDeletionBatch?, val recordsByEntity: Map<CloudEntity, List<CloudRecord>>, val queues: List<QueuedMutation>) {
    companion object { val entities = InstallmentAcknowledgementSnapshot.entities + CloudEntity.LEDGER_WALLET }
    fun requireUnchanged(current: InstallmentPaymentAcknowledgementSnapshot) {
        require(owner == current.owner && planId == current.planId && batch == current.batch)
        require(recordsByEntity.keys == entities && current.recordsByEntity.keys == entities)
        require(entities.all { recordsByEntity.getValue(it).sortedBy(CloudRecord::id) == current.recordsByEntity.getValue(it).sortedBy(CloudRecord::id) })
        fun sorted(q: List<QueuedMutation>) = q.sortedWith(compareBy({ it.mutation.entity.table }, { it.mutation.recordId }))
        require(sorted(queues) == sorted(current.queues))
    }
}
sealed interface InstallmentPaymentAcknowledgement {
    data class NeedLedger(val id: String) : InstallmentPaymentAcknowledgement
    data class NeedWallet(val id: String) : InstallmentPaymentAcknowledgement
    data class Acknowledge(val record: CloudRecord) : InstallmentPaymentAcknowledgement
    data class Deferred(val reason: String) : InstallmentPaymentAcknowledgement
    data class Conflict(val reason: String) : InstallmentPaymentAcknowledgement
}
fun planInstallmentPaymentAcknowledgement(snapshot: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation,
    remotePlan: CloudRecord?, remoteCycle: CloudRecord?, remoteLedger: Map<String, CloudRecord?>, remoteWallets: Map<String, CloudRecord?>): InstallmentPaymentAcknowledgement {
    val (plan, local) = requireInstallmentPaymentAcknowledgementIntent(snapshot, queued)
    val localRecord = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single { it.id == local.id }
    if (snapshot.batch != null) return InstallmentPaymentAcknowledgement.Deferred("source_deletion_batch")
    val siblings = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map { it to DueOccurrenceRecord.fromCloudRecord(it) }
        .filter { (_, c) -> c.sourceKindWireValue == "installment" && c.sourceId == snapshot.planId && c.selectedMonthKey == local.selectedMonthKey }.map { it.first }
    installmentPaymentSiblingDecision(snapshot.owner, snapshot.planId, local, siblings)?.let { return it }

    fun pending(entity: CloudEntity, id: String) = snapshot.queues.any { it.mutation.entity == entity && it.mutation.recordId == id }
    if (pending(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)) return InstallmentPaymentAcknowledgement.Deferred("source_pending")
    if (remotePlan == null || plan.deletedAt != null) return InstallmentPaymentAcknowledgement.Conflict("source_unavailable")
    val source = ackPlan(remotePlan, snapshot.owner, snapshot.planId)
    if (source.deletedAt != null) return InstallmentPaymentAcknowledgement.Conflict("source_unavailable")
    val normalized = plan.copy(createdAt = source.createdAt, updatedAt = source.updatedAt, syncVersion = source.syncVersion, lastModifiedByDeviceId = source.lastModifiedByDeviceId)
    if (normalized != source || Duration.between(Instant.parse(plan.createdAt), Instant.parse(source.createdAt)).abs() >= Duration.ofNanos(1000))
        return InstallmentPaymentAcknowledgement.Deferred("source_not_pulled")
    val remote = remoteCycle?.let { ackCycle(it, snapshot.owner, snapshot.planId, local.selectedMonthKey, local.id) }
    if (remote != null && (remote.statusWireValue != "paid" || remote.linkedTransactionId != local.linkedTransactionId ||
            RecordConflictResolver.semanticFingerprint(canonicalAckCycle(local.toCloudRecord()).payload) !=
            RecordConflictResolver.semanticFingerprint(canonicalAckCycle(remoteCycle).payload)))
        return InstallmentPaymentAcknowledgement.Conflict("paid_cycle_changed")
    val undo = queued.mutation.kind == MutationKind.DELETE
    if (!undo && remote == null) return InstallmentPaymentAcknowledgement.Deferred("paid_write_not_implemented")
    val link = local.linkedTransactionId
    if (link == null) {
        require(remoteLedger.keys.isEmpty() || remoteLedger.values.all { it == null })
        return if (undo && (remote == null || remote.deletedAt != null))
            InstallmentPaymentAcknowledgement.Acknowledge(remoteCycle ?: localRecord)
        else InstallmentPaymentAcknowledgement.Conflict("legacy_paid_link_missing")
    }
    require(remoteLedger.keys.all { it == link })
    if (pending(CloudEntity.LEDGER_TRANSACTION, link)) return InstallmentPaymentAcknowledgement.Deferred("ledger_pending")
    if (!remoteLedger.containsKey(link)) return InstallmentPaymentAcknowledgement.NeedLedger(link)
    val serverExpense = remoteLedger[link]?.let { paymentAckLedger(it, snapshot.owner, link) }
    val localExpense = snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull { it.id == link }?.let { paymentAckLedger(it, snapshot.owner, link) }
    val target = remoteCycle ?: localRecord
    if (undo && (remote == null || remote.deletedAt != null)) {
        if (serverExpense?.deletedAt == null && serverExpense != null || localExpense?.deletedAt == null && localExpense != null)
            return InstallmentPaymentAcknowledgement.Deferred("deleted_cycle_ledger_still_live")
        return InstallmentPaymentAcknowledgement.Acknowledge(target)
    }
    if (localExpense?.financialAckPayload() != serverExpense?.financialAckPayload()) return InstallmentPaymentAcknowledgement.Deferred("ledger_not_pulled")
    val expense = serverExpense ?: return InstallmentPaymentAcknowledgement.Conflict("paid_ledger_missing")
    if (expense.deletedAt != null || expense.isArchived || expense.primaryKind != TransactionPrimaryKind.EXPENSE || expense.entryStatus != TransactionEntryStatus.POSTED ||
        expense.amountMinor <= 0 || expense.amountMinor != local.amountMinorSnapshot || local.paidAt == null || remote?.deletedAt != null)
        return InstallmentPaymentAcknowledgement.Conflict("invalid_paid_financial_footprint")
    if (!installmentPaymentCurrenciesMatch(plan.currencyCode, expense.sourceCurrencyCode.orEmpty())) return InstallmentPaymentAcknowledgement.Conflict("paid_currency_mismatch")
    val walletId = expense.sourceWalletId ?: return InstallmentPaymentAcknowledgement.Conflict("paid_wallet_missing")
    if (pending(CloudEntity.LEDGER_WALLET, walletId)) return InstallmentPaymentAcknowledgement.Deferred("wallet_pending")
    require(remoteWallets.keys.all { it == walletId })
    if (!remoteWallets.containsKey(walletId)) return InstallmentPaymentAcknowledgement.NeedWallet(walletId)
    val serverWallet = remoteWallets[walletId]?.let { paymentAckWallet(it, snapshot.owner, walletId) }
    val currentWallet = snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).singleOrNull { it.id == walletId }?.let { paymentAckWallet(it, snapshot.owner, walletId) }
    if (serverWallet?.currencyCode != currentWallet?.currencyCode || serverWallet?.kindWireValue != currentWallet?.kindWireValue || serverWallet?.deletedAt != currentWallet?.deletedAt)
        return InstallmentPaymentAcknowledgement.Deferred("wallet_not_pulled")
    if (serverWallet == null || serverWallet.deletedAt != null || serverWallet.kind == null || serverWallet.kind in setOf(WalletKind.CREDIT_CARD, WalletKind.INVESTMENT) ||
        !installmentPaymentCurrenciesMatch(plan.currencyCode, serverWallet.currencyCode)) return InstallmentPaymentAcknowledgement.Conflict("paid_wallet_currency_or_kind")
    return InstallmentPaymentAcknowledgement.Acknowledge(target)
}

fun requireInstallmentPaymentAcknowledgementIntent(snapshot: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation): Pair<InstallmentPlanRecord, DueOccurrenceRecord> {
    require(UUID.fromString(snapshot.owner.value).toString() == snapshot.owner.value && UUID.fromString(snapshot.planId).toString() == snapshot.planId)
    require(snapshot.recordsByEntity.keys == InstallmentPaymentAcknowledgementSnapshot.entities)
    snapshot.recordsByEntity.forEach { (entity, rows) -> require(rows.all { it.entity == entity.table && it.ownerUserId == snapshot.owner.value } && rows.map { it.id }.distinct().size == rows.size) }
    require(snapshot.queues.all { it.mutation.entity in InstallmentPaymentAcknowledgementSnapshot.entities && it.mutation.subjectUserId == snapshot.owner.value })
    require(snapshot.queues.map { it.mutation.entity to it.mutation.recordId }.distinct().size == snapshot.queues.size && queued in snapshot.queues)
    val q = queued.mutation
    require(q.entity == CloudEntity.DUE_OCCURRENCE_RECORD && q.subjectUserId == snapshot.owner.value)
    val row = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single { it.id == q.recordId }
    val cycle = DueOccurrenceRecord.fromCloudRecord(row).let { ackCycle(row, snapshot.owner, snapshot.planId, it.selectedMonthKey, q.recordId) }
    require(cycle.statusWireValue == "paid" && YearMonth.parse(cycle.selectedMonthKey).toString() == cycle.selectedMonthKey)
    require(q.kind == if (cycle.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE)
    require(q.payload == row.payload && q.baseVersion == row.syncVersion && q.modifiedAt == row.updatedAt)
    require(UUID.fromString(q.deviceId).toString() == q.deviceId && cycle.lastModifiedByDeviceId == q.deviceId)
    return ackPlan(snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single { it.id == snapshot.planId }, snapshot.owner, snapshot.planId) to cycle
}
private fun paymentAckWallet(row: CloudRecord, owner: UserId, id: String): LedgerWalletRecord {
    ackIdentity(row, CloudEntity.LEDGER_WALLET, owner, id)
    val wallet = LedgerWalletRecord.fromCloudRecord(row)
    require(wallet.id == id && wallet.ownerUserId == owner.value && wallet.syncVersion == row.syncVersion && wallet.deletedAt == row.deletedAt)
    require(Instant.parse(wallet.updatedAt) == Instant.parse(requireNotNull(row.updatedAt)))
    return wallet
}

fun installmentPaymentSiblingDecision(owner: UserId, planId: String, target: DueOccurrenceRecord, records: List<CloudRecord>): InstallmentPaymentAcknowledgement? {
    require(records.map { it.id }.distinct().size == records.size)
    val fingerprint = RecordConflictResolver.semanticFingerprint(canonicalAckCycle(target.toCloudRecord()).payload)
    for (row in records) {
        val cycle = ackCycle(row, owner, planId, target.selectedMonthKey, row.id)
        if (cycle.id == target.id) continue
        val financial = cycle.statusWireValue == "paid" || cycle.paidAt != null || cycle.linkedTransactionId != null
        if (target.deletedAt != null && cycle.deletedAt == null && financial)
            return InstallmentPaymentAcknowledgement.Conflict("live_paid_sibling_during_undo")
        if (financial && RecordConflictResolver.semanticFingerprint(canonicalAckCycle(row).payload) != fingerprint)
            return InstallmentPaymentAcknowledgement.Conflict("financial_sibling_requires_reconciliation")
        if (!financial && cycle.deletedAt == null) return InstallmentPaymentAcknowledgement.Deferred("duplicate_cycle_requires_reconciliation")
    }
    return null
}

private fun paymentAckLedger(row: CloudRecord, owner: UserId, id: String): LedgerTransactionRecord {
    val amount = requireNotNull(row.payload["amount_minor"] as? JsonPrimitive)
    require(!amount.isString && amount.longOrNull != null)
    return ackLedger(row, owner, id)
}
