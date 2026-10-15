package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentPaymentAcknowledgementTest {
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
    private val version = 9007199254740995L
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", amount, 15, 12, 1, walletId, "USD", false, now, now, null, version, device)
    private val wallet = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = "USD").toMutation(owner, null, device, now).record)
    private val expense = LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, txId, owner.value, buildJsonObject {
        put("id", txId); put("user_id", owner.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
        put("title", "Loan"); put("amount_minor", amount); put("source_wallet_id", walletId); put("source_currency_code", "USD")
        put("occurred_at", now); put("created_at", now); put("updated_at", now); put("deleted_at", JsonNull); put("is_archived", false)
        put("sync_version", version); put("last_modified_by_device_id", device)
    }, now, null, version))
    private val cycle = DueOccurrenceRecord(cycleId, owner.value, "installment", id, "2026-10", now, amount, "paid", now, txId, now, now, null, version, device)
    private fun snapshot(c: DueOccurrenceRecord = cycle, tx: LedgerTransactionRecord? = expense, w: LedgerWalletRecord = wallet) =
        InstallmentPaymentAcknowledgementSnapshot(owner, id, null, InstallmentPaymentAcknowledgementSnapshot.entities.associateWith { when (it) {
            CloudEntity.INSTALLMENT_PLAN -> listOf(plan.toCloudRecord()); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(c.toCloudRecord())
            CloudEntity.LEDGER_TRANSACTION -> listOfNotNull(tx?.toCloudRecord()); CloudEntity.LEDGER_WALLET -> listOf(w.toCloudRecord()); else -> error("Unexpected entity")
        } }, listOf(QueuedMutation(c.pendingMutation(if (c.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE), 0, 0, null)))
    private fun decide(s: InstallmentPaymentAcknowledgementSnapshot = snapshot(), remote: DueOccurrenceRecord? = cycle.copy(syncVersion = version + 1, updatedAt = later),
        tx: LedgerTransactionRecord? = expense, w: LedgerWalletRecord? = wallet, source: InstallmentPlanRecord? = plan) =
        planInstallmentPaymentAcknowledgement(s, s.queues.first(), source?.toCloudRecord(), remote?.toCloudRecord(), mapOf(txId to tx?.toCloudRecord()), mapOf(walletId to w?.toCloudRecord()))
    @Test fun `already paid server record ACK retains exact Long amount and version without any write decision`() {
        val d = decide() as InstallmentPaymentAcknowledgement.Acknowledge
        assertEquals(version + 1, d.record.syncVersion); assertEquals(amount, DueOccurrenceRecord.fromCloudRecord(d.record).amountMinorSnapshot)
    }
    @Test fun `unknown ledger and wallet require explicit authoritative reads instead of assuming availability`() {
        val s = snapshot(); val q = s.queues.single()
        assertEquals(InstallmentPaymentAcknowledgement.NeedLedger(txId), planInstallmentPaymentAcknowledgement(s, q, plan.toCloudRecord(), cycle.toCloudRecord(), emptyMap(), emptyMap()))
        assertEquals(InstallmentPaymentAcknowledgement.NeedWallet(walletId), planInstallmentPaymentAcknowledgement(s, q, plan.toCloudRecord(), cycle.toCloudRecord(), mapOf(txId to expense.toCloudRecord()), emptyMap()))
    }
    @Test fun `pending source ledger or wallet queue defers even when server payload matches`() {
        for ((entity, row) in listOf(CloudEntity.INSTALLMENT_PLAN to plan.toCloudRecord(), CloudEntity.LEDGER_TRANSACTION to expense.toCloudRecord(), CloudEntity.LEDGER_WALLET to wallet.toCloudRecord())) {
            val s = snapshot().let { it.copy(queues = it.queues + QueuedMutation(PendingMutation(entity, row.id, owner.value, MutationKind.UPSERT, row.payload, row.updatedAt!!, row.syncVersion, device), 0, Long.MAX_VALUE, "conflict")) }
            assertTrue(decide(s) is InstallmentPaymentAcknowledgement.Deferred)
        }
    }
    @Test fun `missing or nonidentical remote cycle never acknowledges a pending payment`() {
        assertTrue(decide(remote = null) is InstallmentPaymentAcknowledgement.Deferred)
        assertTrue(decide(remote = cycle.copy(amountMinorSnapshot = 1375)) is InstallmentPaymentAcknowledgement.Conflict)
        assertTrue(decide(remote = cycle.copy(statusWireValue = "skipped", amountMinorSnapshot = null, linkedTransactionId = null, paidAt = null)) is InstallmentPaymentAcknowledgement.Conflict)
    }
    @Test fun `currency amount wallet kind and posted live expense footprint must agree`() {
        for (tx in listOf(expense.copy(amountMinor = 1375), expense.copy(sourceCurrencyCode = "JPY"), expense.copy(primaryKindWireValue = "income"),
            expense.copy(entryStatusWireValue = "draft"), expense.copy(deletedAt = later), expense.copy(isArchived = true)))
            assertTrue(decide(s = snapshot(tx = tx), tx = tx) is InstallmentPaymentAcknowledgement.Conflict)
        for (w in listOf(wallet.copy(currencyCode = "JPY"), wallet.copy(kindWireValue = "creditCard"), wallet.copy(kindWireValue = "investment")))
            assertTrue(decide(s = snapshot(w = w), w = w) is InstallmentPaymentAcknowledgement.Conflict)
    }
    @Test fun `financial remote drift waits for normal pull without rewriting a ledger`() {
        assertTrue(decide(tx = expense.copy(amountMinor = 1375)) is InstallmentPaymentAcknowledgement.Deferred)
        assertTrue(decide(w = wallet.copy(currencyCode = "JPY")) is InstallmentPaymentAcknowledgement.Deferred)
    }
    @Test fun `metadata or description only ledger ACK and source archive can preserve existing paid history`() {
        val source = plan.copy(isArchived = true, updatedAt = later)
        val s = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.INSTALLMENT_PLAN to listOf(source.toCloudRecord()))) }
        assertTrue(decide(s = s, source = source, tx = expense.copy(title = "Server title", updatedAt = later, syncVersion = version + 1)) is InstallmentPaymentAcknowledgement.Acknowledge)
    }
    @Test fun `foreign owner aliased source month and response identity are rejected`() {
        for (r in listOf(cycle.copy(id = other), cycle.copy(ownerUserId = other), cycle.copy(sourceId = other), cycle.copy(selectedMonthKey = "2026-11")))
            assertTrue(runCatching { decide(remote = r) }.isFailure)
        assertTrue(runCatching { decide(tx = expense.copy(ownerUserId = other)) }.isFailure)
        assertTrue(runCatching { decide(w = wallet.copy(ownerUserId = other)) }.isFailure)
    }
    @Test fun `undo ACK accepts only tombstoned or absent money and keeps frozen paid history`() {
        val deleted = cycle.copy(deletedAt = later, updatedAt = later); val tx = expense.copy(deletedAt = later, updatedAt = later)
        val s = snapshot(deleted, tx)
        assertTrue(decide(s, deleted, tx) is InstallmentPaymentAcknowledgement.Acknowledge)
        assertTrue(decide(s, null, null) is InstallmentPaymentAcknowledgement.Acknowledge)
        assertTrue(decide(s, deleted, expense) is InstallmentPaymentAcknowledgement.Deferred)
    }
    @Test fun `lost ledger undo conflict restores authoritative paid marker after live expense is pulled`() {
        val deleted = cycle.copy(deletedAt = later, updatedAt = later)
        assertTrue(decide(snapshot(deleted), cycle, expense) is InstallmentPaymentAcknowledgement.Acknowledge)
        assertTrue(decide(snapshot(deleted, expense.copy(deletedAt = later)), cycle, expense) is InstallmentPaymentAcknowledgement.Deferred)
    }
    @Test fun `legacy nil link paid tombstone can ACK absence without inventing an expense`() {
        val c = cycle.copy(amountMinorSnapshot = null, paidAt = null, linkedTransactionId = null, deletedAt = later, updatedAt = later)
        assertTrue(decide(snapshot(c, null), null, null) is InstallmentPaymentAcknowledgement.Acknowledge)
        assertTrue(decide(snapshot(c.copy(deletedAt = null), null), c.copy(deletedAt = null), null) is InstallmentPaymentAcknowledgement.Conflict)
    }
    @Test fun `quoted wallet version and ledger amount cannot masquerade as numeric financial wire data`() {
        val s = snapshot(); val q = s.queues.single()
        val ledger = expense.toCloudRecord().let { it.copy(payload = JsonObject(it.payload + ("amount_minor" to JsonPrimitive(amount.toString())))) }
        assertTrue(runCatching { planInstallmentPaymentAcknowledgement(s, q, plan.toCloudRecord(), cycle.toCloudRecord(), mapOf(txId to ledger), mapOf(walletId to wallet.toCloudRecord())) }.isFailure)
        val wrongWallet = wallet.toCloudRecord().let { it.copy(payload = JsonObject(it.payload + ("sync_version" to JsonPrimitive(it.syncVersion.toString())))) }
        assertTrue(runCatching { planInstallmentPaymentAcknowledgement(s, q, plan.toCloudRecord(), cycle.toCloudRecord(), mapOf(txId to expense.toCloudRecord()), mapOf(walletId to wrongWallet)) }.isFailure)
    }

    @Test fun `missing server undo ACK preserves unknown payload fields explicit nulls and exact numbers`() {
        for (linked in listOf(true, false)) {
            val c = cycle.copy(deletedAt = later, updatedAt = later, linkedTransactionId = if (linked) txId else null)
            val s = snapshot(c, expense.copy(deletedAt = later, updatedAt = later))
            val raw = c.toCloudRecord().let { it.copy(payload = JsonObject(it.payload + mapOf("future_amount" to JsonPrimitive(amount), "future_optional" to JsonNull))) }
            val changed = s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(raw)), queues = s.queues.map { it.copy(mutation = it.mutation.copy(payload = raw.payload)) })
            val decision = decide(changed, null, null) as InstallmentPaymentAcknowledgement.Acknowledge
            assertEquals(raw, decision.record)
        }
    }

    @Test fun `undo cannot ACK one tombstone while another live paid sibling still references deleted expense`() {
        val deleted = cycle.copy(deletedAt = later, updatedAt = later)
        val sibling = cycle.copy(id = other)
        assertTrue(installmentPaymentSiblingDecision(owner, id, deleted, listOf(deleted.toCloudRecord(), sibling.toCloudRecord())) is InstallmentPaymentAcknowledgement.Conflict)
        assertNull(installmentPaymentSiblingDecision(owner, id, cycle, listOf(cycle.toCloudRecord(), sibling.toCloudRecord())))
    }

}
