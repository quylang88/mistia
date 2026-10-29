package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class CardPaidCyclePagingTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val card="22222222-2222-2222-2222-222222222222"
    private val id="33333333-3333-3333-3333-333333333333"
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-15T00:00:00Z"
    private val version=9007199254740993L
    private lateinit var server:MockWebServer
    private lateinit var store:SupabasePostgrestRemoteStore
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val cert=HandshakeCertificates.Builder().heldCertificate(certificate).build();val trust=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(cert.sslSocketFactory(),false);start()}
        val client=OkHttpClient.Builder().sslSocketFactory(trust.sslSocketFactory(),trust.trustManager).callTimeout(3,TimeUnit.SECONDS).build()
        store=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"fixture"),client,writableEntities=emptySet())
    }
    @After fun close(){server.shutdown()}
    private fun cycle()=DueOccurrenceRecord(id,owner.value,"creditCard",card,"2026-09",time,70,"paid",time,other,time,time,null,version,id)
    private suspend fun page(offset:Int=0)=store.fetchCardCyclePage(card,"fixture",owner,offset,100)
    @Test fun fullMembershipIncludesAllMonthsTombstonesAndExactLongWithoutAWriteGate()=runTest {
        val first=cycle();val second=first.copy(id=other,selectedMonthKey="2026-10",deletedAt=time)
        for((index,row) in listOf(first,second).withIndex()) {
            server.enqueue(MockResponse().setHeader("Content-Range","$index-$index/2").setBody("[${row.toPayload()}]"))
            val p=page(index);assertEquals(row.toCloudRecord(),p.records.single());assertEquals(if(index==0)1 else null,p.nextOffset)
            val r=server.takeRequest(1,TimeUnit.SECONDS)!!;val url=r.requestUrl!!
            assertEquals("GET",r.method);assertEquals("/rest/v1/due_occurrence_records",url.encodedPath)
            assertEquals("eq.${owner.value}",url.queryParameter("user_id"));assertEquals("eq.creditCard",url.queryParameter("source_kind_raw_value"))
            assertEquals("eq.$card",url.queryParameter("source_id"));assertEquals("id.asc",url.queryParameter("order"))
            for(key in listOf("selected_month_key","deleted_at","status_raw_value","limit"))assertNull(url.queryParameter(key))
            assertEquals("$index-${index+99}",r.getHeader("Range"));assertEquals("count=exact",r.getHeader("Prefer"))
        }
    }
    @Test fun malformedForeignPrivateOrDuplicateRowsCannotProveCompleteMembership()=runTest {
        val p=cycle().toPayload()
        val bad=listOf(JsonArray(listOf(JsonObject(p+("user_id" to JsonPrimitive(other))))),JsonArray(listOf(JsonObject(p+("source_id" to JsonPrimitive(other))))),
            JsonArray(listOf(JsonObject(p+("source_kind_raw_value" to JsonPrimitive("installment"))))),JsonArray(listOf(JsonObject(p+("sync_version" to JsonPrimitive(version.toString()))))),
            JsonArray(listOf(JsonObject(p+("_mistia_android_spoof" to JsonPrimitive(true))))),JsonArray(listOf(p,p)))
        for(body in bad){server.enqueue(MockResponse().setHeader("Content-Range","0-0/1").setBody(body.toString()));assertTrue(runCatching{page()}.isFailure)}
        assertEquals(bad.size,server.requestCount)
    }
    @Test fun exactTerminalEmptyPageCanProveAbsenceWithoutHidingAnIncompleteRange()=runTest {
        server.enqueue(MockResponse().setHeader("Content-Range","*/0").setBody("[]"))
        assertEquals(DueOccurrencePage(emptyList(),null),page())
        server.enqueue(MockResponse().setHeader("Content-Range","*/2").setBody("[]"))
        assertEquals(DueOccurrencePage(emptyList(),null),page(2))
        server.enqueue(MockResponse().setHeader("Content-Range","*/2").setBody("[]"))
        assertTrue(runCatching{page()}.isFailure);assertEquals(3,server.requestCount)
    }
    @Test fun missingOrContradictoryRangeCannotBeTreatedAsAnEmptyCollection()=runTest {
        for(range in listOf(null,"0-0/*","1-1/1","0-0/0")) {
            val response=MockResponse().setBody("[${cycle().toPayload()}]");if(range!=null)response.setHeader("Content-Range",range)
            server.enqueue(response);assertTrue(runCatching{page()}.isFailure)
        }
        assertEquals(4,server.requestCount)
    }
    @Test fun invalidInputFailsBeforeHttp()=runTest {
        for((cardId,offset,limit) in listOf(Triple("invalid",0,100),Triple(card,-1,100),Triple(card,0,1001),Triple(card,Int.MAX_VALUE,100)))
            assertTrue(runCatching{store.fetchCardCyclePage(cardId,"fixture",owner,offset,limit)}.exceptionOrNull() is IllegalArgumentException)
        assertEquals(0,server.requestCount)
    }
}
