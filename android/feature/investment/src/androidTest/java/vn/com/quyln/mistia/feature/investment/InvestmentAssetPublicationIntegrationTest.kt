package vn.com.quyln.mistia.feature.investment

import android.content.Context
import android.graphics.Bitmap
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Collections
import java.util.UUID
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

/** Real Room, durable files and authenticated HTTPS clients against a local contract fixture. */
@RunWith(AndroidJUnit4::class)
class InvestmentAssetPublicationIntegrationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channel="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-24T00:00:00Z"
    private var session:AuthSession?=AuthSession(owner,null,"local-contract-token","refresh",Long.MAX_VALUE)
    private var enabled=true
    private var clock=4000L
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var cache:FileInvestmentProductImageCache
    private lateinit var repo:InvestmentRepository
    private lateinit var directory:File
    private lateinit var server:MockWebServer
    private lateinit var coordinator:InvestmentAssetPushCoordinator
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private val objects=Collections.synchronizedMap(mutableMapOf<String,ByteArray>())
    private var backend:CloudRecord?=null
    private var collision=0
    private var collisionBytes:ByteArray?=null
    private var loseRpcReply=false
    private var onRpc:(suspend ()->Unit)?=null
    private var onUpload:(()->Unit)?=null
    private val objectPrefix="/storage/v1/object/investment-product-images/"
    @Before fun setup()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        directory=File(context.cacheDir,"asset-publication-integration-${UUID.randomUUID()}")
        cache=FileInvestmentProductImageCache(directory,{session?.userId})
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={session?.userId},productImages=cache)
        repo=OfflineFirstInvestmentRepository(store,productImages=cache)
        repo.saveChannel(owner,InvestmentChannelDraft(channel,"Shop"),"VND",device,now).getOrThrow()
        val q=store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE).single()
        val raw=store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,channel)!!
        assertTrue(store.acknowledgeInvestmentChannelMutation(q,raw.copy(syncVersion=1,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(1))))))
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);dispatcher=fixture();start()}
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager)
            .retryOnConnectionFailure(false).callTimeout(5,TimeUnit.SECONDS).build()
        val config=SupabaseConfig(server.url("/").toString(),"local-publishable-key")
        val assets=SupabaseInvestmentAssetClient(config,http,{session},{enabled})
        val images=SupabaseInvestmentProductImageClient(config,http,{session},{enabled})
        coordinator=InvestmentAssetPushCoordinator(store,assets,true,{session},{clock},cache,images)
    }
    @After fun close(){server.shutdown();db.close();directory.deleteRecursively()}
    private fun jsonResponse(payload:CloudRecord?)=MockResponse().setBody(JsonArray(listOfNotNull(payload?.payload)).toString())
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests.add(request)
            val path=request.requestUrl!!.encodedPath
            if(path=="/rest/v1/investment_assets")return jsonResponse(backend)
            if(path.startsWith(objectPrefix)) {
                val objectPath=path.removePrefix(objectPrefix)
                return when(request.method) {
                    "POST"->{
                        val data=request.body.clone().readByteArray()
                        onUpload?.invoke()
                        if(collision!=0) {
                            objects[objectPath]=collisionBytes ?: data
                            MockResponse().setResponseCode(collision).setBody("local collision fixture")
                        } else {objects[objectPath]=data;MockResponse().setResponseCode(201)}
                    }
                    "GET"->objects[objectPath]?.let{MockResponse().setBody(Buffer().write(it))} ?: MockResponse().setResponseCode(404)
                    "DELETE"->{objects.remove(objectPath);MockResponse().setResponseCode(404)}
                    else->MockResponse().setResponseCode(405)
                }
            }
            if(path=="/rest/v1/rpc/mutate_investment_asset") {
                val body=Json.parseToJsonElement(request.body.clone().readUtf8()).jsonObject
                val expected=body.getValue("p_expected_version").jsonPrimitive.long
                if(expected!=(backend?.syncVersion ?: 0L))return jsonResponse(null)
                val incoming=body.getValue("p_asset").jsonObject
                val version=(backend?.syncVersion ?: 0L)+1
                val p=JsonObject(incoming+mapOf("sync_version" to JsonPrimitive(version),"updated_at" to JsonPrimitive("2026-10-24T00:30:00Z")))
                backend=CloudRecord(CloudEntity.INVESTMENT_ASSET.table,id,owner.value,p,"2026-10-24T00:30:00Z",null,version)
                val callback=onRpc;onRpc=null
                if(callback!=null)runBlocking{callback()}
                if(loseRpcReply){loseRpcReply=false;return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)}
                return jsonResponse(backend)
            }
            return MockResponse().setResponseCode(404)
        }
    }
    private fun jpeg(color:Int):ByteArray {
        val bitmap=Bitmap.createBitmap(8,4,Bitmap.Config.ARGB_8888);bitmap.eraseColor(color)
        return try{ByteArrayOutputStream().use{bitmap.compress(Bitmap.CompressFormat.JPEG,90,it);it.toByteArray()}}finally{bitmap.recycle()}
    }
    private suspend fun photo(expected:InvestmentAssetRecord?=null,color:Int=android.graphics.Color.BLUE,writeDate:String?=null):InvestmentAssetRecord {
        val bytes=jpeg(color)
        val candidate=repo.stageProductImage(owner,id,PreparedInvestmentProductImage(bytes,bytes,"image/jpeg",8,4)).getOrThrow()
        return repo.saveAssetImage(owner,InvestmentAssetDraft(id,channel,"Cards","VND","box",expected,
            InvestmentAssetImageChange.Replace(InvestmentProductImagePath.parse(owner,id,candidate.path))),candidate,UUID.randomUUID().toString(),device,
            writeDate ?: if(expected==null)now else "2026-10-24T01:00:00Z").getOrThrow()
    }
    private suspend fun push()=coordinator.pushPending(owner,requireNotNull(session).accessToken)
    private fun order()=requests.map{it.method+" "+it.requestUrl!!.encodedPath.substringBefore(owner.value)}
    private fun assertAuthenticated() {
        for(request in requests) {
            assertEquals("Bearer local-contract-token",request.getHeader("Authorization"))
            assertEquals("local-publishable-key",request.getHeader("apikey"))
        }
    }
    private fun rpcBodies()=requests.filter{it.requestUrl!!.encodedPath.startsWith("/rest/v1/rpc/")}.map{Json.parseToJsonElement(it.body.clone().readUtf8()).jsonObject}
    @Test fun replacementPublishesActualBytesThenRpcAndAcknowledgesOnlyTheAssetQueue()=runBlocking {
        val asset=photo();val walletQueue=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)
        assertEquals(1,push().pushed)
        assertEquals(listOf("GET /rest/v1/investment_assets","POST $objectPrefix","POST /rest/v1/rpc/mutate_investment_asset"),order())
        assertArrayEquals(jpeg(android.graphics.Color.BLUE),objects[asset.imagePath])
        val body=rpcBodies().single();assertEquals(JsonPrimitive(0),body["p_expected_version"]);assertEquals(JsonPrimitive(false),body["p_force"])
        assertFalse(LOCAL_ASSET_IMAGE_INTENT_KEY in body.getValue("p_asset").jsonObject)
        val after=store.reconcileInvestmentAssetImagePublication(owner,id)
        assertEquals(backend,after.record);assertNull(after.pending);assertTrue(after.imageAcknowledged)
        assertEquals(walletQueue,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE));assertAuthenticated()
    }
    @Test fun duplicateUploadRequiresAnAuthenticatedExactByteReadBeforeMetadata()=runBlocking {
        collision=409;photo()
        assertEquals(1,push().pushed)
        assertEquals(listOf("GET /rest/v1/investment_assets","POST $objectPrefix","GET $objectPrefix","POST /rest/v1/rpc/mutate_investment_asset"),order())
        assertEquals(1,rpcBodies().size);assertAuthenticated()
    }
    @Test fun aDifferentObjectAtTheImmutablePathRetainsTheQueueAndNeverCallsRpc()=runBlocking {
        collision=400;collisionBytes=jpeg(android.graphics.Color.RED);photo()
        val before=store.reconcileInvestmentAssetImagePublication(owner,id)
        assertEquals(1,push().permanentFailures)
        assertTrue(rpcBodies().isEmpty());assertNull(backend)
        val after=store.reconcileInvestmentAssetImagePublication(owner,id)
        assertEquals(before.record,after.record);assertNotNull(after.pending);assertFalse(after.imageAcknowledged)
        assertEquals(1,cache.pendingUploads(owner).getOrThrow().size)
    }
    @Test fun lostRpcReplyRetriesBySemanticAckWithoutReplayingTheObjectOrMetadataWrite()=runBlocking {
        photo();loseRpcReply=true
        assertEquals(1,push().retryableFailures)
        assertNotNull(backend);assertNotNull(store.reconcileInvestmentAssetImagePublication(owner,id).pending)
        clock=100_000
        assertEquals(1,push().acknowledged)
        assertEquals(1,rpcBodies().size);assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.encodedPath.startsWith(objectPrefix)})
        assertNull(store.reconcileInvestmentAssetImagePublication(owner,id).pending)
    }
    @Test fun lateRpcAckKeepsALaterRenameAndItsAcknowledgedPhotoCannotReplayOverRemotePhoto()=runBlocking {
        val asset=photo()
        onRpc={repo.saveAsset(owner,InvestmentAssetDraft(id,channel,"Renamed","VND","box",asset),device,"2026-10-24T01:00:00Z").getOrThrow();Unit}
        assertEquals(1,push().staleResponses)
        val pending=store.reconcileInvestmentAssetImagePublication(owner,id)
        assertNotNull(pending.pending);assertTrue(pending.imageAcknowledged)
        val remotePhoto=InvestmentProductImagePath.create(owner,id,"88888888-8888-8888-8888-888888888888").value
        backend=backend!!.copy(payload=JsonObject(backend!!.payload+("image_path" to JsonPrimitive(remotePhoto))))
        assertEquals(1,push().pushed)
        val sent=rpcBodies().last().getValue("p_asset").jsonObject
        assertEquals("Renamed",sent.financeRawString("name"));assertEquals(remotePhoto,sent.financeRawString("image_path"))
        assertEquals(remotePhoto,InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,id)!!).imagePath)
        assertEquals(1,requests.count{it.method=="POST" && it.requestUrl!!.encodedPath.startsWith(objectPrefix)})
    }
    @Test fun lateRpcAckCannotClearANewerPhotoAndOldBytesDeleteOnlyAfterItsMatchingAck()=runBlocking {
        val first=photo();var next:InvestmentAssetRecord?=null
        onRpc={next=photo(first,android.graphics.Color.RED)}
        assertEquals(1,push().staleResponses)
        val pending=store.reconcileInvestmentAssetImagePublication(owner,id)
        assertEquals(next!!.imagePath,pending.imagePublication!!.path);assertFalse(pending.imageAcknowledged)
        assertTrue(cache.readyDeletions(owner).getOrThrow().isEmpty());assertNotNull(cache.cachedImageData(owner,id,first.imagePath!!).getOrThrow())
        assertEquals(1,push().pushed)
        assertNull(store.reconcileInvestmentAssetImagePublication(owner,id).pending)
        assertTrue(requests.last().method=="DELETE");assertTrue(requests.last().requestUrl!!.encodedPath.endsWith(first.imagePath!!))
        assertNull(cache.cachedImageData(owner,id,first.imagePath!!).getOrThrow())
        assertNotNull(cache.cachedImageData(owner,id,next!!.imagePath!!).getOrThrow())
    }
    @Test fun aSessionChangeDuringActualUploadCannotReachTheRpcOrAcknowledgeTheOldQueue()=runBlocking {
        photo();val before=store.reconcileInvestmentAssetImagePublication(owner,id)
        onUpload={session=null}
        assertTrue(runCatching{push()}.exceptionOrNull() is CancellationException)
        assertTrue(rpcBodies().isEmpty());assertNull(backend)
        session=AuthSession(owner,null,"local-contract-token","refresh",Long.MAX_VALUE)
        val after=store.reconcileInvestmentAssetImagePublication(owner,id)
        assertEquals(before.record,after.record);assertEquals(before.pending,after.pending);assertFalse(after.imageAcknowledged)
    }
    @Test fun aConfirmedWriteAgainstAHigherRemoteBaseProtectsTheConcurrentRename()=runBlocking {
        val asset=photo()
        backend=asset.copy(name="Before",syncVersion=7,updatedAt="2026-10-23T00:00:00Z",lastModifiedByDeviceId="99999999-9999-9999-9999-999999999999").toCloudRecord()
        onRpc={repo.saveAsset(owner,InvestmentAssetDraft(id,channel,"Renamed","VND","box",asset),device,"2026-10-24T00:15:00Z").getOrThrow();Unit}
        assertEquals(1,push().staleResponses)
        assertEquals(8L,backend!!.syncVersion)
        assertEquals(1,push().pushed)
        assertEquals("Renamed",store.reconcileInvestmentAssetImagePublication(owner,id).record!!.payload.financeRawString("name"))
        assertEquals(9L,backend!!.syncVersion)
    }
    @Test fun aServerClockLaterThanTheConcurrentRenameCannotEraseItOnTheNextCycle()=runBlocking {
        val asset=photo()
        onRpc={repo.saveAsset(owner,InvestmentAssetDraft(id,channel,"Renamed","VND","box",asset),device,"2026-10-24T00:15:00Z").getOrThrow();Unit}
        assertEquals(1,push().staleResponses)
        assertEquals("Renamed",InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,id)!!).name)
        assertEquals(1,push().pushed)
        assertEquals("Renamed",InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,id)!!).name)
        assertNull(store.reconcileInvestmentAssetImagePublication(owner,id).pending)
    }
    @Test fun aLostReplyAndLaterServerClockCannotEraseAConcurrentRenameOnRetry()=runBlocking {
        val asset=photo();loseRpcReply=true
        onRpc={repo.saveAsset(owner,InvestmentAssetDraft(id,channel,"Renamed","VND","box",asset),device,"2026-10-24T00:15:00Z").getOrThrow();Unit}
        assertEquals(1,push().staleResponses)
        clock=100_000
        assertEquals(1,push().pushed)
        assertEquals("Renamed",InvestmentAssetRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_ASSET.table,id)!!).name)
        assertEquals(2,rpcBodies().size)
    }
    @Test fun aServerClockLaterThanTheNewPhotoCannotRollItsPointerBack()=runBlocking {
        val first=photo();var next:InvestmentAssetRecord?=null
        onRpc={next=photo(first,android.graphics.Color.RED,"2026-10-24T00:15:00Z")}
        assertEquals(1,push().staleResponses)
        assertEquals(next!!.imagePath,store.reconcileInvestmentAssetImagePublication(owner,id).record!!.payload.financeRawString("image_path"))
        assertEquals(1,push().pushed)
        assertEquals(next!!.imagePath,store.reconcileInvestmentAssetImagePublication(owner,id).record!!.payload.financeRawString("image_path"))
        assertNotNull(cache.cachedImageData(owner,id,next!!.imagePath!!).getOrThrow())
    }

}
