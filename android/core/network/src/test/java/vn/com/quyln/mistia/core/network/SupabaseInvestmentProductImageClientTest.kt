package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.AuthSession
import vn.com.quyln.mistia.core.model.InvestmentProductImagePath
import vn.com.quyln.mistia.core.model.UserId

class SupabaseInvestmentProductImageClientTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val otherOwner = UserId("22222222-2222-2222-2222-222222222222")
    private val assetId = "33333333-3333-3333-3333-333333333333"
    private val objectId = "44444444-4444-4444-4444-444444444444"
    private val path = InvestmentProductImagePath.create(owner, assetId, objectId).value
    private val jpeg = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 3, 7, 0xff.toByte(), 0xd9.toByte())
    private val session = AtomicReference<AuthSession?>()
    private val writeGate = AtomicBoolean(true)
    private val callerCurrent = AtomicBoolean(true)
    private lateinit var server: MockWebServer
    private lateinit var httpClient: OkHttpClient
    private lateinit var client: SupabaseInvestmentProductImageClient

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
        }
        httpClient = OkHttpClient.Builder().sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager).build()
        session.set(authSession(owner))
        client = newClient()
    }

    @After
    fun tearDown() = server.shutdown()

    @Test fun `chunked private response larger than the bucket ceiling is rejected safely`() = runTest {
        server.enqueue(MockResponse().setChunkedBody(Buffer().write(ByteArray(5_242_881)),8192))
        val result=client.download(owner,assetId,path)
        assertTrue(result.isFailure);assertSafeFailure(result)
    }

    @Test
    fun `download uses only authenticated private object route and binary bytes`() = runTest {
        server.enqueue(binaryResponse())
        assertArrayEquals(jpeg, client.download(owner, assetId, path).getOrThrow())
        assertPrivateRequest("GET")
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `download 404 is missing but unauthorized and upstream errors fail`() = runTest {
        server.enqueue(MockResponse().setResponseCode(404))
        assertNull(client.download(owner, assetId, path).getOrThrow())
        for (status in listOf(400, 401, 403, 409, 500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("private-error-detail"))
            val result = client.download(owner, assetId, path)
            assertTrue("HTTP $status must fail", result.isFailure)
            assertSafeFailure(result)
        }
    }

    @Test
    fun `upload posts JPEG without replacing immutable object`() = runTest {
        server.enqueue(MockResponse().setResponseCode(201))
        client.upload(owner, assetId, path, jpeg).getOrThrow()
        val request = assertPrivateRequest("POST")
        assertEquals("image/jpeg", request.getHeader("Content-Type"))
        assertEquals("false", request.getHeader("x-upsert"))
        assertArrayEquals(jpeg, request.body.readByteArray())
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `only 400 and 409 upload collisions can succeed after matching private GET`() = runTest {
        for (status in listOf(400, 409)) {
            server.enqueue(MockResponse().setResponseCode(status))
            server.enqueue(binaryResponse())
            client.upload(owner, assetId, path, jpeg).getOrThrow()
            assertPrivateRequest("POST")
            assertPrivateRequest("GET")
        }
        assertEquals(4, server.requestCount)
    }

    @Test
    fun `collision never acknowledges different remote bytes or missing remote object`() = runTest {
        for (probe in listOf(binaryResponse(byteArrayOf(8, 9)), MockResponse().setResponseCode(404), MockResponse().setResponseCode(403))) {
            server.enqueue(MockResponse().setResponseCode(409))
            server.enqueue(probe)
            assertTrue(client.upload(owner, assetId, path, jpeg).isFailure)
            assertPrivateRequest("POST")
            assertPrivateRequest("GET")
        }
    }

    @Test
    fun `other upload errors fail without probing object`() = runTest {
        for (status in listOf(401, 403, 413, 422, 500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("private-error-detail"))
            val result = client.upload(owner, assetId, path, jpeg)
            assertTrue(result.isFailure)
            assertSafeFailure(result)
            assertPrivateRequest("POST")
        }
        assertEquals(5, server.requestCount)
    }

    @Test
    fun `delete is idempotent for success and 404`() = runTest {
        for (status in listOf(200, 204, 404)) {
            server.enqueue(MockResponse().setResponseCode(status))
            client.delete(owner, assetId, path).getOrThrow()
            assertPrivateRequest("DELETE")
        }
    }

    @Test
    fun `delete unauthorized and upstream errors fail`() = runTest {
        for (status in listOf(400, 401, 403, 409, 500)) {
            server.enqueue(MockResponse().setResponseCode(status).setBody("private-error-detail"))
            val result = client.delete(owner, assetId, path)
            assertTrue(result.isFailure)
            assertSafeFailure(result)
        }
        assertEquals(5, server.requestCount)
    }

    @Test
    fun `each disabled write gate blocks upload and delete before any HTTP`() = runTest {
        for ((global, investment) in listOf(false to false, false to true, true to false)) {
            val gatedClient = newClient(writesEnabled = { global && investment })
            assertTrue(gatedClient.upload(owner, assetId, path, jpeg).isFailure)
            assertTrue(gatedClient.delete(owner, assetId, path).isFailure)
        }
        assertEquals(0, server.requestCount)
        // Reads do not require write capability.
        server.enqueue(binaryResponse())
        assertArrayEquals(jpeg, newClient(writesEnabled = { false }).download(owner, assetId, path).getOrThrow())
        assertPrivateRequest("GET")
    }

    @Test
    fun `invalid owner asset and path fail before any HTTP for all operations`() = runTest {
        val unsafePaths = listOf("https://private.invalid/$path", "$path?token=secret", "../$path", path.uppercase(), "$path/extra", path.replace(".jpg", ".png"))
        for (unsafe in unsafePaths) {
            assertTrue(client.download(owner, assetId, unsafe).isFailure)
            assertTrue(client.upload(owner, assetId, unsafe, jpeg).isFailure)
            assertTrue(client.delete(owner, assetId, unsafe).isFailure)
        }
        assertTrue(client.download(otherOwner, assetId, path).isFailure)
        assertTrue(client.upload(owner, "55555555-5555-5555-5555-555555555555", path, jpeg).isFailure)
        assertTrue(client.delete(owner, "not-an-asset", path).isFailure)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `missing blank and mismatched sessions cannot access private objects`() = runTest {
        for (invalid in listOf(null, authSession(otherOwner), authSession(owner).copy(accessToken = ""))) {
            session.set(invalid)
            assertTrue(client.download(owner, assetId, path).isFailure)
            assertTrue(client.upload(owner, assetId, path, jpeg).isFailure)
            assertTrue(client.delete(owner, assetId, path).isFailure)
        }
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `unconfigured client cannot make any storage request`() = runTest {
        val unconfigured = newClient(config = SupabaseConfig("", ""))
        assertTrue(unconfigured.download(owner, assetId, path).isFailure)
        assertTrue(unconfigured.upload(owner, assetId, path, jpeg).isFailure)
        assertTrue(unconfigured.delete(owner, assetId, path).isFailure)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `stale caller fence prevents all requests`() = runTest {
        callerCurrent.set(false)
        assertTrue(client.download(owner, assetId, path, callerCurrent::get).isFailure)
        assertTrue(client.upload(owner, assetId, path, jpeg, callerCurrent::get).isFailure)
        assertTrue(client.delete(owner, assetId, path, callerCurrent::get).isFailure)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `account switch while download in flight does not return old private bytes`() = runTest {
        respondAfter { session.set(authSession(otherOwner)) }
        assertTrue(client.download(owner, assetId, path).isFailure)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `same owner session replacement while download in flight does not return bytes`() = runTest {
        respondAfter { session.set(authSession(owner).copy(accessToken = "replacement-token")) }
        assertTrue(client.download(owner, assetId, path).isFailure)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `late write success cannot acknowledge old owner session or caller revision`() = runTest {
        respondAfter { session.set(authSession(otherOwner)) }
        assertTrue(client.upload(owner, assetId, path, jpeg).isFailure)
        session.set(authSession(owner))
        respondAfter { callerCurrent.set(false) }
        assertTrue(client.delete(owner, assetId, path, callerCurrent::get).isFailure)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `caller fence becoming stale discards downloaded private bytes`() = runTest {
        respondAfter { callerCurrent.set(false) }
        assertTrue(client.download(owner, assetId, path, callerCurrent::get).isFailure)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `write gate closing after collision suppresses even collision probe`() = runTest {
        respondAfter(status = 409) { writeGate.set(false) }
        assertTrue(client.upload(owner, assetId, path, jpeg).isFailure)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `account switch after collision suppresses collision probe`() = runTest {
        respondAfter(status = 400) { session.set(authSession(otherOwner)) }
        assertTrue(client.upload(owner, assetId, path, jpeg).isFailure)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `late collision probe cannot acknowledge bytes for stale caller`() = runTest {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = if (request.method == "POST") {
                MockResponse().setResponseCode(409)
            } else {
                callerCurrent.set(false)
                binaryResponse()
            }
        }
        assertTrue(client.upload(owner, assetId, path, jpeg, callerCurrent::get).isFailure)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `upload snapshots caller bytes for immutable collision comparison`() = runTest {
        val mutableInput = jpeg.copyOf()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = if (request.method == "POST") {
                mutableInput[2] = 99
                MockResponse().setResponseCode(409)
            } else binaryResponse()
        }
        client.upload(owner, assetId, path, mutableInput).getOrThrow()
        assertArrayEquals(jpeg, assertPrivateRequest("POST").body.readByteArray())
        assertPrivateRequest("GET")
    }

    @Test
    fun `new requests use latest current session credentials`() = runTest {
        session.set(authSession(owner).copy(accessToken = "latest-access-token"))
        server.enqueue(binaryResponse())
        client.download(owner, assetId, path).getOrThrow()
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("Bearer latest-access-token", request!!.getHeader("Authorization"))
    }

    @Test
    fun `cancellation cancels private request and propagates instead of Result failure`() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val deferred = async(Dispatchers.Default) { client.download(owner, assetId, path) }
        assertNotNull(server.takeRequest(2, TimeUnit.SECONDS))
        deferred.cancelAndJoin()
        assertTrue(deferred.isCancelled)
    }

    private fun newClient(
        config: SupabaseConfig = SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
        writesEnabled: () -> Boolean = writeGate::get,
    ) = SupabaseInvestmentProductImageClient(config, httpClient, session::get, writesEnabled)

    private fun authSession(userId: UserId) = AuthSession(userId, null, "user-access-token", "refresh-token", Long.MAX_VALUE)

    private fun binaryResponse(bytes: ByteArray = jpeg) = MockResponse().setBody(Buffer().write(bytes))

    private fun respondAfter(status: Int = 200, action: () -> Unit) {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                action()
                return binaryResponse().setResponseCode(status)
            }
        }
    }

    private fun assertPrivateRequest(method: String): RecordedRequest {
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        request!!
        assertEquals(method, request.method)
        assertEquals("/storage/v1/object/investment-product-images/$path", request.requestUrl?.encodedPath)
        assertNull(request.requestUrl?.query)
        assertEquals("publishable-key", request.getHeader("apikey"))
        assertEquals("Bearer user-access-token", request.getHeader("Authorization"))
        return request
    }

    private fun assertSafeFailure(result: Result<*>) {
        val message = result.exceptionOrNull()?.toString().orEmpty()
        for (privateText in listOf(path, "user-access-token", "publishable-key", "private-error-detail")) {
            assertFalse(message.contains(privateText))
        }
    }
}
