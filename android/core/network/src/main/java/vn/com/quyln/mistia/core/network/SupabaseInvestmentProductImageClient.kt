package vn.com.quyln.mistia.core.network

import java.io.IOException
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import vn.com.quyln.mistia.core.model.AuthSession
import vn.com.quyln.mistia.core.model.InvestmentProductImagePath
import vn.com.quyln.mistia.core.model.InvestmentProductImageRemote
import vn.com.quyln.mistia.core.model.UserId

/** Authenticated private Storage access, without cache or metadata publication side effects. */
class SupabaseInvestmentProductImageClient(
    private val config: SupabaseConfig,
    client: OkHttpClient,
    private val currentSession: () -> AuthSession?,
    // The composition root must supply the conjunction of global and investment write gates.
    private val writesEnabled: () -> Boolean,
) : InvestmentProductImageRemote {
    // A private object request must never follow a redirect to a public or signed URL.
    private val storageClient = client.newBuilder().followRedirects(false).followSslRedirects(false).build()

    override suspend fun download(
        owner: UserId,
        assetId: String,
        path: String,
        isCurrent: () -> Boolean,
    ): Result<ByteArray?> = storageResult {
        val context = capture(owner, assetId, path, isWrite = false, isCurrent)
        execute(context, "GET").let { response ->
            ensureCurrent(context)
            val bytes = when {
                response.isSuccessful -> checkNotNull(response.bytes)
                response.code == 404 -> null
                else -> throw SupabaseHttpException(response.code,"")
            }
            ensureCurrent(context)
            bytes
        }
    }

    override suspend fun upload(
        owner: UserId,
        assetId: String,
        path: String,
        bytes: ByteArray,
        isCurrent: () -> Boolean,
    ): Result<Unit> = storageResult {
        val context = capture(owner, assetId, path, isWrite = true, isCurrent)
        val immutableBytes = bytes.copyOf()
        val status = execute(context, "POST", immutableBytes).let { response ->
            ensureCurrent(context)
            response.code
        }
        when (status) {
            in 200..299 -> Unit
            400, 409 -> {
                // Even the read used to verify an upload collision requires the write gate.
                val matches = execute(context, "GET").let { response ->
                    ensureCurrent(context)
                    val same = response.isSuccessful && checkNotNull(response.bytes).contentEquals(immutableBytes)
                    ensureCurrent(context)
                    same
                }
                if (!matches) throw SupabaseHttpException(status,"")
            }
            else -> throw SupabaseHttpException(status,"")
        }
        ensureCurrent(context)
    }

    override suspend fun delete(
        owner: UserId,
        assetId: String,
        path: String,
        isCurrent: () -> Boolean,
    ): Result<Unit> = storageResult {
        val context = capture(owner, assetId, path, isWrite = true, isCurrent)
        execute(context, "DELETE").let { response ->
            ensureCurrent(context)
            if (!response.isSuccessful && response.code != 404) throw SupabaseHttpException(response.code,"")
        }
        ensureCurrent(context)
    }

    private suspend fun capture(
        owner: UserId,
        assetId: String,
        path: String,
        isWrite: Boolean,
        isCurrent: () -> Boolean,
    ): RequestContext {
        currentCoroutineContext().ensureActive()
        check(config.isConfigured) { "Private product image storage is not configured" }
        InvestmentProductImagePath.parse(owner, assetId, path)
        val session = checkNotNull(currentSession()) { "Private product image session is unavailable" }
        check(session.userId == owner && session.accessToken.isNotBlank()) { "Private product image session does not match owner" }
        val base = config.projectUrl.toHttpUrl()
        check(base.scheme == "https" && base.username.isEmpty() && base.password.isEmpty() && base.query == null && base.fragment == null) {
            "Invalid private product image storage configuration"
        }
        val url = base.newBuilder().addPathSegments("storage/v1/object/investment-product-images")
            .apply { path.split('/').forEach { addPathSegment(it) } }.build()
        return RequestContext(session, url, isWrite, isCurrent).also { ensureCurrent(it) }
    }

    private suspend fun ensureCurrent(context: RequestContext) {
        currentCoroutineContext().ensureActive()
        check(context.isCurrent() && currentSession() == context.session) { "Private product image request is no longer current" }
        check(!context.isWrite || writesEnabled()) { "Private product image writes are disabled" }
    }

    private suspend fun execute(context: RequestContext, method: String, bytes: ByteArray? = null): StorageResponse {
        ensureCurrent(context)
        val request = Request.Builder().url(context.url)
            .header("apikey", config.anonKey)
            .header("Authorization", "Bearer ${context.session.accessToken}")
            .apply {
                when (method) {
                    "GET" -> get()
                    "POST" -> header("x-upsert", "false").post(checkNotNull(bytes).toRequestBody(JPEG_MEDIA_TYPE))
                    "DELETE" -> delete()
                    else -> error("Unsupported private product image operation")
                }
            }.build()
        ensureCurrent(context)
        return storageClient.newCall(request).await(readBytes = method == "GET")
    }

    private suspend fun <T> storageResult(operation: suspend () -> T): Result<T> = try {
        Result.success(operation())
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        // HTTP response bodies, transport errors, and their URLs may contain private data.
        Result.failure(when(error) {
            is SupabaseHttpException->SupabaseHttpException(error.statusCode,"")
            is StorageRequestException->error
            else->StorageRequestException()
        })
    }

    private suspend fun Call.await(readBytes: Boolean): StorageResponse = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (!continuation.isCancelled) continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    // Consume and close on OkHttp's callback thread. Cancellation remains wired to
                    // the call until the complete private body has been read, including slow bodies.
                    val result = response.use {
                        StorageResponse(it.code, if (readBytes && it.isSuccessful) readPrivateBody(it.body) else null)
                    }
                    if (!continuation.isCancelled) continuation.resumeWith(Result.success(result))
                } catch (error: IOException) {
                    if (!continuation.isCancelled) continuation.resumeWithException(error)
                }
            }
        })
    }

    private fun readPrivateBody(body:okhttp3.ResponseBody):ByteArray {
        val limit=5_242_880
        if(body.contentLength()>limit)throw IOException("Private image exceeds storage limit")
        return body.byteStream().use{input->
            val output=java.io.ByteArrayOutputStream(8192)
            val buffer=ByteArray(8192)
            while(true) {
                val count=input.read(buffer,0,minOf(buffer.size,limit-output.size()+1))
                if(count<0)break
                if(count>limit-output.size())throw IOException("Private image exceeds storage limit")
                if(count>0)output.write(buffer,0,count)
            }
            output.toByteArray()
        }
    }

    private data class StorageResponse(val code: Int, val bytes: ByteArray?) {
        val isSuccessful: Boolean get() = code in 200..299
    }

    private data class RequestContext(
        val session: AuthSession,
        val url: HttpUrl,
        val isWrite: Boolean,
        val isCurrent: () -> Boolean,
    )

    private class StorageRequestException(statusCode: Int? = null) : IOException(
        if (statusCode == null) "Private product image request failed" else "Private product image request failed ($statusCode)",
    )

    private companion object {
        val JPEG_MEDIA_TYPE = "image/jpeg".toMediaType()
    }
}
