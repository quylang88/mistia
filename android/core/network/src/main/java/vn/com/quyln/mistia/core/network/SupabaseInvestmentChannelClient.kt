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

/** Closed channel metadata port. Financial investment entities remain outside this client. */
class SupabaseInvestmentChannelClient(
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
        val id=requireNotNull(payload.financeRawString("id")){"Missing channel identity"}
        val context=capture(entity,id,accessToken,ownerUserId,true)
        validatePayload(context,payload,creating=true)
        val body=JsonArray(listOf(payload)).toString().toRequestBody(JSON_TYPE)
        requireNotNull(execute(context,request(context,context.url).post(body).build())){"Missing created channel representation"}
    }
    override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? = safely {
        require(expectedVersion in 0 until Long.MAX_VALUE){"Invalid channel base version"}
        val context=capture(entity,recordId,accessToken,ownerUserId,true)
        validatePayload(context,payload,creating=false)
        require(requireNotNull(payload.financeRawLong("sync_version"))>expectedVersion){"Channel version must advance beyond the compared base"}
        val url=context.url.newBuilder().addQueryParameter("id","eq.$recordId").addQueryParameter("sync_version","eq.$expectedVersion").build()
        execute(context,request(context,url).patch(payload.toString().toRequestBody(JSON_TYPE)).build())
    }
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val url:HttpUrl,val caller:CoroutineContext)
    private suspend fun capture(entity:CloudEntity,id:String,token:String,owner:UserId,write:Boolean):Context {
        currentCoroutineContext().ensureActive()
        require(entity==CloudEntity.INVESTMENT_CHANNEL){"Only investment channel metadata is supported"}
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(id)==id){"Invalid channel identity"}
        check(config.isConfigured){"Investment channel service is not configured"}
        if(write)check(writesEnabled()){"Investment channel writes are disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Investment channel session changed")
        val base=config.projectUrl.toHttpUrl()
        require(base.scheme=="https" && base.username.isEmpty() && base.password.isEmpty() && base.query==null && base.fragment==null){"Invalid channel service configuration"}
        val url=base.newBuilder().addPathSegments("rest/v1/investment_channels").addQueryParameter("user_id","eq.${owner.value}").build()
        return Context(owner,id,session,write,url,currentCoroutineContext()).also(::ensureCurrent)
    }
    private fun ensureCurrent(context:Context) {
        context.caller.ensureActive()
        if(currentSession()!=context.session || (context.write && !writesEnabled()))throw CancellationException("Investment channel authorization changed")
        context.caller.ensureActive()
    }
    private fun validatePayload(context:Context,payload:JsonObject,creating:Boolean) {
        require(payload.financeRawString("id")==context.id && payload.financeRawString("user_id")==context.owner.value){"Channel payload identity differs"}
        val version=requireNotNull(payload.financeRawLong("sync_version"));require(version>0){"Invalid channel version"}
        Instant.parse(requireNotNull(payload.financeRawString("updated_at")))
        require(financeRawUuid(requireNotNull(payload.financeRawString("last_modified_by_device_id")))==payload.financeRawString("last_modified_by_device_id")){"Invalid channel device identity"}
        val deleted=payload.financeRawString("deleted_at")
        if(deleted!=null) {
            require(!creating && payload.keys==DELETE_KEYS){"Invalid channel tombstone patch"};Instant.parse(deleted)
        } else {
            val record=decode(context,payload)
            val channel=InvestmentChannelRecord.fromCloudRecord(record)
            require(channel.name.isNotEmpty() && normalizedInvestmentChannelName(channel.name)==channel.name){"Invalid channel name"}
        }
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
        val rows=Json.parseToJsonElement(text).jsonArray
        require(rows.size<=1){"Ambiguous channel representation"}
        val record=rows.singleOrNull()?.jsonObject?.let{decode(context,it)}
        ensureCurrent(context)
        return record
    }
    private fun decode(context:Context,payload:JsonObject):CloudRecord {
        require(payload.financeRawString("id")==context.id && payload.financeRawString("user_id")==context.owner.value){"Channel response identity differs"}
        val version=requireNotNull(payload.financeRawLong("sync_version"));require(version>=0){"Invalid channel response version"}
        val updated=requireNotNull(payload.financeRawString("updated_at"));Instant.parse(updated)
        val deleted=payload.financeRawString("deleted_at")?.also{Instant.parse(it)}
        return CloudRecord(CloudEntity.INVESTMENT_CHANNEL.table,context.id,context.owner.value,payload,updated,deleted,version)
            .also{InvestmentChannelRecord.fromCloudRecord(it)}
    }
    private suspend fun Call.awaitText():String = suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,error:IOException) {if(!continuation.isCancelled)continuation.resumeWithException(error)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val body=response.use {
                        if(!it.isSuccessful)throw SupabaseHttpException(it.code,"")
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Channel response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Channel response exceeds limit")
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
        catch(network:IOException){throw IOException("Investment channel network request failed")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment channel request or response")}
    companion object {
        private const val MAX_BODY=2_000_000
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
        private val DELETE_KEYS=setOf("id","user_id","updated_at","deleted_at","sync_version","last_modified_by_device_id")
    }
}
