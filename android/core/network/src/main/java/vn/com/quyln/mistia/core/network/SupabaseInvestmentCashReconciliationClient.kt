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

/** Closed immutable reconciliation ledger preparation and compared atomic posting publication. */
class SupabaseInvestmentCashReconciliationClient(private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean):InvestmentCashReconciliationRemote {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val base:HttpUrl,val caller:CoroutineContext)

    override suspend fun fetchEvent(owner:UserId,eventId:String,accessToken:String):InvestmentCashReconciliationCloudSnapshot=safely {
        val c=capture(owner,eventId,accessToken,false)
        val ledgerId=investmentLedgerIdentity(eventId,"cash-reconciliation")
        val url=c.base.newBuilder().addPathSegments("rest/v1/ledger_transactions").addQueryParameter("user_id","eq.${owner.value}")
            .addQueryParameter("id","eq.$ledgerId").addQueryParameter("limit","2").build()
        val rows=execute(c,authorized(c,url).get().build());require(rows.size<=1)
        val ledger=rows.singleOrNull()?.let{decode(c,CloudEntity.LEDGER_TRANSACTION,it).also{row->requireInvestmentCashReconciliationLedger(owner,eventId,row,true)}}
        val postings=mutableListOf<CloudRecord>();var cursor:String?=null;var chars=0L
        while(true) {
            val pageUrl=c.base.newBuilder().addPathSegments("rest/v1/investment_wallet_postings").addQueryParameter("user_id","eq.${owner.value}")
                .addQueryParameter("event_id","eq.$eventId").addQueryParameter("order","id.asc").addQueryParameter("limit","100")
                .apply{cursor?.let{addQueryParameter("id","gt.$it")}}.build()
            val page=execute(c,authorized(c,pageUrl).get().build());require(page.size<=100)
            if(page.isEmpty())break
            for(p in page) {
                val row=decode(c,CloudEntity.INVESTMENT_POSTING,p);posting(c,row);require(row.syncVersion>0)
                require(cursor?.let{row.id>it}!=false)
                chars+=p.toString().length;require(postings.size<10000 && chars<=67_108_864)
                cursor=row.id;postings+=row
            }
        }
        ensureCurrent(c);InvestmentCashReconciliationCloudSnapshot(owner,eventId,ledger,postings)
    }
    override suspend fun createLedger(owner:UserId,eventId:String,ledger:CloudRecord,accessToken:String):CloudRecord?=safely {
        val c=capture(owner,eventId,accessToken,true)
        requireInvestmentCashReconciliationLedger(owner,eventId,ledger,false);require(ledger.syncVersion==1L)
        require(ledger.payload["deleted_at"]==JsonNull && ledger.payload.financeRawString("last_modified_by_device_id")!=null)
        val url=c.base.newBuilder().addPathSegments("rest/v1/ledger_transactions").build()
        ambiguous {
            val rows=execute(c,authorized(c,url).post(jsonBody(ledger.payload)).build());require(rows.size<=1)
            rows.singleOrNull()?.let{decode(c,CloudEntity.LEDGER_TRANSACTION,it).also{saved->
                requireInvestmentCashReconciliationLedger(owner,eventId,saved,true);require(saved.syncVersion==1L && investmentCashReconciliationBusinessMatches(ledger,saved))
            }}
        }
    }
    override suspend fun publishPostings(owner:UserId,eventId:String,group:InvestmentCashReconciliationGroup,expectedVersions:Map<String,Long>,accessToken:String):List<CloudRecord> = safely {
        val c=capture(owner,eventId,accessToken,true);requireInvestmentCashReconciliationGroup(owner,eventId,group,false)
        val posts=listOf(group.holder,group.linked)
        require(expectedVersions.keys==posts.map{it.id}.toSet())
        for(row in posts) {
            val expected=expectedVersions.getValue(row.id);require(expected in 0 until Long.MAX_VALUE && row.syncVersion==expected+1)
            require(row.payload["trade_id"]==JsonNull && row.payload["asset_id"]==JsonNull && row.payload["deleted_at"]==JsonNull && row.payload.financeRawString("last_modified_by_device_id")!=null)
        }
        val body=buildJsonObject {
            put("p_rows",JsonArray(posts.map{it.payload}));put("p_expected_versions",buildJsonObject{expectedVersions.toSortedMap().forEach{(id,v)->put(id,v)}});put("p_force",false)
        }
        val url=c.base.newBuilder().addPathSegments("rest/v1/rpc/mutate_investment_cash_postings").build()
        ambiguous {
            val saved=execute(c,authorized(c,url).post(jsonBody(body)).build()).map{decode(c,CloudEntity.INVESTMENT_POSTING,it)}
            require(saved.size==2 && saved.map{it.id}.toSet()==expectedVersions.keys)
            val byId=saved.associateBy{it.id}
            val result=InvestmentCashReconciliationGroup(group.ledger,byId.getValue(group.holder.id),byId.getValue(group.linked.id))
            requireInvestmentCashReconciliationGroup(owner,eventId,result,false)
            for(row in posts) {
                val actual=byId.getValue(row.id)
                require(actual.syncVersion==expectedVersions.getValue(row.id)+1 && investmentCashReconciliationBusinessMatches(row,actual))
            }
            ensureCurrent(c);saved
        }
    }
    private fun jsonBody(body:JsonObject):RequestBody {
        val text=body.toString();require(text.toByteArray(Charsets.UTF_8).size<=MAX_BODY);return text.toRequestBody(JSON_TYPE)
    }
    private suspend inline fun <T> ambiguous(block:()->T):T=try{block()}
        catch(cancelled:CancellationException){throw cancelled}
        catch(http:SupabaseHttpException){throw http}
        catch(network:IOException){throw network}
        catch(invalid:Exception){throw IOException("Investment reconciliation result unavailable")}
    private suspend fun capture(owner:UserId,id:String,token:String,write:Boolean):Context {
        val caller=currentCoroutineContext();caller.ensureActive();uuid(owner.value);uuid(id)
        check(config.isConfigured){"Reconciliation service unavailable"};if(write)check(writesEnabled()){"Reconciliation writes disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Reconciliation session changed")
        val url=config.projectUrl.toHttpUrl();require(url.scheme=="https" && url.username.isEmpty() && url.password.isEmpty() && url.query==null && url.fragment==null)
        return Context(owner,id,session,write,url,caller).also(::ensureCurrent)
    }
    private fun ensureCurrent(c:Context) {
        c.caller.ensureActive()
        if(currentSession()!=c.session || c.write && !writesEnabled())throw CancellationException("Reconciliation authorization changed")
        c.caller.ensureActive()
    }
    private fun authorized(c:Context,url:HttpUrl):Request.Builder {
        ensureCurrent(c)
        return Request.Builder().url(url).header("Authorization","Bearer ${c.session.accessToken}").header("apikey",config.anonKey)
            .header("Content-Type","application/json").header("Prefer","return=representation")
    }
    private suspend fun execute(c:Context,request:Request):List<JsonObject> {
        ensureCurrent(c)
        val text=try{http.newCall(request).awaitText()}catch(error:Exception){ensureCurrent(c);throw error}
        ensureCurrent(c)
        if(text.isBlank())throw IOException("Reconciliation response unavailable")
        val rows=Json.parseToJsonElement(text).jsonArray;require(rows.size<=10000)
        return rows.map{it.jsonObject}.also{ensureCurrent(c)}
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
        require(p.financeRawString("event_id")==c.id && p.financeRawString("ledger_transaction_id")==investmentLedgerIdentity(c.id,"cash-reconciliation"))
        uuid(requireNotNull(p.financeRawString("wallet_id")))
        for(key in listOf("asset_id","trade_id"))require(p[key]==null || p[key]==JsonNull)
        require(p.financeRawString("role_raw_value") =="cashReconciliation" &&
            p.financeRawString("cash_bucket_raw_value") =="booked" && p.financeRawString("cash_origin_raw_value") =="manual")
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
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Reconciliation response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Reconciliation response exceeds limit")
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
        catch(network:IOException){throw IOException("Investment reconciliation network request failed")}
        catch(state:IllegalStateException){throw IllegalStateException("Investment reconciliation service unavailable")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment reconciliation request or response")}
    companion object {
        private const val MAX_BODY=8_388_608
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
        private val RETRY_MESSAGES=mapOf("version_conflict" to "version_conflict",
            "Transfer exceeds the investment profit held by this wallet" to "investment_cash_holder_limit",
            "Investment cash was already used on another device" to "investment_cash_used",
            "Investment cash ledger transaction is missing" to "investment_cash_ledger_missing",
            "Invalid investment cash wallet" to "investment_cash_invalid_wallet")
    }
}
