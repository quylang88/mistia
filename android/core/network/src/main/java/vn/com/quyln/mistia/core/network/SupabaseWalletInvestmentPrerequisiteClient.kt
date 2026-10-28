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

/** Bound ordinary-wallet metadata preparation; never a financial or root-wallet writer. */
class SupabaseWalletInvestmentPrerequisiteClient(private val config:SupabaseConfig,client:OkHttpClient,
    private val currentSession:()->AuthSession?,private val writesEnabled:()->Boolean):WalletInvestmentPrerequisiteRemote {
    private val http=client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    private data class Context(val owner:UserId,val id:String,val session:AuthSession,val base:HttpUrl,val caller:CoroutineContext,val write:Boolean)
    override suspend fun fetchWallet(owner:UserId,id:String,accessToken:String):CloudRecord?=safely {
        val c=capture(owner,id,accessToken,false);fetch(c)
    }
    override suspend fun publishActive(owner:UserId,prepared:WalletInvestmentPrerequisitePreparation,accessToken:String):CloudRecord?=safely {
        val c=capture(owner,prepared.id,accessToken,true);require(prepared.source.owner==owner)
        val base=walletInvestmentPrerequisiteWriteBase(prepared)
        val observed=fetch(c);checkCurrent(c)
        if(observed!=null) {
            // Recover only our journal-proven own reply; never adopt a create race.
            if(runCatching{planWalletInvestmentPrerequisiteRebase(prepared.preparedSource,prepared.id,observed,prepared.preparedSource)}.getOrNull()!=null)
                return@safely observed.also{checkCurrent(c)}
            if(base==0L || observed.syncVersion!=base || observed.deletedAt!=null || observed.payload.financeRawArchived()!=false ||
                observed.payload["archived_at"]!=JsonNull || observed.payload.financeRawString("currency_code")!=prepared.proposal.payload.financeRawString("currency_code") ||
                observed.payload.financeRawString("kind_raw_value")!=prepared.proposal.payload.financeRawString("kind_raw_value"))return@safely null.also{checkCurrent(c)}
        } else if(base>0L)return@safely null.also{checkCurrent(c)}
        val url=c.base.newBuilder().addPathSegments("rest/v1/ledger_wallets").apply {
            if(base>0L){addQueryParameter("id","eq.${c.id}");addQueryParameter("user_id","eq.${owner.value}");addQueryParameter("sync_version","eq.$base")}
        }.build()
        val body=prepared.proposal.payload.toString();require(body.toByteArray(Charsets.UTF_8).size<=MAX_BODY)
        val builder=authorized(c,url);val payload=body.toRequestBody(JSON_TYPE)
        val request=if(base==0L)builder.post(payload).build() else builder.patch(payload).build()
        val saved=try {
            val rows=execute(c,request);require(rows.size<=1)
            rows.singleOrNull()?.let{p->decode(c,p).also{row->
                requireNotNull(planWalletInvestmentPrerequisiteRebase(prepared.preparedSource,prepared.id,row,prepared.preparedSource))
            }}
        }catch(cancelled:CancellationException){throw cancelled}
        catch(error:SupabaseHttpException){throw error}
        catch(error:IOException){throw error}
        catch(error:Exception){throw IOException("Wallet prerequisite response unavailable")}
        checkCurrent(c);saved
    }
    private suspend fun capture(owner:UserId,id:String,token:String,write:Boolean):Context {
        val caller=currentCoroutineContext();caller.ensureActive()
        require(financeRawUuid(owner.value)==owner.value && financeRawUuid(id)==id && id!=investmentSystemWalletId(owner))
        check(config.isConfigured){"Wallet prerequisite service unavailable"}
        if(write)check(writesEnabled()){"Wallet prerequisite writes disabled"}
        val session=currentSession()
        if(session==null || session.userId!=owner || session.accessToken!=token || token.isBlank())throw CancellationException("Wallet prerequisite session changed")
        val url=config.projectUrl.toHttpUrl();require(url.scheme=="https" && url.username.isEmpty() && url.password.isEmpty() && url.query==null && url.fragment==null)
        return Context(owner,id,session,url,caller,write).also(::checkCurrent)
    }
    private fun checkCurrent(c:Context) {
        c.caller.ensureActive()
        if(currentSession()!=c.session || c.write && !writesEnabled())throw CancellationException("Wallet prerequisite authorization changed")
        c.caller.ensureActive()
    }
    private fun authorized(c:Context,url:HttpUrl):Request.Builder {
        checkCurrent(c)
        return Request.Builder().url(url).header("Authorization","Bearer ${c.session.accessToken}").header("apikey",config.anonKey)
            .header("Content-Type","application/json").header("Prefer","return=representation")
    }
    private suspend fun fetch(c:Context):CloudRecord? {
        val url=c.base.newBuilder().addPathSegments("rest/v1/ledger_wallets").addQueryParameter("id","eq.${c.id}")
            .addQueryParameter("user_id","eq.${c.owner.value}").addQueryParameter("limit","2").build()
        val rows=execute(c,authorized(c,url).get().build());require(rows.size<=1)
        return rows.singleOrNull()?.let{decode(c,it)}.also{checkCurrent(c)}
    }
    private fun decode(c:Context,p:JsonObject):CloudRecord {
        require(p.keys.none{it.startsWith("_mistia_android_")})
        val row=CloudRecord(CloudEntity.LEDGER_WALLET.table,c.id,c.owner.value,p,p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
        require(row.financeRawIdentity(c.owner,CloudEntity.LEDGER_WALLET,true) && p.financeRawString("id")==c.id && p.financeRawString("user_id")==c.owner.value &&
            row.syncVersion>0 && row.financeRawDeleted(true)!=null && p.financeRawArchived()!=null)
        for(key in listOf("created_at","updated_at"))Instant.parse(requireNotNull(p.financeRawString(key)))
        row.deletedAt?.let(Instant::parse);p.financeRawString("archived_at")?.let(Instant::parse)
        p.financeRawString("last_modified_by_device_id")?.let{require(financeRawUuid(it)==it)}
        val wallet=LedgerWalletRecord.fromCloudRecord(row)
        require(wallet.kind !in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) && wallet.systemPurposeRawValue==null && wallet.investmentLinkedWalletId==null &&
            wallet.currencyCode.financeReportingCode()==wallet.currencyCode && java.util.Currency.getInstance(wallet.currencyCode).defaultFractionDigits>=0)
        return row
    }
    private suspend fun execute(c:Context,request:Request):List<JsonObject> {
        checkCurrent(c)
        val text=try{http.newCall(request).awaitText()}catch(error:Exception){checkCurrent(c);throw error}
        checkCurrent(c);if(text.isBlank())throw IOException("Wallet prerequisite response unavailable")
        val rows=Json.parseToJsonElement(text).jsonArray;require(rows.size<=2)
        return rows.map{it.jsonObject}.also{checkCurrent(c)}
    }
    private suspend fun Call.awaitText():String=suspendCancellableCoroutine{continuation->
        continuation.invokeOnCancellation{cancel()}
        enqueue(object:Callback {
            override fun onFailure(call:Call,e:IOException){if(!continuation.isCancelled)continuation.resumeWithException(e)}
            override fun onResponse(call:Call,response:Response) {
                try {
                    val text=response.use {
                        if(!it.isSuccessful)throw SupabaseHttpException(it.code,"")
                        if(it.body.contentLength()>MAX_BODY)throw IOException("Wallet prerequisite response exceeds limit")
                        it.body.byteStream().use{input->
                            val output=java.io.ByteArrayOutputStream(4096);val buffer=ByteArray(8192)
                            while(true) {
                                val count=input.read(buffer,0,minOf(buffer.size,MAX_BODY-output.size()+1))
                                if(count<0)break
                                if(count>MAX_BODY-output.size())throw IOException("Wallet prerequisite response exceeds limit")
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
        catch(http:SupabaseHttpException){throw SupabaseHttpException(http.statusCode,"")}
        catch(error:IOException){throw IOException("Wallet prerequisite network request failed")}
        catch(error:IllegalStateException){throw IllegalStateException("Wallet prerequisite service unavailable")}
        catch(error:Exception){throw IllegalArgumentException("Invalid wallet prerequisite request or response")}
    companion object {
        private const val MAX_BODY=1_048_576
        private val JSON_TYPE="application/json; charset=utf-8".toMediaType()
    }
}
