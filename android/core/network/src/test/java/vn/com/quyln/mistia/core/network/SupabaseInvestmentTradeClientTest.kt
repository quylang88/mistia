package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.mockwebserver.*
import okhttp3.mockwebserver.Dispatcher
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

class SupabaseInvestmentTradeClientTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val asset="44444444-4444-4444-4444-444444444444"
    private val otherAsset="55555555-5555-5555-5555-555555555555"
    private val channel="66666666-6666-6666-6666-666666666666"
    private val wallet="77777777-7777-7777-7777-777777777777"
    private val second="88888888-8888-8888-8888-888888888888"
    private val token="trade-contract-token"
    private val now="2026-10-26T00:00:00Z"
    private val version=9007199254740993L
    private val session=AtomicReference<AuthSession?>(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE))
    private val enabled=AtomicBoolean(true)
    private lateinit var server:MockWebServer
    private lateinit var http:OkHttpClient
    private lateinit var client:SupabaseInvestmentTradeClient
    private val calls=java.util.Collections.synchronizedList(mutableListOf<Call>())
    @Before fun setup() {
        val certificate=HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server=MockWebServer().apply{useHttps(serverTls.sslSocketFactory(),false);start()}
        http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).retryOnConnectionFailure(false)
            .callTimeout(3,TimeUnit.SECONDS).eventListener(object:EventListener(){override fun callStart(call:Call){calls.add(call)}}).build()
        client=SupabaseInvestmentTradeClient(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http,{session.get()},{enabled.get()})
    }
    @After fun close(){server.shutdown()}
    private fun row(v:Long=1,identity:String=id,assetId:String=asset)=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,identity,owner.value,buildJsonObject {
        put("id",identity);put("user_id",owner.value);put("channel_id",channel);put("asset_id",assetId);put("kind_raw_value","buy")
        put("quantity_decimal_string","1.25");put("unit_label","box");put("gross_amount_minor",100);put("currency_code","VND");put("accounting_gross_amount_minor",100);put("accounting_currency_code","VND")
        put("funding_wallet_id",wallet);put("capital_return_wallet_id",JsonNull)
        for(key in listOf("exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string","note"))put(key,JsonNull)
        put("created_at",now);put("updated_at",now);put("occurred_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun response(vararg rows:CloudRecord)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private suspend fun mutate(proposal:CloudRecord=row(),base:Long=0,assets:Set<String> = setOf(asset))=client.mutateTrade(owner,proposal,base,assets,token)
    private fun rpc(name:String):JsonObject {
        val r=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals("POST",r.method);assertEquals("/rest/v1/rpc/"+name,r.requestUrl!!.encodedPath);assertNull(r.requestUrl!!.query)
        assertEquals("Bearer "+token,r.getHeader("Authorization"));assertEquals("local-publishable-key",r.getHeader("apikey"))
        return Json.parseToJsonElement(r.body.readUtf8()).jsonObject
    }
    @Test fun ownedLookupPinsIdentityOwnerAndExactLongAndPreservesOpaqueNulls()=runTest {
        val raw=row(version);server.enqueue(response(raw));val result=client.fetchTrade(owner,id,token);assertNotNull(result)
        assertEquals(raw,result);val r=server.takeRequest(1,TimeUnit.SECONDS)!!
        assertEquals("GET",r.method);assertEquals("/rest/v1/investment_trades",r.requestUrl!!.encodedPath)
        assertEquals("eq."+id,r.requestUrl!!.queryParameter("id"));assertEquals("eq."+owner.value,r.requestUrl!!.queryParameter("user_id"));assertEquals("2",r.requestUrl!!.queryParameter("limit"))
    }
    @Test fun createUsesExpectedZeroForceFalseAndReturnsTheActualRebuiltVersionTwo()=runTest {
        val saved=row(2);server.enqueue(response(saved));val result=mutate();assertNotNull(result)
        assertEquals(saved,result!!.requested);assertEquals(listOf(saved),result!!.trades)
        val body=rpc("mutate_investment_trade");assertEquals(setOf("p_trade","p_expected_version","p_force"),body.keys)
        assertEquals(JsonPrimitive(0),body["p_expected_version"]);assertEquals(JsonPrimitive(false),body["p_force"])
        assertEquals(row().payload,body["p_trade"])
    }
    @Test fun casPreservesLongBaseAndTheAdditionalRebuildVersionIncrement()=runTest {
        val proposal=row(version+1);server.enqueue(response(row(version+2)))
        assertEquals(version+2,mutate(proposal,version)!!.requested.syncVersion)
        val body=rpc("mutate_investment_trade");assertEquals(JsonPrimitive(version),body["p_expected_version"])
        assertEquals(JsonPrimitive(version+1),body["p_trade"]!!.jsonObject["sync_version"])
    }
    @Test fun returnedOtherTradesFromBothAffectedAssetsAreKeptForCoherentReconciliation()=runTest {
        val proposal=row(8,assetId=otherAsset);val saved=row(9,assetId=otherAsset);val other=row(12,identity=second)
        server.enqueue(response(other,saved));val result=mutate(proposal,7,setOf(asset,otherAsset))!!
        assertEquals(saved,result!!.requested);assertEquals(listOf(other,saved),result.trades)
    }
    @Test fun emptyMutationAndDeleteRepliesRemainCasMissesRatherThanInventedAcks()=runTest {
        server.enqueue(response());assertNull(mutate())
        server.enqueue(response());assertNull(client.deleteTrade(owner,id,3,now,device,token))
        server.enqueue(response());assertNull(client.fetchTrade(owner,id,token))
        assertEquals(3,server.requestCount)
    }
    @Test fun serverDerivedFifoAndFinancialAuthorityIsOmittedFromTheSubmittedTrade()=runTest {
        val raw=row().let{it.copy(payload=JsonObject(it.payload+buildJsonObject{
            put("released_cost_basis_minor",999);put("realized_profit_loss_minor",999);put("position_cost_basis_after_minor",999);put("position_quantity_after_decimal_string","999")
            put("funding_wallet_amount_minor",999);put("funding_wallet_currency_code","JPY");put("funding_ledger_transaction_id",second)
        }))};server.enqueue(response(row(2)));assertNotNull(mutate(raw))
        val sent=rpc("mutate_investment_trade")["p_trade"]!!.jsonObject
        for(key in listOf("released_cost_basis_minor","realized_profit_loss_minor","position_cost_basis_after_minor","position_quantity_after_decimal_string","funding_wallet_amount_minor","funding_wallet_currency_code","funding_ledger_transaction_id"))assertFalse(key,key in sent)
        assertEquals(JsonPrimitive(Long.MAX_VALUE),sent["future_large"]);assertSame(JsonNull,sent["future_null"])
    }
    @Test fun duplicateForeignUnrelatedOrMissingRequestedRowsCannotAuthorizeAnyAck()=runTest {
        val foreign=row(2).let{it.copy(ownerUserId=asset,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(asset))))}
        for(rows in listOf(listOf(row(2),row(2)),listOf(foreign),listOf(row(2,assetId=otherAsset)),listOf(row(2,identity=second)),listOf(row(2),row(3,identity=second,assetId=otherAsset)))) {
            server.enqueue(response(*rows.toTypedArray()));assertTrue(runCatching{mutate()}.isFailure)
        }
    }
    @Test fun aWriteReplyCannotChangeTheRequestedBusinessIntentOrActor()=runTest {
        for(fields in listOf(buildJsonObject{put("gross_amount_minor",101);put("accounting_gross_amount_minor",101)},buildJsonObject{put("unit_label","card")},
            buildJsonObject{put("last_modified_by_device_id",second)},buildJsonObject{put("created_at","2026-10-25T00:00:00Z")},buildJsonObject{put("channel_id",second)})) {
            val saved=row(2).let{it.copy(payload=JsonObject(it.payload+fields))};server.enqueue(response(saved));assertTrue(runCatching{mutate()}.isFailure)
        }
    }
    @Test fun legacyCreateAndServerTrimmedPresentationHaveDeliberateVersionAndTextRules()=runTest {
        val proposal=row(99).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("unit_label"," box ");put("note"," note ")}))}
        val saved=row(2).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("note"))))}
        server.enqueue(response(saved));assertEquals(saved,mutate(proposal)!!.requested)
    }
    @Test fun postgresMicrosecondRoundingIsMetadataPrecisionRatherThanChangedUserIntent()=runTest {
        val proposal=row().let{it.copy(payload=JsonObject(it.payload+buildJsonObject{
            put("created_at","2026-10-26T00:00:00.123456789Z");put("occurred_at","2026-10-26T00:00:00.999999600Z")
        }))}
        val saved=row(2).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{
            put("created_at","2026-10-26T00:00:00.123457Z");put("occurred_at","2026-10-26T00:00:01Z")
        }))}
        server.enqueue(response(saved));assertEquals(saved,mutate(proposal)!!.requested)
    }
    @Test fun postgresHalfMicrosecondTiesDoNotChangeTheOriginalTimestampIntent()=runTest {
        for((input,output) in listOf("123456500" to "123456","123457500" to "123458")) {
            val proposal=row().let{it.copy(payload=JsonObject(it.payload+("created_at" to JsonPrimitive("2026-10-26T00:00:00.${input}Z"))))}
            val saved=row(2).let{it.copy(payload=JsonObject(it.payload+("created_at" to JsonPrimitive("2026-10-26T00:00:00.${output}Z"))))}
            server.enqueue(response(saved));assertEquals(saved,mutate(proposal)!!.requested)
        }
    }
    @Test fun writeReplyVersionMustMatchTheEffectiveRpcRatherThanTheSubmittedVersion()=runTest {
        for(v in listOf(1L,3L,Long.MAX_VALUE)) {server.enqueue(response(row(v)));assertTrue(runCatching{mutate()}.isFailure)}
        server.enqueue(response(row(version+1)));assertTrue(runCatching{mutate(row(version+1),version)}.isFailure)
    }
    @Test fun deleteUsesTheClosedRpcAndRequiresItsOwnedExactVersionTombstone()=runTest {
        val dead=row(version+1).let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        server.enqueue(response(dead));assertEquals(dead,client.deleteTrade(owner,id,version,now,device,token))
        val body=rpc("delete_investment_trade");assertEquals(setOf("p_trade_id","p_owner_user_id","p_expected_version","p_modified_at","p_device_id"),body.keys)
        assertEquals(JsonPrimitive(version),body["p_expected_version"]);assertEquals(JsonPrimitive(owner.value),body["p_owner_user_id"])
        assertEquals(JsonPrimitive(id),body["p_trade_id"]);assertEquals(JsonPrimitive(device),body["p_device_id"]);assertEquals(JsonPrimitive(now),body["p_modified_at"])
        for(raw in listOf(row(version+1),dead.copy(syncVersion=version+2,payload=JsonObject(dead.payload+("sync_version" to JsonPrimitive(version+2)))))) {
            server.enqueue(response(raw));assertTrue(runCatching{client.deleteTrade(owner,id,version,now,device,token)}.isFailure)
        }
    }
    @Test fun gateOwnerScopeWrongBaseAndForeignEvidenceAreRejectedBeforeHttp()=runTest {
        enabled.set(false);assertTrue(runCatching{mutate()}.isFailure)
        enabled.set(true)
        assertTrue(runCatching{mutate(base=-1)}.isFailure);assertTrue(runCatching{mutate(row(1),1)}.isFailure)
        assertTrue(runCatching{mutate(assets=emptySet())}.isFailure);assertTrue(runCatching{mutate(assets=setOf(otherAsset))}.isFailure)
        assertTrue(runCatching{client.fetchTrade(owner,"bad",token)}.isFailure)
        assertTrue(runCatching{client.fetchTrade(UserId(asset),id,token)}.exceptionOrNull() is CancellationException)
        for(key in LOCAL_ASSET_PUBLICATION_KEYS+LOCAL_INVESTMENT_WALLET_PARENTS_KEY)assertTrue(runCatching{mutate(row().let{it.copy(payload=JsonObject(it.payload+(key to JsonNull)))})}.isFailure)
        assertEquals(0,server.requestCount)
    }
    @Test fun disabledWriteGateStillAllowsTheOwnedReadPort()=runTest {
        enabled.set(false);server.enqueue(response(row(2)));assertEquals(row(2),client.fetchTrade(owner,id,token))
    }
    @Test fun sameOwnerTokenReplacementAndGateRevocationDuringReplyCancelTheOldCall()=runTest {
        for(revokeGate in listOf(false,true)) {
            session.set(AuthSession(owner,null,token,"refresh",Long.MAX_VALUE));enabled.set(true)
            server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
                if(revokeGate)enabled.set(false) else session.set(session.get()!!.copy(accessToken="replacement"))
                return response(row(2))
            }}
            assertTrue(runCatching{mutate()}.exceptionOrNull() is CancellationException)
        }
    }
    @Test fun cancellationCancelsTheActualHttpCallRatherThanCreatingAFailureReply()=runTest {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val task=async(Dispatchers.Default){mutate()};assertNotNull(server.takeRequest(1,TimeUnit.SECONDS))
        task.cancelAndJoin();assertTrue(calls.single().isCanceled())
    }
    @Test fun anEmptySuccessfulBodyIsRetryableWithoutBeingMistakenForAnEmptyCasArray()=runTest {
        server.enqueue(MockResponse().setBody(""))
        assertTrue(runCatching{mutate()}.exceptionOrNull() is java.io.IOException)
    }
    @Test fun redirectMalformedAndOversizedRepliesDoNotLeakCredentialsOrFollowAnotherHost()=runTest {
        server.enqueue(MockResponse().setResponseCode(302).addHeader("Location","https://example.invalid/"));val redirected=runCatching{mutate()}.exceptionOrNull()
        assertTrue(redirected is SupabaseHttpException);assertEquals(302,(redirected as SupabaseHttpException).statusCode);assertEquals("",redirected.responseBody);assertEquals(1,calls.size)
        for(body in listOf("[{\\\"broken\\\":true}]",JsonArray(List(10001){JsonObject(emptyMap())}).toString()," ".repeat(8_388_609))) {
            server.enqueue(MockResponse().setBody(body));val error=runCatching{mutate()}.exceptionOrNull();assertNotNull(error);assertFalse(error.toString().contains(token));assertFalse(error.toString().contains("refresh"))
        }
    }
    private suspend fun result(assets:Set<String> = setOf(asset),known:Set<String> = setOf(id))=
        client.fetchTradeResult(owner,assets,known,token)
    private fun financial(entity:CloudEntity,trade:String=id,component:String="funding")=
        row(version,investmentLedgerIdentity(trade,component)).let{it.copy(entity=entity.table)}
    private fun serveResult(rows:List<CloudRecord>,onRequest:(RecordedRequest)->Unit={}) {
        server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
            onRequest(request)
            val url=request.requestUrl!!;val table=url.pathSegments.last()
            val ids=url.queryParameterValues("id").filterNotNull()
            val included=ids.firstOrNull{it.startsWith("in.(")}?.removePrefix("in.(")?.removeSuffix(")")?.split(',')?.toSet()
            val cursor=ids.firstOrNull{it.startsWith("gt.")}?.removePrefix("gt.")
            // Deliberately cap the server at one row, below the requested page size.
            return response(*rows.filter{it.entity==table && (included==null || it.id in included) && (cursor==null || it.id>cursor)}.sortedBy{it.id}.take(1).toTypedArray())
        }}
    }
    @Test fun resultReaderKeepsShortPagesTombstonesAndAllDeterministicFinancialComponentsWithTheGateOff()=runTest {
        val dead=row(3,second).let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        val financialRows=listOf("funding","capital-return","profit-loss").map{financial(CloudEntity.LEDGER_TRANSACTION,component=it)}+
            listOf("funding-posting","capital-return-posting","profit-loss-posting","cash-accrual-posting").map{financial(CloudEntity.INVESTMENT_POSTING,component=it)}
        val rows=listOf(row(2),dead)+financialRows;enabled.set(false)
        serveResult(rows){r->
            assertEquals("GET",r.method);assertEquals("Bearer "+token,r.getHeader("Authorization"))
            assertEquals("eq."+owner.value,r.requestUrl!!.queryParameter("user_id"))
            assertEquals("id.asc",r.requestUrl!!.queryParameter("order"));assertEquals("100",r.requestUrl!!.queryParameter("limit"))
            assertNull(r.requestUrl!!.queryParameter("deleted_at"))
        }
        val actual=result();assertEquals(owner,actual.owner);assertEquals(setOf(asset),actual.affectedAssetIds)
        assertEquals(rows.toSet(),actual.rows.toSet());assertEquals(rows.size+3,server.requestCount)
        val first=server.takeRequest()!!;assertEquals("in.("+asset+")",first.requestUrl!!.queryParameter("asset_id"))
    }
    @Test fun missingKnownTradesStillCauseEveryCanonicalFinancialIdentityToBeRead()=runTest {
        val orphan=financial(CloudEntity.LEDGER_TRANSACTION,component="profit-loss")
        serveResult(listOf(orphan));assertEquals(listOf(orphan),result().rows)
        val requests=List(server.requestCount){server.takeRequest()!!}
        val queried=requests.filter{it.requestUrl!!.pathSegments.last()==CloudEntity.LEDGER_TRANSACTION.table}
            .flatMap{it.requestUrl!!.queryParameterValues("id").filterNotNull()}.filter{it.startsWith("in.(")}.joinToString()
        for(component in listOf("funding","capital-return","profit-loss"))assertTrue(queried.contains(investmentLedgerIdentity(id,component)))
    }
    @Test fun resultReaderChunksAllKnownFinancialKeysWithoutAnUnboundedUrlOrDefaultRowCap()=runTest {
        val known=(1..35).map{"00000000-0000-0000-0000-"+it.toString().padStart(12,'0')}.toSet()
        val rows=known.map{financial(CloudEntity.LEDGER_TRANSACTION,it)}+known.map{financial(CloudEntity.INVESTMENT_POSTING,it,"funding-posting")}
        serveResult(rows){r->
            val included=r.requestUrl!!.queryParameterValues("id").filterNotNull().firstOrNull{it.startsWith("in.(")}
            if(included!=null)assertTrue(included.removePrefix("in.(").removeSuffix(")").split(',').size<=100)
        }
        assertEquals(rows.toSet(),result(known=known).rows.toSet());assertEquals(rows.size+5,server.requestCount)
    }
    @Test fun resultReaderRejectsAnUnexpectedAssetOrForeignTradeInsteadOfReturningACandidate()=runTest {
        for(raw in listOf(row(2,assetId=otherAsset),row(2).let{it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(otherAsset))))})) {
            server.enqueue(response(raw));assertTrue(runCatching{result()}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun resultReaderRejectsDuplicateOrUnorderedPagesAndCannotLoopOnAStaleCursor()=runTest {
        for(rows in listOf(listOf(row(2),row(2)),listOf(row(2,second),row(2)))) {
            server.enqueue(response(*rows.toTypedArray()));assertTrue(runCatching{result()}.exceptionOrNull() is IllegalArgumentException)
        }
        server.enqueue(response(row(2)));server.enqueue(response(row(2)))
        assertTrue(runCatching{result()}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun resultReaderRejectsFinancialRowsOutsideTheRequestedCanonicalKeys()=runTest {
        server.enqueue(response());server.enqueue(response(financial(CloudEntity.LEDGER_TRANSACTION,second)))
        assertTrue(runCatching{result()}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun resultReaderValidatesFinancialIdentityLongDateAndDeletedShapesBeforeReturningRows()=runTest {
        val raw=financial(CloudEntity.LEDGER_TRANSACTION)
        for(fields in listOf(buildJsonObject{put("user_id",otherAsset)},buildJsonObject{put("sync_version","3")},
            buildJsonObject{put("updated_at","bad-date")},buildJsonObject{put("deleted_at",false)})) {
            server.enqueue(response());server.enqueue(response(raw.copy(payload=JsonObject(raw.payload+fields))))
            assertTrue(runCatching{result()}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun resultReaderCancelsOnSameOwnerSessionReplacementBetweenPages()=runTest {
        serveResult(listOf(row(2))){if(server.requestCount==2)session.set(session.get()!!.copy(accessToken="replacement"))}
        assertTrue(runCatching{result()}.exceptionOrNull() is CancellationException);assertEquals(2,server.requestCount)
    }
    @Test fun resultReaderCancelsItsActualInFlightHttpRead()=runTest {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val task=async(Dispatchers.Default){result()};assertNotNull(server.takeRequest(1,TimeUnit.SECONDS))
        task.cancelAndJoin();assertTrue(calls.single().isCanceled())
    }
    @Test fun resultReaderRejectsInvalidOrExcessiveScopeBeforeAnyHttp()=runTest {
        for(assets in listOf(emptySet(),setOf("bad"),setOf(asset,otherAsset,channel)))
            assertTrue(runCatching{result(assets=assets)}.exceptionOrNull() is IllegalArgumentException)
        assertTrue(runCatching{result(known=setOf("bad"))}.exceptionOrNull() is IllegalArgumentException)
        assertEquals(0,server.requestCount)
    }

    @Test fun genericPullCannotImportServerSuppliedPrivateTradeCausalEvidence()=runTest {
        val raw=row(2).let{it.copy(payload=JsonObject(it.payload+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to JsonNull)))}
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http)
        server.enqueue(response(raw));assertTrue(runCatching{generic.pullPage(CloudEntity.INVESTMENT_TRADE.table,token,owner,0,100)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun genericOwnedFetchCannotImportServerSuppliedPrivateTradeCausalEvidence()=runTest {
        val raw=row(2).let{it.copy(payload=JsonObject(it.payload+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to JsonNull)))}
        val generic=SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString(),"local-publishable-key"),http)
        server.enqueue(response(raw));assertTrue(runCatching{generic.fetchRecord(CloudEntity.INVESTMENT_TRADE,id,token,owner)}.exceptionOrNull() is IllegalArgumentException)
    }

}
