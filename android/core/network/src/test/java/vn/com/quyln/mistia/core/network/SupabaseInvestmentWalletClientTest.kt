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

class SupabaseInvestmentWalletClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id=investmentSystemWalletId(owner)
    private val device="33333333-3333-3333-3333-333333333333"
    private val token="investment-wallet-access-token"
    private val now="2026-10-24T00:00:00Z"
    private val version=9007199254740993L
    private lateinit var server:MockWebServer
    private lateinit var http:OkHttpClient
    private lateinit var client:SupabaseInvestmentWalletClient
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private val calls=java.util.Collections.synchronizedList(mutableListOf<okhttp3.Call>())
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).eventListener(object:okhttp3.EventListener(){override fun callStart(call:okhttp3.Call){calls.add(call)}}).build()
        client=SupabaseInvestmentWalletClient(SupabaseConfig(server.url("/").toString(),"publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private val entity=CloudEntity.LEDGER_WALLET
    private fun payload(v:Long=version)=buildJsonObject {
        put("id",id);put("user_id",owner.value);put("name","Investment wallet");put("kind_raw_value","investment")
        put("currency_code","VND");put("opening_balance_minor",0L);put("system_purpose_raw_value","investmentProfit")
        put("investment_linked_wallet_id",JsonNull);put("icon_symbol_name",WalletKind.INVESTMENT.defaultIcon);put("icon_color_hex",WalletKind.INVESTMENT.defaultColorHex)
        put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull);put("sort_order",Int.MAX_VALUE-100)
        put("is_archived",false);put("archived_at",JsonNull);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
        put("sync_version",v);put("last_modified_by_device_id",device);put("future_null",JsonNull);put("future_object",buildJsonObject{put("large",Long.MAX_VALUE)})
    }
    private fun response(p:JsonObject)=MockResponse().setBody(JsonArray(listOf(p)).toString())
    private fun request(method:String):RecordedRequest {
        val r=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals(method,r.method);assertEquals("/rest/v1/ledger_wallets",r.requestUrl!!.encodedPath)
        assertEquals("eq."+owner.value,r.requestUrl!!.queryParameter("user_id"))
        assertEquals("Bearer "+token,r.getHeader("Authorization"));assertEquals("publishable-key",r.getHeader("apikey"))
        return r
    }
    @Test fun ownedCanonicalLookupIsExactAndRetainsTheFullLongRepresentation()=runTest {
        val p=payload();server.enqueue(response(p))
        val row=client.fetchRecord(entity,id,token,owner)!!
        assertEquals(p,row.payload);assertEquals(version,row.syncVersion)
        val r=request("GET");assertEquals("eq."+id,r.requestUrl!!.queryParameter("id"));assertEquals("2",r.requestUrl!!.queryParameter("limit"))
    }
    @Test fun createPreservesZeroOpeningBalanceNullLinkOpaqueValuesAndExactVersions()=runTest {
        val p=payload();server.enqueue(response(p))
        assertEquals(p,client.createRecord(entity,token,owner,p).payload)
        val r=request("POST");assertEquals("return=representation",r.getHeader("Prefer"))
        assertEquals(p,Json.parseToJsonElement(r.body.readUtf8()).jsonArray.single())
        assertSame(JsonNull,p["investment_linked_wallet_id"]);assertSame(JsonNull,p["future_null"])
        assertEquals(9007199254740993L,p.financeRawLong("sync_version"));assertEquals(0L,p.financeRawLong("opening_balance_minor"))
    }
    @Test fun conditionalRootMetadataUsesExactOwnerIdAndBaseAndPreservesExplicitLinkClearing()=runTest {
        for(base in listOf(0L,version)) {
            val p=payload(base+1);server.enqueue(response(p))
            assertEquals(base+1,client.conditionalUpdate(entity,id,token,owner,base,p)!!.syncVersion)
            val r=request("PATCH");assertEquals("eq."+id,r.requestUrl!!.queryParameter("id"))
            assertEquals("eq."+base,r.requestUrl!!.queryParameter("sync_version"))
            val expected=JsonObject(p-setOf("current_balance_minor","opening_balance_minor","currency_code","kind_raw_value","system_purpose_raw_value","created_at"))
            assertEquals(expected,Json.parseToJsonElement(r.body.readUtf8()).jsonObject)
        }
    }
    @Test fun metadataWritesCannotReplaceServerDerivedBalancesOrImmutableRootAuthority()=runTest {
        val p=JsonObject(payload()+("current_balance_minor" to JsonPrimitive(Long.MAX_VALUE)))
        server.enqueue(response(p))
        client.createRecord(entity,token,owner,p)
        val created=Json.parseToJsonElement(request("POST").body.readUtf8()).jsonArray.single().jsonObject
        assertFalse("Derived balance cannot be client-written", "current_balance_minor" in created)
        assertEquals(JsonPrimitive(0L),created["opening_balance_minor"])
        server.enqueue(response(p))
        client.conditionalUpdate(entity,id,token,owner,version-1,p)
        val patched=Json.parseToJsonElement(request("PATCH").body.readUtf8()).jsonObject
        for(key in listOf("current_balance_minor","opening_balance_minor","currency_code","kind_raw_value","system_purpose_raw_value","created_at"))
            assertFalse("Immutable or derived authority cannot enter a metadata PATCH: "+key,key in patched)
        assertSame(JsonNull,patched["investment_linked_wallet_id"])
        assertEquals(JsonPrimitive(9007199254740993L),patched["sync_version"])
        assertSame(JsonNull,patched["future_null"])
        assertEquals(Long.MAX_VALUE,patched.getValue("future_object").jsonObject.financeRawLong("large"))
    }
    @Test fun localRootEvidenceCannotEnterDedicatedOrGenericCloudReads()=runTest {
        val forged=JsonObject(payload()+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to JsonNull))
        server.enqueue(response(forged))
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
        request("GET")
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"publishable-key"),http)
        server.enqueue(response(forged));assertTrue(runCatching{generic.pullPage(entity.table,token,owner,0,100)}.isFailure)
        server.enqueue(response(forged));assertTrue(runCatching{generic.fetchRecord(entity,id,token,owner)}.isFailure)
    }
    @Test fun anOrdinaryWalletCannotLeakLocalRootEvidenceThroughTheGenericWriter()=runTest {
        val ordinary=JsonObject(payload()+buildJsonObject{put("id","aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");put("kind_raw_value","cash");put("system_purpose_raw_value",JsonNull)})
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"publishable-key"),http,writableEntities=setOf(entity))
        server.enqueue(response(ordinary))
        assertTrue(runCatching{generic.createRecord(entity,token,owner,JsonObject(ordinary+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to JsonNull)))}.isFailure)
        assertEquals(0,server.requestCount)
    }
    @Test fun writeRepliesCannotChangeTheSubmittedAccountingCurrencyOrVersion()=runTest {
        val proposed=payload()
        for(reply in listOf(JsonObject(proposed+("currency_code" to JsonPrimitive("JPY"))),payload(version+1))) {
            server.enqueue(response(reply));assertTrue(runCatching{client.createRecord(entity,token,owner,proposed)}.isFailure)
            server.enqueue(response(reply));assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,version-1,proposed)}.isFailure)
        }
    }
    @Test fun rootGateIsIndependentOfOrdinaryWalletWritesAndReadsRemainPossibleWhenDisabled()=runTest {
        enabled.set(false)
        assertTrue(runCatching{client.createRecord(entity,token,owner,payload())}.isFailure)
        assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,version,payload(version+1))}.isFailure)
        assertEquals(0,server.requestCount)
        server.enqueue(response(payload()));assertNotNull(client.fetchRecord(entity,id,token,owner));request("GET")
    }
    @Test fun ordinaryAndArbitraryInvestmentWalletsCannotBorrowTheCanonicalPort()=runTest {
        val other="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        for(p in listOf(JsonObject(payload()+("kind_raw_value" to JsonPrimitive("cash"))),
            JsonObject(payload()+("system_purpose_raw_value" to JsonNull)),JsonObject(payload()+("id" to JsonPrimitive(other))),
            JsonObject(payload()+("user_id" to JsonPrimitive(other))),JsonObject(payload()+("opening_balance_minor" to JsonPrimitive(1L))))) {
            assertTrue(runCatching{client.createRecord(entity,token,owner,p)}.isFailure)
            assertTrue(runCatching{client.conditionalUpdate(entity,p.financeRawString("id")!!,token,owner,version-1,p)}.isFailure)
        }
        assertTrue(runCatching{client.fetchRecord(entity,other,token,owner)}.isFailure)
        assertEquals(0,server.requestCount)
    }
    @Test fun otherMetadataAndFinancialEntitiesNeverEnterThisWalletPort()=runTest {
        for(other in listOf(CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_TRADE,CloudEntity.INVESTMENT_POSTING,CloudEntity.LEDGER_TRANSACTION)) {
            assertTrue(runCatching{client.fetchRecord(other,id,token,owner)}.isFailure)
            assertTrue(runCatching{client.createRecord(other,token,owner,payload())}.isFailure)
            assertTrue(runCatching{client.conditionalUpdate(other,id,token,owner,version,payload(version+1))}.isFailure)
        }
        assertEquals(0,server.requestCount)
    }
    @Test fun aRemoteCanonicalArchiveOrTombstoneCanBeReadButCannotBeSentAsALocalMutation()=runTest {
        for(p in listOf(JsonObject(payload()+("deleted_at" to JsonPrimitive(now))),
            JsonObject(payload()+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(now))))) {
            server.enqueue(response(p));assertNotNull(client.fetchRecord(entity,id,token,owner))
            assertTrue(runCatching{client.createRecord(entity,token,owner,p)}.isFailure)
            assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,version-1,p)}.isFailure)
        }
        assertEquals(2,server.requestCount)
    }
    @Test fun conditionalMissAndAnEmptyCreateReplyNeverBecomeAnAcknowledgement()=runTest {
        server.enqueue(MockResponse().setBody("[]"));assertNull(client.conditionalUpdate(entity,id,token,owner,version,payload(version+1)))
        server.enqueue(MockResponse().setBody("[]"))
        assertTrue(runCatching{client.createRecord(entity,token,owner,payload(1))}.exceptionOrNull() is java.io.IOException)
    }
    @Test fun mismatchedForeignDuplicateAndMoneyBearingRepliesAreHeld()=runTest {
        for(p in listOf(JsonObject(payload()+("user_id" to JsonPrimitive("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))),
            JsonObject(payload()+("opening_balance_minor" to JsonPrimitive(1L))),JsonObject(payload()+("kind_raw_value" to JsonPrimitive("cash"))))) {
            server.enqueue(response(p));assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
        }
        server.enqueue(MockResponse().setBody(JsonArray(listOf(payload(),payload())).toString()))
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
    }
    @Test fun versionOverflowStringOrNonadvancingValuesAreRejectedBeforeHttp()=runTest {
        for((base,p) in listOf(Long.MAX_VALUE to payload(Long.MAX_VALUE),version to payload(version),version to JsonObject(payload(version+1)+("sync_version" to JsonPrimitive("9007199254740994")))))
            assertTrue(runCatching{client.conditionalUpdate(entity,id,token,owner,base,p)}.isFailure)
        assertEquals(0,server.requestCount)
    }
    @Test fun exactSessionRotationAndGateRevocationFenceReadAndWriteReplies()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {enabled.set(false);return response(payload())}}
        assertTrue(runCatching{client.createRecord(entity,token,owner,payload())}.exceptionOrNull() is CancellationException)
        enabled.set(true)
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {session.set(session.get()!!.copy(accessToken="rotated"));return response(payload())}}
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.exceptionOrNull() is CancellationException)
    }
    @Test fun httpStatusesAndMalformedBodiesNeverExposePrivateValues()=runTest {
        for(status in listOf(400,401,403,409,429,500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("private-body:"+token))
            val error=runCatching{client.createRecord(entity,token,owner,payload())}.exceptionOrNull() as SupabaseHttpException
            assertEquals(status,error.statusCode);assertEquals("",error.responseBody);assertFalse(error.toString().contains(token))
        }
        server.enqueue(MockResponse().setBody("private-body:"+token))
        val invalid=runCatching{client.fetchRecord(entity,id,token,owner)}.exceptionOrNull()!!
        assertFalse(invalid.toString().contains(token));assertFalse(invalid.toString().contains("private-body"));assertNull(invalid.cause)
    }
    @Test fun boundedBodyAndRedirectDenialProtectThePrivateWalletSession()=runTest {
        server.enqueue(MockResponse().setChunkedBody(Buffer().write(ByteArray(2_000_001)),8192))
        assertTrue(runCatching{client.fetchRecord(entity,id,token,owner)}.isFailure)
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location",server.url("/must-not-follow")))
        assertEquals(302,(runCatching{client.createRecord(entity,token,owner,payload())}.exceptionOrNull() as SupabaseHttpException).statusCode)
        assertEquals(2,server.requestCount)
    }
    @Test fun cancellingTheCallerCancelsItsActualPendingCanonicalWalletRequest()=runBlocking {
        server.enqueue(response(payload()).setBodyDelay(1,TimeUnit.SECONDS))
        val work=async(Dispatchers.Default){client.createRecord(entity,token,owner,payload())}
        assertNotNull(server.takeRequest(2,TimeUnit.SECONDS));assertFalse(work.isCompleted)
        work.cancelAndJoin();assertTrue(work.isCancelled);assertTrue(calls.single().isCanceled())
    }
}
