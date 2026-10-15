package vn.com.quyln.mistia.core.model

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import kotlinx.serialization.json.*

data class InstallmentDeletionChunk(val index: Int, val bytes: ByteArray)
data class InstallmentDeletionBlob(val header: JsonObject, val chunks: List<InstallmentDeletionChunk>)

/** Bound each SQLite value while keeping the causal document exact and integrity checked. */
object InstallmentDeletionStorage {
    const val CHUNK_BYTES = 64 * 1024
    fun pack(batch: InstallmentDeletionBatch): InstallmentDeletionBlob {
        val bytes = batch.toJson().toString().toByteArray(Charsets.UTF_8)
        val chunks = (bytes.indices step CHUNK_BYTES).mapIndexed { index, start ->
            InstallmentDeletionChunk(index, bytes.copyOfRange(start, minOf(start.toLong() + CHUNK_BYTES, bytes.size.toLong()).toInt()))
        }
        val header = buildJsonObject {
            put("format_version", 1); put("byte_count", bytes.size); put("chunk_count", chunks.size); put("sha256", digest(bytes))
        }
        return InstallmentDeletionBlob(header, chunks)
    }
    fun unpack(owner: UserId, planId: String, batchId: String, blob: InstallmentDeletionBlob): InstallmentDeletionBatch {
        val header = blob.header
        require(header.number("format_version") == 1L)
        val count = header.number("chunk_count"); val size = header.number("byte_count")
        require(size in 1..Int.MAX_VALUE.toLong() && count == (size + CHUNK_BYTES - 1) / CHUNK_BYTES)
        val hash = header.getValue("sha256").jsonPrimitive.also { require(it.isString) }.content
        require(Regex("[0-9a-f]{64}").matches(hash))
        val chunks = blob.chunks.sortedBy(InstallmentDeletionChunk::index)
        require(chunks.size.toLong() == count)
        chunks.forEachIndexed { index, chunk ->
            require(chunk.index == index)
            require(chunk.bytes.size == minOf(CHUNK_BYTES.toLong(), size - index.toLong() * CHUNK_BYTES).toInt())
        }
        require(chunks.sumOf { it.bytes.size.toLong() } == size)
        val bytes = ByteArray(size.toInt())
        chunks.forEach { it.bytes.copyInto(bytes, it.index * CHUNK_BYTES) }
        require(digest(bytes) == hash) { "Invalid deletion batch storage digest" }
        val decoded = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
        return InstallmentDeletionBatch.fromJson(owner, planId, Json.parseToJsonElement(decoded).jsonObject).also { require(it.batchId == batchId) }
    }
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun JsonObject.number(key: String) = getValue(key).jsonPrimitive.also { require(!it.isString) }.longOrNull ?: throw IllegalArgumentException("Expected Int64")
}
