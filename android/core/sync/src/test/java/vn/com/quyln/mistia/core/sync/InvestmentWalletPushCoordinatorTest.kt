package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class InvestmentWalletPushCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="33333333-3333-3333-3333-333333333333"
    private val otherDevice="99999999-9999-9999-9999-999999999999"
    private val linked="44444444-4444-4444-4444-444444444444"
    private val id=investmentSystemWalletId(owner)
    private val token="root-token"
    private val now="2026-10-26T00:00:00Z"
    private val later="2026-10-26T01:00:00Z"
    private var session:AuthSession?=AuthSession(owner,null,token,"refresh",Long.MAX_VALUE)
    private fun row(v:Long=0,link:String?=null,date:String=now,actor:String=device,code:String="VND")=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("name","Investment wallet");put("kind_raw_value","investment")
        put("currency_code",code);put("opening_balance_minor",0);put("system_purpose_raw_value","investmentProfit")
        put("investment_linked_wallet_id",link?.let(::JsonPrimitive) ?: JsonNull);put("icon_symbol_name",WalletKind.INVESTMENT.defaultIcon);put("icon_color_hex",WalletKind.INVESTMENT.defaultColorHex)
        put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull);put("sort_order",Int.MAX_VALUE-100)
        put("is_archived",false);put("archived_at",JsonNull);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",date)
        put("sync_version",v);put("last_modified_by_device_id",actor);put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },date,null,v)
    private fun queue(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.LEDGER_WALLET,id,owner.value,MutationKind.UPSERT,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device),0,0,null)
    private fun coordinator(store:Store,remote:Remote,enabled:Boolean=true)=InvestmentWalletPushCoordinator(store,remote,enabled,{session},{4000})
    private fun target()=WalletDraft(id=linked,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record
    @Test fun canonicalRootCreatePublishesExactNullLongAndOnlyItsScopedQueue()=runTest {
        val local=row();val store=Store(local,queue(local));val remote=Remote().apply{created=row(1)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(row(1),store.row);assertNull(store.queued)
        assertEquals(JsonPrimitive(Long.MAX_VALUE),remote.createdPayload!!["future_large"])
        assertSame(JsonNull,remote.createdPayload!!["investment_linked_wallet_id"])
    }
    @Test fun rootSelectionCannotBeStarvedByTheCappedOrdinaryWalletOutbox()=runTest {
        val local=row();val store=Store(local,queue(local));val remote=Remote().apply{created=row(1)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertNull(store.queued) // Generic due-wallet selection below deliberately throws.
    }
    @Test fun disabledGateDoesNotReadFetchWriteOrPersistFailures()=runTest {
        val local=row();val q=queue(local);val store=Store(local,q);val remote=Remote()
        assertEquals(DomainPushSummary(),coordinator(store,remote,false).pushPending(owner,token))
        assertEquals(q,store.queued);assertEquals(0,store.reads);assertEquals(0,remote.fetches);assertEquals(0,remote.writes)
    }
    @Test fun anUnpublishedOrdinaryLinkedWalletDefersRootBeforeHttp()=runTest {
        val local=row(link=linked);val store=Store(local,queue(local)).apply{targetPending=queue(target()).let{it.copy(mutation=it.mutation.copy(recordId=linked))}}
        val remote=Remote();val before=store.queued
        assertEquals(DomainPushSummary(),coordinator(store,remote).pushPending(owner,token))
        assertEquals(before,store.queued);assertEquals(0,remote.fetches);assertEquals(0,remote.writes)
    }
    @Test fun aReservedLinkedTargetIsAnExplicitConflictWithoutAnHttpRequest()=runTest {
        val local=row(link=linked);val store=Store(local,queue(local)).apply{targetRow=target().let{it.copy(payload=JsonObject(it.payload+("system_purpose_raw_value" to JsonPrimitive("futureReserved"))))}}
        val remote=Remote()
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).conflicts)
        assertEquals("conflict_investment_wallet_invalid_link",store.queued!!.lastError)
        assertEquals(0,remote.fetches);assertEquals(0,remote.writes)
    }
    @Test fun serverCanonicalPresentationAndDerivedBalanceDoNotCauseAnotherMetadataWrite()=runTest {
        val local=row(3);val server=row(7).let{it.copy(payload=JsonObject(it.payload+buildJsonObject {
            put("name","Investment Wallet");put("sort_order",2147483547);put("current_balance_minor",9876543210L)
        }))}
        val store=Store(local,queue(local));val remote=Remote().apply{fetched=server}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(server,store.row);assertNull(store.queued);assertEquals(0,remote.writes)
    }
    @Test fun aChangedLinkedChoiceUsesTheExactComparedVersion()=runTest {
        val local=row(9007199254740993L,linked);val store=Store(local,queue(local))
        val remote=Remote().apply{fetched=row(9007199254740993L);updated=row(9007199254740994L,linked)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(9007199254740993L,remote.compared);assertEquals(9007199254740994L,remote.updatedPayload!!.financeRawLong("sync_version"))
        assertNull(store.queued)
    }
    @Test fun currencyMismatchIsHeldBeforeSameBaseCasOrLaterRemoteWinnerAck()=runTest {
        for(remoteVersion in listOf(3L,7L)) {
            val local=row(3,linked);val store=Store(local,queue(local));val remote=Remote().apply{fetched=row(remoteVersion,date=later,actor=otherDevice,code="JPY")}
            assertEquals(1,coordinator(store,remote).pushPending(owner,token).conflicts)
            assertEquals(local,store.row);assertNotNull(store.queued);assertEquals(0,remote.writes)
            assertEquals("conflict_investment_wallet_currency_changed",store.queued!!.lastError)
        }
    }
    @Test fun anotherDevicesLaterLinkChoiceKeepsTheExistingConflictPolicy()=runTest {
        val local=row(3,linked);val winner=row(4,date=later,actor=otherDevice)
        val store=Store(local,queue(local));val remote=Remote().apply{fetched=winner}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(winner,store.row);assertNull(store.queued);assertEquals(0,remote.writes)
    }
    @Test fun anUnprovenOwnLaterServerWriteCannotConsumeTheLocalChoice()=runTest {
        val local=row(3,linked);val store=Store(local,queue(local));val remote=Remote().apply{fetched=row(4,date=later)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).conflicts)
        assertEquals(local,store.row);assertNotNull(store.queued);assertEquals(0,remote.writes)
    }
    @Test fun staleCanonicalArchivesAreRestoredByCasWithoutChangingAccountingCurrency()=runTest {
        val local=row(3);val server=row(4,date=later,actor=otherDevice).let{it.copy(payload=JsonObject(it.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(later))))}
        val store=Store(local,queue(local));val remote=Remote().apply{fetched=server;updated=row(5)}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).pushed)
        assertEquals(4L,remote.compared);assertFalse(store.row!!.payload.financeRawArchived()!!);assertNull(store.queued)
    }
    @Test fun aLateCreateResultPreservesTheNewLinkedChoiceAndQueue()=runTest {
        val original=row();val newer=row(link=linked,date="2026-10-26T00:15:00Z");val store=Store(original,queue(original))
        val remote=Remote().apply{created=row(1);onWrite={store.row=newer;store.queued=queue(newer)}}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).staleResponses)
        assertEquals(newer,store.row);assertEquals(queue(newer),store.queued)
    }
    @Test fun changingTheLinkedDependencyDuringFetchDefersTheWrite()=runTest {
        val local=row(3,linked);val store=Store(local,queue(local));val remote=Remote().apply{
            fetched=row(3);onFetch={store.targetPending=queue(target()).let{it.copy(mutation=it.mutation.copy(recordId=linked))}}
        }
        assertEquals(DomainPushSummary(),coordinator(store,remote).pushPending(owner,token))
        assertNotNull(store.queued);assertEquals(0,remote.writes)
    }
    @Test fun tokenRotationDuringFetchRevokesWriteAndFailureBookkeeping()=runTest {
        val local=row();val q=queue(local);val store=Store(local,q)
        val remote=Remote().apply{onFetch={session=session!!.copy(accessToken="rotated")}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(q,store.queued);assertEquals(0,remote.writes)
    }
    @Test fun sessionRevokedDuringWriteCannotAcknowledgeTheResponse()=runTest {
        val local=row();val q=queue(local);val store=Store(local,q);val remote=Remote().apply{created=row(1);onWrite={session=null}}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,token)}.exceptionOrNull() is CancellationException)
        assertEquals(q,store.queued);assertEquals(local,store.row)
    }
    @Test fun retryableFailuresUseOnlyTheExactRootQueueAndSafeErrorCode()=runTest {
        val local=row();val store=Store(local,queue(local));val remote=Remote().apply{fetchError=SupabaseHttpException(503,"private body")}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).retryableFailures)
        assertEquals(1,store.queued!!.attemptCount);assertEquals(34000L,store.queued!!.nextAttemptAtEpochMillis);assertEquals("http_503",store.queued!!.lastError)
        assertEquals(local,store.row)
    }
    @Test fun createCollisionRefetchSemanticallyAcksCanonicalMetadataDespiteAnOlderClock()=runTest {
        val local=row(date=later);val winner=row(7)
        val store=Store(local,queue(local));val remote=Remote().apply{sequence.addAll(listOf(null,winner));createError=SupabaseHttpException(409,"")}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(winner,store.row);assertNull(store.queued);assertEquals(1,remote.writes);assertEquals(2,remote.fetches)
    }
    @Test fun aConditionalMissRefetchesTheOtherDevicesWinner()=runTest {
        val local=row(3,linked);val winner=row(4,date=later,actor=otherDevice)
        val store=Store(local,queue(local));val remote=Remote().apply{sequence.addAll(listOf(row(3),winner))}
        assertEquals(1,coordinator(store,remote).pushPending(owner,token).acknowledged)
        assertEquals(winner,store.row);assertNull(store.queued);assertEquals(1,remote.writes)
    }
    private inner class Store(var row:CloudRecord?,var queued:QueuedMutation?):LocalStore {
        var targetRow=target();var targetPending:QueuedMutation?=null;var reads=0
        fun snapshot(owner:UserId):InvestmentWalletPublicationSnapshot {
            val hasLink=row?.payload?.financeRawString("investment_linked_wallet_id")!=null
            return InvestmentWalletPublicationSnapshot(owner,row,queued,queued!=null,if(hasLink)targetRow else null,if(hasLink)targetPending else null,hasLink && targetPending!=null)
        }
        override suspend fun investmentWalletPublicationSnapshot(owner:UserId):InvestmentWalletPublicationSnapshot {reads++;return snapshot(owner)}
        override suspend fun acknowledgeInvestmentWalletMutation(mutation:QueuedMutation,remoteRecord:CloudRecord,expected:InvestmentWalletPublicationSnapshot,isSessionCurrent:()->Boolean):Boolean {
            val source=snapshot(owner)
            if(source!=expected || !source.matches(mutation) || source.dependency()!=InvestmentWalletPublicationDependency.READY)return false
            row=remoteRecord;queued=null;return true
        }
        override suspend fun recordInvestmentWalletMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String,expected:InvestmentWalletPublicationSnapshot,isSessionCurrent:()->Boolean):Boolean {
            if(snapshot(owner)!=expected || !expected.matches(mutation))return false
            queued=mutation.copy(attemptCount=mutation.attemptCount+1,nextAttemptAtEpochMillis=nextAttemptAtEpochMillis,lastError=errorCode);return true
        }
        override fun observe(entity:String,ownerUserId:UserId)=MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId:UserId)=MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=row?.takeIf{it.id==recordId && it.ownerUserId==ownerUserId.value}
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=error("No generic root mutation write")
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int):List<QueuedMutation> = error("Root must not use capped ordinary-wallet queue selection")
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=error("No root pull replacement")
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String):Set<String> = setOfNotNull(queued?.mutation?.recordId)
        override suspend fun clearAccount(ownerUserId:UserId)=error("No root account clearing")
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord):Boolean=error("No generic root ACK")
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String):Boolean=error("No generic root failure write")
    }
    private inner class Remote:RemoteMutationStore {
        var fetched:CloudRecord?=null;var created:CloudRecord?=null;var updated:CloudRecord?=null
        var createdPayload:JsonObject?=null;var updatedPayload:JsonObject?=null;var compared:Long?=null
        var fetchError:Exception?=null;var createError:Exception?=null
        var onFetch:(()->Unit)?=null;var onWrite:(()->Unit)?=null
        val sequence=mutableListOf<CloudRecord?>();var fetches=0;var writes=0
        override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? {
            require(entity==CloudEntity.LEDGER_WALLET && recordId==id && ownerUserId==owner && accessToken==token)
            fetches++;onFetch?.invoke();fetchError?.let{throw it};return if(sequence.isNotEmpty())sequence.removeAt(0) else fetched
        }
        override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord {
            require(entity==CloudEntity.LEDGER_WALLET && ownerUserId==owner && payload.financeRawString("id")==id)
            writes++;createdPayload=payload;onWrite?.invoke();createError?.let{throw it};return requireNotNull(created)
        }
        override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? {
            require(entity==CloudEntity.LEDGER_WALLET && recordId==id && ownerUserId==owner)
            writes++;compared=expectedVersion;updatedPayload=payload;onWrite?.invoke();return updated
        }
    }
}
