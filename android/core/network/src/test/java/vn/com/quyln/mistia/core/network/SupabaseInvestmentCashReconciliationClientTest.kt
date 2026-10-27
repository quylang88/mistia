package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class SupabaseInvestmentCashReconciliationClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val source="77777777-7777-7777-7777-777777777777"
    private val linked="88888888-8888-8888-8888-888888888888"
    private val ledgerId=investmentLedgerIdentity(id,"cash-reconciliation")
    private val postingId=investmentLedgerIdentity(id,"linked-cash-posting")
    private val holderId=investmentLedgerIdentity(id,"holder-cash-posting")
    private val token="cash-event-contract-token"
    private val now="2026-10-27T00:00:00Z"
    private val version=9007199254740993L
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private lateinit var server:MockWebServer
    private lateinit var client:SupabaseInvestmentCashReconciliationClient
    private lateinit var http:OkHttpClient
    @Before fun setup() {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(cert).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false).callTimeout(3,TimeUnit.SECONDS).build()
        client=SupabaseInvestmentCashReconciliationClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun transaction(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,ledgerId,owner.value,buildJsonObject {
        put("id",ledgerId);put("user_id",owner.value);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("settlement_role_raw_value","investmentReconciliation");put("title","Cash event");put("note",JsonNull)
        put("amount_minor",80);put("source_wallet_id",if(withdraw)linked else source);put("destination_wallet_id",if(withdraw)source else linked)
        put("destination_amount_minor",80);put("reporting_amount_minor",80);put("reporting_expense_minor",0);put("reporting_income_minor",0)
        for(key in listOf("source_currency_code","destination_currency_code","reporting_currency_code"))put(key,"VND")
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at","deleted_at"))put(key,JsonNull)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun posting(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject {
        put("id",postingId);put("user_id",owner.value);put("event_id",id);put("ledger_transaction_id",ledgerId);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked)
        put("role_raw_value","cashReconciliation");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",if(withdraw)-20 else 50);put("accounting_amount_minor",if(withdraw)-20 else 50);put("currency_code","VND");put("accounting_currency_code","VND")
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
    },now,null,v)
    private fun reply(vararg rows:CloudRecord)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun auth(request:RecordedRequest) {
        assertEquals("Bearer $token",request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
    }
    private fun holder(v:Long=1)=posting(v).let{it.copy(id=holderId,payload=JsonObject(it.payload+buildJsonObject{put("id",holderId);put("wallet_id",source);put("amount_minor",-50);put("accounting_amount_minor",-50)}))}
    private fun group(v:Long=1)=InvestmentCashReconciliationGroup(transaction(),holder(v),posting(v))
    @Test fun comparedBatchSendsCompleteExactVersionMapAndForceFalse()=runTest {
        val g=group(version+1);server.enqueue(reply(g.holder,g.linked))
        assertEquals(listOf(g.holder,g.linked),client.publishPostings(owner,id,g,mapOf(holderId to version,postingId to version),token))
        val r=server.takeRequest();auth(r);assertEquals("/rest/v1/rpc/mutate_investment_cash_postings",r.requestUrl!!.encodedPath)
        val b=Json.parseToJsonElement(r.body.readUtf8()).jsonObject
        assertEquals(setOf("p_rows","p_expected_versions","p_force"),b.keys)
        assertEquals(JsonArray(listOf(g.holder.payload,g.linked.payload)),b["p_rows"])
        assertEquals(buildJsonObject{put(holderId,version);put(postingId,version)},b["p_expected_versions"]);assertEquals(JsonPrimitive(false),b["p_force"])
    }
    @Test fun ledgerInsertHasNoMergeAndCannotBeMistakenForFinancialAcknowledgement()=runTest {
        val row=transaction();server.enqueue(reply(row));assertEquals(row,client.createLedger(owner,id,row,token))
        val r=server.takeRequest();auth(r);assertEquals("POST",r.method);assertEquals("/rest/v1/ledger_transactions",r.requestUrl!!.encodedPath)
        assertFalse(r.getHeader("Prefer")!!.contains("merge"));assertNull(r.requestUrl!!.queryParameter("on_conflict"))
        assertEquals(row.payload,Json.parseToJsonElement(r.body.readUtf8()).jsonObject)
    }
    @Test fun ownedReadsUseDerivedLedgerIdAndContinueShortPostingPagesUntilEmpty()=runTest {
        val posts=listOf(holder(),posting()).sortedBy{it.id};server.enqueue(reply(transaction()));posts.forEach{server.enqueue(reply(it))};server.enqueue(reply())
        val result=client.fetchEvent(owner,id,token);assertEquals(transaction(),result.ledger);assertEquals(posts,result.postings)
        val r=server.takeRequest();auth(r);assertEquals("eq.$ledgerId",r.requestUrl!!.queryParameter("id"));assertEquals("eq.${owner.value}",r.requestUrl!!.queryParameter("user_id"))
        for(i in 0..2) {val request=server.takeRequest();auth(request);assertEquals("eq.$id",request.requestUrl!!.queryParameter("event_id"));assertEquals("eq.${owner.value}",request.requestUrl!!.queryParameter("user_id"));assertEquals(if(i==0)null else "gt.${posts[i-1].id}",request.requestUrl!!.queryParameter("id"))}
    }
    @Test fun incompleteOrFabricatedComparisonMapCannotReachHttp()=runTest {
        for(map in listOf(emptyMap(),mapOf(holderId to 0L),mapOf(holderId to -1L,postingId to 0L),mapOf(holderId to Long.MAX_VALUE,postingId to 0L),mapOf(holderId to 0L,postingId to 0L,source to 0L)))
            assertTrue(runCatching{client.publishPostings(owner,id,group(),map,token)}.isFailure)
        assertEquals(0,server.requestCount)
    }
    @Test fun gatesSessionCurrencyAndCanonicalIdentityAreCheckedBeforeHttp()=runTest {
        enabled.set(false);assertTrue(runCatching{client.createLedger(owner,id,transaction(),token)}.exceptionOrNull() is IllegalStateException)
        assertTrue(runCatching{client.publishPostings(owner,id,group(),mapOf(holderId to 0L,postingId to 0L),token)}.exceptionOrNull() is IllegalStateException)
        enabled.set(true);session.set(session.get()!!.copy(accessToken="rotated"));assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is CancellationException)
        session.set(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
        val wrong=group().let{it.copy(linked=it.linked.copy(payload=JsonObject(it.linked.payload+("accounting_currency_code" to JsonPrimitive("JPY")))))}
        assertTrue(runCatching{client.publishPostings(owner,id,wrong,mapOf(holderId to 0L,postingId to 0L),token)}.isFailure);assertEquals(0,server.requestCount)
    }
    @Test fun sessionRevocationDuringHttpFailureStillCancels()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(r:RecordedRequest):MockResponse {session.set(session.get()!!.copy(accessToken="rotated"));return MockResponse().setResponseCode(403).setBody("private diagnostics")}}
        assertTrue(runCatching{client.createLedger(owner,id,transaction(),token)}.exceptionOrNull() is CancellationException)
    }
    @Test fun partialDifferentOrRegressedBatchRepliesAreAmbiguousAndNeverAcked()=runTest {
        for(rows in listOf(listOf(holder()),listOf(holder(),holder()),listOf(holder(2),posting(1)))) {
            server.enqueue(reply(*rows.toTypedArray()));assertTrue(runCatching{client.publishPostings(owner,id,group(),mapOf(holderId to 0L,postingId to 0L),token)}.exceptionOrNull() is java.io.IOException)
        }
    }
    @Test fun foreignPrivateAndWrongLedgerRepliesAreRejected()=runTest {
        for(row in listOf(transaction().copy(payload=JsonObject(transaction().payload+("user_id" to JsonPrimitive(device)))),transaction().copy(payload=JsonObject(transaction().payload+("_mistia_android_unknown" to JsonPrimitive(true)))),transaction().copy(id=id,payload=JsonObject(transaction().payload+("id" to JsonPrimitive(id)))))) {
            server.enqueue(reply(row));assertTrue(runCatching{client.createLedger(owner,id,transaction(),token)}.exceptionOrNull() is java.io.IOException)
        }
    }    @Test fun versionRaceRetainsOnlyTheClosedSqlConditionWithoutPrivateDiagnostics()=runTest {
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"version_conflict","details":"private synthetic diagnostics"}"""))
        val error=runCatching{client.publishPostings(owner,id,group(),mapOf(holderId to 0L,postingId to 0L),token)}.exceptionOrNull() as SupabaseHttpException
        assertEquals(400,error.statusCode);assertEquals("version_conflict",error.serviceCode);assertFalse(error.toString().contains("private synthetic"))
    }
    @Test fun readsRemainAvailableWithWritesOffAndRejectPrivateOrForeignBodies()=runTest {
        enabled.set(false);server.enqueue(reply());server.enqueue(reply());assertNull(client.fetchEvent(owner,id,token).ledger)
        for(p in listOf(transaction().payload+("user_id" to JsonPrimitive(device)),transaction().payload+("_mistia_android_fake" to JsonPrimitive(true)))) {
            server.enqueue(MockResponse().setBody(JsonArray(listOf(JsonObject(p))).toString()));assertTrue(runCatching{client.fetchEvent(owner,id,token)}.isFailure)
        }
    }
    @Test fun redirectCannotCarryBearerHeadersToAnotherEndpoint()=runTest {
        server.enqueue(MockResponse().setResponseCode(307).setHeader("Location",server.url("/foreign")))
        assertTrue(runCatching{client.createLedger(owner,id,transaction(),token)}.exceptionOrNull() is SupabaseHttpException);assertEquals(1,server.requestCount)
    }
    @Test fun gateRevocationDuringFailedHttpCancelsInsteadOfRecordingAnAuthorizationError()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {enabled.set(false);return MockResponse().setResponseCode(403)}}
        assertTrue(runCatching{client.createLedger(owner,id,transaction(),token)}.exceptionOrNull() is CancellationException)
    }

}
