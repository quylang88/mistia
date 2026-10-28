package vn.com.quyln.mistia.core.network

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.*
import vn.com.quyln.mistia.core.model.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean

class SupabaseWalletInvestmentPrerequisiteClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-28T00:00:00Z"
    private val later="2026-10-28T00:01:00Z"
    private val event=id(20)
    private fun version(row:CloudRecord,n:Long)=row.copy(syncVersion=n,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(n))))
    private fun source(newWallet:Boolean=false):InvestmentTradePublicationSnapshot {
        fun wallet(n:Int)=version(WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=150).toMutation(owner,null,device,now).record,if(newWallet && n==1)0 else 1)
        val root=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject {
            put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1));put("opening_balance_minor",0)
        }))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",1L)
            put("event_id",id(110));put("wallet_id",id(1));put("ledger_transaction_id",id(110));put("role_raw_value","cashAccrual")
            put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",50L);put("accounting_amount_minor",50L)
            put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at",now)
        },now,null,1)
        val before=InvestmentWalletSnapshot(owner,listOf(root,wallet(1),wallet(2),cash))
        val plan=planInvestmentWalletLink(before,InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(root),LedgerWalletRecord.fromCloudRecord(before.rows.single{it.id==id(2)}),event,true,50,"Move all"),device,now)
        val changed=plan.mutations.map{it.first}.associateBy{it.entity to it.id}
        val rows=(before.rows.map{changed[it.entity to it.id] ?: it}+changed.values.filter{r->before.rows.none{it.entity==r.entity && it.id==r.id}}).map{if(it.id==root.id)version(it,2) else it}
        val archive=LedgerWalletRecord.fromCloudRecord(rows.single{it.id==id(1)}).toArchiveMutation(device,later)
        val pending=plan.mutations.filter{it.second.entity!=CloudEntity.LEDGER_WALLET}.map{QueuedMutation(it.second,0,0,null)}+QueuedMutation(archive.pending,0,0,null)
        return InvestmentTradePublicationSnapshot(owner,event,rows.map{if(it.id==id(1))archive.record else it},pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet()).also{it.requireCoherent()}
    }
    private fun active(s:InvestmentTradePublicationSnapshot)=s.rows.single{it.id==id(1)}.let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("is_archived",false);put("archived_at",JsonNull)}))}
    private fun withChange(s:InvestmentTradePublicationSnapshot,row:CloudRecord)=s.copy(rows=s.rows.map{if(it.entity==row.entity && it.id==row.id)row else it},pending=s.pending.map{q->if(q.mutation.recordId==row.id)q.copy(mutation=q.mutation.copy(payload=row.payload,baseVersion=row.syncVersion,modifiedAt=row.updatedAt!!)) else q})
    private val token="wallet-prerequisite-test-token"
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private lateinit var server:MockWebServer
    private lateinit var http:OkHttpClient
    private lateinit var client:SupabaseWalletInvestmentPrerequisiteClient
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false).callTimeout(3,TimeUnit.SECONDS).build()
        client=SupabaseWalletInvestmentPrerequisiteClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun reply(vararg rows:CloudRecord)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun request():RecordedRequest=requireNotNull(server.takeRequest(2,TimeUnit.SECONDS)){"Expected owned wallet HTTP request"}
    private fun auth(r:RecordedRequest){assertEquals("Bearer $token",r.getHeader("Authorization"));assertEquals("local-publishable-key",r.getHeader("apikey"))}
    private fun edit():WalletInvestmentPrerequisitePreparation {
        val s=source();val previous=active(s).let{it.copy(payload=JsonObject(it.payload+("name" to JsonPrimitive("Earlier name"))))}
        return prepareWalletInvestmentPrerequisite(s,id(1),previous)
    }
    @Test fun readsOneOwnedOrdinaryWalletWithoutGivingItFinancialAuthority()=runTest {
        val row=active(source());server.enqueue(reply(row));assertEquals(row,client.fetchWallet(owner,id(1),token))
        val r=request();auth(r);assertEquals("GET",r.method);assertEquals("/rest/v1/ledger_wallets",r.requestUrl!!.encodedPath)
        assertEquals("eq.${owner.value}",r.requestUrl!!.queryParameter("user_id"));assertEquals("eq.${id(1)}",r.requestUrl!!.queryParameter("id"));assertEquals("2",r.requestUrl!!.queryParameter("limit"))
    }
    @Test fun unpublishedActivePreparationIsInsertOnlyWithNoPrivateJournalOnTheWire()=runTest {
        val p=prepareWalletInvestmentPrerequisite(source(true),id(1),null);server.enqueue(reply());server.enqueue(reply(p.proposal))
        assertEquals(p.proposal,client.publishActive(owner,p,token));val probe=request();auth(probe);assertEquals("GET",probe.method)
        val r=request();auth(r);assertEquals("POST",r.method);assertNull(r.requestUrl!!.queryParameter("on_conflict"));assertFalse(r.getHeader("Prefer")!!.contains("merge"))
        val body=Json.parseToJsonElement(r.body.readUtf8()).jsonObject;assertEquals(p.proposal.payload,body);assertTrue(body.keys.none{it.startsWith("_mistia_android_")})
        assertEquals(false,body.financeRawArchived());assertEquals(JsonNull,body["archived_at"])
    }
    @Test fun existingActiveUpdateUsesAnExactLongComparisonAndRetainsTheFinalLocalArchive()=runTest {
        val base=9007199254740993L;val initial=source();val s=withChange(initial,version(initial.rows.single{it.id==id(1)},base))
        val previous=active(s).let{it.copy(payload=JsonObject(it.payload+("name" to JsonPrimitive("Earlier name"))))}
        val p=prepareWalletInvestmentPrerequisite(s,id(1),previous);server.enqueue(reply(previous));server.enqueue(reply(p.proposal))
        assertEquals(p.proposal,client.publishActive(owner,p,token));request();val r=request();auth(r)
        assertEquals("PATCH",r.method);assertEquals("eq.$base",r.requestUrl!!.queryParameter("sync_version"));assertEquals("eq.${owner.value}",r.requestUrl!!.queryParameter("user_id"));assertEquals("eq.${id(1)}",r.requestUrl!!.queryParameter("id"))
        assertEquals(base+1,Json.parseToJsonElement(r.body.readUtf8()).jsonObject.financeRawLong("sync_version"));assertEquals(true,p.preparedRecord.payload.financeRawArchived())
    }
    @Test fun disabledGateAndChangedSessionAreRejectedBeforeAnyRequest()=runTest {
        val p=edit();enabled.set(false);assertTrue(runCatching{client.publishActive(owner,p,token)}.exceptionOrNull() is IllegalStateException)
        enabled.set(true);session.set(session.get()!!.copy(accessToken="rotated"));assertTrue(runCatching{client.fetchWallet(owner,id(1),token)}.exceptionOrNull() is CancellationException)
        assertEquals(0,server.requestCount)
    }
    @Test fun anObservationOrFabricatedWriteProposalCannotEnterTheWriter()=runTest {
        val s=source();val observed=prepareWalletInvestmentPrerequisite(s,id(1),active(s))
        assertTrue(runCatching{client.publishActive(owner,observed,token)}.isFailure)
        val p=edit();val bad=p.copy(proposal=p.proposal.copy(payload=JsonObject(p.proposal.payload+("currency_code" to JsonPrimitive("VND")))))
        assertTrue(runCatching{client.publishActive(owner,bad,token)}.isFailure);assertEquals(0,server.requestCount)
    }
    @Test fun actualRemoteArchiveDeletionAndNewerWinnerNeverReceiveAnActivePatch()=runTest {
        val p=edit();val row=active(source())
        val invalid=listOf(source().rows.single{it.id==id(1)},row.copy(deletedAt=now,payload=JsonObject(row.payload+("deleted_at" to JsonPrimitive(now)))),version(row,5))
        for(remote in invalid) {
            server.enqueue(reply(remote));val result=runCatching{client.publishActive(owner,p,token)}
            assertTrue(result.isFailure || result.getOrNull()==null);assertEquals("GET",request().method)
        }
        assertEquals(3,server.requestCount)
    }
    @Test fun foreignPrivateDuplicateAndSystemWalletReadsAreRejected()=runTest {
        val row=active(source())
        for(rows in listOf(listOf(row.copy(payload=JsonObject(row.payload+("user_id" to JsonPrimitive(device))))),listOf(row.copy(payload=JsonObject(row.payload+("_mistia_android_forged" to JsonPrimitive(true))))),listOf(row,row),listOf(row.copy(payload=JsonObject(row.payload+("system_purpose_raw_value" to JsonPrimitive("investmentProfit"))))))) {
            server.enqueue(reply(*rows.toTypedArray()));assertTrue(runCatching{client.fetchWallet(owner,id(1),token)}.isFailure);request()
        }
    }
    @Test fun authorizationRevocationDuringAnHttpFailureStillCancels()=runTest {
        val p=edit();server.dispatcher=object:Dispatcher(){override fun dispatch(r:RecordedRequest):MockResponse {session.set(session.get()!!.copy(accessToken="rotated"));return MockResponse().setResponseCode(403).setBody("private diagnostics")}}
        assertTrue(runCatching{client.publishActive(owner,p,token)}.exceptionOrNull() is CancellationException);assertEquals(1,server.requestCount)
    }
    @Test fun missingPreviouslyObservedWalletIsNeverRecreated()=runTest {
        server.enqueue(reply());assertNull(client.publishActive(owner,edit(),token));assertEquals("GET",request().method);assertEquals(1,server.requestCount)
    }
    @Test fun lostOwnInsertReplyIsRecoveredByItsExactJournalWithoutAnotherInsert()=runTest {
        val p=prepareWalletInvestmentPrerequisite(source(true),id(1),null);server.enqueue(reply());server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
        assertTrue(runCatching{client.publishActive(owner,p,token)}.exceptionOrNull() is java.io.IOException)
        request();assertEquals("POST",request().method)
        server.enqueue(reply(p.proposal));assertEquals(p.proposal,client.publishActive(owner,p,token));assertEquals("GET",request().method);assertEquals(3,server.requestCount)
    }
    @Test fun redirectsAndNonHttpsTargetsCannotForwardCredentials()=runTest {
        val p=edit();server.enqueue(MockResponse().setResponseCode(302).setHeader("Location",server.url("/other")))
        assertTrue(runCatching{client.publishActive(owner,p,token)}.isFailure);request()
        val insecure=SupabaseWalletInvestmentPrerequisiteClient(SupabaseConfig(server.url("/").toString().replace("https:","http:"),"local-publishable-key"),http,{session.get()},{true})
        assertTrue(runCatching{insecure.fetchWallet(owner,id(1),token)}.isFailure);assertEquals(1,server.requestCount)
    }
    @Test fun genericWalletRoutesRejectTheLocalPrerequisiteJournalOnWritePullAndFetch()=runTest {
        val p=prepareWalletInvestmentPrerequisite(source(),id(1),active(source()))
        val row=p.preparedRecord
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest)=reply(row)}
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,writableEntities=setOf(CloudEntity.LEDGER_WALLET))
        assertTrue(runCatching{generic.createRecord(CloudEntity.LEDGER_WALLET,token,owner,row.payload)}.isFailure)
        assertEquals(0,server.requestCount)
        assertTrue(runCatching{generic.fetchRecord(CloudEntity.LEDGER_WALLET,id(1),token,owner)}.isFailure)
        assertTrue(runCatching{generic.pullPage(CloudEntity.LEDGER_WALLET.table,token,owner,0,100)}.isFailure)
        assertEquals(2,server.requestCount)
    }


    @Test fun disablingTheWriteGateAfterAnAcceptedPatchRevokesItsReply()=runTest {
        val p=edit()
        server.dispatcher=object:Dispatcher(){override fun dispatch(r:RecordedRequest):MockResponse {
            if(r.method=="GET")return reply(active(source()))
            enabled.set(false);return reply(p.proposal)
        }}
        assertTrue(runCatching{client.publishActive(owner,p,token)}.exceptionOrNull() is CancellationException)
        assertEquals("GET",request().method);assertEquals("PATCH",request().method);assertEquals(2,server.requestCount)
    }
    @Test fun callerCancellationAfterAnAcceptedPatchCannotReturnFinancialPermission()=runTest {
        val p=edit();val caller=Job()
        server.dispatcher=object:Dispatcher(){override fun dispatch(r:RecordedRequest):MockResponse {
            if(r.method=="GET")return reply(active(source()))
            caller.cancel();return reply(p.proposal)
        }}
        try {
            assertTrue(runCatching{withContext(caller){client.publishActive(owner,p,token)}}.exceptionOrNull() is CancellationException)
            assertEquals("GET",request().method);assertEquals("PATCH",request().method);assertEquals(2,server.requestCount)
        } finally {caller.cancel()}
    }

}
