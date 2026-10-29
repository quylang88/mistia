package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class CardPaymentPublicationCoordinatorTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val child = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val walletId = "55555555-5555-5555-5555-555555555555"
    private val txId = "66666666-6666-6666-6666-666666666666"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val time = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val wallet=LedgerWalletRecord.fromCloudRecord(WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,time).record).toCloudRecord()
    private val card=LedgerWalletRecord.fromCloudRecord(wallet).copy(id=id,name="Card",kindWireValue="creditCard").toCloudRecord()
    private val payment=TransactionDraft(id=txId,primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,title="Pay Card",amountMinor=9007199254740993,occurredAt=time,sourceWalletId=walletId,destinationWalletId=id)
        .toMutation(owner,null,LedgerWalletRecord.fromCloudRecord(wallet),LedgerWalletRecord.fromCloudRecord(card),null,device,time).record.copy(syncVersion=7).toCloudRecord()
    private fun cycle(version:Long=0)=DueOccurrenceRecord(child,owner.value,"creditCard",id,"2026-10",time,9007199254740993,"paid",time,txId,time,time,null,version,device).toCloudRecord()
    private fun queue(r:CloudRecord)=QueuedMutation(DueOccurrenceRecord.fromCloudRecord(r).pendingMutation(if(r.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE),0,0,null)
    private fun snapshot():CardPaymentPublicationSnapshot {
        val rows=listOf(wallet,card,payment,cycle())
        return CardPaymentPublicationSnapshot(owner,id,CardPaymentPublicationSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}},listOf(queue(cycle())),setOf(CloudEntity.DUE_OCCURRENCE_RECORD.table to child))
    }
    private var session:AuthSession?=AuthSession(owner,"test@example.com","fixture","refresh",Long.MAX_VALUE)
    private var zone=java.time.ZoneId.of("UTC")
    private val now=1792108800000L
    private inner class Local(var state:CardPaymentPublicationSnapshot=snapshot()):LocalStore {
        var reads=0;var commits=0;var failures=0;var onAck:()->Unit={};var failRead=false;var failAck=false;var failRetry=false
        override fun observe(entity:String,ownerUserId:UserId)=MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId:UserId)=MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String):CloudRecord?=state.recordsByEntity.values.flatten().singleOrNull{it.entity==entity && it.id==recordId}
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String):Set<String> = error("Generic scan forbidden")
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=error("Generic write forbidden")
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=Unit
        override suspend fun clearAccount(ownerUserId:UserId)=Unit
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int):List<QueuedMutation> = state.queues.filter{it.mutation.entity==entity && it.nextAttemptAtEpochMillis<=dueAtEpochMillis}.take(limit)
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord):Boolean=error("Generic ACK forbidden")
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean=error("Generic retry forbidden")
        override suspend fun cardPaymentPublicationSnapshot(owner:UserId,cardId:String):CardPaymentPublicationSnapshot {
            reads++;if(failRead)throw IOException("local read");require(owner==state.owner)
            return state.copy(cardId=cardId)
        }
        private fun unchanged(s:CardPaymentPublicationSnapshot)=runCatching{s.requireUnchanged(state.copy(cardId=s.cardId))}.isSuccess
        override suspend fun acknowledgeCardPaymentPublication(expected:CardPaymentPublicationSnapshot,queued:QueuedMutation,
            observed:CardPaymentPublicationObservation,zone:java.time.ZoneId,isSessionCurrent:()->Boolean):Boolean {
            if(failAck)throw IOException("local ACK");onAck();if(!isSessionCurrent())throw CancellationException("final session")
            if(!unchanged(expected))return false
            val d=planCardPaymentPublication(expected,queued,observed,zone) as CardPaymentPublicationDecision.Acknowledge
            state=state.copy(queues=state.queues-queued,recordsByEntity=state.recordsByEntity+
                (CloudEntity.DUE_OCCURRENCE_RECORD to state.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map{if(it.id==d.record.id)d.record else it}),dirtyKeys=state.dirtyKeys-(queued.mutation.entity.table to queued.mutation.recordId))
            commits++;return true
        }
        override suspend fun recordCardPaymentPublicationFailure(expected:CardPaymentPublicationSnapshot,queued:QueuedMutation,
            nextAttemptAtEpochMillis:Long,errorCode:String,isSessionCurrent:()->Boolean):Boolean {
            if(failRetry)throw IOException("local retry");if(!isSessionCurrent())throw CancellationException("final retry session")
            if(!unchanged(expected))return false
            state=state.copy(queues=state.queues.map{if(it==queued)it.copy(attemptCount=it.attemptCount+1,nextAttemptAtEpochMillis=nextAttemptAtEpochMillis,lastError=errorCode)else it});failures++;return true
        }
        fun nextGeneration(){state=state.copy(queues=state.queues.map{it.copy(attemptCount=8)})}
    }
    private inner class Remote:RemoteMutationStore,CardPaymentPublicationRemote {
        var marker:CloudRecord?=null;var siblings=emptyList<CloudRecord>();var reads=0;var pages=0;var writes=0
        var onRead:suspend ()->Unit={};var onPublish:suspend ()->Unit={};var alterResult:(CloudRecord)->CloudRecord={it};var malformedPage=false
        var tx:CloudRecord?=payment;var cash:CloudRecord?=wallet
        var additionalLedger=emptyMap<String,CloudRecord?>()
        override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? {
            require(ownerUserId==owner && accessToken=="fixture");reads++;onRead()
            return when(entity){CloudEntity.LEDGER_TRANSACTION->if(recordId==txId)tx else additionalLedger[recordId];CloudEntity.LEDGER_WALLET->if(recordId==id)card else cash;else->error("Unexpected read")}
        }
        override suspend fun fetchCardCyclePage(cardId:String,accessToken:String,ownerUserId:UserId,offset:Int,limit:Int):DueOccurrencePage {
            require(cardId==id && ownerUserId==owner && accessToken=="fixture");pages++;onRead()
            if(malformedPage)return DueOccurrencePage(listOf(cycle(1)),offset)
            val all=listOfNotNull(marker)+siblings
            val page=all.drop(offset).take(1);return DueOccurrencePage(page,if(offset+page.size<all.size)offset+page.size else null)
        }
        override suspend fun publish(source:CardPaymentPublicationSnapshot,queued:QueuedMutation,observed:CardPaymentPublicationObservation,zone:java.time.ZoneId,accessToken:String):CloudRecord? {
            require(accessToken=="fixture");val d=planCardPaymentPublication(source,queued,observed,zone) as CardPaymentPublicationDecision.Write
            writes++;val p=d.payload;marker=CloudRecord(entity.table,queued.mutation.recordId,owner.value,p,p.financeRawString("updated_at"),p.financeRawString("deleted_at"),p.financeRawLong("sync_version")!!)
            onPublish();return alterResult(marker!!)
        }
        override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord=error("Generic creation forbidden")
        override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord?=error("Generic update forbidden")
    }
    private val entity=CloudEntity.DUE_OCCURRENCE_RECORD
    private fun worker(l:Local,r:Remote,enabled:Boolean=true)=CardPaymentPublicationCoordinator(l,r,r,enabled,{session},{now},{zone})
    private fun change(l:Local,row:CloudRecord) {
        val q=queue(row);l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(entity to listOf(row)),queues=listOf(q),dirtyKeys=setOf(entity.table to row.id))
    }
    @Test fun `new paid marker is published and ACKed without altering money`()=runTest {
        val l=Local();val r=Remote();val before=l.state.recordsByEntity-entity
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").pushed);assertEquals(1,r.writes);assertEquals(1,l.commits)
        assertTrue(l.state.queues.isEmpty());assertEquals(before,l.state.recordsByEntity-entity);assertEquals(1L,r.marker!!.syncVersion)
    }
    @Test fun `disabled gate touches no persistence or network`()=runTest {
        val l=Local();val r=Remote();assertEquals(DomainPushSummary(),worker(l,r,false).pushPending(owner,"fixture"));assertEquals(0,l.reads);assertEquals(0,r.reads)
    }
    @Test fun `lost response uses semantic ACK with full dependency reobservation`()=runTest {
        val l=Local();val r=Remote().apply{marker=cycle(1)}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").acknowledged);assertEquals(0,r.writes);assertEquals(6,r.reads);assertEquals(2,r.pages)
    }
    @Test fun `late new queue before write after write or inside ACK is preserved`()=runTest {
        for(stage in 0..2) {
            val l=Local();val r=Remote()
            when(stage){0->r.onRead={l.nextGeneration()};1->r.onPublish={l.nextGeneration()};2->l.onAck={l.nextGeneration()}}
            assertEquals(1,worker(l,r).pushPending(owner,"fixture").staleResponses);assertEquals(0,l.commits);assertEquals(8,l.state.queues.single().attemptCount)
            assertEquals(if(stage==0)0 else 1,r.writes);assertEquals(0,l.failures)
        }
    }
    @Test fun `account token zone changes and caller cancellation cannot ACK or retry`()=runTest {
        for(stage in 0..3) {
            session=AuthSession(owner,"test@example.com","fixture","refresh",Long.MAX_VALUE);zone=java.time.ZoneId.of("UTC")
            val l=Local();val r=Remote().apply{onPublish={when(stage){0->session=session!!.copy(accessToken="new");1->session=session!!.copy(userId=UserId(other));2->zone=java.time.ZoneId.of("Asia/Tokyo");else->throw CancellationException("caller")}}}
            assertTrue(runCatching{worker(l,r).pushPending(owner,"fixture")}.exceptionOrNull() is CancellationException);assertEquals(0,l.commits);assertEquals(0,l.failures)
        }
    }
    @Test fun `final session callback rolls back local ACK`()=runTest {
        val l=Local().apply{onAck={session=null}};val r=Remote()
        assertTrue(runCatching{worker(l,r).pushPending(owner,"fixture")}.exceptionOrNull() is CancellationException);assertEquals(0,l.commits);assertEquals(0,l.failures)
    }
    @Test fun `local read ACK and retry IO failures propagate without network bookkeeping`()=runTest {
        for(stage in 0..2) {
            val l=Local().apply{failRead=stage==0;failAck=stage==1;failRetry=stage==2};val r=Remote().apply{if(stage==2)onRead={throw IOException("remote")}}
            val e=runCatching{worker(l,r).pushPending(owner,"fixture")}.exceptionOrNull()
            assertEquals(listOf("local read","local ACK","local retry")[stage],e?.message);assertEquals(0,l.failures)
        }
    }
    @Test fun `transient remote errors backoff only the captured driver`()=runTest {
        val l=Local();val r=Remote().apply{onRead={throw IOException("remote secret")}}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").retryableFailures);val q=l.state.queues.single()
        assertEquals(now+30000,q.nextAttemptAtEpochMillis);assertEquals("network_io",q.lastError);assertEquals(0,r.writes)
    }
    @Test fun `closed RPC races are retryable without leaking diagnostics`()=runTest {
        val l=Local();val r=Remote().apply{onPublish={throw vn.com.quyln.mistia.core.network.SupabaseHttpException(400,"private diagnostics","card_payment_wallet_changed")}}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").retryableFailures);assertEquals(0,l.commits)
    }
    @Test fun `ambiguous submitted reply is retryable and next run ACKs actual result`()=runTest {
        val l=Local();val r=Remote().apply{alterResult={it.copy(syncVersion=91)}}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").retryableFailures);assertEquals(0,l.commits)
        l.state=l.state.copy(queues=l.state.queues.map{it.copy(nextAttemptAtEpochMillis=0)});r.alterResult={it}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").acknowledged);assertEquals(1,r.writes)
    }
    @Test fun `source and financial prerequisites defer without poisoning the queue`()=runTest {
        for(dep in listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.LEDGER_WALLET)) {
            val l=Local();val row=l.state.recordsByEntity.getValue(dep).first()
            val q=QueuedMutation(PendingMutation(dep,row.id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device),0,Long.MAX_VALUE,"conflict")
            l.state=l.state.copy(queues=l.state.queues+q,dirtyKeys=l.state.dirtyKeys+(row.entity to row.id))
            val r=Remote();assertEquals(DomainPushSummary(),worker(l,r).pushPending(owner,"fixture"));assertEquals(0,r.writes);assertEquals(0,l.failures)
        }
    }
    @Test fun `financial sibling on later page is retained as conflict`()=runTest {
        val l=Local();val r=Remote().apply{marker=cycle(1);siblings=listOf(DueOccurrenceRecord.fromCloudRecord(cycle(1)).copy(id=other).toCloudRecord())}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").conflicts);assertEquals(0,r.writes);assertEquals(0,l.commits);assertEquals(2,r.pages)
    }
    @Test fun `malformed page cannot grant authority`()=runTest {
        val l=Local();val r=Remote().apply{malformedPage=true}
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").permanentFailures);assertEquals(0,r.writes)
    }
    @Test fun `unobserved undo establishes tombstone and later repay can recover old receipt`()=runTest {
        val l=Local();val r=Remote();val deleted=DueOccurrenceRecord.fromCloudRecord(cycle()).copy(deletedAt=later,updatedAt=later).toCloudRecord()
        val tx=LedgerTransactionRecord.fromCloudRecord(payment).copy(deletedAt=later,updatedAt=later).toCloudRecord()
        change(l,deleted);l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(tx)));r.tx=tx
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").pushed);assertNotNull(r.marker!!.deletedAt)
        val paid="2026-10-15T02:00:00Z";val active=DueOccurrenceRecord.fromCloudRecord(cycle()).copy(paidAt=paid,updatedAt=paid,amountMinorSnapshot=70).toCloudRecord()
        val activeTx=LedgerTransactionRecord.fromCloudRecord(payment).copy(occurredAt=paid,updatedAt=paid,amountMinor=70,destinationAmountMinor=70,reportingAmountMinor=70).toCloudRecord()
        change(l,active);l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(activeTx)));r.tx=activeTx
        assertEquals(1,worker(l,r).pushPending(owner,"fixture").pushed);assertEquals(2L,r.marker!!.syncVersion);assertEquals(70L,r.marker!!.payload.financeRawLong("amount_minor_snapshot"))
    }
    @Test fun `complete scan finds payment after more than one hundred unrelated cycles`()=runTest {
        val l=Local();val extra=(1..127).map{n->DueOccurrenceRecord.fromCloudRecord(cycle()).copy(id=java.util.UUID(0,n.toLong()).toString(),sourceKindWireValue="recurringBill",statusWireValue="skipped",paidAt=null,linkedTransactionId=null).toCloudRecord()}
        val queues=extra.map(::queue)
        l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(entity to (extra+cycle())),queues=queues+l.state.queues,dirtyKeys=l.state.dirtyKeys+extra.map{it.entity to it.id})
        val r=Remote();assertEquals(1,worker(l,r).pushPending(owner,"fixture").pushed);assertEquals(127,l.state.queues.size)
    }
    @Test fun `unsupported legacy paid shape stays available to the ACK only path`()=runTest {
        val l=Local();change(l,DueOccurrenceRecord.fromCloudRecord(cycle()).copy(linkedTransactionId=null).toCloudRecord());val r=Remote()
        assertEquals(DomainPushSummary(),worker(l,r).pushPending(owner,"fixture"));assertEquals(0,r.writes);assertEquals(0,l.failures)
    }
    @Test fun `actual caller cancellation after server commit keeps the queue`()=runTest {
        val l=Local();val r=Remote().apply{onPublish={currentCoroutineContext().cancel();yield()}}
        val job=async{worker(l,r).pushPending(owner,"fixture")}
        assertTrue(runCatching{job.await()}.exceptionOrNull() is CancellationException)
        assertEquals(0,l.commits);assertEquals(0,l.failures);assertEquals(1,l.state.queues.size);assertNotNull(r.marker)
    }
    @Test fun `mismatched initial session never reads local state or makes requests`()=runTest {
        val l=Local();val r=Remote();session=session!!.copy(accessToken="rotated")
        assertTrue(runCatching{worker(l,r).pushPending(owner,"fixture")}.exceptionOrNull() is CancellationException)
        assertEquals(0,l.reads);assertEquals(0,r.reads);assertEquals(0,r.writes)
    }

    @Test fun `due composite publishes through the card capability independently of bill writes`()=runTest {
        val l=Local();val r=Remote()
        val due=DueOccurrencePushCoordinator(l,r,false,cardPaymentPublicationCoordinator=worker(l,r))
        assertEquals(1,due.pushPending(owner,"fixture").pushed)
        assertEquals(1,l.commits);assertEquals(1,r.writes);assertTrue(l.state.queues.isEmpty())
    }
    @Test fun `due composite preserves a modern undo awaiting its actual financial allocation`()=runTest {
        val l=Local();val r=Remote().apply{marker=cycle(1)}
        val tomb=DueOccurrenceRecord.fromCloudRecord(cycle()).copy(deletedAt=later,updatedAt=later).toCloudRecord()
        val tx=LedgerTransactionRecord.fromCloudRecord(payment).copy(deletedAt=later,updatedAt=later).toCloudRecord()
        change(l,tomb);l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(tx)));r.tx=tx
        val postId=investmentLedgerIdentity(txId,"cash-consumption-booked")
        val post=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postId,owner.value,buildJsonObject {
            put("id",postId);put("user_id",owner.value);put("event_id",txId);put("ledger_transaction_id",txId)
            put("created_at",time);put("updated_at",later);put("deleted_at",JsonNull);put("sync_version",0);put("last_modified_by_device_id",device)
        },later,null,0)
        val pq=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_POSTING,postId,owner.value,MutationKind.UPSERT,post.payload,later,0,device),0,Long.MAX_VALUE,"capacity_conflict")
        l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(CloudEntity.INVESTMENT_POSTING to listOf(post)),queues=l.state.queues+pq,dirtyKeys=l.state.dirtyKeys+(post.entity to postId))
        val before=l.state;val due=DueOccurrencePushCoordinator(l,r,false,cardPaymentPublicationCoordinator=worker(l,r))
        assertEquals(DomainPushSummary(),due.pushPending(owner,"fixture"));assertEquals(before,l.state)
        assertTrue("The actual card worker must examine its dependencies",l.reads>0)
        assertEquals(0,l.failures);assertEquals(0,l.commits);assertEquals(0,r.writes)
    }
    @Test fun `a later different payment recovers lost old marker receipts only after confirmed undo`()=runTest {
        val nextId="77777777-7777-7777-7777-777777777777";val paid="2026-10-15T02:00:00Z"
        for(deleted in listOf(false,true)) {
            val l=Local();val r=Remote()
            val dead=LedgerTransactionRecord.fromCloudRecord(payment).copy(deletedAt=later,updatedAt=later).toCloudRecord()
            val next=LedgerTransactionRecord.fromCloudRecord(payment).copy(id=nextId,occurredAt=paid,createdAt=paid,updatedAt=paid).toCloudRecord()
            val desired=DueOccurrenceRecord.fromCloudRecord(cycle()).copy(linkedTransactionId=nextId,paidAt=paid,updatedAt=paid).toCloudRecord()
            change(l,desired);l.state=l.state.copy(recordsByEntity=l.state.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(dead,next)))
            r.tx=dead;r.additionalLedger=mapOf(nextId to next)
            r.marker=DueOccurrenceRecord.fromCloudRecord(cycle(1)).copy(deletedAt=if(deleted)later else null,updatedAt=later).toCloudRecord()
            val before=l.state.recordsByEntity-entity
            assertEquals(1,worker(l,r).pushPending(owner,"fixture").pushed)
            assertEquals(nextId,r.marker!!.payload.financeRawString("linked_transaction_id"));assertEquals(before,l.state.recordsByEntity-entity)
            assertEquals(0,l.failures);assertTrue(l.state.queues.isEmpty())
        }
    }

}
