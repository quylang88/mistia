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

/** Actual repository/Room/closed HTTPS; imported legacy profit inputs are explicit fixtures, not an SQL oracle. */
@RunWith(AndroidJUnit4::class)
class InvestmentCashReconciliationPublicationIntegrationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val linked="22222222-2222-4222-8222-222222222222"
    private val selected="33333333-3333-4333-8333-333333333333"
    private val device="44444444-4444-4444-8444-444444444444"
    private val event="55555555-5555-4555-8555-555555555555"
    private val now="2026-10-27T00:00:00Z"
    private var clock=10000L
    private var enabled=true
    private var session:AuthSession?=AuthSession(owner,null,"cash-integration-token","refresh",Long.MAX_VALUE)
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private lateinit var server:MockWebServer
    private lateinit var coordinator:InvestmentCashReconciliationPushCoordinator
    private lateinit var remote:InvestmentCashReconciliationRemote
    private val backend=Collections.synchronizedMap(linkedMapOf<Pair<String,String>,CloudRecord>())
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private var onCommit:(suspend ()->Unit)?=null
    private var loseReply=false
    private var loseLedger=false
    private var postCalls=0
    private var ledgerCalls=0
    private var failure:Int?=null
    private var failureBody=""
    private var corruptPosting=false
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={session?.userId});repo=OfflineFirstInvestmentRepository(store)
        fun wallet(id:String)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,now).record
        val root=wallet(investmentSystemWalletId(owner)).let{it.copy(payload=JsonObject(it.payload+buildJsonObject {
            put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",linked);put("opening_balance_minor",0)
            put("name","Investment wallet");put("icon_symbol_name","chart.line.uptrend.xyaxis");put("icon_color_hex","#9A67FF");put("sort_order",2147483547)
            put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull)
        }))}
        fun imported(entity:CloudEntity,id:String,fields:JsonObject)=CloudRecord(entity.table,id,owner.value,JsonObject(fields+buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0);put("last_modified_by_device_id",device)
        }),now,null,0)
        val profit=imported(CloudEntity.INVESTMENT_TRADE,"66666666-6666-4666-8666-666666666666",buildJsonObject{put("realized_profit_loss_minor",800);put("accounting_currency_code","VND")})
        val cash=imported(CloudEntity.INVESTMENT_POSTING,"77777777-7777-4777-8777-777777777777",buildJsonObject {
            put("event_id","77777777-7777-4777-8777-777777777778");put("ledger_transaction_id","77777777-7777-4777-8777-777777777778");put("wallet_id",selected);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("occurred_at",now);put("amount_minor",50);put("accounting_amount_minor",50);put("currency_code","VND");put("accounting_currency_code","VND")
        })
        for(row in listOf(root,wallet(linked),wallet(selected),profit,cash)) {
            val entity=CloudEntity.fromTable(row.entity)!!
            store.commitMutation(row,PendingMutation(entity,row.id,owner.value,MutationKind.UPSERT,row.payload,now,0,device))
            val q=store.pendingMutations(owner,entity,Long.MAX_VALUE).single{it.mutation.recordId==row.id}
            val clean=row.copy(syncVersion=1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(1))))
            assertTrue(store.acknowledgeMutation(q,clean));backend[clean.entity to clean.id]=clean
        }
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(cert).build();val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);dispatcher=fixture();start()}
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false).callTimeout(5,TimeUnit.SECONDS).build()
        remote=SupabaseInvestmentCashReconciliationClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        coordinator=InvestmentCashReconciliationPushCoordinator(store,remote,true,{session},{clock})
    }
    @After fun close(){server.shutdown();db.close()}
    private fun reply(rows:List<CloudRecord>)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private val ledgerId get()=investmentLedgerIdentity(event,"cash-reconciliation")
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests+=request
            val url=request.requestUrl!!;val path=url.encodedPath
            assertEquals("Bearer "+session?.accessToken,request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
            if(request.method=="GET") {
                assertEquals("eq.${owner.value}",url.queryParameter("user_id"))
                val table=url.pathSegments.last();val exact=url.queryParameter("id")?.takeIf{it.startsWith("eq.")}?.removePrefix("eq.")
                val cursor=url.queryParameter("id")?.takeIf{it.startsWith("gt.")}?.removePrefix("gt.")
                val eventFilter=url.queryParameter("event_id")?.removePrefix("eq.")
                return reply(synchronized(backend){backend.values.filter{it.entity==table && (exact==null || it.id==exact) && (cursor==null || it.id>cursor) && (eventFilter==null || it.payload.financeRawString("event_id")==eventFilter)}.sortedBy{it.id}.take(1).map{row->
                    if(corruptPosting && row.entity==CloudEntity.INVESTMENT_POSTING.table)row.copy(payload=JsonObject(row.payload+("accounting_amount_minor" to JsonPrimitive(999)))) else row
                }})
            }
            assertEquals("POST",request.method)
            failure?.let{failure=null;return MockResponse().setResponseCode(it).setBody(failureBody)}
            val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
            val saved:List<CloudRecord>
            if(path=="/rest/v1/ledger_transactions") {
                ledgerCalls++;val id=body.financeRawString("id")!!
                if(backend.containsKey(CloudEntity.LEDGER_TRANSACTION.table to id))return MockResponse().setResponseCode(409)
                val row=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,body,body.financeRawString("updated_at"),null,body.financeRawLong("sync_version")!!)
                backend[row.entity to row.id]=row;saved=listOf(row)
            } else {
                assertEquals("/rest/v1/rpc/mutate_investment_cash_postings",path);postCalls++;assertEquals(JsonPrimitive(false),body["p_force"])
                val expected=body["p_expected_versions"]!!.jsonObject
                val incoming=body["p_rows"]!!.jsonArray.map{it.jsonObject};assertEquals(2,incoming.size)
                if(incoming.any{p->val id=p.financeRawString("id")!!;(backend[CloudEntity.INVESTMENT_POSTING.table to id]?.syncVersion ?: 0L)!=expected[id]!!.jsonPrimitive.long})return MockResponse().setResponseCode(409)
                saved=incoming.map{p->CloudRecord(CloudEntity.INVESTMENT_POSTING.table,p.financeRawString("id")!!,owner.value,p,p.financeRawString("updated_at"),null,p.financeRawLong("sync_version")!!)}
                saved.forEach{backend[it.entity to it.id]=it}
            }
            val callback=onCommit;onCommit=null;if(callback!=null)runBlocking{callback()}
            if((path=="/rest/v1/ledger_transactions" && loseLedger) || (path.endsWith("mutate_investment_cash_postings") && loseReply)) {
                loseLedger=false;loseReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)
            }
            return reply(saved)
        }
    }
    private suspend fun snapshot()=store.investmentCashEventPublicationSnapshot(owner,event)
    private suspend fun create(amount:Long=80) {
        val view=readInvestmentCashReconciliation(store.investmentCashSnapshot(owner))
        repo.reconcileCash(owner,InvestmentCashReconciliationRequest(view,listOf(InvestmentCashReconciliationTransfer(event,selected,amount)),now,now,"Reconciliation",true),device,"2026-10-27T00:05:00Z").getOrThrow()
    }
    private suspend fun push()=coordinator.pushPending(owner,session!!.accessToken)
    private fun posts()=backend.values.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==event}
    private suspend fun changedWallet() {
        val row=WalletDraft(id=selected,name="Newer wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,"2026-10-27T00:06:00Z")
        store.commitMutation(row.record,row.pending)
    }
    @Test fun actualRepositoryEightyTransferPublishesLedgerAndFiftyProfitTogether()=runBlocking {
        create();assertEquals(3,snapshot().pending.size);assertEquals(1,push().pushed)
        assertTrue(snapshot().pending.isEmpty());assertEquals(1,ledgerCalls);assertEquals(1,postCalls)
        assertEquals(80L,backend[CloudEntity.LEDGER_TRANSACTION.table to ledgerId]!!.payload.financeRawLong("amount_minor"));assertEquals(setOf(-50L,50L),posts().map{it.payload.financeRawLong("amount_minor")}.toSet())
        assertEquals(0,push().pushed);assertEquals(1,ledgerCalls);assertEquals(1,postCalls)
    }
    @Test fun partialThirtyPublishesOnlyThirtyProfit()=runBlocking {create(30);assertEquals(1,push().pushed);assertEquals(setOf(-30L,30L),posts().map{it.payload.financeRawLong("amount_minor")}.toSet())}
    @Test fun lostLedgerReplyKeepsAllQueuesAndResumesWithoutDuplicateRealTransfer()=runBlocking {
        create();loseLedger=true;assertEquals(1,push().retryableFailures);assertEquals(3,snapshot().pending.size);assertEquals(0,postCalls)
        clock+=30001;assertEquals(1,push().pushed);assertEquals(1,ledgerCalls);assertEquals(1,postCalls);assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun lostPostingReplyRecoversTheWholeSemanticGroupWithoutReplayingBatch()=runBlocking {
        create();loseReply=true;assertEquals(1,push().retryableFailures);assertEquals(3,snapshot().pending.size)
        clock+=30001;assertEquals(1,push().acknowledged);assertEquals(1,ledgerCalls);assertEquals(1,postCalls);assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun newWalletMutationDuringLedgerPreparationStopsBatchAndRetainsAllOriginalQueues()=runBlocking {
        create();onCommit={changedWallet()};assertEquals(1,push().staleResponses);assertEquals(0,postCalls);assertEquals(4,snapshot().pending.size)
    }
    @Test fun newWalletMutationDuringBatchCommitPreventsLateFinancialAck()=runBlocking {
        create();loseLedger=true;push();clock+=30001;onCommit={changedWallet()};assertEquals(1,push().staleResponses);assertEquals(4,snapshot().pending.size)
    }
    @Test fun corruptedPostResultCannotClearAnyFinancialQueue()=runBlocking {
        create();loseReply=true;push();clock+=30001;corruptPosting=true;val result=push();assertEquals(3,snapshot().pending.size);assertEquals(1,result.retryableFailures+result.permanentFailures+result.conflicts)
    }
    @Test fun futureBackoffAndDisabledGateMakeNoNetworkCalls()=runBlocking {
        create();val before=snapshot();val q=before.pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION};assertTrue(store.recordInvestmentCashReconciliationFailure(q,50000,"network_io",before))
        assertEquals(DomainPushSummary(),push());assertTrue(requests.isEmpty())
        coordinator=InvestmentCashReconciliationPushCoordinator(store,remote,false,{session},{clock});clock=60000;assertEquals(DomainPushSummary(),push());assertTrue(requests.isEmpty())
    }
    @Test fun dirtyWalletDependencyDefersBeforeAnyHttp()=runBlocking {create();changedWallet();assertEquals(DomainPushSummary(),push());assertTrue(requests.isEmpty())}
    @Test fun existingDifferentImmutableLedgerIntentIsHeldWithoutOverwrite()=runBlocking {
        create();val row=investmentCashReconciliationGroup(snapshot()).ledger.let{it.copy(syncVersion=2,payload=JsonObject(it.payload+buildJsonObject{put("sync_version",2);put("title","Other intent")}))};backend[row.entity to row.id]=row
        assertEquals(1,push().conflicts);assertEquals(0,ledgerCalls);assertEquals(0,postCalls);assertEquals(3,snapshot().pending.size)
    }
    @Test fun cleanLedgerWithOrphanPostingQueuesCanResumeTheDedicatedGroup()=runBlocking {
        create();val row=investmentCashReconciliationGroup(snapshot()).ledger.let{it.copy(syncVersion=1,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(1))))};backend[row.entity to row.id]=row
        val q=snapshot().pending.single{it.mutation.recordId==row.id};assertTrue(store.acknowledgeMutation(q,row));assertEquals(2,snapshot().pending.size)
        assertEquals(1,push().pushed);assertEquals(0,ledgerCalls);assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun observedMissingLedgerIsNeverRecreated()=runBlocking {
        create();val row=investmentCashReconciliationGroup(snapshot()).ledger.let{it.copy(syncVersion=1,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(1))))}
        val q=snapshot().pending.single{it.mutation.recordId==row.id};assertTrue(store.acknowledgeMutation(q,row))
        assertEquals(1,push().conflicts);assertEquals(0,ledgerCalls);assertEquals(0,postCalls);assertEquals(2,snapshot().pending.size)
    }
    @Test fun sameOwnerSessionRotationDuringLedgerReplyCancelsAndPreservesAllQueues()=runBlocking {
        create();onCommit={session=session!!.copy(accessToken="rotated")};assertTrue(runCatching{push()}.exceptionOrNull() is CancellationException);assertEquals(3,snapshot().pending.size);assertEquals(0,postCalls)
    }
    @Test fun unrelatedHundredAndOneOrdinaryQueuesDoNotStarveReconciliation()=runBlocking {
        create();val original=investmentCashReconciliationGroup(snapshot()).ledger
        repeat(101){n->val id=java.util.UUID(0,1000L+n).toString()
            val row=original.copy(id=id,payload=JsonObject(original.payload+buildJsonObject{put("id",id);put("settlement_role_raw_value",JsonNull)}))
            store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_TRANSACTION,id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,0,device))}
        assertEquals(1,push().pushed);assertEquals(101,snapshot().pending.size);assertTrue(snapshot().pending.all{it.mutation.recordId!=ledgerId})
    }    @Test fun sqlComparedVersionRaceRetriesWithoutRecordingPrivateDiagnostics()=runBlocking {
        create();failure=400;failureBody="""{"code":"P0001","message":"version_conflict","details":"private synthetic details"}"""
        assertEquals(1,push().retryableFailures);val driver=snapshot().pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        assertEquals("version_conflict",driver.lastError);assertEquals(40000L,driver.nextAttemptAtEpochMillis)
        clock+=30001;assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun forbiddenResponseIsPermanentAndCannotConsumeTheFinancialGroup()=runBlocking {
        create();failure=403;failureBody="private details";assertEquals(1,push().permanentFailures)
        assertEquals(3,snapshot().pending.size);val q=snapshot().pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION};assertEquals("http_403",q.lastError);assertEquals(Long.MAX_VALUE,q.nextAttemptAtEpochMillis)
    }
    @Test fun laterAcknowledgedLinkChoiceCannotRedirectTheConfirmedDestination()=runBlocking {
        create();val root=snapshot().rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==investmentSystemWalletId(owner)}
        val changed=root.copy(payload=JsonObject(root.payload+("investment_linked_wallet_id" to JsonPrimitive(selected))))
        store.commitMutation(changed,PendingMutation(CloudEntity.LEDGER_WALLET,root.id,owner.value,MutationKind.UPSERT,changed.payload,changed.updatedAt!!,changed.syncVersion,device))
        val q=snapshot().pending.single{it.mutation.recordId==root.id};val saved=changed.copy(syncVersion=2,payload=JsonObject(changed.payload+("sync_version" to JsonPrimitive(2))))
        assertTrue(store.acknowledgeMutation(q,saved));backend[saved.entity to saved.id]=saved
        assertEquals(1,push().pushed);assertEquals(linked,backend[CloudEntity.LEDGER_TRANSACTION.table to ledgerId]!!.payload.financeRawString("destination_wallet_id"))
        assertEquals(linked,posts().single{it.payload.financeRawLong("amount_minor")==50L}.payload.financeRawString("wallet_id"))
    }
    @Test fun legacyPartialPostingResultUsesEachActuallyObservedComparisonVersion()=runBlocking {
        create();val group=investmentCashReconciliationGroup(snapshot())
        fun saved(row:CloudRecord)=row.copy(syncVersion=1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(1))))
        for(row in listOf(saved(group.ledger),saved(group.holder)))backend[row.entity to row.id]=row
        assertEquals(1,push().pushed);assertEquals(0,ledgerCalls);assertEquals(1,postCalls);assertTrue(snapshot().pending.isEmpty())
        val request=requests.single{it.requestUrl!!.encodedPath.endsWith("mutate_investment_cash_postings")}
        val expected=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject["p_expected_versions"]!!.jsonObject
        assertEquals(JsonPrimitive(1),expected[group.holder.id]);assertEquals(JsonPrimitive(0),expected[group.linked.id])
    }
    @Test fun localAcknowledgementIoPropagatesWithoutFalselyRecordingANetworkRetry()=runBlocking {
        create();val broken=object:LocalStore by store {
            override suspend fun acknowledgeInvestmentCashReconciliationResult(expected:InvestmentCashEventPublicationSnapshot,candidate:InvestmentCashReconciliationCloudSnapshot,isSessionCurrent:()->Boolean):Boolean=throw java.io.IOException("Local database synthetic failure")
        }
        coordinator=InvestmentCashReconciliationPushCoordinator(broken,remote,true,{session},{clock})
        val error=runCatching{push()}.exceptionOrNull();assertTrue(error is java.io.IOException);assertEquals("Local database synthetic failure",error!!.message)
        assertEquals(3,snapshot().pending.size);assertTrue(snapshot().pending.all{it.attemptCount==0 && it.lastError==null})
    }

    @Test fun cleanHistoryDoesNotRescanTheWholeRoomGenerationPerEvent()=runBlocking {
        create();assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty());requests.clear()
        var reads=0
        val counted=object:LocalStore by store {
            override suspend fun investmentCashEventPublicationSnapshot(owner:UserId,eventId:String):InvestmentCashEventPublicationSnapshot {
                reads++;return store.investmentCashEventPublicationSnapshot(owner,eventId)
            }
        }
        coordinator=InvestmentCashReconciliationPushCoordinator(counted,remote,true,{session},{clock})
        assertEquals(DomainPushSummary(),push());assertTrue(requests.isEmpty());assertEquals(1,reads)
    }
    @Test fun cleanPostingsStillIdentifyAndRecoverTheOnlyRemainingLedgerQueue()=runBlocking {
        create();val group=investmentCashReconciliationGroup(snapshot())
        val saved=group.rows.map{it.copy(syncVersion=1,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(1))))}
        for(row in saved) {
            backend[row.entity to row.id]=row
            if(row.entity==CloudEntity.INVESTMENT_POSTING.table) {
                val q=snapshot().pending.single{it.mutation.recordId==row.id};assertTrue(store.acknowledgeMutation(q,row))
            }
        }
        assertEquals(1,snapshot().pending.size);assertEquals(1,push().acknowledged)
        assertTrue(snapshot().pending.isEmpty());assertEquals(0,ledgerCalls);assertEquals(0,postCalls)
    }

}
