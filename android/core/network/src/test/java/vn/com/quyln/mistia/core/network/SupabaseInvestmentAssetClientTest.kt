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

class SupabaseInvestmentAssetClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val token="asset-access-token"
    private val now="2026-10-24T00:00:00Z"
    private val version=9007199254740993L
    private lateinit var server:MockWebServer
    private lateinit var http:OkHttpClient
    private lateinit var client:SupabaseInvestmentAssetClient
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private val calls=java.util.Collections.synchronizedList(mutableListOf<okhttp3.Call>())
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).eventListener(object:okhttp3.EventListener(){override fun callStart(call:okhttp3.Call){calls.add(call)}}).build()
        client=SupabaseInvestmentAssetClient(SupabaseConfig(server.url("/").toString(),"publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private val entity=CloudEntity.INVESTMENT_ASSET
    private val channel="44444444-4444-4444-4444-444444444444"
    private fun payload(v:Long=version)=InvestmentAssetRecord(id,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,v,device)
        .toCloudRecord().payload.let{JsonObject(it+("future_null" to JsonNull)+("future_marker" to JsonPrimitive("keep")))}
    private fun response(p:JsonObject)=MockResponse().setBody(JsonArray(listOf(p)).toString())
    private fun rpc(function:String):JsonObject {
        val r=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals("POST",r.method);assertEquals("/rest/v1/rpc/"+function,r.requestUrl!!.encodedPath)
        assertNull(r.requestUrl!!.query);assertEquals("Bearer "+token,r.getHeader("Authorization"))
        assertEquals("publishable-key",r.getHeader("apikey"))
        return Json.parseToJsonElement(r.body.readUtf8()).jsonObject
    }
    @Test fun ownedLookupPreservesLongNullAndOpaqueFieldsAndPinsExactOwnerAndIdentity()=runTest {
        val p=payload();server.enqueue(response(p))
        val result=client.fetchRecord(entity,id,token,owner)!!
        assertEquals(p,result.payload);assertEquals(version,result.syncVersion)
        val r=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals("GET",r.method);assertEquals("/rest/v1/investment_assets",r.requestUrl!!.encodedPath)
        assertEquals("eq."+id,r.requestUrl!!.queryParameter("id"));assertEquals("eq."+owner.value,r.requestUrl!!.queryParameter("user_id"))
        assertEquals("2",r.requestUrl!!.queryParameter("limit"))
    }
    @Test fun createUsesAtomicRpcExpectedZeroAndNeverForcesARacedExistingAsset()=runTest {
        val p=payload(1);server.enqueue(response(p))
        assertEquals(p,client.createRecord(entity,token,owner,p).payload)
        val body=rpc("mutate_investment_asset")
        assertEquals(p,body["p_asset"]);assertEquals(JsonPrimitive(0),body["p_expected_version"])
        assertEquals(JsonPrimitive(false),body["p_force"]);assertEquals(3,body.size)
    }
    @Test fun conditionalRpcUsesExactLongBaseIncludingLegacyZeroAndServerVersionAuthority()=runTest {
        for(base in listOf(0L,version)) {
            val p=payload(base+1);server.enqueue(response(p))
            assertEquals(base+1,client.conditionalUpdate(entity,id,token,owner,base,p)!!.syncVersion)
            val body=rpc("mutate_investment_asset")
            assertEquals(JsonPrimitive(base),body["p_expected_version"]);assertEquals(JsonPrimitive(false),body["p_force"])
            assertEquals(p,body["p_asset"])
        }
    }
    @Test fun conditionalMissReturnsNullAndCreateMissSignalsConflictForARefetch()=runTest {
        server.enqueue(MockResponse().setBody("[]"));assertNull(client.conditionalUpdate(entity,id,token,owner,version,payload(version+1)))
        server.enqueue(MockResponse().setBody("[]"))
        assertEquals(409,(runCatching{client.createRecord(entity,token,owner,payload(1))}.exceptionOrNull() as SupabaseHttpException).statusCode)
        assertEquals(2,server.requestCount)
    }
    @Test fun causalEvidenceIsStrippedOnWriteAndRejectedOnEveryCloudIngress()=runTest {
        val row=CloudRecord(entity.table,id,owner.value,payload(),now,null,version)
        val parent=InvestmentAssetPublicationParent(version,null,device,false,investmentAssetPublicationFingerprint(row.payload),investmentAssetPublicationFingerprint(row.payload,true))
        val local=JsonObject(row.withAssetPublicationParent(parent).payload+("sync_version" to JsonPrimitive(version+1)))
        server.enqueue(response(payload(version+1)))
        client.conditionalUpdate(entity,id,token,owner,version,local)
        val sent=rpc("mutate_investment_asset").getValue("p_asset").jsonObject
        assertTrue(LOCAL_ASSET_PUBLICATION_KEYS.none{it in sent})
        val forged=JsonObject(payload()+(LOCAL_ASSET_PUBLICATION_PARENTS_KEY to JsonNull))
        server.enqueue(response(forged))
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
        server.takeRequest(1,TimeUnit.SECONDS)
        val gateway=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"publishable-key"),http)
        server.enqueue(response(forged))
        assertTrue(runCatching{gateway.pullPage(entity.table,token,owner,0,100)}.isFailure)
    }
    @Test fun localImageIntentNeverBecomesARpcColumnAndServerCannotInjectPrivateProvenance()=runTest {
        val marker=buildJsonObject {
            put("version",1);put("owner_user_id",owner.value);put("asset_id",id);put("revision","55555555-5555-5555-5555-555555555555")
            put("previous_path",JsonNull);put("candidate",JsonNull)
        }
        val local=JsonObject(payload()+(LOCAL_ASSET_IMAGE_INTENT_KEY to marker))
        server.enqueue(response(payload()))
        client.conditionalUpdate(entity,id,token,owner,version-1,local)
        assertEquals(payload(),rpc("mutate_investment_asset")["p_asset"])
        server.enqueue(response(local));assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
        val bad=JsonObject(payload()+(LOCAL_ASSET_IMAGE_INTENT_KEY to JsonNull))
        assertTrue(runCatching{client.createRecord(entity,token,owner,bad)}.isFailure);assertEquals(2,server.requestCount)
    }
    @Test fun deletionUsesOnlyTheClosedVersionBoundDeleteRpcAndCannotCreateATombstone()=runTest {
        val full=JsonObject(payload(version+1)+("deleted_at" to JsonPrimitive(now)))
        val patch=JsonObject(full.filterKeys{it in setOf("id","user_id","updated_at","deleted_at","sync_version","last_modified_by_device_id")})
        server.enqueue(response(full))
        assertEquals(now,client.conditionalUpdate(entity,id,token,owner,version,patch)!!.deletedAt)
        assertEquals(buildJsonObject{put("p_asset_id",id);put("p_owner_user_id",owner.value);put("p_expected_version",version);put("p_modified_at",now);put("p_device_id",device)},rpc("delete_investment_asset"))
        assertTrue(runCatching{client.createRecord(entity,token,owner,full)}.isFailure)
        assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,version,JsonObject(patch+("name" to JsonPrimitive("forged"))))}.isFailure)
        assertEquals(1,server.requestCount)
    }
    @Test fun disabledGatePreventsEveryWriteButAllowsOwnedReads()=runTest {
        enabled.set(false)
        assertTrue(runCatching{client.createRecord(entity,token,owner,payload())}.isFailure)
        assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,version,payload(version+1))}.isFailure)
        assertEquals(0,server.requestCount)
        server.enqueue(MockResponse().setBody("[]"));assertNull(client.fetchRecord(entity,id,token,owner))
    }
    @Test fun otherDomainsForeignIdentityInvalidVersionsAndStaleSessionsNeverSendRequests()=runTest {
        for(other in listOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_TRADE,CloudEntity.INVESTMENT_POSTING)) {
            assertTrue(runCatching{client.fetchRecord(other,id,token,owner)}.isFailure)
            assertTrue(runCatching{client.createRecord(other,token,owner,payload())}.isFailure)
            assertTrue(runCatching{client.conditionalUpdate(other,id,token,owner,version,payload(version+1))}.isFailure)
        }
        for(p in listOf(JsonObject(payload()+("user_id" to JsonPrimitive(channel))),JsonObject(payload()+("sync_version" to JsonPrimitive("9007199254740993")))))
            assertTrue(runCatching{client.createRecord(entity,token,owner,p)}.isFailure)
        assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,Long.MAX_VALUE,payload())}.isFailure)
        assertTrue(runCatching{client.fetchRecord(entity,"../"+id,token,owner)}.isFailure)
        assertTrue(runCatching{client.fetchRecord(entity,id,"old-token",owner)}.exceptionOrNull() is CancellationException)
        assertEquals(0,server.requestCount)
    }
    @Test fun duplicateForeignAndMalformedRepliesAreRejectedWithoutPrivateErrorDetails()=runTest {
        for(body in listOf(JsonArray(listOf(payload(),payload())).toString(),JsonArray(listOf(JsonObject(payload()+("user_id" to JsonPrimitive(channel))))).toString(),"private-body:"+token)) {
            server.enqueue(MockResponse().setBody(body))
            val error=runCatching{client.fetchRecord(entity,id,token,owner)}.exceptionOrNull()!!
            assertFalse(error.toString().contains("private-body"));assertFalse(error.toString().contains(token));assertNull(error.cause)
        }
    }
    @Test fun sessionOrGateRevokedDuringTheRpcCannotAcknowledgeItsReply()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            enabled.set(false);return response(payload())
        }}
        assertTrue(runCatching{client.createRecord(entity,token,owner,payload())}.exceptionOrNull() is CancellationException)
        enabled.set(true)
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            session.set(session.get()!!.copy(accessToken="rotated"));return response(payload())
        }}
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.exceptionOrNull() is CancellationException)
    }
    @Test fun httpFailuresPreserveRetryStatusButNeverPrivateBodyOrSession()=runTest {
        for(status in listOf(400,401,403,409,429,500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("private-body:"+token))
            val error=runCatching{client.createRecord(entity,token,owner,payload())}.exceptionOrNull() as SupabaseHttpException
            assertEquals(status,error.statusCode);assertEquals("",error.responseBody)
            assertFalse(error.toString().contains(token));assertFalse(error.toString().contains("private-body"))
        }
    }
    @Test fun bodyLimitsAndRedirectDenialApplyToRpcAndReadResponses()=runTest {
        server.enqueue(MockResponse().setChunkedBody(Buffer().write(ByteArray(2_000_001)),8192))
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location",server.url("/must-not-follow")))
        assertEquals(302,(runCatching{client.createRecord(entity,token,owner,payload())}.exceptionOrNull() as SupabaseHttpException).statusCode)
        assertEquals(2,server.requestCount)
    }
    @Test fun callerCancellationCancelsTheActualPrivateRpcCall()=runBlocking {
        server.enqueue(response(payload()).setBodyDelay(1,TimeUnit.SECONDS))
        val work=async(Dispatchers.Default){client.createRecord(entity,token,owner,payload())}
        assertNotNull(server.takeRequest(2,TimeUnit.SECONDS));assertFalse(work.isCompleted)
        work.cancelAndJoin();assertTrue(work.isCancelled);assertTrue(calls.single().isCanceled())
    }
    @Test fun genericPullAlsoRefusesServerInjectionOfPrivateImageIntent()=runTest {
        val raw=JsonObject(payload()+(LOCAL_ASSET_IMAGE_INTENT_KEY to buildJsonObject{put("version",1)}))
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"publishable-key"),http)
        server.enqueue(response(raw))
        assertTrue(runCatching{generic.pullPage(entity.table,token,owner,0,100)}.isFailure)
        server.enqueue(response(raw))
        assertTrue(runCatching{generic.fetchRecord(entity,id,token,owner)}.isFailure)
        assertEquals(2,server.requestCount)
    }

    @Test fun emptySuccessfulRpcResponseIsAnUncertainRetryableReply()=runTest {
        server.enqueue(MockResponse().setBody(""))
        val error=runCatching{client.createRecord(entity,token,owner,payload(1))}.exceptionOrNull()
        assertTrue(error is java.io.IOException);assertFalse(error is SupabaseHttpException)
        assertFalse(error.toString().contains(token));assertNull(error!!.cause)
    }

}
