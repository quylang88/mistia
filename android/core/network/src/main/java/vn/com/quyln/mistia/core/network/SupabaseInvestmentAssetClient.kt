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

/** Closed asset RPC port. Financial investment writers remain outside this client. */
class SupabaseInvestmentAssetClient(
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
        val id=requireNotNull(payload.financeRawString("id")){"Missing asset identity"}
        val context=capture(entity,id,accessToken,ownerUserId,true)
        validatePayload(context,payload,creating=true)
        mutate(context,payload,0) ?: throw SupabaseHttpException(409,"")
    }
    override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? = safely {
        require(expectedVersion in 0 until Long.MAX_VALUE){"Invalid asset base version"}
        val context=capture(entity,recordId,accessToken,ownerUserId,true)
        validatePayload(context,payload,creating=false)
        require(requireNotNull(payload.financeRawLong("sync_version"))>expectedVersion){"Asset proposed version must advance beyond the compared base"}
        if(payload.financeRawString("deleted_at")!=null) {
            val body=buildJsonObject {
                put("p_asset_id",context.id);put("p_owner_user_id",context.owner.value);put("p_expected_version",expectedVersion)
                put("p_modified_at",requireNotNull(payload.financeRawString("deleted_at")))
                put("p_device_id",requireNotNull(payload.financeRawString("last_modified_by_device_id")))
            }
            executeRpc(context,"delete_investment_asset",body)
        } else mutate(context,payload,expectedVersion)
    }
    private suspend fun mutate(context:Context,payload:JsonObject,expectedVersion:Long):CloudRecord? = executeRpc(context,"mutate_investment_asset",buildJsonObject {
        put("p_asset",assetPayloadForCloud(payload));put("p_expected_version",expectedVersion);put("p_force",false)
    })
    private suspend fun executeRpc(context:Context,function:String,payload:JsonObject):CloudRecord? {
        val url=config.projectUrl.toHttpUrl().newBuilder().addPathSegments("rest/v1/rpc/$function").build()
        return execute(context,request(context,url).post(payload.toString().toRequestBody(JSON_TYPE)).build())
    }
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val write:Boolean,val url:HttpUrl,val caller:CoroutineContext)
    private suspend fun capture(entity:CloudEntity,id:String,token:String,owner:UserId,write:Boolean):Context {
        currentCoroutineContext().ensureActive()
        require(entity==CloudEntity.INVESTMENT_ASSET){"Only investment asset metadata is supported"}
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(id)==id){"Invalid asset identity"}
        check(config.isConfigured){"Investment asset service is not configured"}
        if(write)check(writesEnabled()){"Investment asset writes are disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Investment asset session changed")
        val base=config.projectUrl.toHttpUrl()
        require(base.scheme=="https" && base.username.isEmpty() && base.password.isEmpty() && base.query==null && base.fragment==null){"Invalid asset service configuration"}
        val url=base.newBuilder().addPathSegments("rest/v1/investment_assets").addQueryParameter("user_id","eq.${owner.value}").build()
        return Context(owner,id,session,write,url,currentCoroutineContext()).also(::ensureCurrent)
    }
    private fun ensureCurrent(context:Context) {
        context.caller.ensureActive()
        if(currentSession()!=context.session || (context.write && !writesEnabled()))throw CancellationException("Investment asset authorization changed")
        context.caller.ensureActive()
    }
    private fun validatePayload(context:Context,payload:JsonObject,creating:Boolean) {
        require(payload.financeRawString("id")==context.id && payload.financeRawString("user_id")==context.owner.value){"Asset payload identity differs"}
        val version=requireNotNull(payload.financeRawLong("sync_version"));require(version>0){"Invalid asset version"}
        Instant.parse(requireNotNull(payload.financeRawString("updated_at")))
        require(financeRawUuid(requireNotNull(payload.financeRawString("last_modified_by_device_id")))==payload.financeRawString("last_modified_by_device_id")){"Invalid asset device identity"}
        val deleted=payload.financeRawString("deleted_at")
        if(deleted!=null) {
            require(!creating && payload.keys==DELETE_KEYS){"Invalid asset tombstone patch"};Instant.parse(deleted)
        } else {
            val record=decode(context,payload,allowLocal=true)
            val asset=InvestmentAssetRecord.fromCloudRecord(record)
            require(asset.name.isNotEmpty() && normalizedInvestmentChannelName(asset.name)==asset.name){"Invalid asset name"}
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
        if(text.isBlank())throw IOException("Asset response is unavailable")
        val rows=Json.parseToJsonElement(text).jsonArray
        require(rows.size<=1){"Ambiguous asset representation"}
        val record=rows.singleOrNull()?.jsonObject?.let{decode(context,it)}
        ensureCurrent(context)
        return record
    }
    private fun decode(context:Context,payload:JsonObject,allowLocal:Boolean=false):CloudRecord {
        require(allowLocal || LOCAL_ASSET_IMAGE_INTENT_KEY !in payload){"Remote asset cannot supply local image provenance"}
        require(payload.financeRawString("id")==context.id && payload.financeRawString("user_id")==context.owner.value){"Asset response identity differs"}
        val version=requireNotNull(payload.financeRawLong("sync_version"));require(version>=0){"Invalid asset response version"}
        val updated=requireNotNull(payload.financeRawString("updated_at"));Instant.parse(updated)
        val deleted=payload.financeRawString("deleted_at")?.also{Instant.parse(it)}
        return CloudRecord(CloudEntity.INVESTMENT_ASSET.table,context.id,context.owner.value,payload,updated,deleted,version)
            .also{InvestmentAssetRecord.fromCloudRecord(it);if(allowLocal)localAssetImagePublication(it)}
    }
    private suspend fun Call.awaitText():String = suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,error:IOException) {if(!continuation.isCancelled)continuation.resumeWithException(error)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val body=response.use {
                        if(!it.isSuccessful)throw SupabaseHttpException(it.code,"")
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Asset response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Asset response exceeds limit")
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
        catch(network:IOException){throw IOException("Investment asset network request failed")}
        catch(invalid:Exception){throw IllegalArgumentException("Invalid investment asset request or response")}
    companion object {
        private const val MAX_BODY=2_000_000
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
        private val DELETE_KEYS=setOf("id","user_id","updated_at","deleted_at","sync_version","last_modified_by_device_id")
    }
}
