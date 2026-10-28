package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.time.Instant
import java.util.Currency
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import vn.com.quyln.mistia.core.model.*

/** Closed ordinary lifecycle RPC; generic transaction or posting writes are never used. */
class SupabaseInvestmentOrdinaryClient(private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean):InvestmentOrdinaryRemote {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val base:HttpUrl,val caller:CoroutineContext)

    override suspend fun fetchEvent(owner:UserId,eventId:String,accessToken:String):InvestmentOrdinaryCloudSnapshot=safely {
        val c=capture(owner,eventId,accessToken,false)
        val adjustmentId=investmentLedgerIdentity(eventId,"cash-unreconciled-adjustment")
        val url=c.base.newBuilder().addPathSegments("rest/v1/ledger_transactions").addQueryParameter("user_id","eq.${owner.value}")
            .addQueryParameter("id","in.($eventId,$adjustmentId)").addQueryParameter("limit","3").build()
        val ledgers=read(c,url).map{decode(c,CloudEntity.LEDGER_TRANSACTION,it).also{row->common(c,row,CloudEntity.LEDGER_TRANSACTION);require(row.syncVersion>=0)}}
        require(ledgers.size<=2 && ledgers.map{it.id}.distinct().size==ledgers.size && ledgers.all{it.id in setOf(eventId,adjustmentId)})
        val transaction=ledgers.singleOrNull{it.id==eventId}?.also{require(!requiresInvestmentLedgerDomain(it.payload) && LedgerTransactionRecord.fromCloudRecord(it).supportsOrdinaryTransactionLifecycle())}
        val adjustment=ledgers.singleOrNull{it.id==adjustmentId}?.also{require(it.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")}
        val postings=mutableListOf<CloudRecord>();var cursor:String?=null
        while(true) {
            val pageUrl=c.base.newBuilder().addPathSegments("rest/v1/investment_wallet_postings").addQueryParameter("user_id","eq.${owner.value}")
                .addQueryParameter("event_id","eq.$eventId").addQueryParameter("order","id.asc").addQueryParameter("limit","100")
                .apply{cursor?.let{addQueryParameter("id","gt.$it")}}.build()
            val page=read(c,pageUrl);require(page.size<=100)
            if(page.isEmpty())break
            for(p in page) {
                val row=decode(c,CloudEntity.INVESTMENT_POSTING,p);posting(c,row);require(row.syncVersion>=0)
                require(cursor?.let{row.id>it}!=false && postings.size<4)
                cursor=row.id;postings+=row
            }
        }
        // Ordinary parents/adjustments are editable. Fence the multi-page read so
        // one observation cannot mix allocations from a later atomic mutation.
        val finalLedgers=read(c,url).map{decode(c,CloudEntity.LEDGER_TRANSACTION,it).also{row->common(c,row,CloudEntity.LEDGER_TRANSACTION);require(row.syncVersion>=0)}}
        require(finalLedgers.size<=2 && finalLedgers.map{it.id}.distinct().size==finalLedgers.size)
        if(finalLedgers.associateBy{it.id}!=ledgers.associateBy{it.id})throw IOException("Ordinary event changed during read")
        ensureCurrent(c);InvestmentOrdinaryCloudSnapshot(owner,eventId,transaction,adjustment,postings)
    }
    override suspend fun publish(source:InvestmentOrdinaryPublicationSnapshot,accessToken:String):InvestmentOrdinaryPublicationResult=safely {
        val c=capture(source.owner,source.eventId,accessToken,true)
        val group=investmentOrdinaryPublicationGroup(source);require(group.queues.isNotEmpty())
        for(row in group.rows) {
            common(c,row,requireNotNull(CloudEntity.fromTable(row.entity)))
            require(row.syncVersion in 0 until Long.MAX_VALUE)
            uuid(requireNotNull(row.payload.financeRawString("last_modified_by_device_id")))
            if(row.entity==CloudEntity.LEDGER_TRANSACTION.table) {
                uuid(requireNotNull(row.payload.financeRawString("created_by_user_id")))
                require(row.payload.financeRawString("last_modified_by_user_id")==c.session.userId.value)
            }
        }
        val body=buildJsonObject {
            put("p_transaction",group.primary.payload);put("p_adjustment",group.adjustment?.payload ?: JsonNull)
            put("p_postings",JsonArray(group.postings.map{it.payload}));put("p_expected_version",group.primary.syncVersion)
            put("p_expected_adjustment_version",group.adjustment?.syncVersion ?: 0L)
            put("p_expected_posting_versions",buildJsonObject{group.postings.forEach{put(it.id,it.syncVersion)}})
            put("p_expected_presence",buildJsonObject{investmentOrdinaryExpectedPresence(source).toSortedMap().forEach{(id,present)->put(id,present)}})
        }
        val url=c.base.newBuilder().addPathSegments("rest/v1/rpc/mutate_ordinary_investment_event").build()
        ambiguous(c) {
            val result=Json.parseToJsonElement(executeText(c,authorized(c,url).post(jsonBody(body)).build())).jsonObject
            require(result.keys==setOf("transaction","adjustment","postings"))
            val actual=InvestmentOrdinaryPublicationResult(source.owner,source.eventId,
                decode(c,CloudEntity.LEDGER_TRANSACTION,result.getValue("transaction").jsonObject),
                result["adjustment"]?.takeUnless{it==JsonNull}?.let{decode(c,CloudEntity.LEDGER_TRANSACTION,it.jsonObject)},
                result.getValue("postings").jsonArray.map{decode(c,CloudEntity.INVESTMENT_POSTING,it.jsonObject)})
            planInvestmentOrdinaryAcknowledgement(source,actual)
            ensureCurrent(c);actual
        }
    }
    private suspend fun read(c:Context,url:HttpUrl):List<JsonObject> {
        val rows=Json.parseToJsonElement(executeText(c,authorized(c,url).get().build())).jsonArray
        require(rows.size<=100);return rows.map{it.jsonObject}.also{ensureCurrent(c)}
    }
    private fun jsonBody(body:JsonObject):RequestBody {
        val text=body.toString();require(text.toByteArray(Charsets.UTF_8).size<=MAX_BODY);return text.toRequestBody(JSON_TYPE)
    }
    private suspend inline fun <T> ambiguous(c:Context,block:()->T):T=try{block()}
        catch(cancelled:CancellationException){throw cancelled}
        catch(error:Exception){ensureCurrent(c);when(error){
            is SupabaseHttpException->throw error
            is IOException->throw error
            else->throw IOException("Investment ordinary result unavailable")
        }}
    private suspend fun capture(owner:UserId,id:String,token:String,write:Boolean):Context {
        val caller=currentCoroutineContext();caller.ensureActive();uuid(owner.value);uuid(id)
        check(config.isConfigured){"Ordinary service unavailable"};if(write)check(writesEnabled()){"Ordinary writes disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Ordinary session changed")
        val url=config.projectUrl.toHttpUrl();require(url.scheme=="https" && url.username.isEmpty() && url.password.isEmpty() && url.query==null && url.fragment==null)
        return Context(owner,id,session,write,url,caller).also(::ensureCurrent)
    }
    private fun ensureCurrent(c:Context) {
        c.caller.ensureActive()
        if(currentSession()!=c.session || c.write && !writesEnabled())throw CancellationException("Ordinary authorization changed")
        c.caller.ensureActive()
    }
    private fun authorized(c:Context,url:HttpUrl):Request.Builder {
        ensureCurrent(c)
        return Request.Builder().url(url).header("Authorization","Bearer ${c.session.accessToken}").header("apikey",config.anonKey)
            .header("Content-Type","application/json").header("Prefer","return=representation")
    }
    private suspend fun executeText(c:Context,request:Request):String {
        ensureCurrent(c)
        val text=try{http.newCall(request).awaitText()}catch(error:Exception){ensureCurrent(c);throw error}
        ensureCurrent(c)
        if(text.isBlank())throw IOException("Ordinary response unavailable")
        return text
    }
    private fun uuid(value:String){require(financeRawUuid(value)==value)}
    private fun instant(value:String?):Instant {
        val i=Instant.parse(requireNotNull(value));return Instant.ofEpochSecond(i.epochSecond,Math.rint(i.nano.toDouble()/1000).toLong()*1000)
    }
    private fun code(value:String?):String {
        val raw=requireNotNull(value);require(raw.financeReportingCode()==raw && Currency.getInstance(raw).defaultFractionDigits>=0);return raw
    }
    private fun decode(c:Context,entity:CloudEntity,p:JsonObject):CloudRecord {
        val id=requireNotNull(p.financeRawString("id"));return CloudRecord(entity.table,id,c.owner.value,p,p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
    }
    private fun common(c:Context,row:CloudRecord,entity:CloudEntity) {
        uuid(row.id);require(row.entity==entity.table && row.ownerUserId==c.owner.value && row.payload.financeRawString("id")==row.id &&
            row.payload.financeRawString("user_id")==c.owner.value && row.financeRawIdentity(c.owner,entity,true) && row.syncVersion>=0 &&
            row.payload.financeRawLong("sync_version")==row.syncVersion && row.updatedAt==row.payload.financeRawString("updated_at") &&
            row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at"))
        require(row.payload.keys.none{it.startsWith("_mistia_android_")})
        for(key in listOf("created_at","updated_at","occurred_at"))instant(row.payload.financeRawString(key))
        row.deletedAt?.let(::instant)
        val actor=row.payload["last_modified_by_device_id"]
        if(actor!=null && actor!=JsonNull)uuid(requireNotNull(row.payload.financeRawString("last_modified_by_device_id")))
    }
    private fun posting(c:Context,row:CloudRecord) {
        common(c,row,CloudEntity.INVESTMENT_POSTING);val p=row.payload
        require(row.id in listOf("cash-consumption-booked","cash-consumption-unreconciled","cash-destination-booked","cash-destination-unreconciled").map{investmentLedgerIdentity(c.id,it)})
        require(p.financeRawString("event_id")==c.id && p.financeRawString("ledger_transaction_id")==c.id)
        uuid(requireNotNull(p.financeRawString("wallet_id")))
        for(key in listOf("asset_id","trade_id"))require(p[key]==null || p[key]==JsonNull)
        require(p.financeRawString("cash_origin_raw_value")=="derived" && p.financeRawString("role_raw_value") in setOf("cashConsumption","cashTransfer") && p.financeRawString("cash_bucket_raw_value") in setOf("booked","unreconciled"))
        require(p.financeRawLong("amount_minor")!=null && p.financeRawLong("accounting_amount_minor")!=null)
        code(p.financeRawString("currency_code"));code(p.financeRawString("accounting_currency_code"))
    }
    private suspend fun Call.awaitText():String=suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,e:IOException){if(!continuation.isCancelled)continuation.resumeWithException(e)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val text=response.use {
                        if(!it.isSuccessful) {
                            // Retain only a closed SQL condition; diagnostics and arbitrary server text never escape.
                            val serviceCode=if(it.code==400)runCatching {
                                val bytes=it.peekBody(65_537).bytes()
                                if(bytes.size>65_536)null else {
                                    val body=Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
                                    if(body.financeRawString("code")=="P0001")RETRY_MESSAGES[body.financeRawString("message")] else null
                                }
                            }.getOrNull() else null
                            throw SupabaseHttpException(it.code,"",serviceCode)
                        }
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Ordinary response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Ordinary response exceeds limit")
                                if(count>0)output.write(buffer,0,count)
                            };output.toString(Charsets.UTF_8.name())
                        }
                    }
                    if(!continuation.isCancelled)continuation.resumeWith(Result.success(text))
                }catch(error:IOException){if(!continuation.isCancelled)continuation.resumeWithException(error)}
            }
        })
    }
    private suspend inline fun <T> safely(block:()->T):T=try{block()}
        catch(cancelled:CancellationException){throw cancelled}
        catch(http:SupabaseHttpException){throw SupabaseHttpException(http.statusCode,"",http.serviceCode)}
        catch(network:IOException){throw IOException("Investment ordinary network request failed")}
        catch(state:IllegalStateException){throw IllegalStateException("Investment ordinary service unavailable")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment ordinary request or response")}
    companion object {
        private const val MAX_BODY=8_388_608
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
        private val RETRY_MESSAGES=setOf("ordinary_investment_version_conflict","ordinary_investment_capacity_conflict","ordinary_investment_invalid_wallet").associateWith{it}
    }
}
