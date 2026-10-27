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
    private lateinit var server:MockWebServer
    private lateinit var coordinator:InvestmentTradePushCoordinator
    private val requests=Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private val backend=Collections.synchronizedMap(linkedMapOf<Pair<String,String>,CloudRecord>())
    private var onRpc:(suspend ()->Unit)?=null
    private var loseReply=false
    private var corruptFinancial=false
    private var validateEditsAgainstBackendHistory=false
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={session?.userId});repo=OfflineFirstInvestmentRepository(store)
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
        coordinator=InvestmentTradePushCoordinator(store,remote,true,{session},{clock})
    }
    @After fun close(){server.shutdown();db.close()}
    private fun response(rows:List<CloudRecord>)=MockResponse().setBody(JsonArray(rows.map{it.payload}).toString())
    private fun fixture()=object:Dispatcher() {
        override fun dispatch(request:RecordedRequest):MockResponse {
            requests.add(request)
            assertEquals("Bearer local-contract-token",request.getHeader("Authorization"));assertEquals("local-publishable-key",request.getHeader("apikey"))
            val url=request.requestUrl!!;val path=url.encodedPath
            if(request.method=="GET") {
                assertEquals("eq."+owner.value,url.queryParameter("user_id"))
                val table=url.pathSegments.last();val filters=url.queryParameterValues("id").filterNotNull()
                val exact=filters.firstOrNull{it.startsWith("eq.")}?.removePrefix("eq.")
                val ids=filters.firstOrNull{it.startsWith("in.(")}?.removePrefix("in.(")?.removeSuffix(")")?.split(',')?.toSet()
                val cursor=filters.firstOrNull{it.startsWith("gt.")}?.removePrefix("gt.")
                val assets=url.queryParameter("asset_id")?.removePrefix("in.(")?.removeSuffix(")")?.split(',')?.toSet()
                val rows=synchronized(backend){backend.values.toList()}.filter{it.entity==table && (exact==null || it.id==exact) &&
                    (ids==null || it.id in ids) && (cursor==null || it.id>cursor) && (assets==null || it.payload.financeRawString("asset_id") in assets)}.sortedBy{it.id}.take(1)
                return response(rows.map{if(corruptFinancial && it.entity==CloudEntity.LEDGER_TRANSACTION.table)it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonPrimitive(71)))) else it})
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
            val existing=backend[CloudEntity.INVESTMENT_TRADE.table to requested]
            if((existing?.syncVersion ?: 0L)!=base)return response(emptyList())
            val source=runBlocking{store.investmentTradePublicationSnapshot(owner,requested)}
            val projected=if(validateEditsAgainstBackendHistory && incoming!=null && existing!=null)try {
                serverEditRows(source,incoming,existing)
            }catch(rejected:InvestmentAccountingException) {
                return MockResponse().setResponseCode(400).setBody("local SQL FIFO dependency fixture")
            } else source.rows
            val tradeIds=synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}.map{it.id}.toSet()}+requested
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
            return response(synchronized(backend){backend.values.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table && if(delete)it.id==requested else it.deletedAt==null}})
        }
    }
    private fun serverEditRows(local:InvestmentTradePublicationSnapshot,incoming:JsonObject,existing:CloudRecord):List<CloudRecord> {
        val metadata=local.rows.filter{it.entity !in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}
        val rows=metadata+synchronized(backend){backend.values.toList()}
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

}
