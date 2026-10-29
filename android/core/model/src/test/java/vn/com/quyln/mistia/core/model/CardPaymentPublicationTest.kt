package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class CardPaymentPublicationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val device=id(90)
    private val birth="2026-08-01T00:00:00Z"
    private val paid="2026-10-15T00:00:00Z"
    private val undo="2026-10-15T01:00:00Z"
    private val later="2026-10-15T02:00:00Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val amount=9007199254740993L
    private val version=9007199254740995L
    private val cash=LedgerWalletRecord.fromCloudRecord(WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,birth).record)
    private val card=cash.copy(id=id(2),name="Card",kindWireValue="creditCard")
    private val profile=CreditCardProfileRecord(id(3),owner.value,"Issuer","visa","1234",Long.MAX_VALUE,10,26,null,card.id,cash.id,true,birth,birth,null,0,device)
    private val payment=TransactionDraft(id=id(4),primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,
        title="Pay Card",amountMinor=amount,occurredAt=paid,sourceWalletId=cash.id,destinationWalletId=card.id)
        .toMutation(owner,null,cash,card,null,device,paid).record.copy(syncVersion=version)
    private val cycle=DueOccurrenceRecord(id(5),owner.value,"creditCard",card.id,"2026-09","2026-10-25T15:00:00Z",amount,"paid",paid,payment.id,birth,paid,null,0,device)
    private fun source(c:DueOccurrenceRecord=cycle,txs:List<LedgerTransactionRecord> = listOf(payment),wallets:List<LedgerWalletRecord> = listOf(cash,card),
        extra:List<CloudRecord> = emptyList()):CardPaymentPublicationSnapshot {
        val rows=wallets.map{it.toCloudRecord()}+txs.map{it.toCloudRecord()}+profile.toCloudRecord()+c.toCloudRecord()+extra
        val q=QueuedMutation(c.pendingMutation(if(c.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE),0,0,null)
        return CardPaymentPublicationSnapshot(owner,card.id,CardPaymentPublicationSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}},listOf(q),setOf(CloudEntity.DUE_OCCURRENCE_RECORD.table to c.id))
    }
    private fun observation(cycles:List<DueOccurrenceRecord> = emptyList(),txs:Map<String,LedgerTransactionRecord?> = mapOf(payment.id to payment),
        wallets:Map<String,LedgerWalletRecord?> = mapOf(cash.id to cash,card.id to card))=
        CardPaymentPublicationObservation(cycles.map{it.toCloudRecord()},txs.mapValues{it.value?.toCloudRecord()},wallets.mapValues{it.value?.toCloudRecord()})
    private fun decide(s:CardPaymentPublicationSnapshot=source(),o:CardPaymentPublicationObservation=observation())=
        planCardPaymentPublication(s,s.queues.single{it.mutation.entity==CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.recordId==cycle.id},o,zone)
    private fun pending(s:CardPaymentPublicationSnapshot,row:CloudRecord):CardPaymentPublicationSnapshot {
        val q=QueuedMutation(PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,owner.value,
            if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,row.payload.financeRawString("last_modified_by_device_id")!!),0,Long.MAX_VALUE,"network_io")
        return s.copy(queues=s.queues+q,dirtyKeys=s.dirtyKeys+(row.entity to row.id))
    }
    private fun assertConflict(d:CardPaymentPublicationDecision)=assertTrue("Expected conflict, got $d",d is CardPaymentPublicationDecision.Conflict)
    private fun assertRejected(block:()->Unit)=assertTrue("Invalid authority must throw",runCatching(block).isFailure)
    @Test fun deletedArchivedPaymentHistoryMayPublishOnlyItsTombstone() {
        val dead=cycle.copy(deletedAt=undo,updatedAt=undo)
        val tx=payment.copy(isArchived=true,archivedAt=undo,deletedAt=undo,updatedAt=undo)
        assertTrue(decide(source(dead,listOf(tx)),observation(txs=mapOf(tx.id to tx))) is CardPaymentPublicationDecision.Write)
        assertConflict(decide(source(txs=listOf(tx)),observation(txs=mapOf(tx.id to tx))))
    }
    @Test fun archivedButUndeletedPaymentCannotAuthorizeADeletedMarker() {
        val dead=cycle.copy(deletedAt=undo,updatedAt=undo)
        val tx=payment.copy(isArchived=true,archivedAt=undo,updatedAt=undo)
        assertEquals(CardPaymentPublicationDecision.Deferred("deleted_cycle_ledger_still_live"),decide(source(dead,listOf(tx)),observation(txs=mapOf(tx.id to tx))))
    }
    @Test fun laterPaymentMayFollowArchivedAndDeletedHistoricalMoney() {
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val desired=cycle.copy(linkedTransactionId=next.id,paidAt=later,updatedAt=later)
        val old=payment.copy(isArchived=true,archivedAt=undo,deletedAt=undo,updatedAt=undo)
        for(remote in listOf(cycle.copy(syncVersion=1),cycle.copy(syncVersion=2,deletedAt=undo,updatedAt=undo)))
            assertTrue(decide(source(desired,listOf(old,next)),observation(listOf(remote),mapOf(old.id to old,next.id to next))) is CardPaymentPublicationDecision.Write)
    }
    @Test fun newPaidMarkerUsesExactLongAndExplicitAbsentIdentity() {
        val d=decide() as CardPaymentPublicationDecision.Write
        assertNull(d.expectedVersion);assertEquals(1L,d.payload.financeRawLong("sync_version"))
        assertEquals(amount,d.payload.financeRawLong("amount_minor_snapshot"));assertEquals(cycle.copy(syncVersion=1).toPayload(),d.payload)
    }
    @Test fun observedZeroPendingMarkerIsUpdatedWithoutBeingMistakenForANewBirth() {
        val old=cycle.copy(statusWireValue="pending",paidAt=null,linkedTransactionId=null)
        val s=source().let{it.copy(queues=it.queues.map{q->q.copy(remoteIdentityObserved=true)})}
        val d=decide(s,observation(listOf(old))) as CardPaymentPublicationDecision.Write
        assertEquals(0L,d.expectedVersion);assertEquals(1L,d.payload.financeRawLong("sync_version"))
    }
    @Test fun aKnownPendingOrSkippedLongVersionCanBecomePaid() {
        for(status in listOf("pending","skipped")) {
            val local=cycle.copy(syncVersion=version)
            val old=local.copy(statusWireValue=status,paidAt=null,linkedTransactionId=null)
            val d=decide(source(local),observation(listOf(old))) as CardPaymentPublicationDecision.Write
            assertEquals(version,d.expectedVersion);assertEquals(version+1,d.payload.financeRawLong("sync_version"))
        }
    }
    @Test fun actualMatchingMarkerUsesFinanciallyProvenSemanticAcknowledgement() {
        val remote=cycle.copy(syncVersion=1)
        assertEquals(CardPaymentPublicationDecision.Acknowledge(remote.toCloudRecord()),decide(o=observation(listOf(remote))))
    }
    @Test fun previouslyObservedAbsentActiveIdentityIsNeverRecreated() {
        assertConflict(decide(source(cycle.copy(syncVersion=1))))
        val s=source().let{it.copy(queues=it.queues.map{q->q.copy(remoteIdentityObserved=true)})}
        assertConflict(decide(s))
    }
    @Test fun missingRemoteRowsAreRequestedBeforeAnyWriteOrSemanticAcknowledgement() {
        assertEquals(CardPaymentPublicationDecision.NeedLedger(payment.id),decide(o=observation(txs=emptyMap())))
        assertEquals(CardPaymentPublicationDecision.NeedWallet(cash.id),decide(o=observation(wallets=emptyMap())))
        assertEquals(CardPaymentPublicationDecision.NeedWallet(card.id),decide(o=observation(wallets=mapOf(cash.id to cash))))
    }
    @Test fun currentProfileChoicesAndChargeAggregateDoNotRewritePaidHistory() {
        val changed=profile.copy(paymentSourceWalletId=id(91),statementClosingDay=25,paymentDueDay=30)
        var s=source().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.CREDIT_CARD_PROFILE to listOf(changed.toCloudRecord())))}
        val unrelated=payment.copy(id=id(12),title="Later charge",amountMinor=3)
        s=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to (s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION)+unrelated.toCloudRecord())))
        val d=decide(s) as CardPaymentPublicationDecision.Write
        assertEquals(cycle.copy(syncVersion=1).toPayload(),d.payload)
    }
    @Test fun archivedWalletHistoryMayPublishAfterItsActualPaymentAlreadyExists() {
        val a=cash.copy(isArchived=true);val b=card.copy(isArchived=true)
        assertTrue(decide(source(wallets=listOf(a,b)),observation(wallets=mapOf(a.id to a,b.id to b))) is CardPaymentPublicationDecision.Write)
    }
    @Test fun legacyOverpaymentCanDescribeASmallerStatementWithoutRepricingMoney() {
        val c=cycle.copy(amountMinorSnapshot=amount-1)
        assertTrue(decide(source(c)) is CardPaymentPublicationDecision.Write)
        assertConflict(decide(source(cycle.copy(amountMinorSnapshot=amount+1))))
    }
    @Test fun invalidOrdinaryFinancialFootprintsCannotCreateOrAcknowledgeMarkers() {
        for(tx in listOf(payment.copy(amountMinor=0),payment.copy(deletedAt=undo,updatedAt=undo),payment.copy(isArchived=true),
            payment.copy(primaryKindWireValue="expense"),payment.copy(entryStatusWireValue="planned"),
            payment.copy(transferSubtypeWireValue="fx"),payment.copy(destinationAmountMinor=amount-1),
            payment.copy(destinationWalletId=cash.id),payment.copy(sourceCurrencyCode="USD"),payment.copy(occurredAt=later))) {
            for(rows in listOf(emptyList(),listOf(cycle.copy(syncVersion=1))))assertConflict(decide(source(txs=listOf(tx)),observation(rows,txs=mapOf(tx.id to tx))))
        }
    }
    @Test fun deletedSystemForeignKindOrDifferentCurrencyWalletCannotAuthorizeActivePayment() {
        for(w in listOf(cash.copy(deletedAt=undo,updatedAt=undo),cash.copy(kindWireValue="creditCard"),cash.copy(kindWireValue="investment"),
            cash.copy(kindWireValue="unknown"),cash.copy(systemPurposeRawValue="investmentProfit"),cash.copy(currencyCode="USD"),cash.copy(currencyCode="123")))
            assertConflict(decide(source(wallets=listOf(w,card)),observation(wallets=mapOf(w.id to w,card.id to card))))
        assertConflict(decide(source(wallets=listOf(cash,card.copy(deletedAt=undo,updatedAt=undo))),observation(wallets=mapOf(cash.id to cash,card.id to card.copy(deletedAt=undo,updatedAt=undo)))))
        assertRejected { decide(o=observation(wallets=mapOf(cash.id to cash.copy(ownerUserId=id(99)),card.id to card))) }
    }
    @Test fun pendingFinancialAndRelevantAllocationQueuesHoldTheMarker() {
        for(row in listOf(payment.toCloudRecord(),cash.toCloudRecord(),card.toCloudRecord()))
            assertTrue(decide(pending(source(),row)) is CardPaymentPublicationDecision.Deferred)
        val postId=investmentLedgerIdentity(payment.id,"cash-consumption-booked")
        val post=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postId,owner.value,buildJsonObject {
            put("id",postId);put("user_id",owner.value);put("event_id",payment.id);put("ledger_transaction_id",payment.id)
            put("created_at",paid);put("updated_at",paid);put("deleted_at",JsonNull);put("sync_version",0);put("last_modified_by_device_id",device)
        },paid,null,0)
        assertEquals(CardPaymentPublicationDecision.Deferred("investment_allocation_pending"),decide(pending(source(extra=listOf(post)),post)))
    }
    @Test fun unrelatedQueuesAndChangedProfileQueueCannotStarveHistoricalMarker() {
        val s=pending(source(),profile.toCloudRecord())
        assertTrue(decide(s) is CardPaymentPublicationDecision.Write)
    }
    @Test fun changedRemoteFinancialIdentityOrBirthRevokesTheObservation() {
        assertEquals(CardPaymentPublicationDecision.Deferred("ledger_not_pulled"),decide(o=observation(txs=mapOf(payment.id to payment.copy(amountMinor=amount-1)))))
        assertRejected { decide(o=observation(txs=mapOf(payment.id to payment.copy(createdAt=later)))) }
        assertRejected { decide(o=observation(listOf(cycle.copy(syncVersion=1,createdAt=later)))) }
        assertRejected { decide(o=observation(wallets=mapOf(cash.id to cash.copy(createdAt=later),card.id to card))) }
    }
    @Test fun changedRemoteWalletKindOrCurrencyWaitsForPullRatherThanAuthorizingAWrite() {
        assertEquals(CardPaymentPublicationDecision.Deferred("wallet_not_pulled"),decide(o=observation(wallets=mapOf(cash.id to cash.copy(currencyCode="USD"),card.id to card))))
    }
    @Test fun sameMonthAndLegacyDueMonthLiveSiblingsNeedReconciliation() {
        for(sibling in listOf(cycle.copy(id=id(6)),cycle.copy(id=id(6),selectedMonthKey="2026-10"),
            cycle.copy(id=id(6),statusWireValue="pending",linkedTransactionId=null,paidAt=null))) {
            assertConflict(decide(o=observation(listOf(sibling))))
            assertConflict(decide(source(extra=listOf(sibling.toCloudRecord()))))
        }
    }
    @Test fun nextMonthsIndependentStatementDoesNotConflictWithLegacyDueMonthLookup() {
        val sibling=cycle.copy(id=id(6),selectedMonthKey="2026-10",scheduledDate="2026-11-25T15:00:00Z",linkedTransactionId=id(77))
        assertTrue(decide(o=observation(listOf(sibling))) is CardPaymentPublicationDecision.Write)
    }
    @Test fun anotherMonthsMarkerCannotReuseThisPaymentIdentity() {
        assertConflict(decide(o=observation(listOf(cycle.copy(id=id(6),selectedMonthKey="2026-08",scheduledDate=birth)))))
    }
    @Test fun undoCreatesVersionOneAbsenceFenceOnlyAfterActualPaymentDisappears() {
        val dead=cycle.copy(deletedAt=undo,updatedAt=undo);val tx=payment.copy(deletedAt=undo,updatedAt=undo)
        for(remoteTx in listOf(tx,null)) {
            val d=decide(source(dead,listOf(tx)),observation(txs=mapOf(tx.id to remoteTx))) as CardPaymentPublicationDecision.Write
            assertNull(d.expectedVersion);assertEquals(1L,d.payload.financeRawLong("sync_version"));assertEquals(undo,d.payload.financeRawString("deleted_at"))
        }
        assertTrue(decide(source(dead,listOf(tx))) is CardPaymentPublicationDecision.Deferred)
        assertTrue(decide(source(dead),observation(txs=mapOf(payment.id to null))) is CardPaymentPublicationDecision.Deferred)
    }
    @Test fun observedAbsentUndoAcknowledgesOnlyActualDeletedFinancialHistory() {
        val dead=cycle.copy(syncVersion=version,deletedAt=undo,updatedAt=undo);val tx=payment.copy(deletedAt=undo,updatedAt=undo)
        assertEquals(CardPaymentPublicationDecision.Acknowledge(dead.toCloudRecord()),decide(source(dead,listOf(tx)),observation(txs=mapOf(tx.id to null))))
        val unseen=dead.copy(syncVersion=0)
        val s=source(unseen,listOf(tx)).let{it.copy(queues=it.queues.map{q->q.copy(remoteIdentityObserved=true)})}
        assertTrue(decide(s,observation(txs=mapOf(tx.id to null))) is CardPaymentPublicationDecision.Acknowledge)
    }
    @Test fun lateOldActiveReceiptCanBeTombstonedAfterLedgerUndo() {
        val dead=cycle.copy(deletedAt=undo,updatedAt=undo);val tx=payment.copy(deletedAt=undo,updatedAt=undo)
        val d=decide(source(dead,listOf(tx)),observation(listOf(cycle.copy(syncVersion=1)),mapOf(tx.id to tx))) as CardPaymentPublicationDecision.Write
        assertEquals(1L,d.expectedVersion);assertEquals(2L,d.payload.financeRawLong("sync_version"))
    }
    @Test fun anUnknownNewerTombstoneIsNeverResurrectedByAnOldIntent() {
        assertConflict(decide(o=observation(listOf(cycle.copy(syncVersion=1,deletedAt=undo,updatedAt=undo)))))
    }
    @Test fun laterDifferentPaymentRecoversOnlyAfterTheOldFinancialIdentityIsConfirmedDead() {
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val desired=cycle.copy(linkedTransactionId=next.id,paidAt=later,updatedAt=later)
        val old=payment.copy(deletedAt=undo,updatedAt=undo)
        for(remote in listOf(cycle.copy(syncVersion=1),cycle.copy(syncVersion=2,deletedAt=undo,updatedAt=undo))) {
            val s=source(desired,listOf(old,next))
            val o=observation(listOf(remote),mapOf(old.id to old,next.id to next))
            val d=decide(s,o) as CardPaymentPublicationDecision.Write
            assertEquals(remote.syncVersion,d.expectedVersion);assertEquals(next.id,d.payload.financeRawString("linked_transaction_id"))
            assertEquals(CardPaymentPublicationDecision.NeedLedger(old.id),decide(s,o.copy(ledger=o.ledger-old.id)))
            assertConflict(decide(source(desired,listOf(payment,next)),o.copy(ledger=o.ledger+(payment.id to payment.toCloudRecord()))))
            assertTrue(decide(pending(s,old.toCloudRecord()),o) is CardPaymentPublicationDecision.Deferred)
        }
    }
    @Test fun newCycleIdentityCanFollowDeletedSiblingOnlyAfterStrictlyLaterConfirmedPayment() {
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val desired=cycle.copy(linkedTransactionId=next.id,paidAt=later,updatedAt=later)
        val old=payment.copy(deletedAt=undo,updatedAt=undo)
        val sibling=cycle.copy(id=id(6),syncVersion=2,deletedAt=undo,updatedAt=undo)
        val s=source(desired,listOf(old,next),extra=listOf(sibling.toCloudRecord()))
        val o=observation(listOf(sibling),mapOf(old.id to old,next.id to next))
        assertTrue(decide(s,o) is CardPaymentPublicationDecision.Write)
        assertConflict(decide(s,o.copy(cycles=listOf(sibling.copy(deletedAt=null).toCloudRecord()))))
        val equal=next.copy(occurredAt=undo);val notLater=desired.copy(paidAt=undo)
        assertConflict(decide(source(notLater,listOf(old,equal),extra=listOf(sibling.toCloudRecord())),observation(listOf(sibling),mapOf(old.id to old,equal.id to equal))))
    }
    @Test fun staleQueueUnknownFieldsAndIncompleteDirtyGenerationCannotAuthorizePublication() {
        val s=source();s.requireCoherent();s.requireUnchanged(s)
        assertRejected { s.copy(dirtyKeys=emptySet()).requireCoherent() }
        assertRejected { s.copy(queues=s.queues.map{it.copy(mutation=it.mutation.copy(baseVersion=1))}).requireCoherent() }
        assertRejected { s.requireUnchanged(source(cycle.copy(amountMinorSnapshot=amount-1))) }
        val row=cycle.toCloudRecord().let{it.copy(payload=JsonObject(it.payload+("unknown" to JsonPrimitive(true))))}
        val invalid=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to listOf(row)),queues=s.queues.map{it.copy(mutation=it.mutation.copy(payload=row.payload))})
        assertRejected { decide(invalid) }
    }
    @Test fun remotePrivateOrUnrequestedDependencyAndDuplicateMembershipAreRejected() {
        val o=observation();val row=payment.toCloudRecord().let{it.copy(payload=JsonObject(it.payload+("_mistia_android_spoof" to JsonPrimitive(true))))}
        assertRejected { decide(o=o.copy(ledger=mapOf(payment.id to row))) }
        assertRejected { decide(o=o.copy(ledger=o.ledger+(id(99) to null))) }
        assertRejected { decide(o=observation(listOf(cycle,cycle))) }
    }
    @Test fun submittedResultMustBeExactClosedMarkerAtComparedVersion() {
        val s=source();val o=observation();val result=cycle.copy(syncVersion=1).toCloudRecord()
        requireCardPaymentPublicationResult(s,s.queues.single(),o,zone,result)
        for(bad in listOf(cycle.copy(syncVersion=2).toCloudRecord(),cycle.copy(syncVersion=1,amountMinorSnapshot=amount-1).toCloudRecord(),
            result.copy(payload=JsonObject(result.payload+("unknown" to JsonNull))),result.copy(ownerUserId=id(99))))
            assertRejected { requireCardPaymentPublicationResult(s,s.queues.single(),o,zone,bad) }
    }
    @Test fun serverAuditTimestampIsRetainedWhileResultFactsRemainExact() {
        val s=source();val o=observation()
        requireCardPaymentPublicationResult(s,s.queues.single(),o,zone,cycle.copy(syncVersion=1,updatedAt=later).toCloudRecord())
        assertRejected { requireCardPaymentPublicationResult(s,s.queues.single(),o,zone,cycle.copy(syncVersion=1,updatedAt="invalid").toCloudRecord()) }
    }
    @Test fun paidOrPendingTargetCannotBeRelabelledToAnUnrelatedHistoricalMonth() {
        val remote=cycle.copy(syncVersion=version,selectedMonthKey="2026-06",scheduledDate="2026-07-25T15:00:00Z")
        val known=cycle.copy(syncVersion=version)
        assertConflict(decide(source(known),observation(listOf(remote.copy(statusWireValue="pending",paidAt=null,linkedTransactionId=null)))))
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val old=payment.copy(deletedAt=undo,updatedAt=undo)
        val desired=known.copy(linkedTransactionId=next.id,paidAt=later,updatedAt=later)
        assertConflict(decide(source(desired,listOf(old,next)),observation(listOf(remote),mapOf(old.id to old,next.id to next))))
    }
    @Test fun undoMayPublishBeforeALocallyQueuedReplacementForTheSameStatement() {
        val dead=cycle.copy(deletedAt=undo,updatedAt=undo)
        val old=payment.copy(deletedAt=undo,updatedAt=undo)
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val replacement=cycle.copy(id=id(6),linkedTransactionId=next.id,paidAt=later,createdAt=later,updatedAt=later)
        val s=pending(source(dead,listOf(old,next),extra=listOf(replacement.toCloudRecord())),replacement.toCloudRecord())
        val d=decide(s,observation(listOf(cycle.copy(syncVersion=1)),mapOf(old.id to old)))
        assertTrue("Old tombstone must clear before new publication: $d",d is CardPaymentPublicationDecision.Write)
    }
    @Test fun replacementWaitsUntilItsLocallyQueuedPredecessorMarkerIsAcknowledged() {
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val desired=cycle.copy(linkedTransactionId=next.id,paidAt=later,updatedAt=later)
        val old=payment.copy(deletedAt=undo,updatedAt=undo)
        val predecessor=cycle.copy(id=id(6),syncVersion=2,deletedAt=undo,updatedAt=undo)
        val s=pending(source(desired,listOf(old,next),extra=listOf(predecessor.toCloudRecord())),predecessor.toCloudRecord())
        assertEquals(CardPaymentPublicationDecision.Deferred("predecessor_cycle_pending"),decide(s,observation(listOf(predecessor),mapOf(old.id to old,next.id to next))))
    }
    @Test fun legacyDueMonthPendingIdentityCanBeNormalizedAtTheSameFrozenDueDate() {
        val old=cycle.copy(syncVersion=version,selectedMonthKey="2026-10",statusWireValue="pending",paidAt=null,linkedTransactionId=null)
        assertTrue(decide(source(cycle.copy(syncVersion=version)),observation(listOf(old))) is CardPaymentPublicationDecision.Write)
    }
    @Test fun sameLedgerRepayRequiresStrictlyLaterActualOccurredAt() {
        val next=payment.copy(occurredAt=later,updatedAt=later)
        val desired=cycle.copy(paidAt=later,updatedAt=later)
        val remote=cycle.copy(syncVersion=2,deletedAt=undo,updatedAt=undo)
        assertTrue(decide(source(desired,listOf(next)),observation(listOf(remote),mapOf(next.id to next))) is CardPaymentPublicationDecision.Write)
        assertConflict(decide(source(),observation(listOf(remote))))
    }
    @Test fun oldDifferentPaymentProofCannotHideAnUnpublishedCanonicalAllocation() {
        val next=payment.copy(id=id(8),occurredAt=later,createdAt=later,updatedAt=later)
        val desired=cycle.copy(linkedTransactionId=next.id,paidAt=later,updatedAt=later)
        val old=payment.copy(deletedAt=undo,updatedAt=undo)
        val postId=investmentLedgerIdentity(old.id,"cash-consumption-booked")
        val post=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postId,owner.value,buildJsonObject {
            put("id",postId);put("user_id",owner.value);put("event_id",old.id);put("ledger_transaction_id",old.id)
            put("created_at",paid);put("updated_at",undo);put("deleted_at",undo);put("sync_version",1);put("last_modified_by_device_id",device)
        },undo,undo,1)
        val s=pending(source(desired,listOf(old,next),extra=listOf(post)),post)
        assertEquals(CardPaymentPublicationDecision.Deferred("investment_allocation_pending"),decide(s,observation(listOf(cycle.copy(syncVersion=1)),mapOf(old.id to old,next.id to next))))
    }
    @Test fun postgresPrecisionAndAuditOnlyFinancialChangesPreserveHistoricalProof() {
        val at="2026-10-15T00:00:00.123456789Z"
        val tx=payment.copy(occurredAt=at,createdAt=at)
        val local=cycle.copy(paidAt=at,createdAt=at)
        val actual=tx.copy(title="Renamed",syncVersion=version+1,occurredAt=cashEventInstant(at).toString(),createdAt=cashEventInstant(at).toString())
        val remote=local.copy(syncVersion=1,paidAt=actual.occurredAt,createdAt=actual.createdAt)
        assertEquals(CardPaymentPublicationDecision.Acknowledge(remote.toCloudRecord()),decide(source(local,listOf(tx)),observation(listOf(remote),mapOf(tx.id to actual))))
    }
}
