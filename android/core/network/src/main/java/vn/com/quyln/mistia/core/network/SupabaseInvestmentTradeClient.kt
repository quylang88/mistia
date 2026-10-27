package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.time.Instant
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import vn.com.quyln.mistia.core.model.*

/** The atomic RPC owns FIFO/financial rebuilding; generic table writes remain closed. */
class SupabaseInvestmentTradeClient(
    private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean,
):InvestmentTradeRemote,InvestmentRetirementRemote {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val base:HttpUrl,val caller:CoroutineContext)
    override suspend fun fetchRetirementHistory(owner:UserId,entity:CloudEntity,id:String,accessToken:String):InvestmentRetirementHistory = safely {
        require(entity in setOf(CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_CHANNEL))
        val context=capture(owner,id,accessToken,false)
        var characters=0L
        suspend fun pages(table:CloudEntity):List<CloudRecord> {
            val result=mutableListOf<CloudRecord>();var cursor:String?=null
            while(true) {
                val url=context.base.newBuilder().addPathSegments("rest/v1/${table.table}")
                    .addQueryParameter("user_id","eq.${owner.value}").addQueryParameter("order","id.asc").addQueryParameter("limit","100")
                    .addQueryParameter(if(entity==CloudEntity.INVESTMENT_CHANNEL)"channel_id" else if(table==CloudEntity.INVESTMENT_ASSET)"id" else "asset_id","eq.$id")
                    .apply{cursor?.let{addQueryParameter("id","gt.$it")}}.build()
                val rows=execute(context,authorized(context,url).get().build());require(rows.size<=100)
                if(rows.isEmpty())break
                for(payload in rows) {
                    val row=if(table==CloudEntity.INVESTMENT_TRADE)decode(context,payload) else {
                        val key=requireNotNull(payload.financeRawString("id"));val version=requireNotNull(payload.financeRawLong("sync_version"))
                        CloudRecord(table.table,key,owner.value,payload,payload.financeRawString("updated_at"),payload.financeRawString("deleted_at"),version).also{
                            InvestmentAssetRecord.fromCloudRecord(it)
                            require(payload.financeRawString("id")==key && payload.financeRawString("user_id")==owner.value && payload.keys.none{it.startsWith("_mistia_android_")})
                        }
                    }
                    require(cursor?.let{row.id>it}!=false)
                    require(if(entity==CloudEntity.INVESTMENT_CHANNEL)row.payload.financeRawString("channel_id")==id
                        else if(table==CloudEntity.INVESTMENT_ASSET)row.id==id else row.payload.financeRawString("asset_id")==id)
                    cursor=row.id;characters+=payload.toString().length
                    require(result.size<10000 && characters<=67_108_864)
                    result+=row
                }
            }
            return result
        }
        val assets=pages(CloudEntity.INVESTMENT_ASSET);val trades=pages(CloudEntity.INVESTMENT_TRADE)
        ensureCurrent(context)
        InvestmentRetirementHistory(owner,entity,id,assets,trades).also{it.requireValid()}
    }
    override suspend fun fetchTradeResult(owner:UserId,affectedAssetIds:Set<String>,knownTradeIds:Set<String>,accessToken:String):InvestmentTradeCloudSnapshot = safely {
        require(affectedAssetIds.size in 1..2 && affectedAssetIds.all{financeRawUuid(it)==it})
        require(knownTradeIds.size<=10000 && knownTradeIds.all{financeRawUuid(it)==it})
        val context=capture(owner,affectedAssetIds.sorted().first(),accessToken,false)
        val result=mutableListOf<CloudRecord>()
        var characters=0L
        suspend fun pages(entity:CloudEntity,ids:Set<String>?=null) {
            var cursor:String?=null
            while(true) {
                val url=context.base.newBuilder().addPathSegments("rest/v1/${entity.table}")
                    .addQueryParameter("user_id","eq.${owner.value}").addQueryParameter("order","id.asc").addQueryParameter("limit","100")
                    .apply {
                        if(ids==null)addQueryParameter("asset_id","in.(${affectedAssetIds.sorted().joinToString(",")})")
                        else addQueryParameter("id","in.(${ids.sorted().joinToString(",")})")
                        cursor?.let{addQueryParameter("id","gt.$it")}
                    }.build()
                val page=execute(context,authorized(context,url).get().build())
                require(page.size<=100)
                // A short page can reflect a lower server row cap. Only an empty page proves exhaustion.
                if(page.isEmpty())break
                for(payload in page) {
                    val row=if(entity==CloudEntity.INVESTMENT_TRADE)decode(context,payload) else decodeFinancial(context,entity,payload)
                    require(cursor?.let{row.id>it}!=false){"Investment result page did not advance"}
                    if(ids==null)require(row.payload.financeRawString("asset_id") in affectedAssetIds) else require(row.id in ids)
                    cursor=row.id
                    characters+=payload.toString().length
                    require(result.size<80000 && characters<=67_108_864){"Investment result exceeds limit"}
                    result+=row
                    if(entity==CloudEntity.INVESTMENT_TRADE)require(result.size<=10000)
                }
            }
        }
        pages(CloudEntity.INVESTMENT_TRADE)
        val trades=knownTradeIds+result.map{it.id}
        require(trades.size<=10000)
        for((entity,components) in listOf(
            CloudEntity.LEDGER_TRANSACTION to listOf("funding","capital-return","profit-loss"),
            CloudEntity.INVESTMENT_POSTING to listOf("funding-posting","capital-return-posting","profit-loss-posting","cash-accrual-posting"),
        )) {
            val ids=trades.flatMap{trade->components.map{investmentLedgerIdentity(trade,it)}}.toSet()
            require(ids.size==trades.size*components.size)
            for(chunk in ids.sorted().chunked(100))pages(entity,chunk.toSet())
        }
        ensureCurrent(context)
        // This is a read candidate. Cross-table consistency and dirty intent proof belong to the atomic Room ACK.
        InvestmentTradeCloudSnapshot(owner,affectedAssetIds,result)
    }
    override suspend fun fetchTrade(owner:UserId,id:String,accessToken:String):CloudRecord?=safely {
        val context=capture(owner,id,accessToken,false)
        val url=context.base.newBuilder().addPathSegments("rest/v1/investment_trades")
            .addQueryParameter("user_id","eq.${owner.value}").addQueryParameter("id","eq.$id").addQueryParameter("limit","2").build()
        val rows=execute(context,authorized(context,url).get().build())
        require(rows.size<=1){"Ambiguous investment trade lookup"}
        rows.singleOrNull()?.let{decode(context,it).also{row->require(row.id==id)}}
    }
    override suspend fun mutateTrade(owner:UserId,proposal:CloudRecord,expectedVersion:Long,affectedAssetIds:Set<String>,accessToken:String):InvestmentTradeMutationResult?=safely {
        val context=capture(owner,proposal.id,accessToken,true)
        requireInvestmentTradeForPublication(owner,proposal)
        require(expectedVersion>=0 && expectedVersion<Long.MAX_VALUE-1 && proposal.syncVersion>expectedVersion && proposal.syncVersion<Long.MAX_VALUE)
        require(affectedAssetIds.size in 1..2 && affectedAssetIds.all{financeRawUuid(it)==it} && proposal.payload.financeRawString("asset_id") in affectedAssetIds)
        val body=buildJsonObject {
            put("p_trade",investmentTradePayloadForCloud(proposal.payload));put("p_expected_version",expectedVersion);put("p_force",false)
        }
        val values=execute(context,rpc(context,"mutate_investment_trade",body))
        if(values.isEmpty())return@safely null
        val rows=values.map{decode(context,it)}
        require(rows.map{it.id}.distinct().size==rows.size && rows.all{it.deletedAt==null && it.payload.financeRawString("asset_id") in affectedAssetIds}) {
            "Investment trade result scope differs"
        }
        val saved=rows.singleOrNull{it.id==proposal.id} ?: throw IllegalArgumentException("Missing requested investment trade result")
        // INSERT fixes version1, then rebuild advances it. Existing rows use incoming proposal then rebuild.
        val rebuilt=proposal.syncVersion+1
        require(if(expectedVersion==0L)saved.syncVersion==2L || saved.syncVersion==rebuilt else saved.syncVersion==rebuilt) {
            "Unexpected rebuilt investment trade version"
        }
        require(sameSubmittedIntent(proposal.payload,saved.payload)){"Investment trade response changed submitted intent"}
        ensureCurrent(context)
        InvestmentTradeMutationResult(saved,rows)
    }
    override suspend fun deleteTrade(owner:UserId,id:String,expectedVersion:Long,modifiedAt:String,deviceId:String,accessToken:String):CloudRecord?=safely {
        val context=capture(owner,id,accessToken,true)
        require(expectedVersion>=0 && expectedVersion<Long.MAX_VALUE && financeRawUuid(deviceId)==deviceId);Instant.parse(modifiedAt)
        val body=buildJsonObject {
            put("p_trade_id",id);put("p_owner_user_id",owner.value);put("p_expected_version",expectedVersion)
            put("p_modified_at",modifiedAt);put("p_device_id",deviceId)
        }
        val values=execute(context,rpc(context,"delete_investment_trade",body));require(values.size<=1)
        values.singleOrNull()?.let{decode(context,it).also{saved->
            require(saved.id==id && saved.syncVersion==expectedVersion+1 && saved.deletedAt!=null &&
                postgresInstant(requireNotNull(saved.deletedAt))==postgresInstant(modifiedAt) && saved.payload.financeRawString("last_modified_by_device_id")==deviceId)
            ensureCurrent(context)
        }}
    }
    private suspend fun capture(owner:UserId,id:String,token:String,write:Boolean):Context {
        currentCoroutineContext().ensureActive()
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(id)==id)
        check(config.isConfigured){"Investment trade service unavailable"}
        if(write)check(writesEnabled()){"Investment trade writes disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Investment trade session changed")
        val base=config.projectUrl.toHttpUrl()
        require(base.scheme=="https" && base.username.isEmpty() && base.password.isEmpty() && base.query==null && base.fragment==null)
        return Context(owner,id,session,write,base,currentCoroutineContext()).also(::ensureCurrent)
    }
    private fun ensureCurrent(context:Context) {
        context.caller.ensureActive()
        if(currentSession()!=context.session || context.write && !writesEnabled())throw CancellationException("Investment trade authorization changed")
        context.caller.ensureActive()
    }
    private fun authorized(context:Context,url:HttpUrl):Request.Builder {
        ensureCurrent(context)
        return Request.Builder().url(url).header("apikey",config.anonKey).header("Authorization","Bearer ${context.session.accessToken}")
            .header("Content-Type","application/json").header("Prefer","return=representation")
    }
    private fun rpc(context:Context,function:String,body:JsonObject):Request {
        val url=context.base.newBuilder().addPathSegments("rest/v1/rpc/$function").build()
        return authorized(context,url).post(body.toString().toRequestBody(JSON_TYPE)).build()
    }
    private suspend fun execute(context:Context,request:Request):List<JsonObject> {
        ensureCurrent(context)
        val text=http.newCall(request).awaitText();ensureCurrent(context)
        if(text.isBlank())throw IOException("Investment trade response unavailable")
        val rows=Json.parseToJsonElement(text).jsonArray;require(rows.size<=10000){"Investment trade result exceeds limit"}
        val result=rows.map{it.jsonObject};ensureCurrent(context);return result
    }
    private fun decode(context:Context,payload:JsonObject):CloudRecord {
        val id=requireNotNull(payload.financeRawString("id"));val version=requireNotNull(payload.financeRawLong("sync_version"))
        val updated=requireNotNull(payload.financeRawString("updated_at"));val deleted=payload.financeRawString("deleted_at")
        return CloudRecord(CloudEntity.INVESTMENT_TRADE.table,id,context.owner.value,payload,updated,deleted,version).also {
            requireInvestmentTradeForPublication(context.owner,it,forWrite=false,allowLocalEvidence=false)
        }
    }
    private fun decodeFinancial(context:Context,entity:CloudEntity,payload:JsonObject):CloudRecord {
        require(entity in setOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING))
        val id=requireNotNull(payload.financeRawString("id"));require(financeRawUuid(id)==id)
        val version=requireNotNull(payload.financeRawLong("sync_version"));require(version>=0)
        val updated=requireNotNull(payload.financeRawString("updated_at"))
        val row=CloudRecord(entity.table,id,context.owner.value,payload,updated,payload.financeRawString("deleted_at"),version)
        require(row.financeRawIdentity(context.owner,entity,true) && row.financeRawDeleted(true)!=null)
        for(key in listOf("created_at","updated_at","occurred_at"))Instant.parse(requireNotNull(payload.financeRawString(key)))
        for(key in LOCAL_ASSET_PUBLICATION_KEYS+LOCAL_INVESTMENT_WALLET_PARENTS_KEY+LOCAL_TRADE_PUBLICATION_PARENTS_KEY)require(key !in payload)
        return row
    }
    private fun sameSubmittedIntent(proposal:JsonObject,result:JsonObject):Boolean {
        fun value(p:JsonObject,key:String):JsonElement {
            val raw=p[key] ?: return JsonNull
            if(raw==JsonNull)return raw
            val text=p.financeRawString(key)
            return when(key) {
                "created_at","occurred_at"->JsonPrimitive(postgresInstant(requireNotNull(text)).toString())
                "quantity_decimal_string","exchange_rate_decimal_string","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string"->
                    JsonPrimitive(requireNotNull(text).toBigDecimal().stripTrailingZeros().toPlainString())
                "unit_label"->InvestmentUnitLabel.normalizedDisplay(text)?.let(::JsonPrimitive) ?: JsonNull
                "note"->text?.trim()?.takeUnless{it.isEmpty()}?.let(::JsonPrimitive) ?: JsonNull
                "currency_code","accounting_currency_code"->JsonPrimitive(requireNotNull(text?.financeReportingCode()))
                else->raw
            }
        }
        return INTENT_KEYS.all{value(proposal,it)==value(result,it)}
    }
    private fun postgresInstant(value:String):Instant {
        val instant=Instant.parse(value)
        return Instant.ofEpochSecond(instant.epochSecond,Math.rint(instant.nano.toDouble()/1000).toLong()*1000)
    }
    private suspend fun Call.awaitText():String=suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,e:IOException){if(!continuation.isCancelled)continuation.resumeWithException(e)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val text=response.use {
                        if(!it.isSuccessful)throw SupabaseHttpException(it.code,"")
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Investment trade response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Investment trade response exceeds limit")
                                if(count>0)output.write(buffer,0,count)
                            }
                            output.toString(Charsets.UTF_8.name())
                        }
                    }
                    if(!continuation.isCancelled)continuation.resumeWith(Result.success(text))
                }catch(error:IOException){if(!continuation.isCancelled)continuation.resumeWithException(error)}
            }
        })
    }
    private suspend inline fun <T> safely(block:()->T):T=try{block()}
        catch(cancelled:CancellationException){throw cancelled}
        catch(changed:InvestmentRetirementHistoryChanged){throw changed}
        catch(http:SupabaseHttpException){throw SupabaseHttpException(http.statusCode,"")}
        catch(network:IOException){throw IOException("Investment trade network request failed")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment trade request or response")}
    companion object {
        private const val MAX_BODY=8_388_608
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
        private val INTENT_KEYS=setOf("id","user_id","asset_id","channel_id","kind_raw_value","quantity_decimal_string","unit_label",
            "gross_amount_minor","currency_code","accounting_gross_amount_minor","accounting_currency_code","exchange_rate_decimal_string",
            "exchange_rate_provider","exchange_rate_date","funding_wallet_id","capital_return_wallet_id","funding_to_accounting_rate_decimal_string",
            "accounting_to_capital_return_rate_decimal_string","note","occurred_at","created_at","last_modified_by_device_id")
    }
}
