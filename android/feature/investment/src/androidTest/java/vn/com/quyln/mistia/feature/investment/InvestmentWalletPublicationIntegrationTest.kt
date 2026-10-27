package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.*
import vn.com.quyln.mistia.core.sync.*

/** Actual Room/outbox and closed authenticated HTTPS port against a local contract fixture. */
@RunWith(AndroidJUnit4::class)
class InvestmentWalletPublicationIntegrationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="33333333-3333-3333-3333-333333333333"
    private val oldLink="44444444-4444-4444-4444-444444444444"
    private val newLink="55555555-5555-5555-5555-555555555555"
    private val event="66666666-6666-6666-6666-666666666666"
    private val rootId=investmentSystemWalletId(owner)
    private val now="2026-10-26T00:00:00Z"
    private val serverTime="2026-10-26T00:30:00Z"
    private var session:AuthSession?=AuthSession(owner,null,"root-contract-token","refresh",Long.MAX_VALUE)
    private var clock=4000L
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private lateinit var server:MockWebServer
    private lateinit var coordinator:InvestmentWalletPushCoordinator
    private lateinit var rootRemote:SupabaseInvestmentWalletClient
    private lateinit var ordinaryRemote:SupabasePostgrestRemoteStore
    private val ordinaryBackend=mutableMapOf<String,CloudRecord>()
    private var backend:CloudRecord?=null
    private var rootHttpStatus:Int?=null
    private var loseReply=false
    private var onWrite:(suspend ()->Unit)?=null
    private var onOrdinaryFetch:(suspend ()->Unit)?=null
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private fun wallet(id:String)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record
    private fun root(v:Long=0,link:String?=oldLink,date:String=now,actor:String=device)=wallet(rootId).let{it.copy(syncVersion=v,updatedAt=date,payload=JsonObject(it.payload+buildJsonObject {
        put("name","Investment wallet");put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")
        put("opening_balance_minor",0);put("investment_linked_wallet_id",link?.let(::JsonPrimitive) ?: JsonNull)
        put("current_balance_minor",9876543210L);put("sync_version",v);put("updated_at",date);put("last_modified_by_device_id",actor)
    }))}
    private fun mutation(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device)
    private fun response(row:CloudRecord?)=MockResponse().setBody(JsonArray(listOfNotNull(row?.payload)).toString())
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={session?.userId});repo=OfflineFirstInvestmentRepository(store)
        for(id in listOf(oldLink,newLink)) {
            val raw=wallet(id);store.commitMutation(raw,mutation(raw))
            val q=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==id}
            val confirmed=raw.copy(syncVersion=1,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(1))))
            assertTrue(store.acknowledgeMutation(q,confirmed));ordinaryBackend[id]=confirmed
        }
        val raw=root();store.commitMutation(raw,mutation(raw))
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);dispatcher=fixture();start()}
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager)
            .retryOnConnectionFailure(false).callTimeout(5,TimeUnit.SECONDS).build()
        val config=SupabaseConfig(server.url("/").toString(),"local-publishable-key")
        rootRemote=SupabaseInvestmentWalletClient(config,http,{session},{true})
        ordinaryRemote=SupabasePostgrestRemoteStore(config,http,writableEntities=setOf(CloudEntity.LEDGER_WALLET))
        coordinator=InvestmentWalletPushCoordinator(store,rootRemote,true,{session},{clock})
    }
    @After fun close(){server.shutdown();db.close()}
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests.add(request)
            if(request.requestUrl!!.encodedPath!="/rest/v1/ledger_wallets")return MockResponse().setResponseCode(404)
            val queryId=request.requestUrl!!.queryParameter("id")?.removePrefix("eq.")
            if(request.method=="GET") {
                val result=if(queryId==rootId)backend else ordinaryBackend[queryId]
                if(queryId!=rootId) {val callback=onOrdinaryFetch;onOrdinaryFetch=null;if(callback!=null)runBlocking{callback()}}
                return response(result)
            }
            val payload=Json.parseToJsonElement(request.body.clone().readUtf8()).let{if(it is JsonArray)it.single().jsonObject else it.jsonObject}
            val id=queryId ?: payload.financeRawString("id") ?: return MockResponse().setResponseCode(400)
            val existing=if(id==rootId)backend else ordinaryBackend[id]
            if(id!=rootId) {
                if(request.method=="POST" && existing!=null)return MockResponse().setResponseCode(409)
                if(request.method=="PATCH" && request.requestUrl!!.queryParameter("sync_version")!="eq."+existing?.syncVersion)return response(null)
                val p=JsonObject(existing?.payload.orEmpty()+payload+("updated_at" to JsonPrimitive(serverTime)))
                // Effective enforce_investment_linked_wallet SQL rejects retirement while cloud root still links it.
                if(backend?.payload?.financeRawString("investment_linked_wallet_id")==id &&
                    (p.financeRawArchived()==true || p.financeRawString("deleted_at")!=null ||
                        p["currency_code"]!=existing?.payload?.get("currency_code") || p["kind_raw_value"]!=existing?.payload?.get("kind_raw_value")))
                    return MockResponse().setResponseCode(400).setBody("{\"code\":\"P0001\",\"message\":\"Unlink this wallet before archiving it\"}")
                val row=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,p,serverTime,p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
                ordinaryBackend[id]=row;return response(row)
            }
            rootHttpStatus?.let{return MockResponse().setResponseCode(it)}
            val desiredLink=payload.financeRawString("investment_linked_wallet_id")
            if(desiredLink!=null && ordinaryBackend[desiredLink]?.payload?.financeRawArchived()!=false)return MockResponse().setResponseCode(400)
            if(request.method=="POST" && existing!=null)return MockResponse().setResponseCode(409)
            if(request.method=="PATCH" && request.requestUrl!!.queryParameter("sync_version")!="eq."+existing?.syncVersion)return response(null)
            val p=JsonObject((existing?.payload.orEmpty()+payload)+buildJsonObject {
                put("name","Investment Wallet");put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")
                put("opening_balance_minor",0);put("icon_symbol_name","chart.line.uptrend.xyaxis");put("icon_color_hex","#9A67FF")
                put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull);put("sort_order",2147483547)
                put("is_archived",false);put("archived_at",JsonNull);put("current_balance_minor",9876543210L);put("updated_at",serverTime)
            })
            backend=CloudRecord(CloudEntity.LEDGER_WALLET.table,rootId,owner.value,p,serverTime,null,requireNotNull(p.financeRawLong("sync_version")))
            val callback=onWrite;onWrite=null
            if(callback!=null)runBlocking{callback()}
            if(loseReply){loseReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
            return response(backend)
        }
    }
    private suspend fun push()=coordinator.pushPending(owner,session!!.accessToken)
    private suspend fun pushBoth(investmentEnabled:Boolean=true,ordinaryEnabled:Boolean=true)=WalletPublicationPushCoordinator(
        WalletPushCoordinator(store,ordinaryRemote,ordinaryEnabled,investmentWalletSource=if(investmentEnabled)store::investmentWalletPublicationSnapshot else null,nowEpochMillis={clock}),
        InvestmentWalletPushCoordinator(store,rootRemote,investmentEnabled,{session},{clock}),
    ).pushPending(owner,session!!.accessToken)
    private suspend fun chooseNewLink() {
        val current=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,rootId)!!)
        val target=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,newLink)!!)
        repo.changeLinkedWallet(owner,InvestmentWalletLinkRequest(current,target,event,false,0,"Move cash"),device,"2026-10-26T00:15:00Z").getOrThrow()
    }
    private fun writes()=requests.filter{it.method in setOf("POST","PATCH")}
    private fun assertAuthenticated() {
        for(r in requests) {
            assertEquals("Bearer root-contract-token",r.getHeader("Authorization"));assertEquals("local-publishable-key",r.getHeader("apikey"))
            assertEquals("eq."+owner.value,r.requestUrl!!.queryParameter("user_id"))
            if(r.method!="POST")assertEquals("eq."+rootId,r.requestUrl!!.queryParameter("id"))
        }
    }
    @Test fun actualRootMetadataAckDoesNotWriteDerivedBalancesOrConsumeFinancialQueues()=runBlocking {
        val domains=listOf(CloudEntity.INVESTMENT_TRADE,CloudEntity.INVESTMENT_POSTING,CloudEntity.LEDGER_TRANSACTION)
        for((index,entity) in domains.withIndex()) {
            val id="77777777-7777-7777-7777-77777777777"+index
            val raw=CloudRecord(entity.table,id,owner.value,buildJsonObject{put("id",id);put("user_id",owner.value);put("updated_at",now);put("sync_version",0);put("deleted_at",JsonNull)},now,null,0)
            store.commitMutation(raw,mutation(raw))
        }
        val before=domains.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
        assertEquals(1,push().pushed);assertNull(store.investmentWalletPublicationSnapshot(owner).pending)
        assertEquals(before,domains.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)})
        val sent=Json.parseToJsonElement(writes().single().body.clone().readUtf8()).jsonArray.single().jsonObject
        assertFalse("current_balance_minor" in sent);assertEquals(JsonPrimitive(0),sent["opening_balance_minor"])
        assertEquals(backend,store.record(owner,CloudEntity.LEDGER_WALLET.table,rootId));assertAuthenticated()
    }
    @Test fun anOrdinaryWalletBacklogCannotStarveTheCanonicalRoot()=runBlocking {
        val rows=(0 until 105).map{index->wallet("88888888-8888-8888-8888-"+index.toString().padStart(12,'0')).let{row->
            row.copy(updatedAt="2026-10-25T00:00:00Z",payload=JsonObject(row.payload+("updated_at" to JsonPrimitive("2026-10-25T00:00:00Z"))))
        }}
        store.commitMutations(rows.map{it to mutation(it)})
        assertFalse(store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE,100).any{it.mutation.recordId==rootId})
        val before=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE,1000).filter{it.mutation.recordId!=rootId}
        assertEquals(1,push().pushed)
        assertEquals(before,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE,1000))
        assertEquals(1,writes().size);assertAuthenticated()
    }
    @Test fun aLaterServerClockCannotEraseTheConcurrentLinkedChoiceOnTheNextCycle()=runBlocking {
        onWrite={chooseNewLink()}
        assertEquals(1,push().staleResponses)
        assertEquals(newLink,store.investmentWalletPublicationSnapshot(owner).record!!.payload.financeRawString("investment_linked_wallet_id"))
        assertEquals(1,push().pushed)
        assertEquals(newLink,store.investmentWalletPublicationSnapshot(owner).record!!.payload.financeRawString("investment_linked_wallet_id"))
        assertNull(store.investmentWalletPublicationSnapshot(owner).pending);assertAuthenticated()
    }
    @Test fun aLostReplyCannotEraseTheConcurrentLinkedChoiceOnRetry()=runBlocking {
        loseReply=true;onWrite={chooseNewLink()}
        assertEquals(1,push().staleResponses);clock=100_000
        assertEquals(1,push().pushed)
        assertEquals(newLink,store.investmentWalletPublicationSnapshot(owner).record!!.payload.financeRawString("investment_linked_wallet_id"))
        assertEquals(2,writes().size)
    }
    @Test fun aDefiniteWriteAgainstAHigherRemoteBaseProtectsTheConcurrentChoice()=runBlocking {
        backend=root(7,null,"2026-10-25T00:00:00Z","99999999-9999-9999-9999-999999999999")
        onWrite={chooseNewLink()}
        assertEquals(1,push().staleResponses);assertEquals(8L,backend!!.syncVersion)
        assertEquals(1,push().pushed)
        assertEquals(9L,backend!!.syncVersion);assertEquals(newLink,backend!!.payload.financeRawString("investment_linked_wallet_id"))
    }
    @Test fun rootPreflightUnlinksBeforeRetiringThePreviouslyLinkedOrdinaryWallet()=runBlocking {
        backend=root(7,oldLink,"2026-10-25T00:00:00Z","99999999-9999-9999-9999-999999999999")
        chooseNewLink()
        val old=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,oldLink)!!)
        val archived=old.toArchiveMutation(device,"2026-10-26T00:16:00Z")
        store.commitMutation(archived.record,archived.pending)
        val result=pushBoth()
        assertEquals(0,result.permanentFailures);assertEquals(2,result.pushed)
        assertEquals(newLink,backend!!.payload.financeRawString("investment_linked_wallet_id"))
        assertEquals(true,ordinaryBackend[oldLink]!!.payload.financeRawArchived())
        assertTrue(store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).isEmpty())
        assertEquals(listOf(rootId,oldLink),writes().map{it.requestUrl!!.queryParameter("id")?.removePrefix("eq.")})
    }
    @Test fun aDirtyNewTargetAndOldWalletRetirementCompleteInOneCycleWithoutPermanentFailure()=runBlocking {
        backend=root(7,oldLink,"2026-10-25T00:00:00Z","99999999-9999-9999-9999-999999999999")
        val fresh=wallet(newLink);store.commitMutation(fresh,mutation(fresh));ordinaryBackend.remove(newLink)
        chooseNewLink()
        val old=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,oldLink)!!)
        val archived=old.toArchiveMutation(device,"2026-10-26T00:16:00Z");store.commitMutation(archived.record,archived.pending)
        val result=pushBoth()
        assertEquals(0,result.permanentFailures);assertEquals(3,result.pushed)
        assertTrue(store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).isEmpty())
        assertEquals(newLink,backend!!.payload.financeRawString("investment_linked_wallet_id"))
        assertEquals(true,ordinaryBackend[oldLink]!!.payload.financeRawArchived())
        assertEquals(listOf(newLink,rootId,oldLink),writes().map{request->
            request.requestUrl!!.queryParameter("id")?.removePrefix("eq.") ?:
                Json.parseToJsonElement(request.body.clone().readUtf8()).jsonArray.single().jsonObject.financeRawString("id")
        })
    }
    @Test fun failedRootPublicationKeepsOldWalletRetirementRetryableWithoutSendingIt()=runBlocking {
        backend=root(7,oldLink,"2026-10-25T00:00:00Z","99999999-9999-9999-9999-999999999999")
        val fresh=wallet(newLink);store.commitMutation(fresh,mutation(fresh));ordinaryBackend.remove(newLink);chooseNewLink()
        val old=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,oldLink)!!)
        val archived=old.toArchiveMutation(device,"2026-10-26T00:16:00Z");store.commitMutation(archived.record,archived.pending)
        val before=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==oldLink}
        rootHttpStatus=503;val first=pushBoth()
        assertEquals(0,first.permanentFailures);assertEquals(1,first.retryableFailures);assertEquals(1,first.pushed)
        assertEquals(before,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==oldLink})
        assertFalse(writes().any{it.requestUrl!!.queryParameter("id")=="eq."+oldLink})
        clock=100000;rootHttpStatus=null;assertEquals(2,pushBoth().pushed)
        assertTrue(store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).isEmpty())
        assertEquals(newLink,backend!!.payload.financeRawString("investment_linked_wallet_id"));assertEquals(true,ordinaryBackend[oldLink]!!.payload.financeRawArchived())
    }
    @Test fun aNewTargetBeyondTheOrdinaryDueLimitStillUnlocksTheRoot()=runBlocking {
        val backlog=(0 until 105).map{index->wallet("88888888-8888-8888-8888-"+index.toString().padStart(12,'0')).let{row->
            row.copy(updatedAt="2026-10-25T00:00:00Z",payload=JsonObject(row.payload+("updated_at" to JsonPrimitive("2026-10-25T00:00:00Z"))))
        }}
        store.commitMutations(backlog.map{it to mutation(it)})
        val fresh=wallet(newLink);store.commitMutation(fresh,mutation(fresh));ordinaryBackend.remove(newLink);chooseNewLink()
        assertFalse(store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE,100).any{it.mutation.recordId==newLink})
        val result=pushBoth();assertEquals(0,result.permanentFailures)
        assertEquals(newLink,backend!!.payload.financeRawString("investment_linked_wallet_id"));assertNull(store.investmentWalletPublicationSnapshot(owner).pending)
        val first=writes().first();assertEquals(newLink,Json.parseToJsonElement(first.body.clone().readUtf8()).jsonArray.single().jsonObject.financeRawString("id"))
    }
    @Test fun rootBecomingDirtyDuringOrdinaryFetchDefersItsOldWalletArchiveBeforeHttpWrite()=runBlocking {
        val initial=store.investmentWalletPublicationSnapshot(owner)
        assertTrue(store.acknowledgeInvestmentWalletMutation(initial.pending!!,root(1),initial));backend=root(1)
        val old=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,oldLink)!!)
        val archived=old.toArchiveMutation(device,"2026-10-26T00:16:00Z")
        // Legacy dirty retirement remains recoverable even though current user edits now reject a linked archive.
        restoreLegacyInvestmentFixture(db,listOf(archived.record to archived.pending))
        val before=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single()
        onOrdinaryFetch={chooseNewLink()}
        val ordinary=WalletPushCoordinator(store,ordinaryRemote,true,investmentWalletSource=store::investmentWalletPublicationSnapshot,nowEpochMillis={clock})
        assertEquals(DomainPushSummary(),ordinary.pushPending(owner,session!!.accessToken))
        assertTrue(writes().isEmpty());assertEquals(before,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==oldLink})
        assertEquals(2,pushBoth().pushed);assertEquals(true,ordinaryBackend[oldLink]!!.payload.financeRawArchived())
    }
    @Test fun aDirtyNewTargetIsCreatedBeforeTheRootPointsToIt()=runBlocking {
        val fresh=wallet(newLink);store.commitMutation(fresh,mutation(fresh));ordinaryBackend.remove(newLink)
        chooseNewLink()
        val result=pushBoth()
        assertEquals(2,result.pushed);assertEquals(0,result.permanentFailures)
        assertEquals(newLink,backend!!.payload.financeRawString("investment_linked_wallet_id"))
        assertTrue(store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).isEmpty())
        assertEquals(listOf(newLink,rootId),writes().map{request->
            Json.parseToJsonElement(request.body.clone().readUtf8()).jsonArray.single().jsonObject.financeRawString("id")
        })
    }
    @Test fun disabledInvestmentGateLeavesRootPendingWhileOrdinaryWalletCanPublish()=runBlocking {
        val fresh=wallet(newLink);store.commitMutation(fresh,mutation(fresh));ordinaryBackend.remove(newLink)
        chooseNewLink();val rootBefore=store.investmentWalletPublicationSnapshot(owner).pending
        val result=pushBoth(investmentEnabled=false)
        assertEquals(1,result.pushed);assertNull(backend);assertEquals(rootBefore,store.investmentWalletPublicationSnapshot(owner).pending)
        assertEquals(1,writes().size);assertTrue(requests.all{it.requestUrl!!.queryParameter("id")!="eq."+rootId})
    }
    @Test fun disabledOrdinaryGateLeavesNewTargetAndRootPendingWithoutHttp()=runBlocking {
        val fresh=wallet(newLink);store.commitMutation(fresh,mutation(fresh));ordinaryBackend.remove(newLink)
        chooseNewLink();val before=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)
        assertEquals(DomainPushSummary(),pushBoth(ordinaryEnabled=false))
        assertEquals(before,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE));assertTrue(requests.isEmpty())
    }
    @Test fun sameOwnerTokenRotationInsideRoomAckRollsBackTheSuccessfulHttpReceipt()=runBlocking {
        val before=store.investmentWalletPublicationSnapshot(owner);val original=session
        val guarded=RoomLocalStore(db,currentBillOwner={
            val v=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE record_id = '$rootId'").use{it.moveToFirst();it.getLong(0)}
            if(v>0)session=session!!.copy(accessToken="replacement-token")
            session?.userId
        })
        val subject=InvestmentWalletPushCoordinator(guarded,rootRemote,true,{session},{clock})
        val error=runCatching{subject.pushPending(owner,original!!.accessToken)}.exceptionOrNull()
        assertTrue(error.toString(),error is CancellationException)
        session=original;assertEquals(before,store.investmentWalletPublicationSnapshot(owner));assertNotNull(backend)
    }
    @Test fun sessionRevokedDuringActualWriteCannotAcknowledgeOrFailTheOldQueue()=runBlocking {
        val before=store.investmentWalletPublicationSnapshot(owner);onWrite={session=null}
        assertTrue(runCatching{push()}.exceptionOrNull() is CancellationException)
        session=AuthSession(owner,null,"root-contract-token","refresh",Long.MAX_VALUE)
        assertEquals(before,store.investmentWalletPublicationSnapshot(owner));assertNotNull(backend)
    }
}
