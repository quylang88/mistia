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

/** Closed canonical investment-wallet metadata port; ordinary wallets and financial rows stay outside it. */
class SupabaseInvestmentWalletClient(
    private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean,
) : RemoteMutationStore {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? = safely {
        val context=capture(entity,recordId,accessToken,ownerUserId,false)
        val url=context.url.newBuilder().addQueryParameter("id","eq.$recordId").addQueryParameter("limit","2").build()
        execute(context,request(context,url).get().build())
    }
    override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord = safely {
        val id=requireNotNull(payload.financeRawString("id")){"Missing wallet identity"}
        val context=capture(entity,id,accessToken,ownerUserId,true)
        validatePayload(context,payload)
        val body=JsonArray(listOf(investmentWalletPayloadForCloud(payload))).toString().toRequestBody(JSON_TYPE)
        validateWriteReply(context,payload,execute(context,request(context,context.url).post(body).build())) ?: throw IOException("Missing created investment wallet representation")
    }
    override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? = safely {
        require(expectedVersion in 0 until Long.MAX_VALUE){"Invalid wallet base version"}
        val context=capture(entity,recordId,accessToken,ownerUserId,true)
        validatePayload(context,payload)
        require(requireNotNull(payload.financeRawLong("sync_version"))>expectedVersion){"Investment wallet version must advance beyond the compared base"}
        val url=context.url.newBuilder().addQueryParameter("id","eq.$recordId").addQueryParameter("sync_version","eq.$expectedVersion").build()
        validateWriteReply(context,payload,execute(context,request(context,url).patch(JsonObject(payload-IMMUTABLE_PATCH_FIELDS).toString().toRequestBody(JSON_TYPE)).build()))
    }
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val url:HttpUrl,val caller:CoroutineContext)
    private suspend fun capture(entity:CloudEntity,id:String,token:String,owner:UserId,write:Boolean):Context {
        currentCoroutineContext().ensureActive()
        require(entity==CloudEntity.LEDGER_WALLET){"Only canonical investment wallet metadata is supported"}
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(id)==id){"Invalid wallet identity"}
        check(config.isConfigured){"Investment wallet service is not configured"}
        if(write)check(writesEnabled()){"Investment wallet writes are disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Investment wallet session changed")
        require(id==investmentSystemWalletId(owner)){"Only the canonical investment wallet identity is supported"}
        val base=config.projectUrl.toHttpUrl()
        require(base.scheme=="https" && base.username.isEmpty() && base.password.isEmpty() && base.query==null && base.fragment==null){"Invalid wallet service configuration"}
        val url=base.newBuilder().addPathSegments("rest/v1/ledger_wallets").addQueryParameter("user_id","eq.${owner.value}").build()
        return Context(owner,id,session,write,url,currentCoroutineContext()).also(::ensureCurrent)
    }
    private fun ensureCurrent(context:Context) {
        context.caller.ensureActive()
        if(currentSession()!=context.session || (context.write && !writesEnabled()))throw CancellationException("Investment wallet authorization changed")
        context.caller.ensureActive()
    }
    private fun validatePayload(context:Context,payload:JsonObject) {
        require(payload.financeRawString("id")==context.id && payload.financeRawString("user_id")==context.owner.value){"Investment wallet payload identity differs"}
        require(requireNotNull(payload.financeRawLong("sync_version"))>0){"Invalid investment wallet version"}
        val device=requireNotNull(payload.financeRawString("last_modified_by_device_id"))
        require(financeRawUuid(device)==device){"Invalid investment wallet device identity"}
        canonicalInvestmentWalletForPublication(context.owner,decode(context,payload),forWrite=true)
    }
    private fun request(context:Context,url:HttpUrl):Request.Builder {
        ensureCurrent(context)
        return Request.Builder().url(url).header("apikey",config.anonKey).header("Authorization","Bearer ${context.session.accessToken}")
            .header("Content-Type","application/json").header("Prefer","return=representation")
    }
    private suspend fun execute(context:Context,request:Request):CloudRecord? {
        ensureCurrent(context)
        val text=http.newCall(request).awaitText()
        ensureCurrent(context)
        if(text.isBlank())throw IOException("Investment wallet response is unavailable")
        val rows=Json.parseToJsonElement(text).jsonArray
        require(rows.size<=1){"Ambiguous wallet representation"}
        val record=rows.singleOrNull()?.jsonObject?.let{decode(context,it)}
        ensureCurrent(context)
        return record
    }
    private fun validateWriteReply(context:Context,submitted:JsonObject,result:CloudRecord?):CloudRecord? {
        if(result==null)return null
        val wallet=canonicalInvestmentWalletForPublication(context.owner,result,forWrite=true)
        require(wallet.currencyCode==submitted.financeRawString("currency_code")?.financeReportingCode()){"Investment wallet response changed accounting currency"}
        require(result.syncVersion==submitted.financeRawLong("sync_version")){"Investment wallet response changed proposed version"}
        return result
    }
    private fun decode(context:Context,payload:JsonObject):CloudRecord {
        require(LOCAL_INVESTMENT_WALLET_PARENTS_KEY !in payload){"Local investment wallet evidence cannot enter the wire port"}
        require(payload.financeRawString("id")==context.id && payload.financeRawString("user_id")==context.owner.value){"Investment wallet response identity differs"}
        val version=requireNotNull(payload.financeRawLong("sync_version"));require(version>=0){"Invalid wallet response version"}
        val updated=requireNotNull(payload.financeRawString("updated_at"));Instant.parse(updated)
        val deleted=payload.financeRawString("deleted_at")?.also{Instant.parse(it)}
        return CloudRecord(CloudEntity.LEDGER_WALLET.table,context.id,context.owner.value,payload,updated,deleted,version)
            .also{canonicalInvestmentWalletForPublication(context.owner,it)}
    }
    private suspend fun Call.awaitText():String = suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,error:IOException) {if(!continuation.isCancelled)continuation.resumeWithException(error)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val body=response.use {
                        if(!it.isSuccessful)throw SupabaseHttpException(it.code,"")
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Investment wallet response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Investment wallet response exceeds limit")
                                if(count>0)output.write(buffer,0,count)
                            }
                            output.toString(Charsets.UTF_8.name())
                        }
                    }
                    if(!continuation.isCancelled)continuation.resumeWith(Result.success(body))
                }catch(error:IOException){if(!continuation.isCancelled)continuation.resumeWithException(error)}
            }
        })
    }
    private suspend inline fun <T> safely(block:()->T):T = try{block()}
        catch(cancelled:CancellationException){throw cancelled}
        catch(http:SupabaseHttpException){throw SupabaseHttpException(http.statusCode,"")}
        catch(network:IOException){throw IOException("Investment wallet network request failed")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment wallet request or response")}
    companion object {
        private val IMMUTABLE_PATCH_FIELDS=setOf("current_balance_minor","opening_balance_minor","currency_code","kind_raw_value","system_purpose_raw_value","created_at")
        private const val MAX_BODY=2_000_000
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
    }
}
