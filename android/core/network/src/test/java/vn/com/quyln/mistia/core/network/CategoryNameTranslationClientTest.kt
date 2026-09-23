package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.CategoryNameTranslations

class CategoryNameTranslationClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: SupabaseCategoryNameTranslator

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder()
            .addTrustedCertificate(certificate.certificate)
            .build()
        server = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
        }
        client = SupabaseCategoryNameTranslator(
            SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            OkHttpClient.Builder().sslSocketFactory(
                clientCertificates.sslSocketFactory(),
                clientCertificates.trustManager,
            ).build(),
        )
    }

    @After
    fun tearDown() = server.shutdown()

    @Test
    fun `translation request matches edge function contract and trims response`() = runTest {
        server.enqueue(MockResponse().setBody(
            """{"name_vietnamese":" Ăn ngoài ","name_english":" Dining ","name_japanese":" 外食 "}"""
        ))

        val result = client.translate("Ăn ngoài", CategoryNameLanguage.VIETNAMESE, "access-token")

        assertEquals(CategoryNameTranslations("Ăn ngoài", "Dining", "外食"), result)
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("POST", request!!.method)
        assertEquals("/functions/v1/translate-category-name", request.requestUrl?.encodedPath)
        assertEquals("publishable-key", request.headers["apikey"])
        assertEquals("Bearer access-token", request.headers["Authorization"])
        assertEquals("{\"name\":\"Ăn ngoài\",\"source_language\":\"vi\"}", request.body.readUtf8())
    }

    @Test
    fun `translation error exposes status without response secrets in message`() = runTest {
        server.enqueue(MockResponse().setResponseCode(502).setBody("{\"message\":\"private upstream detail\"}"))

        val failure = runCatching {
            client.translate("Ăn ngoài", CategoryNameLanguage.VIETNAMESE, "access-token")
        }.exceptionOrNull()

        assertEquals(502, (failure as SupabaseHttpException).statusCode)
        assertEquals("Supabase request failed (502)", failure.message)
    }
}
