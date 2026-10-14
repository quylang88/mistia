package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class TransactionDeletePostgrestTest {
    private lateinit var server:MockWebServer
    private lateinit var client:OkHttpClient
    private lateinit var config:SupabaseConfig
    private lateinit var store:SupabasePostgrestRemoteStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-14T00:00:00Z"
    private val version=9007199254740993L
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val tls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val trust=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply {useHttps(tls.sslSocketFactory(),false);start()}
        client=OkHttpClient.Builder().sslSocketFactory(trust.sslSocketFactory(),trust.trustManager).build()
        config=SupabaseConfig(server.url("/").toString().removeSuffix("/"),"test-publishable")
        store=SupabasePostgrestRemoteStore(config,client,writableEntities=setOf(CloudEntity.LEDGER_TRANSACTION))
    }
    @After fun close()=server.shutdown()
    private fun patch()=buildJsonObject {
        put("id",id);put("user_id",owner.value);put("updated_at",now);put("deleted_at",now)
        put("sync_version",version+1);put("last_modified_by_device_id",device);put("last_modified_by_user_id",owner.value)
    }
    private fun returned(ownerValue:String=owner.value)=JsonObject(patch()+mapOf("user_id" to JsonPrimitive(ownerValue),
        "amount_minor" to JsonPrimitive(version),"category_id" to JsonNull,"reporting_amount_minor" to JsonNull,
        "future_wire_field" to JsonPrimitive("retained")))
    @Test fun `HTTPS delete patch scopes id owner and exact version without rewriting money fields`()=runTest {
        val response=returned()
        server.enqueue(MockResponse().setBody("[$response]"))
        val row=store.conditionalUpdate(CloudEntity.LEDGER_TRANSACTION,id,"token",owner,version,patch())!!
        val request=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals("PATCH",request.method)
        assertEquals("/rest/v1/ledger_transactions",request.requestUrl!!.encodedPath)
        assertEquals("eq.$id",request.requestUrl!!.queryParameter("id"))
        assertEquals("eq.${owner.value}",request.requestUrl!!.queryParameter("user_id"))
        assertEquals("eq.$version",request.requestUrl!!.queryParameter("sync_version"))
        assertEquals("return=representation",request.headers["Prefer"])
        val body=Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals(patch(),body)
        assertFalse("amount_minor" in body);assertFalse("category_id" in body)
        assertEquals(version+1,row.syncVersion);assertEquals(response,row.payload)
    }
    @Test fun `gate off prevents transaction delete HTTPS request`()=runTest {
        val disabled=SupabasePostgrestRemoteStore(config,client)
        try {disabled.conditionalUpdate(CloudEntity.LEDGER_TRANSACTION,id,"token",owner,version,patch());fail("Gate bypass")}
        catch (_:IllegalStateException) { }
        assertEquals(0,server.requestCount)
    }
    @Test fun `conditional race returns null and foreign owner response cannot be acknowledged`()=runTest {
        server.enqueue(MockResponse().setBody("[]"))
        assertNull(store.conditionalUpdate(CloudEntity.LEDGER_TRANSACTION,id,"token",owner,version,patch()))
        server.enqueue(MockResponse().setBody("[${returned(device)}]"))
        try {store.conditionalUpdate(CloudEntity.LEDGER_TRANSACTION,id,"token",owner,version,patch());fail("Foreign response accepted")}
        catch (_:IllegalArgumentException) { }
        assertEquals(2,server.requestCount)
    }
}
