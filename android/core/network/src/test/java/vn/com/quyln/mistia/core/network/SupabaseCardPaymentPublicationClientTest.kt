package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class SupabaseCardPaymentPublicationClientTest {
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
    private val wallet=LedgerWalletRecord.fromCloudRecord(WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).record)
    private val card=wallet.copy(id=id,name="Card",kindWireValue="creditCard")
    private val payment=TransactionDraft(id=txId,primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,
        title="Pay Card",amountMinor=amount,occurredAt=now,sourceWalletId=wallet.id,destinationWalletId=card.id)
        .toMutation(owner,null,wallet,card,null,device,now).record.copy(syncVersion=version)
    private val cycle=DueOccurrenceRecord(cycleId,owner.value,"creditCard",card.id,"2026-09","2026-10-25T15:00:00Z",amount,"paid",now,txId,now,now,null,version,device)
    private fun source(c:DueOccurrenceRecord=cycle.copy(syncVersion=0),tx:LedgerTransactionRecord=payment,w:LedgerWalletRecord=wallet):CardPaymentPublicationSnapshot {
        val rows=listOf(w.toCloudRecord(),card.toCloudRecord(),tx.toCloudRecord(),c.toCloudRecord())
        val q=QueuedMutation(c.pendingMutation(if(c.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE),0,0,null)
        return CardPaymentPublicationSnapshot(owner,card.id,CardPaymentPublicationSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}},listOf(q),setOf(CloudEntity.DUE_OCCURRENCE_RECORD.table to c.id))
    }
    private fun observation(c:DueOccurrenceRecord?=null,tx:LedgerTransactionRecord?=payment,w:LedgerWalletRecord?=wallet)=
        CardPaymentPublicationObservation(listOfNotNull(c?.toCloudRecord()),mapOf(txId to tx?.toCloudRecord()),mapOf(walletId to w?.toCloudRecord(),card.id to card.toCloudRecord()))
    private val token="card-local-test-token"
    private val enabled=AtomicBoolean(true)
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private lateinit var server:MockWebServer
    private lateinit var http:OkHttpClient
    private lateinit var client:SupabaseCardPaymentPublicationClient
    @Before fun open() {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val st=HandshakeCertificates.Builder().heldCertificate(cert).build();val ct=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server=MockWebServer().apply{useHttps(st.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(ct.sslSocketFactory(),ct.trustManager).retryOnConnectionFailure(false).callTimeout(3,java.util.concurrent.TimeUnit.SECONDS).build()
        client=SupabaseCardPaymentPublicationClient(SupabaseConfig(server.url("/").toString(),"local-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun write(s:CardPaymentPublicationSnapshot,o:CardPaymentPublicationObservation)=
        planCardPaymentPublication(s,s.queues.single(),o,ZoneId.of("UTC")) as CardPaymentPublicationDecision.Write
    private suspend fun send(s:CardPaymentPublicationSnapshot=source(),o:CardPaymentPublicationObservation=observation())=
        client.publish(s,s.queues.single(),o,ZoneId.of("UTC"),token)
    @Test fun createSendsClosedExplicitNullCycleAndExactLongAmountWithoutAnyGenericBypass()=runTest {
        val s=source();val d=write(s,observation());server.enqueue(MockResponse().setBody(d.payload.toString()))
        val saved=send()!!;assertEquals(1L,saved.syncVersion);assertEquals(amount,saved.payload.financeRawLong("amount_minor_snapshot"))
        val r=requireNotNull(server.takeRequest(2,java.util.concurrent.TimeUnit.SECONDS));assertEquals("POST",r.method);assertEquals("/rest/v1/rpc/mutate_card_paid_cycle",r.requestUrl!!.encodedPath);assertNull(r.requestUrl!!.query)
        assertEquals("Bearer $token",r.getHeader("Authorization"));assertEquals("local-key",r.getHeader("apikey"));assertEquals("return=representation",r.getHeader("Prefer"))
        val sent=Json.parseToJsonElement(r.body.readUtf8()).jsonObject
        assertEquals(d.payload,sent["p_cycle"]);assertEquals(JsonPrimitive(false),sent["p_expected_presence"])
        assertTrue("deleted_at" in d.payload && d.payload["deleted_at"]==JsonNull)
    }
    @Test fun conditionalUpdateUsesOwnerIdAndExactLargeComparedVersion()=runTest {
        val s=source(cycle);val o=observation(cycle.copy(statusWireValue="pending",paidAt=null,linkedTransactionId=null));val d=write(s,o)
        server.enqueue(MockResponse().setBody(d.payload.toString()));assertEquals(version+1,send(s,o)!!.syncVersion)
        val r=requireNotNull(server.takeRequest(2,java.util.concurrent.TimeUnit.SECONDS));assertEquals("POST",r.method);assertEquals("/rest/v1/rpc/mutate_card_paid_cycle",r.requestUrl!!.encodedPath);assertNull(r.requestUrl!!.query)
        val body=Json.parseToJsonElement(r.body.readUtf8()).jsonObject
        assertEquals(d.payload,body["p_cycle"]);assertEquals(JsonPrimitive(version),body["p_expected_version"]);assertEquals(JsonPrimitive(true),body["p_expected_presence"])
    }
    @Test fun anExistingZeroIdentityUsesComparedPresenceAndClosedRpcVersionConflict()=runTest {
        val s=source().let{it.copy(queues=it.queues.map{q->q.copy(remoteIdentityObserved=true)})}
        val o=observation(cycle.copy(syncVersion=0,statusWireValue="pending",paidAt=null,linkedTransactionId=null))
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"card_payment_version_conflict","detail":"hidden detail"}"""))
        val error=runCatching{send(s,o)}.exceptionOrNull() as SupabaseHttpException
        assertEquals("card_payment_version_conflict",error.serviceCode);assertEquals("",error.responseBody)
        val r=requireNotNull(server.takeRequest(2,java.util.concurrent.TimeUnit.SECONDS));assertEquals("POST",r.method)
        val body=Json.parseToJsonElement(r.body.readUtf8()).jsonObject
        assertEquals(JsonPrimitive(0),body["p_expected_version"]);assertEquals(JsonPrimitive(true),body["p_expected_presence"])
    }
    @Test fun gatesSessionAndChangedFinancialProofRefuseHttp()=runTest {
        enabled.set(false);assertTrue(runCatching{send()}.exceptionOrNull() is IllegalStateException);assertEquals(0,server.requestCount)
        enabled.set(true);session.set(session.get()!!.copy(userId=UserId(other)));assertTrue(runCatching{send()}.exceptionOrNull() is CancellationException);assertEquals(0,server.requestCount)
        session.set(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
        assertTrue(runCatching{send(o=observation(tx=payment.copy(amountMinor=amount-1)))}.isFailure);assertEquals(0,server.requestCount)
    }
    @Test fun malformedDifferentPartialOrDuplicateRepliesCannotAcknowledgeACycle()=runTest {
        val d=write(source(),observation())
        val replies=listOf(JsonArray(emptyList()),JsonArray(listOf(d.payload,d.payload)),JsonObject(d.payload+("user_id" to JsonPrimitive(other))),JsonObject(d.payload+("amount_minor_snapshot" to JsonPrimitive(17))),JsonObject(d.payload+("sync_version" to JsonPrimitive(2))),JsonObject(d.payload-("paid_at")))
        for(raw in replies){server.enqueue(MockResponse().setBody(raw.toString()));assertTrue(runCatching{send()}.exceptionOrNull() is IOException)}
    }
    @Test fun redirectsAndServerDiagnosticsAreClosed()=runTest {
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location",server.url("/redirected")))
        val redirect=runCatching{send()}.exceptionOrNull() as SupabaseHttpException;assertEquals(302,redirect.statusCode);assertEquals(1,server.requestCount)
        server.enqueue(MockResponse().setResponseCode(409).setBody("sensitive backend diagnostics"))
        val collision=runCatching{send()}.exceptionOrNull() as SupabaseHttpException;assertEquals(409,collision.statusCode);assertEquals("",collision.responseBody)
    }
    @Test fun sessionRotationAfterACommittedRequestCancelsBeforeReturningItsReceipt()=runTest {
        val d=write(source(),observation())
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {session.set(session.get()!!.copy(accessToken="rotated"));return MockResponse().setBody(d.payload.toString())}}
        assertTrue(runCatching{send()}.exceptionOrNull() is CancellationException);assertEquals(1,server.requestCount)
    }
    @Test fun postgresTimestampRepresentationIsNormalizedWithoutChangingBusinessFields()=runTest {
        val d=write(source(),observation())
        val p=JsonObject(d.payload.mapValues{(key,value)->if(key in setOf("created_at","updated_at","scheduled_date","paid_at") && value!=JsonNull)JsonPrimitive(value.jsonPrimitive.content.replace("Z","+00:00"))else value})
        server.enqueue(MockResponse().setBody(p.toString()))
        assertEquals(1L,send()!!.syncVersion)
    }
    @Test fun gateRotationDuringTheWriteCancelsBeforeExposingAnyReceipt()=runTest {
        val d=write(source(),observation())
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {enabled.set(false);return MockResponse().setBody(d.payload.toString())}}
        assertTrue(runCatching{send()}.exceptionOrNull() is CancellationException)
    }
    @Test fun cleartextConfigurationIsRejectedBeforeAnyRequest()=runTest {
        client=SupabaseCardPaymentPublicationClient(SupabaseConfig("http://localhost/","local-key"),http,{session.get()},{enabled.get()})
        assertTrue(runCatching{send()}.exceptionOrNull() is IllegalStateException);assertEquals(0,server.requestCount)
    }
    @Test fun callerCancellationCancelsTheLiveTransport()=runTest {
        val d=write(source(),observation())
        server.enqueue(MockResponse().setBody(d.payload.toString()).setBodyDelay(500,java.util.concurrent.TimeUnit.MILLISECONDS))
        val job=async(start=kotlinx.coroutines.CoroutineStart.UNDISPATCHED){send()}
        assertNotNull(server.takeRequest(2,java.util.concurrent.TimeUnit.SECONDS));job.cancel()
        assertTrue(runCatching{job.await()}.exceptionOrNull() is CancellationException)
    }

    @Test fun paidWriteUsesAtomicComparedRpcWithSourceLedgerWalletAndCompleteSiblingMembership()=runTest {
        val s=source();val o=observation();val d=write(s,o)
        server.enqueue(MockResponse().setBody(d.payload.toString()))
        val result=runCatching{send(s,o)}
        val request=requireNotNull(server.takeRequest(2,java.util.concurrent.TimeUnit.SECONDS))
        assertEquals("Atomic source/ledger fence cannot be replaced by a generic marker INSERT","/rest/v1/rpc/mutate_card_paid_cycle",request.requestUrl!!.encodedPath)
        assertEquals("POST",request.method);assertNull(request.requestUrl!!.query)
        val body=Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals(setOf("p_cycle","p_expected_version","p_expected_presence","p_expected_ledger","p_expected_wallets","p_expected_cycles"),body.keys)
        assertEquals(d.payload,body["p_cycle"]);assertEquals(JsonPrimitive(0),body["p_expected_version"]);assertEquals(JsonPrimitive(false),body["p_expected_presence"])
        assertEquals(JsonObject(o.ledger.mapValues{it.value?.payload ?: JsonNull}),body["p_expected_ledger"])
        assertEquals(JsonObject(o.wallets.mapValues{it.value?.payload ?: JsonNull}),body["p_expected_wallets"]);assertEquals(JsonArray(emptyList()),body["p_expected_cycles"])
        assertTrue(result.isSuccess)
    }


    @Test fun realPostgresObservedZeroUpdateKeepsTheActualServerAuditTimestamp()=runTest {
        val frame=Json.parseToJsonElement(requireNotNull(javaClass.getResourceAsStream("/card-paid-cycle-postgres-receipt.json")).bufferedReader().use{it.readText()}).jsonObject
        val actualOwner=UserId(requireNotNull(frame.financeRawString("owner")))
        fun row(entity:CloudEntity,p:JsonObject)=CloudRecord(entity.table,requireNotNull(p.financeRawString("id")),actualOwner.value,p,
            p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
        val desired=row(CloudEntity.DUE_OCCURRENCE_RECORD,frame.getValue("localCycle").jsonObject)
        val q=QueuedMutation(DueOccurrenceRecord.fromCloudRecord(desired).pendingMutation(),0,0,null,remoteIdentityObserved=true)
        val rows=frame.getValue("records").jsonArray.map{raw->val r=raw.jsonObject;row(requireNotNull(CloudEntity.fromTable(requireNotNull(r.financeRawString("entity")))),r.getValue("payload").jsonObject)}+desired
        val s=CardPaymentPublicationSnapshot(actualOwner,requireNotNull(frame.financeRawString("cardId")),CardPaymentPublicationSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}},listOf(q),setOf(desired.entity to desired.id))
        val proof=frame.getValue("observed").jsonObject
        fun dependencies(key:String,entity:CloudEntity)=proof.getValue(key).jsonObject.mapValues{if(it.value==JsonNull)null else row(entity,it.value.jsonObject)}
        val o=CardPaymentPublicationObservation(proof.getValue("s").jsonArray.map{row(CloudEntity.DUE_OCCURRENCE_RECORD,it.jsonObject)},dependencies("l",CloudEntity.LEDGER_TRANSACTION),dependencies("w",CloudEntity.LEDGER_WALLET))
        write(s,o)
        session.set(AuthSession(actualOwner,null,token,"refresh",Long.MAX_VALUE))
        val actual=frame.getValue("result").jsonObject
        assertNotEquals(desired.updatedAt,actual.financeRawString("updated_at"))
        server.enqueue(MockResponse().setBody(actual.toString()))
        val receipt=runCatching{send(s,o)}
        assertNotNull(server.takeRequest(2,java.util.concurrent.TimeUnit.SECONDS))
        assertTrue("A real committed SQL result must acknowledge even when the server updates its audit timestamp: ${receipt.exceptionOrNull()}",receipt.isSuccess)
        assertEquals(actual.financeRawString("updated_at"),receipt.getOrThrow()!!.updatedAt)
    }

    @Test fun transactionAbortCodesAreClosedAndRetryable()=runTest {
        for(code in listOf("40P01","40001")) {
            server.enqueue(MockResponse().setResponseCode(400).setBody(buildJsonObject{put("code",code);put("message","private server diagnostics")}.toString()))
            val error=runCatching{send()}.exceptionOrNull() as SupabaseHttpException
            assertEquals("card_payment_retry_transaction",error.serviceCode);assertEquals("",error.responseBody)
        }
    }
}
