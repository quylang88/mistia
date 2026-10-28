package vn.com.quyln.mistia.feature.investment

import android.content.Context
import android.graphics.Bitmap
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.UUID
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okio.Buffer
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.*
import vn.com.quyln.mistia.core.sync.*

/** Real repository, Room and authenticated HTTPS. Effective SQL arithmetic/version rules have separate pgTAP evidence. */
@RunWith(AndroidJUnit4::class)
class InvestmentTradePublicationIntegrationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val asset="33333333-3333-3333-3333-333333333333"
    private val wallet="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-26T00:00:00Z"
    private val serverTime="2026-10-26T00:30:00Z"
    @Volatile private var session:AuthSession?=AuthSession(owner,null,"local-contract-token","refresh",Long.MAX_VALUE)
    private var enabled=true
    private var clock=4000L
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    private lateinit var cache:FileInvestmentProductImageCache
    private lateinit var imageDirectory:File
    private lateinit var server:MockWebServer
    private lateinit var coordinator:InvestmentTradePushCoordinator
    private lateinit var assetCoordinator:InvestmentAssetPushCoordinator
    private lateinit var channelCoordinator:InvestmentChannelPushCoordinator
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private val backend=Collections.synchronizedMap(linkedMapOf<Pair<String,String>,CloudRecord>())
    private val objects=Collections.synchronizedMap(mutableMapOf<String,ByteArray>())
    private val objectPrefix="/storage/v1/object/investment-product-images/"
    private var onRpc:(suspend ()->Unit)?=null
    private var loseReply=false
    private var corruptFinancial=false
    private var validateEditsAgainstBackendHistory=false
    private lateinit var ordinaryRemote:SupabasePostgrestRemoteStore
    private lateinit var walletPrerequisiteRemote:WalletInvestmentPrerequisiteRemote
    private lateinit var rootCoordinator:InvestmentWalletPushCoordinator
    private var beforeRead:(suspend (RecordedRequest)->Unit)?=null
    private var beforeMetadataWrite:(suspend (CloudEntity,JsonObject)->Unit)?=null
    private var onMetadataCommit:(suspend (CloudEntity,JsonObject)->Unit)?=null
    private var metadataFailure:Int?=null
    private var loseMetadataReply=false
    @Before fun setup()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        imageDirectory=File(context.cacheDir,"trade-retirement-images-${UUID.randomUUID()}")
        cache=FileInvestmentProductImageCache(imageDirectory,{session?.userId})
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={session?.userId},productImages=cache);repo=OfflineFirstInvestmentRepository(store,productImages=cache)
        val rows=listOf(
            InvestmentAssetRecord(asset,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,0,device).toCloudRecord(),
            InvestmentChannelRecord(channel,owner.value,"Shop","shippingbox.fill","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord(),
            WalletDraft(id=wallet,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000).toMutation(owner,null,device,now).record,
            WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record.let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))},
        )
        for(row in rows) {
            val entity=CloudEntity.fromTable(row.entity)!!
            store.commitMutation(row,PendingMutation(entity,row.id,owner.value,MutationKind.UPSERT,row.payload,now,0,device))
            val q=store.pendingMutations(owner,entity,Long.MAX_VALUE).single{it.mutation.recordId==row.id}
            assertTrue(store.acknowledgeMutation(q,row.copy(syncVersion=1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(1))))))
        }
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);dispatcher=fixture();start()}
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false).callTimeout(5,TimeUnit.SECONDS).build()
        val remote=SupabaseInvestmentTradeClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        val assets=SupabaseInvestmentAssetClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        val channels=SupabaseInvestmentChannelClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        val rootRemote=SupabaseInvestmentWalletClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        ordinaryRemote=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,writableEntities=setOf(CloudEntity.LEDGER_WALLET))
        walletPrerequisiteRemote=SupabaseWalletInvestmentPrerequisiteClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        rootCoordinator=InvestmentWalletPushCoordinator(store,rootRemote,true,{session},{clock})
        for(row in store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table))backend[row.entity to row.id]=row
        val images=SupabaseInvestmentProductImageClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session},{enabled})
        assetCoordinator=InvestmentAssetPushCoordinator(store,assets,true,{session},{clock},cache,images,retirementRemote=remote,
            metadataRemote=InvestmentTradeMetadataRemote{user,entity,key,token->channels.fetchRecord(entity,key,token,user)})
        channelCoordinator=InvestmentChannelPushCoordinator(store,channels,true,{session},{clock},retirementRemote=remote)
        coordinator=InvestmentTradePushCoordinator(store,remote,true,{session},{clock},InvestmentTradeMetadataRemote{user,entity,key,token->
            when(entity) {
                CloudEntity.INVESTMENT_ASSET->assets.fetchRecord(entity,key,token,user)
                CloudEntity.INVESTMENT_CHANNEL->channels.fetchRecord(entity,key,token,user)
                else->error("Invalid test metadata entity")
            }
        })
    }
    @After fun close(){server.shutdown();db.close();imageDirectory.deleteRecursively()}
    private fun response(rows:List<CloudRecord>)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests.add(request)
            assertEquals("Bearer "+session?.accessToken,request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
            val url=request.requestUrl!!;val path=url.encodedPath
            if(path.startsWith(objectPrefix)) {
                val objectPath=path.removePrefix(objectPrefix)
                InvestmentProductImagePath.parse(owner,objectPath.split('/')[1],objectPath)
                return when(request.method) {
                    "POST"->if(objects.containsKey(objectPath))MockResponse().setResponseCode(409) else {
                        objects[objectPath]=request.body.clone().readByteArray();MockResponse().setResponseCode(201)
                    }
                    "GET"->objects[objectPath]?.let{MockResponse().setBody(Buffer().write(it))} ?: MockResponse().setResponseCode(404)
                    "DELETE"->{objects.remove(objectPath);MockResponse().setResponseCode(204)}
                    else->MockResponse().setResponseCode(405)
                }
            }
            if(request.method=="GET") {
                beforeRead?.let{runBlocking{it(request)}}
                assertEquals("eq."+owner.value,url.queryParameter("user_id"))
                val table=url.pathSegments.last();val filters=url.queryParameterValues("id").filterNotNull()
                val exact=filters.firstOrNull{it.startsWith("eq.")}?.removePrefix("eq.")
                val ids=filters.firstOrNull{it.startsWith("in.(")}?.removePrefix("in.(")?.removeSuffix(")")?.split(',')?.toSet()
                val cursor=filters.firstOrNull{it.startsWith("gt.")}?.removePrefix("gt.")
                val assets=url.queryParameter("asset_id")?.removePrefix("eq.")?.removePrefix("in.(")?.removeSuffix(")")?.split(',')?.toSet()
                val parent=url.queryParameter("channel_id")?.removePrefix("eq.")
                val rows=synchronized(backend){backend.values.toList()}.filter{it.entity==table && (exact==null || it.id==exact) &&
                    (ids==null || it.id in ids) && (cursor==null || it.id>cursor) && (assets==null || it.payload.financeRawString("asset_id") in assets) &&
                    (parent==null || it.payload.financeRawString("channel_id")==parent)}.sortedBy{it.id}.take(1)
                return response(rows.map{if(corruptFinancial && it.entity==CloudEntity.LEDGER_TRANSACTION.table)it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonPrimitive(71)))) else it})
            }
            if(path in setOf("/rest/v1/investment_channels","/rest/v1/ledger_wallets") && request.method in setOf("PATCH","POST") || path=="/rest/v1/rpc/mutate_investment_asset") {
                val wire=Json.parseToJsonElement(request.body.clone().readUtf8())
                val body=if(wire is JsonArray)wire.single().jsonObject else wire.jsonObject
                val assetRpc=path.endsWith("mutate_investment_asset")
                val entity=if(assetRpc)CloudEntity.INVESTMENT_ASSET else if(path=="/rest/v1/ledger_wallets")CloudEntity.LEDGER_WALLET else CloudEntity.INVESTMENT_CHANNEL
                val input=if(assetRpc)body.getValue("p_asset").jsonObject else body
                val identity=input.financeRawString("id") ?: url.queryParameter("id")!!.removePrefix("eq.")
                val key=entity.table to identity
                val old=backend[key]
                val payload=if(entity==CloudEntity.LEDGER_WALLET && old!=null)JsonObject(old.payload+input) else input
                val expected=if(assetRpc)body.financeRawLong("p_expected_version")!! else if(request.method=="POST")0 else url.queryParameter("sync_version")!!.removePrefix("eq.").toLong()
                if(old==null && expected!=0L || old!=null && old.syncVersion!=expected)return response(emptyList())
                if(!assetRpc && old!=null && request.method=="POST")return MockResponse().setResponseCode(409)
                val before=beforeMetadataWrite;beforeMetadataWrite=null;if(before!=null)runBlocking{before(entity,payload)}
                metadataFailure?.let{metadataFailure=null;return MockResponse().setResponseCode(it)}
                assertEquals(owner.value,payload.financeRawString("user_id"))
                assertTrue(payload.keys.none{it.startsWith("_mistia_android_")})
                if(assetRpc) {
                    assertEquals(JsonPrimitive(false),body["p_force"])
                    val parent=backend[CloudEntity.INVESTMENT_CHANNEL.table to payload.financeRawString("channel_id")]
                    if(parent==null || parent.deletedAt!=null || parent.payload.financeRawArchived()!=false)return MockResponse().setResponseCode(400)
                }
                if(payload.financeRawArchived()==true) {
                    val assets=if(assetRpc)setOf(key.second) else synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_ASSET.table &&
                        it.deletedAt==null && it.payload.financeRawString("channel_id")==key.second}.map{it.id}.toSet()}
                    val active=synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.deletedAt==null && it.payload.financeRawString("asset_id") in assets}}
                    val open=active.groupBy{it.payload.financeRawString("asset_id")}.values.any{rows->
                        rows.maxWith(compareBy<CloudRecord>{it.payload.financeRawString("occurred_at")}.thenBy{it.payload.financeRawString("created_at")}.thenBy{it.id})
                            .payload.financeRawString("position_quantity_after_decimal_string")!!.toBigDecimal().signum()>0
                    }
                    if(open)return MockResponse().setResponseCode(400).setBody("Close cloud positions before archive")
                }
                val version=if(assetRpc)expected+1 else payload.financeRawLong("sync_version")!!
                val saved=CloudRecord(entity.table,key.second,owner.value,JsonObject(payload+buildJsonObject{put("sync_version",version);put("updated_at",serverTime)}),serverTime,payload.financeRawString("deleted_at"),version)
                backend[key]=saved
                if(assetRpc && old!=null && old.payload.financeRawString("default_unit_label")==null && payload.financeRawString("default_unit_label")!=null)
                    repairServerLegacyUnits(old,payload)
                val callback=onMetadataCommit;onMetadataCommit=null;if(callback!=null)runBlocking{callback(entity,payload)}
                if(loseMetadataReply){loseMetadataReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                return response(listOf(saved))
            }
            val delete=path=="/rest/v1/rpc/delete_investment_trade"
            if(request.method!="POST" || !delete && path!="/rest/v1/rpc/mutate_investment_trade")return MockResponse().setResponseCode(404)
            val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
            val incoming=if(delete)null else body.getValue("p_trade").jsonObject
            val requested=if(delete)body.financeRawString("p_trade_id")!! else incoming!!.financeRawString("id")!!
            val base=body.financeRawLong("p_expected_version")!!
            if(!delete) {
                assertEquals(JsonPrimitive(false),body["p_force"])
                for(key in listOf(LOCAL_TRADE_PUBLICATION_PARENTS_KEY,"released_cost_basis_minor","funding_ledger_transaction_id","position_cost_basis_after_minor"))assertFalse(key,key in incoming!!)
            } else {assertEquals(owner.value,body.financeRawString("p_owner_user_id"));assertEquals(device,body.financeRawString("p_device_id"))}
            if(incoming!=null)for(key in listOf("funding_wallet_id","capital_return_wallet_id")) {
                val walletId=incoming.financeRawString(key) ?: continue
                val remoteWallet=backend[CloudEntity.LEDGER_WALLET.table to walletId]
                if(remoteWallet==null || remoteWallet.deletedAt!=null || remoteWallet.payload.financeRawArchived()!=false)
                    return MockResponse().setResponseCode(400).setBody("Inactive trade cash wallet")
            }
            val existing=backend[CloudEntity.INVESTMENT_TRADE.table to requested]
            if((existing?.syncVersion ?: 0L)!=base)return response(emptyList())
            val source=runBlocking{store.investmentTradePublicationSnapshot(owner,requested)}
            val projected=if(validateEditsAgainstBackendHistory && incoming!=null && existing!=null)try {
                serverEditRows(source,incoming,existing)
            }catch(rejected:InvestmentAccountingException) {
                return MockResponse().setResponseCode(400).setBody("local SQL FIFO dependency fixture")
            } else source.rows
            val affected=setOfNotNull(existing?.payload?.financeRawString("asset_id"),incoming?.financeRawString("asset_id"),source.requestedRecord?.payload?.financeRawString("asset_id"))
            val tradeIds=synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.payload.financeRawString("asset_id") in affected}.map{it.id}.toSet()}+requested
            val canonical=tradeIds.flatMap{trade->listOf("funding","capital-return","profit-loss","funding-posting","capital-return-posting","profit-loss-posting","cash-accrual-posting").map{investmentLedgerIdentity(trade,it)}}.toSet()
            for(raw in projected.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id in tradeIds || it.entity in setOf(CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table) && it.id in canonical}) {
                val previous=backend[raw.entity to raw.id]
                if(delete && (previous==null || previous.deletedAt!=null))continue
                val writeDate=if(delete)body.financeRawString("p_modified_at")!! else serverTime
                val requestedComponents=listOf("funding","capital-return","profit-loss","funding-posting","capital-return-posting","profit-loss-posting","cash-accrual-posting").map{investmentLedgerIdentity(requested,it)}.toSet()
                // A delete RPC cannot publish another queued local deletion. Its rebuild only advances that server row.
                if(delete && raw.id!=requested && raw.id !in requestedComponents) {
                    if(previous!=null && previous.deletedAt==null)backend[raw.entity to raw.id]=previous.copy(syncVersion=previous.syncVersion+1,updatedAt=writeDate,
                        payload=JsonObject(previous.payload+buildJsonObject{put("sync_version",previous.syncVersion+1);put("updated_at",writeDate)}))
                    continue
                }
                val version=when {
                    raw.entity==CloudEntity.INVESTMENT_TRADE.table && raw.id==requested->if(delete)base+1 else if(existing==null)2L else incoming!!.financeRawLong("sync_version")!!+1
                    else->(previous?.syncVersion ?: 0L)+1
                }
                val fields=buildJsonObject {
                    if(raw.entity==CloudEntity.INVESTMENT_TRADE.table && raw.id==requested && incoming!=null)incoming.forEach{put(it.key,it.value)}
                    put("sync_version",version);put("updated_at",writeDate)
                    if(delete)put("deleted_at",body.getValue("p_modified_at"))
                }
                val payload=JsonObject((if(delete)previous!!.payload else raw.payload)-LOCAL_TRADE_PUBLICATION_PARENTS_KEY+fields)
                backend[raw.entity to raw.id]=raw.copy(payload=payload,syncVersion=version,updatedAt=writeDate,deletedAt=payload.financeRawString("deleted_at"))
            }
            val callback=onRpc;onRpc=null;if(callback!=null)runBlocking{callback()}
            if(loseReply){loseReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
            return response(synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && if(delete)it.id==requested else it.deletedAt==null && it.payload.financeRawString("asset_id") in affected}})
        }
    }
    /** Mirrors effective SQL's NULL-label update (+1 including tombstones), then active FIFO rebuild (+1).
     * Uses the model only to supply financial fields, never as an independent SQL arithmetic oracle. */
    private fun repairServerLegacyUnits(old:CloudRecord,payload:JsonObject) {
        val cloud=synchronized(backend){backend.values.toList()}
        val metadata=runBlocking{source()}.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}
        val rows=(metadata+cloud).associateBy{it.entity to it.id}.toMutableMap()
        rows[old.entity to old.id]=old
        val current=InvestmentAssetRecord.fromCloudRecord(old)
        val draft=InvestmentAssetDraft(old.id,current.channelId,payload.financeRawString("name")!!,current.currencyCode,
            payload.financeRawString("default_unit_label")!!,current)
        val plan=planInvestmentAssetMutation(InvestmentAssetSnapshot(owner,rows.values.toList()),InvestmentAssetRequest.Save(draft),device,serverTime)
        for((raw,_) in plan.mutations.filter{it.first.entity!=CloudEntity.INVESTMENT_ASSET.table}) {
            val previous=rows[raw.entity to raw.id]
            val isTrade=raw.entity==CloudEntity.INVESTMENT_TRADE.table
            val labelled=isTrade && previous?.payload?.financeRawString("unit_label")==null
            val increments=(if(labelled)1 else 0)+(if(isTrade && raw.deletedAt!=null)0 else 1)
            val version=(previous?.syncVersion ?: 0)+increments
            val fields=JsonObject(raw.payload.filterKeys{!it.startsWith("_mistia_android_")}+buildJsonObject{
                put("sync_version",version);put("updated_at",serverTime);put("last_modified_by_device_id",device)
            })
            backend[raw.entity to raw.id]=raw.copy(payload=fields,syncVersion=version,updatedAt=serverTime)
        }
    }
    private fun serverEditRows(local:InvestmentTradePublicationSnapshot,incoming:JsonObject,existing:CloudRecord):List<CloudRecord> {
        val metadata=local.rows.filter{it.entity !in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}
        val rows=(metadata+synchronized(backend){backend.values.toList()}).associateBy{it.entity to it.id}.values.toList()
        val buying=incoming.financeRawString("kind_raw_value")=="buy"
        val walletId=incoming.financeRawString(if(buying)"funding_wallet_id" else "capital_return_wallet_id")
        val selected=walletId?.let{key->LedgerWalletRecord.fromCloudRecord(rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==key})}
        val accounting=incoming.financeRawLong("accounting_gross_amount_minor")!!
        val code=incoming.financeRawString("accounting_currency_code")!!
        val rate=incoming.financeRawString(if(buying)"funding_to_accounting_rate_decimal_string" else "accounting_to_capital_return_rate_decimal_string")
        val funding=if(buying && selected!=null)investmentPurchaseConvertedMinor(accounting,code,selected.currencyCode,rate,inverse=true) else null
        val target=InvestmentAssetRecord.fromCloudRecord(rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==incoming.financeRawString("asset_id")})
        val draft=InvestmentTradeEditDraft(existing.id,target.id,if(buying)InvestmentTradeKind.BUY else InvestmentTradeKind.SELL,
            incoming.financeRawString("quantity_decimal_string")!!,incoming.financeRawString("unit_label")!!,incoming.financeRawLong("gross_amount_minor")!!,accounting,code,
            incoming.financeRawString("exchange_rate_decimal_string"),incoming.financeRawString("exchange_rate_provider"),incoming.financeRawString("exchange_rate_date"),walletId,funding,rate,
            incoming.financeRawString("note"),incoming.financeRawString("occurred_at")!!,incoming.financeRawString("created_at")!!)
        val request=InvestmentTradeEditRequest(existing,draft,target,selected,null,"Reserve")
        val snapshot=InvestmentTradeCreationSnapshot(owner,rows)
        val plan=try{planInvestmentTradeEdit(snapshot,request,device,serverTime)}catch(review:InvestmentTradeEditConfirmationRequired){
            planInvestmentTradeEdit(snapshot,request.copy(consent=review.review.consent),device,serverTime)
        }
        val keys=plan.mutations.map{it.first.entity to it.first.id}.toSet()
        return rows.filterNot{it.entity to it.id in keys}+plan.mutations.map{it.first}
    }
    private suspend fun buy(cost:Long=70):CloudRecord {
        val s=store.investmentPurchaseSnapshot(owner)
        return repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,asset,"2.5","box",cost,cost,"VND",null,null,null,if(cost>0)wallet else null,if(cost>0)cost else null,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(s.rows.single{it.id==asset}),if(cost>0)LedgerWalletRecord.fromCloudRecord(s.rows.single{it.id==wallet}) else null,null,"Reserve"),device,now).getOrThrow()
    }
    private suspend fun closeThenArchive(archiveChannel:Boolean,cost:Long=0) {
        buy(cost);assertEquals(1,push().pushed)
        val before=source()
        for(row in before.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table)})
            backend[row.entity to row.id]=row
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(before.requestedRecord!!,null,"Reserve"),device,"2026-10-27T01:00:00Z").getOrThrow()
        if(archiveChannel)repo.archiveChannel(owner,InvestmentChannelRecord.fromCloudRecord(source().rows.single{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.id==channel}),device,"2026-10-27T01:01:00Z").getOrThrow()
        else repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==asset}),device,"2026-10-27T01:01:00Z").getOrThrow()
    }
    @Test fun actualOfflineCloseCanPublishBeforeTheQueuedAssetArchive()=runBlocking {
        closeThenArchive(false)
        assertEquals(1,push().pushed)
        val after=source()
        assertFalse(after.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_TRADE})
        assertTrue(after.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_ASSET})
        assertTrue(InvestmentAssetRecord.fromCloudRecord(after.rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==asset}).isArchived)
        assertNotNull(backend[CloudEntity.INVESTMENT_TRADE.table to id]!!.deletedAt)
    }
    @Test fun actualOfflineCloseCanPublishBeforeTheQueuedChannelArchive()=runBlocking {
        closeThenArchive(true)
        assertEquals(1,push().pushed)
        val after=source()
        assertFalse(after.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_TRADE})
        assertTrue(after.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_CHANNEL})
        assertTrue(InvestmentChannelRecord.fromCloudRecord(after.rows.single{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.id==channel}).isArchived)
        assertNotNull(backend[CloudEntity.INVESTMENT_TRADE.table to id]!!.deletedAt)
    }
    @Test fun actualOfflineCloseThenAssetAndChannelArchiveFinishesAcrossTheOrderedPublishers()=runBlocking {
        closeThenArchive(false,70)
        repo.archiveChannel(owner,InvestmentChannelRecord.fromCloudRecord(source().rows.single{it.entity==CloudEntity.INVESTMENT_CHANNEL.table && it.id==channel}),device,"2026-10-27T01:02:00Z").getOrThrow()
        InvestmentPublicationPushCoordinator(channelCoordinator,assetCoordinator,coordinator).pushPending(owner,requireNotNull(session).accessToken)
        assertTrue("Every actual trade/financial/archive proposal must finish",source().pending.isEmpty())
        assertEquals(true,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
        assertEquals(true,backend[CloudEntity.INVESTMENT_CHANNEL.table to channel]!!.payload.financeRawArchived())
    }
    @Test fun actualRenamedAssetAndChannelStageTheirActiveMetadataBeforeClosingAndArchiving()=runBlocking {
        buy(70);assertEquals(1,push().pushed)
        val before=source()
        for(row in before.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table)})backend[row.entity to row.id]=row
        repo.saveAsset(owner,InvestmentAssetDraft(asset,channel,"New cards","VND","box",InvestmentAssetRecord.fromCloudRecord(before.rows.single{it.id==asset})),device,"2026-10-27T01:00:00Z").getOrThrow()
        repo.saveChannel(owner,InvestmentChannelDraft(channel,"New shop",InvestmentChannelRecord.fromCloudRecord(before.rows.single{it.id==channel})),"VND",device,"2026-10-27T01:01:00Z").getOrThrow()
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-27T01:02:00Z").getOrThrow()
        repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-27T01:03:00Z").getOrThrow()
        repo.archiveChannel(owner,InvestmentChannelRecord.fromCloudRecord(source().rows.single{it.id==channel}),device,"2026-10-27T01:04:00Z").getOrThrow()
        val result=InvestmentPublicationPushCoordinator(channelCoordinator,assetCoordinator,coordinator).pushPending(owner,requireNotNull(session).accessToken)
        assertTrue("Renamed metadata and final archive queues must finish: $result",source().pending.isEmpty())
        assertEquals("New cards",backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawString("name"))
        assertEquals("New shop",backend[CloudEntity.INVESTMENT_CHANNEL.table to channel]!!.payload.financeRawString("name"))
        assertEquals(true,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
        assertEquals(true,backend[CloudEntity.INVESTMENT_CHANNEL.table to channel]!!.payload.financeRawArchived())
        val writes=requests.filter{it.method!="GET"}.drop(1)
        assertEquals("/rest/v1/investment_channels",writes[0].requestUrl!!.encodedPath)
        assertEquals(false,Json.parseToJsonElement(writes[0].body.clone().readUtf8()).jsonObject.financeRawArchived())
        assertEquals("/rest/v1/rpc/mutate_investment_asset",writes[1].requestUrl!!.encodedPath)
        assertEquals(false,Json.parseToJsonElement(writes[1].body.clone().readUtf8()).jsonObject.getValue("p_asset").jsonObject.financeRawArchived())
        assertEquals("/rest/v1/rpc/delete_investment_trade",writes[2].requestUrl!!.encodedPath)
    }
    @Test fun legacyNullUnitsAreRepairedBeforeClosingAndArchivingWithoutRecreatingTheTrade()=runBlocking {
        buy(70);assertEquals(1,push().pushed);seedCloudMetadata()
        for((entity,key,field) in listOf(Triple(CloudEntity.INVESTMENT_ASSET,asset,"default_unit_label"),Triple(CloudEntity.INVESTMENT_TRADE,id,"unit_label"))) {
            val old=backend[entity.table to key]!!
            val legacy=old.copy(payload=JsonObject(old.payload+(field to JsonNull)))
            backend[entity.table to key]=legacy
            store.replacePullSnapshot(owner,entity.table,listOf(legacy))
        }
        val current=InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset})
        repo.saveAsset(owner,InvestmentAssetDraft(asset,channel,"Cards","VND","box",current),device,"2026-10-27T00:01:00Z").getOrThrow()
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-27T00:02:00Z").getOrThrow()
        repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-27T00:03:00Z").getOrThrow()
        val result=publishAll()
        assertTrue("Unit repair and final close/archive must finish: $result",source().pending.isEmpty())
        val trade=backend[CloudEntity.INVESTMENT_TRADE.table to id]!!
        assertEquals("box",trade.payload.financeRawString("unit_label"));assertNotNull(trade.deletedAt)
        assertEquals(5L,trade.syncVersion) // original2 + label1 + rebuild1 + delete1
        val deletes=requests.filter{it.requestUrl!!.encodedPath=="/rest/v1/rpc/delete_investment_trade"}
        assertEquals(1,deletes.size)
        assertEquals(4L,Json.parseToJsonElement(deletes.single().body.clone().readUtf8()).jsonObject.financeRawLong("p_expected_version"))
        assertEquals(1,requests.count{it.requestUrl!!.encodedPath=="/rest/v1/rpc/mutate_investment_trade"})
        assertEquals(true,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
    }
    @Test fun legacyDeletedUnitsAreLabelledOnceWithoutSendingAnotherDelete()=runBlocking {
        buy(70);assertEquals(1,push().pushed)
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-27T00:00:00Z").getOrThrow()
        assertEquals(1,push().pushed);seedCloudMetadata()
        for((entity,key,field) in listOf(Triple(CloudEntity.INVESTMENT_ASSET,asset,"default_unit_label"),Triple(CloudEntity.INVESTMENT_TRADE,id,"unit_label"))) {
            val old=backend[entity.table to key]!!;val legacy=old.copy(payload=JsonObject(old.payload+(field to JsonNull)))
            backend[entity.table to key]=legacy;store.replacePullSnapshot(owner,entity.table,listOf(legacy))
        }
        val current=InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset})
        repo.saveAsset(owner,InvestmentAssetDraft(asset,channel,"Cards","VND","box",current),device,"2026-10-27T00:01:00Z").getOrThrow()
        assertEquals(MutationKind.DELETE,source().requestedQueue!!.mutation.kind)
        repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-27T00:02:00Z").getOrThrow()
        val result=publishAll()
        assertTrue("Deleted history unit repair must finish: $result",source().pending.isEmpty())
        val trade=backend[CloudEntity.INVESTMENT_TRADE.table to id]!!
        assertNotNull(trade.deletedAt);assertEquals("box",trade.payload.financeRawString("unit_label"));assertEquals(4L,trade.syncVersion)
        assertEquals(1,requests.count{it.requestUrl!!.encodedPath=="/rest/v1/rpc/delete_investment_trade"})
        assertEquals(1,requests.count{it.requestUrl!!.encodedPath=="/rest/v1/rpc/mutate_investment_trade"})
    }
    @Test fun sweepingDueMetadataCannotBypassAnotherAssetsFutureRetryTime()=runBlocking {
        val target="88888888-8888-8888-8888-888888888888"
        cleanMetadata(InvestmentAssetRecord(target,owner.value,channel,"Later cards","VND",null,"box",0,false,null,now,now,null,0,device).toCloudRecord())
        seedCloudMetadata()
        for(key in listOf(asset,target)) {
            val current=InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==key})
            repo.saveAsset(owner,InvestmentAssetDraft(key,channel,"Changed $key","VND","box",current),device,"2026-10-27T00:01:00Z").getOrThrow()
        }
        val queued=source().pending.single{it.mutation.recordId==target}
        assertTrue(store.recordInvestmentAssetMutationFailure(queued,clock+9000,"network_io"))
        val before=store.reconcileInvestmentAssetImagePublication(owner,target)
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).pushed)
        assertEquals(before,store.reconcileInvestmentAssetImagePublication(owner,target))
        assertFalse(requests.any{request->request.requestUrl!!.queryParameterValues("id").any{it=="eq.$target"} ||
            request.requestUrl!!.encodedPath=="/rest/v1/rpc/mutate_investment_asset" && request.body.clone().readUtf8().contains(target)})
    }
    @Test fun aNewCloudAssetBetweenHistoryReadsDoesNotPermanentlyFailTheArchive()=runBlocking {
        closeThenArchive(true,70)
        val before=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_CHANNEL}
        beforeRead={request->
            if(request.requestUrl!!.encodedPath=="/rest/v1/investment_trades" && request.requestUrl!!.queryParameter("channel_id")=="eq.$channel") {
                beforeRead=null
                val extra="88888888-8888-8888-8888-888888888888"
                val cloudAsset=InvestmentAssetRecord(extra,owner.value,channel,"Concurrent asset","VND",null,"box",1,false,null,now,now,null,1,device).toCloudRecord()
                backend[cloudAsset.entity to cloudAsset.id]=cloudAsset
                val rows=(source().rows.filter{it.entity!=CloudEntity.INVESTMENT_TRADE.table}.map{row->if(row.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table))backend[row.entity to row.id] ?: row else row}+listOf(cloudAsset)).associateBy{it.entity to it.id}.values.toList()
                val plan=planInvestmentPurchase(InvestmentPurchaseSnapshot(owner,rows),InvestmentPurchaseRequest(
                    InvestmentPurchaseDraft("99999999-9999-9999-9999-999999999999",extra,"1","box",0,0,"VND",null,null,null,null,null,null,null,now,now),
                    InvestmentAssetRecord.fromCloudRecord(cloudAsset),null,null,"Reserve"),device,now)
                val cloud=plan.trade.copy(syncVersion=2,payload=JsonObject(plan.trade.payload+("sync_version" to JsonPrimitive(2))))
                backend[cloud.entity to cloud.id]=cloud
            }
        }
        val first=channelCoordinator.pushPending(owner,session!!.accessToken)
        assertEquals(0,first.permanentFailures)
        assertEquals(before,source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_CHANNEL})
        assertEquals(DomainPushSummary(),channelCoordinator.pushPending(owner,session!!.accessToken))
        assertEquals(before,source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_CHANNEL})
        assertFalse(backend[CloudEntity.INVESTMENT_CHANNEL.table to channel]!!.payload.financeRawArchived()!!)
        val concurrent=backend[CloudEntity.INVESTMENT_TRADE.table to "99999999-9999-9999-9999-999999999999"]!!
        backend[concurrent.entity to concurrent.id]=concurrent.copy(deletedAt=serverTime,updatedAt=serverTime,syncVersion=3,
            payload=JsonObject(concurrent.payload+buildJsonObject{put("deleted_at",serverTime);put("updated_at",serverTime);put("sync_version",3)}))
        publishAll()
        assertTrue(source().pending.isEmpty())
        assertEquals(true,backend[CloudEntity.INVESTMENT_CHANNEL.table to channel]!!.payload.financeRawArchived())
    }
    private suspend fun seedBlockedArchives(entity:CloudEntity) {
        val existingTrade=backend[CloudEntity.INVESTMENT_TRADE.table to id]!!
        val separateChannel="d0000000-0000-4000-8000-000000000000"
        if(entity==CloudEntity.INVESTMENT_ASSET) {
            cleanMetadata(InvestmentChannelRecord(separateChannel,owner.value,"Blocked branch","shippingbox.fill","#9A67FF",2,false,null,now,now,null,0,device).toCloudRecord())
            backend[CloudEntity.INVESTMENT_CHANNEL.table to separateChannel]=source().rows.single{it.id==separateChannel}
        }
        for(index in 0 until 100) {
            val blocked="a000%04x-0000-4000-8000-000000000000".format(index)
            val blockedAsset=if(entity==CloudEntity.INVESTMENT_ASSET)blocked else "b000%04x-0000-4000-8000-000000000000".format(index)
            val parent=if(entity==CloudEntity.INVESTMENT_CHANNEL)blocked else separateChannel
            val assetRow=InvestmentAssetRecord(blockedAsset,owner.value,parent,"Blocked $index","VND",null,"box",0,false,null,now,now,null,1,device).toCloudRecord()
            backend[assetRow.entity to assetRow.id]=assetRow
            val raw=if(entity==CloudEntity.INVESTMENT_ASSET)assetRow else InvestmentChannelRecord(blocked,owner.value,"Blocked $index","shippingbox.fill","#9A67FF",index,false,null,now,now,null,1,device).toCloudRecord()
            backend[raw.entity to raw.id]=raw
            val archived=raw.copy(payload=JsonObject(raw.payload+buildJsonObject{put("is_archived",true);put("archived_at",now)}))
            store.commitMutation(archived,PendingMutation(entity,blocked,owner.value,MutationKind.UPSERT,archived.payload,now,1,device))
            val tradeId="c000%04x-0000-4000-8000-000000000000".format(index)
            val trade=existingTrade.copy(id=tradeId,payload=JsonObject(existingTrade.payload+buildJsonObject{
                put("id",tradeId);put("asset_id",blockedAsset);put("channel_id",parent)
                for(field in listOf("gross_amount_minor","accounting_gross_amount_minor","released_cost_basis_minor","realized_profit_loss_minor","position_cost_basis_after_minor"))put(field,0)
                for(field in listOf("funding_wallet_id","funding_wallet_currency_code","funding_wallet_amount_minor","funding_ledger_transaction_id","funding_to_accounting_rate_decimal_string"))put(field,JsonNull)
            }))
            backend[trade.entity to trade.id]=trade
        }
    }
    @Test fun movedTradeFinishesBeforeRetiringItsOriginalAssetAndChannel()=runBlocking {
        moveThenRetireOriginal(false)
    }
    @Test fun renamedMoveTargetIsPublishedBeforeMovingAndRetiringTheOriginalBranch()=runBlocking {
        moveThenRetireOriginal(true)
    }
    @Test fun aBlockedAssetBacklogCannotStarveTheDueMoveTarget()=runBlocking {
        moveThenRetireOriginal(true,CloudEntity.INVESTMENT_ASSET)
    }
    @Test fun aBlockedChannelBacklogCannotStarveTheDueMoveTarget()=runBlocking {
        moveThenRetireOriginal(true,CloudEntity.INVESTMENT_CHANNEL)
    }
    @Test fun aNewChannelAndAssetAreCreatedBeforeMovingAndRetiringTheOldBranch()=runBlocking {
        moveThenRetireOriginal(false,newTarget=true)
    }
    private suspend fun moveThenRetireOriginal(renameTarget:Boolean,blockedDomain:CloudEntity?=null,newTarget:Boolean=false) {
        buy(70);assertEquals(1,push().pushed)
        val target="88888888-8888-8888-8888-888888888888"
        val targetChannel="99999999-9999-9999-9999-999999999999"
        if(newTarget) {
            seedCloudMetadata()
            repo.saveChannel(owner,InvestmentChannelDraft(targetChannel,"Other shop"),"VND",device,"2026-10-27T00:00:01Z").getOrThrow()
            repo.saveAsset(owner,InvestmentAssetDraft(target,targetChannel,"Other cards","VND","box"),device,"2026-10-27T00:00:02Z").getOrThrow()
        } else {
            cleanMetadata(InvestmentChannelRecord(targetChannel,owner.value,"Other shop","shippingbox.fill","#9A67FF",1,false,null,now,now,null,0,device).toCloudRecord())
            cleanMetadata(InvestmentAssetRecord(target,owner.value,targetChannel,"Other cards","VND",null,"box",0,false,null,now,now,null,0,device).toCloudRecord())
            seedCloudMetadata()
        }
        validateEditsAgainstBackendHistory=true
        if(blockedDomain!=null)seedBlockedArchives(blockedDomain)
        if(renameTarget) {
            repo.saveChannel(owner,InvestmentChannelDraft(targetChannel,"Target shop",InvestmentChannelRecord.fromCloudRecord(source().rows.single{it.id==targetChannel})),"VND",device,"2026-10-27T00:01:00Z").getOrThrow()
            repo.saveAsset(owner,InvestmentAssetDraft(target,targetChannel,"Target cards","VND","box",InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==target})),device,"2026-10-27T00:02:00Z").getOrThrow()
        }
        val context=source();val raw=context.requestedRecord!!
        repo.editTrade(owner,InvestmentTradeEditRequest(raw,InvestmentTradeEditDraft(id,target,InvestmentTradeKind.BUY,"2.5","box",70,70,"VND",null,null,null,wallet,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==target}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,"2026-10-27T00:03:00Z").getOrThrow()
        repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-27T00:04:00Z").getOrThrow()
        repo.archiveChannel(owner,InvestmentChannelRecord.fromCloudRecord(source().rows.single{it.id==channel}),device,"2026-10-27T00:05:00Z").getOrThrow()
        val result=publishAll()
        val left=source().pending
        assertEquals("Only deliberately blocked unrelated archives may remain: $result, ${left.map{it.mutation.entity.table+":"+it.mutation.recordId+":"+it.lastError}}",if(blockedDomain==null)0 else 100,left.size)
        assertTrue(left.all{it.mutation.entity==blockedDomain && it.mutation.recordId.startsWith("a000")})
        assertEquals(target,backend[CloudEntity.INVESTMENT_TRADE.table to id]!!.payload.financeRawString("asset_id"))
        assertEquals(targetChannel,backend[CloudEntity.INVESTMENT_TRADE.table to id]!!.payload.financeRawString("channel_id"))
        assertEquals(true,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
        assertEquals(true,backend[CloudEntity.INVESTMENT_CHANNEL.table to channel]!!.payload.financeRawArchived())
        assertEquals(false,backend[CloudEntity.INVESTMENT_ASSET.table to target]!!.payload.financeRawArchived())
        assertEquals(false,backend[CloudEntity.INVESTMENT_CHANNEL.table to targetChannel]!!.payload.financeRawArchived())
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to investmentLedgerIdentity(id,"funding")]!!.payload.financeRawLong("amount_minor"))
        val writes=requests.filter{it.method!="GET"}.drop(1)
        val move=writes.indexOfFirst{it.requestUrl!!.encodedPath=="/rest/v1/rpc/mutate_investment_trade"}
        val oldArchive=writes.indexOfFirst{it.requestUrl!!.encodedPath=="/rest/v1/rpc/mutate_investment_asset" &&
            Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject.getValue("p_asset").jsonObject.let{p->p.financeRawString("id")==asset && p.financeRawArchived()==true}}
        assertTrue("Old asset archive follows the actual move",move>=0 && oldArchive>move)
        if(renameTarget)assertEquals("Target cards",backend[CloudEntity.INVESTMENT_ASSET.table to target]!!.payload.financeRawString("name"))
    }
    private suspend fun assetStage() {
        buy(70);assertEquals(1,push().pushed);val before=source()
        for(row in before.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table)})backend[row.entity to row.id]=row
        repo.saveAsset(owner,InvestmentAssetDraft(asset,channel,"New cards","VND","box",InvestmentAssetRecord.fromCloudRecord(before.rows.single{it.id==asset})),device,"2026-10-26T00:05:00Z").getOrThrow()
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-26T00:06:00Z").getOrThrow()
        repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-26T00:07:00Z").getOrThrow()
    }
    private suspend fun seedCloudMetadata() {
        for(row in source().rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table)})backend[row.entity to row.id]=row
    }
    private fun jpeg(color:Int):ByteArray {
        val bitmap=Bitmap.createBitmap(8,4,Bitmap.Config.ARGB_8888);bitmap.eraseColor(color)
        return try{ByteArrayOutputStream().use{bitmap.compress(Bitmap.CompressFormat.JPEG,90,it);it.toByteArray()}}finally{bitmap.recycle()}
    }
    private suspend fun photo(color:Int,name:String="Cards",date:String="2026-10-26T00:05:00Z"):InvestmentAssetRecord {
        val bytes=jpeg(color);val candidate=repo.stageProductImage(owner,asset,PreparedInvestmentProductImage(bytes,bytes,"image/jpeg",8,4)).getOrThrow()
        val current=InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset})
        return repo.saveAssetImage(owner,InvestmentAssetDraft(asset,channel,name,"VND","box",current,
            InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,asset,candidate.path))),candidate,UUID.randomUUID().toString(),device,date).getOrThrow()
    }
    private suspend fun closeAndArchivePhoto() {
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-27T00:00:00Z").getOrThrow()
        repo.archiveAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-27T00:01:00Z").getOrThrow()
    }
    private suspend fun addCloudPosition() {
        val original=source();val current=backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!
        val rows=original.rows.map{row->if(row.entity in setOf(CloudEntity.INVESTMENT_ASSET.table,CloudEntity.INVESTMENT_CHANNEL.table))backend[row.entity to row.id] ?: row else row}
        val extra="77777777-7777-7777-7777-777777777777"
        val plan=planInvestmentPurchase(InvestmentPurchaseSnapshot(owner,rows),InvestmentPurchaseRequest(InvestmentPurchaseDraft(extra,asset,"1","box",0,0,"VND",null,null,null,null,null,null,null,"2026-10-27T02:00:00Z",now),
            InvestmentAssetRecord.fromCloudRecord(current),null,null,"Reserve"),device,now)
        val cloud=plan.trade.copy(syncVersion=2,payload=JsonObject(plan.trade.payload+("sync_version" to JsonPrimitive(2))))
        backend[cloud.entity to cloud.id]=cloud
    }
    private suspend fun restoreAndRenameAfterStage() {
        repo.restoreAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-26T00:14:00Z").getOrThrow()
        repo.saveAsset(owner,InvestmentAssetDraft(asset,channel,"Later local name","VND","box",InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset})),device,"2026-10-26T00:15:00Z").getOrThrow()
    }
    private fun metadataWrites()=requests.filter{it.method!="GET" && it.requestUrl!!.encodedPath in setOf("/rest/v1/investment_channels","/rest/v1/rpc/mutate_investment_asset")}
    private suspend fun publishAll():DomainPushSummary {
        val root=rootCoordinator.pushPending(owner,requireNotNull(session).accessToken)
        assertEquals("Root metadata prerequisite must succeed",0,root.conflicts+root.retryableFailures+root.permanentFailures)
        return InvestmentPublicationPushCoordinator(channelCoordinator,assetCoordinator,coordinator).pushPending(owner,requireNotNull(session).accessToken)
    }
    @Test fun lostStageReplyBacksOffThePreparedQueueThenRecoversWithoutReplayingItsWrite()=runBlocking {
        assetStage();loseMetadataReply=true
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).retryableFailures)
        val queued=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}
        assertEquals(1,queued.attemptCount);assertEquals(34000L,queued.nextAttemptAtEpochMillis);assertEquals(1L,queued.mutation.baseVersion)
        assertEquals(2L,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.syncVersion)
        val count=metadataWrites().size;clock=40000
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).reconciled)
        assertEquals(count,metadataWrites().size);assertEquals(2L,source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}.mutation.baseVersion)
        publishAll();assertTrue(source().pending.isEmpty());assertEquals(true,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
    }
    @Test fun aDefiniteStageDoesNotEraseANewerActualRestoreAndNameWithAnEarlierClientClock()=runBlocking {
        assetStage();onMetadataCommit={_,_->restoreAndRenameAfterStage()}
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).reconciled)
        val row=source().rows.single{it.id==asset};assertEquals("Later local name",row.payload.financeRawString("name"));assertEquals(false,row.payload.financeRawArchived())
        assertEquals("2026-10-26T00:15:00Z",row.updatedAt);assertEquals(2L,row.syncVersion)
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).pushed)
        assertEquals(1,push().pushed);assertTrue(source().pending.isEmpty())
        assertEquals("Later local name",backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawString("name"));assertEquals(false,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
    }
    @Test fun aStage503RecordsRetryAgainstTheExactPreparedGeneration()=runBlocking {
        assetStage();metadataFailure=503
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).retryableFailures)
        val q=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}
        assertEquals("http_503",q.lastError);assertEquals(1,q.attemptCount);assertEquals(34000L,q.nextAttemptAtEpochMillis)
        assertEquals(1L,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.syncVersion)
        clock=40000;publishAll();assertTrue(source().pending.isEmpty())
    }
    @Test fun anOlderStage403CannotFailOrBackoffANewerActualRestoreAndName()=runBlocking {
        assetStage();beforeMetadataWrite={_,_->restoreAndRenameAfterStage()};metadataFailure=403
        val result=assetCoordinator.pushPending(owner,session!!.accessToken)
        assertEquals(1,result.staleResponses);assertEquals(0,result.permanentFailures)
        val q=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}
        assertEquals(0,q.attemptCount);assertEquals(0L,q.nextAttemptAtEpochMillis);assertNull(q.lastError)
        assertEquals("Later local name",q.mutation.payload!!.financeRawString("name"))
        publishAll();assertTrue(source().pending.isEmpty());assertEquals(false,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawArchived())
    }
    @Test fun aSessionRotatedDuringStageCommitCannotRebaseAndTheNextSessionRecoversIt()=runBlocking {
        assetStage();onMetadataCommit={_,_->session=session!!.copy(accessToken="rotated-local-token")}
        assertTrue(runCatching{assetCoordinator.pushPending(owner,"local-contract-token")}.exceptionOrNull() is CancellationException)
        val q=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET};assertEquals(1L,q.mutation.baseVersion);assertEquals(0,q.attemptCount)
        val count=metadataWrites().size
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).reconciled);assertEquals(count,metadataWrites().size)
        publishAll();assertTrue(source().pending.isEmpty())
    }
    @Test fun aNewCloudPositionAfterClosureProofKeepsTheFinalArchiveRetryable()=runBlocking {
        closeThenArchive(false,70);assertEquals(1,push().pushed)
        beforeMetadataWrite={_,_->addCloudPosition()}
        val result=assetCoordinator.pushPending(owner,session!!.accessToken)
        assertEquals(1,result.retryableFailures);assertEquals(0,result.permanentFailures)
        val q=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}
        assertEquals("http_400",q.lastError);assertEquals(34000L,q.nextAttemptAtEpochMillis)
        clock=40000;val count=metadataWrites().size
        assertEquals(DomainPushSummary(),assetCoordinator.pushPending(owner,session!!.accessToken));assertEquals(count,metadataWrites().size)
    }
    @Test fun aNewCloudPositionAlsoKeepsTheFinalChannelArchiveRetryable()=runBlocking {
        closeThenArchive(true,70);assertEquals(1,push().pushed);beforeMetadataWrite={_,_->addCloudPosition()}
        val result=channelCoordinator.pushPending(owner,session!!.accessToken)
        assertEquals(1,result.retryableFailures);assertEquals(0,result.permanentFailures)
        assertEquals(34000L,source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_CHANNEL}.nextAttemptAtEpochMillis)
        clock=40000;val count=metadataWrites().size
        assertEquals(DomainPushSummary(),channelCoordinator.pushPending(owner,session!!.accessToken));assertEquals(count,metadataWrites().size)
    }
    @Test fun aStage403RemainsPermanentForItsExactPreparedIntent()=runBlocking {
        assetStage();metadataFailure=403;val result=assetCoordinator.pushPending(owner,session!!.accessToken)
        assertEquals(1,result.permanentFailures);assertEquals(0,result.retryableFailures)
        val q=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}
        assertEquals("http_403",q.lastError);assertEquals(Long.MAX_VALUE,q.nextAttemptAtEpochMillis)
    }
    @Test fun aFinalArchive403IsNotChangedToAnArchiveRaceRetry()=runBlocking {
        closeThenArchive(false,70);assertEquals(1,push().pushed);metadataFailure=403
        val result=assetCoordinator.pushPending(owner,session!!.accessToken)
        assertEquals(1,result.permanentFailures);assertEquals(0,result.retryableFailures)
        val q=source().pending.single{it.mutation.entity==CloudEntity.INVESTMENT_ASSET}
        assertEquals("http_403",q.lastError);assertEquals(Long.MAX_VALUE,q.nextAttemptAtEpochMillis)
    }
    @Test fun aReplacementPhotoUploadsBeforeItsActiveStageAndRetiresOldBytesOnlyAfterFinalArchiveAck()=runBlocking {
        seedCloudMetadata();val first=photo(android.graphics.Color.BLUE);assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).pushed)
        buy(70);assertEquals(1,push().pushed);val replacement=photo(android.graphics.Color.RED,"New cards","2026-10-26T00:15:00Z");closeAndArchivePhoto()
        val start=requests.size
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).reconciled)
        val stageRequests=requests.drop(start)
        val upload=stageRequests.indexOfFirst{it.method=="POST" && it.requestUrl!!.encodedPath==objectPrefix+replacement.imagePath}
        val rpc=stageRequests.indexOfFirst{it.requestUrl!!.encodedPath=="/rest/v1/rpc/mutate_investment_asset"}
        assertTrue(upload>=0 && rpc>upload);assertArrayEquals(jpeg(android.graphics.Color.RED),objects[replacement.imagePath])
        assertTrue(objects.containsKey(first.imagePath));assertTrue(source().pending.any{it.mutation.entity==CloudEntity.INVESTMENT_ASSET})
        publishAll();assertTrue(source().pending.isEmpty());assertEquals(replacement.imagePath,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawString("image_path"))
        assertFalse(objects.containsKey(first.imagePath));assertTrue(objects.containsKey(replacement.imagePath))
    }
    @Test fun aNewerActualPhotoAfterTheActiveStageCannotBeReplacedByTheOlderStageReply()=runBlocking {
        seedCloudMetadata();photo(android.graphics.Color.BLUE);assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).pushed)
        buy(70);assertEquals(1,push().pushed);val staged=photo(android.graphics.Color.RED,"New cards","2026-10-26T00:15:00Z");closeAndArchivePhoto()
        var newer:InvestmentAssetRecord?=null
        onMetadataCommit={_,_->
            repo.restoreAsset(owner,InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset}),device,"2026-10-27T00:14:00Z").getOrThrow()
            newer=photo(android.graphics.Color.GREEN,"Later photo","2026-10-27T00:15:00Z")
        }
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).reconciled)
        assertEquals(newer!!.imagePath,source().rows.single{it.id==asset}.payload.financeRawString("image_path"));assertEquals(staged.imagePath,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawString("image_path"))
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).pushed);assertEquals(1,push().pushed)
        assertTrue(source().pending.isEmpty());assertEquals(newer!!.imagePath,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawString("image_path"))
        assertArrayEquals(jpeg(android.graphics.Color.GREEN),objects[newer!!.imagePath])
    }
    @Test fun keepingAnAlreadyAcknowledgedPhotoCanAdoptANewerServerPhotoWithoutRetainingItsOldPrivateIntent()=runBlocking {
        seedCloudMetadata();buy(70);assertEquals(1,push().pushed);photo(android.graphics.Color.BLUE)
        onMetadataCommit={_,_->
            repo.saveAsset(owner,InvestmentAssetDraft(asset,channel,"New cards","VND","box",InvestmentAssetRecord.fromCloudRecord(source().rows.single{it.id==asset})),device,"2026-10-26T00:15:00Z").getOrThrow()
        }
        assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).staleResponses)
        assertTrue(store.reconcileInvestmentAssetImagePublication(owner,asset).imageAcknowledged)
        val next=InvestmentProductImagePath.create(owner,asset,"88888888-8888-8888-8888-888888888888").value;objects[next]=jpeg(android.graphics.Color.GREEN)
        val old=backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!
        backend[old.entity to old.id]=old.copy(syncVersion=3,payload=JsonObject(old.payload+buildJsonObject{put("sync_version",3);put("image_path",next);put("last_modified_by_device_id","99999999-9999-9999-9999-999999999999")}))
        closeAndArchivePhoto();assertEquals(1,assetCoordinator.pushPending(owner,session!!.accessToken).reconciled)
        val current=source().rows.single{it.id==asset};assertEquals(next,current.payload.financeRawString("image_path"));assertNull(localAssetImagePublication(current))
        publishAll();assertTrue(source().pending.isEmpty());assertEquals(next,backend[CloudEntity.INVESTMENT_ASSET.table to asset]!!.payload.financeRawString("image_path"))
    }
    private suspend fun editNote() {
        val s=store.investmentPurchaseSnapshot(owner);val old=s.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}
        repo.editTrade(owner,InvestmentTradeEditRequest(old,InvestmentTradeEditDraft(id,asset,InvestmentTradeKind.BUY,"2.5","box",70,70,"VND",null,null,null,wallet,70,null,"New local note",now,now),
            InvestmentAssetRecord.fromCloudRecord(s.rows.single{it.id==asset}),LedgerWalletRecord.fromCloudRecord(s.rows.single{it.id==wallet}),null,"Reserve"),device,"2026-10-26T00:15:00Z").getOrThrow()
    }
    private suspend fun source()=store.investmentTradePublicationSnapshot(owner,id)
    private suspend fun push()=coordinator.pushPending(owner,requireNotNull(session).accessToken)
    private fun rpcRequests()=requests.filter{it.requestUrl!!.encodedPath.contains("/rpc/")}
    @Test fun actualBuyUsesAuthenticatedClosedRpcAndClearsTradeLedgerAndPostingTogether()=runBlocking {
        buy();assertEquals(3,source().pending.size);assertEquals(1,push().pushed)
        val after=source();assertTrue(after.pending.isEmpty());assertEquals(2L,after.requestedRecord!!.syncVersion)
        assertEquals(70L,after.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
        assertEquals(-70L,after.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.payload.financeRawLong("amount_minor"));assertEquals(1,rpcRequests().size)
    }
    @Test fun actualPromotionalBuyHasNoFundingLegOrInventedWalletDebit()=runBlocking {
        buy(0);assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty())
        assertFalse(after.rows.any{it.entity in setOf(CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)})
    }
    @Test fun lateActualEditSurvivesTheOlderDefiniteRpcAndThenUsesItsComparedVersion()=runBlocking {
        buy();onRpc={editNote()};assertEquals(1,push().staleResponses)
        val current=source();assertEquals("New local note",current.requestedRecord!!.payload.financeRawString("note"));assertEquals(0,current.requestedQueue!!.attemptCount)
        assertEquals(1,push().pushed);assertTrue(source().pending.isEmpty())
        assertEquals(listOf(0L,2L),rpcRequests().map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject.financeRawLong("p_expected_version")})
        assertEquals(4L,source().requestedRecord!!.syncVersion)
    }
    @Test fun lostReplyIsRecoveredByCompleteSemanticAckWithoutReplayingTheRpc()=runBlocking {
        buy();loseReply=true;assertEquals(1,push().retryableFailures);assertEquals(3,source().pending.size)
        clock=100_000;assertEquals(1,push().acknowledged);assertTrue(source().pending.isEmpty());assertEquals(1,rpcRequests().size)
    }
    @Test fun malformedFinancialReadCannotPartiallyAcknowledgeTheAcceptedTrade()=runBlocking {
        buy();corruptFinancial=true;assertEquals(1,push().retryableFailures);assertEquals(3,source().pending.size);assertEquals(3,source().dirtyKeys.size)
        corruptFinancial=false;clock=100_000;assertEquals(1,push().acknowledged);assertTrue(source().pending.isEmpty());assertEquals(1,rpcRequests().size)
    }
    @Test fun tokenReplacementDuringRpcRevokesReceiptAndAllFinancialAcknowledgement()=runBlocking {
        buy();val before=source();val old=session;onRpc={session=session!!.copy(accessToken="rotated")}
        assertTrue(runCatching{push()}.exceptionOrNull() is CancellationException);session=old;assertEquals(before,source())
    }
    @Test fun closedClientGateRejectsActualHttpWriteAndKeepsAllQueues()=runBlocking {
        buy();enabled=false;val result=push();assertEquals(1,result.permanentFailures)
        assertTrue(rpcRequests().isEmpty());assertEquals(3,source().pending.size)
    }
    @Test fun actualNeverPublishedDeletionUsesAbsenceProofAndSendsNoDeleteRpc()=runBlocking {
        val raw=buy();repo.deleteTrade(owner,InvestmentTradeDeletionRequest(raw,null,"Reserve"),device,now).getOrThrow()
        assertEquals(1,push().acknowledged);assertTrue(source().pending.isEmpty());assertTrue(rpcRequests().isEmpty())
    }
    @Test fun actualPublishedDeletionUsesTheClosedDeleteRpcAndImportsAllTombstones()=runBlocking {
        buy();assertEquals(1,push().pushed);val raw=source().requestedRecord!!
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(raw,null,"Reserve"),device,now).getOrThrow()
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty());assertEquals(3L,after.requestedRecord!!.syncVersion)
        assertTrue(after.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.all{it.deletedAt!=null})
        assertEquals("/rest/v1/rpc/delete_investment_trade",rpcRequests().last().requestUrl!!.encodedPath)
    }
    private suspend fun cleanMetadata(row:CloudRecord) {
        val entity=CloudEntity.fromTable(row.entity)!!
        store.commitMutation(row,PendingMutation(entity,row.id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device))
        val q=store.pendingMutations(owner,entity,Long.MAX_VALUE).single{it.mutation.recordId==row.id}
        assertTrue(store.acknowledgeMutation(q,row.copy(syncVersion=row.syncVersion+1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(row.syncVersion+1))))))
    }
    @Test fun exactFxBuyKeepsJpyFundingAndVndAccountingAmountsPairedThroughActualRoomAndHttps()=runBlocking {
        for((entity,identity) in listOf(CloudEntity.LEDGER_WALLET to wallet,CloudEntity.INVESTMENT_ASSET to asset)) {
            val raw=store.record(owner,entity.table,identity)!!
            cleanMetadata(raw.copy(payload=JsonObject(raw.payload+("currency_code" to JsonPrimitive("JPY")))))
        }
        val context=store.investmentPurchaseSnapshot(owner)
        repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,asset,"2.5","box",70,11550,"VND","165",null,null,wallet,70,"165",null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,now).getOrThrow()
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty())
        val ledger=after.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table};assertEquals(70L,ledger.payload.financeRawLong("amount_minor"));assertEquals("JPY",ledger.payload.financeRawString("source_currency_code"))
        assertEquals(11550L,ledger.payload.financeRawLong("reporting_amount_minor"));assertEquals("VND",ledger.payload.financeRawString("reporting_currency_code"))
        val posting=after.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table};assertEquals(-70L,posting.payload.financeRawLong("amount_minor"));assertEquals(-11550L,posting.payload.financeRawLong("accounting_amount_minor"))
    }
    private suspend fun sell(gross:Long):String {
        val saleId="77777777-7777-7777-7777-777777777777";val context=store.investmentPurchaseSnapshot(owner)
        repo.saveSale(owner,InvestmentSaleRequest(InvestmentSaleDraft(saleId,asset,"1","box",gross,gross,"VND",null,null,null,if(gross>0)wallet else null,null,null,"2026-10-26T00:01:00Z",now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),if(gross>0)LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}) else null,null,"Reserve"),device,now).getOrThrow()
        return saleId
    }
    @Test fun actualSaleReconcilesCapitalProfitAndBookedCashAlongsideTheRebuiltBuy()=runBlocking {
        buy();assertEquals(1,push().pushed);val saleId=sell(80)
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty())
        val sale=after.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        assertEquals(28L,sale.payload.financeRawLong("released_cost_basis_minor"));assertEquals(52L,sale.payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals(52L,after.rows.single{it.id==investmentLedgerIdentity(saleId,"cash-accrual-posting")}.payload.financeRawLong("amount_minor"))
        assertEquals(3L,after.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}.syncVersion)
    }
    @Test fun zeroValueSalePublishesTheExactLossWithoutInventingAnOrdinaryWalletReceipt()=runBlocking {
        buy();assertEquals(1,push().pushed);val saleId=sell(0)
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty())
        val sale=after.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}
        assertEquals(-28L,sale.payload.financeRawLong("realized_profit_loss_minor"))
        val posting=after.rows.single{it.id==investmentLedgerIdentity(saleId,"cash-accrual-posting")}
        assertEquals(investmentSystemWalletId(owner),posting.payload.financeRawString("wallet_id"));assertEquals(-28L,posting.payload.financeRawLong("amount_minor"))
        assertFalse(after.rows.any{it.id==investmentLedgerIdentity(saleId,"capital-return")})
    }
    @Test fun reassignmentUsesTheComparedOriginalAndTargetAssetHistoriesBeforeAtomicAcknowledgement()=runBlocking {
        buy();assertEquals(1,push().pushed)
        val target="88888888-8888-8888-8888-888888888888"
        cleanMetadata(InvestmentAssetRecord(target,owner.value,channel,"Other cards","VND",null,"box",0,false,null,now,now,null,0,device).toCloudRecord())
        val context=store.investmentPurchaseSnapshot(owner);val raw=context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}
        repo.editTrade(owner,InvestmentTradeEditRequest(raw,InvestmentTradeEditDraft(id,target,InvestmentTradeKind.BUY,"2.5","box",70,70,"VND",null,null,null,wallet,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==target}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,now).getOrThrow()
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty());assertEquals(target,after.requestedRecord!!.payload.financeRawString("asset_id"))
        assertEquals(target,after.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.payload.financeRawString("asset_id"))
        assertTrue(requests.any{it.requestUrl!!.queryParameter("asset_id")?.let{filter->filter.contains(asset) && filter.contains(target)}==true})
    }

    @Test fun queuedSalesDeleteBeforeAcquisitionsAndOwnRebuildCannotEraseThePendingBuyDeletion()=runBlocking {
        buy();val saleId=sell(80);assertEquals(2,push().pushed)
        var context=store.investmentPurchaseSnapshot(owner)
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId},null,"Reserve"),device,now).getOrThrow()
        context=store.investmentPurchaseSnapshot(owner)
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id},null,"Reserve"),device,now).getOrThrow()
        assertEquals(2,push().pushed);assertTrue(source().pending.isEmpty())
        val deleted=rpcRequests().filter{it.requestUrl!!.encodedPath.endsWith("delete_investment_trade")}.map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject}
        assertEquals(listOf(saleId,id),deleted.map{it.financeRawString("p_trade_id")})
        assertEquals(listOf(2L,4L),deleted.map{it.financeRawLong("p_expected_version")})
    }

    @Test fun fourPublishedBuysDeletedLocallyOldestFirstCannotStrandTheLastTombstoneAfterThreeRebuilds()=runBlocking {
        val trades=listOf(id,"77777777-7777-7777-7777-777777777777","88888888-8888-8888-8888-888888888888","99999999-9999-9999-9999-999999999999")
        for((index,tradeId) in trades.withIndex()) {
            val context=store.investmentPurchaseSnapshot(owner)
            repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(tradeId,asset,"1","box",0,0,"VND",null,null,null,null,null,null,null,"2026-10-26T00:00:0${index}Z",now),
                InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),null,null,"Reserve"),device,now).getOrThrow()
            assertEquals(1,push().pushed)
        }
        for((index,tradeId) in trades.withIndex()) {
            val raw=store.investmentPurchaseSnapshot(owner).rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==tradeId}
            repo.deleteTrade(owner,InvestmentTradeDeletionRequest(raw,null,"Reserve"),device,"2026-10-26T00:15:0${index}Z").getOrThrow()
        }
        assertEquals(4,push().pushed);assertTrue(source().pending.isEmpty())
        val deletes=rpcRequests().filter{it.requestUrl!!.encodedPath.endsWith("delete_investment_trade")}.map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject}
        assertEquals(trades.reversed(),deletes.map{it.financeRawString("p_trade_id")})
        assertEquals(listOf(2L,4L,6L,8L),deletes.map{it.financeRawLong("p_expected_version")})
    }

    private suspend fun editQuantity(tradeId:String,quantity:String,date:String) {
        val context=store.investmentPurchaseSnapshot(owner);val raw=context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==tradeId}
        val p=raw.payload;val buying=p.financeRawString("kind_raw_value")=="buy"
        val request=InvestmentTradeEditRequest(raw,InvestmentTradeEditDraft(tradeId,asset,if(buying)InvestmentTradeKind.BUY else InvestmentTradeKind.SELL,quantity,"box",
            p.financeRawLong("gross_amount_minor")!!,p.financeRawLong("accounting_gross_amount_minor")!!,"VND",null,null,null,wallet,if(buying)p.financeRawLong("funding_wallet_amount_minor") else null,
            null,p.financeRawString("note"),p.financeRawString("occurred_at")!!,p.financeRawString("created_at")!!),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve")
        val first=repo.editTrade(owner,request,device,date)
        val confirmation=first.exceptionOrNull() as? InvestmentTradeEditConfirmationRequired
        if(confirmation!=null)repo.editTrade(owner,request.copy(consent=confirmation.review.consent),device,date).getOrThrow() else first.getOrThrow()
    }
    @Test fun reducingTheSaleBeforeTheBuyPublishesBothValidOfflineEditsWithoutSendingAnInvalidIntermediateHistory()=runBlocking {
        var context=store.investmentPurchaseSnapshot(owner)
        repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,asset,"10","box",100,100,"VND",null,null,null,wallet,100,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,now).getOrThrow()
        assertEquals(1,push().pushed);val saleId="77777777-7777-7777-7777-777777777777";context=store.investmentPurchaseSnapshot(owner)
        repo.saveSale(owner,InvestmentSaleRequest(InvestmentSaleDraft(saleId,asset,"10","box",200,200,"VND",null,null,null,wallet,null,null,"2026-10-26T00:01:00Z",now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,now).getOrThrow()
        assertEquals(1,push().pushed)
        editQuantity(saleId,"5","2026-10-26T00:15:00Z");editQuantity(id,"5","2026-10-26T00:15:01Z")
        val before=rpcRequests().size;validateEditsAgainstBackendHistory=true
        val result=push();assertEquals(result.toString(),2,result.pushed);assertTrue(source().pending.isEmpty())
        val edits=rpcRequests().drop(before).map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject.getValue("p_trade").jsonObject}
        assertEquals(listOf(saleId,id),edits.map{it.financeRawString("id")})
        assertEquals("5",source().requestedRecord!!.payload.financeRawString("quantity_decimal_string"))
        assertEquals(100L,source().rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==saleId}.payload.financeRawLong("realized_profit_loss_minor"))
    }

    @Test fun deletingAfterAnUnpublishedNoteEditRetiresTheExistingServerIntentWithoutPublishingTheDiscardedNote()=runBlocking {
        buy();assertEquals(1,push().pushed);editNote()
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-26T00:16:00Z").getOrThrow()
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty());assertNotNull(after.requestedRecord!!.deletedAt)
        assertNull(after.requestedRecord!!.payload.financeRawString("note"));assertEquals(2,rpcRequests().size)
        assertTrue(rpcRequests().last().requestUrl!!.encodedPath.endsWith("delete_investment_trade"))
    }
    @Test fun deletingAfterAnUnpublishedAmountEditRetiresActualServerFinancialAmounts()=runBlocking {
        buy();assertEquals(1,push().pushed);val context=store.investmentPurchaseSnapshot(owner)
        repo.editTrade(owner,InvestmentTradeEditRequest(context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id},
            InvestmentTradeEditDraft(id,asset,InvestmentTradeKind.BUY,"2.5","box",90,90,"VND",null,null,null,wallet,90,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==asset}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,"2026-10-26T00:15:00Z").getOrThrow()
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-26T00:16:00Z").getOrThrow()
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty())
        val funding=after.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table};assertNotNull(funding.deletedAt);assertEquals(70L,funding.payload.financeRawLong("amount_minor"))
        assertEquals(70L,after.requestedRecord!!.payload.financeRawLong("gross_amount_minor"));assertEquals(2,rpcRequests().size)
    }

    @Test fun deletingAfterAnUnpublishedReassignmentRetiresBothHistoriesWithoutUploadingTheDiscardedMove()=runBlocking {
        buy();assertEquals(1,push().pushed);val target="88888888-8888-8888-8888-888888888888"
        cleanMetadata(InvestmentAssetRecord(target,owner.value,channel,"Other cards","VND",null,"box",0,false,null,now,now,null,0,device).toCloudRecord())
        val context=store.investmentPurchaseSnapshot(owner);val old=context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==id}
        repo.editTrade(owner,InvestmentTradeEditRequest(old,InvestmentTradeEditDraft(id,target,InvestmentTradeKind.BUY,"2.5","box",70,70,"VND",null,null,null,wallet,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==target}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==wallet}),null,"Reserve"),device,"2026-10-26T00:15:00Z").getOrThrow()
        repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,"2026-10-26T00:16:00Z").getOrThrow()
        assertEquals(1,push().pushed);val after=source();assertTrue(after.pending.isEmpty());assertNotNull(after.requestedRecord!!.deletedAt)
        assertEquals(asset,after.requestedRecord!!.payload.financeRawString("asset_id"));assertEquals(asset,after.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.payload.financeRawString("asset_id"))
        assertEquals(2,rpcRequests().size);assertTrue(rpcRequests().last().requestUrl!!.encodedPath.endsWith("delete_investment_trade"))
    }


    @Test fun actualOfflineBuyPublishesFundingBeforeTheOrdinaryWalletsFinalArchive()=runBlocking {
        seedCloudMetadata();buy()
        OfflineFirstFinanceRepository(store).archiveWallet(owner,RecordId(wallet),device,"2026-10-26T00:06:00Z").getOrThrow()
        val walletPublisher=WalletPublicationPushCoordinator(WalletPushCoordinator(store,ordinaryRemote,true,
            investmentWalletSource=store::investmentWalletPublicationSnapshot,investmentRetirementSource=store::investmentTradePublicationSnapshot,
            investmentPrerequisites=WalletInvestmentPrerequisiteCoordinator(store,walletPrerequisiteRemote,true,{session}),nowEpochMillis={clock}),rootCoordinator)
        val investments=InvestmentPublicationPushCoordinator(channelCoordinator,assetCoordinator,coordinator)
        repeat(3){walletPublisher.pushPending(owner,session!!.accessToken);investments.pushPending(owner,session!!.accessToken);clock+=30001}
        assertTrue("Trade, financial result and final ordinary archive must finish",source().pending.isEmpty())
        assertEquals(true,backend[CloudEntity.LEDGER_WALLET.table to wallet]!!.payload.financeRawArchived())
        assertEquals(true,store.record(owner,CloudEntity.LEDGER_WALLET.table,wallet)!!.payload.financeRawArchived())
        assertEquals(70L,backend[CloudEntity.LEDGER_TRANSACTION.table to investmentLedgerIdentity(id,"funding")]!!.payload.financeRawLong("amount_minor"))
        assertEquals(-70L,backend[CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(id,"funding-posting")]!!.payload.financeRawLong("amount_minor"))
        val trade=requests.indexOfFirst{it.requestUrl!!.encodedPath.endsWith("mutate_investment_trade")}
        val archive=requests.indexOfLast{it.method=="PATCH" && it.requestUrl!!.queryParameter("id")=="eq.$wallet"}
        assertTrue(trade>=0 && archive>trade)
        assertEquals(1,requests.count{it.requestUrl!!.encodedPath.endsWith("mutate_investment_trade")})
    }

}
