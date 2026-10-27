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

/** Only the existing atomic deposit/withdrawal RPC, with separately owned complete event reads. */
class SupabaseInvestmentCashEventClient(private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean):InvestmentCashEventRemote {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val base:HttpUrl,val caller:CoroutineContext)

    override suspend fun fetchEvent(owner:UserId,eventId:String,accessToken:String):InvestmentCashEventCloudSnapshot=safely {
        val c=capture(owner,eventId,accessToken,false)
        val ledgerUrl=c.base.newBuilder().addPathSegments("rest/v1/ledger_transactions").addQueryParameter("user_id","eq.${owner.value}")
            .addQueryParameter("id","eq.$eventId").addQueryParameter("limit","2").build()
        val ledgerRows=execute(c,authorized(c,ledgerUrl).get().build());require(ledgerRows.size<=1)
        val ledger=ledgerRows.singleOrNull()?.let{decode(c,CloudEntity.LEDGER_TRANSACTION,it).also{row->transaction(c,row,false)}}
        val postings=mutableListOf<CloudRecord>();var cursor:String?=null;var chars=0L
        while(true) {
            val url=c.base.newBuilder().addPathSegments("rest/v1/investment_wallet_postings").addQueryParameter("user_id","eq.${owner.value}")
                .addQueryParameter("event_id","eq.$eventId").addQueryParameter("order","id.asc").addQueryParameter("limit","100")
                .apply{cursor?.let{addQueryParameter("id","gt.$it")}}.build()
            val page=execute(c,authorized(c,url).get().build());require(page.size<=100)
            if(page.isEmpty())break
            for(p in page) {
                val row=decode(c,CloudEntity.INVESTMENT_POSTING,p);posting(c,row)
                require(cursor?.let{row.id>it}!=false)
                chars+=p.toString().length;require(postings.size<10000 && chars<=67_108_864)
                cursor=row.id;postings+=row
            }
        }
        ensureCurrent(c);InvestmentCashEventCloudSnapshot(owner,eventId,ledger,postings)
    }

    override suspend fun mutateEvent(owner:UserId,proposal:InvestmentCashEventProposal,expectedVersion:Long,expectedPostingVersion:Long?,accessToken:String):CloudRecord?=safely {
        val c=capture(owner,proposal.transaction.id,accessToken,true);base(expectedVersion);expectedPostingVersion?.let(::base)
        val row=proposal.transaction;transaction(c,row,true);posting(c,proposal.posting)
        require(row.syncVersion==expectedVersion+1)
        val post=proposal.posting;val p=post.payload;val t=row.payload
        require(post.id==investmentLedgerIdentity(c.id,"cash-transfer-posting") && post.deletedAt==null)
        require(post.syncVersion==(expectedPostingVersion?.plus(1) ?: 1L))
        require(p["trade_id"]==JsonNull && p["asset_id"]==JsonNull && p.financeRawString("role_raw_value")=="cashTransfer" &&
            p.financeRawString("cash_bucket_raw_value")=="booked" && p.financeRawString("cash_origin_raw_value")=="manual")
        val deposit=t.financeRawString("settlement_role_raw_value")=="investmentCashDeposit"
        val amount=requireNotNull(t.financeRawLong("amount_minor"));val signed=if(deposit)amount else -amount
        val code=requireNotNull(t.financeRawString("reporting_currency_code"))
        require(p.financeRawLong("amount_minor")==signed && p.financeRawLong("accounting_amount_minor")==signed &&
            p.financeRawString("currency_code")==code && p.financeRawString("accounting_currency_code")==code &&
            p.financeRawString("wallet_id")==t.financeRawString(if(deposit)"destination_wallet_id" else "source_wallet_id"))
        require(instant(p.financeRawString("occurred_at"))==instant(t.financeRawString("occurred_at")) &&
            instant(post.updatedAt)==instant(row.updatedAt) && p.financeRawString("last_modified_by_device_id")==t.financeRawString("last_modified_by_device_id"))
        val body=body(c,expectedVersion,expectedPostingVersion,buildJsonObject{
            put("p_transaction",t);put("p_postings",JsonArray(listOf(p)))
            for(key in listOf("p_transaction_id","p_owner_user_id","p_deleted_at","p_device_id"))put(key,JsonNull)
        })
        write(c,body,expectedVersion){saved->
            require(saved.deletedAt==null && saved.payload.financeRawString("last_modified_by_device_id")==t.financeRawString("last_modified_by_device_id"))
            require(semantic(saved.payload)==semantic(t))
        }
    }

    override suspend fun deleteEvent(owner:UserId,eventId:String,expectedVersion:Long,expectedPostingVersion:Long?,modifiedAt:String,deviceId:String,accessToken:String):CloudRecord?=safely {
        val c=capture(owner,eventId,accessToken,true);base(expectedVersion);expectedPostingVersion?.let(::base);instant(modifiedAt);uuid(deviceId)
        val body=body(c,expectedVersion,expectedPostingVersion,buildJsonObject{
            put("p_transaction",JsonNull);put("p_postings",JsonArray(emptyList()));put("p_transaction_id",eventId)
            put("p_owner_user_id",owner.value);put("p_deleted_at",modifiedAt);put("p_device_id",deviceId)
        })
        write(c,body,expectedVersion){saved->require(saved.deletedAt!=null && instant(saved.deletedAt)==instant(modifiedAt) &&
            instant(saved.updatedAt)==instant(modifiedAt) && saved.payload.financeRawString("last_modified_by_device_id")==deviceId)}
    }

    private fun body(c:Context,version:Long,postingVersion:Long?,fields:JsonObject)=JsonObject(fields+buildJsonObject {
        put("p_expected_version",version);put("p_expected_posting_versions",buildJsonObject{
            postingVersion?.let{put(investmentLedgerIdentity(c.id,"cash-transfer-posting"),it)}
        });put("p_force",false)
    })
    private suspend fun write(c:Context,body:JsonObject,expectedVersion:Long,check:(CloudRecord)->Unit):CloudRecord? {
        val text=body.toString();require(text.toByteArray(Charsets.UTF_8).size<=MAX_BODY)
        val url=c.base.newBuilder().addPathSegments("rest/v1/rpc/mutate_investment_cash_event").build()
        val request=authorized(c,url).post(text.toRequestBody(JSON_TYPE)).build()
        // After HTTP starts, malformed replies are ambiguous outcomes: keep work for owned recovery reads.
        return try {
            val rows=execute(c,request);require(rows.size<=1)
            rows.singleOrNull()?.let{p->decode(c,CloudEntity.LEDGER_TRANSACTION,p).also{row->
                transaction(c,row,false);require(row.syncVersion==expectedVersion+1);check(row);ensureCurrent(c)
            }}
        }catch(cancelled:CancellationException){throw cancelled}
        catch(http:SupabaseHttpException){throw http}
        catch(network:IOException){throw network}
        catch(invalid:Exception){throw IOException("Investment cash event result unavailable")}
    }
    private suspend fun capture(owner:UserId,id:String,token:String,write:Boolean):Context {
        val caller=currentCoroutineContext();caller.ensureActive();uuid(owner.value);uuid(id)
        check(config.isConfigured){"Cash event service unavailable"};if(write)check(writesEnabled()){"Cash event writes disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Cash event session changed")
        val url=config.projectUrl.toHttpUrl();require(url.scheme=="https" && url.username.isEmpty() && url.password.isEmpty() && url.query==null && url.fragment==null)
        return Context(owner,id,session,write,url,caller).also(::ensureCurrent)
    }
    private fun ensureCurrent(c:Context) {
        c.caller.ensureActive()
        if(currentSession()!=c.session || c.write && !writesEnabled())throw CancellationException("Cash event authorization changed")
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
        if(text.isBlank())throw IOException("Cash event response unavailable")
        val rows=Json.parseToJsonElement(text).jsonArray;require(rows.size<=10000)
        return rows.map{it.jsonObject}.also{ensureCurrent(c)}
    }
    private fun uuid(value:String){require(financeRawUuid(value)==value)}
    private fun base(value:Long){require(value in 0 until Long.MAX_VALUE)}
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
    private fun transaction(c:Context,row:CloudRecord,forWrite:Boolean) {
        common(c,row,CloudEntity.LEDGER_TRANSACTION);require(row.id==c.id)
        val p=row.payload;require(p.financeRawString("settlement_role_raw_value") in setOf("investmentCashDeposit","investmentCashWithdrawal") &&
            p.financeRawString("primary_kind_raw_value")=="transfer" && p.financeRawString("transfer_subtype_raw_value")=="internalTransfer" &&
            p.financeRawString("entry_status_raw_value")=="posted" && p.financeRawArchived()==false)
        require(!p.financeRawString("title").isNullOrBlank())
        val amount=requireNotNull(p.financeRawLong("amount_minor"));require(amount>0 && p.financeRawLong("destination_amount_minor")==amount &&
            p.financeRawLong("reporting_amount_minor")==amount && p.financeRawLong("reporting_expense_minor")==0L && p.financeRawLong("reporting_income_minor")==0L)
        val currency=code(p.financeRawString("source_currency_code"));require(code(p.financeRawString("destination_currency_code"))==currency && code(p.financeRawString("reporting_currency_code"))==currency)
        for(key in listOf("source_wallet_id","destination_wallet_id","created_by_user_id","last_modified_by_user_id"))uuid(requireNotNull(p.financeRawString(key)))
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at"))
            require(p[key]==JsonNull || !forWrite && key !in p)
        require(p["note"]==null || p["note"]==JsonNull || p.financeRawString("note")!=null)
        if(forWrite){require(row.deletedAt==null && p["deleted_at"]==JsonNull);uuid(requireNotNull(p.financeRawString("last_modified_by_device_id")))}
    }
    private fun posting(c:Context,row:CloudRecord) {
        common(c,row,CloudEntity.INVESTMENT_POSTING);val p=row.payload
        require(p.financeRawString("event_id")==c.id && p.financeRawString("ledger_transaction_id")==c.id)
        uuid(requireNotNull(p.financeRawString("wallet_id")))
        for(key in listOf("asset_id","trade_id"))require(p[key]==null || p[key]==JsonNull)
        require(p.financeRawString("role_raw_value") in setOf("cashTransfer","cashAccrual","cashReconciliation","cashConsumption","cashCorrection") &&
            p.financeRawString("cash_bucket_raw_value") in setOf("booked","unreconciled") && p.financeRawString("cash_origin_raw_value") in setOf("manual","derived","inferred"))
        require(p.financeRawLong("amount_minor")!=null && p.financeRawLong("accounting_amount_minor")!=null)
        code(p.financeRawString("currency_code"));code(p.financeRawString("accounting_currency_code"))
    }
    private fun semantic(p:JsonObject)=JsonObject((p-setOf("sync_version","updated_at","last_modified_by_device_id","last_modified_by_user_id")).mapValues{(key,value)->
        when(key){"created_at","occurred_at","deleted_at"->if(value==JsonNull)JsonNull else JsonPrimitive(instant(p.financeRawString(key)).toString());else->value}
    })
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
                                    body.financeRawString("message")?.takeIf{code->body.financeRawString("code")=="P0001" && code in INVESTMENT_CASH_EVENT_RETRY_CODES}
                                }
                            }.getOrNull() else null
                            throw SupabaseHttpException(it.code,"",serviceCode)
                        }
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Cash event response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Cash event response exceeds limit")
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
        catch(network:IOException){throw IOException("Investment cash event network request failed")}
        catch(state:IllegalStateException){throw IllegalStateException("Investment cash event service unavailable")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment cash event request or response")}
    companion object {private const val MAX_BODY=8_388_608;private val JSON_TYPE="application/json; charset=utf-8".toMediaType()}
}
