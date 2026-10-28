package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class SupabaseInvestmentOrdinaryClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-28T00:00:00Z"
    private val token="ordinary-contract-token"
    private val enabled=AtomicBoolean(true)
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private lateinit var server:MockWebServer
    private lateinit var client:SupabaseInvestmentOrdinaryClient
    private lateinit var http:OkHttpClient
    @Before fun setup() {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val st=HandshakeCertificates.Builder().heldCertificate(cert).build()
        val ct=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server=MockWebServer().apply{useHttps(st.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(ct.sslSocketFactory(),ct.trustManager).retryOnConnectionFailure(false).callTimeout(3,TimeUnit.SECONDS).build()
        client=SupabaseInvestmentOrdinaryClient(SupabaseConfig(server.url("/").toString(),"local-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val event=id(20)
    private fun wallet(n:Int,opening:Long=100)=WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
    private fun source(transfer:Boolean=false):InvestmentOrdinaryPublicationSnapshot {
        val parent=CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record
        val root=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1))}))}
        val legacy=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60);put("accounting_amount_minor",60);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-28T00:00:01Z")
        },now,null,0)
        val rows=listOf(root,wallet(1),wallet(2,0),parent.toCloudRecord(),child.toCloudRecord(),legacy)
        val save=TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}})
        val draft=if(transfer)TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,title="Transfer",amountMinor=70,destinationAmountMinor=70,sourceWalletId=id(1),destinationWalletId=id(2),occurredAt="2026-10-28T00:00:02Z")
            else TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,sourceWalletId=id(1),categoryId=id(31),occurredAt="2026-10-28T00:00:02Z")
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(event,now),null,"Adjustment","JPY")
        val error=runCatching{planTransactionInvestmentSave(save,request,device,now)}.exceptionOrNull()
        assertTrue(error is InvestmentFundUsageConfirmationRequired)
        val plan=planTransactionInvestmentSave(save,request.copy(consent=(error as InvestmentFundUsageConfirmationRequired).review.consent),device,now)
        val pending=plan.mutations.map{QueuedMutation(it.second,0,0,null)}
        return InvestmentOrdinaryPublicationSnapshot(owner,event,rows+plan.mutations.map{it.first},pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }

    private fun result(s:InvestmentOrdinaryPublicationSnapshot):InvestmentOrdinaryPublicationResult {
        val g=investmentOrdinaryPublicationGroup(s)
        fun saved(r:CloudRecord)=r.copy(syncVersion=r.syncVersion+1,payload=JsonObject(r.payload+("sync_version" to JsonPrimitive(r.syncVersion+1))))
        return InvestmentOrdinaryPublicationResult(s.owner,s.eventId,saved(g.primary),g.adjustment?.let(::saved),g.postings.map(::saved))
    }
    private fun body(r:InvestmentOrdinaryPublicationResult)=buildJsonObject {
        put("transaction",r.transaction.payload);put("adjustment",r.adjustment?.payload ?: JsonNull);put("postings",JsonArray(r.postings.map{it.payload}))
    }
    private fun auth(r:RecordedRequest){assertEquals("Bearer $token",r.getHeader("Authorization"));assertEquals("local-key",r.getHeader("apikey"))}
    @Test fun wholeGroupUsesOnlyTheClosedRpcWithEveryExplicitNullAndExactLongComparison()=runTest {
        val original=source();val base=9007199254740993L
        val keys=investmentOrdinaryPublicationGroup(original).rows.map{it.entity to it.id}.toSet()
        val s=original.copy(rows=original.rows.map{if(it.entity to it.id in keys)it.copy(syncVersion=base,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(base))))else it},pending=original.pending.map{it.copy(mutation=it.mutation.copy(baseVersion=base,payload=JsonObject(requireNotNull(it.mutation.payload)+("sync_version" to JsonPrimitive(base)))))})
        val expected=result(s);server.enqueue(MockResponse().setBody(body(expected).toString()))
        assertEquals(expected,client.publish(s,token));val r=server.takeRequest();auth(r)
        assertEquals("POST",r.method);assertEquals("/rest/v1/rpc/mutate_ordinary_investment_event",r.requestUrl!!.encodedPath)
        assertNull(r.requestUrl!!.query);assertFalse(r.getHeader("Prefer")!!.contains("merge"))
        val sent=Json.parseToJsonElement(r.body.readUtf8()).jsonObject;val g=investmentOrdinaryPublicationGroup(s)
        assertEquals(setOf("p_transaction","p_adjustment","p_postings","p_expected_version","p_expected_adjustment_version","p_expected_posting_versions","p_expected_presence"),sent.keys)
        assertEquals(g.primary.payload,sent["p_transaction"]);assertEquals(JsonNull,sent["p_adjustment"])
        assertEquals(JsonPrimitive(base),sent["p_expected_version"]);assertEquals(JsonPrimitive(0),sent["p_expected_adjustment_version"])
        assertEquals(buildJsonObject{g.postings.forEach{put(it.id,base)}},sent["p_expected_posting_versions"])
        assertEquals(JsonArray(g.postings.map{it.payload}),sent["p_postings"])
        assertEquals(buildJsonObject{g.rows.forEach{put(it.id,true)}},sent["p_expected_presence"])
    }
    @Test fun readIsOwnerScopedAndUsesTerminalEmptyPaginationEvenForShortPagesWithWritesOff()=runTest {
        val s=source(true);val r=result(s);enabled.set(false)
        server.enqueue(MockResponse().setBody(JsonArray(listOf(r.transaction.payload)).toString()))
        r.postings.sortedBy{it.id}.forEach{server.enqueue(MockResponse().setBody(JsonArray(listOf(it.payload)).toString()))}
        server.enqueue(MockResponse().setBody("[]"))
        server.enqueue(MockResponse().setBody(JsonArray(listOf(r.transaction.payload)).toString()))
        val actual=client.fetchEvent(owner,event,token);assertEquals(r.transaction,actual.transaction);assertNull(actual.adjustment);assertEquals(r.postings.sortedBy{it.id},actual.postings)
        val ledger=server.takeRequest();auth(ledger);assertEquals("eq.${owner.value}",ledger.requestUrl!!.queryParameter("user_id"))
        assertEquals("in.($event,${investmentLedgerIdentity(event,"cash-unreconciled-adjustment")})",ledger.requestUrl!!.queryParameter("id"))
        val sorted=r.postings.sortedBy{it.id}
        for(i in 0..sorted.size){val request=server.takeRequest();auth(request);assertEquals("eq.${owner.value}",request.requestUrl!!.queryParameter("user_id"));assertEquals("eq.$event",request.requestUrl!!.queryParameter("event_id"));assertEquals(if(i==0)null else "gt.${sorted[i-1].id}",request.requestUrl!!.queryParameter("id"))}
        val fence=server.takeRequest();auth(fence);assertEquals(ledger.requestUrl,fence.requestUrl)
    }
    @Test fun partialDuplicateDifferentOrPrivateResponsesAreAmbiguousAndCannotAck()=runTest {
        val s=source(true);val r=result(s)
        val replies=listOf(body(r.copy(postings=r.postings.dropLast(1))),body(r.copy(postings=r.postings+r.postings.first())),body(r.copy(transaction=r.transaction.copy(payload=JsonObject(r.transaction.payload+("amount_minor" to JsonPrimitive(69)))))),body(r.copy(transaction=r.transaction.copy(payload=JsonObject(r.transaction.payload+("_mistia_android_fake" to JsonPrimitive(true)))))))
        for(reply in replies){server.enqueue(MockResponse().setBody(reply.toString()));assertTrue(runCatching{client.publish(s,token)}.exceptionOrNull() is IOException)}
    }
    @Test fun gatesAndCapturedSessionsRefuseWritesBeforeHttp()=runTest {
        val s=source();enabled.set(false)
        assertTrue(runCatching{client.publish(s,token)}.exceptionOrNull() is IllegalStateException)
        enabled.set(true);session.set(session.get()!!.copy(accessToken="rotated"))
        assertTrue(runCatching{client.publish(s,token)}.exceptionOrNull() is CancellationException)
        assertEquals(0,server.requestCount)
    }
    @Test fun revocationDuringHttpFailureCancelsAndNeverRecordsAStaleAuthorizationFailure()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse{enabled.set(false);return MockResponse().setResponseCode(403).setBody("private details")}}
        assertTrue(runCatching{client.publish(source(),token)}.exceptionOrNull() is CancellationException)
    }
    @Test fun sqlConditionsAreClosedAndPrivateDiagnosticsAreDiscarded()=runTest {
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"ordinary_investment_version_conflict","details":"private diagnostics"}"""))
        val error=runCatching{client.publish(source(),token)}.exceptionOrNull() as SupabaseHttpException
        assertEquals("ordinary_investment_version_conflict",error.serviceCode);assertFalse(error.toString().contains("private diagnostics"))
    }
    @Test fun redirectCannotForwardBearerCredentials()=runTest {
        server.enqueue(MockResponse().setResponseCode(307).setHeader("Location",server.url("/foreign")))
        assertTrue(runCatching{client.publish(source(),token)}.exceptionOrNull() is SupabaseHttpException);assertEquals(1,server.requestCount)
    }
    private fun unreconciled(s:InvestmentOrdinaryPublicationSnapshot):InvestmentOrdinaryPublicationSnapshot {
        val g=investmentOrdinaryPublicationGroup(s);val old=g.postings.single()
        val postId=investmentLedgerIdentity(event,"cash-consumption-unreconciled")
        val post=old.copy(id=postId,payload=JsonObject(old.payload+buildJsonObject{put("id",postId);put("cash_bucket_raw_value","unreconciled")}))
        val adjustmentId=investmentLedgerIdentity(event,"cash-unreconciled-adjustment")
        val adjustment=g.primary.copy(id=adjustmentId,payload=JsonObject(g.primary.payload+buildJsonObject {
            put("id",adjustmentId);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("settlement_role_raw_value","investmentReserveUse")
            put("title","Adjustment");put("source_wallet_id",investmentSystemWalletId(owner));put("destination_wallet_id",id(1));put("category_id",JsonNull)
            put("amount_minor",30);put("destination_amount_minor",30);put("reporting_amount_minor",30);put("reporting_expense_minor",0);put("reporting_income_minor",0)
            put("source_currency_code","JPY");put("destination_currency_code","JPY");put("reporting_currency_code","JPY")
        }))
        val pending=s.pending.map{q->if(q.mutation.recordId==old.id)q.copy(mutation=q.mutation.copy(recordId=post.id,payload=post.payload))else q}+QueuedMutation(PendingMutation(CloudEntity.LEDGER_TRANSACTION,adjustment.id,owner.value,MutationKind.UPSERT,adjustment.payload,now,0,device),0,0,null)
        return s.copy(rows=s.rows.map{if(it==old)post else it}+adjustment,pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }
    @Test fun reserveAdjustmentAndCompleteTombstonesAreSentInTheSameAtomicRequest()=runTest {
        val live=unreconciled(source());val keys=investmentOrdinaryPublicationGroup(live).rows.map{it.entity to it.id}.toSet()
        val deleted=live.copy(rows=live.rows.map{if(it.entity to it.id in keys)it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))else it},pending=live.pending.map{it.copy(mutation=it.mutation.copy(kind=MutationKind.DELETE,payload=JsonObject(requireNotNull(it.mutation.payload)+("deleted_at" to JsonPrimitive(now)))))})
        for(s in listOf(live,deleted)) {
            val expected=result(s);server.enqueue(MockResponse().setBody(body(expected).toString()));assertEquals(expected,client.publish(s,token))
            val sent=Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject;val group=investmentOrdinaryPublicationGroup(s)
            assertEquals(group.adjustment!!.payload,sent["p_adjustment"])
            assertEquals(JsonArray(group.postings.map{it.payload}),sent["p_postings"])
            assertEquals(group.primary.payload,sent["p_transaction"])
        }
    }
    @Test fun sessionRotationAfterSuccessfulReplyStillCancelsBeforeAnyResultEscapes()=runTest {
        val s=source();val reply=body(result(s)).toString()
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse{session.set(session.get()!!.copy(accessToken="rotated"));return MockResponse().setBody(reply)}}
        assertTrue(runCatching{client.publish(s,token)}.exceptionOrNull() is CancellationException)
    }
    @Test fun corruptLocalGenerationOrPrivateWireDataNeverReachesHttp()=runTest {
        val s=source();val badQueue=s.copy(pending=s.pending.map{it.copy(mutation=it.mutation.copy(baseVersion=1))})
        assertTrue(runCatching{client.publish(badQueue,token)}.isFailure)
        val primary=investmentOrdinaryPublicationGroup(s).primary
        val p=JsonObject(primary.payload+("_mistia_android_forged" to JsonPrimitive(true)))
        val privateSource=s.copy(rows=s.rows.map{if(it.id==primary.id)it.copy(payload=p)else it},pending=s.pending.map{if(it.mutation.recordId==primary.id)it.copy(mutation=it.mutation.copy(payload=p))else it})
        assertTrue(runCatching{client.publish(privateSource,token)}.isFailure);assertEquals(0,server.requestCount)
    }
    @Test fun foreignCloudReadAndRepeatedPostingCursorCannotBecomeARecoveryProof()=runTest {
        val s=source();val r=result(s)
        val foreign=JsonObject(r.transaction.payload+("user_id" to JsonPrimitive(device)))
        server.enqueue(MockResponse().setBody(JsonArray(listOf(foreign)).toString()))
        assertTrue(runCatching{client.fetchEvent(owner,event,token)}.isFailure)
        server.enqueue(MockResponse().setBody(JsonArray(listOf(r.transaction.payload)).toString()))
        val page=JsonArray(r.postings.map{it.payload}).toString()
        server.enqueue(MockResponse().setBody(page));server.enqueue(MockResponse().setBody(page))
        assertTrue(runCatching{client.fetchEvent(owner,event,token)}.isFailure)
    }
    @Test fun unknownSqlMessagesAndResponseShapesNeverLeakPrivateDiagnostics()=runTest {
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"private diagnostic","details":"private details"}"""))
        val error=runCatching{client.publish(source(),token)}.exceptionOrNull() as SupabaseHttpException
        assertNull(error.serviceCode);assertFalse(error.toString().contains("private"))
        server.enqueue(MockResponse().setBody("[]"));assertTrue(runCatching{client.publish(source(),token)}.exceptionOrNull() is IOException)
    }

    @Test fun aMutableParentChangingBetweenReadPagesMakesTheObservationRetryable()=runTest {
        val s=source();val first=result(s);val next=first.transaction.copy(syncVersion=2,payload=JsonObject(first.transaction.payload+("sync_version" to JsonPrimitive(2))))
        server.enqueue(MockResponse().setBody(JsonArray(listOf(first.transaction.payload)).toString()))
        server.enqueue(MockResponse().setBody(JsonArray(first.postings.map{it.payload}).toString()))
        server.enqueue(MockResponse().setBody("[]"))
        server.enqueue(MockResponse().setBody(JsonArray(listOf(next.payload)).toString()))
        assertTrue(runCatching{client.fetchEvent(owner,event,token)}.exceptionOrNull() is IOException)
    }

    @Test fun zeroBirthAndObservedZeroUseDifferentCompletePresenceComparisons()=runTest {
        val initial=source()
        for(existing in listOf(false,true)) {
            val s=initial.copy(pending=initial.pending.map{it.copy(remoteIdentityObserved=existing)})
            server.enqueue(MockResponse().setBody(body(result(s)).toString()));client.publish(s,token)
            val sent=Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
            assertEquals(buildJsonObject{investmentOrdinaryPublicationGroup(s).rows.forEach{put(it.id,existing)}},sent["p_expected_presence"])
        }
    }
    @Test fun observedZeroCloudRowsRemainReadableWithWritesDisabled()=runTest {
        enabled.set(false);val s=source();val g=investmentOrdinaryPublicationGroup(s)
        val ledger=JsonArray(listOf(g.primary.payload)).toString()
        server.enqueue(MockResponse().setBody(ledger));server.enqueue(MockResponse().setBody(JsonArray(g.postings.map{it.payload}).toString()));server.enqueue(MockResponse().setBody("[]"));server.enqueue(MockResponse().setBody(ledger))
        val cloud=client.fetchEvent(owner,event,token)
        assertEquals(0L,cloud.transaction!!.syncVersion);assertTrue(cloud.postings.all{it.syncVersion==0L})
    }

}
