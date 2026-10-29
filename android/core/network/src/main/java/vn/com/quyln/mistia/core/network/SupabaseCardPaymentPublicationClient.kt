package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.time.ZoneId
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import vn.com.quyln.mistia.core.model.*

/** Paid card markers require a closed compared financial proof; no generic paid-cycle gate. */
class SupabaseCardPaymentPublicationClient(private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean):CardPaymentPublicationRemote {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    override suspend fun publish(source:CardPaymentPublicationSnapshot,queued:QueuedMutation,
        observed:CardPaymentPublicationObservation,zone:ZoneId,accessToken:String):CloudRecord? {
        val caller=currentCoroutineContext();caller.ensureActive()
        check(config.isConfigured && writesEnabled()) {"Card payment writes disabled"}
        val captured=currentSession()
        fun current() {
            caller.ensureActive()
            if(captured==null || currentSession()!=captured || captured.userId!=source.owner || captured.accessToken!=accessToken ||
                accessToken.isBlank() || !writesEnabled())throw CancellationException("Card payment authorization changed")
            caller.ensureActive()
        }
        current()
        val base=config.projectUrl.toHttpUrl()
        require(base.isHttps && base.username.isEmpty() && base.password.isEmpty() && base.query==null && base.fragment==null)
        val decision=planCardPaymentPublication(source,queued,observed,zone)
        require(decision is CardPaymentPublicationDecision.Write) {"No card payment write authority"}
        val url=base.newBuilder().addPathSegments("rest/v1/rpc/mutate_card_paid_cycle").build()
        val body=buildJsonObject {
            put("p_cycle",decision.payload)
            put("p_expected_version",decision.expectedVersion ?: 0L)
            put("p_expected_presence",decision.expectedVersion!=null)
            put("p_expected_ledger",JsonObject(observed.ledger.toSortedMap().mapValues{it.value?.payload ?: JsonNull}))
            put("p_expected_wallets",JsonObject(observed.wallets.toSortedMap().mapValues{it.value?.payload ?: JsonNull}))
            put("p_expected_cycles",JsonArray(observed.cycles.sortedBy{it.id}.map{it.payload}))
        }
        val serialized=body.toString();require(serialized.toByteArray(Charsets.UTF_8).size<=MAX_BODY)
        val request=Request.Builder().url(url).header("Authorization","Bearer $accessToken").header("apikey",config.anonKey)
            .header("Content-Type","application/json").header("Prefer","return=representation")
            .post(serialized.toRequestBody("application/json; charset=utf-8".toMediaType())).build()
        current()
        try {
            val raw=http.newCall(request).awaitText();current()
            val p=Json.parseToJsonElement(raw).jsonObject
            val result=CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table,requireNotNull(p.financeRawString("id")),source.owner.value,p,
                p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
            requireCardPaymentPublicationResult(source,queued,observed,zone,result)
            current();return result
        }catch(error:Exception) {
            current()
            when(error) {
                is CancellationException->throw error
                is SupabaseHttpException->throw SupabaseHttpException(error.statusCode,"",error.serviceCode)
                else->throw IOException("Card payment result unavailable")
            }
        }
    }
    private suspend fun Call.awaitText():String=suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,error:IOException) {if(!continuation.isCancelled)continuation.resumeWithException(error)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val raw=response.use {
                        if(!it.isSuccessful) {
                            val code=if(it.code==400)runCatching {
                                val bytes=it.peekBody(65_537).bytes()
                                if(bytes.size>65_536)null else {
                                    val error=Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
                                    when(error.financeRawString("code")) {
                                        "P0001"->error.financeRawString("message")?.takeIf{it in CARD_PAYMENT_PUBLICATION_RETRY_CODES}
                                        "40P01","40001"->"card_payment_retry_transaction"
                                        else->null
                                    }
                                }
                            }.getOrNull() else null
                            throw SupabaseHttpException(it.code,"",code)
                        }
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Card response too large")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1));if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Card response too large")
                                if(count>0)output.write(buffer,0,count)
                            };output.toString(Charsets.UTF_8.name())
                        }
                    }
                    if(!continuation.isCancelled)continuation.resumeWith(Result.success(raw))
                }catch(error:IOException){if(!continuation.isCancelled)continuation.resumeWithException(error)}
            }
        })
    }
    companion object {private const val MAX_BODY=1_048_576}
}

val CARD_PAYMENT_PUBLICATION_RETRY_CODES=setOf(
    "card_payment_version_conflict","card_payment_ledger_changed",
    "card_payment_wallet_changed","card_payment_membership_changed","card_payment_retry_transaction")
