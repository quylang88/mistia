package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentMoneyContractTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val txId = "44444444-4444-4444-4444-444444444444"
    private val cycleId = "55555555-5555-5555-5555-555555555555"
    private val device = "66666666-6666-6666-6666-666666666666"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val amount = 9007199254740993L
    private fun plan(currency: String = "USD") = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", amount, 15, 12, 1, walletId, currency, false, now, now, null, 7, device)
    private fun wallet(currency: String = "USD") = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = currency, openingBalanceMinor = amount).toMutation(owner, null, device, now).record)
    private fun transaction(currency: String = "USD") = LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, txId, owner.value, buildJsonObject {
        put("id", txId); put("user_id", owner.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
        put("title", "Loan"); put("amount_minor", amount); put("source_wallet_id", walletId); put("source_currency_code", currency)
        put("occurred_at", now); put("created_at", now); put("updated_at", now); put("deleted_at", JsonNull); put("is_archived", false)
        put("sync_version", 0); put("last_modified_by_device_id", device)
    }, now, null, 0))
    private fun cycle() = DueOccurrenceRecord(cycleId, owner.value, "installment", id, "2026-10", now, amount, "paid", now, txId, now, now, null, 0, device)
    private fun snapshot(records: List<CloudRecord> = emptyList(), currency: String = "USD") = BillMoneySnapshot(owner, plan(currency).toCloudRecord(), YearMonth.of(2026, 10),
        CloudEntity.entries.associateWith { entity -> records.filter { it.entity == entity.table } + when (entity) {
            CloudEntity.INSTALLMENT_PLAN -> listOf(plan(currency).toCloudRecord()); CloudEntity.LEDGER_WALLET -> listOf(wallet(currency).toCloudRecord()); else -> emptyList()
        } }, sourceKind = DueSourceKind.INSTALLMENT)
    private fun write(r: CloudRecord) = r to PendingMutation(CloudEntity.fromTable(r.entity)!!, r.id, owner.value, if (r.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE, r.payload, r.updatedAt!!, r.syncVersion, device)
    private fun writes(tx: LedgerTransactionRecord = transaction(), c: DueOccurrenceRecord = cycle()) = listOf(write(tx.toCloudRecord()), write(c.toCloudRecord()))
    private fun rejects(s: BillMoneySnapshot = snapshot(), w: List<Pair<CloudRecord, PendingMutation>>) = assertTrue(runCatching { s.requireValidMutations(w) }.isFailure)
    @Test fun `exact same currency payment and duplicate paid markers share one expense`() {
        for (currency in listOf("USD", "JPY", "VND")) {
            val tx = transaction(currency); val c = cycle()
            snapshot(currency = currency).requireValidMutations(writes(tx, c) + write(c.copy(id = other).toCloudRecord()))
        }
    }
    @Test fun `paid marker must match expense amount and require paid time and exact linked expense`() {
        for (c in listOf(cycle().copy(amountMinorSnapshot = 1375), cycle().copy(amountMinorSnapshot = null), cycle().copy(paidAt = null), cycle().copy(linkedTransactionId = null),
            cycle().copy(statusWireValue = "skipped"), cycle().copy(linkedTransactionId = other))) rejects(w = writes(c = c))
    }
    @Test fun `payment cannot omit expense and cannot post an archived or tombstoned expense`() {
        rejects(w = listOf(write(cycle().toCloudRecord())))
        rejects(w = writes(transaction().copy(isArchived = true)))
        rejects(w = writes(transaction().copy(deletedAt = now)))
    }
    @Test fun `already settled current cycle cannot be overwritten as another payment`() {
        for (status in listOf("paid", "skipped")) {
            val previous = cycle().copy(statusWireValue = status, paidAt = if (status == "paid") now else null, linkedTransactionId = if (status == "paid") txId else null)
            rejects(snapshot(listOf(previous.toCloudRecord())), writes())
        }
    }
    @Test fun `payment cannot leave pending duplicate unresolved or share expense with another month`() {
        val pending = cycle().copy(id = other, statusWireValue = "pending", linkedTransactionId = null, paidAt = null, amountMinorSnapshot = null)
        rejects(snapshot(listOf(pending.toCloudRecord())), writes())
        val shared = cycle().copy(id = other, selectedMonthKey = "2026-11")
        rejects(snapshot(listOf(shared.toCloudRecord())), writes())
    }
    private fun deleted(tx: LedgerTransactionRecord) = tx.copy(deletedAt = later, updatedAt = later, lastModifiedByDeviceId = device)
    private fun deleted(c: DueOccurrenceRecord) = c.copy(deletedAt = later, updatedAt = later, lastModifiedByDeviceId = device)
    @Test fun `undo requires every live linked expense and duplicate paid marker together`() {
        val tx = transaction(); val c = cycle(); val duplicate = c.copy(id = other)
        val s = snapshot(listOf(tx.toCloudRecord(), c.toCloudRecord(), duplicate.toCloudRecord()))
        val full = writes(deleted(tx), deleted(c)) + write(deleted(duplicate).toCloudRecord())
        s.requireValidMutations(full)
        rejects(s, full.filterNot { it.first.id == tx.id }); rejects(s, full.filterNot { it.first.id == duplicate.id })
    }
    @Test fun `undo preserves frozen amount currency schedule links and transaction fields`() {
        val tx = transaction(); val c = cycle(); val s = snapshot(listOf(tx.toCloudRecord(), c.toCloudRecord()))
        for (changed in listOf(deleted(c).copy(amountMinorSnapshot = 1375), deleted(c).copy(scheduledDate = later), deleted(c).copy(linkedTransactionId = other), deleted(c).copy(statusWireValue = "skipped")))
            rejects(s, writes(deleted(tx), changed))
        for (changed in listOf(deleted(tx).copy(amountMinor = 1375), deleted(tx).copy(sourceCurrencyCode = "JPY"), deleted(tx).copy(sourceWalletId = other), deleted(tx).copy(title = "Changed")))
            rejects(s, writes(changed, deleted(c)))
    }
    @Test fun `legacy paid marker without amount or link and already deleted expense undo remain valid`() {
        val legacy = cycle().copy(amountMinorSnapshot = null, linkedTransactionId = null, paidAt = null)
        snapshot(listOf(legacy.toCloudRecord())).requireValidMutations(listOf(write(deleted(legacy).toCloudRecord())))
        val tx = transaction().copy(deletedAt = now); val c = cycle()
        snapshot(listOf(tx.toCloudRecord(), c.toCloudRecord())).requireValidMutations(listOf(write(deleted(c).toCloudRecord())))
    }
    @Test fun `actor clock and mutation tombstone kind must agree with the exact written payload`() {
        val originals = writes()
        for (bad in listOf(originals[0].second.copy(deviceId = other), originals[0].second.copy(modifiedAt = later), originals[0].second.copy(kind = MutationKind.DELETE)))
            rejects(w = listOf(originals[0].first to bad, originals[1]))
    }
    @Test fun `wire updated clock cannot disagree with row metadata and outbox even if both are newer`() {
        val original = writes()
        val forged = original.first().first.copy(updatedAt = later) to original.first().second.copy(modifiedAt = later)
        rejects(w = listOf(forged, original.last()))
    }

}
