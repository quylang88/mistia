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
class InvestmentCashEventPublicationIntegrationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val linked="22222222-2222-4222-8222-222222222222"
    private val selected="33333333-3333-4333-8333-333333333333"
    private val newborn="88888888-8888-4888-8888-888888888888"
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
    private lateinit var coordinator:InvestmentCashEventPushCoordinator
    private lateinit var remote:InvestmentCashEventRemote
    private lateinit var ordinaryRemote:SupabasePostgrestRemoteStore
    private lateinit var walletPrerequisiteRemote:WalletInvestmentPrerequisiteRemote
    private lateinit var rootPublisher:InvestmentWalletPushCoordinator
    private val backend=Collections.synchronizedMap(linkedMapOf<Pair<String,String>,CloudRecord>())
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private var onCommit:(suspend ()->Unit)?=null
    private var loseWalletReply=false
    private var onWalletCommit:(suspend ()->Unit)?=null
    private var loseReply=false
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
            put("wallet_id",linked);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",300);put("accounting_amount_minor",300);put("currency_code","VND");put("accounting_currency_code","VND")
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
        remote=SupabaseInvestmentCashEventClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        val config=SupabaseConfig(server.url("/").toString(),"local-publishable-key")
        ordinaryRemote=SupabasePostgrestRemoteStore(config,http,writableEntities=setOf(CloudEntity.LEDGER_WALLET))
        walletPrerequisiteRemote=SupabaseWalletInvestmentPrerequisiteClient(config,http,{session},{enabled})
        rootPublisher=InvestmentWalletPushCoordinator(store,SupabaseInvestmentWalletClient(config,http,{session},{enabled}),true,{session},{clock})
        coordinator=InvestmentCashEventPushCoordinator(store,remote,true,{session},{clock})
    }
    @After fun close(){server.shutdown();db.close()}
    private fun reply(rows:List<CloudRecord>)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests+=request
            assertEquals("Bearer "+session?.accessToken,request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
            val url=request.requestUrl!!;val path=url.encodedPath
            if(request.method=="GET") {
                assertEquals("eq.${owner.value}",url.queryParameter("user_id"))
                val table=url.pathSegments.last();val exact=url.queryParameter("id")?.takeIf{it.startsWith("eq.")}?.removePrefix("eq.")
                val cursor=url.queryParameter("id")?.takeIf{it.startsWith("gt.")}?.removePrefix("gt.")
                val id=url.queryParameter("event_id")?.removePrefix("eq.")
                return reply(synchronized(backend){backend.values.filter{it.entity==table && (exact==null || it.id==exact) && (cursor==null || it.id>cursor) && (id==null || it.payload.financeRawString("event_id")==id)}.sortedBy{it.id}.take(1).map{row->
                    if(corruptPosting && row.entity==CloudEntity.INVESTMENT_POSTING.table)row.copy(payload=JsonObject(row.payload+("accounting_amount_minor" to JsonPrimitive(999)))) else row
                }})
            }
            if(request.method in setOf("PATCH","POST") && path=="/rest/v1/ledger_wallets") {
                val element=Json.parseToJsonElement(request.body.clone().readUtf8());val body=if(element is JsonArray)element.single().jsonObject else element.jsonObject
                val id=url.queryParameter("id")?.removePrefix("eq.") ?: requireNotNull(body.financeRawString("id"))
                assertTrue(id in setOf(investmentSystemWalletId(owner),linked,selected,newborn))
                assertTrue(body.keys.none{it.startsWith("_mistia_android_")})
                val previous=backend[CloudEntity.LEDGER_WALLET.table to id]
                if(request.method=="POST") {
                    assertNull(request.getHeader("Prefer")?.takeIf{it.contains("merge-duplicates")})
                    if(previous!=null)return MockResponse().setResponseCode(409)
                } else {
                    assertEquals("eq.${owner.value}",url.queryParameter("user_id"))
                    assertEquals("eq.${previous!!.syncVersion}",url.queryParameter("sync_version"))
                }
                // Mirror only the already independently verified SQL archive rule;
                // this fixture is not a replacement for the real PostgreSQL race oracle.
                if(id!=investmentSystemWalletId(owner) && body.financeRawArchived()==true) {
                    val retained=backend.values.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.deletedAt==null &&
                        it.payload.financeRawString("wallet_id")==id && it.payload.financeRawString("cash_bucket_raw_value")!=null}
                        .fold(java.math.BigInteger.ZERO){sum,row->sum+requireNotNull(row.payload.financeRawLong("accounting_amount_minor")).toBigInteger()}
                    if(retained!=java.math.BigInteger.ZERO)return MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"Move or adjust the investment cash held by this wallet first"}""")
                }
                val version=(previous?.syncVersion ?: 0L)+1
                val payload=JsonObject((previous?.payload ?: JsonObject(emptyMap()))+body+buildJsonObject{put("sync_version",version);put("updated_at","2026-10-28T00:30:00Z")})
                val saved=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,payload,"2026-10-28T00:30:00Z",null,version)
                backend[saved.entity to saved.id]=saved
                val callback=onWalletCommit;onWalletCommit=null;if(callback!=null)runBlocking{callback()}
                if(loseWalletReply){loseWalletReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                return reply(listOf(saved))
            }
            assertEquals("POST",request.method);assertEquals("/rest/v1/rpc/mutate_investment_cash_event",path)
            val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject;assertEquals(JsonPrimitive(false),body["p_force"])
            failure?.let{failure=null;return MockResponse().setResponseCode(it).setBody(failureBody)}
            val incoming=(body["p_transaction"] as? JsonObject)
            if(incoming!=null && incoming.financeRawString("deleted_at")==null) {
                for(key in listOf("source_wallet_id","destination_wallet_id")) {
                    val wallet=backend[CloudEntity.LEDGER_WALLET.table to incoming.financeRawString(key)]
                    if(wallet==null || wallet.deletedAt!=null || wallet.payload.financeRawArchived()!=false)
                        return MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"investment_cash_invalid_selected_wallet"}""")
                }
            }
            val id=incoming?.financeRawString("id") ?: body.financeRawString("p_transaction_id")!!
            val old=backend[CloudEntity.LEDGER_TRANSACTION.table to id];val base=body.financeRawLong("p_expected_version")!!
            if((old?.syncVersion ?: 0)!=base)return reply(emptyList())
            val postingId=investmentLedgerIdentity(id,"cash-transfer-posting");val previous=backend[CloudEntity.INVESTMENT_POSTING.table to postingId]
            body["p_expected_posting_versions"]!!.jsonObject[postingId]?.let{assertEquals(previous!!.syncVersion,it.jsonPrimitive.long)}
            val saved:CloudRecord
            if(incoming==null) {
                if(old==null || old.deletedAt!=null)return reply(emptyList())
                val date=body.financeRawString("p_deleted_at")!!
                val all=synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id && it.deletedAt==null}}
                for(row in all)backend[row.entity to row.id]=row.copy(syncVersion=row.syncVersion+1,updatedAt=date,deletedAt=date,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",row.syncVersion+1);put("updated_at",date);put("deleted_at",date);put("last_modified_by_device_id",device)}))
                saved=old.copy(syncVersion=base+1,updatedAt=date,deletedAt=date,payload=JsonObject(old.payload+buildJsonObject{put("sync_version",base+1);put("updated_at",date);put("deleted_at",date);put("last_modified_by_device_id",device)}))
            } else {
                assertTrue(incoming.keys.none{it.startsWith("_mistia_android_")})
                val supplied=body["p_postings"]!!.jsonArray.single().jsonObject
                val pv=(previous?.syncVersion ?: 0)+1;val created=previous?.payload?.get("created_at") ?: incoming.getValue("created_at")
                val post=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,JsonObject(supplied+buildJsonObject{put("sync_version",pv);put("created_at",created);put("updated_at",incoming.getValue("updated_at"))}),incoming.financeRawString("updated_at"),null,pv)
                backend[post.entity to post.id]=post
                saved=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,JsonObject(incoming+("sync_version" to JsonPrimitive(base+1))),incoming.financeRawString("updated_at"),null,base+1)
            }
            backend[saved.entity to saved.id]=saved
            val callback=onCommit;onCommit=null;if(callback!=null)runBlocking{callback()}
            if(loseReply){loseReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
            return reply(listOf(saved))
        }
    }
    private suspend fun snapshot()=store.investmentCashEventPublicationSnapshot(owner,event)
    private suspend fun create(direction:InvestmentCashTransferDirection=InvestmentCashTransferDirection.DEPOSIT,sameWallet:Boolean=false,selectedId:String=selected) {
        val view=readInvestmentCashTransfer(store.investmentCashSnapshot(owner),direction,if(sameWallet)linked else selectedId,if(direction==InvestmentCashTransferDirection.DEPOSIT)50 else 20)
        repo.saveCashTransfer(owner,InvestmentCashTransferRequest(view.system,view.linked,view.selected,
            InvestmentCashTransferDraft(event,direction,view.selected.id,if(direction==InvestmentCashTransferDirection.DEPOSIT)50 else 20,null,now,now),view.preview,"Cash event"),device,"2026-10-27T00:05:00Z").getOrThrow()
    }
    private suspend fun push()=coordinator.pushPending(owner,session!!.accessToken)
    @Test fun actualDepositPublishesOneAtomicEventAndClearsItsCanonicalPair()=runBlocking {
        create();assertEquals(2,snapshot().pending.size)
        assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
        assertEquals(50L,backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!.payload.financeRawLong("amount_minor"))
        val post=backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(event,"cash-transfer-posting")]!!
        assertEquals(50L,post.payload.financeRawLong("accounting_amount_minor"));assertEquals(now,post.payload.financeRawString("created_at"))
        assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun actualWithdrawalUsesTheNegativeCanonicalAllocationAndPairedLedgerAmounts()=runBlocking {
        create(InvestmentCashTransferDirection.WITHDRAWAL);assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
        val post=backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(event,"cash-transfer-posting")]!!
        assertEquals(-20L,post.payload.financeRawLong("amount_minor"));assertEquals(-20L,post.payload.financeRawLong("accounting_amount_minor"))
    }
    @Test fun sameWalletDepositChangesAllocationWithoutInventingActualCashMovement()=runBlocking {
        create(sameWallet=true);assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
        val row=backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!
        assertEquals(linked,row.payload.financeRawString("source_wallet_id"));assertEquals(linked,row.payload.financeRawString("destination_wallet_id"))
    }
    private suspend fun edit(amount:Long=40,note:String="Edited event") {
        val view=readInvestmentCashTransferLifecycle(store.investmentCashSnapshot(owner),event,requestedMinor=amount)
        val request=InvestmentCashTransferRequest(view.baseline.system,view.baseline.linked,view.baseline.selected,
            view.event.draft.copy(amountMinor=amount,note=note),view.baseline.preview,"Edited cash event")
        repo.changeCashTransfer(owner,InvestmentCashTransferLifecycleRequest.Save(view.event,request),device,"2026-10-27T00:06:00Z").getOrThrow()
    }
    private suspend fun delete() {
        val view=readInvestmentCashTransferLifecycle(store.investmentCashSnapshot(owner),event)
        val request=InvestmentCashTransferRequest(view.baseline.system,view.baseline.linked,view.baseline.selected,view.event.draft,view.baseline.preview,view.event.title)
        repo.changeCashTransfer(owner,InvestmentCashTransferLifecycleRequest.Delete(view.event,request),device,"2026-10-27T00:07:00Z").getOrThrow()
    }
    @Test fun actualPublishedEventCanBeEditedThenRetiredThroughTheSameAtomicRpc()=runBlocking {
        create();assertEquals(1,push().pushed);edit();assertEquals(1,push().pushed)
        assertEquals(40L,backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!.payload.financeRawLong("amount_minor"))
        delete();assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
        assertNotNull(backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!.deletedAt)
        assertNotNull(backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(event,"cash-transfer-posting")]!!.deletedAt)
        assertEquals(3,requests.count{it.method=="POST"})
        assertTrue(requests.filter{it.method=="POST"}.all{!it.body.clone().readUtf8().contains(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY)})
    }
    @Test fun aNeverPublishedDeletionRequiresBothAbsenceReadsAndSendsNoWrite()=runBlocking {
        create();delete();assertEquals(1,push().acknowledged);assertTrue(snapshot().pending.isEmpty());assertTrue(requests.none{it.method=="POST"})
        assertTrue(requests.any{it.requestUrl!!.encodedPath=="/rest/v1/investment_wallet_postings"})
    }
    @Test fun aLostCommittedReplyBacksOffThenRecoversTheWholePairWithoutReplayingTheWrite()=runBlocking {
        create();loseReply=true
        assertEquals(1,push().retryableFailures);val q=snapshot().requestedQueue!!
        assertEquals(1,q.attemptCount);assertEquals(40000L,q.nextAttemptAtEpochMillis)
        val count=requests.size;assertEquals(DomainPushSummary(),push());assertEquals(count,requests.size)
        clock=40000;assertEquals(1,push().acknowledged);assertTrue(snapshot().pending.isEmpty());assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun aNewerActualEditSurvivesTheOldReplyAndPublishesUsingItsConfirmedVersion()=runBlocking {
        create();onCommit={edit(40,"Later user intent")}
        assertEquals(1,push().staleResponses);val after=snapshot()
        assertEquals("Later user intent",after.requestedRecord!!.payload.financeRawString("note"));assertEquals(0L,after.requestedQueue!!.mutation.baseVersion)
        assertTrue(isKnownPriorCashEventPublication(after.requestedRecord!!,backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!,device))
        assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty());assertEquals("Later user intent",backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!.payload.financeRawString("note"))
        assertEquals(2,requests.count{it.method=="POST"})
    }
    @Test fun sameOwnerSessionRotationCannotAcknowledgeOrFailTheOldCashQueue()=runBlocking {
        create();onCommit={session=AuthSession(owner,null,"rotated-cash-token","refresh",Long.MAX_VALUE)}
        assertTrue(runCatching{push()}.exceptionOrNull() is CancellationException)
        assertEquals(0,snapshot().requestedQueue!!.attemptCount)
        assertEquals(1,push().acknowledged);assertTrue(snapshot().pending.isEmpty());assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun permissionFailureIsPermanentAndLeavesBothFinancialRowsPending()=runBlocking {
        create();val before=snapshot().rows;failure=403
        assertEquals(1,push().permanentFailures);val after=snapshot();assertEquals(before,after.rows);assertEquals(2,after.pending.size)
        assertEquals(Long.MAX_VALUE,after.requestedQueue!!.nextAttemptAtEpochMillis);assertEquals("http_403",after.requestedQueue!!.lastError)
    }
    @Test fun anInconsistentFinancialReadCannotClearTheLedgerOrPostingAndCanRecoverLater()=runBlocking {
        create();corruptPosting=true
        assertEquals(1,push().retryableFailures);assertEquals(2,snapshot().pending.size)
        corruptPosting=false;clock=40000
        assertEquals(1,push().acknowledged);assertTrue(snapshot().pending.isEmpty());assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun aRoomAcknowledgementFailureMustPropagateWithoutReclassifyingTheNetworkDecision()=runBlocking {
        create();val before=snapshot()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_cash_result BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' BEGIN SELECT RAISE(ABORT, 'cash result insertion failure'); END")
        assertTrue(runCatching{push()}.exceptionOrNull().toString().contains("cash result insertion failure"))
        assertEquals(before,snapshot())
    }

    @Test fun aLocalSourceReadFailureAfterHttpMustNotBeRecordedAsANetworkRetry()=runBlocking {
        create();val before=snapshot();var reads=0;val error=java.io.IOException("Local cash source failed")
        val guarded=object:LocalStore by store {
            override suspend fun investmentCashEventPublicationSnapshot(owner:UserId,eventId:String):InvestmentCashEventPublicationSnapshot {
                if(++reads==3)throw error
                return store.investmentCashEventPublicationSnapshot(owner,eventId)
            }
        }
        coordinator=InvestmentCashEventPushCoordinator(guarded,remote,true,{session},{clock})
        assertSame(error,runCatching{push()}.exceptionOrNull());assertEquals(before,snapshot())
    }

    @Test fun dirtyRootMetadataHoldsTheCashEventUntilItsExactUpstreamAcknowledgement()=runBlocking {
        create();val rootId=investmentSystemWalletId(owner);val row=store.record(owner,CloudEntity.LEDGER_WALLET.table,rootId)!!
        store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_WALLET,rootId,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device))
        val before=snapshot();assertEquals(DomainPushSummary(),push());assertTrue(requests.isEmpty());assertEquals(before,snapshot())
        val rootQ=before.pending.single{it.mutation.recordId==rootId}
        val next=row.copy(syncVersion=2,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(2))))
        assertTrue(store.acknowledgeMutation(rootQ,next));backend[row.entity to row.id]=next
        assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun unrelatedOrdinaryLedgerQueuesAndTheirFinancialRowsRemainUntouched()=runBlocking {
        create();val current=snapshot().requestedRecord!!;val extra="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        val row=current.copy(id=extra,payload=JsonObject(current.payload+buildJsonObject{put("id",extra);put("settlement_role_raw_value",JsonNull)}))
        store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_TRANSACTION,extra,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,0,device))
        val queued=snapshot().pending.single{it.mutation.recordId==extra}
        assertEquals(1,push().pushed);val after=snapshot()
        assertEquals(listOf(queued),after.pending);assertEquals(row,after.rows.single{it.id==extra});assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun aDisabledCoordinatorReadsAndWritesNothingForTheOwnedQueuedEvent()=runBlocking {
        create();val before=snapshot();coordinator=InvestmentCashEventPushCoordinator(store,remote,false,{session},{clock})
        assertEquals(DomainPushSummary(),push());assertEquals(before,snapshot());assertTrue(requests.isEmpty())
    }
    @Test fun aWrongCapturedTokenCannotInspectOrMutateTheOwnedCashQueue()=runBlocking {
        create();val before=snapshot()
        assertTrue(runCatching{coordinator.pushPending(owner,"wrong-token")}.exceptionOrNull() is CancellationException)
        assertEquals(before,snapshot());assertTrue(requests.isEmpty())
    }

    private fun remoteEdit(at:String,actor:String="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",retired:Boolean=false) {
        for(key in listOf(CloudEntity.LEDGER_TRANSACTION.table to event,CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(event,"cash-transfer-posting"))) {
            val row=backend[key]!!
            backend[key]=row.copy(syncVersion=row.syncVersion+1,updatedAt=at,deletedAt=if(retired)at else null,payload=JsonObject(row.payload+buildJsonObject {
                put("sync_version",row.syncVersion+1);put("updated_at",at);put("last_modified_by_device_id",actor);put("deleted_at",if(retired)JsonPrimitive(at) else JsonNull)
                if(row.entity==CloudEntity.LEDGER_TRANSACTION.table)put("note","Other device event")
            }))
        }
    }
    @Test fun aLaterForeignIntentImportsItsCompletePairWithoutReplayingTheLocalEdit()=runBlocking {
        create();assertEquals(1,push().pushed);edit();remoteEdit("2026-10-27T00:10:00Z")
        assertEquals(1,push().acknowledged);assertTrue(snapshot().pending.isEmpty())
        assertEquals("Other device event",snapshot().requestedRecord!!.payload.financeRawString("note"));assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun aLaterLocalIntentPublishesAgainstTheObservedForeignVersion()=runBlocking {
        create();assertEquals(1,push().pushed);edit();remoteEdit("2026-10-27T00:05:00Z")
        assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
        assertEquals("Edited event",backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!.payload.financeRawString("note"))
        val body=Json.parseToJsonElement(requests.last{it.method=="POST"}.body.clone().readUtf8()).jsonObject
        assertEquals(2L,body.financeRawLong("p_expected_version"));assertEquals(JsonPrimitive(2),body["p_expected_posting_versions"]!!.jsonObject[investmentLedgerIdentity(event,"cash-transfer-posting")])
    }
    @Test fun aLaterForeignTombstoneRetiresTheAliveLocalCanonicalPairAtomically()=runBlocking {
        create();assertEquals(1,push().pushed);edit();remoteEdit("2026-10-27T00:10:00Z",retired=true)
        assertEquals(1,push().acknowledged);assertTrue(snapshot().pending.isEmpty());assertNotNull(snapshot().requestedRecord!!.deletedAt)
        assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun anUnknownOwnLaterIntentIsHeldWithoutOverwritingEitherFinancialResult()=runBlocking {
        create();assertEquals(1,push().pushed);edit();remoteEdit("2026-10-27T00:10:00Z",actor=device)
        val before=snapshot().rows;assertEquals(1,push().conflicts);assertEquals(before,snapshot().rows)
        assertEquals(2,snapshot().pending.size);assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun cashCapacityAndDependentEventRejectionsRetainFiniteRetryInsteadOfPermanentFailure()=runBlocking {
        create()
        for(code in listOf("investment_cash_limit_conflict","investment_cash_has_dependent_events")) {
            failure=400;failureBody=buildJsonObject{put("code","P0001");put("message",code);put("details","private diagnostic");put("hint",JsonNull)}.toString()
            assertEquals(1,push().retryableFailures);val q=snapshot().requestedQueue!!
            assertTrue(q.nextAttemptAtEpochMillis in (clock+1) until Long.MAX_VALUE);assertFalse(q.lastError!!.contains("private"))
            clock=q.nextAttemptAtEpochMillis
        }
        assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty())
    }

    @Test fun theCashEventBeyondOneHundredOrdinaryQueuesIsStillPublishedWithoutConsumingThem()=runBlocking {
        create();val current=snapshot().requestedRecord!!;val prior="2026-10-26T00:00:00Z"
        for(index in 1..101) {
            val id=String.format(java.util.Locale.ROOT,"aaaaaaaa-aaaa-4aaa-8aaa-%012d",index)
            val row=current.copy(id=id,updatedAt=prior,payload=JsonObject(current.payload+buildJsonObject {
                put("id",id);put("updated_at",prior);put("settlement_role_raw_value",JsonNull)
            }))
            store.commitMutation(row,PendingMutation(CloudEntity.LEDGER_TRANSACTION,id,owner.value,MutationKind.UPSERT,row.payload,prior,0,device))
        }
        val before=snapshot();assertEquals(103,before.pending.size)
        val ordinary=before.pending.filter{it.mutation.recordId!=event && it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        assertEquals(1,push().pushed);assertEquals(ordinary,snapshot().pending);assertEquals(1,requests.count{it.method=="POST"})
    }
    @Test fun aLostReplyAfterANewerEditRecoversTheRecordedPriorIntentWithoutLosingTheEdit()=runBlocking {
        create();onCommit={edit(40,"Edit during lost reply")};loseReply=true
        assertEquals(1,push().staleResponses);val after=snapshot()
        assertEquals(0,after.requestedQueue!!.attemptCount);assertEquals("Edit during lost reply",after.requestedRecord!!.payload.financeRawString("note"))
        assertEquals(1,push().pushed);assertTrue(snapshot().pending.isEmpty());assertEquals(2,requests.count{it.method=="POST"})
    }
    @Test fun anOrphanedRemoteCanonicalPostingCannotAuthorizeCreatingOrAcknowledgingItsLedger()=runBlocking {
        create();assertEquals(1,push().pushed);edit();backend.remove(CloudEntity.LEDGER_TRANSACTION.table to event)
        val before=snapshot().rows;assertEquals(1,push().conflicts);assertEquals(before,snapshot().rows);assertEquals(2,snapshot().pending.size)
        assertEquals(1,requests.count{it.method=="POST"})
    }

    @Test fun offlineDepositThenArchivePublishesTheAtomicCashEventBeforeSourceWalletRetirement()=runBlocking {
        create()
        OfflineFirstFinanceRepository(store).archiveWallet(owner,RecordId(selected),device,"2026-10-27T00:06:00Z").getOrThrow()
        val wallets=WalletPublicationPushCoordinator(WalletPushCoordinator(store,ordinaryRemote,true,
            investmentWalletSource=store::investmentWalletPublicationSnapshot,investmentRetirementSource=store::investmentTradePublicationSnapshot,
            investmentPrerequisites=WalletInvestmentPrerequisiteCoordinator(store,walletPrerequisiteRemote,true,{session}),nowEpochMillis={clock}),rootPublisher)
        fun empty(entity:CloudEntity)=object:DomainPushCoordinator {
            override val entity=entity
            override suspend fun pushPending(ownerUserId:UserId,accessToken:String)=DomainPushSummary()
        }
        val investments=InvestmentPublicationPushCoordinator(empty(CloudEntity.INVESTMENT_CHANNEL),empty(CloudEntity.INVESTMENT_ASSET),empty(CloudEntity.INVESTMENT_TRADE),cash=coordinator)
        repeat(3){wallets.pushPending(owner,session!!.accessToken);investments.pushPending(owner,session!!.accessToken);clock+=30001}
        assertEquals("cash event and final source archive must finish",0,snapshot().pending.size)
        assertEquals(true,backend[CloudEntity.LEDGER_WALLET.table to selected]!!.payload.financeRawArchived())
        assertEquals(true,store.record(owner,CloudEntity.LEDGER_WALLET.table,selected)!!.payload.financeRawArchived())
        assertEquals(50L,backend[CloudEntity.LEDGER_TRANSACTION.table to event]!!.payload.financeRawLong("amount_minor"))
        assertEquals(50L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(event,"cash-transfer-posting")]!!.payload.financeRawLong("accounting_amount_minor"))
        val mutation=requests.indexOfFirst{it.requestUrl!!.encodedPath.endsWith("mutate_investment_cash_event")}
        val archive=requests.indexOfLast{it.method=="PATCH" && it.requestUrl!!.queryParameter("id")=="eq.$selected"}
        assertTrue(mutation>=0 && archive>mutation)
    }


    private fun retiringWalletPublisher()=WalletPublicationPushCoordinator(WalletPushCoordinator(store,ordinaryRemote,true,
        investmentWalletSource=store::investmentWalletPublicationSnapshot,investmentRetirementSource=store::investmentTradePublicationSnapshot,
        investmentPrerequisites=WalletInvestmentPrerequisiteCoordinator(store,walletPrerequisiteRemote,true,{session}),nowEpochMillis={clock}),rootPublisher)
    private suspend fun newWalletDeposit() {
        OfflineFirstFinanceRepository(store).saveWallet(owner,WalletDraft(id=newborn,name="New cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000),device,now).getOrThrow()
        create(selectedId=newborn)
        OfflineFirstFinanceRepository(store).archiveWallet(owner,RecordId(newborn),device,"2026-10-27T00:06:00Z").getOrThrow()
        assertNull(backend[CloudEntity.LEDGER_WALLET.table to newborn])
    }
    private suspend fun finishNewWalletDeposit() {
        repeat(4){retiringWalletPublisher().pushPending(owner,session!!.accessToken);push();clock+=30001}
        assertTrue("Birth, real cash and final archive must all finish",snapshot().pending.isEmpty())
        assertEquals(true,backend[CloudEntity.LEDGER_WALLET.table to newborn]!!.payload.financeRawArchived())
        assertEquals(true,store.record(owner,CloudEntity.LEDGER_WALLET.table,newborn)!!.payload.financeRawArchived())
        assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.encodedPath=="/rest/v1/ledger_wallets"})
        assertEquals(1,requests.count{it.requestUrl!!.encodedPath.endsWith("mutate_investment_cash_event")})
        val birth=requests.indexOfFirst{it.method=="POST" && it.requestUrl!!.encodedPath=="/rest/v1/ledger_wallets"}
        val cash=requests.indexOfFirst{it.requestUrl!!.encodedPath.endsWith("mutate_investment_cash_event")}
        val archive=requests.indexOfLast{it.method=="PATCH" && it.requestUrl!!.queryParameter("id")=="eq.$newborn"}
        assertTrue(birth>=0 && cash>birth && archive>cash)
    }
    @Test fun anActualNeverPublishedWalletIsCreatedActiveBeforeCashAndFinallyArchived()=runBlocking {
        newWalletDeposit();finishNewWalletDeposit()
    }
    @Test fun aLostOwnWalletBirthReplyBacksOffThenRecoversWithoutAnotherInsert()=runBlocking {
        newWalletDeposit();loseWalletReply=true
        assertEquals(1,retiringWalletPublisher().pushPending(owner,session!!.accessToken).retryableFailures)
        val q=snapshot().pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}
        assertEquals("network_io",q.lastError);assertEquals(40000L,q.nextAttemptAtEpochMillis)
        val before=snapshot();val count=requests.size
        assertEquals(DomainPushSummary(),retiringWalletPublisher().pushPending(owner,session!!.accessToken));assertEquals(DomainPushSummary(),push())
        assertEquals(before,snapshot());assertEquals(count,requests.size)
        clock=40000;finishNewWalletDeposit()
    }
    @Test fun anActualRenameDuringLostBirthReplySurvivesRecoveryAndPublishesItsOwnActiveVersion()=runBlocking {
        newWalletDeposit();loseWalletReply=true
        onWalletCommit={OfflineFirstFinanceRepository(store).saveWallet(owner,WalletDraft(id=newborn,name="Newest name",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000),device,"2026-10-27T00:07:00Z").getOrThrow()}
        assertEquals(1,retiringWalletPublisher().pushPending(owner,session!!.accessToken).staleResponses)
        val row=store.record(owner,CloudEntity.LEDGER_WALLET.table,newborn)!!
        // The second ordinary pass in the same composite cycle recovers our birth.
        assertEquals("Newest name",row.payload.financeRawString("name"));assertEquals(1L,row.syncVersion);assertNotNull(row.payload[LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY])
        finishNewWalletDeposit()
        assertEquals("Newest name",backend[CloudEntity.LEDGER_WALLET.table to newborn]!!.payload.financeRawString("name"))
        val activeEdits=requests.filter{it.method=="PATCH" && it.requestUrl!!.queryParameter("id")=="eq.$newborn"}
            .map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject}.filter{it.financeRawArchived()==false}
        assertEquals(1,activeEdits.size);assertEquals("Newest name",activeEdits.single().financeRawString("name"))
    }
    @Test fun sessionRotationAfterBirthCommitKeepsTheJournalAndTheNewSessionRecoversIt()=runBlocking {
        newWalletDeposit();onWalletCommit={session=session!!.copy(accessToken="rotated-wallet-token")}
        val failure=runCatching{retiringWalletPublisher().pushPending(owner,"cash-integration-token")}.exceptionOrNull()
        assertTrue(failure is CancellationException)
        val q=snapshot().pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}
        assertEquals(0,q.attemptCount);assertEquals(0L,q.mutation.baseVersion)
        assertEquals(true,store.record(owner,CloudEntity.LEDGER_WALLET.table,newborn)!!.payload.financeRawArchived())
        finishNewWalletDeposit()
    }

}
