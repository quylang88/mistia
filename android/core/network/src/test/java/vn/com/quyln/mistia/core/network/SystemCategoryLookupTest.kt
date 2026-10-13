package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class SystemCategoryLookupTest {
    private lateinit var server: MockWebServer
    private lateinit var store: SupabasePostgrestRemoteStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val otherId="33333333-3333-3333-3333-333333333333"
    private val version=9_007_199_254_740_993L

    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply {useHttps(serverCertificates.sslSocketFactory(),false);start()}
        store=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString().removeSuffix("/"),"test-key"),
            OkHttpClient.Builder().sslSocketFactory(clientCertificates.sslSocketFactory(),clientCertificates.trustManager).build())
    }
    @After fun teardown() {server.shutdown()}

    @Test fun `read works with all writes disabled and scopes key system owner range`()=runTest {
        server.enqueue(response("[${payload()}]","20-20/21"))
        val page=store.fetchSystemCategoryPage("rent","token",owner,20,10)
        val records=page.records
        assertNull(page.nextOffset)
        assertEquals(id,records.single().id)
        assertEquals(version,records.single().syncVersion)
        assertEquals(JsonNull,records.single().payload["name_japanese"])
        val request=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals("GET",request.method)
        assertEquals("/rest/v1/transaction_categories",request.requestUrl!!.encodedPath)
        assertEquals("eq.${owner.value}",request.requestUrl!!.queryParameter("user_id"))
        assertEquals("eq.rent",request.requestUrl!!.queryParameter("system_key"))
        assertEquals("eq.true",request.requestUrl!!.queryParameter("is_system"))
        assertEquals("id.asc",request.requestUrl!!.queryParameter("order"))
        assertNull(request.requestUrl!!.queryParameter("id"))
        assertNull(request.requestUrl!!.queryParameter("deleted_at"))
        assertEquals("20-29",request.getHeader("Range"))
        assertEquals("items",request.getHeader("Range-Unit"))
        assertEquals("count=exact",request.getHeader("Prefer"))
        assertEquals("Bearer token",request.getHeader("Authorization"))
        assertEquals("test-key",request.getHeader("apikey"))
    }
    @Test fun `page retains duplicate key IDs and tombstones for reconciliation`()=runTest {
        val first=payload()
        val tombstone=JsonObject(first+mapOf("id" to JsonPrimitive(otherId),"deleted_at" to JsonPrimitive("2026-10-13T00:00:00Z")))
        server.enqueue(response("[$first,$tombstone]","0-1/2"))
        val records=store.fetchSystemCategoryPage("rent","token",owner,0,1000).records
        assertEquals(listOf(id,otherId),records.map {it.id})
        assertEquals("2026-10-13T00:00:00Z",records.last().deletedAt)
        assertEquals(tombstone,records.last().payload)
    }
    @Test fun `empty page is an empty result`()=runTest {
        server.enqueue(response("[]","*/0"))
        assertTrue(store.fetchSystemCategoryPage("rent","token",owner,0,1000).records.isEmpty())
    }
    @Test fun `foreign owner wrong key and custom category responses are rejected`()=runTest {
        listOf("user_id" to JsonPrimitive(otherId),"system_key" to JsonPrimitive("internet"),"is_system" to JsonPrimitive(false)).forEach { (key,value) ->
            server.enqueue(response("[${JsonObject(payload()+ (key to value))}]"))
            assertTrue(runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1000)}.isFailure)
        }
    }
    @Test fun `malformed page cannot silently drop reconciliation rows`()=runTest {
        listOf("", "{}", "[null]", "[1]", "[$id]", "[${payload()},null]").forEach { body ->
            server.enqueue(response(body))
            assertTrue("body=$body",runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1000)}.isFailure)
        }
    }
    @Test fun `invalid range key owner and token fail before network`()=runTest {
        val requests=listOf(
            suspend {store.fetchSystemCategoryPage("rent","token",owner,-1,10)},
            suspend {store.fetchSystemCategoryPage("rent","token",owner,0,0)},
            suspend {store.fetchSystemCategoryPage("rent","token",owner,0,1001)},
            suspend {store.fetchSystemCategoryPage("rent","token",owner,Int.MAX_VALUE,1000)},
            suspend {store.fetchSystemCategoryPage("rent,or(x)","token",owner,0,10)},
            suspend {store.fetchSystemCategoryPage("","token",owner,0,10)},
            suspend {store.fetchSystemCategoryPage("rent","token",UserId("invalid"),0,10)},
            suspend {store.fetchSystemCategoryPage("rent","",owner,0,10)},
        )
        requests.forEach {assertTrue(runCatching {it()}.isFailure)}
        assertEquals(0,server.requestCount)
    }
    @Test fun `invalid version and overfull page fail closed`()=runTest {
        listOf(JsonPrimitive("bad"),JsonPrimitive(-1),JsonPrimitive("9007199254740993"),JsonNull).forEach { value ->
            server.enqueue(response("[${JsonObject(payload()+ ("sync_version" to value))}]"))
            assertTrue(runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1000)}.isFailure)
        }
        server.enqueue(response("[${payload()},${payload()}]"))
        assertTrue(runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1)}.isFailure)
    }
    @Test fun `HTTP failure is retained for coordinator retry classification`()=runTest {
        server.enqueue(MockResponse().setResponseCode(503).setBody("unavailable"))
        val failure=runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1000)}.exceptionOrNull()
        assertTrue(failure is SupabaseHttpException)
        assertEquals(503,(failure as SupabaseHttpException).statusCode)
    }
    @Test fun `server cap smaller than requested page still returns explicit continuation`()=runTest {
        server.enqueue(response("[${payload()}]","0-0/2"))
        val first=store.fetchSystemCategoryPage("rent","token",owner,0,1000)
        assertEquals(1,first.nextOffset)
        server.enqueue(response("[${payload()}]","1-1/2"))
        val second=store.fetchSystemCategoryPage("rent","token",owner,first.nextOffset!!,1000)
        assertNull(second.nextOffset)
    }
    @Test fun `missing inconsistent or unknown exact range cannot imply complete lookup`()=runTest {
        listOf(null,"0-0/*","0-0/0","1-1/2","0-1/2","0-0/999999999999999999").forEach { range ->
            val response=MockResponse().setBody("[${payload()}]")
            if(range!=null) response.setHeader("Content-Range",range)
            server.enqueue(response)
            assertTrue(runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1000)}.isFailure)
        }
        server.enqueue(response("[]","*/1"))
        assertTrue(runCatching {store.fetchSystemCategoryPage("rent","token",owner,0,1000)}.isFailure)
    }
    private fun response(body:String,range:String="0-0/1")=MockResponse().setHeader("Content-Range",range).setBody(body)
    private fun payload()=JsonObject(mapOf(
        "id" to JsonPrimitive(id),"user_id" to JsonPrimitive(owner.value),"system_key" to JsonPrimitive("rent"),
        "is_system" to JsonPrimitive(true),"sync_version" to JsonPrimitive(version),
        "name" to JsonPrimitive("Custom rent"),"name_japanese" to JsonNull,"kind_raw_value" to JsonPrimitive("expense"),
        "hierarchy_role_raw_value" to JsonPrimitive("child"),"parent_category_id" to JsonPrimitive(otherId),
        "created_at" to JsonPrimitive("2026-10-01T00:00:00Z"),"updated_at" to JsonPrimitive("2026-10-13T00:00:00Z"),"deleted_at" to JsonNull,
    ))
}
