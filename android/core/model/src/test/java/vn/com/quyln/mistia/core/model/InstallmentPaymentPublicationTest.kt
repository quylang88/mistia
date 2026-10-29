package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentPaymentPublicationTest {
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
    private fun source(c:DueOccurrenceRecord=cycle.copy(syncVersion=0),tx:LedgerTransactionRecord=expense,w:LedgerWalletRecord=wallet):InstallmentPaymentPublicationSnapshot {
        val b=snapshot(c,tx,w)
        return InstallmentPaymentPublicationSnapshot(b,emptyList(),emptyList(),b.queues.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }
    private fun observation(c:DueOccurrenceRecord?=null,tx:LedgerTransactionRecord?=expense,w:LedgerWalletRecord?=wallet,p:InstallmentPlanRecord?=plan)=
        InstallmentPaymentPublicationObservation(p?.toCloudRecord(),listOfNotNull(c?.toCloudRecord()),mapOf(txId to tx?.toCloudRecord()),mapOf(walletId to w?.toCloudRecord()))
    private fun decide(s:InstallmentPaymentPublicationSnapshot=source(),o:InstallmentPaymentPublicationObservation=observation())=
        planInstallmentPaymentPublication(s,s.base.queues.single{it.mutation.entity==CloudEntity.DUE_OCCURRENCE_RECORD},o,java.time.ZoneId.of("UTC"))
    @Test fun newPaidCycleRequiresExactComparedFinancialFootprintAndExplicitAbsence() {
        val d=decide() as InstallmentPaymentPublicationDecision.Write
        assertNull(d.expectedVersion);assertEquals(1L,d.payload.financeRawLong("sync_version"))
        assertEquals(amount,d.payload.financeRawLong("amount_minor_snapshot"));assertEquals(cycleId,d.payload.financeRawString("id"))
        assertEquals(cycle.copy(syncVersion=1).toPayload(),d.payload)
    }
    @Test fun anObservedZeroCycleUsesConditionalUpdateWithoutConfusingItWithAnAbsentBirth() {
        val c=cycle.copy(syncVersion=0,deletedAt=later,updatedAt=later)
        val desired=c.copy(deletedAt=null,paidAt="2026-10-15T02:00:00Z",updatedAt="2026-10-15T02:00:00Z")
        val tx=expense.copy(occurredAt=desired.paidAt!!,updatedAt=desired.updatedAt)
        val s=source(desired,tx).let{it.copy(base=it.base.copy(queues=it.base.queues.map{q->q.copy(remoteIdentityObserved=true)}))}
        val d=decide(s,observation(c,tx)) as InstallmentPaymentPublicationDecision.Write
        assertEquals(0L,d.expectedVersion);assertEquals(1L,d.payload.financeRawLong("sync_version"))
    }
    @Test fun alreadyPublishedExactCycleUsesExistingFinancialProofWithoutAnotherWrite() {
        val actual=cycle.copy(syncVersion=1)
        val d=decide(o=observation(actual)) as InstallmentPaymentPublicationDecision.Acknowledge
        assertEquals(actual.toCloudRecord(),d.record)
    }
    @Test fun aLargeExistingBaseAndFrozenHistoryRetainExactLongVersionsOnRepay() {
        val dead=cycle.copy(deletedAt=later,updatedAt=later)
        val active=dead.copy(deletedAt=null,paidAt="2026-10-15T02:00:00Z",updatedAt="2026-10-15T02:00:00Z")
        val tx=expense.copy(occurredAt=active.paidAt!!,updatedAt=active.updatedAt)
        val d=decide(source(active,tx),observation(dead,tx)) as InstallmentPaymentPublicationDecision.Write
        assertEquals(version,d.expectedVersion);assertEquals(version+1,d.payload.financeRawLong("sync_version"))
    }
    @Test fun absentPreviouslyObservedIdentityIsNeverRecreated() {
        val s=source().let{it.copy(base=it.base.copy(queues=it.base.queues.map{q->q.copy(remoteIdentityObserved=true)}))}
        assertEquals(InstallmentPaymentPublicationDecision.Conflict("cycle_identity_missing"),decide(s))
        assertTrue(decide(source(cycle)) is InstallmentPaymentPublicationDecision.Conflict)
    }
    @Test fun legacyAckOnlyReadPathStillDefersANewPayment() {
        val s=source().base
        assertEquals(InstallmentPaymentAcknowledgement.Deferred("paid_write_not_implemented"),planInstallmentPaymentAcknowledgement(s,s.queues.single(),plan.toCloudRecord(),null,mapOf(txId to expense.toCloudRecord()),mapOf(walletId to wallet.toCloudRecord())))
    }
    @Test fun financialSiblingAndChangedRemotePaidCycleAreNeverOverwritten() {
        for(c in listOf(cycle.copy(id=other,syncVersion=1),cycle.copy(syncVersion=1,amountMinorSnapshot=amount-1)))
            assertTrue(decide(o=observation(c)) is InstallmentPaymentPublicationDecision.Conflict)
    }
    @Test fun newCycleHoldsUntilSourceWalletLedgerAndInvestmentAllocationAreClean() {
        for(entity in listOf(CloudEntity.INSTALLMENT_PLAN,CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET)) {
            val s=source();val row=s.base.recordsByEntity.getValue(entity).single()
            val q=QueuedMutation(PendingMutation(entity,row.id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device),0,Long.MAX_VALUE,"conflict")
            val held=s.copy(base=s.base.copy(queues=s.base.queues+q),dirtyKeys=s.dirtyKeys+(row.entity to row.id))
            assertTrue(decide(held) is InstallmentPaymentPublicationDecision.Deferred)
        }
    }
    @Test fun sourceDriftAndInvalidWalletCurrencyOrKindCannotCreatePaidCycles() {
        assertTrue(decide(o=observation(p=plan.copy(amountPerCycleMinor=amount-1))) is InstallmentPaymentPublicationDecision.Deferred)
        for(w in listOf(wallet.copy(kindWireValue="creditCard"),wallet.copy(kindWireValue="investment"),wallet.copy(currencyCode="JPY")))
            assertTrue(decide(source(w=w),observation(w=w)) is InstallmentPaymentPublicationDecision.Conflict)
    }
    @Test fun absentDeletedCycleEstablishesAVersionOneFenceOnlyAfterBothExpensesAreDeleted() {
        val deleted=cycle.copy(syncVersion=0,deletedAt=later,updatedAt=later);val tx=expense.copy(deletedAt=later,updatedAt=later)
        val d=decide(source(deleted,tx),observation(tx=tx))
        assertTrue("Deleted unobserved0 must establish a remote identity fence before ACK",d is InstallmentPaymentPublicationDecision.Write)
        d as InstallmentPaymentPublicationDecision.Write
        assertNull(d.expectedVersion);assertEquals(1L,d.payload.financeRawLong("sync_version"));assertEquals(later,d.payload.financeRawString("deleted_at"))
        assertTrue(decide(source(deleted,tx),observation()) is InstallmentPaymentPublicationDecision.Deferred)
    }
    @Test fun lateActivePaymentReceiptCanBeTombstonedAfterTheActualLedgerUndoWithoutLosingIntent() {
        val deleted=cycle.copy(syncVersion=0,deletedAt=later,updatedAt=later);val tx=expense.copy(deletedAt=later,updatedAt=later)
        val old=cycle.copy(syncVersion=1)
        val d=decide(source(deleted,tx),observation(old,tx)) as InstallmentPaymentPublicationDecision.Write
        assertEquals(1L,d.expectedVersion);assertEquals(2L,d.payload.financeRawLong("sync_version"));assertEquals(later,d.payload.financeRawString("deleted_at"))
    }
    @Test fun freshRemoteReadsAreRequiredBeforeAuthorizingAnyCycleWrite() {
        assertEquals(InstallmentPaymentPublicationDecision.NeedLedger(txId),decide(o=observation().copy(ledger=emptyMap())))
        assertEquals(InstallmentPaymentPublicationDecision.NeedWallet(walletId),decide(o=observation().copy(wallets=emptyMap())))
    }
    @Test fun aPendingCanonicalInvestmentPostingHoldsItsCycleEvenWhenParentLedgerIsClean() {
        val s=source();val postId=investmentLedgerIdentity(txId,"cash-consumption-booked")
        val post=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postId,owner.value,buildJsonObject {
            put("id",postId);put("user_id",owner.value);put("event_id",txId);put("ledger_transaction_id",txId)
            put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0);put("last_modified_by_device_id",device)
        },now,null,0)
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_POSTING,postId,owner.value,MutationKind.UPSERT,post.payload,now,0,device),0,Long.MAX_VALUE,"network_io")
        assertEquals(InstallmentPaymentPublicationDecision.Deferred("investment_allocation_pending"),decide(s.copy(postings=listOf(post),postingQueues=listOf(q),dirtyKeys=s.dirtyKeys+(post.entity to post.id))))
    }
    @Test fun cloudPrivateStateCanNeverGrantCyclePublicationAuthority() {
        val o=observation()
        fun bad(row:CloudRecord)=row.copy(payload=JsonObject(row.payload+("_mistia_android_spoof" to JsonPrimitive(true))))
        for(invalid in listOf(o.copy(plan=bad(o.plan!!)),o.copy(ledger=mapOf(txId to bad(expense.toCloudRecord()))),o.copy(wallets=mapOf(walletId to bad(wallet.toCloudRecord())))))
            assertTrue("Cloud evidence must be rejected",runCatching{decide(o=invalid)}.isFailure)
    }
    @Test fun anUnknownRemoteTombstoneCannotBeRestoredByAnOldUnobservedIntent() {
        val remote=cycle.copy(syncVersion=1,deletedAt=later,updatedAt=later)
        assertEquals(InstallmentPaymentPublicationDecision.Conflict("remote_cycle_deleted"),decide(o=observation(remote)))
    }
    @Test fun aNewPaidMarkerMustMatchTheActualLedgerDateAndScheduledCycle() {
        val different=cycle.copy(syncVersion=0,paidAt=later)
        assertEquals(InstallmentPaymentPublicationDecision.Conflict("paid_ledger_date_mismatch"),decide(source(different)))
        val wrong=cycle.copy(syncVersion=0,scheduledDate="2026-10-16T00:00:00Z")
        assertEquals(InstallmentPaymentPublicationDecision.Conflict("not_scheduled"),decide(source(wrong)))
    }
    @Test fun changedSourceOrCycleGenerationRevokesTheCapturedPublication() {
        val s=source();s.requireUnchanged(s)
        val newer=source(cycle.copy(syncVersion=0,paidAt=later))
        assertTrue(runCatching{s.requireUnchanged(newer)}.isFailure)
        assertTrue(runCatching{s.copy(dirtyKeys=emptySet()).requireCoherent()}.isFailure)
    }

    @Test fun repayAfterLostPayOrUndoReplyUsesTheActualNewerExpense() {
        val paid = "2026-10-15T02:00:00Z"
        for (old in listOf(cycle.copy(syncVersion=1), cycle.copy(syncVersion=2,deletedAt=later,updatedAt=later))) {
            for (value in listOf(amount,amount-1)) {
                val desired=cycle.copy(syncVersion=0,amountMinorSnapshot=value,paidAt=paid,updatedAt=paid)
                val tx=expense.copy(amountMinor=value,occurredAt=paid,updatedAt=paid)
                val d=decide(source(desired,tx),observation(old,tx))
                assertTrue("Actual later expense must recover lost marker response: $d",d is InstallmentPaymentPublicationDecision.Write)
                d as InstallmentPaymentPublicationDecision.Write
                assertEquals(old.syncVersion,d.expectedVersion);assertEquals(value,d.payload.financeRawLong("amount_minor_snapshot"))
            }
        }
    }
    @Test fun aKnownPendingOrSkippedIdentityCanBecomePaidAfterTheExpenseCommits() {
        for (status in listOf("pending","skipped")) {
            val old=cycle.copy(statusWireValue=status,paidAt=null,linkedTransactionId=null)
            assertTrue(decide(source(cycle),observation(old)) is InstallmentPaymentPublicationDecision.Write)
        }
    }
    @Test fun financialRepairRequiresStrictCausalityAndTheSameLinkedIdentity() {
        for (old in listOf(cycle.copy(syncVersion=1,amountMinorSnapshot=amount-1),
            cycle.copy(syncVersion=1,deletedAt=later,updatedAt=later),
            cycle.copy(syncVersion=1,paidAt="2026-10-15T02:00:00Z"),
            cycle.copy(syncVersion=1,linkedTransactionId=other))) {
            assertTrue(decide(o=observation(old)) is InstallmentPaymentPublicationDecision.Conflict)
        }
        val paid="2026-10-15T01:00:00Z"
        val desired=cycle.copy(syncVersion=0,paidAt=paid,updatedAt=paid)
        val tx=expense.copy(occurredAt=paid,updatedAt=paid)
        assertTrue(decide(source(desired,tx),observation(cycle.copy(syncVersion=2,deletedAt=paid,updatedAt=paid),tx)) is InstallmentPaymentPublicationDecision.Conflict)
    }

    @Test fun matchingPaidTargetCannotHideAnEquivalentFinancialSibling() {
        val o=observation(cycle.copy(syncVersion=1))
        val duplicate=cycle.copy(syncVersion=1,id=other).toCloudRecord()
        assertTrue(decide(o=o.copy(cycles=o.cycles+duplicate)) is InstallmentPaymentPublicationDecision.Conflict)
    }

}
