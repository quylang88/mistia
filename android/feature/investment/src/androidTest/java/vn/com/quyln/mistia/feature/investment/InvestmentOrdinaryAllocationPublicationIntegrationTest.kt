package vn.com.quyln.mistia.feature.investment

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
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

/** Actual consent/repository/Room and current closed publishers, not an SQL arithmetic oracle. */
@RunWith(AndroidJUnit4::class)
class InvestmentOrdinaryAllocationPublicationIntegrationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-28T00:00:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private var session=AuthSession(owner,null,"ordinary-allocation-test-token","refresh",Long.MAX_VALUE)
    private var clock=10000L
    private var afterOrdinaryCommit:(()->Unit)?=null
    private var afterGenericCommit:(()->Unit)?=null
    private var loseGenericReply=false
    private var capacityFailureEvent:String?=null
    private var loseOrdinaryReply=false
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var finance:OfflineFirstFinanceRepository
    private lateinit var server:MockWebServer
    private lateinit var transactions:TransactionPushCoordinator
    private lateinit var wallets:WalletPushCoordinator
    private lateinit var investments:InvestmentPublicationPushCoordinator
    private lateinit var installmentRemote:InstallmentPaymentPublicationRemote
    private lateinit var cardRemote:CardPaymentPublicationRemote
    private var loseCardReply=false
    private var afterCardCommit:(()->Unit)?=null
    private var loseInstallmentReply=false
    private var afterInstallmentCommit:(()->Unit)?=null
    private lateinit var dueRemote:RemoteMutationStore
    private val backend=Collections.synchronizedMap(linkedMapOf<Pair<String,String>,CloudRecord>())
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner});finance=OfflineFirstFinanceRepository(store)
        finance.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        val parent=finance.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        finance.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val root=WalletDraft(id=investmentSystemWalletId(owner),name="Investment wallet",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).record.let{it.copy(payload=JsonObject(it.payload+buildJsonObject {
            put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1));put("opening_balance_minor",0)
            put("icon_symbol_name","chart.line.uptrend.xyaxis");put("icon_color_hex","#9A67FF");put("sort_order",2147483547)
            put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull)
        }))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now);put("last_modified_by_device_id",device)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60);put("accounting_amount_minor",60);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-28T00:00:01Z")
        },now,null,0)
        // Imported historical booked cash is explicit; its FIFO origin is outside this lifecycle fixture.
        for(row in listOf(root,cash))store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,0,device))
        for(entity in listOf(CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY,CloudEntity.INVESTMENT_POSTING)) {
            for(q in store.pendingMutations(owner,entity,Long.MAX_VALUE)) {
                val row=store.record(owner,entity.table,q.mutation.recordId)!!
                val clean=row.copy(syncVersion=1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(1))))
                assertTrue(store.acknowledgeMutation(q,clean));backend[clean.entity to clean.id]=clean
            }
        }
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(cert).build();val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);dispatcher=fixture();start()}
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false).callTimeout(5,TimeUnit.SECONDS).build()
        val config=SupabaseConfig(server.url("/").toString(),"local-publishable-key")
        installmentRemote=SupabaseInstallmentPaymentPublicationClient(config,http,{session},{true})
        cardRemote=SupabaseCardPaymentPublicationClient(config,http,{session},{true})
        transactions=TransactionPushCoordinator(store,SupabasePostgrestRemoteStore(config,http,writableEntities=setOf(CloudEntity.LEDGER_TRANSACTION)),true,{clock})
        dueRemote=SupabasePostgrestRemoteStore(config,http,writableEntities=setOf(CloudEntity.DUE_OCCURRENCE_RECORD,CloudEntity.TRANSACTION_CATEGORY))
        wallets=WalletPushCoordinator(store,SupabasePostgrestRemoteStore(config,http,writableEntities=setOf(CloudEntity.LEDGER_WALLET)),true,
            nowEpochMillis={clock},investmentWalletSource=store::investmentWalletPublicationSnapshot,investmentRetirementSource=store::investmentTradePublicationSnapshot,
            investmentPrerequisites=WalletInvestmentPrerequisiteCoordinator(store,SupabaseWalletInvestmentPrerequisiteClient(config,http,{session},{true}),true,{session}))
        // These exact current financial coordinators have no channel/asset/trade queues in this fixture.
        fun empty(entity:CloudEntity)=object:DomainPushCoordinator {
            override val entity=entity
            override suspend fun pushPending(ownerUserId:UserId,accessToken:String)=DomainPushSummary()
        }
        investments=InvestmentPublicationPushCoordinator(empty(CloudEntity.INVESTMENT_CHANNEL),empty(CloudEntity.INVESTMENT_ASSET),empty(CloudEntity.INVESTMENT_TRADE),
            InvestmentCashEventPushCoordinator(store,SupabaseInvestmentCashEventClient(config,http,{session},{true}),true,{session},{clock}),
            InvestmentCashReconciliationPushCoordinator(store,SupabaseInvestmentCashReconciliationClient(config,http,{session},{true}),true,{session},{clock}),
            InvestmentLinkedWalletMovePushCoordinator(store,SupabaseInvestmentLinkedWalletMoveClient(config,http,{session},{true}),true,{session},{clock}),
            InvestmentOrdinaryPushCoordinator(store,SupabaseInvestmentOrdinaryClient(config,http,{session},{true}),true,{session},{clock}))
    }
    @After fun close(){server.shutdown();db.close()}
    private fun reply(rows:List<CloudRecord>)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests+=request;assertEquals("Bearer "+session.accessToken,request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
            val url=request.requestUrl!!;val table=url.pathSegments.last()
            if(request.method=="GET") {
                assertEquals("eq.${owner.value}",url.queryParameter("user_id"))
                val exact=url.queryParameter("id")?.takeIf{it.startsWith("eq.")}?.removePrefix("eq.")
                val cursor=url.queryParameter("id")?.takeIf{it.startsWith("gt.")}?.removePrefix("gt.")
                val ids=url.queryParameter("id")?.takeIf{it.startsWith("in.(")}?.removePrefix("in.(")?.removeSuffix(")")?.split(",")?.toSet()
                val event=url.queryParameter("event_id")?.removePrefix("eq.")
                val systemKey=url.queryParameter("system_key")?.removePrefix("eq.")
                val sourceKind=url.queryParameter("source_kind_raw_value")?.removePrefix("eq.")
                val sourceId=url.queryParameter("source_id")?.removePrefix("eq.")
                val selectedMonth=url.queryParameter("selected_month_key")?.removePrefix("eq.")
                val rows=synchronized(backend){backend.values.filter{it.entity==table && (exact==null || it.id==exact) && (ids==null || it.id in ids) && (cursor==null || it.id>cursor) && (event==null || it.payload.financeRawString("event_id")==event) && (systemKey==null || it.payload.financeRawString("system_key")==systemKey) && (sourceKind==null || it.payload.financeRawString("source_kind_raw_value")==sourceKind) && (sourceId==null || it.payload.financeRawString("source_id")==sourceId) && (selectedMonth==null || it.payload.financeRawString("selected_month_key")==selectedMonth)}.sortedBy{it.id}}
                if(systemKey!=null || sourceKind in setOf("installment","creditCard")) {
                    val offset=request.getHeader("Range")!!.substringBefore('-').toInt()
                    val limit=request.getHeader("Range")!!.substringAfter('-').toInt()-offset+1
                    val page=rows.drop(offset).take(limit)
                    return reply(page).setHeader("Content-Range",(if(page.isEmpty())"*"else "$offset-${offset+page.size-1}")+"/"+rows.size)
                }
                return reply(rows.take(if(ids==null)1 else 3))
            }
            if(request.method=="PATCH" && table==CloudEntity.LEDGER_WALLET.table) {
                assertEquals("eq.${owner.value}",url.queryParameter("user_id"))
                val rowId=url.queryParameter("id")!!.removePrefix("eq.")
                val expected=url.queryParameter("sync_version")!!.removePrefix("eq.").toLong()
                val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
                synchronized(backend) {
                    val old=backend[table to rowId] ?: return reply(emptyList())
                    if(old.syncVersion!=expected)return reply(emptyList())
                    val wire=JsonObject(old.payload+body)
                    val saved=old.copy(payload=wire,syncVersion=wire.financeRawLong("sync_version")!!,updatedAt=wire.financeRawString("updated_at"),deletedAt=wire.financeRawString("deleted_at"))
                    backend[table to rowId]=saved;return reply(listOf(saved))
                }
            }
            if(request.method=="POST" && table=="mutate_card_paid_cycle") {
                // Protocol/CAS fixture only; actual SQL financial/identity races
                // are independently exercised against the local85 database.
                val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
                assertEquals(setOf("p_cycle","p_expected_version","p_expected_presence","p_expected_ledger","p_expected_wallets","p_expected_cycles"),body.keys)
                val proposed=body.getValue("p_cycle").jsonObject
                assertEquals(owner.value,proposed.financeRawString("user_id"));assertTrue(proposed.keys.none{it.startsWith("_mistia_android_")})
                fun changed(code:String)=MockResponse().setResponseCode(400).setBody(buildJsonObject{put("code","P0001");put("message",code)}.toString())
                synchronized(backend) {
                    for((arg,entity) in listOf("p_expected_ledger" to CloudEntity.LEDGER_TRANSACTION,"p_expected_wallets" to CloudEntity.LEDGER_WALLET)) {
                        for((rowId,expected) in body.getValue(arg).jsonObject) {
                            val actual=backend[entity.table to rowId]?.payload ?: JsonNull
                            if(actual!=expected)return changed(if(entity==CloudEntity.LEDGER_TRANSACTION)"card_payment_ledger_changed"else"card_payment_wallet_changed")
                        }
                    }
                    val key=CloudEntity.DUE_OCCURRENCE_RECORD.table to requireNotNull(proposed.financeRawString("id"))
                    val old=backend[key];val version=requireNotNull(body.financeRawLong("p_expected_version"))
                    if((old!=null)!=body.getValue("p_expected_presence").jsonPrimitive.boolean || old!=null && old.syncVersion!=version)
                        return changed("card_payment_version_conflict")
                    val all=backend.values.filter{it.entity==key.first && it.ownerUserId==owner.value && it.payload.financeRawString("source_kind_raw_value")=="creditCard" &&
                        it.payload.financeRawString("source_id")==proposed.financeRawString("source_id")}.sortedBy{it.id}
                    if(JsonArray(all.map{it.payload})!=body.getValue("p_expected_cycles"))return changed("card_payment_membership_changed")
                    assertEquals(version+1,proposed.financeRawLong("sync_version"))
                    val wire=if(old==null)proposed else JsonObject(proposed+("updated_at" to JsonPrimitive("2026-10-29T00:00:00Z")))
                    val saved=CloudRecord(key.first,key.second,owner.value,wire,wire.financeRawString("updated_at"),wire.financeRawString("deleted_at"),version+1)
                    backend[key]=saved;afterCardCommit?.also{afterCardCommit=null;it()}
                    if(loseCardReply){loseCardReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                    return MockResponse().setBody(saved.payload.toString())
                }
            }
            if(request.method=="POST" && table=="mutate_installment_paid_cycle") {
                val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
                assertEquals(setOf("p_cycle","p_expected_version","p_expected_presence","p_expected_plan","p_expected_ledger","p_expected_wallet","p_expected_siblings"),body.keys)
                val proposed=body.getValue("p_cycle").jsonObject
                assertEquals(owner.value,proposed.financeRawString("user_id"));assertTrue(proposed.keys.none{it.startsWith("_mistia_android_")})
                synchronized(backend) {
                    fun compared(arg:String,entity:CloudEntity) {
                        val expected=body.getValue(arg).takeUnless{it==JsonNull}?.jsonObject ?: return
                        assertEquals(expected,backend[entity.table to expected.financeRawString("id")]!!.payload)
                    }
                    compared("p_expected_plan",CloudEntity.INSTALLMENT_PLAN);compared("p_expected_ledger",CloudEntity.LEDGER_TRANSACTION);compared("p_expected_wallet",CloudEntity.LEDGER_WALLET)
                    val key=CloudEntity.DUE_OCCURRENCE_RECORD.table to proposed.financeRawString("id")!!
                    val old=backend[key];val version=body.financeRawLong("p_expected_version")!!
                    if((old!=null)!=body.getValue("p_expected_presence").jsonPrimitive.boolean || old!=null && old.syncVersion!=version)
                        return MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"installment_payment_version_conflict"}""")
                    val all=backend.values.filter{it.entity==key.first && it.ownerUserId==owner.value && it.payload.financeRawString("source_kind_raw_value")=="installment" &&
                        it.payload.financeRawString("source_id")==proposed.financeRawString("source_id") && it.payload.financeRawString("selected_month_key")==proposed.financeRawString("selected_month_key")}.sortedBy{it.id}
                    assertEquals(JsonArray(all.map{it.payload}),body.getValue("p_expected_siblings"))
                    assertEquals(version+1,proposed.financeRawLong("sync_version"))
                    val saved=CloudRecord(key.first,key.second,owner.value,proposed,proposed.financeRawString("updated_at"),proposed.financeRawString("deleted_at"),version+1)
                    backend[key]=saved;afterInstallmentCommit?.also{afterInstallmentCommit=null;it()}
                    if(loseInstallmentReply){loseInstallmentReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                    return MockResponse().setBody(saved.payload.toString())
                }
            }
            if(request.method=="POST" && table=="mutate_ordinary_investment_event") {
                // A stateful CAS/protocol fixture. Real SQL validates money and permissions separately.
                val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
                assertEquals(setOf("p_transaction","p_adjustment","p_postings","p_expected_version","p_expected_adjustment_version","p_expected_posting_versions","p_expected_presence"),body.keys)
                val primary=body.getValue("p_transaction").jsonObject
                if(primary.financeRawString("id")==capacityFailureEvent) {
                    capacityFailureEvent=null
                    return MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"ordinary_investment_capacity_conflict"}""")
                }
                val adjustment=body["p_adjustment"]?.takeUnless{it==JsonNull}?.jsonObject
                val postings=body.getValue("p_postings").jsonArray.map{it.jsonObject}
                val proposed=listOf(CloudEntity.LEDGER_TRANSACTION.table to primary)+listOfNotNull(adjustment?.let{CloudEntity.LEDGER_TRANSACTION.table to it})+postings.map{CloudEntity.INVESTMENT_POSTING.table to it}
                val presence=body.getValue("p_expected_presence").jsonObject
                val versions=body.getValue("p_expected_posting_versions").jsonObject
                assertEquals(proposed.map{it.second.financeRawString("id")!!}.toSet(),presence.keys)
                synchronized(backend) {
                    for((entity,payload) in proposed) {
                        val rowId=payload.financeRawString("id")!!
                        assertEquals(owner.value,payload.financeRawString("user_id"));assertTrue(payload.keys.none{it.startsWith("_mistia_android_")})
                        val expected=when { payload===primary->body.financeRawLong("p_expected_version")!!
                            payload===adjustment->body.financeRawLong("p_expected_adjustment_version")!!
                            else->versions.getValue(rowId).jsonPrimitive.long }
                        assertEquals(expected,payload.financeRawLong("sync_version"))
                        val old=backend[entity to rowId]
                        if((old!=null)!=presence.getValue(rowId).jsonPrimitive.boolean || old!=null && old.syncVersion!=expected)
                            return MockResponse().setResponseCode(400).setBody("""{"code":"P0001","message":"ordinary_investment_version_conflict"}""")
                    }
                    val saved=proposed.map{(entity,payload)->
                        val version=payload.financeRawLong("sync_version")!!+1
                        val wire=JsonObject(payload+("sync_version" to JsonPrimitive(version)))
                        CloudRecord(entity,wire.financeRawString("id")!!,owner.value,wire,wire.financeRawString("updated_at"),wire.financeRawString("deleted_at"),version)
                    }
                    saved.forEach{backend[it.entity to it.id]=it}
                    afterOrdinaryCommit?.also{afterOrdinaryCommit=null;it()}
                    if(loseOrdinaryReply){loseOrdinaryReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                    return MockResponse().setBody(buildJsonObject {
                        put("transaction",saved.first().payload)
                        put("adjustment",if(adjustment==null)JsonNull else saved[1].payload)
                        put("postings",JsonArray(saved.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}.map{it.payload}))
                    }.toString())
                }
            }
            if(table in setOf(CloudEntity.DUE_OCCURRENCE_RECORD.table,CloudEntity.TRANSACTION_CATEGORY.table) && request.method in setOf("POST","PATCH")) {
                val raw=Json.parseToJsonElement(request.body.clone().readUtf8())
                val body=if(raw is JsonArray)raw.single().jsonObject else raw.jsonObject
                val rowId=body.financeRawString("id") ?: url.queryParameter("id")!!.removePrefix("eq.")
                synchronized(backend) {
                    val old=backend[table to rowId]
                    if(request.method=="POST" && old!=null)return MockResponse().setResponseCode(409)
                    if(request.method=="PATCH" && (old==null || old.syncVersion!=url.queryParameter("sync_version")!!.removePrefix("eq.").toLong()))return reply(emptyList())
                    val wire=JsonObject(old?.payload.orEmpty()+body)
                    assertEquals(owner.value,wire.financeRawString("user_id"))
                    val saved=CloudRecord(table,rowId,owner.value,wire,wire.financeRawString("updated_at"),wire.financeRawString("deleted_at"),wire.financeRawLong("sync_version")!!)
                    backend[table to rowId]=saved;return reply(listOf(saved))
                }
            }
            if(request.method=="PATCH" && table==CloudEntity.LEDGER_TRANSACTION.table) {
                val rowId=url.queryParameter("id")!!.removePrefix("eq.")
                val expected=url.queryParameter("sync_version")!!.removePrefix("eq.").toLong()
                val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
                assertTrue(body.keys.none{it.startsWith("_mistia_android_")})
                synchronized(backend) {
                    val old=backend[table to rowId] ?: return reply(emptyList())
                    if(old.syncVersion!=expected)return reply(emptyList())
                    val wire=JsonObject(old.payload+body)
                    val saved=old.copy(payload=wire,syncVersion=wire.financeRawLong("sync_version")!!,updatedAt=wire.financeRawString("updated_at"),deletedAt=wire.financeRawString("deleted_at"))
                    backend[table to rowId]=saved;afterGenericCommit?.also{afterGenericCommit=null;it()}
                    if(loseGenericReply){loseGenericReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                    return reply(listOf(saved))
                }
            }
            if(request.method=="POST" && table==CloudEntity.LEDGER_TRANSACTION.table) {
                val wire=Json.parseToJsonElement(request.body.clone().readUtf8())
                val body=if(wire is JsonArray)wire.single().jsonObject else wire.jsonObject
                assertEquals(owner.value,body.financeRawString("user_id"));assertTrue(body.keys.none{it.startsWith("_mistia_android_")})
                val key=table to body.financeRawString("id")!!
                if(backend.containsKey(key))return MockResponse().setResponseCode(409)
                val saved=CloudRecord(table,key.second,owner.value,body,body.financeRawString("updated_at"),null,body.financeRawLong("sync_version")!!)
                backend[key]=saved;afterGenericCommit?.also{afterGenericCommit=null;it()};if(loseGenericReply){loseGenericReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)};return reply(listOf(saved))
            }
            return MockResponse().setResponseCode(404)
        }
    }
    @Test fun confirmedOrdinaryExpensePublishesItsRealLedgerAndExactBookedConsumptionAcrossAutomaticCycles()=runBlocking {
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-28T00:00:02Z",sourceWalletId=id(1),categoryId=id(31))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val review=(finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        finance.saveTransactionWithInvestmentFunds(owner,request.copy(consent=review.consent),device,now).getOrThrow()
        val local=store.investmentTradePublicationSnapshot(owner,id(20));assertEquals(2,local.pending.size)
        val consumption=local.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id(20)}
        assertEquals("cashConsumption",consumption.payload.financeRawString("role_raw_value"));assertEquals(-30L,consumption.payload.financeRawLong("accounting_amount_minor"))
        repeat(3){transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);clock+=30001}
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertEquals("real expense and its confirmed cash consumption must both finish",0,store.investmentTradePublicationSnapshot(owner,id(20)).pending.size)
        assertEquals(-30L,backend[consumption.entity to consumption.id]!!.payload.financeRawLong("accounting_amount_minor"))
        assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"})
        assertFalse(requests.any{it.method=="POST" && it.requestUrl!!.pathSegments.last()==CloudEntity.LEDGER_TRANSACTION.table})
    }
    private suspend fun publishCycles(count:Int=3) {
        repeat(count){transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);clock+=30001}
    }
    private suspend fun snapshot()=store.investmentOrdinaryPublicationSnapshot(owner,id(20))
    private suspend fun cleanIntoBackend(entities:List<CloudEntity>) {
        for(entity in entities)for(q in store.pendingMutations(owner,entity,Long.MAX_VALUE)) {
            val row=store.record(owner,entity.table,q.mutation.recordId)!!
            val clean=row.copy(syncVersion=row.syncVersion+1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(row.syncVersion+1))))
            assertTrue(store.acknowledgeMutation(q,clean));backend[clean.entity to clean.id]=clean
        }
    }
    private suspend fun saveExpense(amount:Long=70,event:Int=20,editing:Boolean=false):LedgerTransactionRecord {
        val draft=TransactionDraft(id=if(editing)id(event) else null,primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=amount,
            occurredAt="2026-10-28T00:00:02Z",sourceWalletId=id(1),categoryId=id(31))
        var request=TransactionInvestmentSaveRequest(draft,if(editing)null else TransactionCreationIdentity(id(event),now),null,"Adjustment","JPY")
        val error=finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(consent=error.review.consent)
        else if(error!=null)throw error
        return finance.saveTransactionWithInvestmentFunds(owner,request,device,now).getOrThrow()
    }
    private suspend fun lifecycle(action:TransactionLifecycleAction) {
        val current=LedgerTransactionRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!)
        var request=TransactionInvestmentLifecycleRequest(current,action,now,"JPY","Adjustment",null)
        val error=finance.prepareTransactionLifecycle(owner,request,device,now).exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(consent=error.review.consent)
        else if(error!=null)throw error
        finance.saveTransactionLifecycle(owner,request,device,now).getOrThrow()
    }
    private suspend fun assertPublished(amount:Long,activeConsumption:Long) {
        assertTrue("All financial queues must finish",snapshot().pending.isEmpty())
        val t=backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!
        assertEquals(amount,t.payload.financeRawLong("amount_minor"))
        val posts=backend.values.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id(20)}
        assertEquals(activeConsumption,posts.filter{it.deletedAt==null}.sumOf{it.payload.financeRawLong("accounting_amount_minor")!!})
        assertFalse(requests.any{it.method=="POST" && it.requestUrl!!.pathSegments.last()==CloudEntity.LEDGER_TRANSACTION.table})
    }
    @Test fun realEditArchiveRestoreAndDeletePublishCompleteComparedHistory()=runBlocking {
        saveExpense();publishCycles();assertPublished(70,-30)
        saveExpense(80,editing=true);publishCycles();assertPublished(80,-40)
        lifecycle(TransactionLifecycleAction.ARCHIVE);publishCycles();assertPublished(80,0)
        assertTrue(backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawArchived()==true)
        lifecycle(TransactionLifecycleAction.RESTORE);publishCycles();assertPublished(80,-40)
        lifecycle(TransactionLifecycleAction.ARCHIVE);publishCycles();assertPublished(80,0)
        lifecycle(TransactionLifecycleAction.DELETE);publishCycles();assertPublished(80,0)
        assertNotNull(backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.deletedAt)
    }
    @Test fun committedLostReplyRecoversWholeGroupWithoutAnotherWrite()=runBlocking {
        saveExpense();loseOrdinaryReply=true;publishCycles();assertPublished(70,-30)
        assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"})
    }
    @Test fun newerConfirmedAmountDuringOldCommitPreservesAndPublishesNewIntent()=runBlocking {
        saveExpense();afterOrdinaryCommit={runBlocking{saveExpense(80,editing=true)}}
        publishCycles(4);assertPublished(80,-40)
        assertEquals(2,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"})
    }
    @Test fun capturedSourceSurvivesClearedDefaultAndUnrelatedWalletQueue()=runBlocking {
        saveExpense()
        val root=store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!
        val cleared=root.copy(payload=JsonObject(root.payload+("investment_linked_wallet_id" to JsonNull)))
        store.commitMutation(cleared,PendingMutation(CloudEntity.LEDGER_WALLET,cleared.id,owner.value,MutationKind.UPSERT,cleared.payload,now,cleared.syncVersion,device))
        cleanIntoBackend(listOf(CloudEntity.LEDGER_WALLET))
        finance.saveWallet(owner,WalletDraft(id=id(2),name="Unrelated",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        publishCycles()
        val pending=snapshot().pending
        assertEquals(1,pending.size);assertEquals(id(2),pending.single().mutation.recordId)
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
    }
    @Test fun internalTransferPublishesConsumptionAndDestinationTogether()=runBlocking {
        finance.saveWallet(owner,WalletDraft(id=id(2),name="Destination",kind=WalletKind.CASH,currencyCode="JPY"),device,now).getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.LEDGER_WALLET))
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,
            title="Transfer",amountMinor=70,occurredAt="2026-10-28T00:00:02Z",sourceWalletId=id(1),destinationWalletId=id(2))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val error=finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired
        finance.saveTransactionWithInvestmentFunds(owner,request.copy(consent=error.review.consent),device,now).getOrThrow()
        publishCycles();assertPublished(70,0)
        val posts=backend.values.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id(20)}
        assertEquals(2,posts.size);assertEquals(setOf(-30L,30L),posts.map{it.payload.financeRawLong("amount_minor")!!}.toSet())
    }
    @Test fun realUnreconciledExpensePublishesReserveAndConsumptionTogether()=runBlocking {
        val cash=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id(10))!!
        val unrec=cash.copy(payload=JsonObject(cash.payload+("cash_bucket_raw_value" to JsonPrimitive("unreconciled"))))
        store.commitMutation(unrec,PendingMutation(CloudEntity.INVESTMENT_POSTING,id(10),owner.value,MutationKind.UPSERT,unrec.payload,now,unrec.syncVersion,device))
        val w=store.record(owner,CloudEntity.LEDGER_WALLET.table,id(1))!!
        val zero=w.copy(payload=JsonObject(w.payload+("opening_balance_minor" to JsonPrimitive(0))))
        store.commitMutation(zero,PendingMutation(CloudEntity.LEDGER_WALLET,id(1),owner.value,MutationKind.UPSERT,zero.payload,now,zero.syncVersion,device))
        val parent=finance.saveCategory(owner,CategoryDraft(id=id(40),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        finance.saveCategory(owner,CategoryDraft(id=id(41),name="Income child",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val income=TransactionDraft(primaryKind=TransactionPrimaryKind.INCOME,title="Later actual income",amountMinor=30,occurredAt="2026-10-28T00:00:03Z",sourceWalletId=id(1),categoryId=id(41))
        finance.saveTransactionWithInvestmentFunds(owner,TransactionInvestmentSaveRequest(income,TransactionCreationIdentity(id(12),now),null,"Adjustment","JPY"),device,now).getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY,CloudEntity.INVESTMENT_POSTING,CloudEntity.LEDGER_TRANSACTION))
        saveExpense(30);publishCycles();assertPublished(30,-30)
        val reserve=backend[CloudEntity.LEDGER_TRANSACTION.table to investmentLedgerIdentity(id(20),"cash-unreconciled-adjustment")]!!
        assertEquals(30L,reserve.payload.financeRawLong("amount_minor"));assertEquals("investmentReserveUse",reserve.payload.financeRawString("settlement_role_raw_value"))
    }

    @Test fun sameFinancialParentCommittedBeforeAllocationRecoversWithoutGenericAck()=runBlocking {
        saveExpense()
        val primary=investmentOrdinaryPublicationGroup(snapshot()).primary
        val observed=primary.copy(syncVersion=7,payload=JsonObject(primary.payload+buildJsonObject {
            put("sync_version",7);put("updated_at","2026-10-28T00:00:10Z");put("last_modified_by_device_id",id(90))
        }),updatedAt="2026-10-28T00:00:10Z")
        backend[observed.entity to observed.id]=observed
        publishCycles();assertPublished(70,-30)
        assertEquals(8L,backend[observed.entity to observed.id]!!.syncVersion)
        assertEquals(1L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.syncVersion)
    }

    @Test fun fullConsumptionBeforeWalletArchivePublishesFinancialGroupBeforeFinalArchive()=runBlocking {
        saveExpense(100)
        val root=store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!
        val cleared=root.copy(payload=JsonObject(root.payload+("investment_linked_wallet_id" to JsonNull)))
        store.commitMutation(cleared,PendingMutation(CloudEntity.LEDGER_WALLET,cleared.id,owner.value,MutationKind.UPSERT,cleared.payload,now,cleared.syncVersion,device))
        cleanIntoBackend(listOf(CloudEntity.LEDGER_WALLET))
        finance.archiveWallet(owner,RecordId(id(1)),device,now).getOrThrow()
        repeat(4){wallets.pushPending(owner,session.accessToken);publishCycles(1)}
        assertPublished(100,-60)
        assertTrue(store.record(owner,CloudEntity.LEDGER_WALLET.table,id(1))!!.payload.financeRawArchived()==true)
        assertTrue(backend[CloudEntity.LEDGER_WALLET.table to id(1)]!!.payload.financeRawArchived()==true)
        val financial=requests.indexOfFirst{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"}
        val archive=requests.indexOfLast{it.method=="PATCH" && it.requestUrl!!.pathSegments.last()==CloudEntity.LEDGER_WALLET.table}
        assertTrue(financial>=0 && archive>financial)
    }

    @Test fun olderGenericCreateCannotStrandNewConfirmedAllocationWithEqualClock()=runBlocking {
        saveExpense(20)
        assertEquals(1,snapshot().pending.size)
        afterGenericCommit={runBlocking{saveExpense(70,editing=true)}}
        assertEquals(1,transactions.pushPending(owner,session.accessToken).staleResponses)
        repeat(4){investments.pushPending(owner,session.accessToken);clock+=30001}
        assertTrue("New confirmed allocation after late generic create must finish",snapshot().pending.isEmpty())
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
        assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()==CloudEntity.LEDGER_TRANSACTION.table})
    }

    private suspend fun genericLateUpdate(remoteVersion:Long=1,backwardClock:Boolean=false) {
        saveExpense(20);cleanIntoBackend(listOf(CloudEntity.LEDGER_TRANSACTION));saveExpense(30,editing=true)
        val old=backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!
        backend[old.entity to old.id]=old.copy(syncVersion=remoteVersion,updatedAt="2026-10-27T23:59:59Z",payload=JsonObject(old.payload+buildJsonObject {
            put("sync_version",remoteVersion);put("updated_at","2026-10-27T23:59:59Z")
        }))
        afterGenericCommit={runBlocking{
            saveExpense(70,editing=true)
            if(backwardClock) {
                val row=store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!
                val next=row.copy(updatedAt="2026-10-27T23:00:00Z",payload=JsonObject(row.payload+("updated_at" to JsonPrimitive("2026-10-27T23:00:00Z"))))
                store.commitMutation(next,PendingMutation(CloudEntity.LEDGER_TRANSACTION,id(20),owner.value,MutationKind.UPSERT,next.payload,next.updatedAt!!,next.syncVersion,device))
            }
        }}
        assertEquals(1,transactions.pushPending(owner,session.accessToken).staleResponses)
        repeat(4){investments.pushPending(owner,session.accessToken);clock+=30001}
        assertTrue("New confirmed allocation after late generic update must finish",snapshot().pending.isEmpty())
        assertEquals(70L,backend[old.entity to old.id]!!.payload.financeRawLong("amount_minor"))
        assertEquals(remoteVersion+2,backend[old.entity to old.id]!!.syncVersion)
        assertEquals(1L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.syncVersion)
    }
    @Test fun olderGenericConditionalUpdateKeepsNewConfirmedFunds()=runBlocking {genericLateUpdate()}
    @Test fun olderGenericLocalWinnerUsesActualLongTargetAndKeepsBackwardClockEdit()=runBlocking {genericLateUpdate(9007199254740993L,true)}
    @Test fun olderGenericCreateWithLostReplyStillKeepsNewConfirmedFunds()=runBlocking {
        saveExpense(20);loseGenericReply=true;afterGenericCommit={runBlocking{saveExpense(70,editing=true)}}
        assertEquals(1,transactions.pushPending(owner,session.accessToken).staleResponses)
        repeat(4){investments.pushPending(owner,session.accessToken);clock+=30001}
        assertTrue(snapshot().pending.isEmpty());assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
    }

    private suspend fun seedOtherDeviceEvent(date:String,version:Long) {
        val g=investmentOrdinaryPublicationGroup(snapshot())
        fun cloud(row:CloudRecord,fields:JsonObject)=row.copy(syncVersion=version,updatedAt=date,payload=JsonObject(row.payload+fields+buildJsonObject {
            put("sync_version",version);put("updated_at",date);put("last_modified_by_device_id",id(90))
        }))
        val primary=cloud(g.primary,buildJsonObject{put("amount_minor",80);put("reporting_amount_minor",80)})
        val posts=g.postings.map{cloud(it,buildJsonObject{put("amount_minor",-40);put("accounting_amount_minor",-40)})}
        for(row in listOf(primary)+posts)backend[row.entity to row.id]=row
    }
    @Test fun actualWholeRemoteWinnerImportsBothRowsWithoutAnyFinancialRequest()=runBlocking {
        saveExpense();seedOtherDeviceEvent("2026-10-28T00:03:00Z",2)
        assertEquals(1,investments.pushPending(owner,session.accessToken).reconciled)
        publishCycles();assertPublished(80,-40)
        assertEquals(80L,store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.payload.financeRawLong("amount_minor"))
        assertFalse(requests.any{it.method=="POST" || it.method=="PATCH"})
    }
    @Test fun actualWholeLocalWinnerPublishesItsMoneyAtComparedHigherBases()=runBlocking {
        saveExpense();seedOtherDeviceEvent("2026-10-27T23:59:59Z",2)
        publishCycles();assertPublished(70,-30)
        assertEquals(3L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.syncVersion)
        assertEquals(3L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.syncVersion)
    }
    @Test fun actualSameClockZeroConflictKeepsRawEvidenceAndNeverSendsEitherMoneyRow()=runBlocking {
        saveExpense();seedOtherDeviceEvent(now,0)
        assertEquals(1,investments.pushPending(owner,session.accessToken).conflicts)
        publishCycles()
        val current=snapshot();assertEquals(2,current.pending.size);assertTrue(current.pending.all{it.nextAttemptAtEpochMillis==Long.MAX_VALUE})
        val parent=store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!
        val conflict=localInvestmentOrdinaryConflict(parent)!!
        assertEquals(70L,parent.payload.financeRawLong("amount_minor"));assertEquals(80L,conflict.observed.transaction!!.payload.financeRawLong("amount_minor"))
        assertFalse(requests.any{it.method=="POST" || it.method=="PATCH"})
    }

    private suspend fun saveCardPayment(amount:Long=70,editing:Boolean=false) {
        if(!editing) {
            finance.saveCreditCard(owner,CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,currencyCode="JPY"),device,now).getOrThrow()
            cleanIntoBackend(listOf(CloudEntity.LEDGER_WALLET,CloudEntity.CREDIT_CARD_PROFILE))
        }
        val draft=TransactionDraft(id=if(editing)id(20)else null,primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,
            title="Transfer",amountMinor=amount,destinationAmountMinor=amount,sourceWalletId=id(1),destinationWalletId=id(2),occurredAt="2026-10-28T00:00:02Z")
        var request=TransactionInvestmentSaveRequest(draft,if(editing)null else TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val error=finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(consent=error.review.consent) else if(error!=null)throw error
        finance.saveTransactionWithInvestmentFunds(owner,request,device,now).getOrThrow()
    }
    private suspend fun importPaidCardOccurrence(pending:Boolean) {
        val row=DueOccurrenceRecord(id(50),owner.value,"creditCard",id(2),"2026-10",now,70,"paid",now,id(20),now,now,null,0,device).toCloudRecord()
        store.commitMutation(row,PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD,row.id,owner.value,MutationKind.UPSERT,row.payload,now,0,device))
        if(!pending)cleanIntoBackend(listOf(CloudEntity.DUE_OCCURRENCE_RECORD))
    }
    @Test fun lateCleanPaidCardCycleCannotUploadAnOfflineChangedPayment()=runBlocking {
        saveCardPayment();publishCycles();saveCardPayment(80,editing=true);importPaidCardOccurrence(false)
        publishCycles()
        assertEquals("Paid source must not send a changed financial group",1,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"})
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertEquals(80L,store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.payload.financeRawLong("amount_minor"))
        assertEquals(2,snapshot().pending.size)
    }
    @Test fun ownPendingCardCycleDoesNotBlockItsConfirmedFinancialGroup()=runBlocking {
        saveCardPayment();publishCycles();saveCardPayment(80,editing=true);importPaidCardOccurrence(true)
        publishCycles()
        assertEquals(80L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        val pending=snapshot().pending;assertEquals(1,pending.size);assertEquals(CloudEntity.DUE_OCCURRENCE_RECORD,pending.single().mutation.entity)
        assertEquals(-40L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
    }
    @Test fun sameFinancialLegacyPaymentFinishesItsAllocationAfterCleanPaidCycleArrives()=runBlocking {
        saveCardPayment();cleanIntoBackend(listOf(CloudEntity.LEDGER_TRANSACTION));importPaidCardOccurrence(false)
        assertEquals(1,snapshot().pending.size)
        publishCycles();assertPublished(70,-30)
        assertEquals(2L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.syncVersion)
        assertEquals(1L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.syncVersion)
    }

    @Test fun capacityRetryDoesNotBlockLaterReleaseAndEarlierBackdatedGroupFinishesNextCycle()=runBlocking {
        saveExpense(70);publishCycles();saveExpense(20,event=21);publishCycles()
        saveExpense(20,editing=true)
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Earlier expense",amountMinor=60,
            occurredAt="2026-10-28T00:00:01.500Z",sourceWalletId=id(1),categoryId=id(31))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(22),now),null,"Adjustment","JPY")
        val review=finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired
        finance.saveTransactionWithInvestmentFunds(owner,request.copy(consent=review.review.consent),device,now).getOrThrow()
        for(event in listOf(20,21,22))assertEquals(-20L,store.record(owner,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(id(event),"cash-consumption-booked"))!!.payload.financeRawLong("amount_minor"))
        // Real source-derived final allocations are20+20+20. SQL capacity math
        // is tested separately; this fixture injects its closed retry condition.
        capacityFailureEvent=id(22)
        val start=requests.size
        val first=investments.pushPending(owner,session.accessToken)
        assertEquals(1,first.retryableFailures);assertEquals(2,first.pushed)
        assertNull(backend[CloudEntity.LEDGER_TRANSACTION.table to id(22)])
        assertEquals(20L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        val pending=snapshot().pending;assertEquals(2,pending.size)
        val driver=pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        assertEquals(id(22),driver.mutation.recordId);assertEquals(clock+30000,driver.nextAttemptAtEpochMillis)
        val eventOrder=requests.drop(start).filter{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"}
            .map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject.getValue("p_transaction").jsonObject.financeRawString("id")}
        assertEquals(listOf(id(22),id(20),id(21)),eventOrder)
        clock+=30001
        assertEquals(1,investments.pushPending(owner,session.accessToken).pushed)
        assertTrue(snapshot().pending.isEmpty())
        assertEquals(60L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(22)]!!.payload.financeRawLong("amount_minor"))
        for(event in listOf(20,21,22))assertEquals(-20L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(event),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
    }

    @Test fun remoteWinnerCannotReattributeOrPublishAnotherConfirmedEventOnTheSameCashSource()=runBlocking {
        saveExpense();saveExpense(20,event=21)
        val primary=store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!
        val remote=primary.copy(syncVersion=2,updatedAt="2026-10-28T00:03:00Z",payload=JsonObject(primary.payload+buildJsonObject {
            put("amount_minor",30);put("reporting_amount_minor",30);put("sync_version",2);put("updated_at","2026-10-28T00:03:00Z");put("last_modified_by_device_id",id(90))
        }))
        backend[remote.entity to remote.id]=remote
        publishCycles()
        val current=snapshot();assertEquals(4,current.pending.size)
        assertEquals("other_event_allocation_changed",localInvestmentOrdinaryConflict(current.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)})!!.reason)
        assertEquals(70L,current.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}.payload.financeRawLong("amount_minor"))
        assertEquals(-20L,current.rows.single{it.id==investmentLedgerIdentity(id(21),"cash-consumption-booked")}.payload.financeRawLong("amount_minor"))
        assertFalse("No dependent financial event may escape the unresolved source",requests.any{it.method=="POST" || it.method=="PATCH"})
    }

    @Test fun paidSourceLockAlsoRetainsTheNextConfirmedAllocationOnThatWallet()=runBlocking {
        saveCardPayment(30);publishCycles();saveCardPayment(50,editing=true);saveExpense(20,event=21);importPaidCardOccurrence(false)
        val before=requests.size
        publishCycles()
        val current=snapshot();assertEquals(4,current.pending.size)
        assertTrue(current.pending.any{it.mutation.recordId==id(20) && it.lastError=="ordinary_paid_source_locked"})
        assertEquals(30L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertNull(backend[CloudEntity.LEDGER_TRANSACTION.table to id(21)])
        assertFalse(requests.drop(before).any{it.method=="POST" || it.method=="PATCH"})
    }

    @Test fun changingAnOfflinePaymentIntoIncomeCannotBypassALatePaidSourceLock()=runBlocking {
        saveCardPayment();publishCycles()
        val parent=finance.saveCategory(owner,CategoryDraft(id=id(32),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        finance.saveCategory(owner,CategoryDraft(id=id(33),name="Salary",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.TRANSACTION_CATEGORY))
        var request=TransactionInvestmentSaveRequest(TransactionDraft(id=id(20),primaryKind=TransactionPrimaryKind.INCOME,title="Income",amountMinor=70,
            sourceWalletId=id(1),categoryId=id(33),occurredAt="2026-10-28T00:00:02Z"),null,null,"Adjustment","JPY")
        val error=finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(consent=error.review.consent) else if(error!=null)throw error
        finance.saveTransactionWithInvestmentFunds(owner,request,device,now).getOrThrow()
        importPaidCardOccurrence(false);publishCycles()
        assertEquals("transfer",backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawString("primary_kind_raw_value"))
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
        assertEquals(2,snapshot().pending.size)
        assertTrue(snapshot().pending.any{it.lastError=="ordinary_paid_source_locked"})
    }

    @Test fun realFundedBillPayUndoAndRepayPublishExpenseAllocationAndCycleWithoutStrandedQueues()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val catalog=vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog(context)
        val zone=java.time.ZoneId.of("UTC");val month=java.time.YearMonth.of(2026,10)
        finance=OfflineFirstFinanceRepository(store,zone,catalog)
        val initial=finance.saveRecurringBill(owner,RecurringBillDraft("Funded bill",id(31),70,id(1),"JPY",paymentStartDay=1,zoneId=zone),device,now).getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.TRANSACTION_CATEGORY,CloudEntity.RECURRING_BILL_PLAN))
        val bill=RecurringBillPlanRecord.fromCloudRecord(store.record(owner,CloudEntity.RECURRING_BILL_PLAN.table,initial.id)!!)
        val due=DueOccurrencePushCoordinator(store,dueRemote,true,nowEpochMillis={clock})
        val categories=CategoryPushCoordinator(store,dueRemote,true,catalog,{clock})
        suspend fun cycle() {repeat(3){categories.pushPending(owner,session.accessToken);transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);due.pushPending(owner,session.accessToken);clock+=30001}}
        suspend fun pay(at:String,creation:Int) {
            var request=BillPaymentRequest(RecordId(bill.id),month,RecordId(id(1)),70,expectedBill=bill,
                investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(creation),at),"JPY","Adjustment"))
            val error=finance.payRecurringBill(owner,request,device,at).exceptionOrNull()
            if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(investment=request.investment!!.copy(consent=error.review.consent)) else if(error!=null)throw error
            finance.payRecurringBill(owner,request,device,at).getOrThrow()
        }
        pay("2026-10-28T00:00:02Z",20);cycle()
        val pendingPay=snapshot()
        val payment=store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!
        val paymentCategory=payment.payload.financeRawString("category_id")?.let{store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,it)}
        assertTrue("PAY pending="+pendingPay.pending.map{listOf(it.mutation.entity.table,it.mutation.recordId,it.lastError)}+
            "; category="+paymentCategory?.payload?.let{listOf(it.financeRawString("system_key"),it.financeRawArchived(),it.financeRawString("parent_category_id"))}+
            "; requests="+requests.map{it.method+" "+it.requestUrl!!.pathSegments.last()},pendingPay.pending.isEmpty())
        assertPublished(70,-30)
        var occurrence=store.recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table).single{it.payload.financeRawString("source_id")==bill.id}
        assertEquals("paid",backend[occurrence.entity to occurrence.id]!!.payload.financeRawString("status_raw_value"))
        assertEquals(id(20),backend[occurrence.entity to occurrence.id]!!.payload.financeRawString("linked_transaction_id"))
        var undo=BillInvestmentUndoRequest(bill,month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(50),"2026-10-28T00:00:03Z"),"JPY","Adjustment"))
        val error=finance.undoRecurringBillPaymentWithInvestmentFunds(owner,undo,device,"2026-10-28T00:00:03Z").exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)undo=undo.copy(investment=undo.investment.copy(consent=error.review.consent)) else if(error!=null)throw error
        finance.undoRecurringBillPaymentWithInvestmentFunds(owner,undo,device,"2026-10-28T00:00:03Z").getOrThrow()
        cycle();assertTrue("UNDO pending="+snapshot().pending.map{listOf(it.mutation.entity.table,it.mutation.recordId,it.lastError)},snapshot().pending.isEmpty());assertPublished(70,0)
        assertNotNull(backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.deletedAt)
        assertNotNull(backend[occurrence.entity to occurrence.id]!!.deletedAt)
        pay("2026-10-28T00:00:04Z",21);cycle();assertTrue("REPAY pending="+snapshot().pending.map{listOf(it.mutation.entity.table,it.mutation.recordId,it.lastError)},snapshot().pending.isEmpty());assertPublished(70,-30)
        assertNull(backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.deletedAt)
        occurrence=store.recordsIncludingDeleted(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table).single{it.deletedAt==null && it.payload.financeRawString("source_id")==bill.id}
        assertNull(backend[occurrence.entity to occurrence.id]!!.deletedAt)
        assertEquals(id(20),backend[occurrence.entity to occurrence.id]!!.payload.financeRawString("linked_transaction_id"))
    }

    @Test fun newFundedInstallmentPaymentPublishesItsPaidCycleAfterTheConfirmedFinancialGroup()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val catalog=vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog(context)
        val zone=java.time.ZoneId.of("UTC");val month=java.time.YearMonth.of(2026,10)
        finance=OfflineFirstFinanceRepository(store,zone,catalog)
        val initial=finance.saveInstallment(owner,InstallmentDraft(id(60),"Funded installment",70,28,1,12,id(1),"JPY"),device,now).getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.INSTALLMENT_PLAN))
        val plan=InstallmentPlanRecord.fromCloudRecord(store.record(owner,CloudEntity.INSTALLMENT_PLAN.table,initial.id)!!)
        var request=InstallmentPaymentRequest(plan,month,RecordId(id(1)),70,
            investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),"2026-10-28T00:00:02Z"),"JPY","Adjustment"))
        val error=finance.payInstallment(owner,request,device,"2026-10-28T00:00:02Z").exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(investment=request.investment!!.copy(consent=error.review.consent)) else if(error!=null)throw error
        val paid=finance.payInstallment(owner,request,device,"2026-10-28T00:00:02Z").getOrThrow()
        val categories=CategoryPushCoordinator(store,dueRemote,true,catalog,{clock})
        val ack=InstallmentPaymentAcknowledgementCoordinator(store,dueRemote,true,{clock})
        val due=DueOccurrencePushCoordinator(store,dueRemote,true,installmentPaymentAcknowledgementCoordinator=ack,
            installmentPaymentPublicationCoordinator=InstallmentPaymentPublicationCoordinator(store,dueRemote,installmentRemote,true,{session},{clock},{zone}),nowEpochMillis={clock})
        repeat(3){categories.pushPending(owner,session.accessToken);transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);due.pushPending(owner,session.accessToken);clock+=30001}
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
        val occurrence=paid.occurrences.single()
        assertNotNull("A newly confirmed installment payment needs its owned paid-cycle publication",backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to occurrence.id])
        assertEquals("paid",backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to occurrence.id]!!.payload.financeRawString("status_raw_value"))
        assertTrue("No payment/cycle queue may remain: "+snapshot().pending.map{it.mutation.entity.table to it.lastError},snapshot().pending.isEmpty())
        var undo=InstallmentInvestmentUndoRequest(plan,month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(50),"2026-10-28T00:00:03Z"),"JPY","Adjustment"))
        val undoError=finance.undoInstallmentPaymentWithInvestmentFunds(owner,undo,device,"2026-10-28T00:00:03Z").exceptionOrNull()
        if(undoError is InvestmentFundUsageConfirmationRequired) {
            undo=undo.copy(investment=undo.investment.copy(consent=undoError.review.consent))
            finance.undoInstallmentPaymentWithInvestmentFunds(owner,undo,device,"2026-10-28T00:00:03Z").getOrThrow()
        } else if(undoError!=null)throw undoError
        repeat(3){transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);due.pushPending(owner,session.accessToken);clock+=30001}
        assertTrue("UNDO pending="+snapshot().pending.map{it.lastError},snapshot().pending.isEmpty())
        assertNotNull(backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to occurrence.id]!!.deletedAt);assertPublished(70,0)
        request=request.copy(amountMinorOverride=80,investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(21),"2026-10-28T00:00:04Z"),"JPY","Adjustment"))
        val repayError=finance.payInstallment(owner,request,device,"2026-10-28T00:00:04Z").exceptionOrNull()
        if(repayError is InvestmentFundUsageConfirmationRequired) {
            request=request.copy(investment=request.investment!!.copy(consent=repayError.review.consent))
            finance.payInstallment(owner,request,device,"2026-10-28T00:00:04Z").getOrThrow()
        } else if(repayError!=null)throw repayError
        repeat(3){transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);due.pushPending(owner,session.accessToken);clock+=30001}
        assertTrue("REPAY pending="+snapshot().pending.map{it.lastError},snapshot().pending.isEmpty());assertPublished(80,-40)
        val final=backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to occurrence.id]!!
        assertNull(final.deletedAt);assertEquals(80L,final.payload.financeRawLong("amount_minor_snapshot"));assertEquals(id(20),final.payload.financeRawString("linked_transaction_id"))
        assertEquals(3L,final.syncVersion)
    }

    private val installmentZone=java.time.ZoneId.of("UTC")
    private val installmentMonth=java.time.YearMonth.of(2026,10)
    private suspend fun prepareInstallment(amount:Long):InstallmentPlanRecord {
        val catalog=vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog(ApplicationProvider.getApplicationContext<Context>())
        finance=OfflineFirstFinanceRepository(store,installmentZone,catalog)
        val saved=finance.saveInstallment(owner,InstallmentDraft(id(60),"Installment",amount,28,1,12,id(1),"JPY"),device,now).getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.INSTALLMENT_PLAN))
        return InstallmentPlanRecord.fromCloudRecord(store.record(owner,CloudEntity.INSTALLMENT_PLAN.table,saved.id)!!)
    }
    private fun installmentDue()=DueOccurrencePushCoordinator(store,dueRemote,true,
        installmentPaymentAcknowledgementCoordinator=InstallmentPaymentAcknowledgementCoordinator(store,dueRemote,true,{clock}),
        installmentPaymentPublicationCoordinator=InstallmentPaymentPublicationCoordinator(store,dueRemote,installmentRemote,true,{session},{clock},{installmentZone}),nowEpochMillis={clock})
    private suspend fun publishInstallmentCycles(due:DueOccurrencePushCoordinator,count:Int=3) {
        val catalog=vn.com.quyln.mistia.core.designsystem.systemCategoryCatalog(ApplicationProvider.getApplicationContext<Context>())
        val categories=CategoryPushCoordinator(store,dueRemote,true,catalog,{clock})
        repeat(count){categories.pushPending(owner,session.accessToken);transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);due.pushPending(owner,session.accessToken);clock+=30001}
    }
    private suspend fun payInstallment(plan:InstallmentPlanRecord,amount:Long,at:String,creation:Int=20):SavedInstallmentPayment {
        var request=InstallmentPaymentRequest(plan,installmentMonth,RecordId(id(1)),amount,
            investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(creation),at),"JPY","Adjustment"))
        val first=finance.payInstallment(owner,request,device,at)
        val error=first.exceptionOrNull()
        if(error !is InvestmentFundUsageConfirmationRequired)return first.getOrThrow()
        request=request.copy(investment=request.investment!!.copy(consent=error.review.consent))
        return finance.payInstallment(owner,request,device,at).getOrThrow()
    }
    private suspend fun undoInstallment(plan:InstallmentPlanRecord,amount:Long,at:String) {
        var request=InstallmentInvestmentUndoRequest(plan,installmentMonth,amount,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(50),at),"JPY","Adjustment"))
        val first=finance.undoInstallmentPaymentWithInvestmentFunds(owner,request,device,at)
        val error=first.exceptionOrNull()
        if(error !is InvestmentFundUsageConfirmationRequired){first.getOrThrow();return}
        request=request.copy(investment=request.investment.copy(consent=error.review.consent))
        finance.undoInstallmentPaymentWithInvestmentFunds(owner,request,device,at).getOrThrow()
    }
    @Test fun lostInstallmentPayAndUndoResponsesRecoverWithANewerAmountFromLocalZero()=runBlocking {
        val plan=prepareInstallment(70);val due=installmentDue()
        val paid=payInstallment(plan,70,"2026-10-28T00:00:02Z");val cycleId=paid.occurrences.single().id
        loseInstallmentReply=true;publishInstallmentCycles(due,1)
        var q=store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single()
        assertEquals("network_io",q.lastError);assertEquals(0L,q.mutation.baseVersion)
        assertEquals(1L,backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to cycleId]!!.syncVersion)
        undoInstallment(plan,70,"2026-10-28T00:00:03Z")
        loseInstallmentReply=true;publishInstallmentCycles(due,1)
        q=store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single()
        assertEquals("network_io",q.lastError);assertEquals(0L,q.mutation.baseVersion)
        assertNotNull(backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to cycleId]!!.deletedAt)
        payInstallment(plan,80,"2026-10-28T00:00:04Z",21);publishInstallmentCycles(due)
        assertTrue("Pending="+snapshot().pending.map{it.lastError},snapshot().pending.isEmpty());assertPublished(80,-40)
        val actual=backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to cycleId]!!
        assertEquals(3L,actual.syncVersion);assertEquals(80L,actual.payload.financeRawLong("amount_minor_snapshot"));assertNull(actual.deletedAt)
        assertEquals(3,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_installment_paid_cycle"})
    }
    @Test fun ordinaryMoneyInstallmentPaymentPublishesItsMarkerWithoutAnyInvestmentAllocation()=runBlocking {
        val plan=prepareInstallment(20);val due=installmentDue()
        val paid=payInstallment(plan,20,"2026-10-28T00:00:02Z");publishInstallmentCycles(due)
        assertTrue("Pending="+snapshot().pending.map{it.lastError},snapshot().pending.isEmpty())
        val marker=backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to paid.occurrences.single().id]!!
        assertEquals(20L,marker.payload.financeRawLong("amount_minor_snapshot"));assertEquals(1L,marker.syncVersion)
        assertEquals(20L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertFalse(backend.values.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id(20)})
        assertFalse(requests.any{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"})
    }

    private suspend fun payCardStatement(amount:Long=70,existingZero:Boolean=false):SavedCreditCardStatementPayment {
        val zone=java.time.ZoneId.of("UTC");val month=java.time.YearMonth.of(2026,9)
        finance=OfflineFirstFinanceRepository(store,zone)
        val account=finance.saveCreditCard(owner,CreditCardDraft(walletId=id(60),profileId=id(61),name="Card",creditLimitMinor=1000,
            statementClosingDay=10,paymentDueDay=26,paymentSourceWalletId=id(1)),device,"2026-08-01T00:00:00Z").getOrThrow()
        finance.saveTransaction(owner,TransactionDraft(id=id(62),primaryKind=TransactionPrimaryKind.EXPENSE,title="Charge",amountMinor=amount,
            occurredAt="2026-09-12T00:00:00Z",sourceWalletId=account.wallet.id,categoryId=id(31)),device,"2026-09-12T00:00:00Z").getOrThrow()
        cleanIntoBackend(listOf(CloudEntity.LEDGER_WALLET,CloudEntity.CREDIT_CARD_PROFILE,CloudEntity.LEDGER_TRANSACTION))
        val card=LedgerWalletRecord.fromCloudRecord(store.record(owner,CloudEntity.LEDGER_WALLET.table,account.wallet.id)!!)
        val profile=CreditCardProfileRecord.fromCloudRecord(store.record(owner,CloudEntity.CREDIT_CARD_PROFILE.table,account.profile.id)!!)
        val state=store.creditCardStatementPaymentSnapshot(owner)
        val statement=creditCardStatementItems(owner,listOf(CreditCardAccount(card,profile)),state.money.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord),
            emptyList(),listOf(month),java.time.Instant.parse(now),zone,state.money.recordsByEntity.getValue(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)).single()
        assertTrue(statement.isPayable);assertEquals(amount,statement.amountMinor)
        if(existingZero) {
            val pending=DueOccurrenceRecord(id(63),owner.value,"creditCard",card.id,java.time.YearMonth.from(statement.dueDate.atZone(zone)).toString(),
                statement.dueDate.toString(),amount,"pending",null,null,"2026-08-01T00:00:00Z",now,null,0,device).toCloudRecord()
            store.replacePullSnapshot(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,listOf(pending))
            backend[pending.entity to pending.id]=pending
        }
        var request=CreditCardStatementPaymentRequest(statement,BillInvestmentOperationContext(TransactionCreationIdentity(id(20),"2026-10-28T00:00:02Z"),"JPY","Adjustment"),"Card payment: Card")
        val error=finance.payCreditCardStatement(owner,request,device,"2026-10-28T00:00:02Z").exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(context=request.context.copy(consent=error.review.consent))else if(error!=null)throw error
        return finance.payCreditCardStatement(owner,request,device,"2026-10-28T00:00:02Z").getOrThrow()
    }
    private fun cardDue()=DueOccurrencePushCoordinator(store,dueRemote,false,
        cardPaymentPublicationCoordinator=CardPaymentPublicationCoordinator(store,dueRemote,cardRemote,true,{session},{clock},{java.time.ZoneId.of("UTC")}),nowEpochMillis={clock})
    private suspend fun publishCardCycles(due:DueOccurrencePushCoordinator,passes:Int=3) {
        repeat(passes){transactions.pushPending(owner,session.accessToken);investments.pushPending(owner,session.accessToken);due.pushPending(owner,session.accessToken);clock+=30001}
    }
    @Test fun newlyFundedCardStatementNeedsItsPaidMarkerAfterTheFinancialGroupPublishes()=runBlocking {
        val paid=payCardStatement();val due=cardDue()
        publishCardCycles(due)
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
        assertNotNull("A real card payment needs its owned paid-cycle marker to finish cloud publication",backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to paid.occurrence.id])
        assertTrue(store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).isEmpty())
        assertTrue("No payment queues may remain: "+snapshot().pending.map{it.mutation.entity.table to it.lastError},snapshot().pending.isEmpty())
    }


    @Test fun cardPaymentLostReplyRecoversActualMarkerWithoutRepeatingMoneyOrRpc()=runBlocking {
        val paid=payCardStatement();val due=cardDue();loseCardReply=true
        publishCardCycles(due,1)
        val q=store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single()
        assertEquals("network_io",q.lastError);assertEquals(0L,q.mutation.baseVersion)
        assertNotNull(backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to paid.occurrence.id])
        val money=synchronized(backend){backend.filterKeys{it.first!=CloudEntity.DUE_OCCURRENCE_RECORD.table}.toMap()}
        publishCardCycles(due)
        assertTrue(snapshot().pending.isEmpty());assertEquals(money,synchronized(backend){backend.filterKeys{it.first!=CloudEntity.DUE_OCCURRENCE_RECORD.table}.toMap()})
        assertTrue(store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).isEmpty())
        assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_card_paid_cycle"})
    }
    @Test fun ordinaryCardStatementPublishesWithoutCreatingAnInvestmentAllocation()=runBlocking {
        val paid=payCardStatement(20);publishCardCycles(cardDue())
        assertTrue(snapshot().pending.isEmpty());assertEquals(20L,backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to paid.occurrence.id]!!.payload.financeRawLong("amount_minor_snapshot"))
        assertEquals(20L,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.payload.financeRawLong("amount_minor"))
        assertFalse(backend.values.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==id(20)})
        assertFalse(requests.any{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_ordinary_investment_event"})
        assertTrue(store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).isEmpty())
    }
    @Test fun observedZeroLegacyCardCycleNormalizesMonthAndRetainsActualServerAudit()=runBlocking {
        val paid=payCardStatement(existingZero=true)
        val q=store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single()
        assertTrue(q.remoteIdentityObserved);assertEquals(0L,q.mutation.baseVersion)
        assertEquals("2026-09",paid.occurrence.selectedMonthKey);assertEquals("2026-08-01T00:00:00Z",paid.occurrence.createdAt)
        publishCardCycles(cardDue())
        val actual=requireNotNull(store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,paid.occurrence.id))
        assertEquals(1L,actual.syncVersion);assertEquals("2026-10-29T00:00:00Z",actual.updatedAt)
        assertEquals(actual,backend[actual.entity to actual.id]);assertTrue(store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).isEmpty())
        val body=Json.parseToJsonElement(requests.single{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_card_paid_cycle"}.body.clone().readUtf8()).jsonObject
        assertEquals(JsonPrimitive(true),body["p_expected_presence"]);assertEquals(JsonPrimitive(0),body["p_expected_version"])
    }
    @Test fun historicalCardTombstoneAndNewPaymentPublishWithoutRewritingMoney()=runBlocking {
        val zone=java.time.ZoneId.of("UTC");val first=payCardStatement();val due=cardDue();publishCardCycles(due)
        val deleted="2026-10-28T00:00:03Z";val later="2026-10-28T00:00:04Z"
        // Imported owned history can retain archived_at after permanent deletion.
        // This fixture does not bypass the paid-card editor lock or claim an undo UI.
        for(entity in listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING)) {
            val affected=synchronized(backend){backend.values.filter{it.entity==entity.table && (it.id==id(20) || it.payload.financeRawString("event_id")==id(20))}.toList()}
            for(row in affected) {
                val fields=buildJsonObject {
                    put("deleted_at",deleted);put("updated_at",deleted);put("sync_version",row.syncVersion+1)
                    if(entity==CloudEntity.LEDGER_TRANSACTION){put("is_archived",true);put("archived_at",deleted)}
                }
                val received=row.copy(payload=JsonObject(row.payload+fields),deletedAt=deleted,updatedAt=deleted,syncVersion=row.syncVersion+1)
                backend[received.entity to received.id]=received
            }
            store.replacePullSnapshot(owner,entity.table,synchronized(backend){backend.values.filter{it.entity==entity.table}.toList()})
        }
        val financialHistory=synchronized(backend){backend.filterKeys{it.first!=CloudEntity.DUE_OCCURRENCE_RECORD.table}.toMap()}
        // Supply the queued maintenance marker explicitly. Automatic card
        // statement maintenance is the next slice; it is not this test's claim.
        val marker=DueOccurrenceRecord.fromCloudRecord(requireNotNull(store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,first.occurrence.id)))
            .copy(deletedAt=deleted,updatedAt=deleted)
        store.commitMutation(marker.toCloudRecord(),marker.pendingMutation(MutationKind.DELETE))
        publishCardCycles(due)
        assertEquals(deleted,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.deletedAt)
        assertEquals("Pending="+store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).map{it.lastError},deleted,backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to marker.id]!!.deletedAt)
        assertEquals(2L,backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to marker.id]!!.syncVersion)
        assertEquals(financialHistory,synchronized(backend){backend.filterKeys{it.first!=CloudEntity.DUE_OCCURRENCE_RECORD.table}.toMap()})
        assertEquals(deleted,backend[CloudEntity.LEDGER_TRANSACTION.table to id(20)]!!.deletedAt)
        val source=store.creditCardStatementPaymentSnapshot(owner).money.recordsByEntity
        val card=LedgerWalletRecord.fromCloudRecord(source.getValue(CloudEntity.LEDGER_WALLET).single{it.id==id(60)})
        val profile=CreditCardProfileRecord.fromCloudRecord(source.getValue(CloudEntity.CREDIT_CARD_PROFILE).single{it.id==id(61)})
        val statement=creditCardStatementItems(owner,listOf(CreditCardAccount(card,profile)),source.getValue(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord),
            source.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord),listOf(java.time.YearMonth.of(2026,9)),java.time.Instant.parse(later),zone,
            source.getValue(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)).single()
        assertTrue(statement.isPayable)
        var request=CreditCardStatementPaymentRequest(statement,BillInvestmentOperationContext(TransactionCreationIdentity(id(21),later),"JPY","Adjustment"),"Card payment again")
        val secondReview=finance.payCreditCardStatement(owner,request,device,later).exceptionOrNull()
        if(secondReview is InvestmentFundUsageConfirmationRequired)request=request.copy(context=request.context.copy(consent=secondReview.review.consent))else if(secondReview!=null)throw secondReview
        val second=finance.payCreditCardStatement(owner,request,device,later).getOrThrow()
        assertNotEquals(first.occurrence.id,second.occurrence.id);publishCardCycles(due)
        assertTrue(store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).isEmpty())
        val actual=backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to second.occurrence.id]!!
        assertNull(actual.deletedAt);assertEquals(id(21),actual.payload.financeRawString("linked_transaction_id"));assertEquals(70L,actual.payload.financeRawLong("amount_minor_snapshot"))
        assertEquals(-30L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(21),"cash-consumption-booked")]!!.payload.financeRawLong("amount_minor"))
        assertNotNull(backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id(20),"cash-consumption-booked")]!!.deletedAt)
        assertEquals(3,requests.count{it.method=="POST" && it.requestUrl!!.pathSegments.last()=="mutate_card_paid_cycle"})
    }

    @Test fun lateCardReceiptCannotConsumeANewerLocalMarkerDeletionIntent()=runBlocking {
        val paid=payCardStatement();val due=cardDue();val deleted="2026-10-28T00:00:03Z"
        afterCardCommit={runBlocking {
            val current=DueOccurrenceRecord.fromCloudRecord(requireNotNull(store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,paid.occurrence.id)))
            val next=current.copy(deletedAt=deleted,updatedAt=deleted)
            store.commitMutation(next.toCloudRecord(),next.pendingMutation(MutationKind.DELETE))
        }}
        publishCardCycles(due,1)
        val current=requireNotNull(store.record(owner,CloudEntity.DUE_OCCURRENCE_RECORD.table,paid.occurrence.id))
        val q=store.pendingMutations(owner,CloudEntity.DUE_OCCURRENCE_RECORD,Long.MAX_VALUE).single()
        assertEquals(deleted,current.deletedAt);assertEquals(MutationKind.DELETE,q.mutation.kind);assertEquals(0,q.attemptCount);assertNull(q.lastError)
        assertNull(backend[CloudEntity.DUE_OCCURRENCE_RECORD.table to paid.occurrence.id]!!.deletedAt)
    }
}
