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

class SupabaseInvestmentCashEventClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val source="77777777-7777-7777-7777-777777777777"
    private val linked="88888888-8888-8888-8888-888888888888"
    private val postingId="625e1715-81fd-57c6-91e1-596e53e42db5"
    private val token="cash-event-contract-token"
    private val now="2026-10-27T00:00:00Z"
    private val version=9007199254740993L
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private lateinit var server:MockWebServer
    private lateinit var client:SupabaseInvestmentCashEventClient
    private lateinit var http:OkHttpClient
    @Before fun setup() {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(cert).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false).callTimeout(3,TimeUnit.SECONDS).build()
        client=SupabaseInvestmentCashEventClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun transaction(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("settlement_role_raw_value",if(withdraw)"investmentCashWithdrawal" else "investmentCashDeposit");put("title","Cash event");put("note",JsonNull)
        put("amount_minor",if(withdraw)20 else 50);put("source_wallet_id",if(withdraw)linked else source);put("destination_wallet_id",if(withdraw)source else linked)
        put("destination_amount_minor",if(withdraw)20 else 50);put("reporting_amount_minor",if(withdraw)20 else 50);put("reporting_expense_minor",0);put("reporting_income_minor",0)
        for(key in listOf("source_currency_code","destination_currency_code","reporting_currency_code"))put(key,"VND")
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at","deleted_at"))put(key,JsonNull)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun posting(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject {
        put("id",postingId);put("user_id",owner.value);put("event_id",id);put("ledger_transaction_id",id);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked)
        put("role_raw_value","cashTransfer");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",if(withdraw)-20 else 50);put("accounting_amount_minor",if(withdraw)-20 else 50);put("currency_code","VND");put("accounting_currency_code","VND")
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
    },now,null,v)
    private fun reply(vararg rows:CloudRecord)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun auth(request:RecordedRequest) {
        assertEquals("Bearer $token",request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
    }
    @Test fun depositUsesOnlyTheAtomicRpcWithExactInt64PostingCasAndExplicitNulls()=runTest {
        val row=transaction(version+1);val post=posting(43);server.enqueue(reply(row))
        assertEquals(row,client.mutateEvent(owner,InvestmentCashEventProposal(row,post),version,42,token))
        val r=server.takeRequest();auth(r);assertEquals("/rest/v1/rpc/mutate_investment_cash_event",r.requestUrl!!.encodedPath);assertEquals("POST",r.method)
        val body=Json.parseToJsonElement(r.body.readUtf8()).jsonObject
        assertEquals(row.payload,body["p_transaction"]);assertEquals(JsonArray(listOf(post.payload)),body["p_postings"])
        assertEquals(JsonPrimitive(version),body["p_expected_version"]);assertEquals(JsonPrimitive(42),body["p_expected_posting_versions"]!!.jsonObject[postingId]);assertEquals(JsonPrimitive(false),body["p_force"])
        for(key in listOf("p_transaction_id","p_owner_user_id","p_deleted_at","p_device_id"))assertEquals(JsonNull,body[key])
        assertEquals(1,server.requestCount)
    }
    @Test fun withdrawalKeepsItsNegativeCanonicalPostingAndNoInventedExistingPostingVersion()=runTest {
        val row=transaction(1,true);val post=posting(1,true);server.enqueue(reply(row))
        assertEquals(row,client.mutateEvent(owner,InvestmentCashEventProposal(row,post),0,null,token))
        val body=Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertEquals(JsonPrimitive(-20),body["p_postings"]!!.jsonArray.single().jsonObject["accounting_amount_minor"])
        assertEquals(JsonObject(emptyMap()),body["p_expected_posting_versions"])
    }
    @Test fun eventReadsAreOwnerScopedAndShortPostingPagesContinueUntilEmpty()=runTest {
        val row=transaction();val post=posting();server.enqueue(reply(row));server.enqueue(reply(post));server.enqueue(reply())
        assertEquals(InvestmentCashEventCloudSnapshot(owner,id,row,listOf(post)),client.fetchEvent(owner,id,token))
        val first=server.takeRequest();auth(first);assertEquals("eq.${owner.value}",first.requestUrl!!.queryParameter("user_id"));assertEquals("eq.$id",first.requestUrl!!.queryParameter("id"))
        val second=server.takeRequest();auth(second);assertEquals("/rest/v1/investment_wallet_postings",second.requestUrl!!.encodedPath);assertEquals("eq.$id",second.requestUrl!!.queryParameter("event_id"))
        val third=server.takeRequest();assertEquals("gt.$postingId",third.requestUrl!!.queryParameter("id"));assertEquals("id.asc",third.requestUrl!!.queryParameter("order"))
    }
    @Test fun deletionSendsOnlyTheClosedRetirementFieldsAndActualPostingBase()=runTest {
        val row=transaction(79).let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))};server.enqueue(reply(row))
        assertEquals(row,client.deleteEvent(owner,id,78,42,now,device,token))
        val r=server.takeRequest();auth(r);val b=Json.parseToJsonElement(r.body.readUtf8()).jsonObject
        assertEquals(JsonNull,b["p_transaction"]);assertEquals(JsonArray(emptyList()),b["p_postings"]);assertEquals(JsonPrimitive(78),b["p_expected_version"])
        assertEquals(JsonPrimitive(id),b["p_transaction_id"]);assertEquals(JsonPrimitive(owner.value),b["p_owner_user_id"]);assertEquals(JsonPrimitive(now),b["p_deleted_at"]);assertEquals(JsonPrimitive(device),b["p_device_id"]);assertEquals(JsonPrimitive(false),b["p_force"])
        assertEquals(JsonPrimitive(42),b["p_expected_posting_versions"]!!.jsonObject[postingId])
    }
    @Test fun disabledWritesSendNoRequestButOwnedReadsRemainAvailable()=runTest {
        enabled.set(false)
        assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() is IllegalStateException)
        assertEquals(0,server.requestCount);server.enqueue(reply());server.enqueue(reply())
        assertEquals(InvestmentCashEventCloudSnapshot(owner,id,null,emptyList()),client.fetchEvent(owner,id,token))
    }
    @Test fun wrongCapturedSessionFailsBeforeAnyRequest()=runTest {
        session.set(AuthSession(UserId(device),null,token,"refresh",Long.MAX_VALUE))
        assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is CancellationException);assertEquals(0,server.requestCount)
    }
    @Test fun mixedCurrenciesAreRejectedBeforeAnyCashWrite()=runTest {
        val wrong=posting().let{it.copy(payload=JsonObject(it.payload+("currency_code" to JsonPrimitive("JPY"))))}
        assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),wrong),0,null,token)}.exceptionOrNull() is IllegalArgumentException);assertEquals(0,server.requestCount)
    }
    @Test fun privateRemoteAuthorityCannotEnterAnEventSnapshot()=runTest {
        val injected=transaction().let{it.copy(payload=JsonObject(it.payload+("_mistia_android_forged_cash_parent" to JsonNull)))};server.enqueue(reply(injected))
        assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun http403IsPreservedAsHttpFailureWithoutReturningItsPrivateBody()=runTest {
        server.enqueue(MockResponse().setResponseCode(403).setBody("private server detail"))
        val error=runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull()
        assertTrue(error is SupabaseHttpException);assertEquals(403,(error as SupabaseHttpException).statusCode);assertFalse(error.toString().contains("private server detail"))
    }
    @Test fun malformedWriteReplyIsRetryableBecauseTheAtomicEventMayAlreadyBeSaved()=runTest {
        server.enqueue(MockResponse().setBody("{broken private body"))
        val error=runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull()
        assertTrue(error is java.io.IOException);assertFalse(error.toString().contains("private body"))
    }
    @Test fun lostWriteBodyReturnsNetworkFailureInsteadOfHangingOrAcknowledging()=runTest {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
        assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() is java.io.IOException)
    }
    @Test fun sameOwnerTokenRotationDuringTheResponseRevokesTheReturnedReceipt()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            session.set(AuthSession(owner,null,"rotated-token","refresh",Long.MAX_VALUE));return reply(transaction())
        }}
        assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() is CancellationException)
    }
    @Test fun completeEventReadsRetainNoncanonicalCashSiblingsForLaterRetirementProof()=runTest {
        val extra="ffffffff-ffff-4fff-8fff-ffffffffffff"
        val sibling=posting().let{it.copy(id=extra,payload=JsonObject(it.payload+buildJsonObject{put("id",extra);put("role_raw_value","cashCorrection");put("amount_minor",0);put("accounting_amount_minor",0)}))}
        server.enqueue(reply(transaction()));server.enqueue(reply(posting(),sibling));server.enqueue(reply())
        assertEquals(listOf(posting(),sibling),client.fetchEvent(owner,id,token).postings)
    }

    @Test fun malformedOrUnrelatedCanonicalProposalCannotSendMoney()=runTest {
        val post=posting()
        val bad=listOf(
            post.copy(id=device,payload=JsonObject(post.payload+("id" to JsonPrimitive(device)))),
            post.copy(payload=JsonObject(post.payload+("accounting_amount_minor" to JsonPrimitive(-50)))),
            post.copy(payload=JsonObject(post.payload+("event_id" to JsonPrimitive(device)))),
            post.copy(payload=JsonObject(post.payload+("_mistia_android_forged_cash_parent" to JsonNull))),
        )
        for(candidate in bad)assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),candidate),0,null,token)}.exceptionOrNull() is IllegalArgumentException)
        assertEquals(0,server.requestCount)
    }
    @Test fun plainHttpIsRejectedBeforeAnyAuthorizationHeaderCanBeSent()=runTest {
        val calls=java.util.concurrent.atomic.AtomicInteger()
        val transport=OkHttpClient.Builder().eventListener(object:okhttp3.EventListener(){override fun callStart(call:okhttp3.Call){calls.incrementAndGet()}}).build()
        val insecure=SupabaseInvestmentCashEventClient(SupabaseConfig(server.url("/").newBuilder().scheme("http").build().toString(),"local-publishable-key"),transport,{session.get()},{enabled.get()})
        assertTrue(runCatching{insecure.fetchEvent(owner,id,token)}.isFailure)
        assertEquals(0,calls.get());assertEquals(0,server.requestCount)
    }
    @Test fun redirectsAreNotFollowedEvenToTheSameServer()=runTest {
        server.enqueue(MockResponse().setResponseCode(302).addHeader("Location",server.url("/unwanted")))
        val error=runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull()
        assertTrue(error is SupabaseHttpException);assertEquals(302,(error as SupabaseHttpException).statusCode);assertEquals(1,server.requestCount)
    }
    @Test fun foreignLedgerAndDuplicatePostingPagesCannotCertifyTheOwnedEvent()=runTest {
        val foreign=transaction().let{it.copy(ownerUserId=device,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(device))))}
        server.enqueue(reply(foreign));assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is IllegalArgumentException)
        server.enqueue(reply(transaction()));server.enqueue(reply(posting(),posting()))
        assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun anUnexpectedVersionAfterTheWriteIsAmbiguousAndCannotBeAcknowledged()=runTest {
        server.enqueue(reply(transaction(2)))
        assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() is java.io.IOException)
    }
    @Test fun revokingTheWriteGateDuringTheReplyRevokesItsReceipt()=runTest {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            enabled.set(false);return reply(transaction())
        }}
        assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() is CancellationException)
    }
    @Test fun cancellationDuringAnOutstandingReadStopsItsCaller()=runTest {
        val failure=kotlinx.coroutines.CompletableDeferred<Throwable>()
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val job=launch {
            try{client.fetchEvent(owner,id,token)}catch(error:Throwable){failure.complete(error);throw error}
        }
        assertNotNull(kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO){server.takeRequest(1,TimeUnit.SECONDS)})
        job.cancel();job.join();assertTrue(failure.await() is CancellationException)
    }

    @Test fun malformedActorInAnOtherwiseOwnedLedgerReadIsRejected()=runTest {
        server.enqueue(reply(transaction().let{it.copy(payload=JsonObject(it.payload+("last_modified_by_device_id" to buildJsonObject{put("bad",true)})))}))
        server.enqueue(reply())
        assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun cashEventPostingCannotSmuggleAnAssetOrTradeReference()=runTest {
        for(key in listOf("trade_id","asset_id")) {
            server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse =
                if(request.requestUrl!!.encodedPath=="/rest/v1/ledger_transactions")reply(transaction())
                else if(request.requestUrl!!.queryParameter("id")==null)reply(posting().let{it.copy(payload=JsonObject(it.payload+(key to JsonPrimitive(device))))})
                else reply()
            }
            assertTrue(runCatching{client.fetchEvent(owner,id,token)}.exceptionOrNull() is IllegalArgumentException)
        }
    }

    @Test fun genericLedgerPullAndFetchCannotImportPrivateCashAuthority()=runTest {
        val row=transaction().let{it.copy(payload=JsonObject(it.payload+(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY to JsonNull)))}
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http)
        server.enqueue(reply(row));assertTrue(runCatching{generic.pullPage(CloudEntity.LEDGER_TRANSACTION.table,token,owner,0,100)}.exceptionOrNull() is IllegalArgumentException)
        server.enqueue(reply(row));assertTrue(runCatching{generic.fetchRecord(CloudEntity.LEDGER_TRANSACTION,id,token,owner)}.exceptionOrNull() is IllegalArgumentException)
    }

    @Test fun aRelabelledCashParentCannotEnterTheGenericLedgerWriter()=runTest {
        val row=transaction().let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY,JsonNull);put("settlement_role_raw_value",JsonNull)}))}
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,writableEntities=setOf(CloudEntity.LEDGER_TRANSACTION))
        server.enqueue(reply(row))
        assertTrue(runCatching{generic.createRecord(CloudEntity.LEDGER_TRANSACTION,token,owner,row.payload)}.isFailure)
        assertEquals(0,server.requestCount)
    }

    @Test fun dynamicCashRejectionsExposeOnlyAnExactWhitelistedSqlCode()=runTest {
        for(code in listOf("investment_cash_limit_conflict","investment_cash_has_dependent_events","investment_cash_invalid_linked_wallet")) {
            server.enqueue(MockResponse().setResponseCode(400).setBody(buildJsonObject{put("code","P0001");put("message",code);put("details",token)}.toString()))
            val error=runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() as SupabaseHttpException
            assertEquals(400,error.statusCode);assertEquals(code,error.serviceCode);assertEquals("",error.responseBody);assertFalse(error.toString().contains(token))
        }
    }
    @Test fun unknownSqlTextWrongSqlCodeAndPermissionErrorsCannotClaimACashDependency()=runTest {
        for((status,body) in listOf(400 to """{"code":"P0001","message":"investment_cash_limit_conflict secret"}""",
            400 to """{"code":"42501","message":"investment_cash_limit_conflict"}""",403 to """{"code":"P0001","message":"investment_cash_limit_conflict"}""")) {
            server.enqueue(MockResponse().setResponseCode(status).setBody(body))
            val error=runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() as SupabaseHttpException
            assertEquals(status,error.statusCode);assertNull(error.serviceCode);assertEquals("",error.responseBody)
        }
    }

    @Test fun authorizationRevocationDuringAnHttpFailureStillCancelsTheCapturedRequest()=runTest {
        for(rotateSession in listOf(true,false)) {
            session.set(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE));enabled.set(true)
            server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
                if(rotateSession)session.set(AuthSession(owner,null,"rotated-token","refresh",Long.MAX_VALUE)) else enabled.set(false)
                return MockResponse().setResponseCode(403).setBody("private denial")
            }}
            assertTrue(runCatching{client.mutateEvent(owner,InvestmentCashEventProposal(transaction(),posting()),0,null,token)}.exceptionOrNull() is CancellationException)
        }
    }

}
