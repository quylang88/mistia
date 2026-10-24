package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class SupabaseInvestmentChannelClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val token="channel-access-token"
    private val now="2026-10-24T00:00:00Z"
    private val version=9007199254740993L
    private lateinit var server:MockWebServer
    private lateinit var client:SupabaseInvestmentChannelClient
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private val calls=java.util.Collections.synchronizedList(mutableListOf<okhttp3.Call>())
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).eventListener(object:okhttp3.EventListener(){override fun callStart(call:okhttp3.Call){calls.add(call)}}).build()
        client=SupabaseInvestmentChannelClient(SupabaseConfig(server.url("/").toString(),"publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun payload(v:Long=version)=InvestmentChannelRecord(id,owner.value,"Cards","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,now,now,null,v,device)
        .toCloudRecord().payload.let{JsonObject(it+("future_null" to JsonNull)+("future_marker" to JsonPrimitive("keep")))}
    private fun response(p:JsonObject)=MockResponse().setBody(JsonArray(listOf(p)).toString())
    private fun request(method:String):okhttp3.mockwebserver.RecordedRequest {
        val value=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals(method,value.method);assertEquals("/rest/v1/investment_channels",value.requestUrl!!.encodedPath)
        assertEquals("eq."+owner.value,value.requestUrl!!.queryParameter("user_id"))
        assertEquals("Bearer "+token,value.getHeader("Authorization"));assertEquals("publishable-key",value.getHeader("apikey"))
        return value
    }
    @Test fun ownedLookupUsesCanonicalChannelIdentityAndExactLongRepresentation()=runTest {
        val p=payload();server.enqueue(response(p))
        val record=client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)!!
        assertEquals(version,record.syncVersion);assertEquals(p,record.payload);assertEquals(owner.value,record.ownerUserId)
        val r=request("GET");assertEquals("eq."+id,r.requestUrl!!.queryParameter("id"))
        assertEquals("2",r.requestUrl!!.queryParameter("limit"));assertEquals(1,server.requestCount)
    }
    @Test fun ownedCreateRetainsExplicitNullsOpaqueFieldsAndAllLongDigits()=runTest {
        val p=payload();server.enqueue(response(p))
        val saved=client.createRecord(CloudEntity.INVESTMENT_CHANNEL,token,owner,p)
        assertEquals(version,saved.syncVersion);assertEquals(p,saved.payload)
        val r=request("POST");assertEquals("return=representation",r.getHeader("Prefer"))
        val sent=Json.parseToJsonElement(r.body.readUtf8()).jsonArray.single().jsonObject
        assertEquals("9007199254740993",sent.getValue("sync_version").jsonPrimitive.content)
        assertFalse(sent.getValue("sync_version").jsonPrimitive.isString)
        assertSame(JsonNull,sent["archived_at"]);assertSame(JsonNull,sent["deleted_at"]);assertSame(JsonNull,sent["future_null"])
        assertEquals(JsonPrimitive("keep"),sent["future_marker"])
    }
    @Test fun ownedConditionalUpdateCarriesExactBaseVersionAndIdentityFilters()=runTest {
        val p=payload(version+1);server.enqueue(response(p))
        val saved=client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,version,p)!!
        assertEquals(9007199254740994L,saved.syncVersion)
        val r=request("PATCH");assertEquals("eq."+id,r.requestUrl!!.queryParameter("id"))
        assertEquals("eq.9007199254740993",r.requestUrl!!.queryParameter("sync_version"))
        assertEquals(p,Json.parseToJsonElement(r.body.readUtf8()).jsonObject)
    }
    @Test fun disabledWritesFailBeforeAnyRequestButOwnedReadsStillWork()=runTest {
        enabled.set(false)
        assertTrue(runCatching{client.createRecord(CloudEntity.INVESTMENT_CHANNEL,token,owner,payload())}.isFailure)
        assertTrue(runCatching{client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,version,payload(version+1))}.isFailure)
        assertEquals(0,server.requestCount)
        server.enqueue(MockResponse().setBody("[]"))
        assertNull(client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner));request("GET")
    }
    @Test fun ordinaryWalletsAssetsTradesAndPostingsNeverEnterTheChannelWriter()=runTest {
        for(entity in listOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE,CloudEntity.INVESTMENT_POSTING)) {
            assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
            assertTrue(runCatching{client.createRecord(entity,token,owner,payload())}.isFailure)
            assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,version,payload(version+1))}.isFailure)
        }
        assertEquals(0,server.requestCount)
    }
    @Test fun forgedIdentityAndNoncanonicalIdsNeverProduceAnHttpRequest()=runTest {
        val other="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        for(bad in listOf("../"+id,"abcdefab-abcd-abcd-abcd-abcdefabcdef".uppercase(),"https://example.invalid/"+id))
            assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,bad,token,owner)}.isFailure)
        for(p in listOf(JsonObject(payload()+("user_id" to JsonPrimitive(other))),JsonObject(payload()+("id" to JsonPrimitive(other))))) {
            assertTrue(runCatching{client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,version-1,p)}.isFailure)
        }
        assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,"old-token",owner)}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,UserId(other))}.exceptionOrNull() is CancellationException)
        assertEquals(0,server.requestCount)
    }
    @Test fun foreignOrAmbiguousReturnedRowsCannotBeAcceptedAsAnOwnedChannel()=runTest {
        for(p in listOf(JsonObject(payload()+("user_id" to JsonPrimitive("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))),
            JsonObject(payload()+("id" to JsonPrimitive("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))))) {
            server.enqueue(response(p))
            assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.isFailure)
        }
        server.enqueue(MockResponse().setBody(JsonArray(listOf(payload(),payload())).toString()))
        assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.isFailure)
    }
    @Test fun aConditionalMissReturnsNullWhileAnEmptyCreateReplyIsNeverAnAcknowledgement()=runTest {
        server.enqueue(MockResponse().setBody("[]"))
        assertNull(client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,version,payload(version+1)))
        server.enqueue(MockResponse().setResponseCode(201).setBody("[]"))
        assertTrue(runCatching{client.createRecord(CloudEntity.INVESTMENT_CHANNEL,token,owner,payload())}.isFailure)
        assertEquals(2,server.requestCount)
    }
    @Test fun tombstonePatchIsExactOwnerAndVersionBoundAndCannotCreateADeletedChannel()=runTest {
        val full=JsonObject(payload(version+1)+("deleted_at" to JsonPrimitive(now)))
        val patch=JsonObject(full.filterKeys{it in setOf("id","user_id","updated_at","deleted_at","sync_version","last_modified_by_device_id")})
        server.enqueue(response(full))
        assertEquals(now,client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,version,patch)!!.deletedAt)
        assertEquals(patch,Json.parseToJsonElement(request("PATCH").body.readUtf8()).jsonObject)
        assertTrue(runCatching{client.createRecord(CloudEntity.INVESTMENT_CHANNEL,token,owner,full)}.isFailure)
        assertTrue(runCatching{client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,version,JsonObject(patch+("name" to JsonPrimitive("forged"))))}.isFailure)
        assertEquals(1,server.requestCount)
    }
    @Test fun versionOverflowNonadvancingAndStringVersionsAreRejectedBeforeTheRequest()=runTest {
        for((base,p) in listOf(Long.MAX_VALUE to payload(Long.MAX_VALUE),version to payload(version),version to JsonObject(payload(version+1)+("sync_version" to JsonPrimitive("9007199254740994")))))
            assertTrue(runCatching{client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,base,p)}.isFailure)
        assertEquals(0,server.requestCount)
    }
    @Test fun replacedSessionCannotReturnAPreviousUsersReadOrWriteReply()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            session.set(session.get()!!.copy(accessToken="rotated-token"));return response(payload())
        }}
        assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.exceptionOrNull() is CancellationException)
        assertEquals(1,server.requestCount)
    }
    @Test fun writeGateRevokedDuringResponseCannotAcknowledgeTheOldWrite()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            enabled.set(false);return response(payload())
        }}
        assertTrue(runCatching{client.createRecord(CloudEntity.INVESTMENT_CHANNEL,token,owner,payload())}.exceptionOrNull() is CancellationException)
        assertEquals(1,server.requestCount)
    }
    @Test fun httpFailuresRetainRetryStatusWithoutExposingBodiesOrTokens()=runTest {
        for(status in listOf(400,401,403,409,429,500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("private-body:"+token))
            val error=runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.exceptionOrNull()!!
            assertEquals(status,(error as SupabaseHttpException).statusCode);assertEquals("",error.responseBody)
            assertFalse(error.toString().contains(token));assertFalse(error.toString().contains("private-body"))
        }
    }
    @Test fun malformedPrivateJsonDoesNotEscapeIntoAnErrorMessage()=runTest {
        server.enqueue(MockResponse().setBody("{private-body:"+token))
        val error=runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.exceptionOrNull()!!
        assertFalse(error.toString().contains(token));assertFalse(error.toString().contains("private-body"));assertNull(error.cause)
    }
    @Test fun chunkedResponseIsBoundedAndRedirectCannotForwardTheSession()=runTest {
        server.enqueue(MockResponse().setChunkedBody(Buffer().write(ByteArray(2_000_001)),8192))
        assertTrue(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.isFailure)
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location",server.url("/must-not-follow")))
        assertEquals(302,(runCatching{client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}.exceptionOrNull() as SupabaseHttpException).statusCode)
        assertEquals(2,server.requestCount)
    }

    @Test fun callerCancellationActuallyCancelsThePendingPrivateHttpCall()=runBlocking {
        server.enqueue(response(payload()).setBodyDelay(1,TimeUnit.SECONDS))
        val work=async(Dispatchers.Default){client.fetchRecord(CloudEntity.INVESTMENT_CHANNEL,id,token,owner)}
        assertNotNull(server.takeRequest(2,TimeUnit.SECONDS));assertFalse(work.isCompleted)
        work.cancelAndJoin()
        assertTrue(work.isCancelled)
        assertTrue(calls.single().isCanceled())
    }

    @Test fun localWinnerMayAdvanceFromTheHigherLocalVersionWhileComparingTheRemoteBase()=runTest {
        val p=payload(12)
        server.enqueue(response(p))
        assertEquals(12L,client.conditionalUpdate(CloudEntity.INVESTMENT_CHANNEL,id,token,owner,7,p)!!.syncVersion)
        val r=request("PATCH")
        assertEquals("eq.7",r.requestUrl!!.queryParameter("sync_version"))
        assertEquals(12L,Json.parseToJsonElement(r.body.readUtf8()).jsonObject.financeRawLong("sync_version"))
    }

}
